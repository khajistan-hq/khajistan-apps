import XCTest

/// Walks Pics/Vids with the Siri Remote: the notice, the stream, a filter, a picture, a video and
/// a Khajistan TV row (signed out), and keeps a screenshot of each stop. Strict about the app's own
/// elements and loose about what the network answers on the day.
final class PicsVidsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
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

    /// Presses toward `element` until it has focus, steering by where it sits against the focused
    /// control. Returns whether it got there.
    @discardableResult
    private func focus(_ element: XCUIElement, app: XCUIApplication, limit: Int = 40) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard element.exists, focused.exists else {
                XCUIRemote.shared.press(.down)
                pause(0.4)
                continue
            }
            let target = element.frame, here = focused.frame
            let dx = target.midX - here.midX, dy = target.midY - here.midY
            // A different row first (up or down), then along the row.
            if abs(dy) > max(here.height, target.height) * 0.6 {
                XCUIRemote.shared.press(dy > 0 ? .down : .up)
            } else {
                XCUIRemote.shared.press(dx > 0 ? .right : .left)
            }
            pause(0.4)
        }
        return element.exists && element.hasFocus
    }

    /// The notice is the first thing under the top bar: reach OK, press it once.
    private func dismissNotice(_ app: XCUIApplication) {
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The notice must come before the stream")
        XCTAssertTrue(focus(ok, app: app), "The notice's OK must take focus")
        XCUIRemote.shared.press(.select)
        pause(1)
        XCTAssertFalse(ok.exists, "OK must dismiss the notice")
    }

    func testNoticeThenTheStreamIsWalkable() {
        let app = launch()
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The adult notice must be the first thing on Pics/Vids")
        XCTAssertTrue(app.staticTexts["This archive holds adult material."].exists, "The notice carries the site's wording")
        XCTAssertTrue(app.buttons["adultNoticeDontAsk"].exists, "The notice offers Don't ask again")
        pause(3)
        screenshot("pv-01-notice", app: app)
        dismissNotice(app)

        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60), "The stream must show tiles")
        pause(6)
        XCTAssertTrue(app.buttons["pnvkind-all"].exists, "Filters must follow the notice")
        screenshot("pv-02-stream", app: app)

        // Down from the tabs into the stream, then a walk that must reach at least five tiles.
        for _ in 0..<6 where !focusedTile(app).exists { XCUIRemote.shared.press(.down); pause(0.5) }
        XCTAssertTrue(focusedTile(app).exists, "A tile must take focus")
        var seen = Set<String>()
        var log: [String] = []
        let walk: [XCUIRemote.Button] = [.right, .down, .left, .down, .right, .right, .down, .left, .down, .right]
        seen.insert(focusedTile(app).identifier)
        for press in walk {
            XCUIRemote.shared.press(press)
            pause(0.7)
            let id = focusedTile(app).exists ? focusedTile(app).identifier : "(off the stream)"
            seen.insert(id)
            log.append("\(press == .left ? "L" : press == .right ? "R" : press == .up ? "U" : "D")->\(id)")
        }
        print("PNVWALK " + log.joined(separator: " "))
        seen.remove("(off the stream)")
        XCTAssertGreaterThanOrEqual(seen.count, 5, "the walk must reach five tiles; walk: \(log)")
        screenshot("pv-03-walked", app: app)

        // Open the focused one, move on with right, back out.
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 20), "Select must open the viewer")
        pause(0.8)
        screenshot("pv-04a-viewer-overlay", app: app)
        pause(6)
        screenshot("pv-04b-viewer-clean", app: app)
        XCUIRemote.shared.press(.right)
        pause(6)
        screenshot("pv-05-viewer-next", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the stream")
        XCTAssertFalse(surface.exists)
    }

    /// Holding down in the stream reaches the end of the first page and the next one arrives.
    func testScrollingLoadsTheNextPage() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        let stream = app.otherElements["pnvStream"]
        XCTAssertTrue(stream.waitForExistence(timeout: 30))
        pause(3)
        let first = Int(stream.value as? String ?? "") ?? 0
        XCTAssertEqual(first, 60, "the first page is 60 rows")
        for _ in 0..<6 where !focusedTile(app).exists { XCUIRemote.shared.press(.down); pause(0.5) }
        var loaded = first
        for _ in 0..<80 {
            XCUIRemote.shared.press(.down)
            pause(0.35)
            loaded = Int(stream.value as? String ?? "") ?? loaded
            if loaded > first { break }
        }
        screenshot("pv-11-paged", app: app)
        XCTAssertGreaterThan(loaded, first, "walking to the end of the page must load the next one")
        XCTAssertEqual(loaded % 60, 0, "pages come in 60s")
    }

    func testFiltersNarrowTheStream() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        let count = app.staticTexts["pnvCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 30), "The count line must show")
        let everything = count.label

        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(focus(videos, app: app), "Videos must take focus")
        XCUIRemote.shared.press(.select)
        pause(8)
        XCTAssertNotEqual(count.label, everything, "Videos must narrow the count")
        screenshot("pv-06-videos", app: app)

        let region = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pnvregion-' AND NOT identifier ENDSWITH '-all'")).firstMatch
        XCTAssertTrue(region.exists, "A region tab must be offered")
        XCTAssertTrue(focus(region, app: app), "A region must take focus")
        XCUIRemote.shared.press(.select)
        pause(8)
        screenshot("pv-07-videos-in-region", app: app)
        XCTAssertTrue(tiles(app).firstMatch.exists || app.staticTexts["Nothing filed under this yet."].exists)
    }

    /// A Khajistan TV row and an account-hosted video, signed out. The row opens on its poster and
    /// says what it needs; the other plays.
    func testVideoAndKhajistanTVRow() {
        let app = launch()
        dismissNotice(app)
        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(videos.waitForExistence(timeout: 60))
        XCTAssertTrue(focus(videos, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        pause(8)

        let ktv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        let account = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-' AND NOT identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        XCTAssertTrue(account.exists, "An account video must be on the first page")
        XCTAssertTrue(focus(account, app: app), "An account video must take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["pnvViewerSurface"].waitForExistence(timeout: 20))
        pause(1)
        screenshot("pv-08a-video-overlay", app: app)
        pause(11)
        screenshot("pv-08b-video-playing", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))

        guard ktv.exists else {
            screenshot("pv-09-no-ktv-row-on-first-page", app: app)
            return
        }
        XCTAssertTrue(focus(ktv, app: app), "A Khajistan TV row must take focus")
        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["pnvViewerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20), "A Khajistan TV row signed out must say what it needs")
        pause(4)
        XCTAssertEqual(state.label, "Sign in to watch Khajistan Transmission.")
        screenshot("pv-09-ktv-signed-out", app: app)
        XCUIRemote.shared.press(.select)
        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "Select must open the sign-in sheet")
        screenshot("pv-10-ktv-sign-in-sheet", app: app)
        XCUIRemote.shared.press(.menu)
        pause(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))
    }
}
