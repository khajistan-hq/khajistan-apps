import Foundation

/// Which pigeon flight a channel change gets, as plain arithmetic so it can be tested (the
/// renderer that flies it is in Player/PigeonOverlay.swift).
enum FlightChoice {
    /// Seconds a flight should outlast the expected tune, so the cut lands under the bird.
    static let margin = 0.5

    /// The flights long enough to cover `expected` seconds, those within a second of the
    /// shortest; when none is long enough, the longest alone. In the order given.
    static func pool(_ flights: [(name: String, length: Double)], expected: Double) -> [String] {
        let fits = flights.filter { $0.length >= expected + margin }
        guard let shortest = fits.map(\.length).min() else {
            return flights.max { $0.length < $1.length }.map { [$0.name] } ?? []
        }
        return fits.filter { $0.length <= shortest + 1.0 }.map(\.name)
    }

    /// The flight after `last` in the pool's order, so every flight in a pool of any size takes
    /// its turn and none flies twice running while another is there.
    static func next(in pool: [String], after last: String?) -> String? {
        guard !pool.isEmpty else { return nil }
        guard let last, let at = pool.firstIndex(of: last) else { return pool[0] }
        return pool[(at + 1) % pool.count]
    }

    /// Whether a channel that is ready cuts now, `elapsed` seconds into a flight whose wing covers
    /// at least half the screen during `covered`: now, inside a covered stretch; not yet, if one
    /// is still to come; now, if none is left (or the flight never covers half). Before
    /// 2026-10-07 a ready channel waited for the last stretch alone, up to 4 s on Swerve and 8 s
    /// on Loop with the new picture already playing behind the bird.
    static func shouldCut(elapsed: Double, covered: [ClosedRange<Double>]) -> Bool {
        if covered.contains(where: { $0.contains(elapsed) }) { return true }
        return !covered.contains(where: { $0.lowerBound > elapsed })
    }

    /// The running tune time: half the old, half the new; the first reading stands alone.
    static func blend(_ before: Double?, _ seconds: Double) -> Double {
        before.map { $0 * 0.5 + seconds * 0.5 } ?? seconds
    }
}
