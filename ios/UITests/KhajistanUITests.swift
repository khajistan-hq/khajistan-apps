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

    /// `-kjstorefront USA` stands in for the App Store storefront the simulator does not have; a
    /// test of another storefront passes its own in `extra`, which comes later and wins.
    private func launch(skin: String, tab: String = "home", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", tab, "-kjstorefront", "USA"] + extra
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

    /// The app draws no membership card on HOME or ACCOUNT, on any storefront (owner, 2026-10-07):
    /// the offer is the Reading Room page's own.
    func testNoMembershipCardOutsideTheReadingRoom() {
        for code in ["USA", "GBR"] {
            let app = launch(skin: "day", extra: ["-kjstorefront", code])
            waitFor(app.buttons["destination-reading"], 10, "HOME still lists its doors (\(code))")
            XCTAssertFalse(app.buttons["join-monthly"].exists, "no membership card on HOME (\(code))")
            app.buttons["tab-yours"].tap()
            waitFor(app.buttons["skin-day"], 10, "ACCOUNT loads (\(code))")
            XCTAssertFalse(app.buttons["join-monthly"].exists || app.buttons["join-annual"].exists,
                           "no membership card on ACCOUNT (\(code))")
            app.terminate()
        }
    }

    /// A tap on the map chooses the region under the finger; the strip and the list follow.
    func testMapTapChoosesARegion() {
        let app = launch(skin: "day", tab: "receiver")
        let map = app.descendants(matching: .any)["receiverMap"]
        waitFor(app.buttons["region-indus"], 40, "the map and its strip load")
        waitFor(map, 5, "the map is on screen")
        let title = app.descendants(matching: .any)["regionTitle"]
        waitFor(title, 10, "the region block is on screen")
        // The Maghreb is the map's western mass. Its label sits a quarter of the way across and just
        // under half way down, at the same place on every screen because the map is drawn from one
        // viewBox: the middle of the shape, not near an edge of it. The tap is placed on the map
        // element's own frame, so it follows the map to any screen size.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.48)).tap()
        let maghreb = NSPredicate(format: "label CONTAINS[c] %@", "Maghreb")
        expectation(for: maghreb, evaluatedWith: title)
        waitForExpectations(timeout: 10)
        shot("map-tap-maghreb", app)
        app.buttons["region-anatolia"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@", "Anatolia"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
    }

    /// A channel plays in the screen docked at the top of the Receiver and goes full screen only
    /// when full screen is chosen (owner, 2026-10-08). Next tunes the next channel behind the
    /// pigeon; closing full screen leaves the same channel playing; off turns the receiver off.
    func testChannelPlaysDockedAndFullScreenOnlyWhenChosen() {
        let app = launch(skin: "grove", tab: "receiver")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        waitFor(first, 40, "Indus lists its channels")
        first.tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 10, "the docked screen opens")
        XCTAssertFalse(app.buttons["closePlayer"].exists, "a channel does not open full screen by itself")
        XCTAssertTrue(app.buttons["tab-receiver"].isHittable, "the tab bar stays on screen")
        let playing = NSPredicate(format: "label == 'Playing'")
        expectation(for: playing, evaluatedWith: state)
        waitForExpectations(timeout: 60)
        shot("player-playing", app)
        let before = state.value as? String ?? ""
        XCTAssertFalse(before.isEmpty, "the screen names the channel it carries")
        app.buttons["nextChannel"].tap()
        usleep(900_000)
        shot("player-channel-change", app)
        // The next channel in the list is tuned behind the wing, then plays or says why it cannot.
        let changed = NSPredicate(format: "value != %@ AND (label == 'Playing' OR label CONTAINS[c] 'could not' OR label CONTAINS[c] 'HTTP' OR label CONTAINS[c] 'not on the dial')", before)
        expectation(for: changed, evaluatedWith: state)
        waitForExpectations(timeout: 60)
        usleep(700_000)
        shot("player-after-change", app)
        let tuned = state.value as? String ?? ""

        app.buttons["fullScreen"].tap()
        let full = app.staticTexts["playerState"]
        waitFor(full, 10, "full screen opens when chosen")
        XCTAssertEqual(full.value as? String, tuned, "full screen carries the same channel, not a new tuning")
        shot("player-full-screen", app)
        // The controls hide 2.6 s into playback; a tap wakes them. On a slow runner they can hide
        // again before the next step, so wake and tap together, a few times if need be.
        let close = app.buttons["closePlayer"]
        for _ in 0..<4 where close.exists {
            if !close.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap() }
            if close.isHittable { close.tap() }
            _ = close.waitForNonExistence(timeout: 3)
        }
        // The docked screen stays in the hierarchy under the cover, so wait for the cover to go.
        XCTAssertFalse(close.exists, "full screen closes")
        XCTAssertTrue(app.buttons["receiverOff"].isHittable, "the docked screen is back on top")
        XCTAssertEqual(state.value as? String, tuned, "the channel is still tuned after full screen closes")

        app.buttons["receiverOff"].tap()
        XCTAssertTrue(state.waitForNonExistence(timeout: 5), "off turns the receiver off")
    }

    /// A Pics/Vids object opens whole, and a swipe moves to the next.
    /// App Store builds (KJ_APP_STORE, owner rulings 2026-10-06) leave Pics/Vids, Chat and the Wall
    /// out: no Pics/Vids tab, none of their doors on Home, and a stored Pics/Vids tab opens Home
    /// instead. Builds for our own devices keep all of them. The same test runs in both builds and asserts the
    /// opposite in each.
    func testPicsVidsChatAndWallAreLeftOutOfStoreBuildsOnly() {
        let app = launch(skin: "day", tab: "picsVids")
        waitFor(app.buttons["tab-home"], 10, "the house bar is drawn")
        let tab = app.buttons["tab-picsVids"]
        let pnvDoor = app.buttons["destination-picsnvids"]
        let chatDoor = app.buttons["destination-chat"]
        let wallDoor = app.buttons["destination-wall"]
        // The first BAZAAR door follows WALL in the menu in every build: reaching it means the
        // three doors above it were passed.
        let marker = app.buttons["destination-toshakhana"]
#if KJ_APP_STORE
        XCTAssertFalse(tab.exists, "a store build has no Pics/Vids tab")
        waitFor(app.textFields["archiveSearch"], 10, "a stored Pics/Vids tab opens Home in a store build")
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        XCTAssertTrue(marker.exists, "Home scrolled past where the Pics/Vids, Chat and Wall doors stood")
        XCTAssertFalse(pnvDoor.exists, "a store build has no Pics/Vids door on Home")
        XCTAssertFalse(chatDoor.exists, "a store build has no Chat door on Home")
        XCTAssertFalse(wallDoor.exists, "a store build has no Wall door on Home")
        shot("store-build-home", app)
#else
        XCTAssertTrue(tab.exists, "builds for our own devices keep the Pics/Vids tab")
        app.buttons["tab-home"].tap()
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        // Pics/Vids is reached from its tab; Home no longer repeats it as a door (one control once,
        // owner 2026-10-07). Chat and the Wall are not tabs and keep their doors.
        XCTAssertFalse(pnvDoor.exists, "Home does not repeat a tab as a door")
        XCTAssertFalse(app.buttons["destination-receiver"].exists, "nor the Receiver")
        XCTAssertTrue(chatDoor.exists, "builds for our own devices keep the Chat door on Home")
        XCTAssertTrue(wallDoor.exists, "builds for our own devices keep the Wall door on Home")
#endif
    }

    /// Chat (own builds only; App Store builds leave it out): HOME's Chat door opens the rooms,
    /// a room shows its lines or says there are none, a signed-out reader is told to sign in to
    /// write, and back and close return to HOME. Reads the live site's rooms.
    func testChatOpensFromHomeAndShowsARoom() throws {
#if KJ_APP_STORE
        throw XCTSkip("App Store builds leave chat out")
#else
        let app = launch(skin: "grove")
        let door = app.buttons["destination-chat"]
        for _ in 0..<8 where !door.exists { app.swipeUp() }
        door.tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chat-room-'")).firstMatch
        waitFor(room, 30, "the rooms load")
        shot("chat-rooms", app)
        room.tap()
        waitFor(app.staticTexts["chatRoomName"], 10, "the room opens")
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'chat-line-'")).firstMatch
        let none = app.staticTexts["No lines in the last 48 hours."]
        let shown = NSPredicate { _, _ in line.exists || none.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 20), .completed,
                       "the room shows its lines or says it has none")
        XCTAssertTrue(app.staticTexts["Sign in under Account to write in a room."].exists, "a signed-out reader is told how to write")
        shot("chat-room", app)
        app.buttons["chatBack"].tap()
        waitFor(room, 10, "back returns to the rooms")
        app.buttons["closePlayer"].tap()
        waitFor(app.buttons["tab-home"], 10, "closing chat returns to the app")
#endif
    }

    /// The region filter reads its own feed: a region shows fewer objects than All, and All
    /// comes back to the full count. (The store pages one feed per region since 2026-10-06.)
    func testPicsVidsRegionFilter() {
        let app = launch(skin: "day", tab: "picsVids")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        waitFor(tile, 40, "the stream loads")
        let notice = app.buttons["adultNoticeOK"]
        if notice.exists {
            notice.tap()
            // A tap while the notice is still leaving lands on it, not on the tile under it.
            XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "the notice goes")
        }
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
        let notice = app.buttons["adultNoticeOK"]
        if notice.exists {
            notice.tap()
            // A tap while the notice is still leaving lands on it, not on the tile under it.
            XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "the notice goes")
        }
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
