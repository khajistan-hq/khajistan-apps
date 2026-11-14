import Foundation

/// The Receiver front's Surf: a live channel at random, and the list next and previous walk.
struct ShufflePick: Identifiable {
    let channel: Channel
    let list: [Channel]
    var surfChoice: SurfChoice? = nil
    var id: String { channel.id }
}

/// What Surf draws from (owner, 2026-10-07: "a shuffle feature for tv or radio with global
/// settings, main atlas or extended atlas settings"; 2026-10-29: all channels, "with an option to
/// choose tv only or radio only"). Kept on the device, in both apps.
enum ShuffleMedium: String, CaseIterable, Identifiable, Hashable, Sendable {
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

/// What kind of channel Surf draws (owner, 2026-11-04: "they are mostly news and boring and i need
/// more songs and dance and film and weird channels"). Read from each channel's genre tags, which
/// carry their evidence in the registry (machinery scripts/signal-room/apply_genres.py). A channel
/// with no tag is reachable under Any only.
enum SurfGenre: String, CaseIterable, Identifiable, Hashable, Sendable {
    // `songs` stays the stored value; the label is Music (owner, 2026-11-04).
    case any, songs, film, local
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Any"
        case .songs: return "Music"
        case .film: return "Film"
        case .local: return "Local"
        }
    }
    static let key = "kj.surf.genre"
    static func stored(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .any }

    func includes(_ genres: [String]?) -> Bool {
        let tags = Set(genres ?? [])
        switch self {
        case .any: return true
        case .songs: return tags.contains("music")
        case .film: return tags.contains("film") || tags.contains("drama")
        case .local: return tags.contains("local")
        }
    }
}

/// Where Surf draws from: the main atlas (the heartbeat and core regions), the extended atlas
/// (the regions behind "Beyond the atlas"), or everywhere.
enum ShuffleScope: String, CaseIterable, Identifiable, Hashable, Sendable {
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
                     medium: ShuffleMedium, scope: ShuffleScope, genre: SurfGenre = .any) -> [Channel] {
        let main = Set(index.regions.filter { ReceiverRules.tiersOnByDefault.contains($0.tier) }.map(\.id))
        var seen = Set<String>()
        var pool: [Channel] = []
        for (region, channels) in lists {
            for channel in channels where medium.includes(channel.mediaType) && genre.includes(channel.genres) {
                let filed = channel.regionIds.flatMap { $0.isEmpty ? nil : $0 } ?? [region]
                let inMain = !Set(filed).isDisjoint(with: main)
                let fits = scope == .everywhere || (scope == .main) == inMain
                if fits, seen.insert(channel.id).inserted { pool.append(channel) }
            }
        }
        return pool
    }

    /// Wait for every requested shard's bounded request. Returning after the first fast region
    /// silently shrank Surf to that region. Failed shards are explicit and cannot start a short
    /// repeat cycle; a later Surf request retries them through ReceiverStore.
    @MainActor
    static func catalogue(_ index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope,
                          genre: SurfGenre = .any,
                          load: @escaping @MainActor (String) async -> [Channel]?) async -> SurfCatalogue {
        let ids = regions(index, scope: scope)
        var lists: [String: [Channel]] = [:]
        var failed: [String] = []
        await withTaskGroup(of: (String, [Channel]?).self) { group in
            for id in ids { group.addTask { @MainActor in (id, await load(id)) } }
            for await (id, list) in group {
                if let list {
                    lists[id] = list
                } else {
                    failed.append(id)
                }
            }
        }
        let read = ids.compactMap { id in lists[id].map { (region: id, channels: $0) } }
        return SurfCatalogue(channels: pool(read, index: index, medium: medium, scope: scope, genre: genre),
                             missingRegions: failed.sorted())
    }

    @MainActor
    static func surf(_ index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope,
                     load: @escaping @MainActor (String) async -> [Channel]?) async -> [Channel] {
        await catalogue(index, medium: medium, scope: scope, load: load).channels.shuffled()
    }
}

struct SurfChoice: Hashable {
    let medium: ShuffleMedium
    let scope: ShuffleScope
    var genre: SurfGenre = .any
}

struct SurfCatalogue {
    let channels: [Channel]
    let missingRegions: [String]
    var isComplete: Bool { missingRegions.isEmpty }
}

/// Stable channel IDs, not regions or stream URLs, define one complete visit cycle.
/// A changed catalogue adds unseen IDs and removes unavailable ones without forgetting visits.
struct SurfCycle {
    private var visited = Set<String>()
    private var remaining: [String] = []
    private var last: String?

    mutating func visit(_ id: String) {
        visited.insert(id)
        remaining.removeAll { $0 == id }
        last = id
    }

    mutating func next(in channels: [Channel], allowNewCycle: Bool) -> Channel? {
        var byID: [String: Channel] = [:]
        for channel in channels where byID[channel.id] == nil { byID[channel.id] = channel }
        remaining.removeAll { byID[$0] == nil || visited.contains($0) }
        let queued = Set(remaining)
        remaining += byID.keys.filter { !visited.contains($0) && !queued.contains($0) }.shuffled()
        if remaining.isEmpty, allowNewCycle, !byID.isEmpty {
            visited.removeAll()
            remaining = Array(byID.keys).shuffled()
            // Finish one cycle and start another without the same channel twice in a row.
            if remaining.count > 1, remaining.first == last { remaining.swapAt(0, 1) }
        }
        guard let id = remaining.first, let channel = byID[id] else { return nil }
        visit(id)
        return channel
    }
}

/// Held by the TV app, so closing and reopening Surf does not reshuffle already visited channels.
struct SurfHistory {
    private var cycles: [SurfChoice: SurfCycle] = [:]
    private var catalogues: [SurfChoice: SurfCatalogue] = [:]

    mutating func update(_ catalogue: SurfCatalogue, for choice: SurfChoice) {
        catalogues[choice] = catalogue
    }

    mutating func next(for choice: SurfChoice) -> Channel? {
        guard let catalogue = catalogues[choice] else { return nil }
        return cycles[choice, default: SurfCycle()].next(in: catalogue.channels, allowNewCycle: catalogue.isComplete)
    }

    mutating func visit(_ channel: Channel, for choice: SurfChoice) {
        cycles[choice, default: SurfCycle()].visit(channel.id)
    }

    /// The next channel not in `skipping`, and the walk as it would stand once it is visited,
    /// asked without changing this walk. Skipped channels are spent in the plan, and a new cycle
    /// the plan starts is in it. Nil when no channel is left, even after a new cycle.
    func plan(for choice: SurfChoice, skipping: Set<String>) -> (channel: Channel, cycle: SurfCycle)? {
        guard let catalogue = catalogues[choice] else { return nil }
        var cycle = cycles[choice, default: SurfCycle()]
        // Two passes: the rest of this cycle, then a whole new one, which reaches every channel.
        for _ in 0..<(2 * catalogue.channels.count) {
            guard let channel = cycle.next(in: catalogue.channels, allowNewCycle: catalogue.isComplete) else { return nil }
            if !skipping.contains(channel.id) { return (channel, cycle) }
        }
        return nil
    }

    /// Carries out a plan: the walk becomes the one the plan left.
    mutating func take(_ cycle: SurfCycle, for choice: SurfChoice) {
        cycles[choice] = cycle
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
