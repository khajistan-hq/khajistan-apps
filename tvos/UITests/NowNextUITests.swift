import XCTest

/// Now playing and Up next on Transmission (owner, 2026-11-08: "add now playing and up next info
/// on all film and tv channels in the reciever, names need to be standardized"). The strip heads
/// with the programme's standardized title, carries the channel's own name ("Channel 5 · Mehfil",
/// never a show's name standing in for it), and Up next names the next programme.
/// Fixture: two days of the November build, channels 5, 8, 14 and 15, rosters cut to five.
final class NowNextUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var schedule: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-11-08.json").path
    }

    private func open(channel: Int, skin: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00"]
        kjLaunch(app)
        let page = app.staticTexts["transmissionState"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        // The cards sit in a lazy row: the later ones exist once the remote walks to them.
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "channel 1 has a card")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        for _ in 1..<channel {
            XCUIRemote.shared.press(.right)
            kjPause(0.4)
        }
        let card = app.buttons["transmission-channel-\(channel)"]
        XCTAssertTrue(card.waitForExistence(timeout: 10) && card.hasFocus, "focus walks right to channel \(channel)")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["transmissionChannel"].waitForExistence(timeout: 30))
        return app
    }

    private func check(channel: Int, name: String, titles: [String], skin: String) {
        let app = open(channel: channel, skin: skin)
        // The sign-on pigeon flies first; then Select wakes the strip, which hides itself after
        // 2.6 s (OverlayTiming), so the checks and the photograph come straight after the press.
        kjPause(12)
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        kjScreenshot("now-next-c\(channel)-\(skin)", app: app)
        let channelLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Channel \(channel) \u{00B7} \(name)")).firstMatch
        XCTAssertTrue(channelLabel.waitForExistence(timeout: 30), "the strip names Channel \(channel) · \(name)")
        // On screen, not merely in the tree: a hidden strip's text is still in the tree.
        let name = app.staticTexts.matching(identifier: "stripName").firstMatch
        XCTAssertTrue(name.exists && app.frame.intersects(name.frame) && name.frame.height > 0, "the strip's name is on screen")
        // VoiceOver hears "Now playing, <title>".
        XCTAssertTrue(name.label.hasPrefix("Now playing, "), "the headline is announced as now playing: \(name.label)")
        // SwiftUI isolates an interpolated right-to-left name (U+2068 … U+2069); VoiceOver does not speak them.
        let heard = String(name.label.dropFirst("Now playing, ".count)).filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        let shown: String? = titles.contains(heard) ? heard : nil
        XCTAssertNotNil(shown, "the strip heads with one of the slot's standardized titles \(titles), got \(heard)")
        // Up next is on screen, and never names the programme already playing.
        let next = app.descendants(matching: .any).matching(identifier: "upNext").firstMatch
        XCTAssertTrue(next.exists && app.frame.intersects(next.frame), "Up next is on the strip")
        if let shown { XCTAssertFalse(next.label.contains(shown), "Up next repeats the headline: \(next.label)") }
    }

    func testMehfilNamesTheChannelAndTheProgramme() {
        check(channel: 5, name: "Mehfil",
              titles: ["Saang Mahfil E Milad 16 November 2020 Part 1", "Saang Mahfil E Milad 16 November 2020 Part 2"], skin: "day")
    }

    func testJordanTelevisionCarriesItsArabicTitle() {
        check(channel: 14, name: "Jordan Television",
              titles: ["أجواء العيد مع الأطفال… فرحة لا تشبهها فرحة", "أجواء الناس بالعيد من أرشيف برنامج شبابيك 1998",
                       "أجواء تراثية أصيلة من ذاكرة المجالس", "أجواء تعليلة أردنية في المضافة وحديث عن الزراعة",
                       "أجواء سعيدة ولقطات من مهرجان جرش تسعينات القرن الماضي"], skin: "grove")
    }

    func testHomeMoviesIsChannelFifteen() {
        // The fixture gives this slot's second programme the first one's title, so Up next would
        // repeat the headline; it must name the next slot's show instead.
        check(channel: 15, name: "Home Movies",
              titles: ["Kessar's Birthday", "Kotmoman 01", "Kotmoman 02", "Kotmoman 03"], skin: "smut")
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// The lit programme block on a channel's row, if one is lit.
    private func litBlock(_ app: XCUIApplication, channel: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch\(channel)-' AND selected == true")).firstMatch
    }

    /// Up and Down presses change channel while watching (owner, 2026-11-24: "The up and down
    /// button should otherwise be treated as changing the channel"); they never open the guide.
    /// XCUIRemote sends presses only, so the swipe that opens the guide is checked on a device.
    func testUpAndDownPressesChangeChannel() {
        let app = open(channel: 14, skin: "day")
        kjPause(12)
        let tuned = any(app, "transmissionChannel")
        XCTAssertEqual(tuned.label, "14")
        XCUIRemote.shared.press(.up)
        let up = NSPredicate { _, _ in tuned.exists && tuned.label == "15" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: up, object: nil)], timeout: 30), .completed,
                       "an Up press tunes the next channel")
        XCTAssertFalse(any(app, "transmissionGuide").exists, "an Up press does not open the guide")
        kjPause(6)
        XCUIRemote.shared.press(.down)
        let down = NSPredicate { _, _ in tuned.exists && tuned.label == "14" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: down, object: nil)], timeout: 30), .completed,
                       "a Down press tunes the channel before")
        XCTAssertFalse(any(app, "transmissionGuide").exists, "a Down press does not open the guide")
    }

    /// The guide is the whole screen, with the picture in a small window at top left (owner,
    /// 2026-11-24: "Full screen with smaller video icon"). Left from the programme on now lights
    /// the channel's own cell, whose description reads beside the picture; Select there tunes the
    /// window and keeps the guide ("show description of a channel on click"); Select on the
    /// programme on now closes it.
    func testGuideIsFullScreenWithThePictureWindow() {
        let app = open(channel: 5, skin: "day")
        kjPause(12)
        let tuned = any(app, "transmissionChannel")
        XCTAssertEqual(tuned.label, "5")
        XCUIRemote.shared.press(.left)
        let guide = any(app, "transmissionGuide")
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "left on the picture opens the guide")
        kjPause(0.8)
        kjScreenshot("transmission-guide-day", app: app)
        XCTAssertEqual(guide.frame.minY, app.frame.minY, accuracy: 2, "the guide starts at the top of the screen")
        XCTAssertEqual(guide.frame.height, app.frame.height, accuracy: 2, "the guide is the whole screen high")
        XCTAssertEqual(guide.frame.width, app.frame.width, accuracy: 2, "the guide is the whole screen wide")
        let window = any(app, "guidePictureWindow")
        XCTAssertTrue(window.exists, "the picture has a window in the guide")
        XCTAssertLessThan(window.frame.width, app.frame.width * 0.45, "the picture window is small: \(window.frame)")
        XCTAssertLessThan(window.frame.maxY, app.frame.height * 0.45, "the picture window is in the top band: \(window.frame)")
        XCTAssertLessThan(window.frame.maxX, app.frame.width * 0.5, "the picture window is at the left: \(window.frame)")
        XCTAssertGreaterThan(window.frame.width, app.frame.width * 0.25, "the picture window is large enough to watch: \(window.frame)")
        XCTAssertTrue(litBlock(app, channel: 5).exists, "the programme on now on the tuned channel is lit")
        XCTAssertTrue(any(app, "guideChannelLine").label.contains("Qawwali"), "the lit channel's own line reads beside the picture")
        // Left: the channel's own cell, and the panel names the channel.
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertTrue(any(app, "guide-ch5").isSelected, "Left from the programme on now lights the channel's cell")
        XCTAssertFalse(litBlock(app, channel: 5).exists, "no programme is lit while the channel's cell is")
        XCTAssertTrue(any(app, "guideHeadline").label.hasPrefix("Channel 5 \u{00B7} Mehfil"), "the panel names the lit channel: \(any(app, "guideHeadline").label)")
        kjScreenshot("transmission-guide-channel-cell", app: app)
        // Channel 8 is the next one the fixture programmes; 6 and 7 are off air in it.
        for _ in 0..<3 { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(any(app, "guide-ch8").isSelected, "three downs light channel 8's cell")
        XCTAssertTrue(any(app, "guideChannelLine").label.contains("NIRT"), "the panel describes channel 8: \(any(app, "guideChannelLine").label)")
        XCTAssertEqual(tuned.label, "5", "lighting a channel does not tune it")
        // Select on the channel's cell: the window tunes, the guide stays.
        XCUIRemote.shared.press(.select)
        let moved = NSPredicate { _, _ in tuned.exists && tuned.label == "8" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 30), .completed,
                       "Select on a channel's cell tunes the window to it")
        kjPause(1.5)
        XCTAssertTrue(guide.exists, "Select on a channel's cell keeps the guide open")
        XCTAssertTrue(window.exists && window.frame.width < app.frame.width * 0.45, "the picture stays in its window")
        // Channel 8 is "National Iranian Radio and Television", tuned and on air: its name reads
        // whole beside LIVE, never cut (Fable, round 9).
        let longName = any(app, "guide-ch8")
        XCTAssertTrue(longName.label.contains("National Iranian Radio and Television") && longName.label.contains("Live"),
                      "channel 8 is the long name, tuned: \(longName.label)")
        // The combined cell joins its children's values ("cut, cut"), so look for the word.
        XCTAssertFalse((longName.value as? String ?? "").contains("cut"), "channel 8's name is cut: \(String(describing: longName.value))")
        kjScreenshot("guide-long-name-live", app: app)
        // Right: the programme on now. Select there closes the guide on the channel tuned.
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(litBlock(app, channel: 8).exists, "Right from the channel's cell lights the programme on now")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntilGone(guide, 5), "Select on the programme on now closes the guide")
        XCTAssertEqual(tuned.label, "8")
        XCTAssertFalse(window.exists, "the picture is full screen again")
        // Back on the bare picture: right opens the guide too, Back closes it.
        kjPause(8)   // the strip hides 2.6 s after the tune, so right meets the bare picture
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right on the bare picture opens the guide")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilGone(guide, 5), "Back closes the guide")
        XCTAssertEqual(tuned.label, "8", "Back keeps the channel the window was showing")
    }

    /// The guide is a time grid (owner, 2026-11-17: "it needs to be showing schedule on an hourly
    /// basis"): each channel's programmes as blocks along its row, the one on now lit. Right lights
    /// the next programme, Left goes back, never before now. Select on a later programme, or on a
    /// stretch off air, tunes nothing. The guide opens over the off-air card too.
    func testGuideIsATimeGridAndOpensOffAir() {
        let app = open(channel: 5, skin: "day")
        kjPause(12)
        XCUIRemote.shared.press(.left)
        let guide = any(app, "transmissionGuide")
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "left on the picture opens the guide")
        kjPause(0.8)
        kjScreenshot("guide-grid-open", app: app)
        let lit = litBlock(app, channel: 5)
        XCTAssertTrue(lit.exists, "a programme on channel 5 is lit")
        let first = lit.label
        // The lit block is the programme on air (12:10 PKT in the fixture), and the panel beside
        // the picture reads the same title in full.
        let headline = any(app, "guideHeadline")
        XCTAssertTrue(headline.exists, "the guide reads the lit programme beside the picture")
        let title = String(first.split(separator: ",").first ?? "")
        XCTAssertFalse(title.isEmpty)
        XCTAssertTrue(headline.label.hasPrefix(title), "the panel names the lit block: \(headline.label) / \(first)")
        XCTAssertTrue(headline.label.contains("Channel 5"), "the panel's facts carry the channel number: \(headline.label)")
        XCTAssertTrue(first.contains("12:"), "the block on air at 12:10 has a 12 o'clock time: \(first)")
        let blocks = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch5-'"))
        XCTAssertGreaterThan(blocks.count, 1, "channel 5's row carries more than the programme on now")
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(lit.exists, "a programme stays lit after Right")
        XCTAssertNotEqual(lit.label, first, "Right lights the next programme")
        kjScreenshot("guide-grid-right", app: app)
        // Select on a later programme tunes nothing and keeps the guide.
        let tuned = any(app, "transmissionChannel")
        XCUIRemote.shared.press(.select)
        kjPause(1.5)
        XCTAssertTrue(guide.exists && tuned.label == "5", "Select on a later programme changes nothing")
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertEqual(lit.label, first, "Left comes back to the programme on now")
        // Channel 6 is off air in the fixture: Down lights its stretch, and Select there does nothing.
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        let dark = litBlock(app, channel: 6)
        XCTAssertTrue(dark.exists && dark.label.hasPrefix("Off air"), "channel 6's lit block is off air: \(dark.label)")
        kjScreenshot("guide-grid-off-air-row", app: app)
        XCUIRemote.shared.press(.select)
        kjPause(1.5)
        XCTAssertTrue(guide.exists && tuned.exists && tuned.label == "5", "Select on a stretch off air changes nothing")
        // Its channel cell tunes it in the window; Back then leaves the viewer on its off-air card.
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertTrue(any(app, "guide-ch6").isSelected, "Left lights channel 6's cell")
        XCUIRemote.shared.press(.select)
        kjPause(3)
        XCTAssertTrue(guide.exists, "the guide stays while the window tunes an off-air channel")
        kjScreenshot("guide-window-off-air", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilGone(guide, 5), "Back closes the guide")
        kjPause(8)
        // The off-air card: Right still opens the guide, so the viewer can go somewhere on.
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right on the off-air card opens the guide")
        kjPause(0.8)
        kjScreenshot("guide-grid-over-off-air", app: app)
        XCTAssertTrue(litBlock(app, channel: 6).exists, "the guide opens lit on the channel tuned, off air")
        XCUIRemote.shared.press(.up)
        kjPause(0.6)
        XCTAssertTrue(litBlock(app, channel: 5).exists, "Up lights channel 5 again")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilGone(guide, 5), "Back closes the guide")
    }

    /// The guide in each skin, for the eye: the tokens do the work, so each is photographed with a
    /// programme lit and with a channel's cell lit.
    func testGuideInEverySkin() {
        for skin in ["day", "grove", "smut"] {
            let app = open(channel: 5, skin: skin)
            kjPause(12)
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(any(app, "transmissionGuide").waitForExistence(timeout: 5), "\(skin): the guide opens")
            kjPause(1)
            kjScreenshot("tv-guide-\(skin)-programme", app: app)
            XCTAssertTrue(any(app, "guidePictureWindow").exists, "\(skin): the picture window")
            XCUIRemote.shared.press(.left)
            kjPause(0.8)
            kjScreenshot("tv-guide-\(skin)-channel", app: app)
            XCTAssertTrue(any(app, "guide-ch5").isSelected, "\(skin): the channel's cell is lit")
            app.terminate()
        }
    }

    /// Opened on the first channel, the guide holds its rows against the top of the list, and every
    /// row it draws has its schedule (Fable, round 1: the fifth row came up empty). Channel 14, Jordan
    /// Television, is strips of short items in the fixture: a block per strip named for the show,
    /// not a row of slivers.
    func testGuideOnTheFirstChannelFillsEveryRow() {
        // Channel 1 is off air in the fixture, and the off-air card carries no channel number, so
        // this opens it by hand rather than through open(channel:).
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-08T12:10:00+05:00"]
        kjLaunch(app)
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "channel 1 has a card")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        XCUIRemote.shared.press(.select)
        let offAir = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'off air'")).firstMatch
        XCTAssertTrue(offAir.waitForExistence(timeout: 30), "channel 1 opens on its off-air card")
        kjPause(8)
        XCUIRemote.shared.press(.right)
        let guide = any(app, "transmissionGuide")
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right opens the guide on channel 1, off air in the fixture")
        kjPause(0.8)
        kjScreenshot("guide-grid-first-channel", app: app)
        for number in 1...7 {
            XCTAssertTrue(any(app, "guide-ch\(number)-0").exists, "channel \(number)'s row has its schedule")
        }
        // Up from the first channel goes round to the last; its rows are drawn too.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertTrue(litBlock(app, channel: 15).exists, "Up from channel 1 lights the last channel")
        for number in 9...15 {
            XCTAssertTrue(any(app, "guide-ch\(number)-0").exists, "channel \(number)'s row has its schedule")
        }
        // Jordan Television, in view beside the last channel: a strip of short items, in runs named
        // for its show, each saying how many it holds.
        let jordan = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch14-'"))
        let names = jordan.allElementsBoundByIndex.map(\.label)
        kjScreenshot("guide-grid-short-items", app: app)
        print("KJGUIDE jordan \(names)")
        XCTAssertLessThanOrEqual(names.count, 8, "Jordan Television's short items are drawn in runs, not one block each: \(names.count)")
        XCTAssertTrue(names.contains { $0.contains(" programmes") || $0.contains(" songs") }, "a run says how many it holds: \(names)")
        XCUIRemote.shared.press(.menu)
    }

    private func waitUntilGone(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: timeout) == .completed
    }
}
