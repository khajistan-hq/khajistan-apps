import AVFoundation
import SwiftUI
import UIKit

/// The picture of an AVPlayer, drawn on a bare AVPlayerLayer. The layer has no background of
/// its own, so whatever the picture does not cover shows the skin's ground behind it.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// True for the Receiver's picture: with the app in the background a television channel's
    /// sound carries on. The player is told so (`audiovisualBackgroundPlaybackPolicy`) and keeps
    /// its layer; the picture is redrawn on return if it has not come back by itself.
    var soundCarriesInBackground = false

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        (view.layer as! AVPlayerLayer).videoGravity = gravity
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.soundCarriesInBackground = soundCarriesInBackground
        if soundCarriesInBackground { player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible }
        let layer = uiView.layer as! AVPlayerLayer
        if layer.player !== player { layer.player = player }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var soundCarriesInBackground = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        NotificationCenter.default.addObserver(self, selector: #selector(enteringForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func enteringForeground() {
        guard soundCarriesInBackground else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.redrawIfBlank() }
    }

    /// Back from the background, the sound plays on but the picture stays black about half the
    /// time (iPhone 17 simulator, 2026-10-28): the player's video does not start again, whether
    /// the layer let go of it in the background or kept it, and handing the layer the player
    /// again or turning the video track off and on does not wake it (Bugbot on PR 9). A seek
    /// does. It lands on the next keyframe, and plays at once rather than waiting to build up a
    /// buffer again, so the screen does not sit on "Connecting…".
    private func redrawIfBlank() {
        let layer = layer as! AVPlayerLayer
        guard window != nil, !layer.isReadyForDisplay, let player = layer.player, player.timeControlStatus == .playing else { return }
        player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .positiveInfinity) { finished in
            DispatchQueue.main.async {
                if finished, player.rate > 0 { player.playImmediately(atRate: player.rate) }
            }
        }
    }
}
