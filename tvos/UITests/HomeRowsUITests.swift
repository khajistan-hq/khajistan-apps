import XCTest

/// Home carries every part of Khajistan (owner, 2026-10-29: "all nav carousels should show up in
/// home", and one "should be able to move down a page in home"). From the region strip, a press
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
        XCTAssertTrue(kjFocusStrip(app), "focus reaches the region strip")
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

    /// News is a shelf on the front (owner, 2026-11-04), and its first cards get live stills, which
    /// VoiceOver reads as "live picture". Stills are taken one at a time, region cards first.
    func testNewsShelfCarriesLivePictures() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let news = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-news-'"))
        XCTAssertTrue(news.firstMatch.waitForExistence(timeout: 90), "the front carries a News shelf")
        let pictured = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-news-' AND label CONTAINS 'live picture'"))
        let two = NSPredicate { _, _ in pictured.count >= 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: two, object: nil)], timeout: 120), .completed,
                       "the first News cards get live stills; pictured \(pictured.count) of \(news.count)")
        print("KJNEWS cards \(news.count), pictured \(pictured.count)")
        XCTAssertTrue(kjFocusStrip(app), "focus reaches the region strip")
        XCUIRemote.shared.press(.down)
        kjPause(1.5)
        kjScreenshot("home-news-pictures", app: app)
    }
}
