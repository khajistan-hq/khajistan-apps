import AVFoundation
import AVKit
import Observation

/// Picture in picture for a receiver channel: the picture leaves its screen and plays in a
/// corner while the viewer browses the app or another one, as the TV app's channels do. One
/// AVPictureInPictureController for each of the player screen's two layers (the one on screen
/// and the one a channel change tunes behind it), made as each layer is drawn, so the one on
/// screen is ready by the time the viewer asks.
@MainActor @Observable
final class PictureInPicture: NSObject {
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// The corner window is up.
    private(set) var isActive = false
    /// Called when the window is up, so the player screen can close behind it.
    @ObservationIgnored var onStart: (() -> Void)?
    /// Called when the window could not open, with the reason to show.
    @ObservationIgnored var onFail: ((String) -> Void)?
    /// The viewer asked for the channel full screen again.
    @ObservationIgnored var onRestore: (() -> Void)?
    /// The window closed without a restore: the signal is no longer wanted.
    @ObservationIgnored var onEnd: (() -> Void)?

    @ObservationIgnored private var controllers: [ObjectIdentifier: AVPictureInPictureController] = [:]
    @ObservationIgnored private var restoring = false
    /// `stop()` closed the window: AVKit still asks to restore, and that is not the viewer asking.
    @ObservationIgnored private var stopping = false

    /// A layer as it is drawn. Called on every redraw; a layer already held is left alone.
    /// Layers no longer on screen are let go: Transmission draws new layers after a channel
    /// change, and the old ones, still holding the same player, were picked by `start` and
    /// refused (owner's Apple TV, 2026-11-15: "pip not working ... in transmission").
    func bind(_ layer: AVPlayerLayer) {
        guard Self.isSupported else { return }
        if !isActive {
            controllers = controllers.filter { $0.value.playerLayer.superlayer != nil || $0.value.playerLayer === layer }
        }
        guard controllers[ObjectIdentifier(layer)] == nil,
              let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        controllers[ObjectIdentifier(layer)] = pip
    }

    /// Opens the corner window on the layer that draws `player`. False when it cannot open now.
    @discardableResult
    func start(_ player: AVPlayer) -> Bool {
        // The layer on screen that draws `player`: an off-screen layer can hold the same player.
        let drawing = controllers.values.filter { $0.playerLayer.player === player && $0.playerLayer.superlayer != nil }
        guard !isActive, let pip = drawing.first(where: \.isPictureInPicturePossible) ?? drawing.first,
              pip.isPictureInPicturePossible else { return false }
        // The window keeps playing outside the app only on a playback session.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        restoring = false
        stopping = false
        pip.startPictureInPicture()
        return true
    }

    /// Closes the window, if it is up. A restore already closing it is left to finish.
    func stop() {
        guard isActive, !restoring else { return }
        stopping = true
        controllers.values.first { $0.isPictureInPictureActive }?.stopPictureInPicture()
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            onStart?()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated {
            isActive = false
            onFail?("Picture in picture did not open. Try again.")
            letGo()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            guard !stopping else { return }
            restoring = true
            onRestore?()
        }
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            if !restoring, !stopping { onEnd?() }
            restoring = false
            stopping = false
            letGo()
        }
    }

    /// The closures hold the player screen's state, which holds this object: let go once the
    /// window is done with them, or each session keeps two players alive.
    func letGo() {
        onStart = nil
        onFail = nil
        onRestore = nil
        onEnd = nil
    }
}
