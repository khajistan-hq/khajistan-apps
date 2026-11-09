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
}
