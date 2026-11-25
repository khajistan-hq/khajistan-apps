import XCTest

/// Back (Menu) from any other section lands on the Receiver's atlas.
final class BackToAtlasUITests: XCTestCase {
    func testBackFromEverySectionReturnsToTheAtlas() {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the atlas must load")
        for section in ["Transmission", "Pics/Vids", "Account"] {
            // Up into the top bar, then along it until the section is focused, then open it.
            let tab = app.buttons.matching(NSPredicate(format: "label ==[c] %@", section)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "the top bar must offer \(section)")
            XCTAssertTrue(kjFocusTopBar(tab, app: app), "\(section) must take focus in the top bar")
            XCUIRemote.shared.press(.select)
            XCTAssertFalse(regions.firstMatch.waitForExistence(timeout: 3), "\(section) must replace the atlas")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "Back from \(section) must return to the atlas")
        }
    }

    /// Back goes one step back: from Account to the Transmission it was opened from, then to the
    /// atlas (owner, 2026-11-04).
    func testBackStepsBackThroughSections() {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the atlas must load")
        func open(_ section: String) {
            let tab = app.buttons.matching(NSPredicate(format: "label ==[c] %@", section)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "the top bar must offer \(section)")
            XCTAssertTrue(kjFocusTopBar(tab, app: app), "\(section) must take focus in the top bar")
            XCUIRemote.shared.press(.select)
        }
        open("Transmission")
        XCTAssertFalse(regions.firstMatch.waitForExistence(timeout: 3), "Transmission must replace the atlas")
        let transmission = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'transmission'")).firstMatch
        XCTAssertTrue(transmission.waitForExistence(timeout: 15), "Transmission must show")
        open("Account")
        XCTAssertTrue(transmission.waitForNonExistence(timeout: 10), "Account must replace Transmission")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(transmission.waitForExistence(timeout: 10), "Back from Account must return to Transmission")
        XCTAssertFalse(regions.firstMatch.exists, "and not jump to the atlas")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "a second Back reaches the atlas")
        // Reaching the atlas ends the history: Back there never returns to Transmission.
        open("Transmission")
        XCTAssertTrue(transmission.waitForExistence(timeout: 15))
        open("Receiver")
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "the top bar returns to the atlas")
        // Back from the top bar is the press that reads the history (the front's content hands
        // Back to tvOS), so press it there.
        XCTAssertTrue(kjIntoTopBar(app), "Up must reach the top bar")
        XCTAssertTrue(app.buttons["nav-receiver"].hasFocus, "Back is pressed from the top bar's Receiver tab")
        XCUIRemote.shared.press(.menu)
        // Transmission takes seconds to draw, so give it the time it would need to come back.
        XCTAssertFalse(transmission.waitForExistence(timeout: 6), "Back on the atlas must not go back to Transmission")
        XCTAssertNotEqual(app.state, .runningForeground, "Back from the atlas, with nothing behind it, leaves the app")
    }

    /// The focus helper must also recover after the remote has moved below the region list.
    func testRegionListCanBeReachedFromTheShelfBelow() {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let genre = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'genre-' AND hasFocus == true")).firstMatch
        for _ in 0..<12 where !genre.exists {
            XCUIRemote.shared.press(.down)
            kjPause(0.35)
        }
        XCTAssertTrue(genre.exists, "start on the Themes row below the front")
        XCTAssertTrue(kjFocusRegions(app), "focus must return upward to the region list")
        XCTAssertTrue(regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                      "an actual region row must have focus")
    }

    /// Back pressed in the top bar while a region is open pops to the map. The top bar sits
    /// outside the Receiver's stack, and this press used to leave the app (QA, 2026-10-06).
    func testBackFromTheTopBarOverARegionPopsToTheMap() {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the atlas must load")
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusRegions(app), "focus must reach the region list")
        XCTAssertTrue(focused.exists, "a region must take focus in the list")
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(regions.firstMatch.waitForExistence(timeout: 5), "the region page must replace the map")
        XCTAssertTrue(kjIntoTopBar(app), "focus must reach the top bar")
        XCTAssertTrue(app.buttons["nav-receiver"].hasFocus, "Up from a region page lands on the Receiver tab")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "Back must pop to the map")
        XCTAssertEqual(app.state, .runningForeground, "and must not leave the app")
    }
}
