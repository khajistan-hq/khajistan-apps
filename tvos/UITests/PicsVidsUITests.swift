import XCTest

/// Walks Pics/Vids with the Siri Remote: the notice, the shelves (one per region), the kind filter,
/// a picture, a video and a Khajistan TV row (signed out), and keeps a screenshot of each stop. Strict about the app's own
/// elements and loose about what the network answers on the day.
final class PicsVidsUITests: XCTestCase {
    override func setUpWithError() throws {
#if KJ_APP_STORE
        throw XCTSkip("App Store builds leave Pics/Vids out (StoreBuild)")
#else
        continueAfterFailure = false
#endif
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids"]
        kjLaunch(app)
        return app
    }

    private func tiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
    }

    private func focusedTile(_ app: XCUIApplication) -> XCUIElement {
        tiles(app).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// One element per region shelf; its value is the number of objects drawn so far.
    private func shelves(_ app: XCUIApplication) -> XCUIElementQuery {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'pnv-shelf-'"))
    }

    /// The shelf that holds the focused tile, by its identifier, or nil.
    private func focusedShelf(_ app: XCUIApplication) -> String? {
        for index in 0..<shelves(app).count {
            let shelf = shelves(app).element(boundBy: index)
            if shelf.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists { return shelf.identifier }
        }
        return nil
    }

    /// The shelves' headings, as one line: region and count, west to east.
    private func headings(_ app: XCUIApplication) -> String {
        // All regions first: it heads the page, so the region shelves can start below the screen.
        let names = ["All regions", "Maghreb", "Mashriq", "Anatolia", "Persia", "Khorasan", "Indus"]
        let format = names.map { "label BEGINSWITH '\($0)'" }.joined(separator: " OR ")
        let texts = app.staticTexts.matching(NSPredicate(format: format))
        return (0..<texts.count).map { texts.element(boundBy: $0).label }.joined(separator: " | ")
    }

    /// The notice is the first thing under the top bar: reach OK, press it once.
    private func dismissNotice(_ app: XCUIApplication) {
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The notice must come before the stream")
        XCTAssertTrue(kjFocus(ok, app: app), "The notice's OK must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(1)
        XCTAssertFalse(ok.exists, "OK must dismiss the notice")
    }

    func testNoticeThenTheShelvesAreWalkable() {
        let app = launch()
        let ok = app.buttons["adultNoticeOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 60), "The adult notice must be the first thing on Pics/Vids")
        XCTAssertTrue(app.staticTexts["This archive holds adult material."].exists, "The notice carries the site's wording")
        XCTAssertTrue(app.buttons["adultNoticeDontAsk"].exists, "The notice offers Don't ask again")
        kjPause(3)
        kjScreenshot("pv-01-notice", app: app)
        dismissNotice(app)

        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60), "The shelves must show tiles")
        kjPause(6)
        XCTAssertTrue(app.buttons["pnvkind-all"].exists, "The filter must follow the notice")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pnvregion-'")).firstMatch.exists, "the shelves replace the region tabs")
        kjScreenshot("pv-02-shelves", app: app)
        print("PNVHEADINGS " + headings(app))

        // Down from the filter into the first shelf, then a walk that must reach at least six
        // tiles on at least two shelves.
        for _ in 0..<6 where !focusedTile(app).exists { XCUIRemote.shared.press(.down); kjPause(0.5) }
        XCTAssertTrue(focusedTile(app).exists, "A tile must take focus")
        var seen = Set<String>()
        var onShelves = Set<String>()
        var log: [String] = []
        let walk: [XCUIRemote.Button] = [.right, .right, .right, .down, .right, .down, .left, .left, .down, .right]
        var lastTileID = focusedTile(app).identifier
        seen.insert(lastTileID)
        if let shelf = focusedShelf(app) { onShelves.insert(shelf) }
        for press in walk {
            XCUIRemote.shared.press(press)
            kjPause(0.8)
            let id = focusedTile(app).exists ? focusedTile(app).identifier : "(off the shelves)"
            seen.insert(id)
            if id != "(off the shelves)" { lastTileID = id }
            if let shelf = focusedShelf(app) { onShelves.insert(shelf) }
            log.append("\(press == .left ? "L" : press == .right ? "R" : press == .up ? "U" : "D")->\(id)")
        }
        print("PNVWALK " + log.joined(separator: " ") + " shelves=" + onShelves.sorted().joined(separator: ","))
        seen.remove("(off the shelves)")
        XCTAssertGreaterThanOrEqual(seen.count, 6, "the walk must reach six tiles; walk: \(log)")
        XCTAssertGreaterThanOrEqual(onShelves.count, 2, "down must move from one region's shelf to the next; shelves: \(onShelves)")
        kjScreenshot("pv-03-walked", app: app)

        // Live shelves can end on a loading/retry control. Choose the last visited tile
        // explicitly; one Select on a focused tile must open its viewer.
        let chosenTile = app.buttons[lastTileID]
        XCTAssertTrue(kjFocus(chosenTile, app: app), "The chosen tile must take focus before Select: \(lastTileID)")
        XCTAssertTrue(chosenTile.hasFocus)
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 20), "Select must open the viewer")
        kjPause(0.8)
        kjScreenshot("pv-04a-viewer-overlay", app: app)
        kjPause(6)
        kjScreenshot("pv-04b-viewer-clean", app: app)
        XCUIRemote.shared.press(.right)
        kjPause(6)
        kjScreenshot("pv-05-viewer-next", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20), "Menu must come back to the shelves")
        XCTAssertFalse(surface.exists)
    }

    /// Save and Collection in the viewer, lit by the remote: Down lights Save, Right Collection, Up
    /// lets go. Signed out, Select on Save says where to sign in, in place.
    func testViewerSaveControls() {
        for skin in ["day", "grove", "smut"] {
            let app = XCUIApplication()
            app.launchArguments = ["-kjtab", "picsvids", "-kjskin", skin]
            kjLaunch(app)
            dismissNotice(app)
            let tile = tiles(app).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 60), "The shelves must show tiles")
            XCTAssertTrue(kjFocus(tile, app: app), "a tile takes focus")
            XCUIRemote.shared.press(.select)
            let save = app.descendants(matching: .any)["pnvSave"]
            XCTAssertTrue(save.waitForExistence(timeout: 20), "the viewer offers Save")
            XCTAssertFalse(save.isSelected, "nothing is lit until the remote moves to it")
            // The grid's viewer draws the status band: the Reel's "no band" check matches it here.
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Khajistan Pics/Vids'")).firstMatch.exists,
                          "the grid viewer shows the status band")
            XCUIRemote.shared.press(.down)
            kjPause(0.6)
            XCTAssertTrue(save.isSelected, "Down lights Save")
            XCUIRemote.shared.press(.right)
            kjPause(0.6)
            XCTAssertTrue(app.descendants(matching: .any)["pnvCollection"].isSelected, "Right lights Collection")
            XCUIRemote.shared.press(.left)
            kjPause(0.6)
            XCTAssertTrue(save.isSelected, "Left comes back to Save")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["pnvSaveNote"].waitForExistence(timeout: 5), "signed out, Save says where to sign in")
            kjScreenshot("\(skin)-pv-save", app: app)
            XCUIRemote.shared.press(.up)
            kjPause(0.6)
            XCTAssertFalse(save.isSelected, "Up lets go")
            app.terminate()
        }
    }

    /// Walking right along a shelf to its end reaches the next page of that shelf.
    func testScrollingLoadsTheNextPage() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(6)
        // A shelf with a full first page and more behind it. Shuffle is on from the start on the
        // Apple TV (owner, 2026-11-14), so a page is PnvAPI.shufflePageSize, 120, not 60.
        var wanted: XCUIElement?
        for index in 0..<shelves(app).count {
            let shelf = shelves(app).element(boundBy: index)
            if Int(shelf.value as? String ?? "") == 120 { wanted = shelf; break }
        }
        guard let shelf = wanted else { return XCTFail("a region with more than one page must be on the page") }
        let first = Int(shelf.value as? String ?? "") ?? 0
        let tile = shelf.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        XCTAssertTrue(kjFocus(tile, app: app), "a tile on the shelf must take focus")
        var loaded = first
        // A shuffled page is 120, and the next is asked for eight from its end.
        for _ in 0..<140 {
            XCUIRemote.shared.press(.right)
            kjPause(0.3)
            loaded = Int(shelf.value as? String ?? "") ?? loaded
            if loaded > first { break }
        }
        kjScreenshot("pv-11-paged", app: app)
        XCTAssertGreaterThan(loaded, first, "walking to the end of the page must load the next one")
    }

    func testFiltersNarrowTheShelves() {
        let app = launch()
        dismissNotice(app)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(6)
        let everything = headings(app)
        XCTAssertFalse(everything.isEmpty, "the shelves must carry headings with their counts")

        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(kjFocus(videos, app: app), "Videos must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(10)
        let narrowed = headings(app)
        print("PNVHEADINGS everything=[\(everything)] videos=[\(narrowed)]")
        XCTAssertNotEqual(narrowed, everything, "Videos must narrow every shelf's count")
        XCTAssertTrue(tiles(app).firstMatch.exists, "the shelves still show tiles")
        kjScreenshot("pv-06-videos", app: app)

        let pictures = app.buttons["pnvkind-image"]
        XCTAssertTrue(pictures.exists, "Pictures is offered")
        XCTAssertTrue(kjFocus(pictures, app: app), "Pictures must take focus")
        XCUIRemote.shared.press(.select)
        kjPause(10)
        XCTAssertNotEqual(headings(app), narrowed, "Pictures must differ from Videos")
        kjScreenshot("pv-07-pictures", app: app)
    }

    /// A Khajistan TV row and an account-hosted video, signed out. The row opens on its poster and
    /// says what it needs; the other plays.
    func testVideoAndKhajistanTVRow() {
        let app = launch()
        dismissNotice(app)
        let videos = app.buttons["pnvkind-video"]
        XCTAssertTrue(videos.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocus(videos, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 60))
        kjPause(8)

        let ktv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        let account = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-' AND NOT identifier BEGINSWITH 'tile-ktv-'")).firstMatch
        XCTAssertTrue(account.exists, "An account video must be on the first page")
        XCTAssertTrue(kjFocus(account, app: app), "An account video must take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["pnvViewerSurface"].waitForExistence(timeout: 20))
        kjPause(1)
        kjScreenshot("pv-08a-video-overlay", app: app)
        kjPause(11)
        kjScreenshot("pv-08b-video-playing", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))

        guard ktv.exists else {
            kjScreenshot("pv-09-no-ktv-row-on-first-page", app: app)
            return
        }
        XCTAssertTrue(kjFocus(ktv, app: app), "A Khajistan TV row must take focus")
        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["pnvViewerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20), "A Khajistan TV row signed out must say what it needs")
        kjPause(4)
        XCTAssertEqual(state.label, "Sign in to watch Khajistan Transmission.")
        kjScreenshot("pv-09-ktv-signed-out", app: app)
        XCUIRemote.shared.press(.select)
        // Sign-in opens on the phone panel (QR and code; 2026-10-27), or on email and password
        // when the tv-sign-in function cannot be reached. Either is the sign-in sheet.
        let phone = app.buttons["tvSignInUsePassword"]
        let password = app.buttons["Sign in"]
        let opened = NSPredicate { _, _ in phone.exists || password.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: opened, object: nil)], timeout: 15), .completed,
                       "Select must open the sign-in sheet")
        kjScreenshot("pv-10-ktv-sign-in-sheet", app: app)
        XCUIRemote.shared.press(.menu)
        kjPause(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 20))
    }

    /// The Reel comes round at a stream's end rather than stopping. The feed is cut to 12 videos
    /// (`-kjreelcap`), so the end is reached whatever a region holds: Anatolia had 48 videos on
    /// 2026-11-14 and 567 on 2026-11-20, past the 200 presses this test used to walk.
    func testReelComesRoundAtTheEndOfASmallRegion() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjreelcap", "12"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(2)
        XCUIRemote.shared.press(.up); kjPause(1)
        var last = surface.value as? String
        var seen = Set([last].compactMap { $0 })
        var cameRound = false
        // Until the first object seen twice: the feed's end, passed.
        for press in 1...30 {
            XCUIRemote.shared.press(.up)
            kjPause(1.2)
            let now = surface.value as? String
            XCTAssertNotEqual(now, last, "Up \(press) moved on")
            last = now
            if let now, !seen.insert(now).inserted { cameRound = true; break }
        }
        print("PNVREEL came round after \(seen.count) distinct")
        XCTAssertTrue(cameRound, "past the end the stream comes round and shows an object again")
    }

    /// A video that cannot play is skipped after a moment; after two in a row the Reel stays on the
    /// third (owner, 2026-11-19: the Reel plays on by itself).
    func testReelSkipsTwoBrokenVideosThenStops() { reelSkipsTwoBrokenVideosThenStops("YES") }

    /// The same, for a video that fails inside the player (a dead address), not before it.
    func testReelSkipsTwoDeadVideosThenStops() { reelSkipsTwoBrokenVideosThenStops("dead") }

    /// Down onto a broken video skips on back, not forward to the video just left (Fable round 5):
    /// with only the deal's second video broken, Up, Up (skipped on to the third), then Down onto
    /// the broken second, which must skip back to the first.
    func testReelSkipsBackwardAfterDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjbrokenvideos", "second"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(2)
        let first = surface.value as? String
        XCTAssertFalse((first ?? "").isEmpty, "the Reel shows its first video")
        // Up onto the broken second. It must show, then be skipped on: a second that played would
        // make the rest of this test pass with no skip run at all.
        XCUIRemote.shared.press(.up)
        let second = waitForValue(surface, notIn: [first], seconds: 5)
        XCTAssertNotNil(second, "Up moved onto the second video")
        let third = waitForValue(surface, notIn: [first, second], seconds: 8)
        XCTAssertNotNil(third, "the broken second was skipped on to the third")
        // Down at once onto the broken second must skip back to the first, not forward again.
        XCUIRemote.shared.press(.down)
        let landed = waitForValue(surface, notIn: [third, second], seconds: 8)
        print("PNVBACK first=\(first ?? "nil") second=\(second ?? "nil") third=\(third ?? "nil") landed=\(landed ?? "nil")")
        XCTAssertEqual(landed, first, "Down onto a broken video skips on back to the one before it")
        // Back on the first video, which plays: Down comes round to the last video loaded (owner,
        // 2026-11-20: "it should work both ways"), and Down again goes on back from there.
        XCUIRemote.shared.press(.down)
        let wrapped = waitForValue(surface, notIn: [first], seconds: 5)
        print("PNVWRAP first=\(first ?? "nil") wrapped=\(wrapped ?? "nil")")
        XCTAssertNotNil(wrapped, "Down on the first video moves")
        XCTAssertNotEqual(wrapped, third, "Down on the first goes round to the end, not forward")
        XCUIRemote.shared.press(.down)
        XCTAssertNotNil(waitForValue(surface, notIn: [wrapped, first], seconds: 5), "Down goes on back from the last")
    }

    /// A lit control holds the skip of a broken video, and a control left alone lets go after
    /// 10 s, so the Reel plays on (Fable round 8).
    func testReelLitControlHoldsTheSkipThenLetsGo() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjbrokenvideos", "second"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        let first = waitForValue(surface, notIn: [nil, ""], seconds: 10)
        // Up onto the broken second, and light Save at once.
        XCUIRemote.shared.press(.up)
        let second = waitForValue(surface, notIn: [first], seconds: 5)
        XCTAssertNotNil(second, "Up moved onto the second video")
        XCUIRemote.shared.press(.right)
        let save = app.descendants(matching: .any)["pnvSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 2) && save.isSelected, "Right lights Save")
        // Well past the 2 s skip: still on the broken second while Save is lit.
        kjPause(5)
        XCTAssertEqual(surface.value as? String, second, "a lit control holds the skip")
        // Left alone, Save lets go after 10 s and the skip goes on.
        let moved = waitForValue(surface, notIn: [second], seconds: 12)
        print("PNVHOLD first=\(first ?? "nil") second=\(second ?? "nil") moved=\(moved ?? "nil")")
        XCTAssertNotNil(moved, "the idle control let go and the Reel went on")
        XCTAssertFalse(save.exists, "Save let go")
    }

    /// A lit control holds autoplay: a video that ends while Save is lit plays again rather than
    /// moving on, and once Save lets go the next end moves on (Fable round 10).
    func testReelLitControlHoldsAutoplay() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjfakeend", "3"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        let first = waitForValue(surface, notIn: [nil, ""], seconds: 10)
        XCUIRemote.shared.press(.right)
        let save = app.descendants(matching: .any)["pnvSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 2) && save.isSelected, "Right lights Save")
        let held = surface.value as? String
        // Two "ends" pass while Save is lit: the video stays.
        kjPause(7)
        XCTAssertTrue(save.isSelected, "Save is still lit")
        XCTAssertEqual(surface.value as? String, held, "a lit control holds autoplay")
        // Left lets go; the next end moves on.
        XCUIRemote.shared.press(.left)
        let moved = waitForValue(surface, notIn: [held], seconds: 20) // CI loads the next video slowly
        print("PNVAUTOHOLD first=\(first ?? "nil") held=\(held ?? "nil") moved=\(moved ?? "nil")")
        XCTAssertNotNil(moved, "with nothing lit, the end moves on")
    }

    /// A lit control lets go after 10 s even while the viewer wakes with no press, as a short
    /// clip's loop makes it do (Fable round 9): the idle timer counts presses, not wakes.
    func testReelLitControlLetsGoUnderAWakePulse() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjwakepulse", "YES"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["pnvViewerSurface"].waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(3)
        XCUIRemote.shared.press(.right)
        let save = app.descendants(matching: .any)["pnvSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 2) && save.isSelected, "Right lights Save")
        let lit = Date()
        while save.exists, Date().timeIntervalSince(lit) < 16 { kjPause(0.5) }
        print("PNVPULSE let go after \(Int(Date().timeIntervalSince(lit))) s")
        XCTAssertFalse(save.exists, "Save let go within 16 s although the viewer woke every 2 s")
    }

    /// A deal that opens on a broken video skips it forward; after a Down onto it, on back.
    func testReelSkipsABrokenFirstVideoBothWays() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjbrokenvideos", "first"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        let first = waitForValue(surface, notIn: [nil, ""], seconds: 10)
        // Read while the first is still failing: a `first` that is really the second (read late)
        // would let short clips pass every later check with no skip run.
        let state = app.descendants(matching: .any)["pnvViewerState"]
        XCTAssertTrue(state.exists && !state.label.contains("Loading"), "the first video shows its failure: \(state.label)")
        let second = waitForValue(surface, notIn: [first, nil, ""], seconds: 8)
        XCTAssertNotNil(second, "the broken first was skipped on to the second")
        // Down onto the broken first: it must show, then be skipped on back, round to the last
        // video loaded, never forward to the second again (Down must work both ways).
        XCUIRemote.shared.press(.down)
        let back = waitForValue(surface, notIn: [second], seconds: 5)
        XCTAssertEqual(back, first, "Down went back onto the first video")
        let landed = waitForValue(surface, notIn: [first], seconds: 8)
        print("PNVFWD first=\(first ?? "nil") second=\(second ?? "nil") landed=\(landed ?? "nil")")
        XCTAssertNotNil(landed, "the broken first was skipped after the Down")
        XCTAssertNotEqual(landed, second, "after a Down a broken first video is skipped on back, not forward")
    }

    /// A video the device cannot decode (VP9 on the Apple TV HD) says so and the Reel moves on;
    /// these do not stop it after two (owner, 2026-11-20: "some videos are showing as black").
    func testReelSkipsAVideoTheTVCannotDecode() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjundecodable", "YES"]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        let said = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'cannot play on this Apple TV'")).firstMatch
        // Watched from the moment the viewer opens, so the first video is counted too.
        var seen: [String] = []
        var saidIt = false
        let end = Date().addingTimeInterval(45)
        while Date() < end {
            if let now = surface.value as? String, !now.isEmpty, seen.last != now { seen.append(now) }
            if !saidIt { saidIt = said.exists }
            kjPause(0.3)
        }
        print("PNVCODEC \(seen.count) \(seen)")
        XCTAssertTrue(saidIt, "an undecodable video says so")
        // Live data: a Khajistan TV row in the deal asks a signed-out viewer to sign in, and the
        // Reel waits there (as before this change). Otherwise eight are skipped, and it stops on
        // the ninth.
        if let stop = seen.firstIndex(where: { $0.hasPrefix("ktv-") }) {
            XCTAssertEqual(stop, seen.count - 1, "the Reel stops at the Khajistan TV row's sign-in")
            XCTAssertLessThanOrEqual(seen.count, 9)
        } else {
            XCTAssertEqual(seen.count, 9, "eight undecodable videos skipped in a row, then the Reel stops on the ninth")
        }
    }

    /// On a shelf (not the Reel) Left from the first object stays put: only the Reel comes round.
    func testShelfLeftFromTheFirstStaysPut() {
        let app = launch()
        dismissNotice(app)
        let tile = tiles(app).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 60), "The shelves must show tiles")
        XCTAssertTrue(kjFocus(tile, app: app), "a tile takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "the tile opens the viewer")
        kjPause(2)
        let first = surface.value as? String
        XCUIRemote.shared.press(.left); kjPause(2)
        XCTAssertEqual(surface.value as? String, first, "Left from a shelf's first object stays put")
        XCUIRemote.shared.press(.right)
        XCTAssertNotNil(waitForValue(surface, notIn: [first], seconds: 8), "Right moves on, so the check above could fail")
    }

    /// The surface's value once it is none of `values`, polled every 0.25 s; nil if it never is.
    private func waitForValue(_ element: XCUIElement, notIn values: [String?], seconds: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let now = element.value as? String
            if !values.contains(now) { return now }
            kjPause(0.25)
        }
        return nil
    }

    private func reelSkipsTwoBrokenVideosThenStops(_ broken: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "picsvids", "-kjbrokenvideos", broken]
        kjLaunch(app)
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        var seen: [String] = []
        let end = Date().addingTimeInterval(30)
        while Date() < end {
            if let now = surface.value as? String, !now.isEmpty, seen.last != now { seen.append(now) }
            kjPause(0.3)
        }
        print("PNVSKIP \(seen)")
        XCTAssertEqual(seen.count, 3, "two skips, then the Reel stays on the third broken video")
    }

    /// The reel (owner, 2026-11-14): Reel opens every region as one stream of videos; on its strip
    /// Shuffle deals again and stays on, and Region steps to a region. It moves as Transmission
    /// does (owner, 2026-11-20): Up the next video, Down the one before, Right lights the controls.
    func testReelShufflesPicksARegionAndNeverEnds() {
        let app = launch()
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(2)
        // At rest the Reel shows one line and no controls (owner, 2026-11-20).
        let save = app.descendants(matching: .any)["pnvSave"]
        let start = surface.value as? String
        XCTAssertFalse((start ?? "").isEmpty, "the Reel shows a video")
        XCTAssertFalse(save.exists, "no controls at rest")
        let line = app.descendants(matching: .any)["pnvReelLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the Reel shows its one line")
        XCTAssertTrue(line.label.hasPrefix("@"), "the line names the account: \(line.label)")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Khajistan Pics/Vids'")).firstMatch.exists,
                       "no status band in the Reel")
        // A press that must not change the video: compared with the video just before it, since
        // the Reel plays on by itself and a short clip can end between two checks.
        func keeps(_ button: XCUIRemote.Button, _ note: String) {
            let before = surface.value as? String
            XCUIRemote.shared.press(button); kjPause(0.6)
            XCTAssertEqual(surface.value as? String, before, note)
        }
        // Left with nothing lit does nothing. (Down on the first video is proved in
        // testReelSkipsBackwardAfterDown, where the first video is known to play.)
        keeps(.left, "Left with nothing lit does not change the video")
        XCTAssertFalse(save.exists, "Left with nothing lit lights nothing")
        // Right lights Save and does not change the video; Left from Save lets go.
        keeps(.right, "Right does not change the video")
        XCTAssertTrue(save.isSelected, "Right lights Save")
        keeps(.left, "Left does not change the video")
        XCTAssertFalse(save.exists, "Left from Save lets go")
        // Right lights Save again; two more reach Shuffle.
        for _ in 0..<3 { XCUIRemote.shared.press(.right); kjPause(0.5) }
        let shuffle = app.descendants(matching: .any)["pnvReelShuffle"]
        // Shuffle is on from the start on the Apple TV, and Select deals again rather than turning
        // it off (owner, 2026-11-14: "shuffle everytime").
        XCTAssertEqual((shuffle.value as? String)?.lowercased(), "on", "Shuffle starts on")
        let before = surface.value as? String
        XCUIRemote.shared.press(.select); kjPause(4)
        XCTAssertEqual((shuffle.value as? String)?.lowercased(), "on", "Select keeps Shuffle on")
        XCTAssertNotEqual(surface.value as? String, before, "Select deals the reel again")
        kjScreenshot("pv-reel-01-shuffled", app: app)
        XCUIRemote.shared.press(.right); kjPause(0.5)
        let region = app.descendants(matching: .any)["pnvReelRegion"]
        // The Reel is videos only (owner, 2026-11-14): step to Mashriq, which has thousands.
        for _ in 0..<12 where (region.value as? String)?.lowercased() != "mashriq" {
            XCUIRemote.shared.press(.select); kjPause(3)
        }
        XCTAssertEqual((region.value as? String)?.lowercased(), "mashriq", "Region steps to Mashriq")
        kjScreenshot("pv-reel-02-region", app: app)
        // Region is the last control: a further Right stays on it.
        XCUIRemote.shared.press(.right); kjPause(0.6)
        XCTAssertTrue(region.isSelected, "Right on Region stays on Region")
        let beforeUp = surface.value as? String
        XCUIRemote.shared.press(.up); kjPause(1.5)
        // Up with a control lit lets go and moves on, as Channel Up does.
        XCTAssertFalse(region.exists, "Up lets go of the lit control")
        XCTAssertNotEqual(surface.value as? String, beforeUp, "Up with a control lit still moves on")
        var last = surface.value as? String
        var seen = Set([last].compactMap { $0 })
        var shown: [String] = []
        for press in 1...22 {
            // Up is the next video, as Channel Up on Transmission (owner, 2026-11-20).
            XCUIRemote.shared.press(.up)
            kjPause(1.5)
            let now = surface.value as? String
            XCTAssertNotEqual(now, last, "Up \(press) moved on")
            // The surface names the kind on show in debug builds: the Reel shows nothing but video.
            XCTAssertEqual(surface.label, "video", "Up \(press) is a video, not a picture")
            if let now { shown.append(now) }
            if let now { seen.insert(now) }
            last = now
        }
        // Every press moved on. The wrap past a stream's end is proven without live data in
        // ios/Tests/PnvRetry; no bound here rests on the region's count.
        print("PNVREEL distinct \(seen.count) of 23 shown")
        // Down goes back to a video already shown, as Channel Down.
        let beforeDown = surface.value as? String
        XCUIRemote.shared.press(.down); kjPause(1.5)
        let afterDown = surface.value as? String
        XCTAssertNotEqual(afterDown, beforeDown, "Down moves")
        // The one before the last Up, or the last shown if a clip ended just before the press.
        XCTAssertTrue(afterDown == shown.dropLast().last || afterDown == shown.last,
                      "Down goes back one video: \(afterDown ?? "nil")")
        kjScreenshot("pv-reel-03-came-round", app: app)
    }

    /// The reel plays on by itself (owner, 2026-11-19: reel should auto play the next video): with
    /// no press at all, the video on screen gives way to the next one when it ends.
    func testReelPlaysTheNextVideoByItself() {
        let app = launch()
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(2)
        // Live data: a Khajistan TV programme (ktv-) runs for many minutes, past this test's wait.
        // Step on to a short clip first; the end of a clip is what is being proved.
        for _ in 0..<6 where (surface.value as? String ?? "").hasPrefix("ktv-") {
            XCUIRemote.shared.press(.up); kjPause(2)
        }
        // Live data: clips run from seconds to minutes. Give each clip 90 s to end by itself; a
        // longer one is passed with Up and the next clip is watched instead, three at most.
        var first = surface.value as? String
        XCTAssertFalse((first ?? "").isEmpty, "the Reel shows a video")
        var now = first
        var waited = 0.0
        for attempt in 0..<3 {
            waited = 0
            while now == first, waited < 90 {
                kjPause(2); waited += 2
                now = surface.value as? String
            }
            if now != first || attempt == 2 { break }
            XCUIRemote.shared.press(.up); kjPause(3)
            first = surface.value as? String
            now = first
        }
        print("PNVAUTOPLAY \(first ?? "nil") -> \(now ?? "nil") after \(Int(waited)) s")
        XCTAssertNotEqual(now, first, "the next video started with no press")
        kjScreenshot("pv-reel-autoplay", app: app)
    }
}
