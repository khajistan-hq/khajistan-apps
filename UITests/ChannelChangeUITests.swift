import XCTest

/// Photographs a channel change from the first press to the new picture: the ground coming up
/// behind the pigeon, the held ground with the incoming channel's name, and the reveal.
final class ChannelChangeUITests: XCTestCase {
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChannelChangeSequence() {
        let app = XCUIApplication()
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 where !focusedRegion.exists { XCUIRemote.shared.press(.down) }
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

        XCUIRemote.shared.press(.down)
        for (index, wait) in [0.15, 0.35, 0.5, 0.8, 1.5, 2.5, 3.0].enumerated() {
            Thread.sleep(forTimeInterval: wait)
            shot(String(format: "%02d-change", index + 3), app)
        }
    }
}
