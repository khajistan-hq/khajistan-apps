import XCTest

/// The account's liked channels are the first shelf under the map (owner, 2026-11-08: "add liked
/// channels on homepage for an account so they are easily accessible"). A Debug build takes the
/// likes from `-kjlikedrefs`, so no account is signed in here.
final class LikedShelfUITests: XCTestCase {
    /// Newest first. The last ref names no channel and must not be drawn.
    private static let refs = "channel:al-arabiya,channel:24-news-hd,channel:radio-srood,channel:afghanistan-international,channel:afaq-fm-98-7,channel:no-such-channel"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    func testLikedShelfIsOnePressDownFromTheMap() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES", "-kjlikedrefs", Self.refs]
        kjLaunch(app)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 90), "the front carries a Liked shelf")
        kjPause(4)
        // The row is lazy, so cards past the screen's edge are not built: the heading's count is read.
        let heading = app.staticTexts["shelf-liked"]
        XCTAssertTrue(heading.exists, "the shelf has its heading")
        XCTAssertEqual(heading.label, "Liked, 5 channels", "five liked channels drawn, the unknown ref left out")
        XCTAssertTrue(cards.element(boundBy: 0).label.hasPrefix("Al Arabiya"), "newest like first, got \(cards.element(boundBy: 0).label)")
        XCTAssertFalse(cards.element(boundBy: 0).label.contains("Liked"), "no second 'Liked' on a card of the Liked shelf")

        XCTAssertTrue(kjFocusStrip(app), "focus reaches the region strip")
        XCUIRemote.shared.press(.down)
        kjPause(6)   // stills arrive one at a time
        XCTAssertTrue(focusedID(app).hasPrefix("liked-"), "one press down from the strip lands on Liked, got \(focusedID(app))")
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

    /// Signed out and with no likes there is no shelf, and down from the strip goes to the genres.
    func testNoLikesNoShelf() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let news = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-'"))
        XCTAssertTrue(news.firstMatch.waitForExistence(timeout: 90), "the front's genre shelves load")
        XCTAssertFalse(app.descendants(matching: .any)["shelf-liked"].exists, "no Liked shelf without likes")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'")).count, 0)
    }

    /// The shelf, focused, in the two night skins (day is photographed above).
    func testLikedShelfInEverySkin() {
        for skin in ["grove", "smut"] {
            let app = XCUIApplication()
            app.launchArguments = ["-kjskin", skin, "-kjtab", "receiver", "-kjnoautoplay", "YES", "-kjlikedrefs", Self.refs]
            kjLaunch(app)
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-'"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 90), "Liked shows in \(skin)")
            XCTAssertTrue(kjFocusStrip(app), "focus reaches the region strip in \(skin)")
            XCUIRemote.shared.press(.down)
            kjPause(6)   // stills arrive one at a time
            XCTAssertTrue(focusedID(app).hasPrefix("liked-"), "down lands on Liked in \(skin), got \(focusedID(app))")
            let pictured = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liked-' AND label CONTAINS 'live picture'"))
            let one = NSPredicate { _, _ in pictured.count >= 1 }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: one, object: nil)], timeout: 60), .completed,
                           "a liked television card gets a live still in \(skin)")
            kjScreenshot("liked-shelf-\(skin)", app: app)
            app.terminate()
        }
    }
}
