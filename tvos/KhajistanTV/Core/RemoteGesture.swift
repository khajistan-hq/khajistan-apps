import Foundation

/// Tells a swipe on the remote's touch surface from a press of one of its arrows. tvOS hands
/// SwiftUI the same move command for both, so the screen also watches the finger (a pan
/// recogniser on indirect touches, Views/RemoteSwipe.swift) and asks here which one a move was.
/// A move that comes while, or just after, the finger has travelled is a swipe; a move with the
/// finger still (a click on the ring, an edge tap) is a press.
enum RemoteGesture {
    enum Kind: Equatable { case swipe, press }

    /// The finger's latest touch: how far it has moved up or down from where it came down, in the
    /// pan recogniser's points (down is positive), and when it last moved (seconds, any one clock).
    struct Pan: Equatable {
        var travel: Double
        var at: TimeInterval
    }

    // The three numbers below are first values and are tuned on the device: the simulator and
    // XCUIRemote send presses only, never a finger.

    /// Travel under this is a thumb settling on the clickpad as it presses, not a swipe.
    static let threshold: Double = 120
    /// How long after the finger last moved a move command still belongs to that swipe. The
    /// Apple TV HD's main thread runs near 30 Hz under a picture, so this is generous.
    static let window: TimeInterval = 0.5
    /// In the guide, each further row a swipe moves costs this much more travel.
    static let rowTravel: Double = 200

    static func classify(moveAt: TimeInterval, lastPan: Pan?) -> Kind {
        guard let pan = lastPan, abs(pan.travel) >= threshold, moveAt - pan.at <= window else { return .press }
        return .swipe
    }

    /// The rows a swipe has earned since the finger came down: none under the threshold, one at
    /// it, and one more per `rowTravel` after; negative upwards. The screen moves the difference
    /// from what it has already moved, so there is no inertia after the finger lifts.
    static func rows(travel: Double) -> Int {
        guard abs(travel) >= threshold else { return 0 }
        let rows = 1 + Int((abs(travel) - threshold) / rowTravel)
        return travel < 0 ? -rows : rows
    }
}

/// What the remote does in the two players (owner, 2026-11-28, on Fable's advice: "use all like
/// how apple tv usually has so people can use it intuitively"). A direction means one thing,
/// whether it came from a swipe on the touch surface or a press of an arrow: down opens the
/// guide and is the only thing that does, up lights the controls, left and right change channel.
/// A click is the next channel and a double click a random one (owner, the same day: "make a
/// click change a channel and double click to randomize").
/// With the guide open the guide reads the remote itself; this map is the picture and the strip.
enum RemoteMap {
    enum Input: Equatable { case up, down, left, right, click, doubleClick }
    enum Context: Equatable {
        /// The picture, with or without the strip showing, and no control lit.
        case picture
        /// A control on the strip is lit.
        case controls
    }
    enum Action: Equatable {
        case openGuide, lightControls, letGo, previousChannel, nextChannel, randomChannel
        /// Along the strip's controls: -1 towards the first, 1 towards the last.
        case walk(Int)
        /// Works the lit control, at once.
        case work
        case none
    }

    static func action(_ input: Input, in context: Context) -> Action {
        switch (context, input) {
        case (.picture, .down): return .openGuide
        case (.picture, .up): return .lightControls
        case (.picture, .left): return .previousChannel
        case (.picture, .right), (.picture, .click): return .nextChannel
        case (.picture, .doubleClick): return .randomChannel
        case (.controls, .left): return .walk(-1)
        case (.controls, .right): return .walk(1)
        case (.controls, .down): return .letGo
        case (.controls, .up): return .none
        // A lit control is worked by every click; there is nothing to wait for.
        case (.controls, .click), (.controls, .doubleClick): return .work
        }
    }

    /// A channel other than the one playing, by a roll in 0..<1; nil when there is no other.
    static func random<T: Equatable>(from all: [T], not current: T, roll: Double) -> T? {
        let others = all.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        return others[min(others.count - 1, max(0, Int(roll * Double(others.count))))]
    }
}

/// Tells a double click from a single one. A click starts a wait of `window`; a second click
/// inside it is a double click, and a wait that runs out is a single click. The screen keeps the
/// clock: it calls `click(at:)`, sleeps `window`, then asks `settle(_:)` with the same time.
struct ClickTally: Equatable {
    /// Under the pigeon's flight, so the wait is not felt as a slow channel change.
    static let window: TimeInterval = 0.3
    enum Outcome: Equatable { case wait, double }
    private(set) var pending: TimeInterval?

    mutating func click(at time: TimeInterval) -> Outcome {
        if let first = pending, time - first <= Self.window {
            pending = nil
            return .double
        }
        pending = time
        return .wait
    }

    /// True when the click made at `time` still stands alone: it is a single click, and is spent.
    mutating func settle(_ time: TimeInterval) -> Bool {
        guard pending == time else { return false }
        pending = nil
        return true
    }
}
