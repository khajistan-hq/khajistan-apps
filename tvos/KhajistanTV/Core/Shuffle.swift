import Foundation

/// The Receiver front's Shuffle: one card from the deck, and the deck order the screen steps through.
/// `medium`, `scope` and `regionId` are the deck this card came from. The player keeps them
/// with the list, so the step off the end deals that deck and not whatever the chips say now.
struct ShufflePick: Identifiable {
    let channel: Channel
    let list: [Channel]
    let medium: ShuffleMedium
    let scope: ShuffleScope
    let regionId: String?
    var id: String { channel.id }

    var deck: ShuffleDeckRef {
        ShuffleDeckRef(medium: medium, scope: scope, regionId: regionId)
    }
}

/// Which deck a list was dealt from. Nil on the player means the list is a shelf opened by hand.
struct ShuffleDeckRef: Equatable {
    var medium: ShuffleMedium
    var scope: ShuffleScope
    var regionId: String?

    var key: String {
        ShuffleDeck.deckKey(medium: medium, scope: scope, regionId: regionId)
    }
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
/// Each key keeps its own order, cursor and mulberry32 stream. Main and Beyond are keyed by
/// medium and scope, so a region change leaves them where they were. Region includes the
/// selected region. Coming back to a key resumes it. The streams do not feed each other.
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
    private struct Hand {
        var rng: Mulberry32
        var order: [String] = []
        var cursor = 0
    }

    private let seed: UInt32
    private var hands: [String: Hand] = [:]
    private var observed: String?

    init(seed: UInt32) {
        self.seed = seed
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

    /// The player stepped past the end of the deck named by `key`. The next draw of that deck
    /// deals another, and `id` is the last id drawn. A deck with the same order and a different
    /// key is left alone.
    mutating func noteListEnded(on id: String, key: String) {
        observed = id
        guard var hand = hands[key] else { return }
        guard hand.order.last == id else { return }
        hand.cursor = hand.order.count
        hands[key] = hand
    }

    /// The next card. `playing` is the channel on screen. A pick of that channel is not a draw.
    /// When it is the card at the cursor and the pool has more than one channel, it is skipped.
    mutating func draw(entries: [ShuffleEntry], medium: ShuffleMedium, scope: ShuffleScope, regionId: String?, playing: String?) -> ShuffleDraw? {
        let ids = Self.playableIDs(entries, medium: medium, scope: scope, regionId: regionId)
        let nextKey = Self.deckKey(medium: medium, scope: scope, regionId: regionId)
        var hand = hands[nextKey] ?? Hand(rng: Mulberry32(seed: seed))
        guard !ids.isEmpty else {
            hand.order = []
            hand.cursor = 0
            hands[nextKey] = hand
            return nil
        }
        if !Self.samePool(hand.order, ids) {
            hand.order = Self.permute(ids, rng: &hand.rng)
            hand.cursor = 0
        }
        // The card at the cursor is the one already on screen: skip it. Do not search the deck
        // for that channel, and do not skip again after a reshuffle.
        var skippedPlaying = false
        if let playing, hand.order.count > 1, hand.cursor < hand.order.count, hand.order[hand.cursor] == playing {
            hand.cursor += 1
            skippedPlaying = true
        }
        if hand.cursor >= hand.order.count {
            let lastDrawn: String? = skippedPlaying ? playing : hand.order.last
            hand.order = Self.avoidFirst(Self.permute(ids, rng: &hand.rng), lastPlayed: lastDrawn)
            hand.cursor = 0
        }
        let id = hand.order[hand.cursor]
        hand.cursor += 1
        hands[nextKey] = hand
        observed = id
        return ShuffleDraw(id: id, order: hand.order)
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

    /// Main and Beyond ignore the region. Region is the only scope whose deck is per region.
    static func deckKey(medium: ShuffleMedium, scope: ShuffleScope, regionId: String?) -> String {
        switch scope {
        case .main, .beyond:
            return "\(medium.rawValue)|\(scope.rawValue)"
        case .region:
            return "\(medium.rawValue)|\(scope.rawValue)|\(selectedRegion(regionId) ?? "")"
        }
    }

    private static func samePool(_ order: [String], _ ids: [String]) -> Bool {
        guard order.count == ids.count else { return false }
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

/// Where Previous and Next go on a channel list. A Surf list does not wrap: Previous on the
/// first card stays, and Next on the last card deals again. A shelf opened by hand still wraps.
enum SurfStep: Equatable {
    case stay
    case deal
    case move(Int)
}

enum SurfNavigation {
    static func step(delta: Int, from position: Int, count: Int, surfList: Bool) -> SurfStep {
        guard count > 1, (0..<count).contains(position) else { return .stay }
        if surfList {
            if delta > 0, position + 1 == count { return .deal }
            if delta < 0, position == 0 { return .stay }
        }
        return .move((position + delta + count) % count)
    }
}

/// Previous and Next for the list in the player. `deck` is set only when Surf, or the step
/// off that list, installed it. A shelf leaves it nil, even when its ids happen to match a deck.
enum SurfList {
    static func step(delta: Int, from position: Int, count: Int, deck: ShuffleDeckRef?) -> SurfStep {
        SurfNavigation.step(delta: delta, from: position, count: count, surfList: deck != nil)
    }
}

/// How the tune ended, as far as the deck cares. A failure and a timeout spend the card.
/// The player's 30 second timeout publishes a failure, and `.timedOut` spends it the same way.
enum SurfTune: Equatable {
    case presented
    case playing
    case failed
    case timedOut
    case cancelled
}

/// Whether the viewer has been given the dealt card.
enum SurfArrival: Equatable {
    /// This channel is the one on screen. The card is spent.
    case onScreen(String)
    /// The previous picture is still showing. The card stays held.
    case notYet
}

/// The rule both screens use before they tell the session a card was shown.
enum SurfPresentation {
    /// Apple TV spends a card when that channel becomes the current one: the cover opened on it,
    /// or the cut landed, whether the tune plays, fails, or times out. Menu before the cut does not.
    /// A neighbour that has reached `.playing` is still not this channel: `currentId` differs, so the card stays held.
    static func television(currentId: String, dealtId: String, tune: SurfTune) -> SurfArrival {
        switch tune {
        case .cancelled:
            return .notYet
        case .presented, .playing, .failed, .timedOut:
            guard currentId == dealtId else { return .notYet }
            return .onScreen(dealtId)
        }
    }

    /// iPhone spends a card when the channel is installed as the live source, before the fade and the settle.
    /// A cancel after that still spends it. A cancel before install does not.
    static func phone(sourceId: String?, dealtId: String, installed: Bool) -> SurfArrival {
        guard installed, sourceId == dealtId else { return .notYet }
        return .onScreen(dealtId)
    }
}

/// The deck the two apps share, and the note when a scope has nothing to play.
/// One flight at a time: Surf cancels an end-of-list deal, and that deal cancels Surf.
@MainActor
final class ShuffleSession {
    static let regionKey = "kjregion"
    static let defaultRegionId = "indus"

    private var deck: ShuffleDeck
    private var selection = ""
    /// Bumped at the start of each pick, and again when that pick is dealt, so one prepared deals once.
    private var generation = 0
    /// Surf, or the step off the end of a Surf list. Starting one cancels the other.
    private var flight: Task<Void, Never>?
    /// A card that was dealt and not yet on screen. The next deal of that deck returns it,
    /// so leaving before the cover, or Menu before the cut, does not skip it.
    private var unshown: [String: ShufflePick] = [:]
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

    /// Cancels the Surf or end-of-list deal already running, then keeps `task` as the one in flight.
    func takeFlight(_ task: Task<Void, Never>) {
        flight?.cancel()
        flight = task
    }

    /// The screen that started the flight is gone. A load that has not dealt yet stops.
    /// A card already dealt stays held until that channel is the one on screen.
    func cancelFlight() {
        flight?.cancel()
        flight = nil
    }

    /// Spend the held card when `arrival` says that channel is on screen. A neighbour playing,
    /// or Menu before the cut, arrives as `.notYet` and leaves the card held.
    func noteArrival(_ arrival: SurfArrival, key: String?) {
        guard let key, case .onScreen(let channelId) = arrival else { return }
        confirmShown(key: key, channelId: channelId)
    }

    /// `channelId` is on screen for `key`. That deal is kept, and the next Surf draws the card after it.
    func confirmShown(key: String, channelId: String) {
        guard unshown[key]?.channel.id == channelId else { return }
        unshown[key] = nil
    }

    /// The next card of this medium and scope. The load runs first. The deck changes only in
    /// `commit`, and only while this pick is still the current one.
    func pick(index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope, regionId: String?, playingId: String?, load: (String) async throws -> [Channel]) async -> ShufflePick? {
        guard let prepared = await prepare(index: index, medium: medium, scope: scope, regionId: regionId, load: load) else { return nil }
        guard let dealt = commit(prepared, finishList: nil, playingId: playingId) else { return nil }
        noteArrival(SurfPresentation.television(currentId: dealt.channel.id, dealtId: dealt.channel.id, tune: .presented), key: dealt.deck.key)
        return dealt
    }

    /// Load the scope's channels without dealing. A newer `prepare` makes this one stale.
    func prepare(index: ReceiverIndex, medium: ShuffleMedium, scope: ShuffleScope, regionId: String?, load: (String) async throws -> [Channel]) async -> ShufflePrepared? {
        let token = beginPick()
        let selectionKey = ShuffleDeck.deckKey(medium: medium, scope: scope, regionId: regionId)
        if selectionKey != selection {
            selection = selectionKey
            blocked = false
            note = nil
        }
        if blocked || Task.isCancelled { return nil }
        let regionSelected = regionId.map { !$0.isEmpty && $0 != "all" } ?? false
        let ids = ShuffleDeck.regionIds(index: index, scope: scope, selected: regionId)
        guard !ids.isEmpty else {
            guard current(token) else { return nil }
            return ShufflePrepared(token: token, medium: medium, scope: scope, regionId: regionId, regionSelected: regionSelected, entries: [], byID: [:])
        }
        var entries: [ShuffleEntry] = []
        var byID: [String: Channel] = [:]
        var seen = Set<String>()
        for id in ids {
            guard current(token) else { return nil }
            let channels: [Channel]
            do {
                channels = try await load(id)
            } catch {
                guard current(token) else { return nil }
                note = error.localizedDescription
                return nil
            }
            guard current(token) else { return nil }
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
        guard current(token) else { return nil }
        return ShufflePrepared(token: token, medium: medium, scope: scope, regionId: regionId, regionSelected: regionSelected, entries: entries, byID: byID)
    }

    /// Deal from a load that is still the current pick. `finishList` is the deck the player
    /// walked off the end of. A list dealt from some other deck is refused before the hands
    /// or this token change. The token is spent before the hand moves, so this prepared deals once.
    func commit(_ prepared: ShufflePrepared, finishList: ShuffleDeckRef?, playingId: String?) -> ShufflePick? {
        guard current(prepared.token) else { return nil }
        let preparedKey = ShuffleDeck.deckKey(medium: prepared.medium, scope: prepared.scope, regionId: prepared.regionId)
        if let finishList, finishList.key != preparedKey { return nil }
        if let waiting = unshown[preparedKey] {
            generation += 1
            return waiting
        }
        generation += 1
        if let finishList {
            deck.noteListEnded(on: playingId ?? "", key: finishList.key)
        }
        guard let dealt = deck.draw(entries: prepared.entries, medium: prepared.medium, scope: prepared.scope, regionId: prepared.regionId, playing: playingId ?? deck.lastPlayed) else {
            note = prepared.scope.emptyNote(medium: prepared.medium, regionSelected: prepared.regionSelected)
            blocked = true
            return nil
        }
        let list = dealt.order.compactMap { prepared.byID[$0] }
        guard let channel = prepared.byID[dealt.id], list.count == dealt.order.count else { return nil }
        note = nil
        blocked = false
        let pick = ShufflePick(channel: channel, list: list, medium: prepared.medium, scope: prepared.scope, regionId: prepared.regionId)
        unshown[preparedKey] = pick
        return pick
    }

    private func beginPick() -> Int {
        generation += 1
        return generation
    }

    private func current(_ token: Int) -> Bool {
        token == generation && !Task.isCancelled
    }
}

/// A load that has not been dealt yet. `commit` deals it only while its token is still current.
struct ShufflePrepared {
    fileprivate let token: Int
    let medium: ShuffleMedium
    let scope: ShuffleScope
    let regionId: String?
    let regionSelected: Bool
    let entries: [ShuffleEntry]
    let byID: [String: Channel]
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
