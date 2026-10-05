import XCTest

/// The three caption paths on screen.
///
/// - Khajistan Transmission: the schedule and the programme's subtitle file are behind the site's
///   preview password, which a test does not hold, so the DEBUG-only `-kjschedulefile` and
///   `-kjsubtitlefile` hand the player this checkout's month and a fixture WebVTT file. The cue is
///   real WebVTT through the app's parser and view; the fetch through the gate is not exercised.
/// - The receiver, signed out: the Captions control is in the strip where the channel offers it,
///   pressing it says the site's sign-in sentence, and a channel it cannot caption says why with no
///   control. Signed-in captions need an account and are not exercised here.
/// - The Screening Room: a film preview's English track from Cloudflare Stream, through the
///   manifest's legible group. Needs TEST_RUNNER_KJ_FILMS_ORIGIN, as FilmsUITests does.
final class SubtitlesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var checkout: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private var scheduleFile: String {
        var karachi = Calendar(identifier: .gregorian)
        karachi.timeZone = TimeZone(identifier: "Asia/Karachi")!
        let c = karachi.dateComponents([.year, .month], from: Date())
        return checkout.appendingPathComponent(String(format: "data/khajistan-tv/programming-%04d-%02d.json", c.year ?? 0, c.month ?? 0)).path
    }

    private var subtitleFile: String {
        checkout.appendingPathComponent("tvos/Tests/Fixtures/subtitles-fixture.vtt").path
    }

    private func waitFor(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    func testTransmissionSubtitleOverAndUnderTheStrip() {
        for skin in ["day", "smut"] {
            let app = XCUIApplication()
            app.launchArguments = ["-kjskin", skin, "-kjtab", "transmission", "-kjschedulefile", scheduleFile, "-kjsubtitlefile", subtitleFile]
            app.launch()
            let page = app.staticTexts["transmissionState"]
            XCTAssertTrue(page.waitForExistence(timeout: 30))
            _ = waitFor(20) { (page.value as? String) == "Ready" }
            let card = app.buttons["transmission-channel-1"]
            XCTAssertTrue(kjFocus(card, app: app), "channel 1's card must take focus")
            XCUIRemote.shared.press(.select)

            let caption = app.descendants(matching: .any)["caption"]
            XCTAssertTrue(caption.waitForExistence(timeout: 30), "\(skin): the programme's subtitle must be on screen")
            XCTAssertTrue(caption.label.contains("This line reads left to right."), caption.label)
            XCTAssertTrue(caption.label.contains("یہ سطر"), caption.label)
            kjPause(10)   // the opening ground lifts, and the strip hides 2.6 s in
            let low = caption.frame
            kjScreenshot("subs-\(skin)-1-transmission-strip-down", app: app)

            XCUIRemote.shared.press(.select)   // wakes the strip
            kjPause(0.8)
            kjScreenshot("subs-\(skin)-2-transmission-strip-up", app: app)
            let control = app.buttons["subtitlesControl"]
            XCTAssertTrue(control.exists, "a programme with subtitles carries the control")
            XCTAssertEqual(control.label, "Subtitles · English")
            XCTAssertLessThan(caption.frame.maxY, low.maxY - 40, "\(skin): the subtitle rises above the strip")

            XCUIRemote.shared.press(.right)    // to the control
            kjPause(0.6)
            kjScreenshot("subs-\(skin)-2b-transmission-control-focused", app: app)
            if !control.hasFocus { print("FOCUSDUMP " + app.debugDescription) }
            XCTAssertTrue(control.hasFocus, "right reaches the Subtitles control")
            XCUIRemote.shared.press(.select)   // off
            kjPause(0.6)
            XCTAssertEqual(control.label, "Subtitles · Off")
            XCTAssertFalse(caption.exists, "off means off")
            kjScreenshot("subs-\(skin)-3-transmission-off", app: app)
            XCUIRemote.shared.press(.select)   // on again
            kjPause(0.6)
            XCTAssertTrue(caption.waitForExistence(timeout: 3))
            XCUIRemote.shared.press(.left)
            kjPause(0.6)
            XCTAssertFalse(control.hasFocus, "left leaves the control")
            app.terminate()
        }
    }

    func testReceiverCaptionsSignedOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "receiver"]
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 where !focusedRegion.exists { XCUIRemote.shared.press(.down) }
        for _ in 0..<40 where focusedRegion.exists && focusedRegion.identifier != "region-indus" {
            XCUIRemote.shared.press(.right)
        }
        XCTAssertEqual(focusedRegion.identifier, "region-indus")
        XCUIRemote.shared.press(.select)

        // ABN News, the first television channel by name: Pakistan, so Urdu by the country rule, so offered.
        let abn = app.buttons["channel-swept-pk-abn-news"]
        XCTAssertTrue(abn.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocus(abn, app: app), "ABN News must take focus")
        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        _ = waitFor(45) { state.label == "Playing" }
        kjPause(8)
        XCUIRemote.shared.press(.right)
        kjPause(0.8)
        let control = app.buttons["captionsControl"]
        XCTAssertTrue(control.exists, "a live channel in a language the recogniser takes offers captions")
        XCTAssertTrue(control.hasFocus, "right reaches the Captions control")
        XCTAssertTrue(control.label.hasPrefix("Captions"), control.label)
        kjScreenshot("live-1-captions-control-focused", app: app)
        XCUIRemote.shared.press(.select)
        let sentence = app.staticTexts["Sign in from the top of the page to use live captions."]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5), "signed out, the site's sentence and no request")
        XCTAssertEqual(control.label, "Captions", "nothing was turned on")
        kjScreenshot("live-2-signed-out-sentence", app: app)
        XCUIRemote.shared.press(.left)
        kjPause(0.5)
        XCTAssertFalse(control.hasFocus)
        XCUIRemote.shared.press(.menu)

        // DD Kashir: Kashmiri is not on the live recogniser, so one line and no control.
        let kashir = app.buttons["channel-india-dd-kashir"]
        XCTAssertTrue(kashir.waitForExistence(timeout: 20))
        XCTAssertTrue(kjFocus(kashir, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        _ = waitFor(45) { state.label == "Playing" }
        kjPause(8)
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        XCTAssertFalse(app.buttons["captionsControl"].exists, "no control for a language that cannot be captioned")
        XCTAssertTrue(app.staticTexts["No captions: Kashmiri is not on the live recogniser."].exists, "the line says why")
        kjScreenshot("live-3-kashmiri-no-control", app: app)
    }

    func testFilmPreviewEnglishTrack() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day"]
        app.launch()
        let entry = app.buttons["screeningRoom"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocus(entry, app: app))
        XCUIRemote.shared.press(.select)
        // Filmfarsi Trailers vol. 1: its public preview announces an English track.
        let film = app.buttons["film-filmfarsi-trailers-vol-1-khajistan"]
        XCTAssertTrue(film.waitForExistence(timeout: 30))
        XCTAssertTrue(kjFocus(film, app: app, limit: 60), "the film must take focus")
        XCUIRemote.shared.press(.select)

        let control = app.buttons["subtitlesControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 45), "a preview whose manifest carries a track offers the control")
        XCTAssertEqual(control.label, "Subtitles · English", "English starts on with nothing remembered")
        let caption = app.descendants(matching: .any)["caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60), "the track's text must reach the house view")
        kjScreenshot("film-1-subtitle-over-panel", app: app)
        kjPause(4)   // the panel hides
        if caption.exists { kjScreenshot("film-2-subtitle-alone", app: app) }
    }
}
