import XCTest

/// The browsing screens move as the TV app's do: shelves of cards that a press up or down walks
/// from one to the next, a card that lifts under focus. Walks the Receiver's front, a region, the
/// Transmission page and Pics/Vids in each skin, asserts where focus lands, and keeps a
/// screenshot of each stop (also written to /tmp/kjtv-native-shots, which is how the owner's
/// review of this pass was done).
///
/// The Screening Room's shelf needs vod.json, which is behind the site password: set
/// TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree, as FilmsUITests does.
final class ShelfUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let skins = ["day", "grove", "smut"]

    private func shot(_ name: String, _ app: XCUIApplication) {
        kjScreenshot(name, app: app)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let dir = URL(fileURLWithPath: "/tmp/kjtv-native-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    private func launch(_ skin: String, tab: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-kjskin", skin]
        if let tab { args += ["-kjtab", tab] }
        if let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty {
            args += ["-kjfilms", origin]
        }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, app: XCUIApplication) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            kjPause(0.7)
        }
    }

    func testReceiverFrontAndShelves() {
        for skin in skins {
            let app = launch(skin, tab: "receiver")
            let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "\(skin): the front must draw its regions")
            kjPause(4)
            // Focus starts on the top bar's tab; down reaches the strip.
            for _ in 0..<6 where !focusedID(app).hasPrefix("region-") { press(.down, app: app) }
            XCTAssertTrue(focusedID(app).hasPrefix("region-"), "\(skin): down from the top bar reaches the strip")
            for _ in 0..<30 where focusedID(app) != "region-indus" { press(.right, app: app) }
            XCTAssertEqual(focusedID(app), "region-indus", "\(skin): the walk east along the strip reaches Indus")
            shot("\(skin)-1-receiver-front", app)

            let mixes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mix-'"))
            if mixes.firstMatch.waitForExistence(timeout: 30) {
                press(.down, app: app)
                XCTAssertTrue(focusedID(app).hasPrefix("mix-"), "\(skin): down from the strip lands on the Khajistan Radio shelf, got \(focusedID(app))")
                kjPause(1.2)
                shot("\(skin)-2-receiver-radio-shelf", app)
                press(.right, times: 2, app: app)
                let inRow = focusedID(app)
                XCTAssertTrue(inRow.hasPrefix("mix-"), "\(skin): right walks along the shelf")
                let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
                if films.firstMatch.exists {
                    press(.down, app: app)
                    XCTAssertTrue(focusedID(app).hasPrefix("film-"), "\(skin): down from radio lands on the Screening Room shelf, got \(focusedID(app))")
                    kjPause(4)   // posters arrive
                    shot("\(skin)-3-receiver-films-shelf", app)
                    press(.up, app: app)
                }
                press(.up, app: app)
                XCTAssertTrue(focusedID(app).hasPrefix("region-"), "\(skin): up from the first shelf returns to the strip, got \(focusedID(app))")
            }
            app.terminate()
        }
    }

    func testRegionPageIsShelvesByMedium() {
        for skin in skins {
            let app = launch(skin, tab: "receiver")
            let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
            kjPause(3)
            for _ in 0..<6 where !focusedID(app).hasPrefix("region-") { press(.down, app: app) }
            for _ in 0..<30 where focusedID(app) != "region-indus" { press(.right, app: app) }
            XCTAssertEqual(focusedID(app), "region-indus")
            XCUIRemote.shared.press(.select)
            let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
            XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 60), "\(skin): Indus must list channels")
            kjPause(2)
            // Focus may start in the top bar; down reaches the first shelf.
            for _ in 0..<3 where !focusedID(app).hasPrefix("channel-") { press(.down, app: app) }
            let first = focusedID(app)
            XCTAssertTrue(first.hasPrefix("channel-"), "\(skin): the first card takes focus, got \(first)")
            kjPause(1)
            shot("\(skin)-4-region-television", app)
            XCTAssertTrue(app.descendants(matching: .any)["shelf-tv"].exists, "\(skin): television is a shelf")
            press(.right, times: 3, app: app)
            XCTAssertNotEqual(focusedID(app), first, "\(skin): right walks along the shelf")
            press(.down, app: app)
            let second = focusedID(app)
            XCTAssertTrue(second.hasPrefix("channel-") || second.hasPrefix("film-"), "\(skin): down reaches the next shelf, got \(second)")
            XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].exists, "\(skin): radio is a shelf")
            kjPause(1)
            shot("\(skin)-5-region-radio", app)
            press(.down, app: app)
            kjPause(1)
            shot("\(skin)-6-region-below", app)
            app.terminate()
        }
    }

    private var scheduleFile: String {
        var karachi = Calendar(identifier: .gregorian)
        karachi.timeZone = TimeZone(identifier: "Asia/Karachi")!
        let c = karachi.dateComponents([.year, .month], from: Date())
        let month = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/khajistan-tv/programming-\(month).json").path
    }

    func testTransmissionCards() {
        for skin in skins {
            let app = launch(skin, tab: "transmission", extra: ["-kjschedulefile", scheduleFile])
            let page = app.staticTexts["transmissionState"]
            XCTAssertTrue(page.waitForExistence(timeout: 30))
            for _ in 0..<20 where (page.value as? String) != "Ready" { kjPause(1) }
            XCTAssertEqual(page.value as? String, "Ready")
            for _ in 0..<4 where !focusedID(app).hasPrefix("transmission-channel-") { press(.down, app: app) }
            XCTAssertTrue(focusedID(app).hasPrefix("transmission-channel-"), "\(skin): a channel card takes focus")
            kjPause(1)
            shot("\(skin)-7-transmission", app)
            app.terminate()
        }
    }

    func testPicsVidsTiles() {
        for skin in skins {
            let app = launch(skin, tab: "picsvids")
            let ok = app.buttons["adultNoticeOK"]
            if ok.waitForExistence(timeout: 60) {
                XCTAssertTrue(kjFocus(ok, app: app))
                XCUIRemote.shared.press(.select)
                kjPause(1)
            }
            let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
            XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 60), "\(skin): the stream must show tiles")
            kjPause(6)
            for _ in 0..<6 where !focusedID(app).hasPrefix("tile-") { press(.down, app: app) }
            XCTAssertTrue(focusedID(app).hasPrefix("tile-"), "\(skin): a tile takes focus")
            press(.right, app: app)
            kjPause(1)
            shot("pv-\(skin)-1-shelves", app)
            press(.down, app: app)
            XCTAssertTrue(focusedID(app).hasPrefix("tile-"), "\(skin): down reaches the next region's shelf, got \(focusedID(app))")
            kjPause(2)
            shot("pv-\(skin)-2-second-shelf", app)
            press(.down, times: 2, app: app)
            kjPause(2)
            shot("pv-\(skin)-3-lower-shelves", app)
            // The one filter, above the shelves: Videos narrows every shelf.
            XCTAssertTrue(kjFocus(app.buttons["pnvkind-video"], app: app), "\(skin): Videos takes focus")
            XCUIRemote.shared.press(.select)
            kjPause(8)
            shot("pv-\(skin)-4-videos", app)
            app.terminate()
        }
    }
}
