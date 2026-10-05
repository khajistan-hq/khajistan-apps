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
    /// The samples of the signal now playing, when it was asked to listen and its carrier can be
    /// read (a progressive file or stream; never HLS). The dancer reads this; nil means no dancer.
    private(set) var signal: SignalTap?
    /// A live radio mount the app is playing itself (LiveRadio.swift), in place of AVPlayer.
    @ObservationIgnored private var liveRadio: LiveRadio?
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

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.syncWithPlayer()
            }
        }
    }

    /// Starts a signal. `seekTo` is where in the file to begin (seconds), for a transmission
    /// joined part-way through; a live stream passes nil. `isLive` is what the system's now-playing
    /// card says; a recording (a mix, a clip) passes false. `listen` taps the audio for the
    /// dancer; the caller passes it only for sound with no picture on a channel that is not
    /// reverent (DancerView.swift). `live` plays a live MP3 or AAC radio mount through
    /// LiveRadio, the only way its samples can be read; anything it cannot play comes back here
    /// and plays on AVPlayer, with no dancer.
    func attach(url: URL, seekTo: Double?, title: String, subtitle: String?, isLive: Bool = true, listen: Bool = false, live: Bool = false) {
        generation += 1
        let gen = generation
        state = .tuning
        signal = nil
        timeoutTask?.cancel()
        removeItemObservers()
        stopLive()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle ?? "Khajistan",
            MPNowPlayingInfoPropertyIsLiveStream: isLive
        ]
        startTimeout(gen)

        if live && listen {
            player.replaceCurrentItem(with: nil)
            fadeTask?.cancel()
            fadeInPending = true
            let radio = LiveRadio(userAgent: KJConfig.userAgent) { [weak self] event in
                Task { @MainActor in
                    self?.liveEvent(event, generation: gen, url: url, title: title, subtitle: subtitle)
                }
            }
            radio.volume = 0
            liveRadio = radio
            signal = radio.signal
            radio.start(url: url)
            return
        }

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

        if listen { installTap(on: item, asset: asset, generation: gen) }

        fadeTask?.cancel()
        player.volume = 0
        fadeInPending = true
        player.replaceCurrentItem(with: item)
        if start == nil { player.play() }
    }

    private func startTimeout(_ gen: Int) {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled, gen == self.generation, self.state == .tuning else { return }
            self.state = .failed("The signal did not start.")
        }
    }

    private func liveEvent(_ event: LiveRadio.Event, generation gen: Int, url: URL, title: String, subtitle: String?) {
        guard gen == generation else { return }
        switch event {
        case .started:
            timeoutTask?.cancel()
            state = .playing
            if fadeInPending {
                fadeInPending = false
                Task { await ramp(to: 1, over: 0.5) }
            }
        case .failed(let message):
            state = .failed(message)
            stopLive()
            signal = nil
        case .fallback:
            // Played plainly, as the site hands the element back to src playback.
            attach(url: url, seekTo: nil, title: title, subtitle: subtitle, listen: false, live: false)
        }
    }

    private func stopLive() {
        liveRadio?.stop()
        liveRadio = nil
    }

    /// The level the listener hears, on whichever player is carrying the signal.
    private var volume: Float {
        get { liveRadio?.volume ?? player.volume }
        set {
            if let liveRadio { liveRadio.volume = newValue } else { player.volume = newValue }
        }
    }

    func pause() {
        if let liveRadio { liveRadio.pause() } else { player.pause() }
        state = .paused
    }

    func resume() {
        volume = 0
        fadeInPending = true
        if let liveRadio {
            liveRadio.resume()
            state = .playing
            fadeInPending = false
            Task { await ramp(to: 1, over: 0.5) }
        } else {
            player.play()
        }
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
        let from = volume
        let steps = max(1, Int(seconds * 60))
        let task = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                guard let self, !Task.isCancelled else { return }
                let t = Float(step) / Float(steps)
                // Ease in-out, so neither end of the fade clicks.
                let eased = t * t * (3 - 2 * t)
                self.volume = from + (target - from) * eased
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
        stopLive()
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeItemObservers()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        state = .idle
        signal = nil
    }

    /// Where the audio has got to, in ms of item time, for reading the tap in step with it.
    var playTimeMS: Double? {
        if let liveRadio { return liveRadio.playTimeMS }
        let time = player.currentTime()
        return time.isNumeric ? time.seconds * 1000 : nil
    }

    /// The clock live captions are placed on (kj-captions-live.js reads the same from the media
    /// element): where the picture is, how far behind the live edge, the programme date the HLS
    /// playlist stamps on it, and the seekable window. A radio mount the app plays itself has no
    /// window and no hold, so it runs on the wall clock.
    struct CaptionClock {
        let now: Double
        let behindLive: Double
        let programDate: Date?
        let window: ClosedRange<Double>?
    }

    var captionClock: CaptionClock? {
        if liveRadio != nil {
            return CaptionClock(now: Date().timeIntervalSince1970, behindLive: 0, programDate: nil, window: nil)
        }
        guard let item = player.currentItem else { return nil }
        let now = player.currentTime().seconds
        guard now.isFinite else { return nil }
        var window: ClosedRange<Double>?
        if let range = item.seekableTimeRanges.last?.timeRangeValue, range.duration.seconds > 0,
           range.start.seconds.isFinite, range.end.seconds.isFinite {
            window = range.start.seconds...range.end.seconds
        }
        return CaptionClock(now: now, behindLive: window.map { max(0, $0.upperBound - now) } ?? 0,
                            programDate: item.currentDate(), window: window)
    }

    /// Holds the picture further back, so a caption lands with the speech (the site's resync).
    func seekBack(by seconds: Double) {
        let target = player.currentTime().seconds - seconds
        guard target.isFinite, seconds > 0 else { return }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    /// Whether anything can be heard: the site's `!paused && !muted && volume > 0`.
    var audible: Bool {
        if let liveRadio { return liveRadio.isPlaying && liveRadio.volume > 0 }
        return player.timeControlStatus == .playing && !player.isMuted && player.volume > 0
    }

    /// Taps the item's audio once its tracks are known. An HLS asset has no audio track to tap,
    /// and then nothing is installed: no signal, no dancer.
    private func installTap(on item: AVPlayerItem, asset: AVURLAsset, generation gen: Int) {
        Task { [weak self] in
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first else { return }
            guard let self, gen == self.generation else { return }
            let tap = SignalTap()
            guard let mix = tap.audioMix(for: track) else { return }
            item.audioMix = mix
            self.signal = tap
        }
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
        guard liveRadio == nil else { return }
        switch player.timeControlStatus {
        case .playing:
            timeoutTask?.cancel()
            state = .playing
            if fadeInPending {
                fadeInPending = false
                Task { await ramp(to: 1, over: 0.5) }
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

    private func removeItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let token = endObserver { NotificationCenter.default.removeObserver(token) }
        endObserver = nil
        if let token = failObserver { NotificationCenter.default.removeObserver(token) }
        failObserver = nil
    }
}
