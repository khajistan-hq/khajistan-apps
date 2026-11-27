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
