import XCTest

/// The dancer, photographed while he dances. Debug builds expose his state as the value of the
/// "dancer" element ("stage=on move=Twerk beat=0.41 …", or "stage=absent" when no tap was made);
/// the screenshots are the record, kept with `.keepAlways`.
final class DancerUITests: XCTestCase {
    /// A channel 2 mix on public storage: the same kind of file tv-play hands the app for the sound channel.
    private let channelTwoMix = "https://qojysegeddztsxdmhjfb.supabase.co/storage/v1/object/public/audio/dirty-desi-funk-96.mp3"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dancer(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "dancer").firstMatch
    }

    private func status(_ app: XCUIApplication) -> String {
        let element = dancer(app)
        return element.exists ? (element.value as? String ?? "") : "no-element"
    }

    /// Waits until the dancer is on stage (entering, dancing or on a break) and returns his status.
    @discardableResult
    private func waitForDancing(_ app: XCUIApplication, timeout: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            last = status(app)
            if ["stage=enter", "stage=on", "stage=smoke"].contains(where: last.hasPrefix) { return last }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return last
    }

    /// Ten seconds of the dancer, a frame every 1.25 s, each named with what he was doing.
    private func photograph(_ prefix: String, _ app: XCUIApplication) -> [String] {
        var seen: [String] = []
        for i in 0..<8 {
            Thread.sleep(forTimeInterval: 1.25)
            let now = status(app)
            seen.append(now)
            let short = now.split(separator: " ").prefix(2).joined(separator: "-")
            shot(String(format: "%@-%02d-%@", prefix, i, short), app)
        }
        print("DANCER \(prefix): " + seen.joined(separator: " | "))
        return seen
    }

    // MARK: - Channel 2's kind of file, on every skin

    private func soundCheck(skin: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-kjsoundtest", channelTwoMix, "-kjsoundtestat", "600", "-kjskin", skin]
        app.launch()
        XCTAssertTrue(dancer(app).waitForExistence(timeout: 30), "the dancer layer must be on screen")
        let first = waitForDancing(app, timeout: 60)
        XCTAssertTrue(first.hasPrefix("stage=enter") || first.hasPrefix("stage=on") || first.hasPrefix("stage=smoke"),
                      "the dancer must come on to a channel 2 mix on \(skin); last status: \(first)")
        let seen = photograph("sound-\(skin)", app)
        XCTAssertTrue(seen.contains { $0.hasPrefix("stage=on") || $0.hasPrefix("stage=enter") || $0.hasPrefix("stage=smoke") },
                      "the dancer must be on stage while photographed on \(skin)")
        app.terminate()
    }

    func testChannelTwoMixDay() { soundCheck(skin: "day") }
    func testChannelTwoMixGrove() { soundCheck(skin: "grove") }
    func testChannelTwoMixSmut() { soundCheck(skin: "smut") }

    // MARK: - The receiver's radio

    /// Indus → Radio → the channel `id`, walking the four-column grid in a snake.
    private func focused(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    private func openRadio(_ ids: [String], skin: String, _ app: XCUIApplication) -> String? {
        app.launchArguments = ["-kjskin", skin]
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        guard regions.firstMatch.waitForExistence(timeout: 60) else { return nil }
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 where !focusedRegion.exists { XCUIRemote.shared.press(.down) }
        for _ in 0..<40 where focusedRegion.exists && focusedRegion.identifier != "region-indus" {
            XCUIRemote.shared.press(.right)
        }
        print("DANCER nav region: \(focused(app))")
        XCUIRemote.shared.press(.select)

        let shelf = app.descendants(matching: .any)["shelf-radio"]
        guard shelf.waitForExistence(timeout: 60) else { shot("nav-no-radio", app); return nil }
        print("DANCER nav channels: \(focused(app))")
        // A region is shelves, television above radio. Focus may start in the top bar; down enters
        // the first shelf. Each shelf is lazy: a card far along does not exist until focus brings
        // it on screen, so the walk reads the focused identifier rather than looking the card up.
        // It goes right along a shelf to its end, down to the next, and back left along that.
        let wanted = Set(ids.map { "channel-\($0)" })
        for _ in 0..<3 where !focused(app).hasPrefix("channel-") { XCUIRemote.shared.press(.down); kjPause(0.5) }
        var found: String?
        var press: XCUIRemote.Button = .right
        walk: for _ in 0..<4 {
            var last = ""
            for _ in 0..<80 {
                let now = focused(app)
                if wanted.contains(now) { found = now; break walk }
                if now == last { break }
                last = now
                XCUIRemote.shared.press(press)
                kjPause(0.45)
            }
            XCUIRemote.shared.press(.down)
            kjPause(0.6)
            press = press == .right ? .left : .right
        }
        guard let hit = found else { print("DANCER nav lost at \(focused(app))"); shot("nav-lost", app); return nil }
        let id = String(hit.dropFirst("channel-".count))
        XCUIRemote.shared.press(.select)
        return id
    }

    /// A Pakistani FM station on a live MP3 mount, played through LiveRadio: the signal must be
    /// readable, and the dancer comes on when what is playing carries a beat. Live radio may be
    /// talking at that minute, so the beat is recorded rather than required; the signal is required.
    func testRadioDancer() {
        let app = XCUIApplication()
        let id = openRadio(["pbc-fm-101-lahore", "radio-in-punjab-rocks-radio", "radio-pk-cityfm89"], skin: "day", app)
        XCTAssertNotNil(id, "a progressive radio channel must open")
        XCTAssertTrue(dancer(app).waitForExistence(timeout: 30))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, status(app).hasPrefix("stage=absent") { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertFalse(status(app).hasPrefix("stage=absent"), "a live radio mount must be readable (\(status(app)))")
        let first = waitForDancing(app, timeout: 40)
        print("DANCER radio \(id ?? "-") first: \(first)")
        _ = photograph("radio-\(id ?? "none")", app)
        app.terminate()
    }

    /// Saut-ul-Quran: recitation. The dancer must never appear, and no tap is made at all.
    func testReverentChannelHasNoDancer() {
        let app = XCUIApplication()
        let id = openRadio(["pbc-saut-ul-quran"], skin: "day", app)
        XCTAssertEqual(id, "pbc-saut-ul-quran", "the recitation channel must open")
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 30))
        // The negative case means something only while the recitation is actually playing.
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, state.label != "Playing" { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertEqual(state.label, "Playing", "the recitation channel must be playing for the check to count")
        var seen = Set<String>()
        for i in 0..<20 {
            Thread.sleep(forTimeInterval: 1)
            seen.insert(status(app).split(separator: " ").first.map(String.init) ?? "")
            if i == 5 || i == 19 { shot(String(format: "reverent-%02d", i), app) }
        }
        print("DANCER reverent: \(seen.sorted())")
        XCTAssertTrue(seen.isSubset(of: ["stage=absent"]), "no tap and no dancer on recitation: \(seen.sorted())")
        app.terminate()
    }
}
