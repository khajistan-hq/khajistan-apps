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
        XCUIRemote.shared.press(.down)
        for (index, wait) in [0.3, 0.6, 0.6, 0.6, 0.6, 0.8, 1.0, 1.5, 2.0].enumerated() {
            Thread.sleep(forTimeInterval: wait)
            shot(String(format: "%02d-change", index + 3), app)
        }
    }

    /// The same change with nothing else going on: no screenshots during it, which freeze the
    /// simulator's screen for a moment. For a screen recording to measure the wipe's frames.
    func testChannelChangeUndisturbed() {
        openChannel()
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 8)
    }

    /// A slow signal: the change flight, then the long flights over the held ground.
    func testSlowTuneShowsTheWaitFlights() {
        app.launchArguments += ["-kjslowtune", "12"]
        openChannel()
        XCUIRemote.shared.press(.down)
        for index in 0..<10 {
            Thread.sleep(forTimeInterval: 1.4)
            shot(String(format: "w%02d", index), app)
        }
    }

    /// A press while the pigeon is still flying must not be lost: down, and down again 0.6 s
    /// later, lands two channels on, not one (2026-10-06: a view laid over the screen during a
    /// flight kept presses from the player).
    func testAPressDuringAFlightIsNotLost() {
        openChannel()
        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let start = current.label
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 12)
        let one = current.label
        XCTAssertNotEqual(one, start, "one press moves one channel")
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(current.label, start, "up comes back")
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        shot("mid-flight", app)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 14)
        XCTAssertNotEqual(current.label, one, "the second press, made mid-flight, moved on a second channel")
        XCTAssertNotEqual(current.label, start)
    }

    private let app = XCUIApplication()

    private func openChannel() {
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        kjFocusStrip(app)
        // Indus carries the most television; walk to it if focus landed elsewhere.
        for _ in 0..<40 where focusedRegion.exists && focusedRegion.identifier != "region-indus" {
            XCUIRemote.shared.press(.right)
        }
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
