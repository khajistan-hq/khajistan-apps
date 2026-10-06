import Foundation

/// Which pigeon flight carries a channel change, given how long the channel is expected to take.
/// Kept apart from the players so the rule can be tested on its own.
enum FlightChoice {
    /// The shortest flight that lasts at least `want` seconds, turning (by `turn`) among those
    /// within a second of it, never `exclude` (the one that just flew). Past due (`want` <= 0)
    /// that is the shortest, so the picture gets its next chance soonest; longer than every
    /// flight, the longest, and the flights chain.
    static func pick<F: Hashable>(_ flights: [F], lengths: [F: Double], want: Double, exclude: F?, turn: Int) -> F? {
        let options = flights.filter { $0 != exclude }
        guard !options.isEmpty else { return flights.first }
        let length = { (f: F) in lengths[f] ?? 4 }
        let byLength = options.sorted { length($0) < length($1) }
        let target = byLength.first { length($0) >= want } ?? byLength.last!
        let near = byLength.filter { abs(length($0) - length(target)) < 1 }
        return near[((turn % near.count) + near.count) % near.count]
    }
}
