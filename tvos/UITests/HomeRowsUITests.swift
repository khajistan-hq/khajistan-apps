import XCTest

/// Home carries every part of Khajistan (owner, 2026-10-29: "all nav carousels should show up in
/// home", and one "should be able to move down a page in home"). From the front (the atlas switch), a press
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
            ("genre-", "themes"),
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
        XCTAssertTrue(kjFocusAtlasSwitch(app), "focus reaches the atlas switch")
        var reached: [String] = []
        // The Themes row sits between the regions and the rest.
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
        var required = ["themes"]
        #if !KJ_APP_STORE
        required += ["reading"]
        #endif
        for required in required {
            XCTAssertTrue(reached.contains(required), "down reaches the \(required) shelf; reached \(reached)")
        }
        // No Screening Room or Transmission shelf on Home; CCTV is the foot of the page (owner,
        // 2026-11-19).
        XCTAssertFalse(reached.contains("films") || reached.contains("transmission"), "Home carries no film or Transmission shelf; reached \(reached)")
        XCTAssertEqual(reached.last, "cameras", "CCTV is the last shelf; reached \(reached)")
        // Off Home since 2026-11-21 (owner): the shelf of every part of Khajistan, and Pics/Vids.
        for gone in ["doors", "picsvids"] {
            XCTAssertFalse(reached.contains(gone), "no \(gone) shelf on Home; reached \(reached)")
        }

        // Up walks back to the front.
        for _ in 0..<26 where !focusedID(app).hasPrefix("region-") && !["beyondTheAtlas", "shuffle"].contains(focusedID(app)) {
            XCUIRemote.shared.press(.up)
            kjPause(0.6)
        }
        let back = focusedID(app)
        XCTAssertEqual(back, "shuffle", "up returns to the front at Surf, not the A–Z list or the switch")
    }

    /// The themes are one row of names with no pictures (owner, 2026-11-18), and Select on one
    /// plays a channel of that theme.
    func testThemesAreNamesAndPlay() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let news = app.buttons["genre-news"]
        XCTAssertTrue(news.waitForExistence(timeout: 90), "the front carries the News theme")
        XCTAssertTrue(news.label.hasSuffix("live"), "a theme reads its name and its live count, got \(news.label)")
        let themes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-'"))
        XCTAssertLessThanOrEqual(themes.count, 7, "one button a theme, not one a channel; got \(themes.count)")
        // A theme is a name: its plate is two lines of text (67 points), where a channel card is 190 or more.
        XCTAssertLessThan(news.frame.height, 160, "a theme is a name, with no picture; height \(news.frame.height)")
        XCTAssertTrue(kjFocusAtlasSwitch(app), "focus reaches the foot of the front")
        XCUIRemote.shared.press(.down)
        kjPause(1.5)
        kjScreenshot("home-themes", app: app)
        XCTAssertTrue(app.buttons["genre-news"].hasFocus, "down from the front lands on News, the first theme")
        // Back from the player returns to the theme pressed, not to News.
        XCUIRemote.shared.press(.right)
        kjPause(0.7)
        XCTAssertTrue(app.buttons["genre-music"].hasFocus, "right from News is Music")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["currentChannel"].waitForExistence(timeout: 30), "Select on a theme opens the player")
        // A theme plays a random channel. Over a playing picture the first Back only hides the
        // strip, as on Apple's app, and the second leaves; radio leaves on the first. One Back was
        // a coin toss on which channel came up.
        let player = app.staticTexts["currentChannel"]
        for _ in 0..<3 where player.exists {
            XCUIRemote.shared.press(.menu)
            kjPause(1.5)
        }
        XCTAssertFalse(player.exists, "Back closes the player")
        XCTAssertTrue(app.buttons["genre-music"].waitForExistence(timeout: 15), "the home page is back under the player")
        kjPause(1.5)
        XCTAssertTrue(app.buttons["genre-music"].hasFocus, "Back from the player returns to the theme pressed")
        // From below, focus comes back to the theme last focused, not to the one above the card left.
        XCUIRemote.shared.press(.down)
        kjPause(1)
        XCTAssertFalse(app.buttons["genre-music"].hasFocus, "down leaves the themes")
        XCUIRemote.shared.press(.up)
        kjPause(1)
        XCTAssertTrue(app.buttons["genre-music"].hasFocus, "up into the themes returns to the theme last focused")
    }
}
