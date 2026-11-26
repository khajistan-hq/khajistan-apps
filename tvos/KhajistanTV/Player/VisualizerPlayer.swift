import AVFoundation
import Combine
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
    @ObservationIgnored private var pieceId: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Bumped by each run, so a run SwiftUI has cancelled cannot tear down or attach over the next.
    @ObservationIgnored private var generation = 0
    /// The list, read once per launch; a failed read is asked again next time.
    private static var rows: [VisualizerPiece]?

    func run(reverent: Bool, auth: AuthStore) async {
        generation += 1
        let gen = generation
        guard let rows = await Self.load(previewPassword: auth.previewPassword) else { return }
        while !Task.isCancelled, gen == generation {
            guard let pick = Visualizer.pick(rows, reverent: reverent, now: Date()) else { break }
            if pick.piece.id != pieceId { await play(pick.piece, auth: auth, gen: gen) }
            try? await Task.sleep(for: .seconds(max(1, pick.until.timeIntervalSinceNow)))
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
        guard let url = await Self.carrier(for: piece, auth: auth), !Task.isCancelled, gen == generation else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        for await status in item.publisher(for: \.status).values {
            if status == .failed || Task.isCancelled || gen != generation { return }
            if status == .readyToPlay { break }
        }
        let duration = item.duration.seconds
        let at = Visualizer.offset(of: piece, at: Date(), duration: duration.isFinite ? duration : nil)
        _ = await player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
        guard !Task.isCancelled, gen == generation, player.currentItem === item else { return }
        player.play()
        ready = true
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
