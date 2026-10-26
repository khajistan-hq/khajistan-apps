import XCTest
@testable import KhajistanCore

/// The website's shuffle fixture, copied to `tvos/Tests/Fixtures/shuffle_fixture.json`.
/// These cases assert its id lists character for character.
final class ShuffleTests: XCTestCase {
    func testMulberry32Words() throws {
        let fixture = try Self.fixture()
        for row in fixture.mulberry32 {
            var rng = Mulberry32(seed: row.seed)
            let got = (0..<row.words.count).map { _ in rng.nextWord() }
            XCTAssertEqual(got, row.words, "seed \(row.seed)")
        }
    }

    func testFixtureOrdersByteForByte() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        XCTAssertFalse(fixture.filters.country.isEmpty)
        XCTAssertFalse(fixture.filters.query.isEmpty)
        for row in fixture.orders {
            var deck = ShuffleDeck(seed: row.seed)
            let dealt = try XCTUnwrap(Self.deal(&deck, entries, row), row.name)
            XCTAssertEqual(dealt.order, row.ids, row.name)
            XCTAssertEqual(dealt.id, row.ids[0], row.name)
            XCTAssertEqual(Set(dealt.order).count, dealt.order.count, row.name)
            let pool = Set(ShuffleDeck.playableIDs(
                entries,
                medium: ShuffleMedium(rawValue: row.medium) ?? .tv,
                scope: ShuffleScope(rawValue: row.scope) ?? .main,
                regionId: row.region
            ))
            XCTAssertEqual(Set(dealt.order), pool, row.name)
            if let playing = row.playing, row.ids.count > 1 {
                XCTAssertNotEqual(dealt.order[0], playing, row.name)
            }
        }
        let main = try XCTUnwrap(fixture.orders.first { $0.filters != nil })
        XCTAssertEqual(main.filters?.country, fixture.filters.country)
        XCTAssertTrue(main.ids.contains("levant-tv-a"))
        XCTAssertTrue(main.ids.contains("anatolia-tv-a"))
        XCTAssertTrue(main.ids.contains("solo-tv"))
        XCTAssertFalse(main.ids.contains("indus-tv-off"))
        let beyondIndus = try XCTUnwrap(fixture.orders.first { $0.scope == "beyond" && $0.region == "indus" })
        let regionIndus = try XCTUnwrap(fixture.orders.first { $0.scope == "region" && $0.region == "indus" && $0.seed == beyondIndus.seed })
        XCTAssertEqual(beyondIndus.ids, regionIndus.ids)
        let beyondOpen = try XCTUnwrap(fixture.orders.first { $0.scope == "beyond" && $0.region == nil && $0.medium == "tv" })
        let tiers = Dictionary(uniqueKeysWithValues: fixture.channels.map { ($0.id, $0.tier) })
        XCTAssertTrue(beyondOpen.ids.allSatisfy { tiers[$0] == "islamicate" })
    }

    func testNoRepeatInsideADeckAndTheBoundarySwapsTheFirstTwo() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        for row in fixture.boundary {
            var deck = ShuffleDeck(seed: row.seed)
            let first = try XCTUnwrap(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
            XCTAssertEqual(Set(first.order).count, first.order.count)
            var last = first
            for _ in 1..<first.order.count {
                last = try XCTUnwrap(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
            }
            let next = try XCTUnwrap(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
            XCTAssertEqual(last.id, row.tail)
            XCTAssertEqual(next.id, row.head)
            XCTAssertNotEqual(row.tail, row.head)
            XCTAssertEqual(next.order[0], row.head)
            XCTAssertEqual(next.order[1], row.tail)
        }
    }

    func testRegionChangeDealsANewDeck() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        for row in fixture.regionChange {
            var left = ShuffleDeck(seed: row.seed)
            var right = left
            var opening: [String] = []
            for index in 0..<row.take {
                let dealt = try XCTUnwrap(Self.deal(&left, entries, medium: row.medium, scope: row.scope, region: row.from, playing: nil))
                _ = Self.deal(&right, entries, medium: row.medium, scope: row.scope, region: row.from, playing: nil)
                if index == 0 { opening = dealt.order }
            }
            let continued = try XCTUnwrap(Self.deal(&left, entries, medium: row.medium, scope: row.scope, region: row.from, playing: nil))
            let reset = try XCTUnwrap(Self.deal(&right, entries, medium: row.medium, scope: row.scope, region: row.to, playing: nil))
            XCTAssertEqual(opening, row.openingOrder)
            XCTAssertEqual(continued.id, row.wouldHaveContinued)
            XCTAssertEqual(reset.order, row.resetOrder)
            XCTAssertNotEqual(reset.id, row.wouldHaveContinued)
            var fresh = ShuffleDeck(seed: row.seed)
            let reseeded = try XCTUnwrap(Self.deal(&fresh, entries, medium: row.medium, scope: row.scope, region: row.to, playing: nil))
            XCTAssertNotEqual(reset.order, reseeded.order)
            XCTAssertNotEqual(reset.order, opening)
        }
    }

    func testOneChannelMayRepeatAndNoneDealsNothing() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        for row in fixture.repeats {
            var deck = ShuffleDeck(seed: row.seed)
            let first = try XCTUnwrap(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
            let second = try XCTUnwrap(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
            XCTAssertEqual(first.id, row.first)
            XCTAssertEqual(second.id, row.second)
        }
        for row in fixture.empty {
            var deck = ShuffleDeck(seed: 1)
            XCTAssertNil(Self.deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: nil))
        }
        XCTAssertEqual(ShuffleScope.main.emptyNote(medium: .tv, regionSelected: true), "No television to surf on the main atlas right now.")
        XCTAssertEqual(ShuffleScope.beyond.emptyNote(medium: .tv, regionSelected: false), "No television beyond the atlas right now.")
        XCTAssertEqual(ShuffleScope.beyond.emptyNote(medium: .radio, regionSelected: true), "No radio in this region right now.")
        XCTAssertEqual(ShuffleScope.resolved("extended"), .beyond)
        XCTAssertEqual(ShuffleScope.resolved("everywhere"), .main)
    }

    func testScopeChoosesRegions() throws {
        let index = try JSONDecoder().decode(ReceiverIndex.self, from: Data(Self.sampleIndex.utf8))
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .main, selected: "indus"), ["indus", "anatolia"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: nil), ["nusantara"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: "anatolia"), ["anatolia"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .region, selected: "nusantara"), ["nusantara"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .region, selected: "kashmir"), [])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: "missing"), [])
        XCTAssertEqual(CameraRegions.ordered(index).map(\.id), ["anatolia", "nusantara"])
        XCTAssertEqual(CameraRegions.total(index), 400)
    }

    func testEmptyScopeDisablesAndAFailedLoadKeepsTheDeck() async throws {
        let index = try JSONDecoder().decode(ReceiverIndex.self, from: Data(Self.sampleIndex.utf8))
        let session = ShuffleSession(seed: 1)
        let channel = "{\"id\":\"%@\",\"name\":\"%@\",\"mediaType\":\"tv\",\"streams\":[{\"id\":\"s\"}],\"activeStreamId\":\"s\"}"
        func parsed(_ id: String) throws -> Channel {
            try JSONDecoder().decode(Channel.self, from: Data(String(format: channel, id, id).utf8))
        }
        var fail = false
        let load: (String) async throws -> [Channel] = { id in
            if fail { throw LoadFailure() }
            return [try parsed(id)]
        }
        let opened = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let first = try XCTUnwrap(opened)
        fail = true
        let missed = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        XCTAssertNil(missed)
        XCTAssertFalse(session.blocked)
        XCTAssertEqual(session.note, "The region could not be loaded.")
        XCTAssertTrue(session.plays(first.list.map(\.id)))
        fail = false
        let continued = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let third = try XCTUnwrap(continued)
        XCTAssertEqual(third.list.map(\.id), first.list.map(\.id))
        XCTAssertNotEqual(third.channel.id, first.channel.id)

        let empty = await session.pick(index: index, medium: .tv, scope: .region, regionId: "kashmir", playingId: nil, load: load)
        XCTAssertNil(empty)
        XCTAssertTrue(session.blocked)
        XCTAssertEqual(session.note, "No television in this region right now.")
        session.noteSelectionChanged()
        XCTAssertFalse(session.blocked)
        XCTAssertNil(session.note)

        let once = await session.pick(index: index, medium: .tv, scope: .region, regionId: "anatolia", playingId: nil, load: load)
        let only = try XCTUnwrap(once)
        let twice = await session.pick(index: index, medium: .tv, scope: .region, regionId: "anatolia", playingId: nil, load: load)
        let again = try XCTUnwrap(twice)
        XCTAssertEqual(only.channel.id, "anatolia")
        XCTAssertEqual(again.channel.id, "anatolia")
        XCTAssertFalse(session.blocked)
    }

    private struct LoadFailure: LocalizedError {
        var errorDescription: String? { "The region could not be loaded." }
    }

    private static let sampleIndex = """
    {"regions":[{"id":"indus","label":"Indus","kind":"state","tier":"heartbeat"},
                {"id":"anatolia","label":"Anatolia","kind":"state","tier":"core"},
                {"id":"nusantara","label":"Nusantara","kind":"state","tier":"islamicate"},
                {"id":"kashmir","label":"Kashmir","kind":"people","tier":"core"}],
     "regionFiles":{"indus":"/data/i.json","anatolia":"/data/a.json","nusantara":"/data/n.json"},
     "cameraFiles":{"nusantara":"/data/n-cam.json","anatolia":"/data/a-cam.json"},
     "regionCounts":{"indus":{"channels":78,"live":78,"byMedium":{"tv":38,"radio":40}},
                     "anatolia":{"channels":60,"live":60,"byMedium":{"tv":20,"radio":16,"camera":24}},
                     "nusantara":{"channels":400,"live":400,"byMedium":{"tv":4,"radio":20,"camera":376}}},
     "totals":{"channels":538,"live":538,"byMedium":{"tv":62,"radio":76,"camera":400}}}
    """

    private static func fixture() throws -> ShuffleFixture {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        let name = "tvos/Tests/Fixtures/shuffle_fixture.json"
        while url.path != "/" {
            let candidate = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder().decode(ShuffleFixture.self, from: Data(contentsOf: candidate))
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    private static func entries(_ fixture: ShuffleFixture) -> [ShuffleEntry] {
        fixture.channels.map {
            ShuffleEntry(id: $0.id, regionId: $0.region, tier: $0.tier, medium: $0.medium, offline: $0.offline ?? false)
        }
    }

    private static func deal(_ deck: inout ShuffleDeck, _ entries: [ShuffleEntry], _ row: ShuffleFixture.Order) -> ShuffleDraw? {
        deal(&deck, entries, medium: row.medium, scope: row.scope, region: row.region, playing: row.playing)
    }

    private static func deal(_ deck: inout ShuffleDeck, _ entries: [ShuffleEntry], medium: String, scope: String, region: String?, playing: String?) -> ShuffleDraw? {
        deck.draw(
            entries: entries,
            medium: ShuffleMedium(rawValue: medium) ?? .tv,
            scope: ShuffleScope(rawValue: scope) ?? .main,
            regionId: region,
            playing: playing
        )
    }
}

private struct ShuffleFixture: Decodable {
    struct Channel: Decodable {
        let id: String
        let region: String
        let tier: String
        let medium: String
        let offline: Bool?
    }
    struct Words: Decodable { let seed: UInt32; let words: [UInt32] }
    struct Filters: Decodable { let country: String; let language: String; let genre: String; let query: String }
    struct Order: Decodable {
        let name: String
        let seed: UInt32
        let medium: String
        let scope: String
        let region: String?
        let playing: String?
        let ids: [String]
        let filters: Filters?
    }
    struct Boundary: Decodable {
        let seed: UInt32
        let medium: String
        let scope: String
        let region: String?
        let tail: String
        let head: String
    }
    struct RegionChange: Decodable {
        let seed: UInt32
        let medium: String
        let scope: String
        let from: String
        let take: Int
        let to: String
        let openingOrder: [String]
        let wouldHaveContinued: String
        let resetOrder: [String]
    }
    struct RepeatRow: Decodable {
        let seed: UInt32
        let medium: String
        let scope: String
        let region: String?
        let first: String
        let second: String
    }
    struct Empty: Decodable { let medium: String; let scope: String; let region: String? }
    let filters: Filters
    let channels: [Channel]
    let mulberry32: [Words]
    let orders: [Order]
    let boundary: [Boundary]
    let regionChange: [RegionChange]
    let repeats: [RepeatRow]
    let empty: [Empty]

    enum CodingKeys: String, CodingKey {
        case filters, channels, mulberry32, orders, boundary, regionChange, empty
        case repeats = "repeat"
    }
}
