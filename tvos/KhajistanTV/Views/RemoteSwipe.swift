import SwiftUI
import UIKit

/// Watches the finger on the remote's touch surface, for a screen that must tell a swipe from a
/// press (Core/RemoteGesture.swift). It draws nothing and takes no focus: its pan recogniser,
/// limited to the remote's indirect touches as FilmRemote's is, sits on the window, above whatever
/// SwiftUI control holds focus, and recognises alongside everything else. The move commands
/// still reach SwiftUI; this only reports how far the finger has travelled.
struct RemoteSwipeReader: UIViewRepresentable {
    /// The recogniser's state and the finger's travel since it came down (down and right positive).
    var onPan: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.onPan = onPan
    }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var onPan: ((UIGestureRecognizer.State, CGPoint) -> Void)?
        private lazy var recogniser: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delegate = self
            return pan
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        // On the window while this view is in one, and off it when the screen goes.
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            window?.removeGestureRecognizer(recogniser)
            newWindow?.addGestureRecognizer(recogniser)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            onPan?(pan.state, pan.translation(in: nil))
        }
    }
}
