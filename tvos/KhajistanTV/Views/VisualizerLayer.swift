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
                // Two players (owner, 2026-11-26: "there should be seamless transition between the visualiser
                // files"): the next piece opens on the one behind and fades in on top; the one it replaces stays
                // up underneath until the fade is over, so the ground never shows between pieces.
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        PlayerLayerView(player: picture.players[i], gravity: .resizeAspectFill)
                            .opacity(picture.ready && (picture.front == i || picture.outgoing == i) ? 1 : 0)
                            .zIndex(picture.front == i ? 1 : 0)
                    }
                }
                .animation(.linear(duration: VisualizerPlayer.fade), value: picture.front)
                .ignoresSafeArea()
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

/// The muted picture: draws a piece from the shuffle bag, asks tv-play for it with the viewer's
/// session (PicsVidsStore.playableURL's route), joins it at a random point, and fades the next piece
/// in over it before it ends, or after half an hour. Torn down when its task ends.
@MainActor @Observable
final class VisualizerPlayer {
    @ObservationIgnored let players: [AVPlayer] = (0..<2).map { _ in
        let player = AVPlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        // The next piece is drawn before this one ends; only if it fails does this one reach its end and loop.
        player.actionAtItemEnd = .pause
        return player
    }
    /// Seconds the next piece takes to fade in over the last.
    static let fade = 1.2
    /// Seconds before a piece ends that the next one starts to load.
    static let lead = 12.0
    /// The player on screen, and the one it is fading in over (nil once the fade is over).
    private(set) var front = 0
    private(set) var outgoing: Int?
    @ObservationIgnored private var loops: [Task<Void, Never>?] = [nil, nil]
    /// Whether the piece on screen was drawn for a devotional programme.
    @ObservationIgnored private var shownReverent: Bool?
    /// The picture is on its first frame, at the clock point.
    private(set) var ready = false
    /// Why the picture is not up, in plain words; nil while it loads or plays.
    private(set) var problem: String?
    /// The step under way, shown while the picture is not up.
    private(set) var step = "starting"
    /// Bumped by each run, so a run SwiftUI has cancelled cannot tear down or attach over the next.
    @ObservationIgnored private var generation = 0
    /// The list, read once per launch; a failed read is asked again next time.
    private static var rows: [VisualizerPiece]?

    func run(reverent: Bool, auth: AuthStore) async {
        generation += 1
        let gen = generation
        // A devotional programme never keeps an After Hours picture, not even while Nature loads (and the other
        // way round): a change of kind clears the picture at once. Only a sign-in change keeps it up.
        if ready, shownReverent != reverent { stop() }
        while !Task.isCancelled, gen == generation {
            // A failed step is tried again in a minute rather than waiting for a mode change.
            step = "reading the list of pictures"
            guard let rows = await Self.load(previewPassword: auth.previewPassword), !rows.isEmpty else {
                problem = "the list of pictures could not be read"
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            let seen = UserDefaults.standard.stringArray(forKey: Visualizer.seenKey) ?? []
            guard let pick = Visualizer.draw(rows, reverent: reverent, seen: seen,
                                             roll: Double.random(in: 0..<1), startRoll: Double.random(in: 0..<1)) else {
                problem = "no picture for this kind of channel yet"
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            let shown = await play(pick.piece, at: pick.offset, auth: auth, gen: gen)
            // A piece that would not open counts as seen too, so the bag moves past it; a cancelled run counts nothing.
            if !Task.isCancelled, gen == generation {
                UserDefaults.standard.set(pick.seen, forKey: Visualizer.seenKey)
                if shown { shownReverent = reverent }
            }
            // The next piece starts loading `lead` seconds before this one ends, so it is up before the end.
            let wait = shown ? max(5, pick.play - Self.lead) : (ready ? 30 : 60)
            try? await Task.sleep(for: .seconds(wait))
        }
        // No stop() here: when the picture should go, the view's task stops it (`guard play`) or onDisappear does,
        // and a change of kind stops it at the top of the next run. A sign-in change keeps the picture up.
    }

    func stop() {
        for i in players.indices { clear(i) }
        outgoing = nil
        ready = false
        shownReverent = nil
    }

    private func clear(_ i: Int) {
        loops[i]?.cancel()
        loops[i] = nil
        players[i].pause()
        players[i].replaceCurrentItem(with: nil)
    }

    /// Opens `piece` on the player behind and fades it in over the one on screen once it is drawing. True once it
    /// is showing; on a failure the piece on screen, if any, stays up.
    private func play(_ piece: VisualizerPiece, at start: TimeInterval, auth: AuthStore, gen: Int) async -> Bool {
        // A fade still under way (a restarted run can arrive inside one) is let finish, never cut short.
        while outgoing != nil {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled || gen != generation { return false }
        }
        let back = ready ? 1 - front : front
        clear(back)
        let current = { !Task.isCancelled && gen == self.generation }
        func fail(_ why: String) -> Bool {
            if current() { clear(back); if !ready { problem = why } }
            return false
        }
        guard auth.isSignedIn else { return fail("sign in to see it") }
        if !ready { step = "asking for the picture link" }
        guard let url = await Self.carrier(for: piece, auth: auth) else { return fail("the picture link was refused") }
        guard current() else { return false }
        if !ready { step = "opening the picture" }
        let player = players[back]
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()   // muted; loading starts now rather than waiting on a status nobody asked for
        let deadline = Date().addingTimeInterval(30)
        while item.status != .readyToPlay {
            guard current(), player.currentItem === item else { return false }
            if item.status == .failed {
                return fail("the picture would not play (\(item.error?.localizedDescription ?? "unknown error"))")
            }
            if Date() > deadline { return fail("the picture did not open within 30 seconds") }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if !ready { step = "joining the picture" }
        _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        guard current(), player.currentItem === item else { return false }
        player.play()
        // Faded in only once frames are coming: ready-to-play and a finished seek do not yet mean a picture.
        let drawing = Date().addingTimeInterval(15)
        while player.timeControlStatus != .playing {
            guard current(), player.currentItem === item else { return false }
            if Date() > drawing { return fail("the picture did not start") }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard current(), player.currentItem === item else { return false }
        // If its successor fails, a piece that runs out goes round again rather than standing still.
        loops[back] = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                guard let self, !Task.isCancelled else { return }
                guard self.front == back, self.outgoing == nil else { continue }
                await player.seek(to: .zero)
                player.play()
            }
        }
        problem = nil
        if ready, back != front {
            let old = front
            outgoing = old
            front = back
            // Not tied to this task: a restart during the fade must not drop the old piece before the fade is over.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.fade + 0.2))
                guard let self, self.outgoing == old else { return }
                self.outgoing = nil
                if old != self.front { self.clear(old) }
            }
        } else {
            front = back
            ready = true
        }
        return true
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
