import XCTest

/// Home carries every part of Khajistan (owner, 2026-10-29: "all nav carousels should show up in
/// home", and one "should be able to move down a page in home"). From the foot of the front, a press
/// down at a time walks the shelves under the front to the last one; each shelf reached is
/// photographed. Transmission, the Reading Room and Pics/Vids need no password and must be there;
/// the Madrassa, the Bazaar and Chat are reported when their feeds answer.
final class HomeRowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    /// The shelf a focused card belongs to, by its identifier.
    private func shelf(of id: String) -> String? {
        let prefixes: [(String, String)] = [
            ("genre-news-", "news"), ("genre-music-", "music"), ("genre-", "genres"),
            ("home-door-", "doors"), ("cameras-", "cameras"), ("film-", "films"), ("home-transmission-", "transmission"),
            ("rr-title-", "reading"), ("home-all-the Reading Room", "reading"),
            ("home-pnv-", "picsvids"), ("home-all-Pics/Vids", "picsvids"),
            ("home-post-", "madrassa"), ("home-all-the Madrassa", "madrassa"),
            ("home-product-", "bazaar"), ("home-all-the Bazaar", "bazaar"), ("home-chat-", "chat"),
        ]
        return prefixes.first { id.hasPrefix($0.0) }?.1
    }

    func testDownWalksEveryShelfOnHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the front draws its regions")
        kjPause(8)   // the shelves load a moment after the front
        XCTAssertTrue(kjFocusFrontFoot(app), "focus reaches the foot of the front")
        var reached: [String] = []
        // The genre shelves (News, Music, Film & drama, ...) sit between the regions and the rest.
        for _ in 0..<26 {
            XCUIRemote.shared.press(.down)
            kjPause(1.2)
            guard let name = shelf(of: focusedID(app)) else { continue }
            if reached.last != name {
                reached.append(name)
                kjScreenshot("home-\(reached.count)-\(name)", app: app)
            }
        }
        print("KJHOME reached: \(reached.joined(separator: " > "))")
        // Transmission's shelf waits for its schedule, which is behind the preview password until
        // launch (a test run has none), so it is not required here.
        // The shelves this build carries (StoreBuild.includes): the store build has no Reading Room,
        // and Pics/Vids only for Friends; its doors shelf shows only with two doors or more.
        var required = ["news", "music"]
        #if !KJ_APP_STORE
        required += ["doors", "reading", "picsvids"]
        #elseif KJ_FRIENDS
        required += ["doors", "picsvids"]
        #endif
        for required in required {
            XCTAssertTrue(reached.contains(required), "down reaches the \(required) shelf; reached \(reached)")
        }

        // Up walks back to the front.
        for _ in 0..<26 where !focusedID(app).hasPrefix("region-") && focusedID(app) != "beyondTheAtlas" {
            XCUIRemote.shared.press(.up)
            kjPause(0.6)
        }
        let back = focusedID(app)
        XCTAssertTrue(back.hasPrefix("region-") || back == "beyondTheAtlas", "up returns to the front, got \(back)")
    }

    /// The recorded list's first four News cards, all Indus channels.
    static let recordedNewsFirst = ["genre-news-swept-pk-24-news-hd", "genre-news-swept-pk-365-news",
                                    "genre-news-swept-pk-abn-news", "genre-news-swept-pk-capital-tv"]

    /// News is a shelf on the front (owner, 2026-11-04), and its first four cards get live stills,
    /// which VoiceOver reads as "live picture". Stills are taken one at a time, region cards first.
    ///
    /// Stills are kept by channel, and a region card's still shows on any card of that channel.
    /// In the recorded list the first four News cards are all Indus channels, and the Indus card
    /// takes one still, so a shelf that asked for none would show one picture there at most. The
    /// local test video always gives a frame, so by default all four must be pictured: that is the
    /// proof the shelf asks.
    ///
    /// A live run (`TEST_RUNNER_KJ_LIVE_RECEIVER=1`) reads the live lists, whose first News cards
    /// can each be a region's own pick, so it cannot prove the shelf asks; it checks that News
    /// gets a picture. A still needs the carrier to reach the runner: on 2026-11-15 the first four
    /// News channels were all off air (run 43681581060). With no News picture, the run is skipped
    /// when a card on another shelf got one, and fails when no card did. That picture can be a
    /// region card's still, so the skip shows the stills store works, not that the shelf asks.
    /// Radio cards never get stills.
    func testNewsShelfCarriesLivePictures() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let news = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-news-'"))
        XCTAssertTrue(news.firstMatch.waitForExistence(timeout: 90), "the front carries a News shelf")
        // Read again on each look: a shelf builds its cards as it comes on screen.
        func firstFour() -> [XCUIElement] { Array(news.allElementsBoundByIndex.prefix(4)) }
        func pictured(_ cards: [XCUIElement]) -> Int { cards.filter { $0.label.contains("live picture") }.count }
        let wanted = kjLiveMedia ? 1 : 4
        if !kjLiveMedia {
            // The proof above holds only while these four are all Indus channels.
            let four = NSPredicate { _, _ in firstFour().count == 4 }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: four, object: nil)], timeout: 10)
            XCTAssertEqual(firstFour().map(\.identifier), Self.recordedNewsFirst, "the recorded News shelf starts with four Indus channels")
        }
        let asked = Date()
        let enough = NSPredicate { _, _ in pictured(firstFour()) >= wanted }
        let got = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enough, object: nil)], timeout: 120) == .completed
        let newsFirst = firstFour()
        print("KJNEWS first \(newsFirst.map(\.identifier)), pictured \(pictured(newsFirst)), wanted \(wanted), in \(Int(Date().timeIntervalSince(asked))) s of 120")
        XCTAssertTrue(kjFocusFrontFoot(app), "focus reaches the foot of the front")
        if !got {
            let names = newsFirst.map(\.label).joined(separator: "; ")
            guard kjLiveMedia else {
                XCTFail("the first News cards get live stills from the local test video: pictured \(pictured(newsFirst)) of 4: \(names)")
                return
            }
            let elsewhere = app.buttons.matching(NSPredicate(format: "(identifier BEGINSWITH 'cameras-' OR (identifier BEGINSWITH 'genre-' AND NOT identifier BEGINSWITH 'genre-news-')) AND label CONTAINS 'live picture'"))
            let stillsWork = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in elsewhere.count > 0 }, object: nil)], timeout: 60) == .completed
            let others = elsewhere.allElementsBoundByIndex.map(\.identifier)
            print("KJNEWS live, no News picture; pictured elsewhere: \(others)")
            guard stillsWork else {
                XCTFail("no card on any shelf got a live still: the stills are broken, not News's carriers. News: \(names)")
                return
            }
            throw XCTSkip("None of the first News cards gave a frame in 120 s while \(others.count) cards on other shelves did (\(others.joined(separator: ", "))): \(names)")
        }
        XCUIRemote.shared.press(.down)
        kjPause(1.5)
        kjScreenshot("home-news-pictures", app: app)
    }
}
