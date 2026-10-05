import XCTest

/// The Screening Room, from the Receiver's front and from a region: open the shelf, walk the posters
/// with the remote, open a film, play its preview, and ask for the full film signed out.
///
/// vod.json is behind the site password (LAUNCH_RESTRICTED in archive/_worker.js), and a test does
/// not hold that password. The tests therefore read the catalogue from a local server of the archive
/// tree, named by TEST_RUNNER_KJ_FILMS_ORIGIN (e.g. http://127.0.0.1:8831), which the app takes in a
/// Debug build through `-kjfilms`. Previews still come from Cloudflare Stream, and vod-token is asked
/// for real: signed out, the app answers without a request, as the site does.
final class FilmsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() throws -> XCUIApplication {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin]
        app.launch()
        return app
    }

    private func films(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
    }

    private func focusedFilm(_ app: XCUIApplication) -> XCUIElement {
        films(app).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testShelfWalkPreviewAndFullFilmSignedOut() throws {
        let app = try launch()

        let entry = app.buttons["screeningRoom"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "The Receiver must offer the Screening Room once vod.json has loaded")
        XCTAssertTrue(kjFocus(entry, app: app), "The Screening Room row must take focus")
        kjScreenshot("vod-01-receiver-row", app: app)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 30), "The shelf must list films")
        kjPause(4)   // the posters arrive
        kjScreenshot("vod-02-shelf", app: app)

        for _ in 0..<6 where !focusedFilm(app).exists { XCUIRemote.shared.press(.down); kjPause(0.5) }
        XCTAssertTrue(focusedFilm(app).exists, "A film must take focus")
        var seen = Set([focusedFilm(app).identifier])
        var log: [String] = []
        for press in [XCUIRemote.Button.right, .right, .right, .down, .left, .left, .down, .right] {
            XCUIRemote.shared.press(press)
            kjPause(0.8)
            let id = focusedFilm(app).exists ? focusedFilm(app).identifier : "(off the grid)"
            seen.insert(id)
            log.append("\(press == .left ? "L" : press == .right ? "R" : "D")->\(id)")
        }
        print("FILMWALK " + log.joined(separator: " "))
        seen.remove("(off the grid)")
        XCTAssertGreaterThanOrEqual(seen.count, 5, "the walk must reach five films; walk: \(log)")
        kjScreenshot("vod-03-walked", app: app)

        // Back up the two rows the walk went down, and left to the first film, which has a preview.
        for _ in 0..<2 { XCUIRemote.shared.press(.up); kjPause(0.6) }
        for _ in 0..<4 { XCUIRemote.shared.press(.left); kjPause(0.5) }
        let chosen = focusedFilm(app).identifier
        XCTAssertEqual(chosen, "film-showgirls-of-pakistan-2021-khajistan")
        print("FILMCHOSEN \(chosen)")
        XCUIRemote.shared.press(.select)

        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 30), "The film's player must show its state")
        for _ in 0..<45 where state.label != "Playing" { kjPause(1) }
        XCTAssertEqual(state.label, "Playing", "the preview must play")
        kjScreenshot("vod-04-preview-with-panel", app: app)
        kjPause(5)
        kjScreenshot("vod-05-preview-picture", app: app)

        // A press wakes the panel with Watch the full film focused, and a second press is Watch.
        // Both go before anything is read back, because the panel hides 2.6 seconds after a press.
        XCUIRemote.shared.press(.select)
        kjPause(0.5)
        XCUIRemote.shared.press(.select)

        let note = app.staticTexts["filmNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 20), "A signed-out viewer must be told why")
        XCTAssertEqual(note.label, "Sign in to the Khajistan account that holds this film, then press Watch the full film again.")
        XCTAssertTrue(app.descendants(matching: .any)["filmPageCode"].exists, "The film's own page must be offered as a code")
        XCTAssertTrue(app.buttons["filmSignIn"].exists, "Sign in must be offered")
        kjScreenshot("vod-06-full-film-signed-out", app: app)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelf")
    }

    func testRegionCarriesItsFilmsOnDemand() throws {
        let app = try launch()
        XCTAssertTrue(app.buttons["screeningRoom"].waitForExistence(timeout: 60), "vod.json must load")
        // Down onto the region strip, then east along it to Indus.
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<12 where !focusedRegion.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        for _ in 0..<20 where !(focusedRegion.exists && focusedRegion.identifier == "region-indus") {
            XCUIRemote.shared.press(.right)
            kjPause(0.6)
        }
        XCTAssertEqual(focusedRegion.identifier, "region-indus", "Indus must take focus")
        XCUIRemote.shared.press(.select)

        let onDemand = app.buttons["medium-vod"]
        XCTAssertTrue(onDemand.waitForExistence(timeout: 60), "Indus must offer its films On Demand")
        XCTAssertEqual(onDemand.label, "On Demand 11")
        XCTAssertTrue(kjFocus(onDemand, app: app), "On Demand must take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 10), "The region's films must list")
        kjPause(4)
        XCTAssertGreaterThanOrEqual(films(app).count, 5, "the first rows of the region's films are on screen")
        kjScreenshot("vod-07-indus-on-demand", app: app)
    }
}
