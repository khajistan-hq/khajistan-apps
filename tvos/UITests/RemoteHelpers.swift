import XCTest

/// What every remote-driven UI test needs: a kept screenshot, a pause that lets focus settle, and
/// a walk toward an element by the Siri Remote's presses.
extension XCTestCase {
    /// Existing navigation fixtures keep the map visible; autoplay has its own acceptance test.
    /// The receiver's list, feeds and map and the chat room list are recorded answers
    /// (`Fixtures/recorded`, shared with the iPhone tests; see `kjFixtureArguments`): one TLS
    /// error on receiver-index.json failed pull requests that never touched the Receiver (CI, 2026-11-14).
    func kjLaunch(_ app: XCUIApplication, autoplay: Bool = false) {
        if !autoplay { app.launchArguments += ["-kjnoautoplay", "YES"] }
        app.launchArguments += kjFixtureArguments(kjRecordedFixtures)
        app.launch()
    }

    /// Waits for the channel just opened to play. When it does not, Down tunes the next channel,
    /// as the player's own line says, up to `tries` channels; then the test is skipped, naming what
    /// each said. For tests whose subject is the strip or captions, not one carrier: 24 News HD and
    /// ABN News did not reach the runner and failed them (CI 2026-11-15, run 43672877637).
    /// `accept` narrows which channel counts, by id: a captions test needs a language the
    /// recogniser takes, and Down can bring up DD Kashir, which plays but is Kashmiri.
    func kjTuneUntilPlaying(_ app: XCUIApplication, tries: Int = 4, accept: @escaping (String) -> Bool = { _ in true }) throws {
        let state = app.staticTexts["playerState"]
        let current = app.staticTexts["currentChannel"]
        var tried: [String] = []
        var turnedDown = 0
        for attempt in 0..<tries {
            // After Down, only the next channel playing counts: the one being left can still
            // reach Playing before the cut (Bugbot on PR 66).
            let left = attempt > 0 && current.exists ? current.label : nil
            if attempt > 0 { XCUIRemote.shared.press(.down); kjPause(1) }
            XCTAssertTrue(state.waitForExistence(timeout: 20), "the player opens")
            let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                state.label == "Playing" && (left == nil || (current.exists && current.label != left))
            }, object: nil)
            // A channel that plays but fails `accept` moves on at once, not after the timeout.
            let played = XCTWaiter.wait(for: [playing], timeout: 30) == .completed
            let id = current.exists ? current.label : "?"
            if played {
                if accept(current.exists ? current.label : "") { return }
                turnedDown += 1
                tried.append("\(id): played, not accepted")
            } else {
                tried.append("\(id): \(state.label)")
            }
        }
        let why = "No accepted channel played on this runner in \(tries) tries: \(tried.joined(separator: "; "))"
        // The local test video always plays: if it did not, the test media is broken. When every
        // channel played and `accept` turned each down, no carrier was dead: the filter or the
        // list is wrong, and that fails too, rather than reading as a dead network.
        guard kjLiveMedia, turnedDown < tries else { XCTFail(why); return }
        throw XCTSkip(why)
    }

    var kjRecordedFixtures: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/recorded").path
    }

    func kjScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func kjPause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Reach the Receiver's region strip with remote presses, including when focus has moved
    /// into a channel shelf below it. Never selects or changes the highlighted channel.
    @discardableResult
    func kjFocusStrip(_ app: XCUIApplication) -> Bool {
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 {
            if focused.exists { return true }
            let current = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let belowStrip = current.exists && !current.identifier.hasPrefix("nav-") && regions.firstMatch.exists
                && current.frame.midY > regions.firstMatch.frame.midY
            XCUIRemote.shared.press(belowStrip ? .up : .down)
            kjPause(0.35)
        }
        return focused.exists
    }

    /// Presses toward `element` until it has focus, steering by where it sits against the focused
    /// control. Returns whether it got there.
    @discardableResult
    func kjFocus(_ element: XCUIElement, app: XCUIApplication, limit: Int = 40) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard element.exists, focused.exists else {
                XCUIRemote.shared.press(.down)
                kjPause(0.4)
                continue
            }
            let target = element.frame, here = focused.frame
            let dx = target.midX - here.midX, dy = target.midY - here.midY
            // A different row first (up or down), then along the row.
            if abs(dy) > max(here.height, target.height) * 0.6 {
                XCUIRemote.shared.press(dy > 0 ? .down : .up)
            } else {
                XCUIRemote.shared.press(dx > 0 ? .right : .left)
            }
            kjPause(0.4)
        }
        return element.exists && element.hasFocus
    }
}

/// The run plays live carriers (`TEST_RUNNER_KJ_LIVE_RECEIVER=1`), which may be down; the
/// default local media may not.
var kjLiveMedia: Bool { ProcessInfo.processInfo.environment["KJ_LIVE_RECEIVER"] == "1" }

/// The recorded lists and local media by default, so a navigation test reads no live list and
/// plays no live carrier. `TEST_RUNNER_KJ_LIVE_RECEIVER=1` makes a live probe: lists live first
/// with the recording behind them, streams live.
func kjFixtureArguments(_ directory: String) -> [String] {
    if kjLiveMedia { return ["-kjfixtures", directory] }
    return ["-kjfixtures", directory, "-kjfixturesonly", "YES", "-kjfixturemedia", "YES"]
}
