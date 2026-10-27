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
        // The app plays a channel when it opens on the Receiver; the tests that drive the
        // receiver start it quiet so a launch pick cannot race their own. `extra` can turn it on.
        app.launchArguments = ["-kjskin", skin, "-kjtab", tab, "-kjstorefront", "USA", "-kjautoplay", "NO"] + extra
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

    /// An active dock occupies the top of the screen. The lazy channel rows only enter the
    /// accessibility tree after the reader scrolls the catalogue past the map.
    private func firstReceiverChannel(_ app: XCUIApplication) -> XCUIElement {
        let catalogue = app.scrollViews["receiverCatalogue"]
        waitFor(catalogue, 10, "Receiver exposes its scrollable catalogue")
        waitFor(app.buttons["region-indus"], 40, "The region strip lists Indus")
        let channel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        for _ in 0..<8 {
            if channel.exists && channel.isHittable { return channel }
            catalogue.swipeUp()
        }
        waitFor(channel, 40, "Indus lists its channels after scrolling past the map")
        XCTAssertTrue(channel.isHittable, "A listed channel can be selected with one tap")
        return channel
    }

    /// The house bar is the app's own: no system tab bar anywhere.
    func testEveryDoorInEverySkin() {
        for skin in skins {
            let app = launch(skin: skin)
            XCTAssertEqual(app.tabBars.count, 0, "The system tab bar must not be drawn")
            waitFor(app.buttons["homeAllRooms"], 10, "HOME leads to every room")
            shot("\(skin)-01-home", app)
            app.buttons["tab-rooms"].tap()
            waitFor(app.buttons["destination-reading"], 10, "ROOMS lists the website's menu")
            shot("\(skin)-02-rooms", app)

            app.buttons["tab-receiver"].tap()
            _ = firstReceiverChannel(app)
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

            app.buttons["tab-rooms"].tap()
            app.buttons["destination-picsnvids"].tap()
            waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch, 40, "the Born Digital stream loads")
            shot("\(skin)-07-pics-vids", app)
            app.buttons["stackBack"].tap()
            waitFor(app.buttons["destination-reading"], 5, "Back returns to the rooms")

            app.buttons["tab-search"].tap()
            waitFor(app.textFields["archiveSearch"], 5, "SEARCH carries the field")
            shot("\(skin)-06-search", app)

            app.buttons["tab-library"].tap()
            waitFor(app.buttons["skin-\(skin)"], 5, "the skin control is on the account page")
            shot("\(skin)-08-account", app)
            app.swipeUp()
            shot("\(skin)-09-account-lower", app)

            app.buttons["tab-rooms"].tap()
            app.buttons["destination-publications"].tap()
            waitFor(app.buttons["closeBrowser"], 10, "the house browser opens")
            let web = app.webViews.firstMatch
            let gate = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Enter the archive")).firstMatch
            let page = web.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Publications")).firstMatch
            let loaded = NSPredicate { _, _ in gate.exists || page.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 45), .completed,
                           "The website renders its password gate or Publications, not merely a mounted WebKit")
            sleep(2)
            shot("\(skin)-10-browser", app)
            app.buttons["closeBrowser"].tap()
            app.terminate()
        }
    }

    /// iPad: ROOMS keeps its list as a sidebar beside the open room, LIBRARY holds to the reading
    /// column, in portrait and in landscape, and the Receiver still draws its map and regions.
    /// iPhone: a ROOMS row spans the screen less the page margins.
    func testRowsHoldToAColumnOnIPadAndSpanTheIPhone() {
        let app = launch(skin: "day", tab: "rooms")
        let row = app.buttons["destination-reading"]
        waitFor(row, 10, "HOME lists the Reading Room door")
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [UIDeviceOrientation] = isPad ? [.portrait, .landscapeLeft] : [.portrait]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            app.buttons["tab-rooms"].tap()
            waitFor(row, 10, "the door row after rotating")
            let screen = app.windows.firstMatch.frame
            let frame = row.frame
            if isPad {
                XCTAssertLessThanOrEqual(frame.maxX, 321, "ROOMS is a sidebar on iPad (\(orientation.rawValue))")
                shot("ipad-\(orientation.rawValue)-rooms", app)
                app.buttons["tab-library"].tap()
                waitFor(app.staticTexts["Khajistan for iPad 1.0"], 5, "ACCOUNT names the device it runs on")
                shot("ipad-\(orientation.rawValue)-account", app)
                app.buttons["tab-receiver"].tap()
                waitFor(app.buttons["region-indus"], 40, "the Receiver keeps its region strip")
                shot("ipad-\(orientation.rawValue)-receiver", app)
            } else {
                XCTAssertEqual(frame.width, screen.width - 40, accuracy: 1, "on iPhone a ROOMS row spans the screen less its 20pt margins")
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// The app draws no membership card on HOME or ACCOUNT, on any storefront (owner, 2026-10-07):
    /// the offer is the Reading Room page's own.
    func testNoMembershipCardOutsideTheReadingRoom() {
        for code in ["USA", "GBR"] {
            let app = launch(skin: "day", extra: ["-kjstorefront", code])
            waitFor(app.buttons["homeAllRooms"], 10, "HOME loads (\(code))")
            XCTAssertFalse(app.buttons["join-monthly"].exists, "no membership card on HOME (\(code))")
            app.buttons["tab-library"].tap()
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
        // The receiver set sits above the map when it is off, so the map can start below the
        // screen: bring it fully into view before tapping on it.
        let window = app.windows.firstMatch.frame
        for _ in 0..<4 where map.frame.maxY > window.maxY - 60 || map.frame.minY < window.minY {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            usleep(600_000)
        }
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

    /// The app opens on the Receiver with a channel already tuning on the set, before anything
    /// is touched (Pluto TV's lesson). A live signal may fail; the set must at least be on.
    func testAppOpensWithAChannelOn() {
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjautoplay", "YES"])
        let state = app.staticTexts["screenState"]
        waitFor(state, 40, "a channel is on the set at launch, untouched")
        let on = NSPredicate(format: "label != 'Standing by'")
        expectation(for: on, evaluatedWith: state)
        waitForExpectations(timeout: 30)
        shot("opens-with-a-channel-on", app)
    }

    /// A channel plays on the receiver set at the top of the Receiver and goes full screen only
    /// when full screen is chosen (owner, 2026-10-08). Next tunes the next channel behind the
    /// pigeon; closing full screen leaves the same channel playing; power puts it on standby.
    func testChannelPlaysDockedAndFullScreenOnlyWhenChosen() {
        // The full-screen controls stay up (-kjcontrolsstay, debug only): on the iOS 26 runner the
        // close button never reports a hit point, so it is tapped by its frame, and a hide racing
        // the tap would turn that tap into a wake.
        let app = launch(skin: "grove", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES"])
        let first = firstReceiverChannel(app)
        first.tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 10, "the receiver is on the page")
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
        let close = app.buttons["closePlayer"]
        waitFor(close, 10, "full screen opens when chosen")
        XCTAssertEqual(full.value as? String, tuned, "full screen carries the same channel, not a new tuning")
        shot("player-full-screen", app)
        let frame = close.frame
        XCTAssertFalse(frame.isEmpty, "the close button has a frame")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        // The set stays in the hierarchy under the cover; full screen is closed once its own power
        // key can be reached again.
        let off = app.buttons["receiverOff"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: off)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(state.value as? String, tuned, "the channel is still tuned after full screen closes")

        app.buttons["receiverOff"].tap()
        expectation(for: NSPredicate(format: "label == 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        shot("player-off", app)
    }

    /// Real controls receive one tap each: connecting Pause cancels tuning; Stop survives tab navigation.
    func testReceiverAutoplaysAndOneTapStopStaysOff() {
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES"])
        let pause = app.buttons["screenPlayPause"]
        waitFor(pause, 60, "Opening Receiver chooses a live signal without a channel tap")
        XCTAssertFalse(app.buttons["closePlayer"].exists)
        pause.tap()
        let state = app.staticTexts["screenState"]
        expectation(for: NSPredicate(format: "label == 'Paused'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        app.buttons["receiverOff"].tap()
        expectation(for: NSPredicate(format: "label == 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        // Tap near a tab cell's edge, away from its text; the whole cell must work.
        app.buttons["tab-home"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        waitFor(app.buttons["homeAllRooms"], 5, "One edge tap selects Home")
        app.buttons["tab-receiver"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitFor(state, 5, "One edge tap selects Receiver")
        XCTAssertEqual(state.label, "Standing by", "Navigation does not undo an explicit Stop")
    }

    func testLeavingDuringAutomaticSelectionCancelsAndReopeningRetries() {
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES", "-kjopeningdelayms", "5000"])
        waitFor(app.buttons["tab-home"], 3, "The tab bar appears before the deliberately suspended selection")
        app.buttons["tab-home"].tap()
        waitFor(app.buttons["homeAllRooms"], 3, "Home opens with one tap")
        sleep(6)
        app.buttons["tab-receiver"].tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 2, "Receiver reopens")
        XCTAssertEqual(state.label, "Standing by", "Leaving canceled the first selection; nothing started under Home")
        waitFor(app.buttons["screenPlayPause"], 60, "Canceled opening can retry when Receiver opens again")
        app.buttons["receiverOff"].tap()
        XCTAssertEqual(state.label, "Standing by")
    }

    /// A signed-out viewer receives a visible reason on the first CC tap; this never spends allowance.
    func testReceiverCCRespondsInDockAndFullScreen() {
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES"])
        let cc = app.buttons["receiverCC"]
        waitFor(cc, 60, "A live signal exposes CC")
        cc.tap()
        waitFor(app.staticTexts["receiverCaptionStatus"], 5, "One CC tap explains sign-in")
        XCTAssertEqual(app.staticTexts["receiverCaptionStatus"].label, "Sign in under Account to use live captions.")
        app.buttons["fullScreen"].tap()
        waitFor(app.buttons["closePlayer"], 5, "One fullscreen tap opens the player")
        app.buttons["receiverCC"].tap()
        waitFor(app.staticTexts["receiverCaptionStatus"], 5, "Fullscreen CC also responds to one tap")
        XCTAssertEqual(app.staticTexts["receiverCaptionStatus"].label, "Sign in under Account to use live captions.")
        app.buttons["closePlayer"].tap()
        waitFor(app.buttons["receiverOff"], 5, "One Close tap returns to the dock")
    }

    /// App Store builds (KJ_APP_STORE, owner rulings 2026-10-06) leave Pics/Vids, Chat and the Wall
    /// out: none of their doors in ROOMS or on HOME, and a stored Pics/Vids launch opens ROOMS
    /// without it. Builds for our own devices keep all of them. The same test runs in both builds and
    /// asserts the opposite in each.
    func testPicsVidsChatAndWallAreLeftOutOfStoreBuildsOnly() {
        let app = launch(skin: "day", tab: "picsVids")
        waitFor(app.buttons["tab-home"], 10, "the house bar is drawn")
        XCTAssertFalse(app.buttons["tab-picsVids"].exists, "Pics/Vids is a room, not a bar door")
        let pnvDoor = app.buttons["destination-picsnvids"]
        let chatDoor = app.buttons["destination-chat"]
        let wallDoor = app.buttons["destination-wall"]
        // The first BAZAAR door follows WALL in the menu in every build: reaching it means the
        // three doors above it were passed.
        let marker = app.buttons["destination-toshakhana"]
#if KJ_APP_STORE
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch.waitForExistence(timeout: 5),
                       "a stored Pics/Vids launch does not open the stream in a store build")
        app.buttons["tab-rooms"].tap()
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        XCTAssertTrue(marker.exists, "ROOMS scrolled past where the Pics/Vids, Chat and Wall doors stood")
        XCTAssertFalse(pnvDoor.exists, "a store build has no Pics/Vids door")
        XCTAssertFalse(chatDoor.exists, "a store build has no Chat door")
        XCTAssertFalse(wallDoor.exists, "a store build has no Wall door")
        shot("store-build-rooms", app)
#else
        waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch, 40, "a Pics/Vids launch opens the stream in ROOMS")
        app.buttons["stackBack"].tap()
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        XCTAssertTrue(pnvDoor.exists, "builds for our own devices keep the Pics/Vids room")
        XCTAssertFalse(app.buttons["destination-receiver"].exists, "ROOMS does not repeat a bar door")
        XCTAssertTrue(chatDoor.exists, "builds for our own devices keep the Chat door")
        XCTAssertTrue(wallDoor.exists, "builds for our own devices keep the Wall door")
#endif
    }

    /// Chat (own builds only; App Store builds leave it out): ROOMS' Chat door opens the rooms,
    /// a room shows its lines or says there are none, a signed-out reader is told to sign in to
    /// write, and back and close return to HOME. Reads the live site's rooms.
    func testChatOpensFromHomeAndShowsARoom() throws {
#if KJ_APP_STORE
        throw XCTSkip("App Store builds leave chat out")
#else
        let app = launch(skin: "grove", tab: "rooms")
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

    /// A Pics/Vids object opens whole, and a swipe moves to the next.
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
        let again = launch(skin: "day", tab: "library")
        again.swipeUp()
        for _ in 0..<6 where !again.buttons["saved-/open-frequencies"].isHittable { again.swipeUp() }
        waitFor(again.buttons["saved-/open-frequencies"], 10, "the saved page survives relaunch")
        shot("saved-page", again)
    }

    /// The Reading Room on the phone: a free title opens, its first issue reads page by page,
    /// and the place is kept; a members' title stops at the website's preview, two pages, and
    /// never shows the third. Reads the live shelf and page server.
    func testReadingRoomReadsAFreeTitleAndStopsAMembersTitleAtThePreview() {
        let app = launch(skin: "day", extra: ["-kjroom", "reading", "-kjtestsignedout", "YES"])
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-title-'"))
        waitFor(titles.firstMatch, 60, "the shelf loads")
        shot("rr-shelf", app)

        let free = titles.matching(NSPredicate(format: "label CONTAINS[c] 'read in full'")).firstMatch
        waitFor(free, 30, "a free title is on the shelf")
        free.tap()
        waitFor(app.staticTexts["rrTitleSummary"], 20, "the title opens")
        let issue = app.buttons["rr-issue-0"]
        waitFor(issue, 10, "the title lists its issues")
        shot("rr-title", app)
        issue.tap()
        let label = app.staticTexts["rrPageLabel"]
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "page 1 is on screen")
        XCTAssertTrue(label.label.hasPrefix("p. 1 / "), "the band says page 1 (\(label.label))")
        shot("rr-reader-p1", app)
        app.buttons["rrNext"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'p. 2 / '"), evaluatedWith: label)
        waitForExpectations(timeout: 10)
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "page 2 is on screen")
        app.buttons["rrReaderClose"].tap()
        waitFor(app.buttons["rrContinue"], 10, "the title offers to continue where reading stopped")
        app.buttons["stackBack"].tap()

        let members = titles.matching(NSPredicate(format: "label CONTAINS[c] 'members'")).firstMatch
        waitFor(members, 30, "a members' title is on the shelf")
        members.tap()
        waitFor(app.buttons["rr-issue-0"], 20, "the members' title lists its issues")
        app.buttons["rr-issue-0"].tap()
        waitFor(label, 45, "the reader opens")
        let gate = app.descendants(matching: .any)["rrGate"]
        for _ in 0..<3 where !gate.exists {
            let next = app.buttons["rrNext"]
            if next.isEnabled { next.tap() }
            _ = gate.waitForExistence(timeout: 15)
        }
        XCTAssertTrue(gate.exists, "a signed-out reader meets the gate inside a members' issue")
        XCTAssertTrue(label.label.hasPrefix("Preview \u{2014} "), "the band names the preview (\(label.label))")
        XCTAssertFalse(app.buttons["rrNext"].isEnabled, "nothing past the gate can be turned to")
        XCTAssertFalse(app.descendants(matching: .any)["rrReaderPage"].exists, "no page image stands behind the gate")
        shot("rr-members-gate", app)
    }

    /// Madrassa, the databases and the Bazaar read the site's own files. The live site holds them
    /// behind its password until launch, so without one the rooms say so and point to Library.
    /// With `TEST_RUNNER_KJ_SITE` set to a local checkout (scripts/dev_server.py), the test walks the
    /// real records: an entry, an essay, the dictionary, the censor certificates, and a product into
    /// the bag. It stops before checkout: nothing is sent to the shop's checkout.
    func testMadrassaDatabasesAndBazaarReadTheSiteData() {
        guard let site = ProcessInfo.processInfo.environment["KJ_SITE"] else {
            let app = launch(skin: "day", extra: ["-kjroom", "madrassa"])
            waitFor(app.descendants(matching: .any)["roomLocked"], 30, "a gated room says it is behind the password")
            app.buttons["lockedToLibrary"].tap()
            waitFor(app.buttons["skin-day"], 10, "the note leads to Library")
            return
        }
        let app = launch(skin: "smut", extra: ["-kjroom", "madrassa", "-kjsite", site])
        waitFor(app.buttons["entry-omar-ali-khan"], 30, "the page's own entries are read")
        shot("madrassa-reference", app)
        app.buttons["entry-omar-ali-khan"].tap()
        waitFor(app.buttons["entryFull"], 10, "an entry opens with its full page one step away")
        app.buttons["stackBack"].tap()

        app.buttons["madrassa-forensics"].tap()
        let post = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'post-'")).firstMatch
        waitFor(post, 20, "the forensics pieces are listed")
        post.tap()
        waitFor(app.buttons["postOnWebsite"], 10, "an essay opens whole, with its page one step away")
        shot("madrassa-essay", app)
        app.buttons["stackBack"].tap()

        app.buttons["madrassa-dictionary"].tap()
        let count = app.staticTexts["lughatCount"]
        waitFor(count, 20, "the dictionary loads")
        XCTAssertTrue(count.label.hasSuffix("of 829 entries"), "every entry is counted (\(count.label))")

        app.buttons["madrassa-databases"].tap()
        app.buttons["db-censorCertificates"].tap()
        let records = app.staticTexts["dbCount"]
        expectation(for: NSPredicate(format: "label == '52 of 52 records'"), evaluatedWith: records)
        waitForExpectations(timeout: 30)
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'record-'")).firstMatch
        record.tap()
        waitFor(app.buttons["recordLink"], 10, "a certificate links to its scan")
        shot("database-record", app)
        app.buttons["recordLink"].tap()
        let pageLabel = app.staticTexts["rrPageLabel"]
        waitFor(pageLabel, 45, "the scan opens in the app's own reader, not the website")
        XCTAssertTrue(pageLabel.label.hasPrefix("p. 1 / "), "on the page the link names (\(pageLabel.label))")
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "the certificate's page is on screen")
        shot("censor-scan", app)
        app.terminate()

        let shop = launch(skin: "day", extra: ["-kjroom", "bazaar", "-kjsite", site])
        let total = shop.staticTexts["bazaarCount"]
        waitFor(total, 30, "the Bazaar loads")
        XCTAssertEqual(total.label, "1,335 of 1,335", "the shelf the site's own code builds")
        let search = shop.textFields["bazaarSearch"]
        search.tap()
        search.typeText("Adam Khor")
        let product = shop.buttons["product-adam-khor-man-eater-t-shirt-khajistan"]
        waitFor(product, 10, "the search finds the product")
        product.tap()
        let size = shop.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'variant-'")).firstMatch
        waitFor(size, 30, "the shop answers with the product's variants")
        XCTAssertFalse(shop.buttons["addToBag"].isEnabled, "nothing can be added before a choice is made")
        size.tap()
        waitFor(shop.staticTexts["productPrice"], 5, "a chosen variant shows its price")
        shop.buttons["addToBag"].tap()
        waitFor(shop.buttons["bagLink"], 5, "the bag holds it")
        shop.buttons["bagLink"].tap()
        waitFor(shop.staticTexts["bagSubtotal"], 5, "the bag states a subtotal")
        XCTAssertTrue(shop.buttons["bagCheckout"].exists, "checkout is offered, and not pressed here")
        shot("bazaar-bag", shop)

        shop.buttons["tab-search"].tap()
        let field = shop.textFields["archiveSearch"]
        field.tap()
        field.typeText("khwaja")
        waitFor(shop.descendants(matching: .any)["searchRoom-Madrassa"], 30, "the Madrassa answers by name")
        waitFor(shop.descendants(matching: .any)["searchRoom-Street Dictionary"], 30, "the dictionary answers by name")
        XCTAssertTrue(shop.descendants(matching: .any)["searchRoom-Reading Room"].exists, "the Reading Room is searched")
        shot("search-rooms", shop)

        shop.buttons["tab-library"].tap()
        let place = shop.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place-reading|'")).firstMatch
        waitFor(place, 10, "a reading place kept on this device is listed in Library")
        shot("library-places", shop)
    }
}
