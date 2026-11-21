import XCTest

/// The welcome (owner, 2026-11-20: "a landing page ... to intro what the app is"). A Debug build
/// shows it only with `-kjwelcome YES`, so no other test meets it.
final class WelcomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ skin: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", "receiver", "-kjwelcome", "YES"]
        kjLaunch(app)
        return app
    }

    /// Start is focused at once, and Select on it opens the Receiver.
    func testStartOpensTheReceiver() {
        for skin in ["day", "grove", "smut"] {
            let app = launch(skin)
            let start = app.buttons["welcomeStart"]
            XCTAssertTrue(start.waitForExistence(timeout: 30), "\(skin): the welcome is up")
            XCTAssertTrue(app.staticTexts["Khajistan"].exists || app.staticTexts["KHAJISTAN"].exists, "\(skin): the welcome names the app")
            kjPause(1)
            XCTAssertTrue(start.hasFocus, "\(skin): Start has focus at once")
            kjScreenshot("welcome-\(skin)", app: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["beyondTheAtlas"].waitForExistence(timeout: 60), "\(skin): Start opens the Receiver")
            XCTAssertFalse(start.exists, "\(skin): the welcome has gone")
            app.terminate()
        }
    }

    /// Menu closes the welcome and does not leave the app.
    func testMenuClosesTheWelcomeAndStaysInTheApp() {
        let app = launch("day")
        let start = app.buttons["welcomeStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        kjPause(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].waitForExistence(timeout: 60), "Menu lands on the Receiver")
        XCTAssertEqual(app.state, .runningForeground, "Menu on the welcome does not leave the app")
        XCTAssertFalse(start.exists)
    }

    /// The negative case: without the flag, a Debug launch never shows it.
    func testNoWelcomeWithoutTheFlag() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver"]
        kjLaunch(app)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["welcomeStart"].exists, "no welcome in a Debug run without -kjwelcome")
    }
}
