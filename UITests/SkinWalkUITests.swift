import XCTest

/// Sets each skin and photographs the screens where the token trap shows first: the Receiver,
/// a region's channels, a receiver player, the Transmission station page and its player, and
/// Account. The Transmission screens read the month's schedule from the checkout through the
/// DEBUG-only `-kjschedulefile`, so they show real now and next without the preview password.
final class SkinWalkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let skins = ["day", "grove", "smut"]

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(upTo timeout: TimeInterval, until condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
    }

    /// The station month's schedule in this checkout: tvos/UITests/<file> -> <checkout>/data/…
    private var scheduleFile: String {
        var karachi = Calendar(identifier: .gregorian)
        karachi.timeZone = TimeZone(identifier: "Asia/Karachi")!
        let c = karachi.dateComponents([.year, .month], from: Date())
        let month = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/khajistan-tv/programming-\(month).json").path
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Presses `press` until the element is focused, up to `tries` times.
    @discardableResult
    private func focus(_ element: XCUIElement, by press: XCUIRemote.Button, tries: Int = 10) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.hasFocus { return true }
            XCUIRemote.shared.press(press)
        }
        return element.exists && element.hasFocus
    }

    private func skinState(_ app: XCUIApplication) -> String {
        (app.staticTexts["skinState"].value as? String) ?? "?"
    }

    func testEverySkinOnEveryScreen() {
        for skin in skins {
            // The Receiver, a region's channels and a player.
            var app = launch(["-kjskin", skin, "-kjtab", "receiver"])
            let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "\(skin): the receiver must draw its regions")
            let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            for _ in 0..<10 where !focusedRegion.exists { XCUIRemote.shared.press(.down) }
            shot("\(skin)-1-receiver", app)
            XCUIRemote.shared.press(.select)
            let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
            if channels.firstMatch.waitForExistence(timeout: 60) {
                let focusedChannel = channels.matching(NSPredicate(format: "hasFocus == true")).firstMatch
                for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down) }
                shot("\(skin)-2-channels", app)
                XCUIRemote.shared.press(.select)
                let state = app.staticTexts["playerState"]
                _ = state.waitForExistence(timeout: 20)
                // Past the opening flight; then a click wakes the overlay, which hides 2.6 s into play.
                Thread.sleep(forTimeInterval: 8)
                XCUIRemote.shared.press(.select)
                Thread.sleep(forTimeInterval: 0.6)
                shot("\(skin)-3-receiver-player", app)
            }
            app.terminate()

            // The station page, a channel card in focus, and the channel's player.
            app = launch(["-kjskin", skin, "-kjtab", "transmission", "-kjschedulefile", scheduleFile])
            let page = app.staticTexts["transmissionState"]
            XCTAssertTrue(page.waitForExistence(timeout: 30))
            wait(upTo: 20) { (page.value as? String) == "Ready" }
            XCTAssertEqual(page.value as? String, "Ready", "\(skin): the schedule file must load")
            let card = app.buttons["transmission-channel-1"]
            // Down from the TRANSMISSION tab lands on the card under it, channel 2.
            focus(app.buttons["transmission-channel-2"], by: .down, tries: 4)
            XCTAssertTrue(focus(card, by: .left, tries: 3), "\(skin): channel 1's card must take focus")
            shot("\(skin)-4-transmission", app)
            XCUIRemote.shared.press(.select)
            let upNext = app.descendants(matching: .any)["upNext"]
            XCTAssertTrue(upNext.waitForExistence(timeout: 20), "\(skin): the player must list what is up next")
            Thread.sleep(forTimeInterval: 10)   // the opening ground holds until the signal settles
            XCUIRemote.shared.press(.select)     // wakes the overlay, which hides 2.6 s in
            Thread.sleep(forTimeInterval: 0.6)
            shot("\(skin)-5-transmission-player", app)
            app.terminate()

            // Account, with the skin control in focus.
            app = launch(["-kjskin", skin, "-kjtab", "account"])
            let control = app.buttons["skin-\(skin)"]
            XCTAssertTrue(control.waitForExistence(timeout: 20))
            XCTAssertEqual(skinState(app), skin)
            focus(app.buttons["skin-automatic"], by: .down)
            focus(control, by: .right, tries: 4)
            shot("\(skin)-6-account", app)
            app.terminate()
        }
    }

    /// The forms, where tvOS draws part of the control itself: the preview-password step (the
    /// schedule asks for it without a schedule file), the sign-in sheet, and the atlas switch.
    func testFormsInEverySkin() {
        for skin in skins {
            var app = launch(["-kjskin", skin, "-kjtab", "transmission"])
            let page = app.staticTexts["transmissionState"]
            XCTAssertTrue(page.waitForExistence(timeout: 30))
            wait(upTo: 30) { (page.value as? String) != "Loading" }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
            shot("\(skin)-7-transmission-\((page.value as? String) ?? "unknown")", app)
            // The field is drawn by the app over a near-invisible system field; typing into it
            // must still reach the binding, which is what enables Continue.
            let proceed = app.buttons["Continue"]
            if skin == "day", (page.value as? String) == "Preview password", proceed.exists {
                XCTAssertFalse(proceed.isEnabled, "Continue waits for a password")
                XCUIRemote.shared.press(.select)
                Thread.sleep(forTimeInterval: 1.5)
                app.typeText("abc")
                XCUIRemote.shared.press(.menu)   // closes the keyboard
                Thread.sleep(forTimeInterval: 1.5)
                XCTAssertTrue(proceed.isEnabled, "typing reaches the field")
                shot("day-7b-transmission-typed", app)
            }
            app.terminate()

            app = launch(["-kjskin", skin, "-kjtab", "account"])
            let signIn = app.buttons["Sign in"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 20))
            XCTAssertTrue(focus(signIn, by: .down, tries: 3))
            XCUIRemote.shared.press(.select)
            Thread.sleep(forTimeInterval: 1.5)
            shot("\(skin)-8-sign-in", app)
            app.terminate()

            app = launch(["-kjskin", skin, "-kjtab", "receiver"])
            let toggle = app.buttons["beyondTheAtlas"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 60))
            // Down into the region strip, then left along it and off its west end to the switch.
            let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
            let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            for _ in 0..<10 where !focusedRegion.exists { XCUIRemote.shared.press(.down) }
            for _ in 0..<40 where !toggle.hasFocus { XCUIRemote.shared.press(.left) }
            XCTAssertTrue(toggle.hasFocus, "\(skin): the atlas switch must take focus")
            shot("\(skin)-9-atlas-switch-focused", app)
            app.terminate()
        }
    }

    /// The notice before a handover comes up over the picture once the overlay has hidden, and
    /// goes when the overlay is woken, so the line is never on screen twice. The lead is stretched
    /// to a day so the slot on air is always inside it.
    func testHandoverNoticeOnlyWhileTheOverlayIsHidden() {
        let app = launch(["-kjskin", "day", "-kjtab", "transmission", "-kjschedulefile", scheduleFile, "-kjhandoverlead", "86400"])
        let page = app.staticTexts["transmissionState"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        wait(upTo: 20) { (page.value as? String) == "Ready" }
        focus(app.buttons["transmission-channel-2"], by: .down, tries: 4)
        XCTAssertTrue(focus(app.buttons["transmission-channel-1"], by: .left, tries: 3))
        XCUIRemote.shared.press(.select)
        let notice = app.descendants(matching: .any)["handoverNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "the notice comes up once the overlay hides")
        Thread.sleep(forTimeInterval: 0.5)
        shot("notice-1-overlay-hidden", app)
        XCUIRemote.shared.press(.select)   // wakes the overlay
        wait(upTo: 3) { !notice.exists }
        XCTAssertFalse(notice.exists, "the notice is not shown while the overlay says the same thing")
        shot("notice-2-overlay-up", app)
    }

    /// Chooses each skin with the remote, checks it is applied at once and kept across a launch,
    /// and that Automatic hands the skin back to the hour.
    func testChoosingASkinAppliesAndPersists() {
        var app = launch(["-kjskin", "day", "-kjtab", "account"])
        XCTAssertTrue(app.buttons["skin-grove"].waitForExistence(timeout: 20))
        XCTAssertEqual(skinState(app), "day")
        XCTAssertTrue(focus(app.buttons["skin-automatic"], by: .down), "the skin control must take focus")
        for skin in ["day", "grove", "smut"] {
            XCTAssertTrue(focus(app.buttons["skin-\(skin)"], by: .right, tries: 4))
            XCUIRemote.shared.press(.select)
            wait(upTo: 3) { self.skinState(app) == skin }
            XCTAssertEqual(skinState(app), skin, "choosing \(skin) applies it at once")
        }
        shot("choose-1-smut-chosen", app)
        app.terminate()

        // No -kjskin: the choice made with the remote is what the app opens on.
        app = launch(["-kjtab", "account"])
        XCTAssertTrue(app.buttons["skin-smut"].waitForExistence(timeout: 20))
        XCTAssertEqual(skinState(app), "smut", "the choice is kept across a launch")

        XCTAssertTrue(focus(app.buttons["skin-automatic"], by: .down))
        XCUIRemote.shared.press(.select)
        let hour = Calendar.current.component(.hour, from: Date())
        let expected = (8...16).contains(hour) ? "day" : ((5...7).contains(hour) || (17...19).contains(hour) ? "smut" : "grove")
        wait(upTo: 3) { self.skinState(app) == expected }
        XCTAssertEqual(skinState(app), expected, "Automatic follows the hour (\(hour):00)")
        shot("choose-2-automatic", app)
    }
}
