import XCTest

/// The Transmission tab plays a channel at once, full screen, with no page of channels first
/// (owner, 2026-11-28: "transmission should start the stream of channels not showing the page, the
/// guide will do that work"). The counts sit on the guide's top line, and Back from the player
/// leaves a plain screen whose focus is the top bar.
final class TransmissionTitleUITests: XCTestCase {
    private var schedule: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-11-08.json").path
    }

    private func launch(last: Int) -> XCUIApplication {
        let app = XCUIApplication()
        // 0: no last channel, so the first-channel rule decides.
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00", "-kj.transmission.lastChannel", "\(last)"]
        kjLaunch(app)
        return app
    }

    /// With no last channel the tab opens the lowest-numbered channel on air with a picture:
    /// Channel 1 is off air in the fixture at this hour, so not Channel 1.
    func testTheTabPlaysAChannelAtOnce() {
        let app = launch(last: 0)
        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "the tab plays a channel with no press on a page")
        // Channels 1 to 4 are off air at 12:10 in the fixture and 5 plays a picture (Saang Mahfil E Milad).
        XCTAssertEqual(channel.label, "5", "the lowest-numbered channel on air with a picture opens")
        XCTAssertFalse(app.buttons["transmission-channel-1"].exists, "no page of channel cards")
        kjScreenshot("transmission-plays-at-once", app: app)
    }

    /// The last channel watched is the one the tab opens: 8, not the 5 the first-channel rule picks.
    func testTheTabOpensTheLastChannelWatched() {
        let app = launch(last: 8)
        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30))
        XCTAssertEqual(channel.label, "8", "the last channel watched opens, not the first-channel rule's 5")
    }

    /// The station's counts are on the guide's top line; there is no channel count.
    func testTheGuideCarriesTheCounts() {
        let app = launch(last: 5)
        XCTAssertTrue(app.descendants(matching: .any)["transmissionChannel"].waitForExistence(timeout: 30))
        kjPause(12)
        XCUIRemote.shared.press(.down)
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down opens the guide")
        kjPause(1.5)
        let counts = guide.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Khajistan Transmission' AND label CONTAINS 'programmes' AND label CONTAINS 'hours'")).firstMatch
        XCTAssertTrue(counts.exists, "the guide's top line carries the programmes and the hours")
        XCTAssertFalse(counts.label.contains("channels"), "no channel count: the rows show the channels: \(counts.label)")
        XCTAssertLessThan(counts.frame.maxY, app.frame.height * 0.4, "the counts sit in the guide's top band")
        kjScreenshot("transmission-guide-counts", app: app)
    }

    /// Back from the player leaves the plain screen under it, with focus on the top bar, and does
    /// not start the channel again.
    func testBackLandsOnTheTopBar() {
        let app = launch(last: 5)
        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30))
        kjPause(12)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(channel.waitForNonExistence(timeout: 10), "Back closes the player")
        let page = app.staticTexts["transmissionState"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertEqual(page.value as? String, "Ready")
        kjPause(2)
        XCTAssertFalse(channel.exists, "the channel does not start again by itself")
        XCTAssertTrue(kjFocusKey(app).hasPrefix("nav-"), "focus is on the top bar: \(kjFocusKey(app))")
        XCTAssertTrue(app.buttons["transmissionWatch"].exists, "Watch is there to go back to the channel")
        kjScreenshot("transmission-after-back", app: app)
    }
}
