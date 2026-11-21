import XCTest

/// The welcome (owner, 2026-11-20: "a landing page ... to intro what the app is"). A Debug build
/// shows it only with `-kjwelcome YES` (always) or `-kjwelcome once` (as Release does), so no other
/// test meets it.
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

    /// The picture is still moving past the ident (10 s) and one turn of the wordmark (8 s): the
    /// last item of a queue ends on `.none` and loops, rather than being dropped (round-2 review).
    func testThePictureKeepsPlayingPastOneLoop() {
        let app = launch("day")
        let picture = app.descendants(matching: .any).matching(identifier: "welcomePicture").firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 30))
        for second in [5, 22, 30] {
            let waited = second == 5 ? 5.0 : (second == 22 ? 17.0 : 8.0)
            kjPause(waited)
            XCTAssertEqual(picture.value as? String, "playing", "the picture is playing at about \(second) s")
        }
    }

    /// Once seen, it does not come again: `-kjwelcome once` reads the device's record as Release does.
    func testItComesOnlyOnce() {
        var app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjwelcome", "once", "-kjwelcomereset", "YES"]
        kjLaunch(app)
        let start = app.buttons["welcomeStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "the first launch shows it")
        kjPause(1)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].waitForExistence(timeout: 60))
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjwelcome", "once"]
        kjLaunch(app)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["welcomeStart"].exists, "the second launch does not")
    }

    /// A launch from the Top Shelf goes where its link points, and the welcome steps aside.
    func testATopShelfLinkSkipsTheWelcome() throws {
        let app = launch("day")
        XCTAssertTrue(app.buttons["welcomeStart"].waitForExistence(timeout: 30), "the welcome is up first")
        // As DeepLinkUITests does: open relaunches the app with the link, and the flag still asks for it.
        app.open(try XCTUnwrap(URL(string: "khajistan://receiver/indus")))
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 60), "the link opens the region page")
        XCTAssertFalse(app.buttons["welcomeStart"].exists, "the welcome stepped aside for the link")
    }
}
