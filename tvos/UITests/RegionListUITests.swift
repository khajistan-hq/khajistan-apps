import XCTest

/// The A–Z region list at the right of the map (Joey, 2026-11-02). Right from Surf reaches it,
/// its names run alphabetically, Down walks them with the map lit for the one focused, and Select
/// opens the region with its television and its radio on shelves of their own.
final class RegionListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testListIsAlphabeticalAndOpensARegion() {
        let app = XCUIApplication()
        kjLaunch(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'regionList-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "the list is on the front")
        kjPause(2)

        let labels = rows.allElementsBoundByIndex.map(\.label)
        XCTAssertGreaterThan(labels.count, 5, "every region that opens channels is listed")
        let sorted = labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(labels, sorted, "the list runs A to Z")

        let focusedRow = rows.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<6 where !focusedRow.exists { XCUIRemote.shared.press(.right); kjPause(0.4) }
        XCTAssertTrue(focusedRow.exists, "Right from the sidebar reaches the list")
        let first = focusedRow.identifier
        XCUIRemote.shared.press(.down)
        kjPause(0.5)
        XCTAssertNotEqual(focusedRow.identifier, first, "Down walks the list")
        kjScreenshot("region-list-lit", app: app)

        XCTAssertTrue(kjFocus(app.buttons["regionList-indus"], app: app), "the remote reaches Indus in the list")
        kjScreenshot("region-list-indus", app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["shelf-tv"].waitForExistence(timeout: 60), "Indus opens on its television")
        XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].exists, "and its radio, on a shelf of its own")
    }
}
