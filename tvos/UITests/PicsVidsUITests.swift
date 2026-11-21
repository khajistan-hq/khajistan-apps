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

    /// The region with the fewest videos on the day, and how many: Anatolia went from 48 to over
    /// 500 on 2026-11-20 when one account was added, so a fixed region cannot carry this test.
    /// Asks what the app asks (pnv_accounts, then a count of each region's videos in pnv_media).
    private func smallestVideoRegion() throws -> (label: String, videos: Int) {
        // The app's own public anon key (Config.swift); it reads only what the site serves.
        let key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFvanlzZWdlZGR6dHN4ZG1oamZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE2Nzc1MjM5MjQsImV4cCI6MTk5MzA5OTkyNH0.iz8hhr1TYYLWk9HyI0b_yxqlzGJgyuXKsBO_2_kuQ94"
        func ask(_ query: String, count: Bool) throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: URL(string: "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/" + query)!)
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if count { request.setValue("count=exact", forHTTPHeaderField: "Prefer") }
            var answer: (Data?, URLResponse?, Error?)
            let done = expectation(description: query)
            URLSession.shared.dataTask(with: request) { answer = ($0, $1, $2); done.fulfill() }.resume()
            wait(for: [done], timeout: 30)
            guard let data = answer.0, let http = answer.1 as? HTTPURLResponse, (200...206).contains(http.statusCode) else {
                throw XCTSkip("the archive did not answer \(query): \(String(describing: answer.2))")
            }
            return (data, http)
        }
        struct Account: Decodable { let region_token: String?; let account_key: String }
        let roster = try JSONDecoder().decode([Account].self, from: ask("pnv_accounts?select=region_token,account_key", count: false).0)
        // PnvRegions.fold and .label, for the regions the strip names.
        let labels = ["arabia": "Mashriq", "persia": "Persia", "khorasan": "Khorasan", "indus": "Indus",
                      "egypt": "Maghreb", "anatolia": "Anatolia", "caucasus": "Caucasus", "qafqaz": "Caucasus", "horn": "Horn of Africa"]
        var keys: [String: [String]] = [:]
        for account in roster {
            guard let raw = account.region_token, !raw.isEmpty else { continue }
            keys[raw == "egypt-nile" ? "arabia" : raw, default: []].append(account.account_key)
        }
        var best: (label: String, videos: Int)?
        for (token, accountKeys) in keys {
            guard let label = labels[token] else { continue }
            let list = accountKeys.map { "\"\($0)\"" }.joined(separator: ",")
            let query = "pnv_media?select=media_key&kind=eq.video&limit=1&account_key=in.(" + list + ")"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let range = try ask(query, count: true).1.value(forHTTPHeaderField: "Content-Range") ?? ""
            guard let n = Int(range.split(separator: "/").last ?? ""), n > 1 else { continue }
            if best == nil || n < best!.videos { best = (label, n) }
        }
        return try XCTUnwrap(best, "no region has two or more videos")
    }

    /// The Reel comes round at a stream's end rather than stopping. It walks the region with the
    /// fewest videos on the day until an object comes back; the bound is that count plus a margin.
    func testReelComesRoundAtTheEndOfASmallRegion() throws {
        let target = try smallestVideoRegion()
        print("PNVREEL smallest region \(target.label): \(target.videos) videos")
        let app = launch()
        dismissNotice(app)
        let reel = app.buttons["pnvReel"]
        XCTAssertTrue(reel.waitForExistence(timeout: 30), "Reel sits beside the kind tabs")
        XCTAssertTrue(kjFocus(reel, app: app), "Reel takes focus")
        XCUIRemote.shared.press(.select)
        let surface = app.buttons["pnvViewerSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 30), "Reel opens the viewer")
        kjPause(2)
        // Down lights Save; Right three times reaches Region.
        XCUIRemote.shared.press(.down); kjPause(0.5)
        for _ in 0..<3 { XCUIRemote.shared.press(.right); kjPause(0.5) }
        let region = app.descendants(matching: .any)["pnvReelRegion"]
        for _ in 0..<12 where (region.value as? String) != target.label {
            XCUIRemote.shared.press(.select); kjPause(3)
        }
        XCTAssertEqual(region.value as? String, target.label, "Region steps to \(target.label)")
        XCUIRemote.shared.press(.up); kjPause(1)
        var last = surface.value as? String
        var seen = Set([last].compactMap { $0 })
        var cameRound = false
        // Until the first object seen twice: the region's end, passed.
        for press in 1...(target.videos + 20) {
            XCUIRemote.shared.press(.right)
            kjPause(1.2)
            let now = surface.value as? String
            XCTAssertNotEqual(now, last, "Right \(press) moved on")
            last = now
            if let now, !seen.insert(now).inserted { cameRound = true; break }
        }
        print("PNVREEL \(target.label) came round after \(seen.count) distinct")
        XCTAssertTrue(cameRound, "past the end the stream comes round and shows an object again")
    }

    /// The reel (owner, 2026-11-14): Reel opens every region as one stream of videos; on its strip
    /// Shuffle deals again and stays on, and Region steps to a region; Right keeps moving on.
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
        // Down lights Save; Right twice reaches Shuffle.
        XCUIRemote.shared.press(.down); kjPause(0.5)
        XCUIRemote.shared.press(.right); kjPause(0.5)
        XCUIRemote.shared.press(.right); kjPause(0.5)
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
        XCUIRemote.shared.press(.up); kjPause(1)
        var last = surface.value as? String
        var seen = Set([last].compactMap { $0 })
        for press in 1...22 {
            XCUIRemote.shared.press(.right)
            kjPause(1.5)
            let now = surface.value as? String
            XCTAssertNotEqual(now, last, "Right \(press) moved on")
            // The status band names the kind; the Reel shows nothing but video.
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'picture'")).firstMatch.exists,
                           "Right \(press) is a video, not a picture")
            if let now { seen.insert(now) }
            last = now
        }
        // Every press moved on. The wrap past a stream's end is proven without live data in
        // ios/Tests/PnvRetry; no bound here rests on the region's count.
        print("PNVREEL distinct \(seen.count) of 23 shown")
        kjScreenshot("pv-reel-03-came-round", app: app)
    }
}
