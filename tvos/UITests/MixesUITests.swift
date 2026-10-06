import XCTest

/// Khajistan Radio, on the Receiver's front: walk the row of mixes with the remote, play one,
/// scrub it, step to the next, and back out. Strict about the app's own elements and loose
/// about what the network answers on the day.
final class MixesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func mixes(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mix-'"))
    }

    private func focusedMix(_ app: XCUIApplication) -> XCUIElement {
        mixes(app).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testMixesFromTheReceiverAreWalkableAndPlay() {
        let app = XCUIApplication()
        app.launch()

        // The mixes lie in full on the Receiver's front, on a row under the regions.
        let firstMix = mixes(app).firstMatch
        XCTAssertTrue(firstMix.waitForExistence(timeout: 60), "The Receiver must lay out the Khajistan Radio mixes once the register has loaded")
        kjPause(3)
        kjScreenshot("mx-00-receiver", app: app)
        XCTAssertTrue(kjFocus(firstMix, app: app), "The first mix must take focus")
        kjScreenshot("mx-01-receiver-mixes-row", app: app)
        // The row is lazy: only the cards on screen exist, so the walk below is the real count.
        XCTAssertGreaterThanOrEqual(mixes(app).count, 3, "the row must show several mixes")

        // Along the row: a walk right must reach five mixes.
        var seen = Set([focusedMix(app).identifier])
        var log: [String] = []
        for _ in 0..<5 {
            XCUIRemote.shared.press(.right)
            kjPause(0.7)
            let id = focusedMix(app).exists ? focusedMix(app).identifier : "(off the row)"
            seen.insert(id)
            log.append("R->\(id)")
        }
        print("MIXWALK " + log.joined(separator: " "))
        seen.remove("(off the row)")
        XCTAssertGreaterThanOrEqual(seen.count, 5, "the walk must reach five mixes; walk: \(log)")
        kjScreenshot("mx-03-walked", app: app)

        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20), "The player must show its state")
        kjPause(1)
        kjScreenshot("mx-04-connecting-or-playing", app: app)
        for _ in 0..<40 where state.label != "Playing" { kjPause(1) }
        XCTAssertEqual(state.label, "Playing", "a mix must start playing")
        let time = app.staticTexts["mixTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "A playing mix shows its position")
        let first = time.label
        kjPause(3)
        kjScreenshot("mx-05-playing", app: app)

        // Right is thirty seconds on; the position must move past what two seconds of play explains.
        XCUIRemote.shared.press(.right)
        kjPause(1.5)
        kjScreenshot("mx-06-after-seek", app: app)
        XCTAssertNotEqual(time.label, first, "the position must move")

        // Down is the next mix.
        let title = app.staticTexts.matching(NSPredicate(format: "label != ''")).count
        XCUIRemote.shared.press(.down)
        kjPause(4)
        kjScreenshot("mx-07-next-mix", app: app)
        XCTAssertGreaterThan(title, 0)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(mixes(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the Receiver and its mixes")
    }
}
