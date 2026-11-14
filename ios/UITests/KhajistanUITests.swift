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
        // Turned on its side, the app's own capture comes out as a portrait frame; the screen's does not.
        let picture = XCUIDevice.shared.orientation.isLandscape ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 30, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
    }

    /// ROOMS: the bar's door on iPad and Mac; on a phone, whose bar has none, HOME's "Every room".
    private func openRooms(_ app: XCUIApplication) {
        if app.buttons["tab-rooms"].exists { app.buttons["tab-rooms"].tap(); return }
        tapOnHome(app, "homeAllRooms")
    }

    /// Scrolls HOME until a control sits clear above the bar and the small player, then taps it.
    /// Measured by frame, not isHittable: under the small player the activation point can be unreadable.
    private func tapOnHome(_ app: XCUIApplication, _ id: String) {
        app.buttons["tab-home"].tap()
        let target = app.buttons[id]
        scrollHome(app, to: target, id)
        target.tap()
    }

    /// Scrolls HOME until `target` sits clear above the bar and the small player.
    /// One snapshot per look: HOME's LazyVStack drops rows as they leave the screen, so a row seen
    /// by `exists` can be gone by the next query, and `frame` or `isHittable` on it then fails the test.
    private func scrollHome(_ app: XCUIApplication, to target: XCUIElement, _ name: String) {
        // The top of the bar, or of the small player when one sits over it.
        let player = app.descendants(matching: .any)["nowPlaying"]
        let floor = ((try? player.snapshot())?.frame.minY ?? app.buttons["tab-home"].frame.minY) - 4
        // Its middle, which is where tap() lands; a tall tile need not fit whole.
        let clear = {
            guard let frame = (try? target.snapshot())?.frame, !frame.isEmpty else { return false }
            return frame.midY > 60 && frame.midY < floor - 20
        }
        for _ in 0..<16 where !clear() { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(clear(), "HOME scrolls to \(name)")
    }

    /// HOME is on screen. Its first room tile marks it: "Every room" sits below the picture tiles
    /// (2e213d2), and HOME's LazyVStack does not build what is off screen, so it is not there to find.
    private func waitForHome(_ app: XCUIApplication, _ timeout: TimeInterval, _ message: String) {
        waitFor(app.buttons["home-room-reading"], timeout, message)
    }

    /// An active dock occupies the top of the screen. The lazy channel rows only enter the
    /// accessibility tree after the reader scrolls the catalogue past the map.
    private func firstReceiverChannel(_ app: XCUIApplication) -> XCUIElement {
        let catalogue = app.scrollViews["receiverCatalogue"]
        waitFor(catalogue, 10, "Receiver exposes its scrollable catalogue")
        waitFor(app.buttons["region-indus"], 40, "The region strip lists Indus")
        let channel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        for _ in 0..<16 {
            if channel.exists && channel.isHittable { return channel }
            // Flicks until the first row is built, because a press-and-drag on the map scrubs
            // stations instead of scrolling.
            guard channel.exists else { catalogue.swipeUp(); usleep(400_000); continue }
            // Then short drags with no momentum, started just above the house bar, where the list
            // or the controls above it are. Since the Receiver's two switches (c9932fd) a flick
            // carried the row across the whole gap between the docked player and the bar (about
            // 370 pt on iPhone 17); 160 pt cannot jump it.
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: catalogue.frame.midX, dy: catalogue.frame.maxY - 120))
            let move: CGFloat = channel.frame.midY < catalogue.frame.midY ? 160 : -160
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: move)))
            usleep(400_000)
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
            waitForHome(app, 10, "HOME leads to every room")
            XCTAssertTrue(app.buttons["tab-home"].exists, "the bar is drawn")
            XCTAssertEqual(app.buttons["tab-rooms"].exists, UIDevice.current.userInterfaceIdiom != .phone,
                           "ROOMS is on the bar of an iPad, never a phone's (owner, 2026-11-04)")
            if UIDevice.current.userInterfaceIdiom == .phone {
                // A room opened from HOME goes back to HOME, not to the list the bar no longer offers.
                tapOnHome(app, "home-room-reading")
                waitFor(app.buttons["stackBack"], 10, "the Reading Room opens from its HOME tile")
                XCTAssertTrue(app.buttons["tab-home"].isSelected, "HOME stays lit over a room opened from it")
                app.buttons["stackBack"].tap()
                waitForHome(app, 10, "Back from a room opened on HOME returns to HOME")
                // Every door stays mounted under the one on show, so test what can be touched, not what exists.
                XCTAssertTrue(app.buttons["home-room-reading"].isHittable, "HOME is the page on show after Back")
                XCTAssertFalse(app.staticTexts["Everything in Khajistan"].isHittable, "Back does not land on the ROOMS list")
                app.swipeDown(); app.swipeDown()
            }
            shot("\(skin)-01-home", app)
            openRooms(app)
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
                           "Transmission shows its channels, or the preview-password step")
            shot("\(skin)-05-transmission", app)

            // Khajistan Radio's mixes play on Transmission's Music channel, not in a section of their own
            // (owner, 2026-10-06).
            XCTAssertFalse(app.buttons["part-radio"].exists, "there is no Khajistan Radio section")

            openRooms(app)
            app.buttons["destination-picsnvids"].tap()
            waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch, 40, "the Born Digital stream loads")
            shot("\(skin)-07-pics-vids", app)
            // A phone pushes the room over the list; a wide window shows it beside the list.
            if app.buttons["stackBack"].exists { app.buttons["stackBack"].tap() }
            waitFor(app.buttons["destination-reading"], 5, "the rooms are reachable again")

            app.buttons["tab-search"].tap()
            waitFor(app.textFields["archiveSearch"], 5, "SEARCH carries the field")
            shot("\(skin)-06-search", app)

            app.buttons["tab-library"].tap()
            waitFor(app.buttons["skin-\(skin)"], 5, "the skin control is on the account page")
            shot("\(skin)-08-account", app)
            app.swipeUp()
            shot("\(skin)-09-account-lower", app)

            openRooms(app)
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
            openRooms(app)
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
            waitForHome(app, 10, "HOME loads (\(code))")
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
        // Choosing a region scrolls the strip to centre it, animated. On a slow runner the chips
        // are still sliding when the next tap is placed, and it lands where Anatolia was (CI,
        // 2026-10-27). Tap once the chip has stopped moving.
        let anatolia = app.buttons["region-anatolia"]
        // A region chosen brings its name and channels up under the set, so the strip is above
        // the screen now: scroll back to it.
        for _ in 0..<6 where !anatolia.isHittable { app.swipeDown(); usleep(500_000) }
        for _ in 0..<20 {
            let before = anatolia.frame
            usleep(250_000)
            if anatolia.isHittable && anatolia.frame == before { break }
        }
        anatolia.tap()
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
        // Settled is anything but tuning: a broadcaster's own refusal arrives in its own words
        // ("You do not have permission to access the requested resource", CI 2026-10-31), so a
        // list of expected wordings missed a channel that had said exactly why it would not play.
        let changed = NSPredicate(format: "value != %@ AND label != '' AND label != ' ' AND label != 'Standing by' AND NOT (label CONTAINS[c] 'Connecting') AND NOT (label CONTAINS[c] 'Surfing')", before)
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
        // Off returns the idle set to the top of the scrolled catalogue. Reveal it before
        // reading its accessibility state; a successful stop can put it above the viewport.
        let catalogue = app.scrollViews["receiverCatalogue"]
        for _ in 0..<8 where !state.exists || !catalogue.frame.contains(state.frame) {
            catalogue.swipeDown()
            usleep(400_000)
        }
        expectation(for: NSPredicate(format: "label == 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(state.value as? String, "", "Off clears the tuned channel as well as its status")
        shot("player-off", app)
    }

    /// With a channel on, the docked set and the switches fill the screen above the section, so
    /// Cameras and Transmission changed only what was under the house bar and looked dead
    /// (owner, 2026-10-28: "every button needs to be immediately responsive"). Each part now
    /// comes up on screen, under the set, on its first tap.
    func testReceiverPartsComeUpUnderTheDockedSet() {
        let app = launch(skin: "grove", tab: "receiver", extra: ["-kjautoplay", "YES", "-kjtestsignedout", "YES"])
        let state = app.staticTexts["screenState"]
        waitFor(state, 40, "the receiver opens")
        expectation(for: NSPredicate(format: "label != 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 40)
        let houseBar = app.buttons["tab-receiver"].frame.minY
        func onScreen(_ element: XCUIElement) -> Bool {
            element.exists && element.frame.minY > 0 && element.frame.maxY < houseBar
        }

        app.buttons["part-cameras"].tap()
        let cameras = app.staticTexts["camerasTotal"]
        waitFor(cameras, 20, "Cameras lists its cameras")
        expectation(for: NSPredicate { _, _ in onScreen(cameras) }, evaluatedWith: cameras)
        // One tap, no second: the time only covers the iOS 26 runner reporting the frame late.
        // CI run 41241274308's recording shows the count under the set within a second of the
        // tap while the 3 s wait on its reported frame ran out.
        waitForExpectations(timeout: 10)
        shot("receiver-part-cameras", app)

        app.buttons["part-transmission"].tap()
        let transmission = NSPredicate { _, _ in
            onScreen(app.buttons["transmission-channel-1"]) || onScreen(app.staticTexts["transmissionPreview"])
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: transmission, object: nil)], timeout: 40), .completed,
                       "Transmission comes up on screen under the set")
        shot("receiver-part-transmission", app)

        app.buttons["part-live"].tap()
        // Live opens on its map, the first thing in the part since the Surf settings moved to the foot.
        let map = app.descendants(matching: .any)["receiverMap"]
        expectation(for: NSPredicate { _, _ in onScreen(map) }, evaluatedWith: map)
        waitForExpectations(timeout: 5)
    }

    /// Seven channels, from the Apple TV app's hand-made schedule (one 24-hour strip on each
    /// channel, 2026-11-04 and 05): the station page counts them and carries a card for each,
    /// named from the schedule's `_meta.channels`, down to Channel 7.
    func testTransmissionListsEveryScheduledChannel() {
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../tvos/UITests/Fixtures/programming-seven-channels.json").standardized.path
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjpart", "transmission", "-kjschedulefile", schedule])
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "7 scheduled channels")).firstMatch
        waitFor(count, 40, "the station page counts seven channels")
        let catalogue = app.scrollViews["receiverCatalogue"]
        let names = ["Cinema", "State Television", "Music", "Family Tapes", "Mehfil", "Trailers", "Macabre"]
        for (index, name) in names.enumerated() {
            let card = app.buttons["transmission-channel-\(index + 1)"]
            // Short drags with no momentum, towards the card: on an iPhone SE a flick carries a
            // card past the gap between the docked set and the house bar.
            for _ in 0..<16 where !(card.exists && card.isHittable) {
                let start = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: catalogue.frame.midX, dy: catalogue.frame.maxY - 120))
                let move: CGFloat = card.frame.midY < catalogue.frame.midY ? 160 : -160
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: move)))
                usleep(400_000)
            }
            XCTAssertTrue(card.exists && card.isHittable, "Channel \(index + 1) has a card")
            XCTAssertTrue(card.label.contains("Channel \(index + 1) \u{00B7} \(name)"), card.label)
            if index % 2 == 1 || index == names.count - 1 { shot("transmission-seven-\(index + 1)", app) }
        }
        XCTAssertFalse(app.buttons["transmission-channel-8"].exists, "no card the schedule does not name")
    }

    /// Share of the pixels in `rect` (points) that are not near black, read off a screenshot.
    private func litShare(_ rect: CGRect, _ app: XCUIApplication) -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return 0 }
        let scale = CGFloat(image.width) / app.frame.width
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        var lit = 0, total = 0
        for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 4) {
            for x in stride(from: Int(box.minX), to: Int(box.maxX), by: 4) {
                let i = (y * width + x) * 4
                if max(pixels[i], pixels[i + 1], pixels[i + 2]) > 40 { lit += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(lit) / Double(total)
    }

    /// Whether the picture in `rect` lights within `timeout`. Only for the checks before the
    /// background: a live channel's first frames can be dark, and a slow CI runner reached the
    /// first check before the picture had painted (PR 9, 2026-11-09). The checks after the
    /// background stay single reads, because a picture that stays black is the bug.
    private func becomesLit(_ rect: CGRect, _ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if litShare(rect, app) > 0.05 { return true }
            sleep(1)
        } while Date() < end
        return false
    }

    /// "Play with the app closed" (DECISIONS 24): the picture lets go of the player while the app
    /// is away, so a television channel's sound carries on. Back in the app, the picture comes
    /// back, full screen and then docked; Bugbot found both black while the state said Playing.
    func testReceiverPictureComesBackAfterTheBackground() {
        let app = launch(skin: "grove", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES"])
        let first = firstReceiverChannel(app)
        first.tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 10, "the receiver is on the page")
        expectation(for: NSPredicate(format: "label == 'Playing'"), evaluatedWith: state)
        waitForExpectations(timeout: 60)
        sleep(4)
        // The docked screen sits on the remote, 16:9 across the set; the middle of it is read.
        let surf = app.buttons["surf"].frame
        let set = app.descendants(matching: .any)["receiverScreen"].frame
        let dockHeight = (set.width - 12) * 9 / 16
        let dock = CGRect(x: set.minX + set.width * 0.2, y: surf.minY - dockHeight * 0.8,
                          width: set.width * 0.6, height: dockHeight * 0.6)
        XCTAssertTrue(becomesLit(dock, app), "the docked picture shows before the background")

        app.buttons["fullScreen"].tap()
        waitFor(app.buttons["closePlayer"], 10, "full screen opens")
        sleep(5)
        // Full screen, the picture is fitted across the middle of the screen.
        let screen = app.frame
        let fullHeight = screen.width * 9 / 16
        let full = CGRect(x: screen.width * 0.2, y: screen.midY - fullHeight * 0.3,
                          width: screen.width * 0.6, height: fullHeight * 0.6)
        XCTAssertTrue(becomesLit(full, app), "the full-screen picture shows before the background")

        XCUIDevice.shared.press(.home)
        sleep(6)
        app.activate()
        sleep(6)
        shot("receiver-full-screen-after-background", app)
        XCTAssertEqual(app.staticTexts["playerState"].label, "Playing", "the channel played on")
        XCTAssertGreaterThan(litShare(full, app), 0.05, "the full-screen picture comes back after the background")

        let close = app.buttons["closePlayer"].frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: close.midX, dy: close.midY)).tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.buttons["receiverOff"])
        waitForExpectations(timeout: 10)
        sleep(4)
        shot("receiver-dock-after-background", app)
        XCTAssertGreaterThan(litShare(dock, app), 0.05, "the docked picture comes back after full screen closes")
    }

    /// Real controls receive one tap each: connecting Pause cancels tuning; Stop survives tab navigation.
    /// The Indus list's television rows carry a still this phone took from each live stream, one at
    /// a time, only for rows on screen. Live network: a still gets two windows of 20 s.
    func testReceiverListShowsLiveStills() {
        for skin in skins {
            let app = launch(skin: skin, tab: "receiver")
            _ = firstReceiverChannel(app)
            let stilled = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-' AND value CONTAINS 'live picture'")).firstMatch
            var got = stilled.waitForExistence(timeout: 20)
            if !got {
                app.scrollViews["receiverCatalogue"].swipeUp()
                got = stilled.waitForExistence(timeout: 20)
            }
            XCTAssertTrue(got, "\(skin): a television row shows a still within 20 s (one retry)")
            sleep(6)
            shot("\(skin)-receiver-list-stills", app)
            app.terminate()
        }
    }

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
        waitForHome(app, 5, "One edge tap selects Home")
        app.buttons["tab-receiver"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitFor(state, 5, "One edge tap selects Receiver")
        XCTAssertEqual(state.label, "Standing by", "Navigation does not undo an explicit Stop")
    }

    func testLeavingDuringAutomaticSelectionCancelsAndReopeningRetries() {
        // "Keep playing on other pages" is on by default (DECISIONS 24); this tests the viewer who turned
        // it off, for whom leaving the Receiver still cancels what it was opening.
        let app = launch(skin: "day", tab: "receiver", extra: ["-kjcontrolsstay", "YES", "-kjtestsignedout", "YES", "-kjholdfirstopening", "YES", "-kjopeningdelayms", "5000", "-kj.receiverKeepsPlaying", "NO"])
        waitFor(app.buttons["tab-home"], 3, "The tab bar appears before the deliberately suspended selection")
        app.buttons["tab-home"].tap()
        waitForHome(app, 3, "Home opens with one tap")
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
        XCTAssertEqual(app.staticTexts["receiverCaptionStatus"].label, "Sign in under You to use live captions.")
        app.buttons["fullScreen"].tap()
        waitFor(app.buttons["closePlayer"], 5, "One fullscreen tap opens the player")
        app.buttons["receiverCC"].tap()
        waitFor(app.staticTexts["receiverCaptionStatus"], 5, "Fullscreen CC also responds to one tap")
        XCTAssertEqual(app.staticTexts["receiverCaptionStatus"].label, "Sign in under You to use live captions.")
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
        if app.buttons["tab-rooms"].exists {
            XCTAssertTrue(app.buttons["tab-rooms"].isSelected, "an excluded Pics/Vids launch falls back to ROOMS")
        } else {
            waitFor(app.staticTexts["Everything in Khajistan"], 5, "an excluded Pics/Vids launch falls back to the ROOMS list")
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch.waitForExistence(timeout: 5),
                       "a stored Pics/Vids launch does not open the stream in a store build")
        openRooms(app)
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        XCTAssertTrue(marker.exists, "ROOMS scrolled past where the Pics/Vids, Chat and Wall doors stood")
        XCTAssertFalse(pnvDoor.exists, "a store build has no Pics/Vids door")
        XCTAssertFalse(chatDoor.exists, "a store build has no Chat door")
        XCTAssertFalse(wallDoor.exists, "a store build has no Wall door")
        shot("store-build-rooms", app)
#else
        waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch, 40, "a Pics/Vids launch opens the stream in ROOMS")
        if app.buttons["stackBack"].exists { app.buttons["stackBack"].tap() }
        for _ in 0..<8 where !marker.exists { app.swipeUp() }
        XCTAssertTrue(marker.exists, "ROOMS scrolled past the Chat and Wall doors")
        XCTAssertTrue(pnvDoor.exists, "builds for our own devices keep the Pics/Vids room")
        XCTAssertFalse(app.buttons["destination-receiver"].exists, "ROOMS does not repeat a bar door")
        XCTAssertTrue(chatDoor.exists, "builds for our own devices keep the Chat door")
        XCTAssertTrue(wallDoor.exists, "builds for our own devices keep the Wall door")
#endif
    }

    /// Chat (own builds only; App Store builds leave it out): ROOMS' Chat door opens the rooms,
    /// a room shows its lines or says there are none, a signed-out reader is told to sign in to
    /// write, and back and close return to HOME. Reads the live site's rooms.
    /// A Chat card on Home opens its own room, as the other shelves open the thing on the card.
    /// The shelf shows rooms already loaded, so Chat is opened once first.
    func testHomeChatCardOpensItsRoom() throws {
#if KJ_APP_STORE
        throw XCTSkip("App Store builds leave chat out")
#else
        let app = launch(skin: "grove", tab: "rooms")
        let door = app.buttons["destination-chat"]
        for _ in 0..<8 where !door.exists { app.swipeUp() }
        door.tap()
        waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chat-room-'")).firstMatch, 30, "the rooms load")
        app.buttons["closePlayer"].tap()
        app.buttons["tab-home"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-chat-'")).firstMatch
        scrollHome(app, to: card, "Home's Chat shelf, there once the rooms are loaded")
        let slug = card.identifier.replacingOccurrences(of: "home-chat-", with: "")
        card.tap()
        waitFor(app.staticTexts["chatRoomName"], 10, "the card opens its own room, not the list")
        XCTAssertFalse(app.buttons["chat-room-\(slug)"].exists, "the room list is not what opened")
        shot("chat-from-home-card", app)
#endif
    }

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
        XCTAssertTrue(app.staticTexts["Sign in under You to write in a room."].exists, "a signed-out reader is told how to write")
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
    /// The stream opens as reels (owner, 2026-11-08: "like reels and grid"): a tile opens a
    /// vertical pager at that object, a swipe up moves to the next, and close returns to the grid.
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
        XCTAssertTrue(app.buttons["pnvReelsLink"].isHittable, "Play as reels is on screen")
        shot("pnv-grid", app)
        // A tile deep in the grid, not the first: the reel must open on the object tapped.
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        // The deepest tile the screen shows (one under the tab bar is not tappable).
        let deep = (0..<min(tiles.count, 9)).reversed().map { tiles.element(boundBy: $0) }.first { $0.isHittable } ?? tile
        let key = String(deep.identifier.dropFirst("tile-".count))
        deep.tap()
        let reel = app.descendants(matching: .any)["reel-\(key)"]
        waitFor(reel, 10, "the reels open on the tapped object")
        XCTAssertLessThan(abs(reel.frame.minY), 20, "the tapped object's reel is the one on screen")
        XCTAssertTrue(app.buttons["pnvSave"].waitForExistence(timeout: 10), "Save is on the rail without a tap")
        sleep(3)
        shot("pnv-reel", app)
        app.swipeUp()
        sleep(3)
        // Gone from the tree, or scrolled up out of the screen: either way not the reel on show.
        XCTAssertTrue(!reel.exists || reel.frame.maxY < 20, "a swipe up moves to the next object")
        shot("pnv-reel-next", app)
        app.swipeDown()
        sleep(2)
        XCTAssertTrue(reel.exists && abs(reel.frame.minY) < 20, "a swipe down goes back to the tapped object")
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "close returns to the grid")
    }

    /// The reel never ends (owner, 2026-11-14): a region with fewer objects than swipes still
    /// moves on every swipe, because the reel deals its objects again once the feed has given
    /// them all. The region and Shuffle are changed from inside the reel.
    func testPicsVidsReelIsEndless() {
        let app = launch(skin: "grove", tab: "picsVids")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        waitFor(tile, 40, "the stream loads")
        let notice = app.buttons["adultNoticeOK"]
        if notice.exists { notice.tap(); XCTAssertTrue(notice.waitForNonExistence(timeout: 5)) }
        app.buttons["pnvReelsLink"].tap()
        let shuffle = app.buttons["pnvReelShuffle"]
        waitFor(shuffle, 10, "Shuffle is at the top of the reel")
        XCTAssertEqual(shuffle.value as? String, "Off")
        shuffle.tap()
        XCTAssertTrue(NSPredicate(format: "value == 'On'").evaluate(with: shuffle) || shuffle.waitForValue("On"), "Shuffle turns on")
        shuffle.press(forDuration: 1.2)
        app.buttons["Stream order"].tap()
        XCTAssertTrue(shuffle.waitForValue("Off"), "a long press goes back to the stream's order")
        // Horn of Africa holds 19 objects (measured 2026-11-14): 24 swipes go past its end.
        app.buttons["pnvReelRegion"].tap()
        // The menu's item, not the grid's chip of the same name under the reel.
        app.buttons.matching(NSPredicate(format: "label == 'Horn of Africa' AND identifier != 'pnvregion-horn'")).firstMatch.tap()
        let reels = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reel-'"))
        func onScreen() -> String? {
            (0..<min(reels.count, 4)).map { reels.element(boundBy: $0) }.first { abs($0.frame.minY) < 20 }?.identifier
        }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in onScreen() != nil }, object: nil)], timeout: 30) == .completed,
                      "the region's reel opens")
        XCTAssertEqual(app.buttons["pnvReelRegion"].value as? String, "Horn of Africa")
        var last = onScreen()
        var seen = Set([last].compactMap { $0 })
        for swipe in 1...24 {
            app.swipeUp()
            sleep(1)
            let now = onScreen()
            XCTAssertNotNil(now, "a reel is on screen after swipe \(swipe)")
            XCTAssertNotEqual(now, last, "swipe \(swipe) moved on")
            if let now { seen.insert(now) }
            last = now
        }
        XCTAssertLessThanOrEqual(seen.count, 19, "24 swipes over 19 objects came round again")
        shot("pnv-reel-endless", app)
    }

    /// The skin control: a pick takes effect and Automatic hands back to the sky.
    func testSkinControl() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "yours"]
        app.launch()
        waitFor(app.buttons["skin-grove"], 10, "the skin control is on the account page")
        app.buttons["skin-grove"].tap()
        let line = app.staticTexts["skinLine"]
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Grove for now'"), evaluatedWith: line)
        waitForExpectations(timeout: 5)
        shot("skin-picked-grove", app)
        app.buttons["skin-auto"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Changes with the time of day'"), evaluatedWith: line)
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

    /// The account sheet must receive the existing model across its presentation boundary.
    /// No account or network sign-in is needed to catch the missing-environment crash.
    func testAccountSignInOpensAndCancelsWithoutAStoredSession() {
        let app = launch(skin: "day", tab: "library", extra: ["-kjtestsignedout", "YES"])
        let open = app.buttons["accountSignIn"]
        waitFor(open, 10, "the signed-out account offers Sign in")
        open.tap()
        let email = app.textFields["signInEmail"]
        waitFor(email, 5, "the sheet opens without a missing AppModel crash")
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Cancel")).firstMatch.tap()
        XCTAssertTrue(email.waitForNonExistence(timeout: 5), "Cancel closes the sheet")
        waitFor(open, 5, "the account screen remains usable after closing the sheet")
    }

    /// Sign in on a TV from the phone: Library → Sign in on a TV, a code typed as people type it,
    /// what asked for it said before anything is approved, then done. `-kjtvapprovefixture`
    /// answers in place of the tv-sign-in function (not deployed) and needs no account.
    func testSignInOnATVFromThePhone() {
        let app = launch(skin: "grove", tab: "library", extra: ["-kjtvapprovefixture", "YES"])
        let open = app.buttons["accountSignInTV"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        waitFor(open, 10, "You offers Sign in on a TV")
        open.tap()
        let field = app.textFields["tvApproveCode"]
        waitFor(field, 10, "the screen asks for the code")
        field.tap()
        field.typeText("1234")
        app.buttons["tvApproveContinue"].tap()
        waitFor(app.staticTexts["tvApproveNote"], 5, "a code that cannot be one is refused in place")
        XCTAssertTrue(app.staticTexts["tvApproveNote"].label.hasPrefix("A code is eight"))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "qrt4 mxz7")
        app.buttons["tvApproveContinue"].tap()
        let what = app.staticTexts["tvApproveWhat"]
        waitFor(what, 5, "what asked for the code is said before approving")
        XCTAssertTrue(what.label.hasPrefix("Apple TV asked for code QRT4-MXZ7"), what.label)
        shot("tv-approve-confirm", app)
        app.buttons["tvApproveConfirm"].tap()
        waitFor(app.staticTexts["tvApproveDone"], 5, "the TV is signing in")
        shot("tv-approve-done", app)
    }

    // MARK: - The reader

    /// The page element, which carries "3/76|page|rtl|spread|zoom" as its value in debug builds.
    private func readerState(_ app: XCUIApplication) -> String {
        let page = app.descendants(matching: .any)["rrReaderPage"]
        return page.exists ? (page.value as? String ?? "") : ""
    }

    @discardableResult
    private func waitForPage(_ app: XCUIApplication, _ position: Int, _ timeout: TimeInterval = 45) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var state = ""
        while Date() < deadline {
            state = readerState(app)
            if state.hasPrefix("\(position)/") && state.contains("|page") { return state }
            usleep(300_000)
        }
        return state
    }

    /// A tap on the page at `x` across (0 left, 1 right), half way down.
    private func tapPage(_ app: XCUIApplication, at x: CGFloat) {
        app.descendants(matching: .any)["rrReaderPage"].coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    /// The reader opens with its controls hidden; a tap in the middle of the page brings them.
    private func showControls(_ app: XCUIApplication) {
        let label = app.staticTexts["rrPageLabel"]
        if label.exists && label.isHittable { return }
        tapPage(app, at: 0.5)
        waitFor(label, 5, "a tap in the middle of the page shows the controls")
    }

    /// Opens a free title's first issue from the Reading Room shelf; with `severalIssues`, the first
    /// free title on the shelf that has more than one. Returns the title's card identifier.
    @discardableResult
    private func openFreeIssue(_ app: XCUIApplication, severalIssues: Bool = false) -> String {
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-title-' AND label CONTAINS[c] 'read in full'"))
        waitFor(titles.firstMatch, 60, "a free title is on the shelf")
        let ids = titles.allElementsBoundByIndex.map(\.identifier)
        for id in ids.prefix(severalIssues ? 8 : 1) {
            let card = app.buttons[id]
            for _ in 0..<6 where !card.isHittable { app.swipeUp() }
            card.tap()
            waitFor(app.buttons["rr-issue-0"], 20, "the title lists its issues")
            if !severalIssues || app.buttons["rr-issue-1"].exists {
                app.buttons["rr-issue-0"].tap()
                waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "page 1 is on screen")
                return id
            }
            app.buttons["stackBack"].tap()
        }
        XCTFail("no free title with several issues on the first rows of the shelf")
        return ""
    }

    /// The Reading Room on the phone: a free title opens to its first page full screen with the
    /// controls hidden, a tap in the middle brings them, its first issue reads page by page, and
    /// the place is kept; a members' title stops at the website's preview, two pages, and never
    /// shows the third. Reads the live shelf and page server.
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
        XCTAssertTrue(waitForPage(app, 1).hasPrefix("1/"), "the reader opens on page 1")
        XCTAssertFalse(label.exists, "the page opens alone, the controls hidden")
        sleep(2)
        shot("rr-reader-immersive", app)
        showControls(app)
        XCTAssertTrue(label.label.hasPrefix("Page 1 of "), "the controls say page 1 (\(label.label))")
        XCTAssertFalse(app.descendants(matching: .any)["rrPageRail"].exists, "no rail: the page has the screen")
        shot("rr-reader-p1", app)
        app.buttons["rrNext"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Page 2 of '"), evaluatedWith: label)
        waitForExpectations(timeout: 10)
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "page 2 is on screen")
        // A keyboard's arrows turn as the arrows on screen do (iPad, Mac), the controls hidden or not.
        let rtl = waitForPage(app, 2).contains("|rtl")
        app.typeKey(rtl ? .rightArrow : .leftArrow, modifierFlags: [])
        XCTAssertTrue(waitForPage(app, 1, 20).hasPrefix("1/"), "the arrow key back turns to page 1 (\(readerState(app)))")
        app.typeKey(rtl ? .leftArrow : .rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForPage(app, 2, 20).hasPrefix("2/"), "the arrow key forward turns to page 2 (\(readerState(app)))")
        showControls(app)
        app.buttons["rrReaderClose"].tap()
        waitFor(app.buttons["rrContinue"], 10, "the title offers to continue where reading stopped")
        app.buttons["stackBack"].tap()

        let members = titles.matching(NSPredicate(format: "label CONTAINS[c] 'members'")).firstMatch
        waitFor(members, 30, "a members' title is on the shelf")
        members.tap()
        waitFor(app.buttons["rr-issue-0"], 20, "the members' title lists its issues")
        app.buttons["rr-issue-0"].tap()
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "the reader opens")
        showControls(app)
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

    /// Kindle's touch: the edge in the issue's direction turns forward and the other edge back
    /// (the left edge is next in a right-to-left issue), a tap in the middle shows and hides the
    /// controls, and a bookmark on a page outlives the app. Run in each skin for the screenshots.
    func testReaderTapZonesChromeAndBookmarkAcrossRelaunch() {
        for skin in skins {
            let app = launch(skin: skin, extra: ["-kjroom", "reading", "-kjtestsignedout", "YES"])
            let card = openFreeIssue(app)
            let first = waitForPage(app, 1)
            let rtl = first.contains("|rtl")
            let forwardX: CGFloat = rtl ? 0.08 : 0.92
            let backX: CGFloat = rtl ? 0.92 : 0.08
            sleep(2)
            shot("rr-\(skin)-phone-page", app)
            tapPage(app, at: forwardX)
            XCTAssertTrue(waitForPage(app, 2, 30).hasPrefix("2/"), "the \(rtl ? "left" : "right") edge turns forward (\(readerState(app)))")
            XCTAssertFalse(app.staticTexts["rrPageLabel"].exists, "a turn by the edge leaves the controls hidden")
            tapPage(app, at: backX)
            XCTAssertTrue(waitForPage(app, 1, 30).hasPrefix("1/"), "the other edge turns back (\(readerState(app)))")
            tapPage(app, at: forwardX)
            waitForPage(app, 2, 30)

            showControls(app)
            sleep(1)
            shot("rr-\(skin)-phone-chrome", app)
            tapPage(app, at: 0.5)
            XCTAssertTrue(app.staticTexts["rrPageLabel"].waitForNonExistence(timeout: 5), "a second tap in the middle hides them")
            showControls(app)

            let mark = app.buttons["rrBookmark"]
            waitFor(mark, 5, "the controls carry a bookmark for the page")
            if (mark.value as? String) == "On" { mark.tap() }
            mark.tap()
            XCTAssertEqual(mark.value as? String, "On", "the page is marked")
            app.buttons["rrPagesButton"].tap()
            waitFor(app.buttons["rrMark-2"], 10, "the pages grid lists the mark")
            sleep(4)
            shot("rr-\(skin)-pages-grid", app)
            app.buttons["rrGridDone"].tap()
            app.terminate()

            // The mark is there after a relaunch, and comes off (once; the other skins are for the pictures).
            for wanted in ["On", "Off"] where skin == skins.first {
                let again = launch(skin: skin, extra: ["-kjroom", "reading", "-kjtestsignedout", "YES"])
                let title = again.buttons[card]
                waitFor(title, 60, "the same title is on the shelf")
                for _ in 0..<6 where !title.isHittable { again.swipeUp() }
                title.tap()
                waitFor(again.buttons["rrContinue"], 20, "the title offers to continue at page 2")
                again.buttons["rrContinue"].tap()
                XCTAssertTrue(waitForPage(again, 2).hasPrefix("2/"), "Continue opens page 2")
                showControls(again)
                let kept = again.buttons["rrBookmark"]
                waitFor(kept, 5, "the bookmark control")
                XCTAssertEqual(kept.value as? String, wanted, "the bookmark reads \(wanted) after a relaunch")
                if wanted == "On" { kept.tap() }
                again.terminate()
            }
        }
    }

    /// Wide: two facing pages, the cover alone, in the issue's order; the grid jumps and the
    /// scrubber offers the way back; the last page leads to the next issue. On a phone the device
    /// is turned to landscape; an iPad runs it in both orientations.
    func testReaderSpreadGridBackAndEndOfIssue() {
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad ? [.portrait, .landscapeLeft] : [.landscapeLeft]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            defer { XCUIDevice.shared.orientation = .portrait }
            let wide = orientation.isLandscape
            let app = launch(skin: wide ? "grove" : "smut", extra: ["-kjroom", "reading", "-kjtestsignedout", "YES"])
            let tag = UIDevice.current.userInterfaceIdiom == .pad ? "ipad-\(wide ? "landscape" : "portrait")" : "phone-landscape"
            openFreeIssue(app, severalIssues: true)
            let first = waitForPage(app, 1)
            XCTAssertFalse(first.contains("|spread"), "the cover is alone (\(first))")
            let rtl = first.contains("|rtl")
            tapPage(app, at: rtl ? 0.08 : 0.92)
            let second = waitForPage(app, 2, 30)
            if wide {
                // The facing page arrives after the first; give it a moment.
                for _ in 0..<20 where !readerState(app).contains("|spread") { usleep(500_000) }
                XCTAssertTrue(readerState(app).contains("|spread"), "a wide screen shows pages 2 and 3 together (\(readerState(app)))")
            } else {
                XCTAssertFalse(second.contains("|spread"), "a tall screen shows one page (\(second))")
            }
            sleep(2)
            shot("rr-\(tag)-page-two", app)

            // The grid jumps, and the way back is offered.
            showControls(app)
            app.buttons["rrPagesButton"].tap()
            let five = app.buttons["rrGridPage-5"]
            waitFor(five, 10, "the grid lists the pages")
            sleep(3)
            shot("rr-\(tag)-grid", app)
            five.tap()
            XCTAssertTrue(waitForPage(app, wide ? 4 : 5, 30).contains("|page"), "the grid opens the page chosen (\(readerState(app)))")
            showControls(app)
            let back = app.buttons["rrBackToPage"]
            waitFor(back, 5, "after a jump the controls offer the way back")
            XCTAssertEqual(back.label.lowercased(), "back to page 2", "it names the page left")
            shot("rr-\(tag)-back-to-page", app)
            back.tap()
            XCTAssertTrue(waitForPage(app, 2, 30).hasPrefix("2/"), "back goes to the page left")

            // The scrubber to its far end, then one more turn: the end of the issue.
            showControls(app)
            let slider = app.descendants(matching: .any)["rrPageSlider"]
            let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.3, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0 : 1, dy: 0.5)))
            let total = Int(first.split(separator: "/")[1].split(separator: "|")[0]) ?? 0
            let last = wide && total > 1 && !total.isMultiple(of: 2) ? total - 1 : total
            XCTAssertTrue(waitForPage(app, last, 45).hasPrefix("\(last)/"), "the scrubber's end is the last page (\(readerState(app)))")
            tapPage(app, at: rtl ? 0.08 : 0.92)
            let end = app.descendants(matching: .any)["rrEnd"]
            waitFor(end, 15, "turning past the last page is the end of the issue")
            shot("rr-\(tag)-end", app)
            let next = app.buttons["rrNextIssue"]
            XCTAssertTrue(next.exists, "a title with more issues offers the next one")
            let before = app.descendants(matching: .any)["rrReaderTitle"].label
            next.tap()
            XCTAssertTrue(waitForPage(app, 1).hasPrefix("1/"), "the next issue opens at page 1")
            showControls(app)
            XCTAssertNotEqual(app.descendants(matching: .any)["rrReaderTitle"].label, before, "the reader names the next issue")
            app.terminate()
        }
    }

    /// Madrassa, the databases and the Bazaar read the site's own files. The live site holds them
    /// behind its password until launch, so without one the rooms say so and hold the password field.
    /// With `TEST_RUNNER_KJ_SITE` set to a local checkout (scripts/dev_server.py), the test walks the
    /// real records: an entry, an essay, the dictionary, the censor certificates, and a product into
    /// the bag. It stops before checkout: nothing is sent to the shop's checkout.
    func testMadrassaDatabasesAndBazaarReadTheSiteData() {
        guard let site = ProcessInfo.processInfo.environment["KJ_SITE"] else {
            let app = launch(skin: "day", extra: ["-kjroom", "madrassa"])
            waitFor(app.descendants(matching: .any)["roomLocked"], 30, "a gated room says it is behind the password")
            XCTAssertTrue(app.secureTextFields.firstMatch.exists, "the note holds the preview password field")
            XCTAssertEqual((app.buttons["lockedOpen"].value as? String)?.lowercased(), "nothing typed", "Open knows nothing is typed yet")
            return
        }
        let app = launch(skin: "smut", extra: ["-kjroom", "madrassa", "-kjsite", site, "-kjtestsignedout", "YES"])
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
        waitFor(app.descendants(matching: .any)["postContents"], 5, "a long piece lists its contents")
        shot("madrassa-essay", app)
        app.buttons["postSave"].tap()
        waitFor(app.textFields["signInEmail"], 5, "Save asks a signed-out reader to sign in, and saves nothing on the device")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.textFields["signInEmail"].waitForNonExistence(timeout: 5), "the sign-in sheet closes")
        app.buttons["stackBack"].tap()

        app.buttons["madrassa-dictionary"].tap()
        let count = app.staticTexts["lughatCount"]
        waitFor(count, 20, "the dictionary loads")
        XCTAssertTrue(count.label.hasSuffix("of 829 entries"), "every entry is counted (\(count.label))")

        app.buttons["madrassa-databases"].tap()
        // The shelves list runs past the screen on a phone: scroll to the database first.
        let censor = app.buttons["db-censorCertificates"]
        for _ in 0..<8 where !censor.exists { app.swipeUp() }
        censor.tap()
        let records = app.staticTexts["dbCount"]
        expectation(for: NSPredicate(format: "label == '52 of 52 records'"), evaluatedWith: records)
        waitForExpectations(timeout: 30)
        app.buttons["dbSortMenu"].tap()
        app.buttons["dbSort-newest"].tap()
        let newest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'record-'")).firstMatch
        waitFor(newest, 10, "sorted records are listed")
        XCTAssertTrue(newest.label.contains("1997") || newest.label.contains("199"), "newest first: the 1990s lead (\(newest.label))")
        XCTAssertEqual(records.label, "52 of 52 records", "sorting changes the order, not the count")
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'record-'")).firstMatch
        record.tap()
        waitFor(app.buttons["recordLink"], 10, "a certificate links to its scan")
        shot("database-record", app)
        app.buttons["recordLink"].tap()
        let pageLabel = app.staticTexts["rrPageLabel"]
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "the scan opens in the app's own reader, not the website")
        showControls(app)
        XCTAssertTrue(pageLabel.label.hasPrefix("Page 1 of "), "on the page the link names (\(pageLabel.label))")
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

        shop.buttons["tab-home"].tap()
        let place = shop.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-continue-' OR identifier BEGINSWITH 'continue-'")).firstMatch
        waitFor(place, 10, "a reading place kept on this device is under Continue on Home")
        shot("library-places", shop)
    }

    /// The Receiver keeps playing under the other doors, with a small bar that pauses it, turns it
    /// off, and leads back to it.
    func testNowPlayingBarFollowsTheReceiverAcrossDoors() {
        let app = launch(skin: "grove", tab: "receiver", extra: ["-kjautoplay", "YES", "-kjtestsignedout", "YES"])
        let state = app.staticTexts["screenState"]
        waitFor(state, 40, "the receiver opens")
        expectation(for: NSPredicate(format: "label != 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 40)
        XCTAssertFalse(app.descendants(matching: .any)["nowPlaying"].exists, "no small player on the Receiver itself")
        openRooms(app)
        let bar = app.descendants(matching: .any)["nowPlaying"]
        waitFor(bar, 5, "the small player shows under another door")
        shot("now-playing-bar", app)
        let toggle = app.buttons["nowPlayingToggle"]
        if toggle.label == "Pause" {
            toggle.tap()
            expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: toggle)
            waitForExpectations(timeout: 10)
        }
        app.buttons["nowPlayingOff"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "Off leaves nothing playing and nothing on screen")
        app.buttons["tab-receiver"].tap()
        expectation(for: NSPredicate(format: "label == 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
    }

    /// A channel left on plays while reading, and its small player is in the reader too, which
    /// covers the house bar (owner, 2026-10-28: "play a tv channel as they read"). Its name closes
    /// the reader and opens the Receiver.
    func testNowPlayingBarStaysOverTheReader() {
        let app = launch(skin: "day", extra: ["-kjroom", "reading", "-kjautoplay", "YES", "-kjtestsignedout", "YES"])
        app.buttons["tab-receiver"].tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 40, "the receiver opens")
        expectation(for: NSPredicate(format: "label != 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 40)
        if app.buttons["tab-rooms"].exists { app.buttons["tab-rooms"].tap() } else { tapOnHome(app, "home-room-reading") }
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rr-title-'"))
        waitFor(titles.firstMatch, 60, "the shelf loads")
        let free = titles.matching(NSPredicate(format: "label CONTAINS[c] 'read in full'")).firstMatch
        waitFor(free, 30, "a free title is on the shelf")
        free.tap()
        let issue = app.buttons["rr-issue-0"]
        waitFor(issue, 20, "the title lists its issues")
        issue.tap()
        waitFor(app.descendants(matching: .any)["rrReaderPage"], 45, "page 1 is on screen")
        let bar = app.descendants(matching: .any)["nowPlaying"]
        waitFor(bar, 5, "the small player is in the reader")
        shot("now-playing-reader", app)
        // The house bar's own small player is still in the tree under the reader: take the one on top.
        let names = app.buttons.matching(identifier: "nowPlayingName").allElementsBoundByIndex
        guard let name = names.first(where: { $0.isHittable }) else { return XCTFail("the reader's small player can be tapped") }
        name.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rrReaderPage"].waitForNonExistence(timeout: 5), "the reader closes")
        waitFor(state, 5, "the Receiver is open")
        XCTAssertFalse(bar.exists, "no small player on the Receiver itself")
    }

    /// With Keep playing off, leaving the Receiver turns the channel off: no bar, nothing on
    /// returning. The choice comes as a launch argument so no test leaves it behind.
    func testLeavingTheReceiverStopsItWhenKeepPlayingIsOff() {
        let app = launch(skin: "smut", tab: "receiver",
                         extra: ["-kjautoplay", "YES", "-kjtestsignedout", "YES", "-kj.receiverKeepsPlaying", "NO"])
        let state = app.staticTexts["screenState"]
        waitFor(state, 40, "the receiver opens")
        expectation(for: NSPredicate(format: "label != 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 40)
        // A house switch carries the toggle trait, so it is not listed among the buttons.
        let choice = app.descendants(matching: .any)["receiverKeepsPlaying"]
        waitFor(choice, 10, "the Receiver offers the choice")
        XCTAssertTrue(["Off", "0"].contains(String(describing: choice.value ?? "")), "the choice reads off (\(String(describing: choice.value)))")
        openRooms(app)
        XCTAssertFalse(app.descendants(matching: .any)["nowPlaying"].waitForExistence(timeout: 3), "nothing plays on another page")
        app.buttons["tab-receiver"].tap()
        expectation(for: NSPredicate(format: "label == 'Standing by'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
    }

    /// "Keep playing" off, the viewer leaves while the launch Surf is still choosing: the Surf is
    /// dropped and nothing starts under the other page. (A Surf has no source until it lands, so a
    /// turn-off that only stopped what was on let it play under ROOMS.)
    func testLeavingDuringTheLaunchSurfPlaysNothingWhenKeepPlayingIsOff() {
        let app = launch(skin: "day", tab: "receiver",
                         extra: ["-kjautoplay", "YES", "-kjtestsignedout", "YES", "-kj.receiverKeepsPlaying", "NO"])
        waitFor(app.buttons["tab-home"], 5, "the house bar is up")
        openRooms(app)
        XCTAssertFalse(app.descendants(matching: .any)["nowPlayingName"].waitForExistence(timeout: 20),
                       "a Surf that was still choosing does not land under another page")
        app.buttons["tab-receiver"].tap()
        let state = app.staticTexts["screenState"]
        waitFor(state, 10, "the receiver reopens")
    }

    /// Signed out, the film watchlist and the Pics/Vids save ask to sign in and keep nothing on
    /// the device: a save is on the account or nowhere.
    func testSavesAskASignedOutReaderToSignIn() {
        // The controls stay up, so the test does not race the viewer's 2.6 s fade.
        let app = launch(skin: "day", extra: ["-kjroom", "picsVids", "-kjtestsignedout", "YES", "-kjcontrolsstay", "YES"])
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        waitFor(tile, 40, "the stream loads")
        let notice = app.buttons["adultNoticeOK"]
        if notice.exists { notice.tap(); XCTAssertTrue(notice.waitForNonExistence(timeout: 5)) }
        XCTAssertFalse(app.buttons["pnvSavedLink"].exists, "no Saved link for a signed-out reader")
        tile.tap()
        waitFor(app.buttons["closePlayer"], 10, "the viewer opens")
        let save = app.buttons["pnvSave"]
        waitFor(save, 5, "the viewer offers Save")
        save.tap()
        let note = app.staticTexts["pnvSaveNote"]
        waitFor(note, 5, "Save says where to sign in")
        XCTAssertTrue(app.buttons["closePlayer"].exists, "the viewer stays open")
        XCTAssertEqual((save.value as? String)?.lowercased(), "off", "nothing is saved on the device")
        shot("pnv-save-signin", app)
    }

    /// Home carries a shelf for each part of Khajistan under the masthead (owner, 2026-10-29), and
    /// scrolls down to them: the Receiver's Surf, the Reading Room's covers, Pics/Vids (its notice
    /// line until the room's notice is answered) and Chat need no password.
    func testHomeScrollsThroughAShelfForEachPart() {
        let app = launch(skin: "day")
        waitForHome(app, 15, "HOME is up")
        sleep(6)   // the shelves load a moment after Home
        let wanted = ["home-surf", "home-shelf-reading", "home-shelf-picsvids", "home-shelf-chat"]
        var seen = Set<String>()
        for step in 0..<14 {
            for shelf in wanted where app.descendants(matching: .any)[shelf].exists { seen.insert(shelf) }
            shot(String(format: "home-scroll-%02d", step), app)
            if seen.count == wanted.count && step >= 6 { break }
            app.swipeUp(velocity: .slow)
            usleep(800_000)
        }
        XCTAssertEqual(seen, Set(wanted), "Home scrolls through a shelf for each part")
    }

    /// Every native room fits the screen it is on, upright and turned: no text runs past the left
    /// or right edge outside a scroll view (a shelf scrolls sideways; a line of text must not).
    /// Run it on the small iPhone, the big one and the iPads, and with the largest text size
    /// (`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`).
    func testEveryRoomFitsTheScreenUprightAndTurned() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        var overflow: [String] = []
        for room in ["receiver", "picsVids", "yours", "chat", "reading", "screening", "bazaar", "madrassa"] {
            let app = launch(skin: "day", extra: ["-kjroom", room, "-kjtestsignedout", "YES"])
            waitFor(app.buttons["tab-home"], 15, "the house bar is up in \(room)")
            for orientation in [UIDeviceOrientation.portrait, isPad ? .landscapeLeft : .landscapeRight] {
                XCUIDevice.shared.orientation = orientation
                sleep(6)
                let tag = "\(room)-\(orientation == .portrait ? "upright" : "turned")"
                shot("fit-\(tag)", app)
                overflow += offScreenText(app).map { "\(tag): \($0)" }
            }
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCTAssertTrue(overflow.isEmpty, "text runs past the screen edge:\n" + overflow.joined(separator: "\n"))
    }

    /// Text and buttons whose frame leaves the window sideways, outside every scroll view.
    private func offScreenText(_ app: XCUIApplication) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        let width = app.windows.firstMatch.frame.width
        var found: [String] = []
        func walk(_ node: XCUIElementSnapshot, inScroll: Bool) {
            let scroll = inScroll || [.scrollView, .collectionView, .table, .webView].contains(node.elementType)
            let f = node.frame
            if !scroll, [.staticText, .button, .textField].contains(node.elementType), f.width > 0, f.height > 0,
               f.minX < -1 || f.maxX > width + 1 {
                found.append("\(node.elementType.rawValue) '\(node.label.prefix(40))' x \(Int(f.minX))...\(Int(f.maxX)) of \(Int(width))")
            }
            for child in node.children { walk(child, inScroll: scroll) }
        }
        walk(root, inScroll: false)
        return found
    }
}

private extension XCUIElement {
    func waitForValue(_ value: String, timeout: TimeInterval = 10) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: self)],
                       timeout: timeout) == .completed
    }
}
