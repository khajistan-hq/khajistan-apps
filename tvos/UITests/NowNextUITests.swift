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

    private func open(channel: Int, skin: String, now: String = "2026-11-08T12:10:00+05:00") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", skin, "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", now]
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

    /// A Persian title carries its Roman form on a line of its own, on the strip and in the guide
    /// (owner, 2026-11-17: "name of film should also be in roman"). Fixture: a real Channel 1
    /// record (programming-2026-11.json, tv-liked-yt--6jom-bc-ga) and an English-only channel 2.
    func testPersianTitleCarriesItsRomanForm() {
        let app = XCUIApplication()
        let schedule = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-roman-title.json").path
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "transmission", "-kjschedulefile", schedule,
                               "-kjnow", "2026-11-04T12:00:00+05:00"]
        kjLaunch(app)
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "channel 1 has a card")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["transmissionChannel"].waitForExistence(timeout: 30))
        kjPause(12)
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        kjScreenshot("roman-title-strip-grove", app: app)
        let name = app.staticTexts.matching(identifier: "stripName").firstMatch
        XCTAssertTrue(name.exists, "the strip carries the name")
        XCTAssertTrue(name.label.contains("اول هیکل"), name.label)
        let latin = app.staticTexts.matching(identifier: "stripLatinName").firstMatch
        XCTAssertTrue(latin.exists && app.frame.intersects(latin.frame), "the Roman form is on the strip")
        XCTAssertEqual(latin.label, "Aval Heykal, with Naser Malek-Motiei")
        XCTAssertGreaterThan(latin.frame.minY, name.frame.minY, "it sits under the Persian name")

        // The guide: right on the bare picture opens it; channel 1's line carries both names.
        kjPause(4)
        XCUIRemote.shared.press(.right)
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10), "right opens the guide")
        kjPause(0.8)
        kjScreenshot("roman-title-guide-grove", app: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Aval Heykal")).firstMatch.exists,
                      "the guide's line for channel 1 carries the Roman form")

        // Negative: an English-only programme has no second line.
        XCUIRemote.shared.press(.menu)
        kjPause(1)
        XCUIRemote.shared.press(.up)   // channel up to 2
        kjPause(12)
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        XCTAssertEqual(app.descendants(matching: .any)["transmissionChannel"].label, "2", "channel up reaches channel 2")
        let english = app.staticTexts.matching(identifier: "stripName").firstMatch
        XCTAssertTrue(english.exists && english.label.contains("Test Programme 2"), "channel 2's strip is up: \(english.label)")
        XCTAssertFalse(app.staticTexts.matching(identifier: "stripLatinName").firstMatch.exists, "no Roman line under an English name")
        // The year the record carries is on the detail line (owner, 2026-11-15: country, then year).
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1965")).firstMatch.exists,
                      "the strip shows the programme's year")
        kjScreenshot("roman-title-english-no-second-line", app: app)
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

    /// The guide on Transmission rises from the bottom, as the Receiver's does (owner, 2026-11-15:
    /// "guide not showing from bottom up in transmission"): left on the bare picture opens it over
    /// the lower part of the screen with the tuned channel lit, down lights the next, Select tunes it.
    func testGuideRisesFromTheBottomAndTunes() {
        let app = open(channel: 5, skin: "day")
        kjPause(12)
        let tuned = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertEqual(tuned.label, "5")
        XCUIRemote.shared.press(.left)
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "left on the picture opens the guide")
        kjPause(0.6)
        kjScreenshot("transmission-guide-day", app: app)
        XCTAssertGreaterThan(guide.frame.minY, app.frame.height / 3, "the guide sits over the bottom of the picture")
        XCTAssertEqual(guide.frame.maxY, app.frame.maxY, accuracy: 2, "the guide reaches the foot of the screen")
        XCTAssertTrue(app.descendants(matching: .any)["guide-ch5"].isSelected, "the tuned channel is lit")
        // Channel 8 is the next one the fixture programmes; 6 and 7 are off air in it.
        for _ in 0..<3 { XCUIRemote.shared.press(.down); kjPause(0.4) }
        XCTAssertTrue(app.descendants(matching: .any)["guide-ch8"].isSelected, "three downs light channel 8")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntilGone(guide, 5), "Select closes the guide")
        let moved = NSPredicate { _, _ in tuned.exists && tuned.label == "8" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 30), .completed,
                       "Select tunes the lit channel")
        // Back on the bare picture: right opens the guide too, Back closes it.
        kjPause(8)   // the strip hides 2.6 s after the tune, so right meets the bare picture
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right on the bare picture opens the guide")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilGone(guide, 5), "Back closes the guide")
    }

    /// The guide is a time grid (owner, 2026-11-17: "it needs to be showing schedule on an hourly
    /// basis"): half-hour marks across the top, each channel's programmes as blocks along its row,
    /// the one on now lit. Right lights the next programme, Left goes back, never before now.
    /// An off-air channel picked from it no longer strands the viewer: the guide opens over the
    /// off-air card too (it opened only over a picture, from #79).
    func testGuideIsATimeGridAndOpensOffAir() {
        let app = open(channel: 5, skin: "day")
        kjPause(12)
        XCUIRemote.shared.press(.left)
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "left on the picture opens the guide")
        kjPause(0.8)
        kjScreenshot("guide-grid-open", app: app)
        let lit = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch5-' AND selected == true")).firstMatch
        XCTAssertTrue(lit.exists, "a programme on channel 5 is lit")
        let first = lit.label
        // The lit block is the programme on air: the strip's headline names it too (12:10 PKT in
        // the fixture), and the guide's own headline reads the same title in full.
        let headline = app.descendants(matching: .any)["guideHeadline"]
        XCTAssertTrue(headline.exists, "the guide reads the lit programme over the grid")
        let title = String(first.split(separator: ",").first ?? "")
        XCTAssertFalse(title.isEmpty)
        XCTAssertTrue(headline.label.hasPrefix(title), "the headline names the lit block: \(headline.label) / \(first)")
        XCTAssertTrue(first.contains("12:"), "the block on air at 12:10 has a 12 o'clock time: \(first)")
        let blocks = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch5-'"))
        XCTAssertGreaterThan(blocks.count, 1, "channel 5's row carries more than the programme on now")
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(lit.exists, "a programme stays lit after Right")
        XCTAssertNotEqual(lit.label, first, "Right lights the next programme")
        kjScreenshot("guide-grid-right", app: app)
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertEqual(lit.label, first, "Left comes back to the programme on now")
        XCUIRemote.shared.press(.left)
        kjPause(0.6)
        XCTAssertEqual(lit.label, first, "Left stops at now")
        // Channel 6 is off air in the fixture: Down lights it, and its row says so.
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertTrue(app.descendants(matching: .any)["guide-ch6"].isSelected, "Down lights channel 6")
        let dark = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch6-' AND selected == true")).firstMatch
        XCTAssertTrue(dark.exists && dark.label.hasPrefix("Off air"), "channel 6's lit block is off air: \(dark.label)")
        kjScreenshot("guide-grid-off-air-row", app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntilGone(guide, 5), "Select closes the guide")
        let tuned = app.descendants(matching: .any)["transmissionChannel"]
        _ = tuned.waitForExistence(timeout: 10)
        kjPause(8)
        // The off-air card: Right still opens the guide, so the viewer can go somewhere on.
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right on the off-air card opens the guide")
        kjScreenshot("guide-grid-over-off-air", app: app)
        XCUIRemote.shared.press(.up)
        kjPause(0.6)
        XCTAssertTrue(app.descendants(matching: .any)["guide-ch5"].isSelected, "Up lights channel 5 again")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilGone(guide, 5), "Back closes the guide")
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
        let guide = app.descendants(matching: .any)["transmissionGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "right opens the guide on channel 1, off air in the fixture")
        kjPause(0.8)
        kjScreenshot("guide-grid-first-channel", app: app)
        for number in 1...5 {
            XCTAssertTrue(app.descendants(matching: .any)["guide-ch\(number)-0"].exists, "channel \(number)'s row has its schedule")
        }
        // Up from the first channel goes round to the last; its rows are drawn too.
        XCUIRemote.shared.press(.up)
        kjPause(0.8)
        XCTAssertTrue(app.descendants(matching: .any)["guide-ch15"].isSelected, "Up from channel 1 lights the last channel")
        for number in 11...15 {
            XCTAssertTrue(app.descendants(matching: .any)["guide-ch\(number)-0"].exists, "channel \(number)'s row has its schedule")
        }
        // Jordan Television, in view beside the last channel: a strip of short items, in runs named
        // for its show.
        let jordan = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide-ch14-'"))
        let names = jordan.allElementsBoundByIndex.map(\.label)
        kjScreenshot("guide-grid-short-items", app: app)
        print("KJGUIDE jordan \(names)")
        XCTAssertLessThanOrEqual(names.count, 8, "Jordan Television's short items are drawn in runs, not one block each: \(names.count)")
        XCUIRemote.shared.press(.menu)
    }

    private func waitUntilGone(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: timeout) == .completed
    }

    /// The channel number pops up in the top corner when the channel changes, as on a 1980s set,
    /// and goes again by itself (owner, 2026-11-15).
    func testChannelNumberPopsUpOnAChange() {
        for skin in ["day", "grove", "smut"] {
            let app = open(channel: 5, skin: skin)
            let osd = app.descendants(matching: .any)["channelNumberOSD"]
            XCTAssertTrue(osd.waitForExistence(timeout: 30), "the number shows once the channel is on (\(skin))")
            XCTAssertEqual(osd.label, "Channel 5")
            XCTAssertTrue(osd.frame.minY < app.frame.height * 0.25 && osd.frame.minX > app.frame.width * 0.5, "top right: \(osd.frame)")
            kjScreenshot("channel-number-c5-\(skin)", app: app)
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !osd.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 6), .completed, "and goes by itself")
            XCUIRemote.shared.press(.up)
            let next = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'channelNumberOSD' AND label != 'Channel 5'")).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 30), "Channel Up shows the next number")
            kjScreenshot("channel-number-up-\(skin)", app: app)
            app.terminate()
        }
    }

    /// No number over a sound-only programme, whose title sits in that corner; off air it shows.
    /// The fixture's channel 5 plays folk-tv, a sound-only tape, at 13:30; channel 6 has no
    /// strips, so it is off air. The off-air number is the check that the number works here at all,
    /// and the change back to 5 checks the sound-only rule on that same path.
    func testNoChannelNumberOverSoundOnlyButOffAir() {
        let app = open(channel: 5, skin: "day", now: "2026-11-08T13:40:00+05:00")
        let osd = app.descendants(matching: .any)["channelNumberOSD"]
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 30), "the sound-only programme is on")
        XCTAssertFalse(osd.waitForExistence(timeout: 8), "no number over a sound-only programme")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(app.staticTexts["Off air"].waitForExistence(timeout: 30), "channel 6 is off air")
        XCTAssertTrue(osd.waitForExistence(timeout: 15), "off air the number shows")
        XCTAssertEqual(osd.label, "Channel 6")
        kjScreenshot("channel-number-off-air", app: app)
        // Back to 5 by a channel change, the path that just showed 6: no sign-on cover or first
        // flight is left to hold the number, so its absence here is the sound-only rule.
        XCUIRemote.shared.press(.down)
        let tuned = app.descendants(matching: .any)["transmissionChannel"]
        let backOnFive = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tuned.exists && tuned.label == "5" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [backOnFive], timeout: 30), .completed, "channel 5 is tuned again")
        XCTAssertTrue(state.waitForExistence(timeout: 30), "channel 5 is back on")
        XCTAssertFalse(osd.waitForExistence(timeout: 12), "no number over a sound-only programme after a change")
    }
}
