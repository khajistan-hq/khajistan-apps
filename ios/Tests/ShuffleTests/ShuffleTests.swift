import XCTest
@testable import KhajistanCore

/// The website's shuffle fixture, copied to `tvos/Tests/Fixtures/shuffle_fixture.json`.
/// These cases assert its id lists character for character.
final class ShuffleTests: XCTestCase {
    func testMulberry32Words() throws {
        let words: [UInt32: [UInt32]] = [
            2: [3153583793, 1395857638, 1225337227, 2310499808],
            3: [3093350482, 166052715, 1959330548, 321813351],
            5: [2962560684, 3318907087, 943874942, 2676532661],
        ]
        for (seed, expected) in words {
            var rng = Mulberry32(seed: seed)
            XCTAssertEqual(expected.map { _ in rng.nextWord() }, expected, "seed \(seed)")
        }
    }

    func testFixtureOrdersCharacterForCharacter() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        for (name, pool) in fixture.pools {
            let region = name == "region" ? fixture.regionScope : nil
            let ids = ShuffleDeck.playableIDs(entries, medium: .tv, scope: Self.scope(name), regionId: region)
            XCTAssertEqual(ids, pool, name)
        }
        let beyond = ShuffleDeck.playableIDs(entries, medium: .tv, scope: .beyond, regionId: fixture.regionScope)
        XCTAssertEqual(beyond, fixture.pools["beyond"])
        XCTAssertTrue(fixture.pools["main"]?.contains("horn-diaspora") == true)
        XCTAssertTrue(fixture.pools["beyond"]?.contains("horn-diaspora") == false)
        for (name, draw) in fixture.draws {
            var deck = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds[name]))
            let region = name == "region" ? fixture.regionScope : nil
            for expected in draw.decks {
                var got: [String] = []
                var order: [String] = []
                for _ in expected {
                    let dealt = try XCTUnwrap(Self.deal(&deck, entries, scope: name, region: region, playing: nil))
                    got.append(dealt.id)
                    order = dealt.order
                }
                XCTAssertEqual(got, expected, name)
                XCTAssertEqual(order, expected, name)
                XCTAssertEqual(Set(order).count, order.count, name)
            }
            let decks = draw.decks
            XCTAssertNotEqual(decks[0].last, decks[1].first, name)
            XCTAssertEqual(decks[1][1], decks[0].last ?? "", name)
        }
    }

    func testDirectoryClickSkipsTheCardAtTheCursor() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        let main = try XCTUnwrap(fixture.draws["main"])
        var deck = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["main"]))
        let opened = try XCTUnwrap(Self.deal(&deck, entries, scope: "main", region: nil, playing: nil))
        XCTAssertEqual(opened.id, "horn-diaspora")
        XCTAssertEqual(opened.order, main.decks[0])
        deck.observe("indus-two")
        let surfed = try XCTUnwrap(Self.deal(&deck, entries, scope: "main", region: nil, playing: "indus-two"))
        XCTAssertEqual(surfed.id, "horn-news")
        XCTAssertEqual(surfed.order, main.decks[0])
        var cold = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["main"]))
        let coldDraw = try XCTUnwrap(Self.deal(&cold, entries, scope: "main", region: nil, playing: "indus-two"))
        XCTAssertEqual(coldDraw.id, "horn-diaspora")
        var tail = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["main"]))
        for _ in 0..<4 {
            _ = try XCTUnwrap(Self.deal(&tail, entries, scope: "main", region: nil, playing: nil))
        }
        let wrapped = try XCTUnwrap(Self.deal(&tail, entries, scope: "main", region: nil, playing: "indus-one"))
        XCTAssertEqual(wrapped.id, "horn-news")
        XCTAssertEqual(wrapped.order, main.decks[1])
    }

    func testRegionChangeDealsANewDeck() throws {
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        var deck = ShuffleDeck(seed: 3)
        let horn = try XCTUnwrap(Self.deal(&deck, entries, scope: "region", region: "horn", playing: nil))
        let indus = try XCTUnwrap(Self.deal(&deck, entries, scope: "region", region: "indus", playing: nil))
        let hornAgain = try XCTUnwrap(Self.deal(&deck, entries, scope: "region", region: "horn", playing: nil))
        XCTAssertEqual(horn.order, try XCTUnwrap(fixture.draws["region"]).decks[0])
        XCTAssertEqual(hornAgain.id, horn.order[1])
        XCTAssertEqual(hornAgain.order, horn.order)
        var fresh = ShuffleDeck(seed: 3)
        let indusFresh = try XCTUnwrap(Self.deal(&fresh, entries, scope: "region", region: "indus", playing: nil))
        XCTAssertEqual(indus.order, indusFresh.order)
        XCTAssertEqual(indus.id, indusFresh.id)
        XCTAssertEqual(Set(indus.order), Set(["indus-one", "indus-two"]))
    }

    func testMainAndBeyondSurviveARegionChange() throws {
        XCTAssertEqual(ShuffleDeck.deckKey(medium: .tv, scope: .main, regionId: "horn"), "tv|main")
        XCTAssertEqual(ShuffleDeck.deckKey(medium: .tv, scope: .main, regionId: "indus"), "tv|main")
        XCTAssertEqual(ShuffleDeck.deckKey(medium: .tv, scope: .beyond, regionId: "horn"), "tv|beyond")
        XCTAssertEqual(ShuffleDeck.deckKey(medium: .tv, scope: .region, regionId: "horn"), "tv|region|horn")
        let fixture = try Self.fixture()
        let entries = Self.entries(fixture)
        var main = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["main"]))
        let first = try XCTUnwrap(Self.deal(&main, entries, scope: "main", region: "horn", playing: nil))
        let next = try XCTUnwrap(Self.deal(&main, entries, scope: "main", region: "indus", playing: nil))
        XCTAssertEqual(first.order, try XCTUnwrap(fixture.draws["main"]).decks[0])
        XCTAssertEqual(next.id, first.order[1])
        XCTAssertEqual(next.order, first.order)
        var beyond = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["beyond"]))
        let opened = try XCTUnwrap(Self.deal(&beyond, entries, scope: "beyond", region: "horn", playing: nil))
        let followed = try XCTUnwrap(Self.deal(&beyond, entries, scope: "beyond", region: "anatolia", playing: nil))
        XCTAssertEqual(opened.order, try XCTUnwrap(fixture.draws["beyond"]).decks[0])
        XCTAssertEqual(followed.id, opened.order[1])
        XCTAssertEqual(followed.order, opened.order)
        var split = ShuffleDeck(seed: try XCTUnwrap(fixture.seeds["main"]))
        let television = try XCTUnwrap(split.draw(entries: entries, medium: .tv, scope: .main, regionId: nil, playing: nil))
        let radio = entries.map { ShuffleEntry(id: $0.id, regionIds: $0.regionIds, beyond: $0.beyond, medium: "radio") }
        _ = split.draw(entries: radio, medium: .radio, scope: .main, regionId: "indus", playing: nil)
        let again = try XCTUnwrap(split.draw(entries: entries, medium: .tv, scope: .main, regionId: "nusantara", playing: nil))
        XCTAssertEqual(again.id, television.order[1])
        XCTAssertEqual(again.order, television.order)
    }

    func testPreviousOnASurfListStaysPut() {
        XCTAssertEqual(SurfNavigation.step(delta: -1, from: 0, count: 5, surfList: true), .stay)
        XCTAssertEqual(SurfNavigation.step(delta: 1, from: 4, count: 5, surfList: true), .deal)
        XCTAssertEqual(SurfNavigation.step(delta: -1, from: 0, count: 5, surfList: false), .move(4))
        XCTAssertEqual(SurfNavigation.step(delta: 1, from: 4, count: 5, surfList: false), .move(0))
    }

    func testPoolKeepsFileOrder() {
        let entries = [
            ShuffleEntry(id: "zeta", regionIds: ["horn"], beyond: false, medium: "tv"),
            ShuffleEntry(id: "alpha", regionIds: ["horn"], beyond: false, medium: "tv"),
            ShuffleEntry(id: "mu", regionIds: ["horn"], beyond: false, medium: "tv"),
        ]
        XCTAssertEqual(ShuffleDeck.playableIDs(entries, medium: .tv, scope: .main, regionId: "indus"), ["zeta", "alpha", "mu"])
    }

    func testFixtureSha256() throws {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        let name = "tvos/Tests/Fixtures/shuffle_fixture.json"
        while url.path != "/" {
            let candidate = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let binary = FileManager.default.isExecutableFile(atPath: "/usr/bin/sha256sum") ? "/usr/bin/sha256sum" : "/usr/bin/shasum"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = binary.hasSuffix("shasum") ? ["-a", "256", candidate.path] : [candidate.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                try process.run()
                process.waitUntilExit()
                let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let digest = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
                XCTAssertEqual(digest, "3912779bf179b5cabc38e3c63b1bb775db7793d03b1fa219e2640c58e21d2f08")
                return
            }
            url.deleteLastPathComponent()
        }
        XCTFail("fixture missing")
    }

    @MainActor
    func testAStaleOrCancelledPickDoesNotDeal() async throws {
        let index = try JSONDecoder().decode(ReceiverIndex.self, from: Data(Self.sampleIndex.utf8))
        let session = ShuffleSession(seed: 1)
        let channel = "{\"id\":\"%@\",\"name\":\"%@\",\"mediaType\":\"tv\",\"streams\":[{\"id\":\"s\"}],\"activeStreamId\":\"s\"}"
        func parsed(_ id: String) throws -> Channel {
            try JSONDecoder().decode(Channel.self, from: Data(String(format: channel, id, id).utf8))
        }
        let load: (String) async throws -> [Channel] = { id in [try parsed(id)] }
        let openedPick = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let opened = try XCTUnwrap(openedPick)
        let order = opened.list.map(\.id)

        let gate = PickGate()
        let hanging = Task { () -> ShufflePrepared? in
            await session.prepare(index: index, medium: .tv, scope: .main, regionId: "indus") { id in
                await gate.enter()
                return [try parsed(id)]
            }
        }
        await gate.arrived()
        let secondPick = await session.pick(index: index, medium: .tv, scope: .main, regionId: "anatolia", playingId: nil, load: load)
        let second = try XCTUnwrap(secondPick)
        gate.release()
        let stale = await hanging.value
        XCTAssertNil(stale)
        XCTAssertEqual(second.list.map(\.id), order)
        XCTAssertEqual(second.channel.id, order[1])

        let later = ShuffleSession(seed: 1)
        let openedLaterPick = await later.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let openedLater = try XCTUnwrap(openedLaterPick)
        let laterOrder = openedLater.list.map(\.id)
        let staleLoad = await later.prepare(index: index, medium: .tv, scope: .main, regionId: "indus", load: load)
        let stalePrepared = try XCTUnwrap(staleLoad)
        let newerLoad = await later.prepare(index: index, medium: .tv, scope: .main, regionId: "indus", load: load)
        let newer = try XCTUnwrap(newerLoad)
        let mainDeck = ShuffleDeckRef(medium: .tv, scope: .main, regionId: "indus")
        XCTAssertNil(later.commit(stalePrepared, finishList: mainDeck, playingId: laterOrder.last))
        let resumed = try XCTUnwrap(later.commit(newer, finishList: nil, playingId: nil))
        XCTAssertEqual(resumed.list.map(\.id), laterOrder)
        XCTAssertEqual(resumed.channel.id, laterOrder[1])

        let third = ShuffleSession(seed: 1)
        let openedThirdPick = await third.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let openedThird = try XCTUnwrap(openedThirdPick)
        let thirdOrder = openedThird.list.map(\.id)
        let heldLoad = await third.prepare(index: index, medium: .tv, scope: .main, regionId: "indus", load: load)
        let held = try XCTUnwrap(heldLoad)
        let cancelled = Task { @MainActor () -> ShufflePick? in
            while !Task.isCancelled { await Task.yield() }
            let mainDeck = ShuffleDeckRef(medium: .tv, scope: .main, regionId: "indus")
            return third.commit(held, finishList: mainDeck, playingId: thirdOrder.last)
        }
        cancelled.cancel()
        let cancelledPick = await cancelled.value
        XCTAssertNil(cancelledPick)
        let afterPick = await third.pick(index: index, medium: .tv, scope: .main, regionId: "horn", playingId: nil, load: load)
        let after = try XCTUnwrap(afterPick)
        XCTAssertEqual(after.list.map(\.id), thirdOrder)
        XCTAssertEqual(after.channel.id, thirdOrder[1])
    }

    func testOneChannelMayRepeatAndNoneDealsNothing() throws {
        let solo = [ShuffleEntry(id: "only", regionIds: ["indus"], beyond: false, medium: "tv")]
        var deck = ShuffleDeck(seed: 1)
        let first = try XCTUnwrap(Self.deal(&deck, solo, scope: "region", region: "indus", playing: nil))
        let second = try XCTUnwrap(Self.deal(&deck, solo, scope: "region", region: "indus", playing: "only"))
        XCTAssertEqual(first.id, "only")
        XCTAssertEqual(second.id, "only")
        var empty = ShuffleDeck(seed: 1)
        XCTAssertNil(Self.deal(&empty, solo, scope: "region", region: "kashmir", playing: nil))
        XCTAssertEqual(ShuffleScope.main.emptyNote(medium: .tv, regionSelected: true), "No television to surf on the main atlas right now.")
        XCTAssertEqual(ShuffleScope.region.emptyNote(medium: .radio, regionSelected: true), "No radio in this region right now.")
        XCTAssertEqual(ShuffleScope.beyond.emptyNote(medium: .tv, regionSelected: false), "No television beyond the atlas right now.")
        XCTAssertEqual(ShuffleScope.beyond.emptyNote(medium: .radio, regionSelected: true), "No radio beyond the atlas right now.")
        XCTAssertEqual(ShuffleScope.resolved("extended"), .beyond)
        XCTAssertEqual(ShuffleScope.resolved("everywhere"), .main)
        XCTAssertEqual(ShuffleScope.resolved(nil), .main)
    }

    func testScopeChoosesRegions() throws {
        let index = try JSONDecoder().decode(ReceiverIndex.self, from: Data(Self.sampleIndex.utf8))
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .main, selected: "indus"), ["indus", "anatolia"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: nil), ["nusantara"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: "anatolia"), ["nusantara"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .region, selected: "nusantara"), ["nusantara"])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .region, selected: "kashmir"), [])
        XCTAssertEqual(ShuffleDeck.regionIds(index: index, scope: .beyond, selected: "missing"), ["nusantara"])
        XCTAssertEqual(CameraRegions.ordered(index).map(\.id), ["anatolia", "nusantara"])
        XCTAssertEqual(CameraRegions.total(index), 400)
    }

    @MainActor
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
        let missedBlocked = session.blocked
        let missedNote = session.note
        XCTAssertFalse(missedBlocked)
        XCTAssertEqual(missedNote, "The region could not be loaded.")
        fail = false
        let continued = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: load)
        let third = try XCTUnwrap(continued)
        XCTAssertEqual(third.list.map(\.id), first.list.map(\.id))
        XCTAssertNotEqual(third.channel.id, first.channel.id)

        let empty = await session.pick(index: index, medium: .tv, scope: .region, regionId: "kashmir", playingId: nil, load: load)
        XCTAssertNil(empty)
        let emptyBlocked = session.blocked
        let emptyNote = session.note
        XCTAssertTrue(emptyBlocked)
        XCTAssertEqual(emptyNote, "No television in this region right now.")
        session.noteSelectionChanged()
        let clearedBlocked = session.blocked
        let clearedNote = session.note
        XCTAssertFalse(clearedBlocked)
        XCTAssertNil(clearedNote)

        let once = await session.pick(index: index, medium: .tv, scope: .region, regionId: "anatolia", playingId: nil, load: load)
        let only = try XCTUnwrap(once)
        let twice = await session.pick(index: index, medium: .tv, scope: .region, regionId: "anatolia", playingId: nil, load: load)
        let again = try XCTUnwrap(twice)
        XCTAssertEqual(only.channel.id, "anatolia")
        XCTAssertEqual(again.channel.id, "anatolia")
        let stillOpen = session.blocked
        XCTAssertFalse(stillOpen)
    }

    /// Surf Main, then the chip moves to Region or Radio. The step off the end of the list
    /// deals Main again. A commit aimed at the new chip, while finishing Main's list, changes nothing.
    @MainActor
    func testChipChangeThenEndOfListContinuesTheListsOwnDeck() async throws {
        let index = try Self.decodedIndex()
        let session = ShuffleSession(seed: 1)
        let openedPick = await session.pick(index: index, medium: .tv, scope: .main, regionId: "horn", playingId: nil, load: Self.atlas)
        let opened = try XCTUnwrap(openedPick)
        let order = opened.list.map(\.id)
        let last = try XCTUnwrap(order.last)

        let regionPrepared = await session.prepare(index: index, medium: .tv, scope: .region, regionId: "indus", load: Self.atlas)
        let regionLoad = try XCTUnwrap(regionPrepared)
        XCTAssertNil(session.commit(regionLoad, finishList: opened.deck, playingId: last))
        let regionBlocked = session.blocked
        XCTAssertFalse(regionBlocked)
        let radio = ShuffleSession(seed: 1)
        let radioOpenedPick = await radio.pick(index: index, medium: .tv, scope: .main, regionId: "horn", playingId: nil, load: Self.atlas)
        let radioOpened = try XCTUnwrap(radioOpenedPick)
        let radioPrepared = await radio.prepare(index: index, medium: .radio, scope: .main, regionId: "indus", load: Self.atlas)
        let radioChip = try XCTUnwrap(radioPrepared)
        XCTAssertNil(radio.commit(radioChip, finishList: radioOpened.deck, playingId: radioOpened.list.last?.id))
        let radioBlocked = radio.blocked
        XCTAssertFalse(radioBlocked)
        let radioNext = await radio.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: Self.atlas)
        let radioContinued = try XCTUnwrap(radioNext)
        XCTAssertEqual(radioContinued.list.map(\.id), radioOpened.list.map(\.id))
        XCTAssertEqual(radioContinued.channel.id, radioOpened.list[1].id)

        let continuedPick = await session.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: Self.atlas)
        let continued = try XCTUnwrap(continuedPick)
        XCTAssertEqual(continued.list.map(\.id), order)
        XCTAssertEqual(continued.channel.id, order[1])

        let own = ShuffleSession(seed: 1)
        let listedPick = await own.pick(index: index, medium: .tv, scope: .main, regionId: "horn", playingId: nil, load: Self.atlas)
        let listed = try XCTUnwrap(listedPick)
        let ownPrepared = await own.prepare(index: index, medium: listed.deck.medium, scope: listed.deck.scope, regionId: listed.deck.regionId, load: Self.atlas)
        let prepared = try XCTUnwrap(ownPrepared)
        let dealtPick = own.commit(prepared, finishList: listed.deck, playingId: listed.list.last?.id)
        let dealt = try XCTUnwrap(dealtPick)
        XCTAssertEqual(dealt.deck, listed.deck)
        let dealtFirst = try XCTUnwrap(dealt.list.first)
        XCTAssertEqual(dealt.channel.id, dealtFirst.id)
        // A playing id from outside this region must not skip the region's first card.
        let regionPick = await own.pick(index: index, medium: .tv, scope: .region, regionId: "indus", playingId: "anatolia", load: Self.atlas)
        let region = try XCTUnwrap(regionPick)
        let fresh = ShuffleSession(seed: 1)
        let freshPick = await fresh.pick(index: index, medium: .tv, scope: .region, regionId: "indus", playingId: "anatolia", load: Self.atlas)
        let regionFresh = try XCTUnwrap(freshPick)
        XCTAssertEqual(region.channel.id, regionFresh.channel.id)
        XCTAssertEqual(region.list.map(\.id), regionFresh.list.map(\.id))
    }

    /// A name-sorted shelf of two channels matches the deck on some seeds. Previous still wraps,
    /// because the shelf is not the Surf list. The Surf list, same ids, stays on the first card.
    func testTwoChannelShelfWrapsAfterSurfingThatRegion() {
        let shelf = ["indus-two", "indus-one"].sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        // File order is the reverse of the shelf, so the two lists match only when the shuffle swaps them.
        let entries = [
            ShuffleEntry(id: "indus-two", regionIds: ["indus"], beyond: false, medium: "tv"),
            ShuffleEntry(id: "indus-one", regionIds: ["indus"], beyond: false, medium: "tv"),
        ]
        var matches = 0
        for seed: UInt32 in 1...40 {
            var deck = ShuffleDeck(seed: seed)
            let drawn = deck.draw(entries: entries, medium: .tv, scope: .region, regionId: "indus", playing: nil)
            if drawn?.order == shelf { matches += 1 }
        }
        XCTAssertEqual(matches, 17)
        var installed: ShuffleDeckRef? = ShuffleDeckRef(medium: .tv, scope: .region, regionId: "indus")
        XCTAssertEqual(SurfList.step(delta: -1, from: 0, count: shelf.count, deck: installed), .stay)
        installed = nil
        XCTAssertEqual(SurfList.step(delta: -1, from: 0, count: shelf.count, deck: installed), .move(1))
        XCTAssertEqual(SurfList.step(delta: 1, from: 1, count: shelf.count, deck: installed), .move(0))
    }

    /// Two regions filed with the same channels share an order. Ending one does not move the other.
    func testDuplicateOrdersAdvanceOnlyTheEndedRegion() throws {
        let entries = [
            ShuffleEntry(id: "same-a", regionIds: ["horn", "indus"], beyond: false, medium: "tv"),
            ShuffleEntry(id: "same-b", regionIds: ["horn", "indus"], beyond: false, medium: "tv"),
        ]
        var deck = ShuffleDeck(seed: 1)
        let horn = try XCTUnwrap(deck.draw(entries: entries, medium: .tv, scope: .region, regionId: "horn", playing: nil))
        let indus = try XCTUnwrap(deck.draw(entries: entries, medium: .tv, scope: .region, regionId: "indus", playing: nil))
        XCTAssertEqual(horn.order, indus.order)
        deck.noteListEnded(on: try XCTUnwrap(horn.order.last), key: ShuffleDeck.deckKey(medium: .tv, scope: .region, regionId: "horn"))
        let hornNext = try XCTUnwrap(deck.draw(entries: entries, medium: .tv, scope: .region, regionId: "horn", playing: nil))
        let indusNext = try XCTUnwrap(deck.draw(entries: entries, medium: .tv, scope: .region, regionId: "indus", playing: nil))
        XCTAssertEqual(hornNext.id, hornNext.order[0])
        XCTAssertEqual(indusNext.id, indus.order[1])
        XCTAssertEqual(indusNext.order, indus.order)
    }

    /// One prepared deals one card. Committing it again does not deal a second.
    @MainActor
    func testDoubleCommitOfOnePreparedDealsOnce() async throws {
        let index = try Self.decodedIndex()
        let session = ShuffleSession(seed: 1)
        let preparedLoad = await session.prepare(index: index, medium: .tv, scope: .main, regionId: "indus", load: Self.oneEach)
        let prepared = try XCTUnwrap(preparedLoad)
        let firstPick = session.commit(prepared, finishList: nil, playingId: nil)
        let first = try XCTUnwrap(firstPick)
        XCTAssertNil(session.commit(prepared, finishList: nil, playingId: nil))
        let nextPick = await session.pick(index: index, medium: .tv, scope: .main, regionId: "anatolia", playingId: nil, load: Self.oneEach)
        let next = try XCTUnwrap(nextPick)
        XCTAssertEqual(next.list.map(\.id), first.list.map(\.id))
        XCTAssertEqual(next.channel.id, first.list[1].id)
    }

    /// The tvOS app model keeps the session. Leaving Receiver used to rebuild it with the view.
    @MainActor
    func testTelevisionDeckSurvivesLeavingReceiver() async throws {
        let index = try Self.decodedIndex()
        let model = TelevisionReceiverModel(seed: 1)
        let firstPick = await model.shuffle.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: Self.oneEach)
        let first = try XCTUnwrap(firstPick)
        let secondPick = await model.shuffle.pick(index: index, medium: .tv, scope: .main, regionId: "horn", playingId: nil, load: Self.oneEach)
        let second = try XCTUnwrap(secondPick)
        XCTAssertEqual(second.list.map(\.id), first.list.map(\.id))
        XCTAssertEqual(second.channel.id, first.list[1].id)
        let rebuilt = TelevisionReceiverModel(seed: 1)
        let restartedPick = await rebuilt.shuffle.pick(index: index, medium: .tv, scope: .main, regionId: "indus", playingId: nil, load: Self.oneEach)
        let restarted = try XCTUnwrap(restartedPick)
        XCTAssertEqual(restarted.channel.id, first.channel.id)
        XCTAssertEqual(restarted.list.map(\.id), first.list.map(\.id))
    }

    private static func decodedIndex() throws -> ReceiverIndex {
        try JSONDecoder().decode(ReceiverIndex.self, from: Data(sampleIndex.utf8))
    }

    /// One television channel per shard, id equal to the region id. Main is indus then anatolia.
    private static func oneEach(_ id: String) async throws -> [Channel] {
        [try channel(id)]
    }

    /// Indus carries two channels, so a region deck and the main deck are not the same list.
    private static func atlas(_ id: String) async throws -> [Channel] {
        switch id {
        case "indus": return [try channel("indus-one"), try channel("indus-two")]
        case "anatolia": return [try channel("anatolia")]
        default: return [try channel(id)]
        }
    }

    private static func channel(_ id: String, medium: String = "tv") throws -> Channel {
        let json = "{\"id\":\"\(id)\",\"name\":\"\(id)\",\"mediaType\":\"\(medium)\",\"streams\":[{\"id\":\"s\"}],\"activeStreamId\":\"s\"}"
        return try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
    }

    /// The tvOS `AppModel` keeps one of these for the life of the app. A new Receiver
    /// screen reads it; it does not build another.
    @MainActor
    private final class TelevisionReceiverModel {
        let shuffle: ShuffleSession
        init(seed: UInt32) { shuffle = ShuffleSession(seed: seed) }
    }

    private final class PickGate: @unchecked Sendable {
        private let lock = NSLock()
        private var entered: CheckedContinuation<Void, Never>?
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                entered = continuation
                let pending = waiters
                waiters = []
                lock.unlock()
                for waiter in pending { waiter.resume() }
            }
        }

        func arrived() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if entered != nil {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }

        func release() {
            lock.lock()
            let continuation = entered
            entered = nil
            lock.unlock()
            continuation?.resume()
        }
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
            ShuffleEntry(id: $0.id, regionIds: $0.regions, beyond: $0.beyond, medium: "tv")
        }
    }

    private static func scope(_ name: String) -> ShuffleScope {
        ShuffleScope(rawValue: name) ?? .main
    }

    private static func deal(_ deck: inout ShuffleDeck, _ entries: [ShuffleEntry], scope: String, region: String?, playing: String?) -> ShuffleDraw? {
        deck.draw(entries: entries, medium: .tv, scope: Self.scope(scope), regionId: region, playing: playing)
    }
}

private struct ShuffleFixture: Decodable {
    struct Channel: Decodable {
        let id: String
        let regions: [String]
        let beyond: Bool
    }
    struct Draw: Decodable {
        let decks: [[String]]
    }
    let regionScope: String
    let channels: [Channel]
    let pools: [String: [String]]
    let seeds: [String: UInt32]
    let draws: [String: Draw]
}
