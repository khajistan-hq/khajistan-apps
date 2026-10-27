import XCTest

/// The Receiver's guide and radio's Now Playing, in each skin. A television channel opens; Right
/// three times lights Guide on the strip (after CC and Like); Select opens the guide with LIVE on
/// the channel playing; Down and Select tune the next row. Then Menu back to the region, and a radio
/// station shows NOW PLAYING with its name.
final class ReceiverGuideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDay() { walk("day") }
    func testGrove() { walk("grove") }
    func testSmut() { walk("smut") }

    private func walk(_ skin: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", skin]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusStrip(app), "focus must reach the region strip")
        // Indus carries the most television and radio.
        for _ in 0..<40 where focusedRegion.exists && focusedRegion.identifier != "region-indus" {
            XCUIRemote.shared.press(.right)
        }
        XCUIRemote.shared.press(.select)

        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        // Focus may start in the top bar; down enters the first shelf, television.
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(focusedChannel.exists, "the remote reaches a channel")
        kjScreenshot("\(skin)-g1-region", app: app)
        XCUIRemote.shared.press(.select)

        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        let start = current.label
        let guideControl = app.buttons["guideControl"]
        XCTAssertTrue(guideControl.waitForExistence(timeout: 30), "the strip offers the guide once the channel plays")
        for _ in 0..<3 { XCUIRemote.shared.press(.right); kjPause(0.4) }
        XCTAssertTrue(guideControl.isSelected, "Right three times lights Guide, after CC and Like")
        XCUIRemote.shared.press(.select)

        let guide = app.descendants(matching: .any)["receiverGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Select opens the guide")
        let live = app.descendants(matching: .any)["guide-\(start)"]
        XCTAssertTrue(live.exists && live.label.contains("Live"), "LIVE marks the channel playing: \(live.label)")
        XCTAssertTrue(live.isSelected, "the guide opens on the channel playing")
        kjPause(1)
        kjScreenshot("\(skin)-g2-guide", app: app)
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertFalse(live.isSelected, "Down lights the next row")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Select closes the guide and tunes")
        let moved = NSPredicate { _, _ in current.label != start }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 30), .completed,
                       "the row chosen in the guide is tuned")
        kjPause(2)
        kjScreenshot("\(skin)-g3-tuned", app: app)

        // Left closes the guide and lets go of its control, so the strip can hide again.
        for _ in 0..<3 { XCUIRemote.shared.press(.right); kjPause(0.4) }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "the guide opens again")
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Left closes the guide")
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of its control")

        // Radio: Menu back to the region; television is the first shelf and radio the next, so one
        // press down from the channel just left reaches a station.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].waitForExistence(timeout: 10), "Indus has a radio shelf")
        kjPause(1)
        XCUIRemote.shared.press(.down)
        kjPause(1)
        let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(focused.exists, "down reaches the radio shelf")
        XCUIRemote.shared.press(.select)
        let nowPlaying = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] '\u{25CF} Now playing'")).firstMatch
        if nowPlaying.waitForExistence(timeout: 40) {
            kjPause(2)
            kjScreenshot("\(skin)-g4-radio", app: app)
        } else {
            kjScreenshot("\(skin)-g4-radio-not-playing", app: app)
            XCTFail("the station played and showed Now Playing")
        }
    }
}
