import SwiftUI
import UIKit

/// Tells a click from a swipe on the remote. SwiftUI's `onMoveCommand` answers both alike, so a
/// brush on the touch surface changed channel as a click did (Joey, 2026-11-02: "you should only
/// be able to change channels by clicking up or down, and swiping down will take you to the TV
/// Guide"). A click up or down is an arrow press (the ring on the newer Siri Remote, the edges of
/// the older one's surface, the arrow buttons of any other remote); a swipe is touches on the
/// surface. The recognisers sit on the window, above the focused view, and let every press and
/// touch through to it as before.
struct RemoteGestures: UIViewRepresentable {
    var clickUp: () -> Void
    var clickDown: () -> Void
    var swipeDown: () -> Void

    func makeUIView(context: Context) -> RemoteGestureView {
        let view = RemoteGestureView()
        // Never a target itself: a UIKit view that takes touches here blocks the remote.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: RemoteGestureView, context: Context) {
        view.clickUp = clickUp
        view.clickDown = clickDown
        view.swipeDown = swipeDown
    }

    static func dismantleUIView(_ view: RemoteGestureView, coordinator: ()) {
        view.detach()
    }
}

final class RemoteGestureView: UIView, UIGestureRecognizerDelegate {
    var clickUp: () -> Void = {}
    var clickDown: () -> Void = {}
    var swipeDown: () -> Void = {}
    private var installed: [UIGestureRecognizer] = []

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        let recognizers = [
            Self.click(.upArrow, target: self, action: #selector(up)),
            Self.click(.downArrow, target: self, action: #selector(down)),
            Self.swipe(.down, target: self, action: #selector(swipedDown)),
        ]
        for recognizer in recognizers {
            // Watch only: the presses and touches still reach SwiftUI, which keeps left, right,
            // Select and the guide's rows.
            recognizer.cancelsTouchesInView = false
            // The focus engine has recognisers of its own on these presses and touches; without
            // this, theirs win and ours never fire.
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
        }
        installed = recognizers
        #if DEBUG
        NSLog("KJREMOTE installed on %@", String(describing: type(of: window)))
        #endif
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func detach() {
        for recognizer in installed { recognizer.view?.removeGestureRecognizer(recognizer) }
        installed = []
    }

    @objc private func up() { log("click up"); clickUp() }
    @objc private func down() { log("click down"); clickDown() }
    @objc private func swipedDown() { log("swipe down"); swipeDown() }

    private func log(_ what: String) {
        #if DEBUG
        NSLog("KJREMOTE %@", what)
        #endif
    }

    private static func click(_ type: UIPress.PressType, target: Any, action: Selector) -> UIGestureRecognizer {
        let recognizer = UITapGestureRecognizer(target: target, action: action)
        recognizer.allowedPressTypes = [NSNumber(value: type.rawValue)]
        recognizer.allowedTouchTypes = []
        return recognizer
    }

    private static func swipe(_ direction: UISwipeGestureRecognizer.Direction, target: Any, action: Selector) -> UIGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer(target: target, action: action)
        recognizer.direction = direction
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        recognizer.allowedPressTypes = []
        return recognizer
    }
}
