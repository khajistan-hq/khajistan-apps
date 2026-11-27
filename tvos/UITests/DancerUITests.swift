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
        kjLaunch(app)
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

    private func openRadio(_ ids: [String], region: String = "indus", skin: String, recorded: Bool = false,
                           extra: [String] = [], _ app: XCUIApplication) -> String? {
        // `recorded` reads the recorded list, not the live one: the live Indus radio shelf fell to
        // two Indian stations on 2026-11-16, and none of the three Pakistani FM stations was on it.
        app.launchArguments = ["-kjskin", skin] + (recorded ? ["-kjfixturesonly", "YES"] : []) + extra
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        guard regions.firstMatch.waitForExistence(timeout: 60) else { return nil }
        XCTAssertTrue(kjFocusRegion(app, "\(region)"), "focus must reach \(region) in the region list")
        print("DANCER nav region: \(focused(app))")
        XCUIRemote.shared.press(.select)

        let shelf = app.descendants(matching: .any)["shelf-radio"]
        guard shelf.waitForExistence(timeout: 60) else { shot("nav-no-radio", app); return nil }
        print("DANCER nav channels: \(focused(app))")
        // A region is shelves, television above radio. Focus may start in the top bar; down enters
        // the first shelf. Each shelf is lazy: a card far along does not exist until focus brings
        // it on screen, so the walk reads the focused identifier rather than looking the card up.
        // It goes right along each shelf to its end and then left to its start, so a row is read
        // whole wherever Down lands in it: Down from the end of television can land on the first
        // radio card, where a walk only leftward read one card (CI on PR 79, 2026-11-16).
        let wanted = Set(ids.map { "channel-\($0)" })
        for _ in 0..<3 where !focused(app).hasPrefix("channel-") { XCUIRemote.shared.press(.down); kjPause(0.5) }
        var found: String?
        walk: for _ in 0..<4 {
            for press in [XCUIRemote.Button.right, .left] {
                var last = ""
                for _ in 0..<80 {
                    let now = focused(app)
                    if wanted.contains(now) { found = now; break walk }
                    if now == last { break }
                    last = now
                    XCUIRemote.shared.press(press)
                    kjPause(0.45)
                }
            }
            XCUIRemote.shared.press(.down)
            kjPause(0.6)
        }
        guard let hit = found else { print("DANCER nav lost at \(focused(app))"); shot("nav-lost", app); return nil }
        let id = String(hit.dropFirst("channel-".count))
        XCUIRemote.shared.press(.select)
        return id
    }

    /// Pakistani and Punjabi FM stations in the recorded Indus list, in the order the walk reaches
    /// them. The live Indus radio shelf fell to two Indian stations on 2026-11-16, so the recorded
    /// list is read in every run.
    static let radioStations = ["radio-pk-cityfm89", "radio-pk-hum-fm-106-2", "radio-pk-mera-fm-107-4", "radio-in-punjab-rocks-radio"]

    /// An FM station plays: the signal must be readable, and the dancer comes on when what is
    /// playing carries a beat. A station may be talking at that minute, so the beat is recorded
    /// rather than required; the signal is required. By default the station plays the local test
    /// sound through AVPlayer; with `TEST_RUNNER_KJ_LIVE_RECEIVER=1` it plays its live mount
    /// through LiveRadio, and a station whose live carrier is down gives way to the next, three at
    /// most, then the test is skipped (CI 2026-11-01, 11-12).
    func testRadioDancer() throws {
        let run = radioDancer(dead: [], tries: 3)
        // Fewer than three passed over means the run stopped on a failure, already recorded.
        guard run.played == nil, kjLiveMedia, run.tried.count == 3 else { return }
        throw XCTSkip("No radio station's live carrier played, \(run.tried.count) tried: \(run.tried.map { "\($0.id): \($0.why)" }.joined(separator: "; ")). LiveRadio was not proved on this run.")
    }

    /// The path a dead live carrier takes, run on every build: `-kjdeadchannels` makes the first
    /// two stations the walk reaches fail as a dead signal does. The test must move past both, in
    /// order, and check the third.
    func testRadioDancerMovesPastDeadStations() throws {
        // A live run would need the third station's real carrier up; testRadioDancer covers live.
        try XCTSkipIf(kjLiveMedia, "the move past dead stations is proved on the local test sound")
        let dead = Array(Self.radioStations.prefix(2))
        let run = radioDancer(dead: dead, tries: 3)
        XCTAssertEqual(run.tried.map(\.id), dead, "both dead stations are tried and passed over: \(run.tried)")
        XCTAssertEqual(run.played, Self.radioStations[2], "the third station plays and is checked")
    }

    /// Opens up to `tries` stations, one launch each, and checks the first that plays. A station
    /// counts as playing only while it is the channel on screen: the player moves on from a dead
    /// signal by itself 3 s after it fails, and the next channel playing is not this station
    /// playing. A station in `dead`, or a dead live carrier, is passed over; anything else fails
    /// the test (the local test sound not playing, a player stuck connecting, paused or never
    /// opened). Returns the station checked, or nil, with what each passed-over station did.
    private func radioDancer(dead: [String], tries: Int) -> (played: String?, tried: [(id: String, why: String)]) {
        var left = Self.radioStations
        var tried: [(id: String, why: String)] = []
        let extra = dead.isEmpty ? [] : ["-kjdeadchannels", dead.joined(separator: ",")]
        for _ in 0..<tries {
            let app = XCUIApplication()
            guard let id = openRadio(left, skin: "day", recorded: true, extra: extra, app) else {
                XCTFail("a progressive radio channel must open; left: \(left)")
                return (nil, tried)
            }
            left.removeAll { $0 == id }
            let state = app.staticTexts["playerState"]
            let current = app.staticTexts["currentChannel"]
            XCTAssertTrue(state.waitForExistence(timeout: 30))
            var moved = false
            let tuned = Date().addingTimeInterval(45)
            while Date() < tuned {
                if current.exists, current.label != id { moved = true; break }
                if state.label == "Playing" { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            // Read once, before the app is closed: a terminated app's labels read empty.
            let label = state.label
            let on = current.exists ? current.label : ""
            // A move that lands between the loop's last look and this read is a move too.
            if !on.isEmpty, on != id { moved = true }
            if moved || label != "Playing" || on != id {
                let why = moved ? "the player moved on to '\(on)'" : "'\(label)'\(on.isEmpty ? ", no channel on screen" : "")"
                shot("\(id)-not-playing", app)
                app.terminate()
                // A dead signal is a failed player, or one that moved on. Connecting, paused or
                // with no channel on screen is stuck, whatever the station. The declared-dead
                // stations of the proof test go through the same test as a live run's.
                let stuck = !moved && (label == "Connecting…" || label == "Paused" || label.isEmpty || on.isEmpty)
                guard !stuck, kjLiveMedia || dead.contains(id) else {
                    XCTFail("\(id) did not play: \(why)")
                    return (nil, tried)
                }
                tried.append((id, why))
                continue
            }
            XCTAssertTrue(dancer(app).waitForExistence(timeout: 30))
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline, status(app).hasPrefix("stage=absent") { Thread.sleep(forTimeInterval: 0.5) }
            XCTAssertFalse(status(app).hasPrefix("stage=absent"), "a playing radio mount must be readable (\(status(app)))")
            let first = waitForDancing(app, timeout: 40)
            print("DANCER radio \(id) first: \(first) passed over: \(tried)")
            _ = photograph("radio-\(id)", app)
            app.terminate()
            return (id, tried)
        }
        return (nil, tried)
    }

    /// Waits up to 45 s for the station opened to play. When its live carrier is off air the test
    /// is skipped, because a check over silence proves nothing. Only a player in its failed state
    /// skips (a dead carrier, or the simulator offline); one stuck connecting, paused or never
    /// opened is a failure, and returns false.
    private func playsOrSkips(_ id: String, _ app: XCUIApplication) throws -> Bool {
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 30))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, state.label != "Playing" { Thread.sleep(forTimeInterval: 0.5) }
        let stuck = state.label == "Connecting…" || state.label == "Paused" || state.label.isEmpty
        if stuck {
            XCTFail("\(id) neither plays nor fails: \(state.label)")
            app.terminate()
            return false
        }
        if state.label != "Playing" {
            shot("\(id)-not-playing", app)
            app.terminate()
            guard kjLiveMedia else { XCTFail("\(id): the local test video did not play (\(state.label))"); return false }
            throw XCTSkip("\(id)'s live carrier is not playing (\(state.label)); the check is meaningless without playback")
        }
        return true
    }

    /// Quran recitation radio. The dancer must never appear, and no tap is made at all.
    ///
    /// The nightly stream probe takes silent stations off the dial (denylist.json), so no single
    /// station can be named. These are Arabia's Quran stations that are reverent by name and were
    /// published and off the denylist on 2026-11-14; the walk takes whichever it reaches first.
    /// Indus's only one, Saut-ul-Quran, was denylisted that day for two silent nights.
    static let recitation = [
        "territory-saudi-arabia-quran-kareem-radio",
        "uae-sharjah-quran-radio",
        "state-qtv-qa-quraan-radio-2",
        "radio-om-the-holy-quran-radio-fm-93-2",
        "territory-saudi-arabia-nida-al-islam-radio",
    ]

    func testReverentChannelHasNoDancer() throws {
        let app = XCUIApplication()
        guard let id = openRadio(Self.recitation, region: "arabia", skin: "day", app) else {
            // The radio shelf opened but none of the candidates is on it: nothing to test.
            if app.descendants(matching: .any)["shelf-radio"].exists {
                app.terminate()
                throw XCTSkip("no recitation channel from the candidate list is on Arabia's dial")
            }
            XCTFail("the Arabia radio shelf must open")
            return
        }
        XCTAssertTrue(Self.recitation.contains(id), "a recitation channel must open (\(id))")
        // The negative case means something only while the recitation is actually playing.
        guard try playsOrSkips(id, app) else { return }
        var seen = Set<String>()
        for i in 0..<20 {
            Thread.sleep(forTimeInterval: 1)
            seen.insert(status(app).split(separator: " ").first.map(String.init) ?? "")
            if i == 5 || i == 19 { shot(String(format: "reverent-%02d", i), app) }
        }
        print("DANCER reverent: \(seen.sorted())")
        // Since the visualizers, a reverent channel does not mount the dancer at all ("no-element").
        XCTAssertTrue(seen.isSubset(of: ["stage=absent", "no-element"]), "no tap and no dancer on recitation: \(seen.sorted())")
        app.terminate()
    }
}
