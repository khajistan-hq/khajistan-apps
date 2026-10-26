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
/// `beyond` is false for a main-atlas channel, including one that is also filed to an extension
/// region. `regionIds` is every region the channel is filed to.
struct ShuffleEntry: Equatable, Sendable {
    var id: String
    var regionIds: [String]
    var beyond: Bool
    var medium: String
    var offline: Bool = false
}

/// The card dealt, and the permutation it came from.
struct ShuffleDraw: Equatable, Sendable {
    var id: String
    var order: [String]
}

/// One Fisher-Yates deck for a medium and a scope.
///
/// The permutation is dealt from the front. The first deck is not rearranged. When it is used
/// up, the same generator deals another. If that deck has more than one channel and its first
/// card is the last id drawn, index 0 swaps with index 1. There is no second shuffle and no
/// extra random number.
///
/// A directory or remote pick is not a draw and does not move the cursor. If the card at the
/// cursor is the channel already playing and the pool has more than one channel, that card is
/// skipped and the next one is drawn. If the skip uses the deck up, the reshuffle treats the
/// playing channel as the last id drawn. One playable channel may repeat. None deals nothing.
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

    /// The channel now on screen. This is not a draw and does not move the cursor.
    mutating func observe(_ id: String) {
        observed = id
    }

    /// The player stepped past the end of the permutation on screen. The next draw deals another,
    /// and `id` (the last card of that permutation) is the last id drawn.
    mutating func noteListEnded(on id: String) {
        observed = id
        guard !order.isEmpty, order.last == id else { return }
        cursor = order.count
    }

    /// True when `ids` is the permutation now being dealt, in that order.
    func plays(_ ids: [String]) -> Bool {
        !order.isEmpty && ids == order
    }

    /// The next card. `playing` is the channel on screen. A pick of that channel is not a draw.
    /// When it is the card at the cursor and the pool has more than one channel, it is skipped.
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
            order = Self.permute(ids, rng: &rng)
            cursor = 0
        }
        // The card at the cursor is the one already on screen: skip it. Do not search the deck
        // for that channel, and do not skip again after a reshuffle.
        var skippedPlaying = false
        if let playing, order.count > 1, cursor < order.count, order[cursor] == playing {
            cursor += 1
            skippedPlaying = true
        }
        if cursor >= order.count {
            let lastDrawn: String? = skippedPlaying ? playing : order.last
            order = Self.avoidFirst(Self.permute(ids, rng: &rng), lastPlayed: lastDrawn)
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
                if entry.beyond { continue }
            case .region:
                guard let selected, entry.regionIds.contains(selected) else { continue }
            case .beyond:
                if !entry.beyond { continue }
            }
            ids.append(entry.id)
        }
        return ids
    }

    /// The shards a scope has to load, in index order. A region with no shard is not among them.
    /// Main is the heartbeat and core regions. Region is the selected region, whatever its tier.
    /// Beyond is the extension regions. A selected region does not narrow it.
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

    /// On a reshuffle, the last id drawn moves off the front by swapping with the second card.
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

/// Where Shuffle draws. Main is every main-atlas channel. Region is the channels filed to the
/// selected region. Beyond is only the channels outside the main atlas. A selected region does
/// not narrow Beyond.
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

    /// Said when the scope has nothing left that can play.
    func emptyNote(medium: ShuffleMedium, regionSelected _: Bool) -> String {
        switch self {
        case .main:
            return "No \(medium.sentence) to surf on the main atlas right now."
        case .region:
            return "No \(medium.sentence) in this region right now."
        case .beyond:
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

    /// The channel now on screen. A directory or remote pick is not a draw and does not move the cursor.
    func observe(_ id: String) {
        deck.observe(id)
    }

    /// The player stepped past the end of the permutation Surf dealt. The next draw deals another.
    func noteListEnded(on id: String) {
        deck.noteListEnded(on: id)
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
            for channel in channels where channel.mediaType == medium.rawValue {
                guard seen.insert(channel.id).inserted else { continue }
                let filed = (channel.regionIds?.isEmpty == false) ? channel.regionIds! : [id]
                let beyond = !filed.contains { regionId in
                    guard let region = index.regions.first(where: { $0.id == regionId }) else { return false }
                    return ReceiverRules.tiersOnByDefault.contains(region.tier)
                }
                entries.append(ShuffleEntry(id: channel.id, regionIds: filed, beyond: beyond, medium: channel.mediaType, offline: false))
                byID[channel.id] = channel
            }
        }
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
