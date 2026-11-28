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
}
