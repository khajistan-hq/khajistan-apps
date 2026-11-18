import AVFoundation
import AVKit
import Observation
import UIKit

/// Picture in picture for a player screen: the picture leaves its screen and plays in a corner
/// while the viewer browses the app or another one, as the TV app's channels and films do. One
/// AVPictureInPictureController for each of the player screen's layers (the one on screen and the
/// one a channel change tunes behind it), made as each layer is drawn, so the one on screen is
/// ready by the time the viewer asks.
///
/// The window carries the house caption plate (owner, 2026-11-17: "pip still not showing subtitles
/// in skin"): a stream's subtitle track is handed to tvOS, which draws it in the skin's colours
/// (`onHandOff`, RecordedSubtitles.handOff), and a file's prepared subtitles are drawn into the
/// picture (HouseCaptionCompositor). Back to full screen is one action, from tvOS's own window
/// menu (the TV button) or from the app's PiP bar (PiPBar), which the viewer lands on as the
/// window opens.
@MainActor @Observable
final class PictureInPicture: NSObject {
    static var isSupported: Bool {
        #if DEBUG
        if proof { return true }
        #endif
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    #if DEBUG
    /// `-kjpipproof YES`: the simulator has no picture in picture, so the window is taken as open
    /// the moment it is asked for. UI tests work the bar against it; the window itself is
    /// checked on an Apple TV.
    static var proof: Bool { UserDefaults.standard.bool(forKey: "kjpipproof") }
    #endif

    /// The corner window is up.
    var isActive: Bool { lifecycle.isActive }
    /// The picture in the window is playing, for the bar's Play/Pause.
    private(set) var isPlaying = false
    /// What the bar names: the channel, the programme or the film.
    var title = ""
    /// The caption the window draws into a file's picture, nil for none. Read ten times a second
    /// while the window is up.
    @ObservationIgnored var captions: (@MainActor () -> String?)?
    /// True while the programme's subtitles are a prepared file (not a track tvOS can draw), so a
    /// file's picture gets the compositor. Nil for never.
    @ObservationIgnored var hasFileCaptions: (@MainActor () -> Bool)?
    /// The compositor is drawing into the playing item's picture.
    private(set) var drawsIntoPicture = false
    /// The skin the caption plate takes.
    @ObservationIgnored var skin: (@MainActor () -> Skin)?
    /// Hands a stream's subtitle track to tvOS as the window opens, which then draws it.
    @ObservationIgnored var onHandOff: (() -> Void)?
    /// The bar's caption control: its label ("Subtitles · English"), nil for none. Read by the
    /// bar, so a label built on observed state redraws it.
    @ObservationIgnored var captionLabel: (@MainActor () -> String?)?
    /// Works the bar's caption control: the next language, then off.
    @ObservationIgnored var onCaptionToggle: (() -> Void)?
    /// Play or pause from the bar or the remote. Nil plays or pauses AVPlayer.
    @ObservationIgnored var onSetPlaying: ((Bool) -> Void)?
    /// The player whose state follows the window's own Play and Pause, which work AVPlayer directly.
    @ObservationIgnored weak var controller: PlayerController?
    /// A broadcast: the window's own Play, after a pause, rejoins it live (`onSetPlaying(true)`)
    /// rather than playing on from where it stopped.
    @ObservationIgnored var rejoinsOnPlay = false
    /// Called when the window is up, so the player screen can close behind it.
    @ObservationIgnored var onStart: (() -> Void)?
    /// Called when the window could not open, with the reason to show.
    @ObservationIgnored var onFail: ((String) -> Void)?
    /// The viewer asked for the picture full screen again.
    @ObservationIgnored var onRestore: (() -> Void)?
    /// The window closed without a restore: the signal is no longer wanted.
    @ObservationIgnored var onEnd: (() -> Void)?

    private var lifecycle = PiPLifecycle()
    @ObservationIgnored private var controllers: [ObjectIdentifier: AVPictureInPictureController] = [:]
    @ObservationIgnored private weak var player: AVPlayer?
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Items given the caption compositor, so it comes off them when the window has gone.
    @ObservationIgnored private var composited = NSHashTable<AVPlayerItem>.weakObjects()
    @ObservationIgnored private var compositing: Task<Void, Never>?
    /// `stop()` came while the window was opening: if AVKit opens it anyway, it is closed at once.
    @ObservationIgnored private var abandoned = false
    /// The bar's shown state and the window's own Play (PiPPlayFollower).
    @ObservationIgnored private var playFollower = PiPPlayFollower(playing: true)
    @ObservationIgnored private let started = ContinuousClock.now
    /// The item last read, held so its identity cannot pass to a new item between two readings.
    @ObservationIgnored private var lastItem: AVPlayerItem?
    /// How long `start` waits for AVKit to open the window.
    static let startWait: Duration = .seconds(6)
    /// How long the window waits, on full screen, for the player screen to come up before it
    /// closes into it (AVKit's restore completion).
    static let restoreSettle: Duration = .milliseconds(500)

    /// A layer as it is drawn. Called on every redraw; a layer already held is left alone.
    /// Layers no longer on screen are let go: Transmission draws new layers after a channel
    /// change, and the old ones, still holding the same player, were picked by `start` and
    /// refused (owner's Apple TV, 2026-11-15: "pip not working ... in transmission"). A layer
    /// not yet in the window counts as off screen too, so it may be let go once and bound again
    /// on its next redraw.
    func bind(_ layer: AVPlayerLayer) {
        guard Self.isSupported else { return }
        if !isActive {
            controllers = controllers.filter { $0.value.playerLayer.superlayer != nil || $0.value.playerLayer === layer }
        }
        guard controllers[ObjectIdentifier(layer)] == nil else { return }
        // AVKit answers isPictureInPicturePossible with false on any session but playback, so
        // the session is set before the controller is made, not when the viewer asks: set in
        // start(), it came after the check and the window never opened (Apple TV HD, 2026-11-16).
        // Only when not already playback: a radio playing under the screens set it, and changing
        // the mode under a live session can drop its sound for a moment.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback, mode: .moviePlayback) }
        guard let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        controllers[ObjectIdentifier(layer)] = pip
    }

    /// Opens the corner window on the layer that draws `player`. False when it cannot open now;
    /// true when it is opening, in which case `onStart` or `onFail` follows.
    @discardableResult
    func start(_ player: AVPlayer) -> Bool {
        guard !isActive, pending == nil else { return false }
        abandoned = false
        #if DEBUG
        if Self.proof {
            self.player = player
            pending = Task { [weak self] in
                self?.pending = nil
                self?.windowOpened()
            }
            return true
        }
        #endif
        // The layer on screen that draws `player`: an off-screen layer can hold the same player.
        let drawing = controllers.values.filter { $0.playerLayer.player === player && $0.playerLayer.superlayer != nil }
        guard let pip = drawing.first(where: \.isPictureInPicturePossible) else { return false }
        self.player = player
        pip.startPictureInPicture()
        // Neither delegate call can come: give up rather than hold the screen's closures for good.
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.startWait)
            guard let self, !Task.isCancelled, !self.isActive else { return }
            self.pending = nil
            pip.stopPictureInPicture()
            self.onFail?("Picture in picture did not open. Try again.")
            self.finish()
        }
        return true
    }

    /// Closes the window, if it is up or opening, and stops nothing else: another signal is
    /// starting, or the screen has taken the picture over.
    func stop() {
        if let pending {
            pending.cancel()
            self.pending = nil
            abandoned = true
            finish()
            return
        }
        if lifecycle.stopAsked() { closeWindow() }
    }

    /// Back to full screen, as the window's own full-screen control does: the player screen opens
    /// again and the window closes into it.
    func restore() {
        guard lifecycle.restoreAsked() else { return }
        onRestore?()
        closeWindow()
    }

    /// Closes the window and ends what it plays, as the window's own close control does.
    func close() {
        if lifecycle.closeAsked() { closeWindow() }
    }

    /// Play or pause the picture in the window.
    func setPlaying(_ playing: Bool) {
        guard player != nil else { return }
        playFollower.ask(playing, at: seconds)
        if let onSetPlaying { onSetPlaying(playing) } else if playing { player?.play() } else { player?.pause() }
        isPlaying = playing
    }

    // MARK: - Inside

    private func closeWindow() {
        #if DEBUG
        if Self.proof {
            // As AVKit does: it asks to restore the interface, whoever closed the window, then stops.
            restoreRequested { _ in self.windowClosed() }
            return
        }
        #endif
        controllers.values.first { $0.isPictureInPictureActive }?.stopPictureInPicture()
    }

    private func windowOpened(_ controller: AVPictureInPictureController? = nil) {
        pending?.cancel()
        pending = nil
        // Stopped while it was opening: no screen is waiting on it, so it closes again at once.
        guard !abandoned else {
            controller?.stopPictureInPicture()
            return
        }
        lifecycle.started()
        isPlaying = player?.timeControlStatus != .paused
        playFollower = PiPPlayFollower(playing: isPlaying)
        self.controller?.followsWindow = true
        onStart?()
        // The screen may have refused the window (`onStart` stops it): only a window still up
        // takes the subtitle track from the screen.
        guard lifecycle.isActive, lifecycle.reason == .none else { return }
        onHandOff?()
        feedWindow()
    }

    /// AVKit asks to restore the interface. The window's own full-screen control opens the screen
    /// now; the bar's Full screen opened it already; Close and Stop get a plain close. The window
    /// closes into the screen once it has had a moment to come up.
    private func restoreRequested(_ completion: @escaping (Bool) -> Void) {
        if lifecycle.reason != .restore {
            guard lifecycle.systemRestoreAsked() else { completion(false); return }
            onRestore?()
        }
        Task {
            try? await Task.sleep(for: Self.restoreSettle)
            completion(true)
        }
    }

    /// The window has gone, however it was closed.
    private func windowClosed() {
        if lifecycle.stopped() { onEnd?() }
        finish()
    }

    /// Ten times a second while the window is up: the caption for a file's picture, the item (a
    /// handover brings a new one, which gets the compositor in its turn), and whether the picture
    /// plays, which the bar shows.
    private func feedWindow() {
        feed?.cancel()
        feed = Task { [weak self] in
            var styled: (item: AVPlayerItem, skin: Skin)?
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                let skin = self.skin?() ?? .day
                if let item = player.currentItem {
                    if !self.composited.contains(item), self.hasFileCaptions?() == true { self.composite(item) }
                    // tvOS draws a stream's track in the colours set at attach: a skin that turns
                    // while the window is up (dawn, dusk) turns the window's subtitles with it.
                    if styled?.item !== item || styled?.skin != skin {
                        if styled != nil { item.textStyleRules = RecordedSubtitles.styleRules(skin) }
                        styled = (item, skin)
                    }
                }
                self.drawsIntoPicture = player.currentItem.map {
                    $0.videoComposition?.customVideoCompositorClass == HouseCaptionCompositor.self
                } ?? false
                let text = PiPCaptionFeed.drawn(read: { self.captions?() }, intoPicture: self.drawsIntoPicture)
                HouseCaptionCompositor.show(text.map { HouseCaptionCompositor.Caption(text: $0, skin: skin) })
                self.followPlaying(player)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The window's own Play and Pause work AVPlayer directly: each is passed on once, so the
    /// player's state follows and a broadcast rejoins live (PiPPlayFollower, which also holds the
    /// bar's state while a Play of its own retunes).
    private func followPlaying(_ player: AVPlayer) {
        let item = player.currentItem
        lastItem = item
        let event = playFollower.read(playing: player.timeControlStatus != .paused,
                                      item: item.map(ObjectIdentifier.init), at: seconds)
        if isPlaying != playFollower.shown { isPlaying = playFollower.shown }
        switch event {
        case .windowPlay:
            if rejoinsOnPlay {
                // The bar holds Playing while the channel rejoins live.
                playFollower.ask(true, at: seconds)
                onSetPlaying?(true)
            } else {
                controller?.follow(playing: true)
            }
        case .windowPause:
            // The end of the file stops the picture too, and that is not a Pause.
            if let item, item.duration.isNumeric, item.currentTime().seconds >= item.duration.seconds - 1 { return }
            controller?.follow(playing: false)
            // A broadcast rejoins live on Play: muted, so the old place is not heard in the moment
            // before the rejoin stops it (PlayerController.stop unmutes; the fade-back skips it).
            if rejoinsOnPlay { player.isMuted = true }
        case .none:
            break
        }
    }

    private var seconds: Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// The compositor draws frames as they come off the track, so a picture tvOS would turn or
    /// scale (a phone video's rotation, a non-square pixel) is left alone rather than drawn wrong.
    private func composite(_ item: AVPlayerItem) {
        composited.add(item)
        compositing?.cancel()
        compositing = Task { [weak self] in
            guard let track = try? await item.asset.loadTracks(withMediaType: .video).first,
                  let (transform, size) = try? await track.load(.preferredTransform, .naturalSize),
                  transform.isIdentity,
                  let made = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: item.asset),
                  made.renderSize == size, made.renderScale == 1,
                  !Task.isCancelled, self?.isActive == true else { return }
            made.customVideoCompositorClass = HouseCaptionCompositor.self
            item.videoComposition = made
        }
    }

    /// The window is done: the compositor comes off the picture (the screen draws its own caption
    /// again) and the player screen's closures are let go.
    private func finish() {
        pending?.cancel()
        pending = nil
        feed?.cancel()
        feed = nil
        compositing?.cancel()
        compositing = nil
        HouseCaptionCompositor.show(nil)
        for item in composited.allObjects where item.videoComposition?.customVideoCompositorClass == HouseCaptionCompositor.self {
            item.videoComposition = nil
        }
        composited.removeAllObjects()
        drawsIntoPicture = false
        controller?.followsWindow = false
        lastItem = nil
        player = nil
        letGo()
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { windowOpened(controller) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated {
            onFail?("Picture in picture did not open. Try again.")
            finish()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated { restoreRequested(completionHandler) }
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
        controller = nil
        rejoinsOnPlay = false
        onHandOff = nil
        onCaptionToggle = nil
        hasFileCaptions = nil
        captions = nil
        captionLabel = nil
        skin = nil
    }
}
