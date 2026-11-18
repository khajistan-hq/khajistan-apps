import XCTest

/// Up reaches the top bar from the Receiver front: from Surf, from the region list and from a
/// shelf below the front (owner, 2026-11-18: "no way to go to the nav when i touch the top on the
/// appletv remote").
final class TopNavReachUITests: XCTestCase {
    private func focusedId(_ app: XCUIApplication) -> String {
        let f = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return f.exists ? (f.identifier.isEmpty ? "<\(f.label)>" : f.identifier) : "none"
    }

    /// Presses Up until a top-bar tab holds focus, or `limit` presses; returns the trail.
    private func upToNav(_ app: XCUIApplication, limit: Int) -> (Bool, [String]) {
        let nav = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nav-' AND hasFocus == true")).firstMatch
        var trail = [focusedId(app)]
        for _ in 0..<limit {
            if nav.exists { return (true, trail) }
            XCUIRemote.shared.press(.up)
            kjPause(0.6)
            trail.append(focusedId(app))
        }
        return (nav.exists, trail)
    }

    func testUpReachesTheNavFromTheFront() {
        let app = XCUIApplication()
        kjLaunch(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'")).firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        XCTAssertTrue(kjFocusFrontFoot(app), "focus starts on the front, off the top bar")
        // The switch keeps focus when it is turned, though the map it governs is drawn again.
        XCUIRemote.shared.press(.select)
        kjPause(2)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].hasFocus, "the switch keeps focus when turned on")
        XCUIRemote.shared.press(.select)
        kjPause(2)
        XCTAssertTrue(app.buttons["beyondTheAtlas"].hasFocus, "and when turned off")
        let (fromSurf, trail1) = upToNav(app, limit: 6)
        print("TOPNAV from surf:", trail1)
        XCTAssertTrue(fromSurf, "Up from Surf reaches the top bar: \(trail1)")
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertTrue(kjFocusRegions(app))
        let (fromList, trail2) = upToNav(app, limit: 16)
        print("TOPNAV from list:", trail2)
        XCTAssertTrue(fromList, "Up from the region list reaches the top bar: \(trail2)")
        // Down into the shelves below the front, then back up.
        XCTAssertTrue(kjFocusFrontFoot(app))
        for _ in 0..<3 { XCUIRemote.shared.press(.down); kjPause(0.6) }
        let (fromShelf, trail3) = upToNav(app, limit: 10)
        print("TOPNAV from shelf:", trail3)
        XCTAssertTrue(fromShelf, "Up from a shelf reaches the top bar: \(trail3)")
        // Up from the shelves enters the front at Surf, never walking the A–Z list (owner,
        // 2026-11-18: twelve rows of it read as Up going nowhere).
        XCTAssertFalse(trail3.contains { $0.hasPrefix("region-") }, "Up does not walk the A–Z list: \(trail3)")
        XCTAssertEqual(trail3.dropLast().last, "shuffle", "the press before the top bar is on Surf: \(trail3)")
    }

    /// From the right-hand end of the first shelf, below the A–Z list: Up still enters the front at
    /// Surf. Before, it climbed into the list at Turkistan and walked all twelve rows.
    func testUpFromTheRightOfTheShelvesSkipsTheList() {
        let app = XCUIApplication()
        kjLaunch(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'")).firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        XCTAssertTrue(kjFocusFrontFoot(app))
        XCUIRemote.shared.press(.down)
        kjPause(0.8)
        for _ in 0..<12 { XCUIRemote.shared.press(.right); kjPause(0.4) }
        let start = focusedId(app)
        XCTAssertFalse(start.hasPrefix("nav-") || start == "beyondTheAtlas", "focus is on a shelf: \(start)")
        let (ok, trail) = upToNav(app, limit: 8)
        print("TOPNAV from the right of the shelves:", trail)
        XCTAssertTrue(ok, "Up reaches the top bar: \(trail)")
        XCTAssertFalse(trail.contains { $0.hasPrefix("region-") }, "Up does not walk the A–Z list: \(trail)")
        XCTAssertEqual(trail.dropLast().last, "shuffle", "the press before the top bar is on Surf: \(trail)")
    }

    /// Each section: open it from the bar, go Down into its page, and come back Up to the bar.
    func testUpReachesTheNavFromEverySection() {
        let app = XCUIApplication()
        kjLaunch(app)
        XCTAssertTrue(app.buttons["nav-receiver"].waitForExistence(timeout: 60))
        kjPause(3)
        for id in ["nav-transmission", "nav-rooms", "nav-account"] {
            let (ok0, t0) = upToNav(app, limit: 12)
            XCTAssertTrue(ok0, "reach the bar before \(id): \(t0)")
            let tab = app.buttons[id]
            guard tab.exists else { print("TOPNAV no tab", id); continue }
            for _ in 0..<8 where !tab.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.4) }
            for _ in 0..<8 where !tab.hasFocus { XCUIRemote.shared.press(.left); kjPause(0.4) }
            XCUIRemote.shared.press(.select)
            kjPause(4)
            var down = [focusedId(app)]
            for _ in 0..<4 { XCUIRemote.shared.press(.down); kjPause(0.7); down.append(focusedId(app)) }
            XCTAssertFalse(down.last!.hasPrefix("nav-"), "Down has left the top bar on \(id): \(down)")
            let (ok, trail) = upToNav(app, limit: 12)
            print("TOPNAV \(id) down:", down, "up:", trail)
            XCTAssertTrue(ok, "Up from \(id)'s page reaches the top bar: \(trail)")
            XCTAssertTrue(tab.hasFocus, "Up lands on the section on screen, \(id): \(trail)")
        }
    }

    /// The Screening Room with films and an Up Next shelf (the owner's screen, 2026-11-18): Up from
    /// a poster in the first shelf reaches the top bar.
    func testUpReachesTheNavFromTheScreeningRoomShelves() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin, "-kj.filmPlaces",
                               "<dict><key>filmfarsi-trailers-vol-1-khajistan</key><real>600</real><key>filmfarsi-trailers-vol-2-khajistan</key><real>600</real></dict>"]
        kjLaunch(app)
        XCTAssertTrue(app.buttons["nav-rooms"].waitForExistence(timeout: 60))
        kjPause(2)
        _ = upToNav(app, limit: 4)
        let tab = app.buttons["nav-rooms"]
        for _ in 0..<8 where !tab.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.4) }
        XCUIRemote.shared.press(.select)
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-' OR identifier BEGINSWITH 'upnext-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        kjPause(2)
        XCUIRemote.shared.press(.down)
        kjPause(0.8)
        // Right still walks the first shelf: its Up handler takes Up only.
        let firstCard = focusedId(app)
        XCTAssertTrue(firstCard.hasPrefix("upnext-"), "Down lands on Up Next: \(firstCard)")
        // Down may land on either card: walk to the left end, then Right must move and Left return.
        for _ in 0..<3 { XCUIRemote.shared.press(.left); kjPause(0.5) }
        let leftEnd = focusedId(app)
        XCTAssertTrue(leftEnd.hasPrefix("upnext-"), "Left stays on Up Next: \(leftEnd)")
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        let second = focusedId(app)
        XCTAssertTrue(second.hasPrefix("upnext-") && second != leftEnd, "Right moves along Up Next: \(leftEnd) → \(second)")
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertEqual(focusedId(app), leftEnd, "Left moves back")
        let (ok, trail) = upToNav(app, limit: 6)
        print("TOPNAV rooms first shelf up:", trail)
        XCTAssertTrue(ok, "Up from the first shelf reaches the top bar: \(trail)")
        XCTAssertTrue(tab.hasFocus, "Up lands on Screening Room, the section on screen: \(trail)")
        for _ in 0..<3 { XCUIRemote.shared.press(.down); kjPause(0.7) }
        let (ok2, trail2) = upToNav(app, limit: 10)
        print("TOPNAV rooms deeper shelf up:", trail2)
        XCTAssertTrue(ok2, "Up from a deeper shelf reaches the top bar: \(trail2)")
    }
}
