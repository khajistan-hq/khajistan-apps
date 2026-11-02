import XCTest

/// A region page's live cards, on the live receiver: the hero plays the focused channel and a
/// television card shows a still this device took from its stream. Reads the network, so a still
/// gets two windows of 20 s (a carrier that does not answer is skipped for the next card).
final class LiveCardsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("KJLIVECARDS \(name): \(text)")
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.identifier
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            kjPause(0.5)
        }
    }

    private func wait(_ timeout: TimeInterval, until condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// Launches on the Receiver in `skin` and opens `region` from the strip, with focus on its first card.
    private func openRegion(_ region: String, skin: String, meter: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", "receiver"] + (meter ? ["-kjframemeter", "YES"] : [])
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the receiver must load")
        kjPause(3)
        XCTAssertTrue(kjFocusStrip(app), "focus must reach the region strip")
        for _ in 0..<20 where focusedID(app) != "region-\(region)" { press(.left) }
        for _ in 0..<40 where focusedID(app) != "region-\(region)" { press(.right) }
        XCTAssertEqual(focusedID(app), "region-\(region)")
        XCUIRemote.shared.press(.select)
        let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 60), "\(region) must list channels")
        kjPause(2)
        for _ in 0..<3 where !focusedID(app).hasPrefix("channel-") { press(.down) }
        XCTAssertTrue(focusedID(app).hasPrefix("channel-"), "a card takes focus, got \(focusedID(app))")
        return app
    }

    private func stilled(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-' AND label CONTAINS 'live picture'")).firstMatch
    }

    func testRegionPageShowsTheHeroAndATelevisionStill() {
        let app = openRegion("maghreb", skin: "day")
        let hero = app.descendants(matching: .any)["regionHero"]
        XCTAssertTrue(hero.exists, "the region page opens on the hero")
        XCTAssertTrue(app.descendants(matching: .any)["heroName"].exists, "the hero names the focused channel")
        XCTAssertTrue(app.descendants(matching: .any)["shelf-tv"].exists)
        // A still on a television card: one window, then a second on the next card.
        var got = wait(20) { self.stilled(app).exists }
        if !got {
            press(.right)
            got = wait(20) { self.stilled(app).exists }
        }
        XCTAssertTrue(got, "a television card shows a still within 20 s (one retry)")
        let picture = app.descendants(matching: .any)["heroPicture"]
        let live = wait(25) { (picture.value as? String) == "live" }
        note("hero", "picture value=\(picture.value as? String ?? "?") live=\(live) stilled=\(stilled(app).label)")
        shot("day-maghreb-hero", app)
    }

    /// The Maghreb page in each skin once stills have come, then focus on radio; and the frame
    /// meter while focus walks along the television shelf with the hero playing.
    func testLiveCardsInEverySkin() {
        for skin in ["day", "grove", "smut"] {
            let app = openRegion("maghreb", skin: skin, meter: skin == "day")
            _ = wait(30) { self.stilled(app).exists }
            kjPause(4)
            shot("\(skin)-maghreb-television", app)
            if skin == "day" {
                let meter = app.staticTexts["frameMeter"]
                let before = meter.label
                for _ in 0..<8 {
                    XCUIRemote.shared.press(.right)
                    kjPause(1.2)
                }
                for _ in 0..<8 {
                    XCUIRemote.shared.press(.left)
                    kjPause(0.4)
                }
                kjPause(3)
                note("framemeter-walk", "before: \(before) | after: \(meter.label)")
            }
            press(.down)
            kjPause(3)
            shot("\(skin)-maghreb-radio", app)
            app.terminate()
        }
    }
}
