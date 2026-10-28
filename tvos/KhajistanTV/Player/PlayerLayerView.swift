import AVFoundation
import SwiftUI
import UIKit

/// The picture of an AVPlayer, drawn on a bare AVPlayerLayer. The layer has no background of
/// its own, so whatever the picture does not cover shows the skin's ground behind it.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// True for the Receiver's picture: with the app in the background the layer lets go of the
    /// player, so a television channel's sound carries on (the system pauses a player that is
    /// still drawing video), and takes it back on return.
    var soundCarriesInBackground = false

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.soundCarriesInBackground = soundCarriesInBackground
        view.attach(player)
        (view.layer as! AVPlayerLayer).videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.soundCarriesInBackground = soundCarriesInBackground
        uiView.attach(player)
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var soundCarriesInBackground = false
    private var player: AVPlayer?
    private var inBackground = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func attach(_ player: AVPlayer) {
        self.player = player
        if !(inBackground && soundCarriesInBackground) { (layer as! AVPlayerLayer).player = player }
    }

    private func configure() {
        backgroundColor = .clear
        (layer as! AVPlayerLayer).videoGravity = .resizeAspect
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(enteringForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func enteredBackground() {
        inBackground = true
        if soundCarriesInBackground { (layer as! AVPlayerLayer).player = nil }
    }

    @objc private func enteringForeground() {
        inBackground = false
        (layer as! AVPlayerLayer).player = player
    }
}
