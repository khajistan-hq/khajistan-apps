import AVFoundation
import Combine
import SwiftUI

/// What a sound channel shows in place of a picture: the dancer, a Khajistan visualizer, or the
/// channel's name alone, as the viewer has chosen (Core/Visualizer.swift). The visualizer is an
/// After Hours picture on a muted AVPlayer of its own, under the channel's sound, so it never
/// touches the signal: a failure only means the dancer (in Dancer's place) or the plain ground.
///
/// `eligible` false draws exactly what was here before the visualizers: the DancerLayer.
struct SoundStage<Behind: View>: View {
    let controller: PlayerController
    /// Sound with no picture, where the dancer could be: radio, or a sound-only programme.
    let eligible: Bool
    let reverent: Bool
    @ViewBuilder let behind: () -> Behind

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VisualizerMode.key) private var stored = VisualizerMode.khajistan.rawValue
    @AppStorage(VisualizerMode.natureKey) private var storedNature = VisualizerMode.nature.rawValue
    @State private var picture = VisualizerPlayer()

    private struct Want: Equatable { let play: Bool; let reverent: Bool; let signedIn: Bool }

    var body: some View {
        let mode = VisualizerMode.current(reverent: reverent, stored: stored, storedNature: storedNature)
        let play = eligible && !reduceMotion && mode.playsPicture && controller.state == .playing
        let dancer = !eligible || (mode != .off && !(play && picture.ready) && !reverent)
        ZStack {
            if dancer {
                // The dancer as before; in Khajistan mode he stands in until the picture is up.
                DancerLayer(controller: controller, behind: behind)
            }
            if play {
                // Attached from the start, invisible until ready: on Apple TV an AVPlayer with no layer and
                // no play() can sit at "unknown" for good (measured 2026-11-26 on the owner's Apple TV HD:
                // stuck at "opening the picture" on a plain 960x540 H.264 file Channel 1 plays fine).
                PlayerLayerView(player: picture.player, gravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .opacity(picture.ready ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if play && picture.ready {
                // The name moves to the top right, as it does for the dancer.
                behind()
                    .scaleEffect(0.45, anchor: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 64)
                    .padding(.trailing, KJLayout.inset)
            } else if !dancer {
                behind().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // When the picture cannot come, one line says why (owner, 2026-11-26: "khajistan visualizer
            // isnt showing on my apple tv"); the dancer stands in meanwhile.
            if mode.playsPicture, !picture.ready {
                // Until the picture is up, the step it is on, so a hang shows as clearly as a failure.
                let step = !play ? (controller.state == .playing ? "off for this channel" : "waiting for the channel to play")
                    : (picture.problem ?? picture.step)
                Text("Khajistan visualizer: \(step)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, KJLayout.inset)
                    .padding(.bottom, 40)
                    .allowsHitTesting(false)
            }
        }
        .task(id: Want(play: play, reverent: reverent, signedIn: model.auth.isSignedIn)) {
            guard play else { return picture.stop() }
            await picture.run(reverent: reverent, auth: model.auth)
        }
        .onDisappear { picture.stop() }
    }
}

/// The muted picture: picks the piece the clock has on, asks tv-play for it with the viewer's
/// session (PicsVidsStore.playableURL's route), joins it at the clock point, loops it, and moves
/// to the next piece at the half hour. Torn down when its task ends.
@MainActor @Observable
final class VisualizerPlayer {
    @ObservationIgnored let player: AVPlayer = {
        let player = AVPlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .none
        return player
    }()
    /// The picture is on its first frame, at the clock point.
    private(set) var ready = false
    /// Why the picture is not up, in plain words; nil while it loads or plays.
    private(set) var problem: String?
    /// The step under way, shown while the picture is not up.
    private(set) var step = "starting"
    @ObservationIgnored private var pieceId: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Bumped by each run, so a run SwiftUI has cancelled cannot tear down or attach over the next.
    @ObservationIgnored private var generation = 0
    /// The list, read once per launch; a failed read is asked again next time.
    private static var rows: [VisualizerPiece]?

    func run(reverent: Bool, auth: AuthStore) async {
        generation += 1
        let gen = generation
        while !Task.isCancelled, gen == generation {
            // A failed step is tried again in a minute rather than waiting for a mode change.
            step = "reading the list of pictures"
            guard let rows = await Self.load(previewPassword: auth.previewPassword), !rows.isEmpty else {
                problem = "the list of pictures could not be read"
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            guard let pick = Visualizer.pick(rows, reverent: reverent, now: Date()) else {
                problem = "no picture for this kind of channel yet"
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            if pick.piece.id != pieceId || !ready { await play(pick.piece, auth: auth, gen: gen) }
            let wait = ready ? max(1, pick.until.timeIntervalSinceNow) : 60
            try? await Task.sleep(for: .seconds(wait))
        }
        if gen == generation { stop() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        pieceId = nil
        ready = false
    }

    private func play(_ piece: VisualizerPiece, auth: AuthStore, gen: Int) async {
        stop()
        pieceId = piece.id
        guard auth.isSignedIn else { problem = "sign in to see it"; return }
        step = "asking for the picture link"
        guard let url = await Self.carrier(for: piece, auth: auth) else { problem = "the picture link was refused"; return }
        step = "opening the picture"
        guard !Task.isCancelled, gen == generation else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()   // muted; loading starts now rather than waiting on a status nobody asked for
        let deadline = Date().addingTimeInterval(30)
        while item.status != .readyToPlay {
            if item.status == .failed {
                problem = "the picture would not play (\(item.error?.localizedDescription ?? "unknown error"))"
                return
            }
            if Task.isCancelled || gen != generation { return }
            if Date() > deadline { problem = "the picture did not open within 30 seconds"; player.pause(); return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        step = "joining the picture at the clock point"
        let duration = item.duration.seconds
        let at = Visualizer.offset(of: piece, at: Date(), duration: duration.isFinite ? duration : nil)
        _ = await player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
        guard !Task.isCancelled, gen == generation, player.currentItem === item else { return }
        player.play()
        ready = true
        problem = nil
        let player = player
        loop = Task {
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                if Task.isCancelled { return }
                await player.seek(to: .zero)
                player.play()
            }
        }
    }

    /// The signed play address, or nil: not signed in, or tv-play said no.
    private static func carrier(for piece: VisualizerPiece, auth: AuthStore) async -> URL? {
        guard auth.isSignedIn, let token = try? await auth.validAccessToken(),
              let route = Transmission.route(for: piece.play_url),
              let request = Transmission.request(for: route, accessToken: token),
              let (data, response) = try? await SupabaseRoute.data(for: request, session: .shared, delegate: RefuseRedirects()),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? Transmission.carrier(from: data, route: route)
    }

    /// The site's file, without the preview password first and with it on a 401 (HouseSongs).
    private static func load(previewPassword: String?) async -> [VisualizerPiece]? {
        if let rows { return rows }
        guard let url = KJURL.sitePath(Visualizer.path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        var reply = try? await URLSession.shared.data(for: request)
        if (reply?.1 as? HTTPURLResponse)?.statusCode == 401, let previewPassword {
            request.setValue(Transmission.basicAuthorization(user: KJConfig.previewUser, password: previewPassword),
                             forHTTPHeaderField: "Authorization")
            reply = try? await URLSession.shared.data(for: request)
        }
        guard let (data, response) = reply, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let read = Visualizer.rows(from: data)
        if !read.isEmpty { rows = read }
        return read
    }
}
