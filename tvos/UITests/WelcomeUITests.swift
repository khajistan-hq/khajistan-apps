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

    /// The picture keeps moving past the ident (10 s) and one turn of the wordmark (8 s): the
    /// wordmark goes back to its start (a frozen last frame never does), and the queue is never
    /// left empty (round-2 and round-3 reviews).
    func testThePictureKeepsPlayingPastOneLoop() {
        let app = launch("day")
        let picture = app.descendants(matching: .any).matching(identifier: "welcomePicture").firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 30))
        var reads: [(String, Double)] = []
        for _ in 0..<30 {
            kjPause(1)
            let parts = ((picture.value as? String) ?? "").split(separator: " ")
            reads.append((parts.first.map(String.init) ?? "stopped", parts.count > 1 ? Double(parts[1]) ?? -1 : -1))
        }
        XCTAssertFalse(reads.contains { $0.0 == "stopped" }, "the picture never stops: \(reads)")
        XCTAssertEqual(reads.first?.0, "ident", "the ident plays first: \(reads)")
        let wordmark = reads.filter { $0.0 == "wordmark" }.map(\.1)
        let wrapped = zip(wordmark, wordmark.dropFirst()).contains { $1 < $0 - 2 }
        XCTAssertTrue(wrapped, "the wordmark goes back to its start: \(wordmark)")
        XCTAssertNotEqual(reads[reads.count - 1].1, reads[reads.count - 2].1, "still moving at the end: \(reads.suffix(2))")
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
    /// `-kjopenurl` opens the link at launch with no relaunch, so `-kjwelcome YES` stays set.
    func testATopShelfLinkSkipsTheWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjwelcome", "YES", "-kjopenurl", "khajistan://receiver/indus"]
        kjLaunch(app)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 60), "the link opens the region page")
        XCTAssertFalse(app.buttons["welcomeStart"].exists, "the welcome stepped aside for the link")
    }

    /// A channel link opens its player, a cover of its own, while the welcome is going: the player
    /// must be up, not dropped behind the closing welcome (round-3 review).
    func testAChannelLinkOverTheWelcomeOpensThePlayer() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-seven-channels.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjwelcome", "YES", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-04T12:00:00+05:00", "-kjopenurl", "khajistan://transmission/7"]
        kjLaunch(app)
        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "the channel's player is up")
        XCTAssertEqual(channel.label, "7")
        XCTAssertFalse(app.buttons["welcomeStart"].exists, "the welcome stepped aside")
    }

    /// A link launch does not count as seeing the welcome: the next plain launch shows it.
    func testALinkLaunchDoesNotMarkItSeen() {
        var app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjwelcome", "once", "-kjwelcomereset", "YES",
                               "-kjopenurl", "khajistan://receiver/indus"]
        kjLaunch(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
            .waitForExistence(timeout: 60), "the link opened")
        kjPause(2)
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjwelcome", "once"]
        kjLaunch(app)
        XCTAssertTrue(app.buttons["welcomeStart"].waitForExistence(timeout: 30), "the next plain launch shows the welcome")
    }

    /// A link in before the first frame (round-4 review): the player still comes up. Measured
    /// 2026-11-21: this passes with RootView's 1.5 s fallback removed too, so SwiftUI still reports
    /// the welcome's dismissal on this path; the fallback is a guard for an order not reproduced.
    func testALinkThatBeatsTheWelcomeStillOpensThePlayer() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-seven-channels.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjwelcome", "YES", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-04T12:00:00+05:00", "-kjopenurl", "khajistan://transmission/7",
                               "-kjopenurlearly", "YES"]
        kjLaunch(app)
        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "the channel's player is up")
        XCTAssertEqual(channel.label, "7")
        XCTAssertFalse(app.buttons["welcomeStart"].exists)
    }
}
