import XCTest

/// Walks the app with the Siri Remote and keeps a screenshot of each stop. Strict about the
/// app's own elements, loose about what the network answers on the day.
final class KhajistanTVUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits until `condition` holds or `timeout` seconds pass. The outcome is not asserted:
    /// the caller reports whatever state the app reached.
    private func wait(upTo timeout: TimeInterval, until condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
    }

    func testReceiverRegionsChannelsAndPlayer() {
        let app = XCUIApplication()
        app.launch()

        let indus = app.buttons["region-indus"]
        XCTAssertTrue(indus.waitForExistence(timeout: 60), "The receiver must list the Indus region")
        screenshot("01-receiver-regions", app: app)

        for _ in 0..<12 {
            if indus.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCUIRemote.shared.press(.select)

        let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 60), "Indus must list at least one channel")
        screenshot("02-indus-channels", app: app)

        let focusedChannel = channels.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<6 {
            if focusedChannel.exists { break }
            XCUIRemote.shared.press(.down)
        }
        XCUIRemote.shared.press(.select)

        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 60), "The player must show its state")
        wait(upTo: 45) {
            guard state.exists else { return false }
            let label = state.label
            return !label.isEmpty && label != "Tuning\u{2026}"
        }
        let outcome = state.exists ? state.label : "overlay-hidden"
        screenshot("03-receiver-player-\(outcome)", app: app)
        XCUIRemote.shared.press(.menu)
    }

    func testKhajistanTVTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "transmission"]
        app.launch()

        // The phase is the sentence's accessibility value, so the screen carries no marker word.
        let state = app.staticTexts["transmissionState"]
        XCTAssertTrue(state.waitForExistence(timeout: 60), "Khajistan TV must show a state")
        wait(upTo: 40) { state.exists && (state.value as? String) != "Loading" }
        let outcome = (state.value as? String) ?? "unknown"
        screenshot("04-khajistan-tv-\(outcome)", app: app)
    }

    func testAccountTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "account"]
        app.launch()

        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 30), "A signed-out account offers Sign in")
        screenshot("05-account", app: app)
    }
}
