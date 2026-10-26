import Foundation

/// The Receiver front's Shuffle: one card from the deck, and the deck order the screen steps through.
struct ShufflePick: Identifiable {
    let channel: Channel
    let list: [Channel]
    var id: String { channel.id }
}

/// mulberry32, with the arithmetic done in `UInt32` so it matches JavaScript's `Math.imul` and `>>>`.
/// `nextUnit()` is a Double in [0, 1).
struct Mulberry32: Sendable {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func nextWord() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        let mixed = (t ^ (t >> 7)) &* (t | 61)
        t = t ^ (t &+ mixed)
        return t ^ (t >> 14)
    }

    mutating func nextUnit() -> Double {
        Double(nextWord()) / 4294967296
    }
}

/// One channel the deck may deal. `offline` is the health and denylist grade already decided by
/// `ReceiverRules.eligible`; the deck does not read country, language, genre or search text.
struct ShuffleEntry: Equatable, Sendable {
    var id: String
    var regionId: String
    var tier: String
    var medium: String
    var offline: Bool = false
}

/// The card dealt, and the permutation it came from.
struct ShuffleDraw: Equatable, Sendable {
    var id: String
    var order: [String]
}

/// One Fisher-Yates deck for a medium, a scope and a region.
///
/// The permutation is dealt from the front. When it is used up, a new one is dealt. If that deck
/// has more than one channel and its first card is the channel already playing, index 0 swaps with
/// index 1. That swap is the whole of the boundary rule: there is no second shuffle and no extra
/// random number. A channel already playing when a deck is first built counts the same way.
/// One playable channel may repeat. None deals nothing.
struct ShuffleDeck: Sendable {
    private var rng: Mulberry32
    private var key: String?
    private var order: [String] = []
    private var cursor = 0
    private var observed: String?

    init(seed: UInt32) {
        rng = Mulberry32(seed: seed)
    }

    /// The live receiver. Tests pass a seed so the deal can be compared with the website.
    init() {
        self.init(seed: UInt32.random(in: .min ..< .max))
    }

    /// The channel last dealt, or the one the screen reported with `observe`.
    var lastPlayed: String? { observed }

    /// The channel now on screen. A later deal treats it as already playing.
    mutating func observe(_ id: String) {
        observed = id
    }

    /// True when `ids` is the permutation now being dealt, in that order.
    func plays(_ ids: [String]) -> Bool {
        !order.isEmpty && ids == order
    }

    /// The next card. `playing` is the channel on screen. Nil leaves the cursor where the last
    /// deal put it, and a new deck then avoids `observed` instead.
    mutating func draw(entries: [ShuffleEntry], medium: ShuffleMedium, scope: ShuffleScope, regionId: String?, playing: String?) -> ShuffleDraw? {
        let ids = Self.playableIDs(entries, medium: medium, scope: scope, regionId: regionId)
        let nextKey = Self.deckKey(medium: medium, scope: scope, regionId: regionId)
        guard !ids.isEmpty else {
            key = nextKey
            order = []
            cursor = 0
            return nil
        }
        if !samePool(key: nextKey, ids: ids) {
            key = nextKey
            order = Self.avoidFirst(Self.permute(ids, rng: &rng), lastPlayed: playing ?? observed)
            cursor = 0
        } else if let playing, let index = order.firstIndex(of: playing) {
            cursor = index + 1
        }
        if cursor >= order.count {
            let last = playing ?? observed ?? order.last
            order = Self.avoidFirst(Self.permute(ids, rng: &rng), lastPlayed: last)
            cursor = 0
        }
        let id = order[cursor]
        cursor += 1
        observed = id
        return ShuffleDraw(id: id, order: order)
    }

    /// Playable ids in list order. The first copy of an id is the one that counts.
    static func playableIDs(_ entries: [ShuffleEntry], medium: ShuffleMedium, scope: ShuffleScope, regionId: String?) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        let selected = Self.selectedRegion(regionId)
        for entry in entries {
            if entry.offline || entry.medium != medium.rawValue || seen.contains(entry.id) { continue }
            seen.insert(entry.id)
            switch scope {
            case .main:
                if !ReceiverRules.tiersOnByDefault.contains(entry.tier) { continue }
            case .region:
                if selected == nil || entry.regionId != selected { continue }
            case .beyond:
                if let selected {
                    if entry.regionId != selected { continue }
                } else if ReceiverRules.tiersOnByDefault.contains(entry.tier) {
                    continue
                }
            }
            ids.append(entry.id)
        }
        return ids
    }

    /// The shards a scope has to load, in index order. A region with no shard is not among them.
    /// Main is the heartbeat and core regions. Region is the selected region, whatever its tier.
    /// Beyond with a selected region is that region. Beyond with none is the extension regions.
    static func regionIds(index: ReceiverIndex, scope: ShuffleScope, selected: String?) -> [String] {
        let listed = index.listedRegions
        let chosen = selectedRegion(selected)
        switch scope {
        case .main:
            return listed.filter { ReceiverRules.tiersOnByDefault.contains($0.tier) }.map(\.id)
        case .region:
            guard let chosen, listed.contains(where: { $0.id == chosen }) else { return [] }
            return [chosen]
        case .beyond:
            if let chosen {
                return listed.contains(where: { $0.id == chosen }) ? [chosen] : []
            }
            return listed.filter { !ReceiverRules.tiersOnByDefault.contains($0.tier) }.map(\.id)
        }
    }

    private static func selectedRegion(_ regionId: String?) -> String? {
        guard let regionId, !regionId.isEmpty, regionId != "all" else { return nil }
        return regionId
    }

    private static func deckKey(medium: ShuffleMedium, scope: ShuffleScope, regionId: String?) -> String {
        "\(medium.rawValue)|\(scope.rawValue)|\(selectedRegion(regionId) ?? "")"
    }

    private func samePool(key nextKey: String, ids: [String]) -> Bool {
        guard key == nextKey, order.count == ids.count else { return false }
        let have = Set(order)
        return ids.allSatisfy { have.contains($0) }
    }

    /// i runs from n-1 down to 1. There is no draw at i = 0.
    private static func permute(_ ids: [String], rng: inout Mulberry32) -> [String] {
        var shuffled = ids
        guard shuffled.count > 1 else { return shuffled }
        var i = shuffled.count - 1
        while i > 0 {
            let j = Int(rng.nextUnit() * Double(i + 1))
            shuffled.swapAt(i, j)
            i -= 1
        }
        return shuffled
    }

    /// The channel already playing moves off the front by swapping with the second card.
    private static func avoidFirst(_ order: [String], lastPlayed: String?) -> [String] {
        var order = order
        if order.count > 1, let lastPlayed, order[0] == lastPlayed {
            order.swapAt(0, 1)
        }
        return order
    }
}

/// What Shuffle draws: television or radio. Kept on the device, in both apps.
enum ShuffleMedium: String, CaseIterable, Identifiable, Sendable {
    case tv, radio
    var id: String { rawValue }
    var label: String { self == .tv ? "Television" : "Radio" }
    /// "television" or "radio" inside a sentence.
    var sentence: String { self == .tv ? "television" : "radio" }
    static let key = "kj.shuffle.medium"
}

/// Where Shuffle draws. Main is the main atlas. Region is the selected region. Beyond is that
/// region when one is selected, and the extension channels when none is.
enum ShuffleScope: String, CaseIterable, Identifiable, Sendable {
    case main, region, beyond
    var id: String { rawValue }
    var label: String {
        switch self {
        case .main: return "Main atlas"
        case .region: return "Region"
        case .beyond: return "Beyond"
        }
    }
    static let key = "kj.shuffle.scope"

    /// A value saved by an older build: "extended" is Beyond, and "everywhere" is the main atlas.
    static func resolved(_ raw: String?) -> ShuffleScope {
        switch raw {
        case Self.region.rawValue: return .region
        case Self.beyond.rawValue, "extended": return .beyond
        default: return .main
        }
    }

    /// Said when the scope has nothing left that can play. A selected region wins over Beyond,
    /// so Beyond then says "this region" too.
    func emptyNote(medium: ShuffleMedium, regionSelected: Bool) -> String {
        switch self {
        case .main:
            return "No \(medium.sentence) to surf on the main atlas right now."
        case .region:
            return "No \(medium.sentence) in this region right now."
        case .beyond:
            if regionSelected {
                return "No \(medium.sentence) in this region right now."
            }
            return "No \(medium.sentence) beyond the atlas right now."
        }
    }
}

/// The deck the two apps share, and the note when a scope has nothing to play.
/// The apps use it from the main actor.
final class ShuffleSession {
    static let regionKey = "kjregion"
    static let defaultRegionId = "indus"

    private var deck: ShuffleDeck
    private var selection = ""
    /// Why the last draw found nothing.
    private(set) var note: String?
    /// True when the scope has no playable channel, until the medium, the scope or the region changes.
    private(set) var blocked = false

    init(seed: UInt32) {
        deck = ShuffleDeck(seed: seed)
    }

    init() {
        deck = ShuffleDeck()
    }

    /// The region on screen: an open region page, then the one the strip last rested on, then Indus,
    /// which is where the strip starts.
    static func currentRegion(stored: String?, openRegion: String?) -> String {
        if let openRegion, !openRegion.isEmpty, openRegion != "all" { return openRegion }
        if let stored, !stored.isEmpty, stored != "all" { return stored }
        return defaultRegionId
    }

    func settings(openRegion: String? = nil, defaults: UserDefaults = .standard) -> (medium: ShuffleMedium, scope: ShuffleScope, regionId: String) {
        let medium = defaults.string(forKey: ShuffleMedium.key).flatMap(ShuffleMedium.init(rawValue:)) ?? .tv
        let scope = ShuffleScope.resolved(defaults.string(forKey: ShuffleScope.key))
        let regionId = Self.currentRegion(stored: defaults.string(forKey: Self.regionKey), openRegion: openRegion)
        return (medium, scope, regionId)
    }

    /// The medium, the scope or the region changed, so a scope that had nothing can be tried again.
    func noteSelectionChanged() {
        blocked = false
        note = nil
    }

    /// The channel now on screen. The next deck treats it as already playing.
    func observe(_ id: String) {
        deck.observe(id)
    }

    /// True when the player's list is the deck's current order, so the step past the end deals again.
    func plays(_ ids: [String]) -> Bool {
        deck.plays(ids)
    }

    /// The next card of this medium and scope.
    ///
    /// `load` returns one region's channels. The store has already applied `ReceiverRules.eligible`,
    /// which drops a channel the health feed or the denylist has taken off air. A load that throws
    /// is reported and the deck is left as it was. An empty pool sets `blocked` and `note`.
    func pick(index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope, regionId: String?, playingId: String?, load: (String) async throws -> [Channel]) async -> ShufflePick? {
        let selectionKey = "\(medium.rawValue)|\(scope.rawValue)|\(regionId ?? "")"
        if selectionKey != selection {
            selection = selectionKey
            blocked = false
        }
        if blocked { return nil }
        let regionSelected = regionId.map { !$0.isEmpty && $0 != "all" } ?? false
        let ids = ShuffleDeck.regionIds(index: index, scope: scope, selected: regionId)
        guard !ids.isEmpty else {
            _ = deck.draw(entries: [], medium: medium, scope: scope, regionId: regionId, playing: playingId)
            note = scope.emptyNote(medium: medium, regionSelected: regionSelected)
            blocked = true
            return nil
        }
        var entries: [ShuffleEntry] = []
        var byID: [String: Channel] = [:]
        var seen = Set<String>()
        for id in ids {
            let channels: [Channel]
            do {
                channels = try await load(id)
            } catch {
                note = error.localizedDescription
                return nil
            }
            let tier = index.regions.first { $0.id == id }?.tier ?? ""
            for channel in channels where channel.mediaType == medium.rawValue {
                guard seen.insert(channel.id).inserted else { continue }
                entries.append(ShuffleEntry(id: channel.id, regionId: id, tier: tier, medium: channel.mediaType, offline: false))
                byID[channel.id] = channel
            }
        }
        // No channel was named: the one already on screen, or the last card dealt, counts.
        guard let dealt = deck.draw(entries: entries, medium: medium, scope: scope, regionId: regionId, playing: playingId ?? deck.lastPlayed) else {
            note = scope.emptyNote(medium: medium, regionSelected: regionSelected)
            blocked = true
            return nil
        }
        let list = dealt.order.compactMap { byID[$0] }
        guard let channel = byID[dealt.id], list.count == dealt.order.count else { return nil }
        note = nil
        blocked = false
        return ShufflePick(channel: channel, list: list)
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
