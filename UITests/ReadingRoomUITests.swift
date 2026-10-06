import XCTest

/// The Reading Room with the Siri Remote, in each of the three skins: the shelf, a free title opened to
/// its issues, a page turned twice and zoomed, and the refusals the page server gives (the members'
/// gate, the account gate, a rights-held title). A screenshot is kept at each stop.
///
/// The shelf and the pages come from the live catalogue RPC and page server with the public key. The
/// language tabs come from data/rr-modules.json, which is behind the site password; a test does not hold
/// it, so TEST_RUNNER_KJ_FILMS_ORIGIN (a local server of the archive tree, as the Screening Room tests
/// use) gives the app that file through `-kjfilms`. Without it the room is one tab of every title in a row
/// per region, and every assertion here still holds.
final class ReadingRoomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let skins = ["day", "grove", "smut"]

    private func launch(skin: String) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-kjtab", "reading", "-kjskin", skin]
        if let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty {
            arguments += ["-kjfilms", origin]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func cards(_ app: XCUIApplication, tagged tag: String? = nil) -> XCUIElementQuery {
        if let tag {
            return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-title-' AND label CONTAINS[c] %@", tag))
        }
        return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-title-'"))
    }

    /// Walks down the shelf until a card carrying the access line exists, and gives it focus.
    private func focusCard(_ app: XCUIApplication, tagged tag: String) -> XCUIElement? {
        for _ in 0..<45 {
            let card = cards(app, tagged: tag).firstMatch
            if card.exists, kjFocus(card, app: app, limit: 25) { return card }
            XCUIRemote.shared.press(.down)
            kjPause(0.6)
        }
        return nil
    }

    /// Opens the focused card to its issues and the first issue to its reader.
    private func openFirstIssue(_ app: XCUIApplication, shot: String? = nil) -> XCUIElement? {
        XCUIRemote.shared.press(.select)
        guard app.staticTexts["rrTitleSummary"].waitForExistence(timeout: 20) else { return nil }
        let issue = app.buttons["rr-issue-0"]
        guard issue.waitForExistence(timeout: 20), kjFocus(issue, app: app) else { return nil }
        kjPause(4)
        if let shot { kjScreenshot(shot, app: app) }
        XCUIRemote.shared.press(.select)
        return issue
    }

    private func readerState(_ app: XCUIApplication) -> String {
        (app.buttons["rrReaderSurface"].value as? String) ?? ""
    }

    /// Waits for the reader to hold `position` with a page on it. Returns the state it settled on.
    @discardableResult
    private func waitForPage(_ app: XCUIApplication, position: Int, timeout: TimeInterval = 90) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var state = ""
        while Date() < deadline {
            state = readerState(app)
            if state.hasPrefix("\(position)/") && state.contains("|page") { return state }
            kjPause(0.5)
        }
        return state
    }

    private func pages(in state: String) -> Int {
        Int(state.split(separator: "/").dropFirst().first?.split(separator: "|").first ?? "") ?? 0
    }

    private func waitForShelf(_ app: XCUIApplication) {
        XCTAssertTrue(cards(app).firstMatch.waitForExistence(timeout: 90), "The shelf must lay out titles once the feed has answered")
        kjPause(6)   // the covers arrive
    }

    // MARK: - A free title

    func testFreeTitleOpensAndTurnsTwoPagesAndZooms() throws {
        for skin in skins {
            let app = launch(skin: skin)
            waitForShelf(app)
            XCTAssertTrue(app.staticTexts["rrDepth"].exists, "The room states its figures")
            kjScreenshot("rr-\(skin)-01-shelf", app: app)

            let card = try XCTUnwrap(focusCard(app, tagged: "read in full"), "a free title must be on the shelf")
            kjScreenshot("rr-\(skin)-02-shelf-focused", app: app)
            XCTAssertNotNil(openFirstIssue(app, shot: "rr-\(skin)-03-title"), "the title must open to its issues and the first issue to a reader")
            _ = card
            let first = waitForPage(app, position: 1)
            XCTAssertTrue(first.hasPrefix("1/") && first.contains("|page"), "page 1 must show; state: \(first)")
            XCTAssertGreaterThanOrEqual(pages(in: first), 3, "the issue must run to three pages for the turn; state: \(first)")
            kjScreenshot("rr-\(skin)-04-reader-band", app: app)
            kjPause(4)
            kjScreenshot("rr-\(skin)-05-reader-clean", app: app)

            // Right turns the page, twice.
            XCUIRemote.shared.press(.right)
            let second = waitForPage(app, position: 2)
            XCTAssertTrue(second.hasPrefix("2/") && second.contains("|page"), "right must turn to page 2; state: \(second)")
            XCUIRemote.shared.press(.right)
            let third = waitForPage(app, position: 3)
            XCTAssertTrue(third.hasPrefix("3/") && third.contains("|page"), "right must turn to page 3; state: \(third)")
            kjPause(3)
            kjScreenshot("rr-\(skin)-06-page-three", app: app)

            // Left turns back.
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(waitForPage(app, position: 2).hasPrefix("2/"), "left must turn back to page 2")

            // Select zooms to 2x, the remote moves the page, Select zooms out.
            XCUIRemote.shared.press(.select)
            kjPause(0.6)
            XCTAssertTrue(readerState(app).hasSuffix("|zoom"), "Select must zoom; state: \(readerState(app))")
            XCUIRemote.shared.press(.right)
            kjPause(0.4)
            XCUIRemote.shared.press(.down)
            kjPause(0.6)
            XCTAssertTrue(readerState(app).hasPrefix("2/"), "a press while zoomed moves the page and does not turn it; state: \(readerState(app))")
            kjPause(3)
            kjScreenshot("rr-\(skin)-07-zoomed", app: app)
            XCUIRemote.shared.press(.menu)
            kjPause(0.6)
            XCTAssertFalse(readerState(app).hasSuffix("|zoom"), "Menu must zoom out before it leaves")
            XCTAssertTrue(app.buttons["rrReaderSurface"].exists, "Menu while zoomed stays in the reader")

            // Menu leaves the reader, then the title.
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.staticTexts["rrTitleSummary"].waitForExistence(timeout: 20), "Menu must come back to the title")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(cards(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelf")
            app.terminate()
        }
    }

    // MARK: - The refusals

    func testMembersGateAtPageThree() throws {
        for skin in skins {
            let app = launch(skin: skin)
            waitForShelf(app)
            _ = try XCTUnwrap(focusCard(app, tagged: "Members"), "a members' title must be on the shelf")
            XCTAssertNotNil(openFirstIssue(app))
            waitForPage(app, position: 1)
            XCUIRemote.shared.press(.right)
            waitForPage(app, position: 2)
            kjPause(1)
            XCUIRemote.shared.press(.right)
            let heading = app.staticTexts["rrGateTitle"]
            XCTAssertTrue(heading.waitForExistence(timeout: 60), "the third page of a paid title is the gate")
            XCTAssertEqual(heading.label, "Membership required")
            let text = app.staticTexts["rrGateText"].label
            XCTAssertTrue(text.hasPrefix("You've read the free preview"), "the gate says it in the site's words: \(text)")
            XCTAssertTrue(app.descendants(matching: .any)["rrTitleCode"].exists, "the gate sends the viewer to the website by a code")
            kjPause(2)
            kjScreenshot("rr-\(skin)-08-members-gate", app: app)
            // Left goes back to the free preview, and right cannot pass the gate.
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(waitForPage(app, position: 2).hasPrefix("2/"), "left from the gate returns to the preview")
            app.terminate()
        }
    }

    func testAccountOpenTitleAsksForSignIn() throws {
        for skin in skins {
            let app = launch(skin: skin)
            waitForShelf(app)
            // The account-open titles are the received print acquisition, which the module index has not filed yet.
            let urdu = app.buttons["rr-tab-unfiled"]
            if urdu.exists, kjFocus(urdu, app: app) {
                XCUIRemote.shared.press(.select)
                kjPause(6)
            }
            guard focusCard(app, tagged: "sign in to read") != nil else {
                print("RRDEBUG tags seen: " + cards(app).allElementsBoundByIndex.map(\.label).joined(separator: " | "))
                kjScreenshot("rr-\(skin)-no-account-open", app: app)
                throw XCTSkip("no account-open title on the shelf today")
            }
            XCTAssertNotNil(openFirstIssue(app))
            waitForPage(app, position: 1)
            // The cover is free, and a declared cover page can be the second leaf; the next one asks for an account.
            let heading = app.staticTexts["rrGateTitle"]
            for _ in 0..<4 where !heading.exists {
                XCUIRemote.shared.press(.right)
                _ = heading.waitForExistence(timeout: 12)
            }
            XCTAssertTrue(heading.waitForExistence(timeout: 60), "the page after the cover of an account-open title is the sign-in")
            XCTAssertEqual(heading.label, "Free to read \u{2014} sign in to continue")
            XCTAssertTrue(app.buttons["rrGateSignIn"].exists, "the gate offers Sign in")
            kjPause(2)
            kjScreenshot("rr-\(skin)-09-account-gate", app: app)
            app.terminate()
        }
    }

    func testRightsHeldTitleShowsCoversAndNoPages() throws {
        for skin in skins {
            let app = launch(skin: skin)
            waitForShelf(app)
            _ = try XCTUnwrap(focusCard(app, tagged: "Rights pending"), "a rights-held title must be on the shelf")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["rrTitleSummary"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["rrTitleSummary"].label.hasSuffix("preserved, cover only"), "the run is described as preserved: \(app.staticTexts["rrTitleSummary"].label)")
            let note = app.staticTexts["rrRightsNote"]
            XCTAssertTrue(note.waitForExistence(timeout: 20), "the banner says why")
            XCTAssertTrue(note.label.contains("until rights for this material are cleared"), note.label)
            kjPause(5)
            kjScreenshot("rr-\(skin)-10-rights-title", app: app)
            // Select on a cover opens nothing.
            let issue = app.buttons["rr-issue-0"]
            XCTAssertTrue(issue.waitForExistence(timeout: 20))
            XCTAssertTrue(kjFocus(issue, app: app))
            XCUIRemote.shared.press(.select)
            kjPause(2)
            XCTAssertFalse(app.buttons["rrReaderSurface"].exists, "a rights-held issue must not open a reader")
            app.terminate()
        }
    }

    // MARK: - The shelf's shape

    func testTabsWhenTheModuleIndexIsThere() throws {
        guard ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"] != nil else {
            throw XCTSkip("the module index is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN")
        }
        let app = launch(skin: "day")
        waitForShelf(app)
        XCTAssertTrue(app.buttons["rr-tab-arabic"].exists, "the languages are tabs")
        XCTAssertTrue(app.buttons["rr-tab-urdu"].exists)
        XCTAssertTrue(app.buttons["rr-tab-persian"].exists)
        let depth = app.staticTexts["rrDepth"].label
        XCTAssertTrue(depth.contains("titles") && depth.contains("issues"), depth)
        // Moving to another language changes the shelf.
        let urdu = app.buttons["rr-tab-urdu"]
        XCTAssertTrue(kjFocus(urdu, app: app))
        XCUIRemote.shared.press(.select)
        kjPause(4)
        XCTAssertNotEqual(app.staticTexts["rrDepth"].label, depth, "another language is another set of figures")
        kjScreenshot("rr-tab-urdu", app: app)
    }
}
