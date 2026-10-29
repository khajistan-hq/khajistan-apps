import Foundation

/// The Receiver front's Surf: a live channel at random, and the list next and previous walk.
struct ShufflePick: Identifiable {
    let channel: Channel
    let list: [Channel]
    var id: String { channel.id }
}

/// What Surf draws from (owner, 2026-10-07: "a shuffle feature for tv or radio with global
/// settings, main atlas or extended atlas settings"; 2026-10-29: all channels, "with an option to
/// choose tv only or radio only"). Kept on the device, in both apps.
enum ShuffleMedium: String, CaseIterable, Identifiable, Sendable {
    case all, tv, radio
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .tv: return "TV only"
        case .radio: return "Radio only"
        }
    }
    static let key = "kj.shuffle.medium"
    static func stored(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .all }

    func includes(_ mediaType: String) -> Bool {
        self == .all ? mediaType == "tv" || mediaType == "radio" : mediaType == rawValue
    }
}

/// Where Surf draws from: the main atlas (the heartbeat and core regions), the extended atlas
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
    static func stored(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .main }

    func includes(tier: String) -> Bool {
        switch self {
        case .main: return ReceiverRules.tiersOnByDefault.contains(tier)
        case .extended: return !ReceiverRules.tiersOnByDefault.contains(tier)
        case .everywhere: return true
        }
    }
}

extension ShufflePick {
    /// The regions whose lists Surf reads for `scope`: each one in it that has a list.
    static func regions(_ index: ReceiverIndex, scope: ShuffleScope) -> [String] {
        index.listedRegions.filter { scope.includes(tier: $0.tier) }.map(\.id)
    }

    /// Every channel Surf may land on, each once, in list order (owner, 2026-10-29: "true surf").
    /// A channel filed to any main-atlas region is a main-atlas signal, even where an extension
    /// lists it too (2026-09-03), so Extended takes only channels filed nowhere in the main atlas.
    static func pool(_ lists: [(region: String, channels: [Channel])], index: ReceiverIndex,
                     medium: ShuffleMedium, scope: ShuffleScope) -> [Channel] {
        let main = Set(index.regions.filter { ReceiverRules.tiersOnByDefault.contains($0.tier) }.map(\.id))
        var seen = Set<String>()
        var pool: [Channel] = []
        for (region, channels) in lists {
            for channel in channels where medium.includes(channel.mediaType) {
                let inMain = !Set(channel.regionIds ?? [region]).isDisjoint(with: main)
                let fits = scope == .everywhere || (scope == .main) == inMain
                if fits, seen.insert(channel.id).inserted { pool.append(channel) }
            }
        }
        return pool
    }

    /// How long Surf waits for the slowest list once another has come: past it, Surf plays from
    /// what has come, and a list still on its way is read (and kept) by the next surf.
    static let patience: Duration = .seconds(4)

    /// Reads every list in `scope` at once and returns the pool shuffled: Surf plays the first,
    /// and next and previous walk the rest, so one surf crosses the whole of the scope rather than
    /// one region. A list that will not load, or is still loading after `patience`, is left out;
    /// the others still surf.
    @MainActor
    static func surf(_ index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope,
                     patience: Duration = patience,
                     load: @escaping @MainActor (String) async -> [Channel]?) async -> [Channel] {
        let ids = regions(index, scope: scope)
        guard !ids.isEmpty else { return [] }
        var lists: [String: [Channel]] = [:]
        await withTaskGroup(of: (String, [Channel]?)?.self) { group in
            for id in ids { group.addTask { @MainActor in (id, await load(id)) } }
            // The clock: answers nil when the patience runs out.
            group.addTask { try? await Task.sleep(for: patience); return nil }
            var answered = 0
            var waitedLongEnough = false
            for await result in group {
                if let (id, list) = result {
                    answered += 1
                    lists[id] = list
                } else {
                    waitedLongEnough = true
                }
                if answered == ids.count || (waitedLongEnough && !lists.isEmpty) {
                    group.cancelAll()
                    break
                }
            }
        }
        let read = ids.compactMap { id in lists[id].map { (region: id, channels: $0) } }
        return pool(read, index: index, medium: medium, scope: scope).shuffled()
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
