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

        // The Screening Room lies in full on the Receiver's front, on a row of posters.
        let first = films(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 60), "The Receiver must lay out the Screening Room once vod.json has loaded")
        kjPause(4)   // the posters arrive
        XCTAssertTrue(kjFocus(first, app: app), "The first film must take focus")
        kjScreenshot("vod-01-receiver-row", app: app)

        var seen = Set([focusedFilm(app).identifier])
        var log: [String] = []
        for _ in 0..<5 {
            XCUIRemote.shared.press(.right)
            kjPause(0.8)
            let id = focusedFilm(app).exists ? focusedFilm(app).identifier : "(off the row)"
            seen.insert(id)
            log.append("R->\(id)")
        }
        print("FILMWALK " + log.joined(separator: " "))
        seen.remove("(off the row)")
        XCTAssertGreaterThanOrEqual(seen.count, 5, "the walk must reach five films; walk: \(log)")
        kjScreenshot("vod-03-walked", app: app)

        // Back along the shelf to the first film, which has a preview.
        for _ in 0..<15 where focusedFilm(app).identifier != "film-showgirls-of-pakistan-2021-khajistan" {
            XCUIRemote.shared.press(.left)
            kjPause(0.6)
        }
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
        XCTAssertFalse(app.descendants(matching: .any)["filmPageCode"].exists, "No code sends a viewer out of the app")
        XCTAssertTrue(app.buttons["filmSignIn"].exists, "Sign in must be offered")
        kjScreenshot("vod-06-full-film-signed-out", app: app)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelf")
    }

    func testRegionCarriesItsFilmsOnDemand() throws {
        let app = try launch()
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 60), "vod.json must load")
        // Down onto the region strip, then east along it to Indus.
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        kjFocusStrip(app)
        for _ in 0..<20 where !(focusedRegion.exists && focusedRegion.identifier == "region-indus") {
            XCUIRemote.shared.press(.right)
            kjPause(0.6)
        }
        XCTAssertEqual(focusedRegion.identifier, "region-indus", "Indus must take focus")
        XCUIRemote.shared.press(.select)

        // The region's films are a shelf of their own, headed On Demand, under television and radio.
        let onDemand = app.descendants(matching: .any)["shelf-vod"]
        XCTAssertTrue(onDemand.waitForExistence(timeout: 60), "Indus must offer its films On Demand")
        let heading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'On Demand'")).firstMatch
        XCTAssertTrue(heading.exists, "the shelf is headed On Demand")
        XCTAssertTrue(heading.label.contains("11 films"), "Indus files 11 films; the heading reads \(heading.label)")
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 10), "The region's films must list")
        XCTAssertTrue(kjFocus(films(app).firstMatch, app: app), "the first film must take focus")
        kjPause(4)
        XCTAssertGreaterThanOrEqual(films(app).count, 5, "the shelf's first films are on screen")
        kjScreenshot("vod-07-indus-on-demand", app: app)
    }
}
