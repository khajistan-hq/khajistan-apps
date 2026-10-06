import XCTest

/// Back (Menu) from any other section lands on the Receiver's atlas.
final class BackToAtlasUITests: XCTestCase {
    func testBackFromEverySectionReturnsToTheAtlas() {
        let app = XCUIApplication()
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the atlas must load")
        for section in ["Transmission", "Pics/Vids", "Account"] {
            // Up into the top bar, then right until the section is focused, then open it.
            for _ in 0..<4 { XCUIRemote.shared.press(.up) }
            let tab = app.buttons.matching(NSPredicate(format: "label ==[c] %@", section)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "the top bar must offer \\(section)")
            for _ in 0..<6 where !tab.hasFocus { XCUIRemote.shared.press(.right) }
            XCTAssertTrue(tab.hasFocus, "\\(section) must take focus in the top bar")
            XCUIRemote.shared.press(.select)
            XCTAssertFalse(regions.firstMatch.waitForExistence(timeout: 3), "\\(section) must replace the atlas")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "Back from \\(section) must return to the atlas")
        }
    }

    /// Back pressed in the top bar while a region is open pops to the map. The top bar sits
    /// outside the Receiver's stack, and this press used to leave the app (QA, 2026-10-06).
    func testBackFromTheTopBarOverARegionPopsToTheMap() {
        let app = XCUIApplication()
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the atlas must load")
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 where !focused.exists { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(focused.exists, "a region must take focus in the strip")
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(regions.firstMatch.waitForExistence(timeout: 5), "the region page must replace the map")
        for _ in 0..<8 { XCUIRemote.shared.press(.up) }
        XCTAssertTrue(app.buttons["Receiver"].hasFocus || app.buttons.matching(NSPredicate(format: "hasFocus == true AND label ==[c] 'Receiver'")).firstMatch.exists,
                      "focus must reach the top bar")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 15), "Back must pop to the map")
        XCTAssertEqual(app.state, .runningForeground, "and must not leave the app")
    }
}
