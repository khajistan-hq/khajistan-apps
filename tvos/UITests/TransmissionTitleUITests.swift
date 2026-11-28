import XCTest

/// The page title stays whole below the top bar when a channel card takes focus (owner,
/// 2026-11-27: "fix the transmission title cut off too").
final class TransmissionTitleUITests: XCTestCase {
    func testTitleStaysBelowTheBarWithACardFocused() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-11-08.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00"]
        kjLaunch(app)
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "channel 1 has a card")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        XCUIRemote.shared.press(.right); kjPause(1.5)
        let title = app.staticTexts["transmissionTitle"]
        let bar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nav-'")).firstMatch
        XCTAssertTrue(title.exists && bar.exists)
        kjScreenshot("transmission-card-focused", app: app)
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.frame.maxY,
                                    "the title starts below the bar: title \(title.frame), bar \(bar.frame)")
    }

    /// Down through the guide reaches the last channel and the page follows it (owner, 2026-11-28:
    /// "not scrolling down on the page"). Each row taking focus pulled the page back to its top.
    func testTheGuideScrollsDownToTheLastChannel() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-11-08.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00"]
        kjLaunch(app)
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "channel 1 has a card")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        // The fixture's last channel. The guide is a lazy stack, so counting the rows on screen
        // would name the last row drawn, not the last channel.
        let last = app.buttons["transmission-channel-15"]
        for _ in 0..<16 { XCUIRemote.shared.press(.down); kjPause(0.4) }
        kjPause(1.0)
        kjScreenshot("transmission-guide-bottom", app: app)
        XCTAssertTrue(last.hasFocus, "the last channel takes focus")
        XCTAssertLessThanOrEqual(last.frame.maxY, app.frame.maxY, "the last channel is on screen: \(last.frame)")
        XCTAssertGreaterThanOrEqual(last.frame.minY, 0, "the last channel is on screen: \(last.frame)")
    }
}
