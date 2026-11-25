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
    /// as the player's own line says, up to `tries` channels; then a live run is skipped, naming what
    /// each said. It fails instead on the local test video, and when every channel played and
    /// `accept` turned each down. For tests whose subject is the strip or captions, not one carrier: 24 News HD and
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

    /// Reach the Receiver's region list (the A–Z list beside the map, the front's one way to a
    /// region since 2026-11-17) with remote presses, including when focus has moved into a shelf
    /// below the front. Never selects. Its rows carry `region-<id>`.
    func kjFocusRegions(_ app: XCUIApplication) -> Bool {
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<14 {
            if focused.exists { return true }
            let current = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let list = app.descendants(matching: .any).matching(identifier: "regionList").firstMatch
            if current.exists, current.identifier.hasPrefix("nav-") {
                XCUIRemote.shared.press(.down)
            } else if current.exists, list.exists, current.frame.minY > list.frame.maxY {
                XCUIRemote.shared.press(.up)
            } else {
                XCUIRemote.shared.press(.right)
            }
            kjPause(0.35)
        }
        return focused.exists
    }

    /// Reach the foot of the front: the Beyond the atlas switch, at the bottom of the sidebar. One
    /// press down from it lands on the first shelf under the front (Liked, or News).
    @discardableResult
    func kjFocusFrontFoot(_ app: XCUIApplication) -> Bool {
        let toggle = app.buttons["beyondTheAtlas"]
        guard toggle.waitForExistence(timeout: 30) else { return false }
        return kjFocus(toggle, app: app)
    }

    /// Reach one region's row in the list (`indus` for `region-indus`), walking up or down it.
    @discardableResult
    func kjFocusRegion(_ app: XCUIApplication, _ id: String) -> Bool {
        guard kjFocusRegions(app) else { return false }
        let target = app.buttons["region-\(id)"]
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-' AND hasFocus == true")).firstMatch
        for _ in 0..<60 {
            guard target.exists else { return false }
            if target.hasFocus { return true }
            // Focus may be mid-move after a press: wait for it to land rather than give up.
            guard focused.exists else { kjPause(0.3); continue }
            XCUIRemote.shared.press(target.frame.midY > focused.frame.midY ? .down : .up)
            kjPause(0.3)
        }
        return target.exists && target.hasFocus
    }

    /// What has focus now, as text that changes when focus moves: its identifier and frame.
    /// The label stands in only when there is no identifier (two unnamed cards share a frame on
    /// a shelf that scrolls under a fixed focus position). It is NOT part of the key otherwise:
    /// a card's label gains "live picture" seconds after it takes focus (LiveCards.cardLabel),
    /// and that must not read as a move.
    func kjFocusKey(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard focused.exists else { return "" }
        let name = focused.identifier.isEmpty ? focused.label : focused.identifier
        return "\(name)|\(focused.frame)"
    }

    /// One remote press, then a wait until focus has moved (or `timeout`). On a slow CI runner a
    /// press takes seconds to land; a fixed pause presses again before it has, and the walk then
    /// steers from where focus was, not where it is. Returns whether focus moved.
    @discardableResult
    func kjPress(_ button: XCUIRemote.Button, app: XCUIApplication, timeout: TimeInterval = 4) -> Bool {
        let before = kjFocusKey(app)
        XCUIRemote.shared.press(button)
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            kjPause(0.2)
            let now = kjFocusKey(app)
            if !now.isEmpty && now != before { kjPause(0.2); return true }
        }
        return false
    }

    /// Reach `tab` in the top bar: up until a top-bar button (`nav-…`) has focus, then along it.
    /// Never a fixed count of presses: just after launch or a Back, the first presses can land
    /// before the app takes them.
    @discardableResult
    func kjFocusTopBar(_ tab: XCUIElement, app: XCUIApplication) -> Bool {
        guard kjIntoTopBar(app) else { return false }
        return kjFocus(tab, app: app)
    }

    /// Up until a top-bar button has focus, and no sideways press: where Up lands is what some
    /// tests check (the bar's default focus is the open section's tab).
    @discardableResult
    func kjIntoTopBar(_ app: XCUIApplication) -> Bool {
        let inBar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nav-' AND hasFocus == true")).firstMatch
        for _ in 0..<12 where !inBar.exists { kjPress(.up, app: app) }
        return inBar.exists
    }

    /// Presses toward `element` until it has focus, steering by where it sits against the focused
    /// control. Returns whether it got there.
    @discardableResult
    func kjFocus(_ element: XCUIElement, app: XCUIApplication, limit: Int = 40) -> Bool {
        var dead = 0   // presses in a row that moved nothing
        for _ in 0..<limit {
            if element.exists && element.hasFocus { return true }
            // Focus that will not move is a trap in the app, not a slow press: stop, so the test
            // fails in seconds and its message can say what holds focus (kjFocusKey).
            if dead >= 4 { return false }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard element.exists, focused.exists else {
                dead = kjPress(.down, app: app) ? 0 : dead + 1
                continue
            }
            let target = element.frame, here = focused.frame
            let dx = target.midX - here.midX, dy = target.midY - here.midY
            // A different row first (up or down), then along the row.
            let moved: Bool
            if abs(dy) > max(here.height, target.height) * 0.6 {
                moved = kjPress(dy > 0 ? .down : .up, app: app)
            } else {
                moved = kjPress(dx > 0 ? .right : .left, app: app)
            }
            dead = moved ? 0 : dead + 1
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
