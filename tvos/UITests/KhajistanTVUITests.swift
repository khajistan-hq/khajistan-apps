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

    private func regionButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
    }

    func testReceiverRegionsChannelsAndPlayer() {
        let app = XCUIApplication()
        app.launch()

        // The map is a Canvas; what the remote can reach is a button over each region's label.
        let regions = regionButtons(app)
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "The receiver must draw a map with regions to open")
        screenshot("01-receiver-map", app: app)

        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for attempt in 0..<20 {
            if focusedRegion.exists { break }
            // Down first; after six tries right as well, in case the way down is the switch.
            XCUIRemote.shared.press(attempt >= 6 && attempt % 2 == 0 ? .right : .down)
        }
        XCTAssertTrue(focusedRegion.exists, "A region on the map must take focus")
        screenshot("02-map-focused", app: app)
        XCUIRemote.shared.press(.select)

        let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 60), "The region must list at least one channel")
        screenshot("03-region-channels", app: app)

        let focusedChannel = channels.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 {
            if focusedChannel.exists { break }
            XCUIRemote.shared.press(.down)
        }
        XCUIRemote.shared.press(.select)

        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 60), "The player must show its state")
        wait(upTo: 45) {
            guard state.exists else { return false }
            let label = state.label
            return !label.isEmpty && label.caseInsensitiveCompare("Connecting\u{2026}") != .orderedSame
        }
        let outcome = state.exists ? state.label : "overlay-hidden"
        screenshot("04-receiver-player-\(outcome)", app: app)
        XCUIRemote.shared.press(.menu)
    }

    /// Best effort: reaching the switch depends on where focus starts, and what the wider map
    /// draws depends on the day's data. The screenshot is the record; nothing here is asserted
    /// beyond the map having drawn.
    func testBeyondTheAtlas() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(regionButtons(app).firstMatch.waitForExistence(timeout: 60), "The receiver must draw a map with regions to open")

        let toggle = app.buttons["beyondTheAtlas"]
        for _ in 0..<12 {
            if toggle.exists && toggle.hasFocus { break }
            XCUIRemote.shared.press(.left)
            XCUIRemote.shared.press(.down)
        }
        // The switch is kept on the device, so it is read rather than assumed: on for the
        // picture, and off again at the end so later tests see the core map.
        if toggle.exists && toggle.hasFocus {
            for _ in 0..<2 where (toggle.value as? String) != "On" { XCUIRemote.shared.press(.select) }
            wait(upTo: 8) { false }
        }
        screenshot("06-map-extended", app: app)
        if toggle.exists && toggle.hasFocus {
            for _ in 0..<2 where (toggle.value as? String) != "Off" { XCUIRemote.shared.press(.select) }
            XCTAssertEqual(toggle.value as? String, "Off", "the wider atlas is left off")
        }
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
