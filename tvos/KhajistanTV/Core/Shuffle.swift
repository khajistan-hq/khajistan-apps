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

/// What Shuffle draws from (owner, 2026-10-07: "a shuffle feature for tv or radio with global
/// settings, main atlas or extended atlas settings"). Kept on the device, in both apps.
enum ShuffleMedium: String, CaseIterable, Identifiable, Sendable {
    case tv, radio
    var id: String { rawValue }
    var label: String { self == .tv ? "Television" : "Radio" }
    static let key = "kj.shuffle.medium"
}

/// Where Shuffle draws from: the main atlas (the heartbeat and core regions), the extended atlas
/// (the regions behind "Beyond the atlas"), or everywhere.
enum ShuffleScope: String, CaseIterable, Identifiable, Sendable {
    case main, extended, everywhere
    var id: String { rawValue }
    var label: String {
        switch self {
        case .main: return "Main atlas"
        case .extended: return "Extended atlas"
        case .everywhere: return "Everywhere"
        }
    }
    static let key = "kj.shuffle.scope"

    func includes(tier: String) -> Bool {
        switch self {
        case .main: return ReceiverRules.tiersOnByDefault.contains(tier)
        case .extended: return !ReceiverRules.tiersOnByDefault.contains(tier)
        case .everywhere: return true
        }
    }
}

extension ShufflePick {
    /// Each region in `scope` that has a shard, weighted by how many channels of `medium` it
    /// carries, in index order. A region with none of that medium weighs nothing.
    static func weights(_ index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope) -> [(String, Int)] {
        index.listedRegions
            .filter { scope.includes(tier: $0.tier) }
            .map { ($0.id, index.regionCounts[$0.id]?.byMedium[medium.rawValue] ?? 0) }
    }
}

/// The Receiver's Cameras: every region with a camera list, the main atlas first, then the
/// extensions, each in index order (owner, 2026-10-07: "make cctv show up in the reciever").
enum CameraRegions {
    static func ordered(_ index: ReceiverIndex) -> [ReceiverIndex.Region] {
        let withCameras = index.regions.filter { index.cameraURL(regionId: $0.id) != nil }
        let main = withCameras.filter { ReceiverRules.tiersOnByDefault.contains($0.tier) }
        return main + withCameras.filter { !ReceiverRules.tiersOnByDefault.contains($0.tier) }
    }

    /// How many cameras the index counts in all, for the section's heading.
    static func total(_ index: ReceiverIndex) -> Int {
        ordered(index).reduce(0) { $0 + (index.regionCounts[$1.id]?.byMedium["camera"] ?? 0) }
    }
}
