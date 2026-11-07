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
        // Select lights the strip's first control (CC); right walks to Like, then Guide.
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        for _ in 0..<4 where !guideControl.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(guideControl.isSelected, "Select then right lights Guide, after CC and Like")
        // Select on the lit Guide control opens the guide; Menu closes it and lets go of the control.
        XCUIRemote.shared.press(.select)
        let guide = app.descendants(matching: .any)["receiverGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Select on Guide opens the guide")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
        kjPause(0.6)
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of the control that opened it")
        // With the strip up, right lights CC and never opens the guide (owner, 2026-11-07).
        let captions = app.buttons["captionsControl"]
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(captions.isSelected, "Right on the strip lights CC")
        XCTAssertFalse(guide.exists, "Right on the strip does not open the guide")
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertFalse(guide.exists, "Left past CC stops there")
        // Right on the bare picture opens the guide (owner, 2026-11-04): wait for the strip to go.
        XCTAssertTrue(captions.waitForNonExistence(timeout: 10), "the strip hides over a playing picture")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Right on the bare picture opens the guide")
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

        // Right in the guide turns to the next region; Menu closes the guide and lets go of its
        // control, so the strip can hide again.
        // With the strip up, left walks its controls; on the bare picture it opens the guide.
        XCTAssertTrue(captions.waitForNonExistence(timeout: 10), "the strip hides after the tune")
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Left on the bare picture opens the guide")
        let region = app.staticTexts["guideRegion"]
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let home = region.label
        XCUIRemote.shared.press(.right)
        let turned = NSPredicate { _, _ in region.label != home }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: turned, object: nil)], timeout: 5), .completed,
                       "Right turns the guide to another region: \(home)")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the next region's channels load into the guide")
        kjScreenshot("\(skin)-g4-next-region", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of its control")

        // Radio: Back to the region; television is the first shelf and radio the next, so one
        // press down from the channel just left reaches a station. Over a playing picture the
        // first Back hides the strip, as Apple's TV app does, and the second leaves.
        XCUIRemote.shared.press(.menu)
        kjPause(0.6)
        if current.exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(current.waitForNonExistence(timeout: 10), "Back, then Back, leaves the channel")
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
        // The bar names the song in place of "On air" while the station names one (PR 33), so read
        // the state off its Play/Pause control: Pause means playing or tuning.
        XCTAssertEqual(app.buttons["radioBarToggle"].label, "Pause",
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
