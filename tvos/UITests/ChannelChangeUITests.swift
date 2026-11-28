import XCTest

/// Photographs a channel change from the first press to the new picture: the pigeon flying in
/// over the skin's ground, the held wing, and the wing sweeping off the new picture.
final class ChannelChangeUITests: XCTestCase {
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChannelChangeSequence() {
        openChannel()
        XCUIRemote.shared.press(.right)
        for (index, wait) in [0.3, 0.6, 0.6, 0.6, 0.6, 0.8, 1.0, 1.5, 2.0].enumerated() {
            Thread.sleep(forTimeInterval: wait)
            shot(String(format: "%02d-change", index + 3), app)
        }
    }

    /// The same change with nothing else going on: no screenshots during it, which freeze the
    /// simulator's screen for a moment. For a screen recording to measure the wipe's frames.
    func testChannelChangeUndisturbed() {
        openChannel()
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 8)
    }

    /// A slow signal: the change flight, then the long flights over the held ground.
    func testSlowTuneShowsTheWaitFlights() {
        app.launchArguments += ["-kjslowtune", "12"]
        openChannel()
        XCUIRemote.shared.press(.right)
        for index in 0..<10 {
            Thread.sleep(forTimeInterval: 1.4)
            shot(String(format: "w%02d", index), app)
        }
    }

    /// A press while the pigeon is still flying must not be lost: right, and right again 0.6 s
    /// later, lands two channels on, not one. Right is the next channel and Left the one before
    /// since the players' remote map of 2026-11-28 (they were Down and Up) (2026-10-06: a view laid over the screen during a
    /// flight kept presses from the player).
    ///
    /// A dead carrier moves the player on by itself, and that move was read as a press: the press back landed
    /// on ABN Urdu, not ABN News, because ABN News was off air (CI 2026-11-15, run 43685308130).
    /// `-kjnomoveon` leaves a dead channel on screen, so only the test's presses move the channel.
    func testAPressDuringAFlightIsNotLost() {
        app.launchArguments += ["-kjnomoveon", "YES"]
        openChannel()
        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let start = current.label
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 12)
        let one = current.label
        XCTAssertNotEqual(one, start, "one press moves one channel")
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(current.label, start, "left comes back")
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 0.6)
        shot("mid-flight", app)
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 14)
        XCTAssertNotEqual(current.label, one, "the second press, made mid-flight, moved on a second channel")
        XCTAssertNotEqual(current.label, start)
    }

    /// Indus's first television channels in the recorded list; the walk opens the first of them.
    private static let indusTelevision = ["swept-pk-24-news-hd", "swept-pk-365-news", "swept-pk-abn-news",
                                          "swept-us-abn-urdu", "swept-in-balle-balle", "swept-pk-capital-tv"]

    /// `-kjnomoveon` holds a dead channel on screen, which the test above relies on.
    func testNoMoveOnHoldsADeadChannel() throws { try deadChannel(held: true) }

    /// Without `-kjnomoveon` the player moves past dead channels, so the test above it is not
    /// passing on a flag that does nothing.
    func testADeadChannelMovesOnWithoutTheFlag() throws { try deadChannel(held: false) }

    /// `-kjdeadchannels` makes Indus's first six channels fail as a dead signal does. The player
    /// waits 3 s on a dead signal before it moves on, and `openChannel` waits 9 s after Select.
    private func deadChannel(held: Bool) throws {
        // The ids are the recorded list's; a live run reads the live lists, where they may be absent.
        try XCTSkipIf(kjLiveMedia, "needs the recorded Indus list")
        app.launchArguments += ["-kjdeadchannels", Self.indusTelevision.joined(separator: ",")]
        if held { app.launchArguments += ["-kjnomoveon", "YES"] }
        openChannel()
        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        if held {
            let opened = current.label
            XCTAssertTrue(Self.indusTelevision.contains(opened), "a dead channel opened, got \(opened)")
            Thread.sleep(forTimeInterval: 6)
            XCTAssertEqual(current.label, opened, "-kjnomoveon holds the dead channel on screen")
        } else {
            let passed = NSPredicate { _, _ in current.exists && !Self.indusTelevision.contains(current.label) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: passed, object: nil)], timeout: 60), .completed,
                           "the player moves past every dead channel, last on \(current.label)")
        }
    }

    /// A press made while the sign-on's pigeon is still flying must not stop channel changes for
    /// the rest of the player's life (found 2026-11-04): Right at once, and Right again once the
    /// change has had time to land, must each move the channel (Right is the next channel since
    /// 2026-11-28; it was Up).
    func testAPressDuringTheSignOnDoesNotStopLaterPresses() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-10.json").path
        let station = XCUIApplication()
        station.launchArguments = ["-kjskin", "day", "-kjtab", "transmission", "-kjschedulefile", schedule,
                                   "-kjnow", "2026-10-15T14:10:00+05:00"]
        kjLaunch(station)
        let page = station.staticTexts["transmissionState"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        waitUntil(20) { (page.value as? String) == "Ready" }
        let card = station.buttons["transmission-channel-1"]
        XCTAssertTrue(kjFocus(card, app: station), "channel 1's card must take focus")
        XCUIRemote.shared.press(.select)

        let channel = station.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "Channel 1 opens")
        XCTAssertEqual(channel.label, "1")
        // The sign-on is still flying: this press lands mid-flight, or is skipped.
        XCUIRemote.shared.press(.right)
        kjPause(12)
        let afterFirst = channel.label
        // Whatever the first press did, every later one moves the channel.
        for press in 1...2 {
            let before = channel.label
            XCUIRemote.shared.press(.right)
            waitUntil(12) { channel.exists && channel.label != before }
            XCTAssertNotEqual(channel.label, before, "press \(press) after the sign-on moves the channel (first press left it on \(afterFirst))")
        }
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) {
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                           timeout: timeout)
    }

    private let app = XCUIApplication()

    private func openChannel() {
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        // Indus carries the most television.
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)

        let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 60))
        let focusedChannel = channels.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 0.3)
        shot("01-opening-ground", app)
        Thread.sleep(forTimeInterval: 9)
        shot("02-first-picture", app)
    }
}
