import XCTest

/// The links the Top Shelf's slides carry open the screen they name, and a link that is not one
/// changes nothing.
final class DeepLinkUITests: XCTestCase {
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTopShelfLinksOpenTheirScreens() throws {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the receiver must load")

        app.open(try XCTUnwrap(URL(string: "khajistan://receiver/indus")))
        // A region page is shelves of channels: its first card is what marks it open.
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 60), "khajistan://receiver/indus must open a region page")
        XCTAssertTrue(app.staticTexts["Indus"].exists, "the region page must be Indus")
        screenshot("link-receiver-indus", app: app)

        app.open(try XCTUnwrap(URL(string: "khajistan://transmission")))
        let state = app.descendants(matching: .any)["transmissionState"]
        XCTAssertTrue(state.waitForExistence(timeout: 60), "khajistan://transmission must open the station page")
        screenshot("link-transmission", app: app)

        // XCUIApplication.open relaunches the app, so each link below lands on a fresh launch, whose
        // screen is the receiver's front. A link that is not one, and a region the index does not
        // list, must leave it there.
        for text in ["khajistan://library", "khajistan://receiver/nowhere", "khajistan://transmission/100"] {
            app.open(try XCTUnwrap(URL(string: text)))
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "\(text) must leave the receiver's front")
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            XCTAssertFalse(tv.exists, "\(text) must not open a region page")
            XCTAssertFalse(state.exists, "\(text) must not open the station page")
        }
        screenshot("link-refused", app: app)
    }

    /// Seven channels, from a hand-made schedule (Fixtures/programming-seven-channels.json, one
    /// 24-hour strip on each channel): the station page carries a card for each and focus walks
    /// right to Channel 7, which opens; Channel Up there goes round to Channel 1, Down back to 7.
    /// The programmes carry no play_url, so each change is the plain retune (`switchChannel`), not
    /// the cut behind the picture (`switchBehind`), which needs a playable source.
    func testSevenChannelsOnThePageAndRoundTheDial() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-seven-channels.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-04T12:00:00+05:00"]
        kjLaunch(app)
        let page = app.staticTexts["transmissionState"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        waitUntil(20) { (page.value as? String) == "Ready" }
        XCTAssertTrue(page.label.contains("7 scheduled channels"), page.label)

        let seventh = app.buttons["transmission-channel-7"]
        for _ in 0..<4 where !app.buttons["transmission-channel-1"].hasFocus { XCUIRemote.shared.press(.down) }
        for _ in 0..<10 where !(seventh.exists && seventh.hasFocus) { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(seventh.exists && seventh.hasFocus, "focus walks right to Channel 7's card")
        screenshot("seven-1-channel-7-card", app: app)
        XCUIRemote.shared.press(.select)

        let channel = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "Channel 7 opens")
        XCTAssertEqual(channel.label, "7")
        // A press made while a pigeon flies (the once-a-launch sign-on, or a change) stops channel
        // changes for the rest of the player's life: found 2026-11-04, on main too, with two
        // channels. Until that is fixed this test lets each flight land before it presses.
        kjPause(8)
        tune(.up, until: "1", channel)
        XCTAssertEqual(channel.label, "1", "Channel Up from 7 goes round to 1")
        screenshot("seven-2-up-to-1", app: app)
        kjPause(8)
        tune(.down, until: "7", channel)
        XCTAssertEqual(channel.label, "7", "Channel Down from 1 goes round to 7")
    }

    /// Presses once, and again if the channel has not moved in twelve seconds, a few times over.
    private func tune(_ button: XCUIRemote.Button, until label: String, _ channel: XCUIElement) {
        for _ in 0..<4 where !(channel.exists && channel.label == label) {
            XCUIRemote.shared.press(button)
            waitUntil(12) { channel.exists && channel.label == label }
        }
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) {
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                           timeout: timeout)
    }
}
