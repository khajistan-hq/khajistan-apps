import AVFoundation
import AVKit
import Observation
import UIKit

/// Picture in picture for a player screen: the picture leaves its screen and plays in a corner
/// while the viewer browses the app or another one, as the TV app's channels and films do.
///
/// The window shows frames this app draws (PiPFramePump), not AVPlayer's own layer, so the house
/// caption plate goes into the window with the picture: a film's track, a programme's prepared
/// file, a receiver channel's live captions (owner, 2026-11-17: "pip still not showing subtitles
/// in skin"). Back to full screen is one action, from the window's own controls (the TV button)
/// or from the app's PiP bar (PiPBar), which the viewer lands on as the window opens.
@MainActor @Observable
final class PictureInPicture: NSObject {
    static var isSupported: Bool {
        #if DEBUG
        if proof { return true }
        #endif
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    #if DEBUG
    /// `-kjpipproof YES`: the simulator has no picture in picture, so the frames' layer is shown
    /// as a corner window in the app itself, fed exactly as the real window is. UI tests photograph
    /// the caption plate in it and work the bar; the real window is checked on an Apple TV.
    static var proof: Bool { UserDefaults.standard.bool(forKey: "kjpipproof") }
    #endif

    /// The corner window is up.
    private(set) var isActive = false
    /// The picture in the window is playing, for the bar's Play/Pause.
    private(set) var isPlaying = false
    /// What the bar names: the channel, the programme or the film.
    var title = ""
    /// A broadcast: the window shows it as live, with no skip and no timeline.
    @ObservationIgnored var isLive = true
    /// The caption on screen now, nil for none. Read ten times a second while the window is up.
    @ObservationIgnored var captions: (@MainActor () -> String?)?
    /// The skin the caption plate takes.
    @ObservationIgnored var skin: (@MainActor () -> Skin)?
    /// Play or pause from the window's own button or the bar. Nil plays or pauses AVPlayer.
    @ObservationIgnored var onSetPlaying: ((Bool) -> Void)?
    /// Called when the window is up, so the player screen can close behind it.
    @ObservationIgnored var onStart: (() -> Void)?
    /// Called when the window could not open, with the reason to show.
    @ObservationIgnored var onFail: ((String) -> Void)?
    /// The viewer asked for the picture full screen again.
    @ObservationIgnored var onRestore: (() -> Void)?
    /// The window closed without a restore: the signal is no longer wanted.
    @ObservationIgnored var onEnd: (() -> Void)?

    @ObservationIgnored private let pump = PiPFramePump()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private weak var player: AVPlayer?
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var restoring = false
    /// `stop()` closed the window: AVKit still asks to restore, and that is not the viewer asking.
    @ObservationIgnored private var stopping = false
    /// `close()` closed the window: the signal ends with it, as the window's own close does.
    @ObservationIgnored private var closing = false

    /// How long `start` waits for the first frame and for AVKit to allow the window.
    static let startWait: Duration = .seconds(4)

    /// A player layer as it is drawn: only its window is wanted, where the frames' layer goes.
    /// Called on every redraw.
    func bind(_ layer: AVPlayerLayer) {
        if let view = layer.delegate as? UIView, let window = view.window { self.window = window }
    }

    /// Opens the corner window on `player`'s picture. False when it cannot open now; true when it
    /// is opening, in which case `onStart` or `onFail` follows.
    @discardableResult
    func start(_ player: AVPlayer) -> Bool {
        guard Self.isSupported, !isActive, pending == nil, player.currentItem != nil,
              let window = window ?? Self.keyWindow else { return false }
        // AVKit answers isPictureInPicturePossible with false on any session but playback, so the
        // session is set before the controller is made (Apple TV HD, 2026-11-16). Only when not
        // already playback: changing the mode under a live session can drop its sound for a moment.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback, mode: .moviePlayback) }
        install(in: window)
        #if DEBUG
        if Self.proof { return startProof(player, in: window) }
        #endif
        guard let controller else { return false }
        restoring = false
        stopping = false
        closing = false
        self.player = player
        // With the screen gone there is no layer on the player: without this tvOS pauses it when
        // the app goes to the background, and the window would freeze over the other app.
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        pump.follow(player)
        feedWindow()
        controller.invalidatePlaybackState()
        pending = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.startWait
            while ContinuousClock.now < deadline {
                guard let self, !Task.isCancelled else { return }
                if self.pump.frames > 0, controller.isPictureInPicturePossible {
                    self.pending = nil
                    controller.startPictureInPicture()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.onFail?("Picture in picture is not ready yet. Try again in a moment.")
            self.finish()
        }
        return true
    }

    /// Closes the window, if it is up or opening, and stops nothing else. A restore already
    /// closing it is left to finish.
    func stop() {
        if let pending {
            pending.cancel()
            self.pending = nil
            finish()
            return
        }
        guard isActive, !restoring else { return }
        stopping = true
        closeWindow()
    }

    /// Back to full screen, as the window's own full-screen control does: the player screen opens
    /// again and the window closes into it.
    func restore() {
        guard isActive, !restoring, !stopping else { return }
        restoring = true
        onRestore?()
        closeWindow()
    }

    /// Closes the window and ends what it plays, as the window's own close control does.
    func close() {
        guard isActive, !restoring, !stopping, !closing else { return }
        closing = true
        closeWindow()
    }

    /// Play or pause the picture in the window.
    func setPlaying(_ playing: Bool) {
        guard player != nil else { return }
        if let onSetPlaying { onSetPlaying(playing) } else if playing { player?.play() } else { player?.pause() }
        isPlaying = playing
        controller?.invalidatePlaybackState()
    }

    // MARK: - Inside

    private func closeWindow() {
        #if DEBUG
        if Self.proof { windowClosed(); return }
        #endif
        controller?.stopPictureInPicture()
    }

    /// The window has gone, however it was closed.
    private func windowClosed() {
        if closing || (!restoring && !stopping) { onEnd?() }
        restoring = false
        stopping = false
        closing = false
        finish()
    }

    #if DEBUG
    private func startProof(_ player: AVPlayer, in window: UIWindow) -> Bool {
        restoring = false
        stopping = false
        closing = false
        self.player = player
        // Where tvOS puts its window: the bottom right, a third of the screen wide.
        let width = window.bounds.width / 3, height = width * 9 / 16
        pump.layer.removeFromSuperlayer()
        window.layer.addSublayer(pump.layer)
        pump.layer.frame = CGRect(x: window.bounds.width - width - 90, y: window.bounds.height - height - 60, width: width, height: height)
        pump.windowDidResize(width: width)
        pump.follow(player)
        feedWindow()
        pending = Task { [weak self] in
            while let self, !Task.isCancelled, self.pump.frames == 0 { try? await Task.sleep(for: .milliseconds(100)) }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.isActive = true
            self.isPlaying = player.timeControlStatus != .paused
            self.onStart?()
        }
        return true
    }
    #endif

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    /// The frames' layer sits at the back of the window, under every screen, sized as the screen:
    /// tvOS takes the window's picture from it and animates the window out of its frame.
    private func install(in window: UIWindow) {
        if pump.layer.superlayer !== window.layer {
            pump.layer.removeFromSuperlayer()
            window.layer.insertSublayer(pump.layer, at: 0)
        }
        pump.layer.frame = window.bounds
        guard controller == nil else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: pump.layer, playbackDelegate: self)
        let made = AVPictureInPictureController(contentSource: source)
        made.delegate = self
        controller = made
    }

    /// Ten times a second while the window is opening or up: the caption, the item (a handover
    /// brings a new one), and whether the picture plays, which the window's button shows.
    private func feedWindow() {
        feed?.cancel()
        feed = Task { [weak self] in
            var lastPlaying: Bool?
            var lastDuration: Double?
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.pump.follow(player)
                let skin = self.skin?() ?? .day
                self.pump.show(self.captions?().flatMap { $0.isEmpty ? nil : PiPFramePump.Caption(text: $0, skin: skin) })
                let playing = player.timeControlStatus != .paused
                let duration = player.currentItem?.duration.seconds
                if playing != lastPlaying || duration != lastDuration {
                    lastPlaying = playing
                    lastDuration = duration
                    self.isPlaying = playing
                    self.controller?.invalidatePlaybackState()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The window is done: stop feeding it and let go of the player screen's closures.
    private func finish() {
        isActive = false
        feed?.cancel()
        feed = nil
        pump.stop()
        pump.layer.removeFromSuperlayer()
        player = nil
        letGo()
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            isPlaying = player?.timeControlStatus != .paused
            onStart?()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated {
            onFail?("Picture in picture did not open. Try again.")
            finish()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            // The bar's Full screen already asked (restore()); `stop()` and `close()` are not a restore.
            guard !stopping, !restoring, !closing else { return }
            restoring = true
            onRestore?()
        }
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { windowClosed() }
    }

    /// The closures hold the player screen's state, which holds this object: let go once the
    /// window is done with them, or each session keeps two players alive.
    func letGo() {
        onStart = nil
        onFail = nil
        onRestore = nil
        onEnd = nil
        onSetPlaying = nil
        captions = nil
        skin = nil
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { setPlaying(playing) }
    }

    /// A broadcast is live: no timeline and no skip. A film runs from its start to its length.
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            let live = CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
            guard !isLive, let duration = player?.currentItem?.duration, duration.isNumeric, duration.seconds > 0 else { return live }
            return CMTimeRange(start: .zero, duration: duration)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { player.map { $0.timeControlStatus == .paused } ?? true }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        pump.windowDidResize(width: CGFloat(newRenderSize.width))
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            guard !isLive, let player else { completionHandler(); return }
            let target = CMTimeMaximum(.zero, CMTimeAdd(player.currentTime(), skipInterval))
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                DispatchQueue.main.async { completionHandler() }
            }
        }
    }
}
