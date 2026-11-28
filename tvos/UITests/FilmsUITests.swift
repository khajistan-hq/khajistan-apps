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

    private func launch(extra: [String] = []) throws -> XCUIApplication {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin] + extra
        kjLaunch(app)
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
        let playing = NSPredicate { _, _ in (try? state.snapshot())?.label == "Playing" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 45),
                       .completed, "the preview must play")
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
        XCTAssertEqual(note.label, "Sign in to the Khajistan account that holds this film.")
        XCTAssertFalse(app.descendants(matching: .any)["filmPageCode"].exists, "No code sends a viewer out of the app")
        XCTAssertTrue(app.buttons["filmSignIn"].exists, "Sign in must be offered")
        kjScreenshot("vod-06-full-film-signed-out", app: app)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelf")
    }

    /// The film page's buttons keep every label whole, on one line, in every skin. On the owner's
    /// Apple TV HD (2026-11-17) the four sat squeezed in one row and broke mid-word: "PREVIE / W",
    /// "WATCHLI / ST", "WEBSIT / E", and "RESUME FROM 1:21:38" on three lines.
    /// A saved place is set through the launch arguments, so Play reads "Resume from 1:21:38".
    func testFilmPageButtonLabelsStayOnOneLine() throws {
        // The tallest a one-line button may be. Measured on the tvOS 27 simulator at 1920 × 1080:
        // Play (a filled plate) is 66 pt on one line and was 126 on three; the others report their
        // label, 29 pt on one line, about 58 on two.
        let oneLine: [String: CGFloat] = ["filmPlay": 80, "filmPreview": 40, "filmWatchlist": 40, "filmOnWebsite": 40]
        let buttons = ["filmPlay", "filmPreview", "filmWatchlist", "filmOnWebsite"]
        // The page's text column ends at 1760 (the 80 pt safe area and 80 pt inset). The three plain
        // buttons report their label alone, and their plate runs 26 pt past it, so a label ends by 1734.
        let columnEnd: CGFloat = 1734
        // Jism is the film in the owner's photograph; World ka Centre has the longest title in front.
        for handle in ["jism-2006-khajistan", "world-ka-centre-center-of-the-world-2002-directors-cut-khajistan"] {
            for skin in ["day", "grove", "smut"] {
                // The saved place puts the film first on the Screening Room's Up Next, whose card
                // opens the film page (a Receiver poster opens the player instead).
                let app = try launch(extra: ["-kjskin", skin, "-kjtab", "rooms", "-kjroom", "screening",
                                             "-kj.filmPlaces", "<dict><key>\(handle)</key><real>4898</real></dict>"])
                // Rooms keeps a copy of Up Next under the room, so the card is found by its focus.
                let card = app.buttons.matching(identifier: "upnext-\(handle)")
                    .matching(NSPredicate(format: "hasFocus == true")).firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 60), "\(skin): Up Next must carry \(handle), focused")
                XCUIRemote.shared.press(.select)

                let play = app.buttons["filmPlay"]
                XCTAssertTrue(play.waitForExistence(timeout: 20), "\(skin): the film page must open")
                kjPause(2)
                XCTAssertTrue(play.label.contains("Resume from 1:21:38"), "\(skin): Play must offer the saved place; reads \(play.label)")
                var drawn: [String] = []
                var row: [CGRect] = []   // Preview, Watchlist, Website: the row under Play
                continueAfterFailure = true   // measure all four, so a failure names every broken label
                defer { continueAfterFailure = false }
                for id in buttons where app.buttons[id].exists {
                    let frame = app.buttons[id].frame
                    drawn.append("\(id) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
                    XCTAssertLessThanOrEqual(frame.height, oneLine[id]!, "\(skin) \(handle): \(id) breaks onto a second line (\(frame))")
                    XCTAssertLessThanOrEqual(frame.maxX, columnEnd, "\(skin) \(handle): \(id) runs past the page's column (\(frame))")
                    if id != "filmPlay" { row.append(frame) }
                }
                // Play alone on the first row, the others under it, left to right without touching.
                // Labels are measured, so two plates (26 pt padding each side) clear by 52 between labels.
                for (i, frame) in row.enumerated() {
                    XCTAssertGreaterThan(frame.minY, play.frame.maxY, "\(skin) \(handle): button \(i + 1) must sit under Play")
                    if i > 0 { XCTAssertGreaterThanOrEqual(frame.minX, row[i - 1].maxX + 52, "\(skin) \(handle): buttons \(i) and \(i + 1) overlap") }
                }
                print("FILMBUTTONS \(skin) \(handle) " + drawn.joined(separator: " | "))
                // Each by name: a count of three would pass with Preview standing in for a missing one.
                for id in ["filmPlay", "filmWatchlist", "filmOnWebsite"] {
                    XCTAssertTrue(app.buttons[id].exists, "\(skin) \(handle): \(id) must draw")
                }
                kjScreenshot("film-buttons-\(skin)-\(handle.prefix(14))", app: app)
                app.terminate()
            }
        }
    }

    func testRegionCarriesItsFilmsOnDemand() throws {
        let app = try launch()
        XCTAssertTrue(films(app).firstMatch.waitForExistence(timeout: 60), "vod.json must load")
        // Onto the region list beside the map, then down it to Indus.
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
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
