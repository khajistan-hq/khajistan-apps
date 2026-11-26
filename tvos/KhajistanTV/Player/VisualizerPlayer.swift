import AVFoundation
import Foundation
import Observation

// Shared with the iPhone app (ios/Khajistan/Player/VisualizerPlayer.swift is a link to this file).
// It reads AuthStore's isSignedIn, previewPassword and validAccessToken(), which both apps' own
// AuthStore carry.

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
            let seen = UserDefaults.standard.stringArray(forKey: Visualizer.seenKey) ?? []
            guard let pick = Visualizer.draw(rows, reverent: reverent, seen: seen,
                                             roll: Double.random(in: 0..<1), startRoll: Double.random(in: 0..<1)) else {
                problem = "no picture for this kind of channel yet"
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            await play(pick.piece, at: pick.offset, auth: auth, gen: gen)
            if ready { UserDefaults.standard.set(pick.seen, forKey: Visualizer.seenKey) }
            let wait = ready ? max(5, pick.play) : 60
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

    private func play(_ piece: VisualizerPiece, at start: TimeInterval, auth: AuthStore, gen: Int) async {
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
        step = "joining the picture"
        let at = start
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
