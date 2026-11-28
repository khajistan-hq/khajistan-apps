import XCTest

/// The Receiver's guide and radio's Now Playing, in each skin. A television channel opens; Up
/// lights CC and Right walks to Guide on the strip (after Like); Select opens the guide with LIVE
/// on the channel playing; Down and Select tune the next row. On the picture Down opens the guide,
/// and nothing else does (the players' remote map, 2026-11-28). Then Menu back to the region, and a radio
/// station shows NOW PLAYING with its name.
final class ReceiverGuideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDay() throws { try walk("day") }
    func testGrove() throws { try walk("grove") }
    func testSmut() throws { try walk("smut") }

    /// A dead channel moves on by itself, an open guide holds that move, and Select on the row
    /// already on screen closes the guide as Back does, so the move goes ahead (PR 58). Every
    /// Indus television channel is made to fail (`-kjdeadchannels`, debug builds only).
    func testSelectOnTheDeadChannelInTheGuideMovesOn() throws {
        let shard = URL(fileURLWithPath: kjRecordedFixtures).appendingPathComponent("data/open-frequencies/regions/indus.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: shard)) as? [String: Any]
        let dead = (root?["channels"] as? [[String: Any]] ?? [])
            .filter { $0["mediaType"] as? String == "tv" }.compactMap { $0["id"] as? String }
        XCTAssertFalse(dead.isEmpty, "the recorded Indus list has television")
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", "day", "-kjdeadchannels", dead.joined(separator: ",")]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(focusedChannel.exists, "the remote reaches a channel")
        XCUIRemote.shared.press(.select)

        let current = app.staticTexts["currentChannel"]
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        let start = current.label
        XCTAssertTrue(dead.contains(start), "a television channel opened: \(start)")
        let failed = NSPredicate { _, _ in !["", "Playing", "Paused"].contains(state.label) && !state.label.hasPrefix("Connecting") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: failed, object: nil)], timeout: 20), .completed,
                       "the dead channel fails")
        // Within the 3 s before the move: Down on a failed picture opens the guide, which holds it.
        XCUIRemote.shared.press(.down)
        let guide = app.descendants(matching: .any)["receiverGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the failed picture opens the guide")
        let live = app.descendants(matching: .any)["guide-\(start)"]
        XCTAssertTrue(live.waitForExistence(timeout: 5) && live.isSelected, "the guide opens on the dead channel")
        kjPause(5)
        XCTAssertEqual(current.label, start, "no move while the guide is open")
        kjScreenshot("dead-g1-guide-holds", app: app)
        // Select on that same row: the guide closes and the move goes ahead.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Select on the row on screen closes the guide")
        let moved = NSPredicate { _, _ in current.label != start }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 20), .completed,
                       "Select on the dead channel's row moves on, as Back does")
        kjScreenshot("dead-g2-moved-on", app: app)
    }

    /// A region with no channel of the medium says so in the guide, inside the rows' space, which
    /// keeps the height the last region's rows had. Dakhan has no television in the recorded list,
    /// and only the extended atlas reaches it.
    func testAnEmptyRegionSaysSoInTheGuide() throws {
        // A live run reads the live lists, where Dakhan may have television.
        try XCTSkipIf(kjLiveMedia, "needs the recorded Dakhan list, which has no television")
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", "day", "-kj.extendedAtlas", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["currentChannel"].waitForExistence(timeout: 15))
        try kjTuneUntilPlaying(app)
        // Down on the bare picture opens the guide, once the strip has gone.
        XCTAssertTrue(app.descendants(matching: .any)["captionsControl"].waitForNonExistence(timeout: 15))
        XCUIRemote.shared.press(.down)
        let guide = app.descendants(matching: .any)["receiverGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the bare picture opens the guide")
        let region = app.staticTexts["guideRegion"]
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        kjPause(1)
        var before = guide.frame.minY
        for _ in 0..<40 where !region.label.contains("Dakhan") {
            before = guide.frame.minY
            XCUIRemote.shared.press(.right)
            kjPause(0.8)
        }
        XCTAssertTrue(region.label.contains("Dakhan"), "Right in the guide reaches Dakhan: \(region.label)")
        // Inside the guide: the strip can print a "No captions: …" line of its own.
        let none = guide.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No television in'")).firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 10), "the guide says Dakhan has no television")
        XCTAssertGreaterThan(none.frame.width, 100, "the line is drawn, not laid out in no width: \(none.frame)")
        XCTAssertTrue(guide.frame.contains(none.frame), "the line sits inside the guide panel: \(none.frame) in \(guide.frame)")
        XCTAssertGreaterThan(none.frame.minY, region.frame.maxY, "the line sits under the region name, in the rows' space")
        XCTAssertEqual(guide.frame.minY, before, accuracy: 2, "the panel keeps the height the region before had")
        kjScreenshot("guide-empty-region", app: app)
    }

    private func walk(_ skin: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", skin]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        // Indus carries the most television and radio.
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)

        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'"))
        XCTAssertTrue(tv.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        // Focus may start in the top bar; down enters the first shelf, television.
        let focusedChannel = tv.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !focusedChannel.exists { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(focusedChannel.exists, "the remote reaches a channel")
        kjScreenshot("\(skin)-g1-region", app: app)
        XCUIRemote.shared.press(.select)

        let current = app.staticTexts["currentChannel"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        // A dead carrier's strip cannot be lit, and the walk then falls short of Guide.
        try kjTuneUntilPlaying(app)
        let start = current.label
        let guideControl = app.buttons["guideControl"]
        XCTAssertTrue(guideControl.waitForExistence(timeout: 30), "the strip offers the guide once the channel plays")
        // The apps print no "broadcast by" line; the website does (owner, 2026-11-16).
        let broadcastBy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'broadcast by'"))
        XCTAssertEqual(broadcastBy.count, 0, "the strip prints no 'broadcast by' line: \(broadcastBy.allElementsBoundByIndex.map(\.label))")
        // The strip hides after 2.6 s idle, and the first press then only wakes it: on a busy
        // runner the third Right fell one short of Guide (CI 2026-10-29, Grove; locally, Smut).
        kjPause(3)   // the picture comes up first; presses during "Tuning" landed as the strip arrived
        // Up lights the strip's first control (CC); right walks to Like, then Guide.
        XCUIRemote.shared.press(.up)
        kjPause(0.6)
        for _ in 0..<4 where !guideControl.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(guideControl.isSelected, "Up then right lights Guide, after CC and Like")
        // Select on the lit Guide control opens the guide; Menu closes it and lets go of the control.
        XCUIRemote.shared.press(.select)
        let guide = app.descendants(matching: .any)["receiverGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Select on Guide opens the guide")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
        kjPause(0.6)
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of the control that opened it")
        // Up lights CC and never opens the guide. Left on CC, the first control, stays on it
        // (owner, 2026-11-07); Down lets go of it, and does not open the guide on that press.
        let captions = app.descendants(matching: .any)["captionsControl"]
        XCUIRemote.shared.press(.up)
        kjPause(0.6)
        XCTAssertTrue(captions.isSelected, "Up lights CC")
        XCTAssertFalse(guide.exists, "Up does not open the guide")
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertTrue(captions.isSelected, "Left on the first control stays on it")
        XCTAssertFalse(guide.exists, "Left on CC does not open the guide")
        XCTAssertEqual(current.label, start, "walking the strip changes no channel")
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertFalse(captions.isSelected, "Down lets go of the lit control")
        XCTAssertFalse(guide.exists, "the Down that lets go does not open the guide")
        // Down on the bare picture opens the guide (2026-11-28): wait for the strip to go.
        XCTAssertTrue(captions.waitForNonExistence(timeout: 10), "the strip hides over a playing picture")
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the bare picture opens the guide")
        // It rises from the bottom (owner, 2026-11-14): the panel sits low, reaches the bottom
        // edge and spans the screen, with the picture left in view above it.
        kjPause(0.6)
        let screen = app.frame
        XCTAssertGreaterThan(guide.frame.minY, screen.height * 0.25, "the guide leaves the picture above it")
        XCTAssertEqual(guide.frame.maxY, screen.maxY, accuracy: 2, "the guide reaches the bottom edge")
        XCTAssertGreaterThan(guide.frame.width, screen.width * 0.9, "the guide spans the screen")
        let live = app.descendants(matching: .any)["guide-\(start)"]
        XCTAssertTrue(live.exists && live.label.contains("Live"), "LIVE marks the channel playing: \(live.label)")
        XCTAssertTrue(live.isSelected, "the guide opens on the channel playing")
        kjPause(1)
        kjScreenshot("\(skin)-g2-guide", app: app)
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertFalse(live.isSelected, "Down lights the next row")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Select closes the guide and tunes")
        let moved = NSPredicate { _, _ in current.label != start }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 30), .completed,
                       "the row chosen in the guide is tuned")
        kjPause(2)
        kjScreenshot("\(skin)-g3-tuned", app: app)

        // Right in the guide turns to the next region; Menu closes the guide and lets go of its
        // control, so the strip can hide again.
        XCTAssertTrue(captions.waitForNonExistence(timeout: 10), "the strip hides after the tune")
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Down on the bare picture opens the guide again")
        let region = app.staticTexts["guideRegion"]
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let home = region.label
        XCUIRemote.shared.press(.right)
        let turned = NSPredicate { _, _ in region.label != home }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: turned, object: nil)], timeout: 5), .completed,
                       "Right turns the guide to another region: \(home)")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the next region's channels load into the guide")
        kjScreenshot("\(skin)-g4-next-region", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(guide.waitForNonExistence(timeout: 5), "Menu closes the guide")
        XCTAssertFalse(guideControl.isSelected, "closing the guide lets go of its control")

        // Radio: Back to the region; television is the first shelf and radio the next, so one
        // press down from the channel just left reaches a station. Over a playing picture the
        // first Back hides the strip, as Apple's TV app does, and the second leaves.
        XCUIRemote.shared.press(.menu)
        kjPause(0.6)
        if current.exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(current.waitForNonExistence(timeout: 10), "Back, then Back, leaves the channel")
        XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].waitForExistence(timeout: 10), "Indus has a radio shelf")
        kjPause(1)
        XCUIRemote.shared.press(.down)
        kjPause(1)
        let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(focused.exists, "down reaches the radio shelf")
        XCUIRemote.shared.press(.select)
        let nowPlaying = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] '\u{25CF} Now playing'")).firstMatch
        // A playing station keeps the Apple TV awake: radio plays through the app's own audio
        // engine, which tvOS does not count as playing, and the box slept and stopped the sound
        // (owner, 2026-10-29).
        // The root screen and the full-screen player each carry a readout; the one under a cover
        // may not redraw, so the live one, whichever it is, answers.
        let readouts = app.staticTexts.matching(identifier: "keepAwake")
        func awakeIs(_ value: String) -> Bool {
            let match = NSPredicate { _, _ in readouts.allElementsBoundByIndex.contains { $0.label == value } }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: match, object: nil)], timeout: 5) == .completed
        }
        // Radio is live third-party carriers too: one not playing gives way to the next on the shelf.
        try kjTuneUntilPlaying(app)
        if nowPlaying.waitForExistence(timeout: 40) {
            XCTAssertTrue(awakeIs("on"), "a playing station holds the Apple TV awake")
            kjPause(2)
            kjScreenshot("\(skin)-g4-radio", app: app)
        } else {
            kjScreenshot("\(skin)-g4-radio-not-playing", app: app)
            XCTFail("the station played and showed Now Playing")
        }

        // Menu leaves the station playing, in Sonos's small player under the region; Off stops it.
        XCUIRemote.shared.press(.menu)
        let bar = app.descendants(matching: .any)["radioBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the radio plays on in the small player")
        // The bar names the song in place of "On air" while the station names one (PR 33), so read
        // the state off its Play/Pause control: Pause means playing or tuning.
        XCTAssertEqual(app.buttons["radioBarToggle"].label, "Pause",
                       "the bar says the station is on: \(app.buttons["radioBarName"].label)")
        kjPause(1)
        kjScreenshot("\(skin)-g5-radio-bar", app: app)
        let off = app.buttons["radioBarOff"]
        // Down into the bar first, then right along it. The region's lowest shelf (Films, under
        // radio) can sit level with the bar, and kjFocus, steering by height, walked its posters
        // to the right instead (CI 2026-11-19, run 44633692006).
        let inBar = app.buttons.matching(NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'radioBar'")).firstMatch
        // Every card Down passes on the way must end above the bar: one that runs under it is
        // where focus got stuck (2026-11-19: a focused film card under the full hero ran past it).
        let card = app.buttons.matching(NSPredicate(format: "hasFocus == true AND NOT (identifier BEGINSWITH 'radioBar')")).firstMatch
        var passedFilm = false
        for _ in 0..<8 where !inBar.exists {
            if card.exists {
                if card.identifier.hasPrefix("film-") { passedFilm = true }
                XCTAssertLessThanOrEqual(card.frame.maxY, bar.frame.minY, "\(card.identifier) ends above the bar")
            }
            XCUIRemote.shared.press(.down); kjPause(0.6)
        }
        // Indus's films come from the live On Demand list; without them this walk proves less.
        if !passedFilm { print("KJGUIDE Down passed no film card: the region has no On Demand shelf today") }
        let held = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(inBar.exists, "Down reaches the small player; focus held on "
                      + (held.exists ? "\(held.identifier) at \(held.frame)" : "nothing") + ", bar at \(bar.frame)")
        for _ in 0..<3 where !off.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(off.hasFocus, "the remote reaches the bar's Off")
        XCTAssertTrue(awakeIs("on"), "the station playing on in the small player still holds it awake")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "Off turns the radio off and the bar goes")
        XCTAssertTrue(awakeIs("off"), "with nothing playing the Apple TV may sleep again")
    }

    /// A film opened from a shelf under the radio bar stops the radio, so the bar goes and the
    /// shelf's cards grow back behind the player. Closing the film must find focus on it again
    /// (2026-11-20: posters shrunk under the bar narrowed every card, the shelf slid sideways, and
    /// focus was lost; Menu then left the region).
    func testAFilmOpenedUnderTheRadioBarGetsFocusBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", "day"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["shelf-radio"].waitForExistence(timeout: 60), "Indus has a radio shelf")
        // The films are the site's live On Demand list: no shelf today, nothing to test.
        try XCTSkipUnless(app.descendants(matching: .any)["shelf-vod"].waitForExistence(timeout: 20),
                          "Indus has no On Demand shelf today")
        kjPause(2)
        let focus = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        // Television is the first shelf and radio the next.
        for _ in 0..<8 where !(focus.exists && focus.identifier.hasPrefix("channel-")) { XCUIRemote.shared.press(.down); kjPause(0.5) }
        XCUIRemote.shared.press(.down)
        kjPause(1)
        XCUIRemote.shared.press(.select)
        try kjTuneUntilPlaying(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.descendants(matching: .any)["radioBar"].waitForExistence(timeout: 10), "the radio plays on in the small player")
        kjPause(1)
        for _ in 0..<4 where !(focus.exists && focus.identifier.hasPrefix("film-")) { XCUIRemote.shared.press(.down); kjPause(0.7) }
        XCTAssertTrue(focus.exists && focus.identifier.hasPrefix("film-"), "Down reaches the films")
        // Well along the shelf, where a sideways slide would carry the card off screen.
        for _ in 0..<7 { XCUIRemote.shared.press(.right); kjPause(0.5) }
        let chosen = focus.identifier
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["radioBar"].waitForNonExistence(timeout: 15), "the film stops the radio")
        kjPause(4)
        XCUIRemote.shared.press(.menu)
        let back = NSPredicate { _, _ in focus.exists && focus.identifier == chosen }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 8), .completed,
                       "focus comes back to the film just closed, \(chosen); it is on \(focus.exists ? focus.identifier : "nothing")")
        // The page keeps the bar's shape until the viewer leaves it: the card stays on screen.
        kjPause(2)
        XCTAssertTrue(focus.exists && app.frame.contains(focus.frame), "the film card is on screen after the film closes: \(focus.frame)")
    }
}
