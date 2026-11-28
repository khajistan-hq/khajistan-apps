import GameController
import SwiftUI
import UIKit

/// The full film's picture: the one thing on screen that takes focus, and the place a swipe across
/// the remote's touch surface lands, which scrubs the film as Apple's player does. Select is read
/// here; the arrows, Play/Pause and Back are SwiftUI's (tvOS hands the arrows to SwiftUI first).
struct FilmRemote: UIViewRepresentable {
    var onSelect: () -> Void
    /// A swipe's state and its travel across, in remote points.
    /// The pan's state and its translation: x scrubs, y tells a slide down from a scrub.
    var onSwipe: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ view: Surface, context: Context) {
        view.remote = self
    }

    final class Surface: UIView {
        var remote: FilmRemote?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let swipe = UIPanGestureRecognizer(target: self, action: #selector(pan))
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(swipe)
            // For the UI tests: the full film is on screen while this view is.
            accessibilityIdentifier = "filmPicture"
        }

        required init?(coder: NSCoder) { nil }

        override var canBecomeFocused: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // After this layout pass, when the screen's views are all in place.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let focus = UIFocusSystem.focusSystem(for: self) else { return }
                focus.requestFocusUpdate(to: self)
                focus.updateFocusIfNeeded()
            }
        }

        // Select reaches the focused view, as Play/Pause does; the arrows do not.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let others = presses.filter { $0.type != .select }
            if !others.isEmpty { super.pressesBegan(others, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.type == .select }) { remote?.onSelect() }
            let others = presses.filter { $0.type != .select }
            if !others.isEmpty { super.pressesEnded(others, with: event) }
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            remote?.onSwipe(recognizer.state, recognizer.translation(in: self))
        }
    }
}

/// A press held on the left or right edge of the Siri Remote's clickpad, read through
/// GameController. tvOS gives SwiftUI one move when a press is let go and nothing while it is
/// held, so Apple's hold-to-scan cannot be built on the move commands. The clickpad is the
/// remote's button A, and the touch surface its dpad: a press with the thumb past half way to an
/// edge, held, is a scan.
@MainActor
final class RemoteHold {
    /// The direction, and true as a hold begins (answered with whether the screen took it), false
    /// as it ends.
    private var onHold: ((Int, Bool) -> Bool)?
    /// How long a press is held before it scans instead of skipping.
    private static let after: Duration = .milliseconds(450)
    private var timer: Task<Void, Never>?
    private var holding: Int?
    /// The remote whose press is pending or held.
    private var owner: ObjectIdentifier?
    private var ended: (direction: Int, at: ContinuousClock.Instant)?
    private var observer: NSObjectProtocol?

    func start(_ onHold: @escaping (Int, Bool) -> Bool) {
        stop()
        self.onHold = onHold
        GCController.controllers().forEach(attach)
        observer = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for controller in GCController.controllers() {
            controller.microGamepad?.buttonA.pressedChangedHandler = nil
            controller.microGamepad?.reportsAbsoluteDpadValues = false
        }
        timer?.cancel()
        timer = nil
        owner = nil
        if let held = holding {
            holding = nil
            _ = onHold?(held, false)
        }
        ended = nil
        // The closure holds the player screen; let go, or each film opened keeps its player alive.
        onHold = nil
    }

    /// True for a move that belongs to a hold: one a remote may send while the press is held, and
    /// the one tvOS sends when it is let go (once). Neither is also a click.
    func swallows(_ direction: Int) -> Bool {
        if holding == direction { return true }
        guard let ended, ended.direction == direction else { return false }
        self.ended = nil
        return ContinuousClock.now - ended.at < .milliseconds(700)
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        pad.reportsAbsoluteDpadValues = true
        let source = ObjectIdentifier(controller)
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            let x = pad.dpad.xAxis.value
            MainActor.assumeIsolated { self?.pressed(pressed, x: x, from: source) }
        }
    }

    private func pressed(_ down: Bool, x: Float, from source: ObjectIdentifier) {
        // A second remote's release does not end the hold the first one is making.
        if !down, let owner, owner != source { return }
        timer?.cancel()
        timer = nil
        guard down else {
            owner = nil
            if let held = holding {
                holding = nil
                ended = (held, .now)
                _ = onHold?(held, false)
            }
            return
        }
        guard abs(x) > 0.5 else { return }
        owner = source
        let direction = x < 0 ? -1 : 1
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.after)
            guard let self, !Task.isCancelled else { return }
            // Only a hold the screen took is one: a refused one leaves its release a click.
            if self.onHold?(direction, true) == true { self.holding = direction }
        }
    }
}
