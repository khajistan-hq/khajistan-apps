import AVFoundation
import SwiftUI
import UIKit

/// The picture of an AVPlayer, drawn on a bare AVPlayerLayer. The layer has no background of
/// its own, so whatever the picture does not cover shows the skin's ground behind it.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        (view.layer as! AVPlayerLayer).player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        (uiView.layer as! AVPlayerLayer).player = player
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

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
        (layer as! AVPlayerLayer).videoGravity = .resizeAspect
    }
}
