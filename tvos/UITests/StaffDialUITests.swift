import XCTest

/// The preview password opens the whole Receiver dial, and clearing it closes it, with the
/// Receiver already loaded and no relaunch (owner, 2026-11-17: "bring all channels back on apple
/// tv"). The site serves the whole dial only to a session that signed in with its password, so
/// this reads the live site: set TEST_RUNNER_KJ_PREVIEW_PASSWORD to run it. XCUITest logs typed
/// text, so the password is written into the result bundle: delete the bundle after a run.
final class StaffDialUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPasswordOpensAndClosesTheWholeDial() throws {
        guard let password = ProcessInfo.processInfo.environment["KJ_PREVIEW_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("reads the live site with the site password; set TEST_RUNNER_KJ_PREVIEW_PASSWORD")
        }
        let app = XCUIApplication()
        // No recorded fixtures: the sign-in and both dials are the live site's.
        app.launchArguments = ["-kjnoautoplay", "YES", "-kjtab", "account"]
        app.launch()
        clearPassword(app)

        let publicCount = try liveNow(app)
        kjScreenshot("staff-dial-1-public", app: app)

        open("account", app)
        let set = app.buttons["Set"]
        XCTAssertTrue(set.waitForExistence(timeout: 10), "Account offers to set the preview password")
        XCTAssertTrue(kjFocus(set, app: app), "the remote reaches Set")
        XCUIRemote.shared.press(.select)
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Set opens the password field")
        XCTAssertTrue(kjFocus(field, app: app), "the remote reaches the field")
        XCUIRemote.shared.press(.select)
        kjPause(1.5)
        app.typeText(password)
        XCUIRemote.shared.press(.menu)   // closes the keyboard
        kjPause(1)
        let save = app.buttons["Save"]
        XCTAssertTrue(kjFocus(save, app: app), "the remote reaches Save")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 10), "the password is saved")

        let wholeCount = try liveNow(app, otherThan: publicCount)
        XCTAssertGreaterThan(wholeCount, publicCount, "the password opens the whole dial")
        let wholeRegions = regionTotal(app)
        kjScreenshot("staff-dial-2-whole", app: app)

        clearPassword(app)
        let afterClear = try liveNow(app, otherThan: wholeCount)
        XCTAssertEqual(afterClear, publicCount, "clearing the password closes the whole dial again")
        // The region rows are a shelf of their own: they must be drawn again from the new dial too.
        XCTAssertGreaterThan(wholeRegions, regionTotal(app), "the region list is drawn again from the public dial")
        kjScreenshot("staff-dial-3-public-again", app: app)
    }

    private func open(_ section: String, _ app: XCUIApplication) {
        let tab = app.buttons["nav-\(section)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "the top bar shows \(section)")
        XCTAssertTrue(kjFocus(tab, app: app), "the remote reaches \(section)")
        XCUIRemote.shared.press(.select)
        kjPause(1)
    }

    private func clearPassword(_ app: XCUIApplication) {
        open("account", app)
        let clear = app.buttons["Clear"]
        guard clear.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(kjFocus(clear, app: app), "the remote reaches Clear")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Set"].waitForExistence(timeout: 10), "the password is cleared")
    }

    /// The live counts on the Receiver's region rows, added up once the rows are on screen.
    private func regionTotal(_ app: XCUIApplication) -> Int {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let total = rows.allElementsBoundByIndex.reduce(0) { sum, row in
                sum + (Int(((row.value as? String) ?? "").filter(\.isNumber)) ?? 0)
            }
            if total > 0 { return total }
            kjPause(1)
        }
        XCTFail("no region row showed a live count")
        return 0
    }

    /// The Receiver's "Live now" count, read once it differs from `otherThan`.
    private func liveNow(_ app: XCUIApplication, otherThan previous: Int? = nil) throws -> Int {
        open("receiver", app)
        let figure = app.descendants(matching: .any)["receiverLiveNow"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if figure.exists {
                let digits = figure.label.filter(\.isNumber)
                if let count = Int(digits), count > 0, count != previous { return count }
            }
            kjPause(1)
        }
        XCTFail("the Live now count did not change from \(previous.map(String.init) ?? "nothing"): \(figure.exists ? figure.label : "not on screen")")
        return previous ?? 0
    }
}
