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
        // The strip hides after 2.6 s idle, and the first press then only wakes it: on a busy
        // runner the third Right fell one short of Guide (CI 2026-10-29, Grove; locally, Smut).
        kjPause(3)   // the picture comes up first; presses during "Tuning" landed as the strip arrived
        for _ in 0..<8 where !guideControl.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(guideControl.isSelected, "Right lights Guide, after CC and Like")
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
        for _ in 0..<8 where !guideControl.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
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
        // A playing station keeps the Apple TV awake: radio plays through the app's own audio
        // engine, which tvOS does not count as playing, and the box slept and stopped the sound
        // (owner, 2026-10-29).
        let awake = app.staticTexts["keepAwake"].firstMatch
        func awakeIs(_ value: String) -> Bool {
            let match = NSPredicate { _, _ in awake.exists && awake.label == value }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: match, object: nil)], timeout: 5) == .completed
        }
        if nowPlaying.waitForExistence(timeout: 40) {
            XCTAssertTrue(awakeIs("on"), "a playing station holds the Apple TV awake")
            kjPause(2)
            kjScreenshot("\(skin)-g4-radio", app: app)
        } else {
            kjScreenshot("\(skin)-g4-radio-not-playing", app: app)
            XCTFail("the station played and showed Now Playing")
        }

        // Menu leaves the station playing, in Sonos's small player under the region; Off stops it.
        XCUIRemote.shared.press(.menu)
        let bar = app.descendants(matching: .any)["radioBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the radio plays on in the small player")
        XCTAssertTrue(app.buttons["radioBarName"].label.contains("On air") || app.buttons["radioBarName"].label.contains("Tuning"),
                      "the bar says the station is on: \(app.buttons["radioBarName"].label)")
        kjPause(1)
        kjScreenshot("\(skin)-g5-radio-bar", app: app)
        let off = app.buttons["radioBarOff"]
        XCTAssertTrue(kjFocus(off, app: app), "the remote reaches the bar's Off")
        XCTAssertTrue(awakeIs("on"), "the station playing on in the small player still holds it awake")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "Off turns the radio off and the bar goes")
        XCTAssertTrue(awakeIs("off"), "with nothing playing the Apple TV may sleep again")
    }
}
