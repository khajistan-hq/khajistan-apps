import XCTest

/// The preview password opens the whole Receiver dial, and clearing it closes it, with the
/// Receiver already loaded and no relaunch (the Apple TV's StaffDialUITests, on a phone). The site
/// serves the whole dial only to a session that signed in with its password, so this reads the
/// live site: set TEST_RUNNER_KJ_PREVIEW_PASSWORD to run it. XCUITest logs typed text, so delete
/// the result bundle after a run.
final class StaffDialUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPasswordOpensAndClosesTheWholeDial() throws {
        guard let password = ProcessInfo.processInfo.environment["KJ_PREVIEW_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("reads the live site with the site password; set TEST_RUNNER_KJ_PREVIEW_PASSWORD")
        }
        let app = XCUIApplication()
        // No recorded fixtures: the sign-in and both dials are the live site's.
        app.launchArguments = ["-kjtab", "library", "-kjautoplay", "NO", "-kjstorefront", "USA"]
        app.launch()
        clearPassword(app)

        let publicCount = liveNow(app)
        let publicList = listTotal(app)
        shot("staff-dial-1-public", app)

        app.buttons["tab-library"].tap()
        reveal(app.buttons["previewPasswordSet"], in: app).tap()
        let field = app.secureTextFields["previewPasswordField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Set opens the password field")
        field.tap()
        field.typeText(password)
        reveal(app.buttons["previewPasswordSave"], in: app).tap()
        XCTAssertTrue(app.buttons["previewPasswordClear"].waitForExistence(timeout: 10), "the password is saved")

        let wholeCount = liveNow(app, otherThan: publicCount)
        XCTAssertGreaterThan(wholeCount, publicCount, "the password opens the whole dial")
        let wholeList = listTotal(app, otherThan: publicList)
        XCTAssertGreaterThan(wholeList, publicList, "the Live list is read again from the whole dial")
        shot("staff-dial-2-whole", app)

        clearPassword(app)
        let afterClear = liveNow(app, otherThan: wholeCount)
        XCTAssertEqual(afterClear, publicCount, "clearing the password closes the whole dial again")
        XCTAssertEqual(listTotal(app, otherThan: wholeList), publicList, "the Live list is read again from the public dial")
        shot("staff-dial-3-public-again", app)
        let counts = XCTAttachment(string: "Live now: \(publicCount) public, \(wholeCount) with the password, \(afterClear) after clearing it")
        counts.name = "staff-dial-counts"
        counts.lifetime = .keepAlways
        add(counts)
    }

    private func clearPassword(_ app: XCUIApplication) {
        app.buttons["tab-library"].tap()
        let set = app.buttons["previewPasswordSet"]
        _ = reveal(set, in: app)
        let clear = app.buttons["previewPasswordClear"]
        guard clear.exists else { return }
        reveal(clear, in: app).tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'For testers'")).firstMatch
            .waitForExistence(timeout: 10), "the password is cleared")
        XCTAssertFalse(clear.exists, "the password is cleared")
    }

    /// Scrolls the page until the control is on screen and clear of the bar.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<12 {
            if element.exists, element.isHittable, element.frame.maxY < app.frame.maxY - 140 { break }
            app.swipeUp()
        }
        return element
    }

    /// The Receiver's "Live now" count, read once it differs from `otherThan`.
    private func liveNow(_ app: XCUIApplication, otherThan previous: Int? = nil) -> Int {
        app.buttons["tab-receiver"].tap()
        let figure = app.descendants(matching: .any)["figure-Live now"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if figure.exists, let count = Int(figure.label.filter(\.isNumber)), count > 0, count != previous {
                return count
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("the Live now count did not change from \(previous.map(String.init) ?? "nothing"): \(figure.exists ? figure.label : "not on screen")")
        return previous ?? 0
    }

    /// The channels in the Live list of the region on screen (its Television and Radio switches
    /// count the list itself, not the index), read once the total differs from `otherThan`.
    private func listTotal(_ app: XCUIApplication, otherThan previous: Int? = nil) -> Int {
        let deadline = Date().addingTimeInterval(60)
        var total = 0
        while Date() < deadline {
            total = ["medium-tv", "medium-radio"].reduce(0) { sum, id in
                let chip = app.buttons[id]
                return sum + (chip.exists ? Int(chip.label.filter(\.isNumber)) ?? 0 : 0)
            }
            if total > 0, total != previous { return total }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("the Live list did not change from \(previous.map(String.init) ?? "nothing"): \(total)")
        return total
    }

    /// The page's top, where the figures are: a channel on air docks the set above it.
    private func shot(_ name: String, _ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
