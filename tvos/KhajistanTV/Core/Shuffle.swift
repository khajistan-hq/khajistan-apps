import Foundation

/// The Receiver front's Shuffle: a live channel at random, and the list it surfs in.
struct ShufflePick: Identifiable {
    let channel: Channel
    let list: [Channel]
    var id: String { channel.id }

    /// A region drawn in proportion to how much it has live, so the shuffle lands where the
    /// receiver is busiest without leaving out a quiet region. `roll(n)` is a number in 0..<n.
    static func region(_ weights: [(String, Int)], roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        let total = weights.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return nil }
        var left = roll(total)
        for (id, weight) in weights where weight > 0 {
            if left < weight { return id }
            left -= weight
        }
        return nil
    }
}
