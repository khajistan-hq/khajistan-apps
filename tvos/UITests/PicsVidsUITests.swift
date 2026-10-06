import XCTest

/// Walks Pics/Vids with the Siri Remote: the notice, the shelves (one per region), the kind filter,
/// a picture, a video and a Khajistan TV row (signed out), and keeps a screenshot of each stop. Strict about the app's own
/// elements and loose about what the network answers on the day.
final class PicsVidsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids"]
        app.launch()
        return app
    }

    private func tiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
    }

    private func focusedTile(_ app: XCUIApplication) -> XCUIElement {
        tiles(app).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// One element per region shelf; its value is the number of objects drawn so far.
    private func shelves(_ app: XCUIApplication) -> XCUIElementQuery {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'pnv-shelf-'"))
    }

    /// The shelf that holds the focused tile, by its identifier, or nil.
    private func focusedShelf(_ app: XCUIApplication) -> String? {
        for index in 0..<shelves(app).count {
            let shelf = shelves(app).element(boundBy: index)
            if shelf.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists { return shelf.identifier }
        }
        return nil
    }

    /// The shelves' headings, as one line: region and count, west to east.
    private func headings(_ app: XCUIApplication) -> String {
        let names = ["Maghreb", "Mashriq", "Anatolia", "Persia", "Khorasan", "Indus"]
        let format = names.map { "label BEGINSWITH '\($0)'" }.joined(separator: " OR ")
        let texts = app.staticTexts.matching(NSPredicate(format: format))
        return (0..<texts.count).map { texts.element(boundBy: $0).label }.joined(separator: " | ")
    }

    /// The notice is the first thing under the top bar: reach OK, press it once.
    private func dismissNotice(_ app: XCUIApplication) {
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The notice must come before the stream")
        XCTAssertTrue(kjFocus(ok, app: app), "The notice's OK must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(1)
        XCTAssertFalse(ok.exists, "OK must dismiss the notice")
    }

    func testNoticeThenTheShelvesAreWalkable() {
        let app = launch()
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The adult notice must be the first thing on Pics/Vids")
        XCTAssertTrue(app.staticTexts["This archive holds adult material."].exists, "The notice carries the site's wording")
        XCTAssertTrue(app.buttons["adultNoticeDontAsk"].exists, "The notice offers Don't ask again")
        kjPause(3)
        kjScreenshot("pv-01-notice", app: app)
        dismissNotice(app)

        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60), "The shelves must show tiles")
        kjPause(6)
        XCTAssertTrue(app.buttons["pnvkind-all"].exists, "The filter must follow the notice")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pnvregion-'")).firstMatch.exists, "the shelves replace the region tabs")
        kjScreenshot("pv-02-shelves", app: app)
        print("PNVHEADINGS " + headings(app))

        // Down from the filter into the first shelf, then a walk that must reach at least six
        // tiles on at least two shelves.
        for _ in 0..<6 where !focusedTile(app).exists { XCUIRemote.shared.press(.down); kjPause(0.5) }
        XCTAssertTrue(focusedTile(app).exists, "A tile must take focus")
        var seen = Set<String>()
        var onShelves = Set<String>()
        var log: [String] = []
        let walk: [XCUIRemote.Button] = [.right, .right, .right, .down, .right, .down, .left, .left, .down, .right]
        seen.insert(focusedTile(app).identifier)
        if let shelf = focusedShelf(app) { onShelves.insert(shelf) }
        for press in walk {
            XCUIRemote.shared.press(press)
            kjPause(0.8)
            let id = focusedTile(app).exists ? focusedTile(app).identifier : "(off the shelves)"
            seen.insert(id)
            if let shelf = focusedShelf(app) { onShelves.insert(shelf) }
            log.append("\(press == .left ? "L" : press == .right ? "R" : press == .up ? "U" : "D")->\(id)")
        }
        print("PNVWALK " + log.joined(separator: " ") + " shelves=" + onShelves.sorted().joined(separator: ","))
        seen.remove("(off the shelves)")
        XCTAssertGreaterThanOrEqual(seen.count, 6, "the walk must reach six tiles; walk: \(log)")
        XCTAssertGreaterThanOrEqual(onShelves.count, 2, "down must move from one region's shelf to the next; shelves: \(onShelves)")
        kjScreenshot("pv-03-walked", app: app)

        // Open the focused one, move on with right, back out.
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 20), "Select must open the viewer")
        kjPause(0.8)
        kjScreenshot("pv-04a-viewer-overlay", app: app)
        kjPause(6)
        kjScreenshot("pv-04b-viewer-clean", app: app)
        XCUIRemote.shared.press(.right)
        kjPause(6)
        kjScreenshot("pv-05-viewer-next", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelves")
        XCTAssertFalse(surface.exists)
    }

    /// Walking right along a shelf to its end reaches the next page of that shelf.
    func testScrollingLoadsTheNextPage() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(6)
        // A shelf with a first page of 60 and more behind it: the first one that has.
        var wanted: XCUIElement?
        for index in 0..<shelves(app).count {
            let shelf = shelves(app).element(boundBy: index)
            if Int(shelf.value as? String ?? "") == 60 { wanted = shelf; break }
        }
        guard let shelf = wanted else { return XCTFail("a region with more than one page must be on the page") }
        let first = Int(shelf.value as? String ?? "") ?? 0
        let tile = shelf.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        XCTAssertTrue(kjFocus(tile, app: app), "a tile on the shelf must take focus")
        var loaded = first
        for _ in 0..<90 {
            XCUIRemote.shared.press(.right)
            kjPause(0.3)
            loaded = Int(shelf.value as? String ?? "") ?? loaded
            if loaded > first { break }
        }
        kjScreenshot("pv-11-paged", app: app)
        XCTAssertGreaterThan(loaded, first, "walking to the end of the page must load the next one")
        XCTAssertEqual(loaded % 60, 0, "pages come in 60s")
    }

    func testFiltersNarrowTheShelves() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(6)
        let everything = headings(app)
        XCTAssertFalse(everything.isEmpty, "the shelves must carry headings with their counts")

        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(kjFocus(videos, app: app), "Videos must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(10)
        let narrowed = headings(app)
        print("PNVHEADINGS everything=[\(everything)] videos=[\(narrowed)]")
        XCTAssertNotEqual(narrowed, everything, "Videos must narrow every shelf's count")
        XCTAssertTrue(tiles(app).firstMatch.exists, "the shelves still show tiles")
        kjScreenshot("pv-06-videos", app: app)

        let pictures = app.buttons["pnvkind-image"]
        XCTAssertTrue(pictures.exists, "Pictures is offered")
        XCTAssertTrue(kjFocus(pictures, app: app), "Pictures must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(10)
        XCTAssertNotEqual(headings(app), narrowed, "Pictures must differ from Videos")
        kjScreenshot("pv-07-pictures", app: app)
    }

    /// A Khajistan TV row and an account-hosted video, signed out. The row opens on its poster and
    /// says what it needs; the other plays.
    func testVideoAndKhajistanTVRow() {
        let app = launch()
        dismissNotice(app)
        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(videos.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocus(videos, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(8)

        let ktv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        let account = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-' AND NOT identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        XCTAssertTrue(account.exists, "An account video must be on the first page")
        XCTAssertTrue(kjFocus(account, app: app), "An account video must take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["pnvViewerSurface"].waitForExistence(timeout: 20))
        kjPause(1)
        kjScreenshot("pv-08a-video-overlay", app: app)
        kjPause(11)
        kjScreenshot("pv-08b-video-playing", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))

        guard ktv.exists else {
            kjScreenshot("pv-09-no-ktv-row-on-first-page", app: app)
            return
        }
        XCTAssertTrue(kjFocus(ktv, app: app), "A Khajistan TV row must take focus")
        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["pnvViewerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20), "A Khajistan TV row signed out must say what it needs")
        kjPause(4)
        XCTAssertEqual(state.label, "Sign in to watch Khajistan Transmission.")
        kjScreenshot("pv-09-ktv-signed-out", app: app)
        XCUIRemote.shared.press(.select)
        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "Select must open the sign-in sheet")
        kjScreenshot("pv-10-ktv-sign-in-sheet", app: app)
        XCUIRemote.shared.press(.menu)
        kjPause(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))
    }
}
