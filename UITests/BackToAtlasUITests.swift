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
}
