import XCTest

/// Picture in picture on the Receiver. A television channel opens; Select lights CC and Right
/// walks the strip to PiP; Select puts the picture in a corner and the player screen closes on
/// the region page. Opening another channel closes the window (one signal at a time).
final class PictureInPictureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPictureGoesToTheCorner() throws {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusStrip(app), "focus must reach the region strip")
        for _ in 0..<40 where focusedRegion.exists && focusedRegion.identifier != "region-indus" {
            XCUIRemote.shared.press(.right)
        }
        XCUIRemote.shared.press(.select)

        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(focusedChannel.exists, "the remote reaches a channel")
        XCUIRemote.shared.press(.select)

        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        let pipControl = app.buttons["pipControl"]
        let captions = app.buttons["captionsControl"]
        XCTAssertTrue(captions.waitForExistence(timeout: 30), "the strip shows once the channel plays")
        // PiP sits in the same strip as CC, so it is there now or not at all. The Apple TV
        // simulator answers isPictureInPictureSupported() with false (Xcode 27, 2026-11-06) and
        // the strip leaves PiP out; only a real Apple TV can run the rest.
        guard pipControl.exists else { throw XCTSkip("this device has no picture in picture") }
        kjPause(3)
        // Select wakes the strip and lights CC; PiP sits at the end of it.
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        for _ in 0..<5 where !pipControl.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(pipControl.isSelected, "Right walks the strip to PiP, after CC, Like and Guide")
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(current.waitForNonExistence(timeout: 15), "the player screen closes behind the window")
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 10), "the region page is back")
        XCTAssertFalse(app.descendants(matching: .any)["radioBar"].exists, "a picture in the corner shows no radio bar")
        kjPause(3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "pip-corner"
        shot.lifetime = .keepAlways
        add(shot)

        // Another channel: the window closes as the new signal starts.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(current.waitForExistence(timeout: 15), "a channel opens over the region")
        kjPause(4)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "pip-closed-by-next-channel"
        after.lifetime = .keepAlways
        add(after)
    }
}
