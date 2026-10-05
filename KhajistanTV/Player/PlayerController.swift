import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// One AVPlayer and what the viewer needs to know about it. Every tuning gets a generation
/// number; a callback that carries an older one belongs to a signal already left behind.
@MainActor @Observable
final class PlayerController {
    enum State: Equatable {
        case idle, tuning, playing, paused, failed(String)
    }

    let player = AVPlayer()
    var state: State = .idle
    @ObservationIgnored var onEnded: (() -> Void)?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.syncWithPlayer()
            }
        }
    }

    /// Starts a signal. `seekTo` is where in the file to begin (seconds), for a transmission
    /// joined part-way through; a live stream passes nil. `isLive` is what the system's now-playing
    /// card says; a recording (a mix, a clip) passes false.
    func attach(url: URL, seekTo: Double?, title: String, subtitle: String?, isLive: Bool = true) {
        generation += 1
        let gen = generation
        state = .tuning
        timeoutTask?.cancel()
        removeItemObservers()

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": KJConfig.userAgent]])
        let item = AVPlayerItem(asset: asset)
        // A transmission joined part-way through starts where the clock has got to. The seek
        // waits for the item to be ready: one asked for earlier is not reliably honoured on HLS.
        let start: Double? = (seekTo ?? 0) > 0 ? seekTo : nil

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let status = observed.status
            let message = observed.error?.localizedDescription ?? "This signal could not be played."
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch status {
                case .failed: self.state = .failed(message)
                case .readyToPlay: self.begin(at: start, generation: gen)
                default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.onEnded?()
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let cause = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = cause?.localizedDescription ?? "The signal stopped."
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.state = .failed(message)
            }
        }

        player.replaceCurrentItem(with: item)
        if start == nil { player.play() }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled, gen == self.generation, self.state == .tuning else { return }
            self.state = .failed("The signal did not start.")
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle ?? "Khajistan",
            MPNowPlayingInfoPropertyIsLiveStream: isLive
        ]
    }

    func pause() {
        player.pause()
        state = .paused
    }

    func resume() {
        player.play()
    }

    func toggle() {
        if state == .playing { pause() } else { resume() }
    }

    func stop() {
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeItemObservers()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        state = .idle
    }

    /// Seeks a ready item to where the transmission has got to, then plays. An item with no
    /// start offset was already told to play in `attach`.
    private func begin(at start: Double?, generation gen: Int) {
        guard let start else { return }
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.player.play()
            }
        }
    }

    /// Reads the player's live status rather than the value the callback carried, so a callback
    /// that arrives late cannot put back a state the viewer has already left.
    private func syncWithPlayer() {
        switch player.timeControlStatus {
        case .playing:
            timeoutTask?.cancel()
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            switch state {
            case .tuning, .playing: state = .tuning
            case .idle, .paused, .failed: break
            }
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func removeItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let token = endObserver { NotificationCenter.default.removeObserver(token) }
        endObserver = nil
        if let token = failObserver { NotificationCenter.default.removeObserver(token) }
        failObserver = nil
    }
}
