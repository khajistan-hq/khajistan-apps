import XCTest

/// The A–Z region list at the right of the map (Joey, 2026-11-02), the front's one way to a region
/// since the front was simplified (owner, 2026-11-17). Right from Surf reaches it, its names run
/// alphabetically, Down walks them with the map lit for the one focused, and Select opens the
/// region with its television and its radio on shelves of their own.
final class RegionListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testListIsAlphabeticalAndOpensARegion() {
        let app = XCUIApplication()
        kjLaunch(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
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

        XCTAssertTrue(kjFocus(app.buttons["region-indus"], app: app), "the remote reaches Indus in the list")
        kjScreenshot("region-list-indus", app: app)
        let map = app.descendants(matching: .any).matching(identifier: "atlasMap").firstMatch
        XCTAssertEqual(map.value as? String, "indus", "the map lights the region the list has focused")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["shelf-tv"].waitForExistence(timeout: 60), "Indus opens on its television")
        XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].exists, "and its radio, on a shelf of its own")
    }

    /// The simplified front (owner, 2026-11-17): each region once, in the list, with no picture
    /// strip repeating them; Surf with one row of choices, All, TV and Radio, and no genre row.
    func testFrontShowsEachRegionOnceAndOneRowOfSurfChoices() {
        let app = XCUIApplication()
        kjLaunch(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "the list is on the front")
        kjPause(3)
        let ids = rows.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(ids.count, Set(ids).count, "each region is on the front once: \(ids)")
        let inList = app.descendants(matching: .any).matching(identifier: "regionList").firstMatch.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertEqual(inList.count, rows.count, "every region control is a row of the list")

        let medium = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shuffle-medium-'"))
        XCTAssertEqual(medium.allElementsBoundByIndex.map(\.label), ["All", "TV", "Radio"], "one row: All, TV, Radio")
        let genre = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'surf-genre-'"))
        XCTAssertEqual(genre.count, 0, "no genre row on the front")
        XCTAssertTrue(app.buttons["shuffle"].exists, "Surf is on the front")
        XCTAssertTrue(app.buttons["beyondTheAtlas"].exists, "the switch is on the front")
        // The negative case: with Surf focused at launch, the map lights nothing.
        let map = app.descendants(matching: .any).matching(identifier: "atlasMap").firstMatch
        XCTAssertTrue(map.exists, "the map is on the front")
        XCTAssertEqual((map.value as? String) ?? "", "", "no region is lit while focus is off the list")
        kjScreenshot("front-simplified", app: app)
    }
}
