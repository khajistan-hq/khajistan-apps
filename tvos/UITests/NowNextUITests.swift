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
