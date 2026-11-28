import XCTest

/// The players' remote map (owner, 2026-11-28; Core/RemoteGesture.swift, `RemoteMap`), proved with
/// presses in both full-screen players. On the picture: Down opens the guide and nothing else
/// does, Up lights the strip's first control, Right and Left change channel and come back, and one
/// click is the next channel. With a control lit: Down lets go, and a click works the control at
/// once and changes no channel. XCUIRemote sends presses only; a swipe sends the app the same
/// move, and the double click's timing is proved in the host tests (ClickTally).
final class RemoteMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func waitFor(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                       timeout: timeout) == .completed
    }

    /// Right until `control` is lit, never past the strip's length.
    private func walk(to control: XCUIElement) {
        for _ in 0..<5 where !control.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
    }

    func testReceiverFollowsTheMap() throws {
        let app = XCUIApplication()
        // `-kjnomoveon`: only the test's presses change channel, never a dead signal's own move.
        app.launchArguments += ["-kjskin", "day", "-kjnomoveon", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(focusedChannel.exists, "the remote reaches a channel")
        XCUIRemote.shared.press(.select)

        let current = app.staticTexts["currentChannel"]
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        try kjTuneUntilPlaying(app)
        kjPause(3)   // the opening flight lands
        let start = current.label
        let guide = app.descendants(matching: .any)["receiverGuide"]
        let captions = app.descendants(matching: .any)["captionsControl"]
        let guideControl = app.buttons["guideControl"]

        // Up lights the first control; it opens no guide and changes no channel.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertTrue(captions.isSelected, "Up lights the strip's first control, Captions")
        XCTAssertFalse(guide.exists, "Up does not open the guide")
        // Up on a lit control does nothing.
        XCUIRemote.shared.press(.up)
        kjPause(0.6)
        XCTAssertTrue(captions.isSelected, "Up on a lit control leaves it lit")
        // Down lets go, and that press opens no guide.
        XCUIRemote.shared.press(.down)
        kjPause(0.8)
        XCTAssertFalse(captions.isSelected, "Down lets go of the lit control")
        XCTAssertFalse(guide.exists, "the Down that lets go does not open the guide")
        XCTAssertEqual(current.label, start, "Up and Down change no channel")

        // Right is the next channel and Left comes back; neither opens the guide.
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitFor(30) { current.exists && current.label != start }, "Right changes channel, still on \(current.label)")
        let next = current.label
        XCTAssertFalse(guide.exists, "Right does not open the guide")
        _ = waitFor(20) { state.label == "Playing" }
        kjPause(2)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitFor(30) { current.exists && current.label == start }, "Left comes back to \(start), on \(current.label)")
        XCTAssertFalse(guide.exists, "Left does not open the guide")
        _ = waitFor(20) { state.label == "Playing" }
        kjPause(2)

        // One click is the next channel: the one Right reached.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitFor(30) { current.exists && current.label != start }, "a single Select changes channel")
        XCTAssertEqual(current.label, next, "a click is the next channel, the one Right reached")
        XCTAssertFalse(guide.exists, "a click does not open the guide")
        _ = waitFor(20) { state.label == "Playing" }
        kjPause(2)

        // With a control lit, Select works it at once and changes no channel.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertTrue(captions.isSelected, "Up lights Captions on the new channel")
        walk(to: guideControl)
        XCTAssertTrue(guideControl.isSelected, "Right walks the strip to Guide")
        XCTAssertEqual(current.label, next, "walking the strip changes no channel")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Select works the lit control: Guide opens the guide")
        kjPause(2)   // well past the 0.3 s a click on the picture waits
        XCTAssertEqual(current.label, next, "Select on a lit control changes no channel")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
        kjPause(0.6)
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of its control")

        // Down on the picture opens the guide.
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the picture opens the guide")
        XCTAssertEqual(current.label, next, "opening the guide changes no channel")
        kjScreenshot("remote-map-receiver-guide", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
    }

    /// The same map on the house station. Fixture: the November build's channels 5, 8, 14 and 15;
    /// 14 and 15 are neighbours on air.
    func testTransmissionFollowsTheMap() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-11-08.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00", "-kj.transmission.lastChannel", "14"]
        kjLaunch(app)
        // The tab plays the channel at once (-kj.transmission.lastChannel; owner, 2026-11-28).
        let tuned = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(tuned.waitForExistence(timeout: 30))
        kjPause(12)   // the sign-on pigeon lands
        XCTAssertEqual(tuned.label, "14")
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        let guideControl = app.descendants(matching: .any)["guideControl"]
        let strip = ["subtitlesControl", "visualizerControl", "guideControl", "pipControl"].map { app.descendants(matching: .any)[$0] }
        func lit() -> [String] { strip.filter { $0.exists && $0.isSelected }.map(\.identifier) }

        // Up lights a control; it opens no guide and changes no channel.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertEqual(lit().count, 1, "Up lights one control on the strip: \(lit())")
        XCTAssertFalse(guide.exists, "Up does not open the guide")
        // Down lets go, and that press opens no guide.
        XCUIRemote.shared.press(.down)
        kjPause(0.8)
        XCTAssertEqual(lit(), [], "Down lets go of the lit control")
        XCTAssertFalse(guide.exists, "the Down that lets go does not open the guide")
        XCTAssertEqual(tuned.label, "14", "Up and Down change no channel")

        // Right is the next channel and Left comes back; neither opens the guide.
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitFor(30) { tuned.exists && tuned.label == "15" }, "Right tunes the next channel, on \(tuned.label)")
        XCTAssertFalse(guide.exists, "Right does not open the guide")
        kjPause(6)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitFor(30) { tuned.exists && tuned.label == "14" }, "Left comes back, on \(tuned.label)")
        XCTAssertFalse(guide.exists, "Left does not open the guide")
        kjPause(6)

        // One click is the next channel.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitFor(30) { tuned.exists && tuned.label == "15" }, "a single Select tunes the next channel, on \(tuned.label)")
        XCTAssertFalse(guide.exists, "a click does not open the guide")
        kjPause(6)

        // With a control lit, Select works it at once and changes no channel.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertEqual(lit().count, 1, "Up lights a control on channel 15: \(lit())")
        walk(to: guideControl)
        XCTAssertTrue(guideControl.isSelected, "Right walks the strip to Guide")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Select works the lit control: Guide opens the guide")
        kjPause(2)   // well past the 0.3 s a click on the picture waits
        XCTAssertEqual(tuned.label, "15", "Select on a lit control changes no channel")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Back closes the guide")
        kjPause(1)

        // Down on the picture opens the guide. Back may have left the Guide control lit; the
        // first Down then lets go, so the control is let go of before the press that is checked.
        if !lit().isEmpty { XCUIRemote.shared.press(.down); kjPause(0.8) }
        XCTAssertFalse(guide.exists, "letting go opens no guide")
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the picture opens the guide")
        XCTAssertEqual(tuned.label, "15", "opening the guide changes no channel")
        kjScreenshot("remote-map-transmission-guide", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Back closes the guide")
    }
}
