import XCTest

/// The account's liked channels are a shelf on Home (owner, 2026-11-08: "add liked channels on
/// homepage for an account so they are easily accessible"), the last one on the page since
/// 2026-11-21 (owner: "put liked video at the botton of the page"). A Debug build takes the
/// likes from `-kjlikedrefs`, so no account is signed in here.
final class LikedShelfUITests: XCTestCase {
    /// Newest first. The last ref names no channel and must not be drawn.
    /// The lists are the recording only (`-kjfixturesonly`): live, 24 News HD left the dial on
    /// 2026-11-15 and five liked became four (CI 43756089230).
    private static let refs = "channel:al-arabiya,channel:24-news-hd,channel:radio-srood,channel:afghanistan-international,channel:afaq-fm-98-7,channel:no-such-channel"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    func testLikedShelfIsTheLastOnHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES", "-kjlikedrefs", Self.refs, "-kjfixturesonly", "YES"]
        kjLaunch(app)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 90), "the front carries a Liked shelf")
        kjPause(4)
        // The row is lazy, so cards past the screen's edge are not built: the heading's count is read.
        let heading = app.staticTexts["shelf-liked"]
        XCTAssertTrue(heading.exists, "the shelf has its heading")
        XCTAssertEqual(heading.label, "Liked, 5 live", "five liked channels drawn, the unknown ref left out")
        XCTAssertTrue(cards.element(boundBy: 0).label.hasPrefix("Al Arabiya"), "newest like first, got \(cards.element(boundBy: 0).label)")
        XCTAssertFalse(cards.element(boundBy: 0).label.contains("Liked"), "no second 'Liked' on a card of the Liked shelf")

        XCTAssertTrue(kjFocusAtlasSwitch(app), "focus reaches the atlas switch")
        XCUIRemote.shared.press(.down)
        kjPause(1)
        XCTAssertFalse(focusedID(app).hasPrefix("liked-"), "Liked is not the first shelf under the front, got \(focusedID(app))")
        XCTAssertTrue(kjFocus(cards.firstMatch, app: app, limit: 80), "focus reaches the Liked shelf")
        XCUIRemote.shared.press(.down)
        kjPause(6)   // stills arrive one at a time
        XCTAssertTrue(focusedID(app).hasPrefix("liked-"), "nothing under Liked: down stays on it, got \(focusedID(app))")
        kjScreenshot("liked-shelf-focused", app: app)

        let firstId = String(focusedID(app).dropFirst("liked-".count))
        XCUIRemote.shared.press(.select)
        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 30), "Select opens the player")
        XCTAssertEqual(current.label, firstId, "the player plays the liked channel that had focus")
        kjPause(3)
        // The player's Like reads the account, which `-kjlikedrefs` stands in for only on the shelf,
        // so this picture shows Like unlit. A signed-in account shows it lit.
        kjScreenshot("liked-player", app: app)
    }

    /// Signed out and with no likes there is no shelf, and down from the front goes to the themes.
    func testNoLikesNoShelf() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let news = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-'"))
        XCTAssertTrue(news.firstMatch.waitForExistence(timeout: 90), "the front's themes load")
        XCTAssertFalse(app.descendants(matching: .any)["shelf-liked"].exists, "no Liked shelf without likes")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'")).count, 0)
    }

    /// The shelf, focused, in the two night skins (day is photographed above).
    func testLikedShelfInEverySkin() {
        for skin in ["grove", "smut"] {
            let app = XCUIApplication()
            app.launchArguments = ["-kjskin", skin, "-kjtab", "receiver", "-kjnoautoplay", "YES", "-kjlikedrefs", Self.refs, "-kjfixturesonly", "YES"]
            kjLaunch(app)
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 90), "Liked shows in \(skin)")
            XCTAssertTrue(kjFocusAtlasSwitch(app), "focus reaches the atlas switch in \(skin)")
            XCUIRemote.shared.press(.down)
            kjPause(1.5)
            XCTAssertTrue(focusedID(app).hasPrefix("liked-"), "down lands on Liked in \(skin), got \(focusedID(app))")
            // Names only, as the Themes row (owner, 2026-11-21): a plate two lines of text high,
            // never a picture card (236 or more), and no "live picture" on any of them.
            let first = cards.firstMatch
            XCTAssertLessThan(first.frame.height, 160, "a liked channel is a name, with no picture; height \(first.frame.height)")
            let pictured = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-' AND label CONTAINS 'live picture'"))
            XCTAssertEqual(pictured.count, 0, "no liked channel carries a picture in \(skin)")
            kjScreenshot("liked-shelf-\(skin)", app: app)
            app.terminate()
        }
    }
}
