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
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    /// A new signal starts silent and its sound comes up once it is actually playing.
    @ObservationIgnored private var fadeInPending = false

    /// The controller that last started a signal: the one the lock screen's buttons reach.
    private static weak var active: PlayerController?

    /// The lock screen and headphone buttons, wired once for the life of the app.
    private static let remoteCommands: Void = {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { _ in
            Task { @MainActor in PlayerController.active?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            Task { @MainActor in PlayerController.active?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlayerController.active?.toggle() }
            return .success
        }
    }()

    init() {
        _ = Self.remoteCommands
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

        // Sound carries on with the screen locked, as radio should (UIBackgroundModes audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        Self.active = self

        fadeTask?.cancel()
        player.volume = 0
        fadeInPending = true
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
        updateNowPlayingRate(0)
    }

    func resume() {
        player.volume = 0
        fadeInPending = true
        player.play()
    }

    /// Brings the sound down to nothing over `seconds`, for a channel change: the old channel
    /// fades out as the ground comes up, and the new one fades in once it plays.
    func fadeOut(over seconds: Double = 0.45) async {
        fadeInPending = false
        await ramp(to: 0, over: seconds)
    }

    /// Returns once the signal plays or fails, or after `limit`, whichever is first. The ground
    /// lifts on the first of those: a picture, a reason on screen, or no more waiting.
    func settled(within limit: Duration = .seconds(8)) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !Task.isCancelled {
            switch state {
            case .playing, .failed, .idle, .paused: return
            case .tuning: try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Moves the volume to `target` in steps of a sixtieth of a second. A newer ramp, or a new
    /// signal, cancels this one where it stands.
    private func ramp(to target: Float, over seconds: Double) async {
        fadeTask?.cancel()
        let from = player.volume
        let steps = max(1, Int(seconds * 60))
        let task = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                guard let self, !Task.isCancelled else { return }
                let t = Float(step) / Float(steps)
                // Ease in-out, so neither end of the fade clicks.
                let eased = t * t * (3 - 2 * t)
                self.player.volume = from + (target - from) * eased
            }
        }
        fadeTask = task
        await task.value
    }

    func toggle() {
        if state == .playing { pause() } else { resume() }
    }

    func stop() {
        fadeTask?.cancel()
        fadeInPending = false
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeItemObservers()
        if Self.active === self { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
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
            updateNowPlayingRate(1)
            if fadeInPending {
                fadeInPending = false
                Task { await ramp(to: 1, over: 0.9) }
            }
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

    private func updateNowPlayingRate(_ rate: Double) {
        guard Self.active === self, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
