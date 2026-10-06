import XCTest

/// Walks every door and the native rooms in each of the three skins, and keeps a screenshot of
/// each screen (exported from the result bundle with `xcrun xcresulttool export attachments`).
/// Rooms that read the live website or a live signal wait on the network; the assertions say
/// what has to be on screen, not only that a view mounted.
final class KhajistanUITests: XCTestCase {
    private let skins = ["day", "grove", "smut"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(skin: String, tab: String = "home", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", tab] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 30, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
    }

    /// The house bar is the app's own: no system tab bar anywhere.
    func testEveryDoorInEverySkin() {
        for skin in skins {
            let app = launch(skin: skin)
            XCTAssertEqual(app.tabBars.count, 0, "The system tab bar must not be drawn")
            waitFor(app.textFields["archiveSearch"], 10, "HOME carries the site's search")
            waitFor(app.buttons["join-monthly"], 5, "HOME carries the membership")
            shot("\(skin)-01-home", app)
            app.swipeUp()
            shot("\(skin)-02-home-doors", app)

            app.buttons["tab-receiver"].tap()
            waitFor(app.buttons["region-indus"], 40, "the region strip lists Indus")
            waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch, 40, "Indus lists its channels")
            shot("\(skin)-03-receiver", app)
            app.swipeUp()
            shot("\(skin)-04-receiver-channels", app)

            app.swipeDown(); app.swipeDown()
            app.buttons["part-transmission"].tap()
            let ready = NSPredicate { _, _ in
                app.buttons["transmission-channel-1"].exists || app.staticTexts["transmissionPreview"].exists
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 40), .completed,
                           "Transmission shows its two channels, or the preview-password step")
            shot("\(skin)-05-transmission", app)

            // Khajistan Radio's mixes play on Transmission's channel 2, not in a section of their own
            // (owner, 2026-10-06).
            XCTAssertFalse(app.buttons["part-radio"].exists, "there is no Khajistan Radio section")

            app.buttons["tab-picsVids"].tap()
            waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch, 40, "the Born Digital stream loads")
            shot("\(skin)-07-pics-vids", app)

            app.buttons["tab-yours"].tap()
            waitFor(app.buttons["skin-\(skin)"], 5, "the skin control is on the account page")
            shot("\(skin)-08-account", app)
            app.swipeUp()
            shot("\(skin)-09-account-lower", app)

            app.buttons["tab-home"].tap()
            app.buttons["destination-reading"].tap()
            waitFor(app.buttons["closeBrowser"], 10, "the house browser opens")
            let web = app.webViews.firstMatch
            let gate = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Enter the archive")).firstMatch
            let reading = web.staticTexts["Reading Room"].firstMatch
            let loaded = NSPredicate { _, _ in gate.exists || reading.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 45), .completed,
                           "The website renders its password gate or the Reading Room, not merely a mounted WebKit")
            sleep(2)
            shot("\(skin)-10-browser", app)
            app.buttons["closeBrowser"].tap()
            app.terminate()
        }
    }

    /// iPad: the rows of HOME and ACCOUNT hold to the reading column (KJLayout.readingWidth, 720)
    /// and sit centred, in portrait and in landscape, and the Receiver still draws its map and
    /// regions. iPhone: the same row spans the screen less the page margins, exactly as before,
    /// which is the case the column must never touch.
    func testRowsHoldToAColumnOnIPadAndSpanTheIPhone() {
        let app = launch(skin: "day")
        let row = app.buttons["destination-reading"]
        waitFor(row, 10, "HOME lists the Reading Room door")
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [UIDeviceOrientation] = isPad ? [.portrait, .landscapeLeft] : [.portrait]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            app.buttons["tab-home"].tap()
            waitFor(row, 10, "the door row after rotating")
            let screen = app.windows.firstMatch.frame
            let frame = row.frame
            if isPad {
                XCTAssertLessThanOrEqual(frame.width, 721, "a HOME row stays in the reading column (\(orientation.rawValue))")
                XCTAssertEqual(frame.midX, screen.midX, accuracy: 2, "the column is centred (\(orientation.rawValue))")
                shot("ipad-\(orientation.rawValue)-home", app)
                app.buttons["tab-yours"].tap()
                waitFor(app.staticTexts["Khajistan for iPad 1.0"], 5, "ACCOUNT names the device it runs on")
                shot("ipad-\(orientation.rawValue)-account", app)
                app.buttons["tab-receiver"].tap()
                waitFor(app.buttons["region-indus"], 40, "the Receiver keeps its region strip")
                shot("ipad-\(orientation.rawValue)-receiver", app)
            } else {
                XCTAssertEqual(frame.width, screen.width - 40, accuracy: 1, "on iPhone a HOME row spans the screen less its 20pt margins")
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// A tap on the map chooses the region under the finger; the strip and the list follow.
    func testMapTapChoosesARegion() {
        let app = launch(skin: "day", tab: "receiver")
        let map = app.descendants(matching: .any)["receiverMap"]
        waitFor(app.buttons["region-indus"], 40, "the map and its strip load")
        waitFor(map, 5, "the map is on screen")
        let title = app.descendants(matching: .any)["regionTitle"]
        waitFor(title, 10, "the region block is on screen")
        // The Maghreb is the map's western mass: a quarter of the way in, half way down.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55)).tap()
        let maghreb = NSPredicate(format: "label CONTAINS[c] %@", "Maghreb")
        expectation(for: maghreb, evaluatedWith: title)
        waitForExpectations(timeout: 10)
        shot("map-tap-maghreb", app)
        app.buttons["region-anatolia"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@", "Anatolia"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
    }

    /// A channel plays, and a swipe up tunes the next behind the pigeon.
    func testChannelPlaysAndSwipeChangesIt() {
        let app = launch(skin: "grove", tab: "receiver")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        waitFor(first, 40, "Indus lists its channels")
        first.tap()
        let state = app.staticTexts["playerState"]
        waitFor(state, 10, "the player opens")
        let playing = NSPredicate(format: "label == 'Playing'")
        expectation(for: playing, evaluatedWith: state)
        waitForExpectations(timeout: 60)
        shot("player-playing", app)
        let before = state.value as? String ?? ""
        XCTAssertFalse(before.isEmpty, "the player names the channel it carries")
        app.swipeUp()
        usleep(900_000)
        shot("player-channel-change", app)
        // The next channel in the list is tuned behind the wing, then plays or says why it cannot.
        let changed = NSPredicate(format: "value != %@ AND (label == 'Playing' OR label CONTAINS[c] 'could not' OR label CONTAINS[c] 'HTTP' OR label CONTAINS[c] 'not on the dial')", before)
        expectation(for: changed, evaluatedWith: state)
        waitForExpectations(timeout: 60)
        usleep(700_000)
        shot("player-after-change", app)
        app.buttons["closePlayer"].tap()
    }

    /// A Pics/Vids object opens whole, and a swipe moves to the next.
    /// App Store builds (KJ_APP_STORE, owner ruling 2026-10-06) leave Pics/Vids out: no tab, no
    /// Home door, and a stored Pics/Vids tab opens Home instead. Builds for our own devices keep
    /// both. The same test runs in both builds and asserts the opposite in each.
    func testPicsVidsIsLeftOutOfStoreBuildsOnly() {
        let app = launch(skin: "day", tab: "picsVids")
        waitFor(app.buttons["tab-home"], 10, "the house bar is drawn")
        let tab = app.buttons["tab-picsVids"]
        let door = app.buttons["destination-picsnvids"]
        let chat = app.buttons["destination-chat"]
#if KJ_APP_STORE
        XCTAssertFalse(tab.exists, "a store build has no Pics/Vids tab")
        waitFor(app.textFields["archiveSearch"], 10, "a stored Pics/Vids tab opens Home in a store build")
        for _ in 0..<8 where !chat.exists { app.swipeUp() }
        XCTAssertTrue(chat.exists, "Home scrolled past where the Pics/Vids door stood")
        XCTAssertFalse(door.exists, "a store build has no Pics/Vids door on Home")
        shot("store-build-home", app)
#else
        XCTAssertTrue(tab.exists, "builds for our own devices keep the Pics/Vids tab")
        app.buttons["tab-home"].tap()
        for _ in 0..<8 where !door.exists { app.swipeUp() }
        XCTAssertTrue(door.exists, "builds for our own devices keep the Pics/Vids door on Home")
#endif
    }

    /// The region filter reads its own feed: a region shows fewer objects than All, and All
    /// comes back to the full count. (The store pages one feed per region since 2026-10-06.)
    func testPicsVidsRegionFilter() {
        let app = launch(skin: "day", tab: "picsVids")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        waitFor(tile, 40, "the stream loads")
        if app.buttons["adultNoticeOK"].exists { app.buttons["adultNoticeOK"].tap() }
        let count = app.staticTexts["pnvCount"]
        func objects() -> Int {
            let text = count.label.filter(\.isNumber)
            return Int(text) ?? 0
        }
        let settled = { (test: @escaping (Int) -> Bool) -> Bool in
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in test(objects()) }, object: nil)], timeout: 40) == .completed
        }
        XCTAssertTrue(settled { $0 > 0 }, "All states a count")
        let all = objects()
        let region = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pnvregion-' AND identifier != 'pnvregion-all'")).firstMatch
        waitFor(region, 10, "a region filter is offered")
        region.tap()
        XCTAssertTrue(settled { $0 > 0 && $0 < all }, "a region shows fewer objects than All (\(all))")
        waitFor(tile, 40, "the region's stream draws tiles")
        shot("pnv-region", app)
        app.buttons["pnvregion-all"].tap()
        XCTAssertTrue(settled { $0 == all }, "All returns to its full count")
    }

    func testPicsVidsViewer() {
        let app = launch(skin: "day", tab: "picsVids")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        waitFor(tile, 40, "the stream loads")
        if app.buttons["adultNoticeOK"].exists { app.buttons["adultNoticeOK"].tap() }
        tile.tap()
        waitFor(app.buttons["closePlayer"], 10, "the viewer opens")
        sleep(2)
        shot("pnv-viewer", app)
        app.swipeLeft()
        sleep(2)
        shot("pnv-viewer-next", app)
        app.buttons["closePlayer"].tap()
    }

    /// The skin control: a pick takes effect and Automatic hands back to the sky.
    func testSkinControl() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "yours"]
        app.launch()
        waitFor(app.buttons["skin-grove"], 10, "the skin control is on the account page")
        app.buttons["skin-grove"].tap()
        let line = app.staticTexts["skinLine"]
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Grove, until'"), evaluatedWith: line)
        waitForExpectations(timeout: 5)
        shot("skin-picked-grove", app)
        app.buttons["skin-auto"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Following the sun'"), evaluatedWith: line)
        waitForExpectations(timeout: 5)
    }

    /// A page saved in the house browser is still on the account page after a relaunch.
    func testSavedPageSurvivesRelaunch() {
        // The receiver's web page is outside the password gate, so it can be saved by anyone; it is
        // reached through the app's own link format.
        let app = launch(skin: "day")
        app.open(URL(string: "khajistan://open?url=https%3A%2F%2Fkhajistan-archive.pages.dev%2Fopen-frequencies")!)
        let save = app.buttons["Save page"]
        let remove = app.buttons["Remove saved page"]
        let canSave = NSPredicate { _, _ in save.exists || remove.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: canSave, object: nil)], timeout: 45), .completed)
        if remove.exists { remove.tap() }
        waitFor(save, 5, "the page can be saved")
        save.tap()
        waitFor(remove, 5, "the page is saved")
        app.buttons["closeBrowser"].tap()
        app.terminate()
        let again = launch(skin: "day", tab: "yours")
        again.swipeUp()
        for _ in 0..<6 where !again.buttons["saved-/open-frequencies"].isHittable { again.swipeUp() }
        waitFor(again.buttons["saved-/open-frequencies"], 10, "the saved page survives relaunch")
        shot("saved-page", again)
    }
}
