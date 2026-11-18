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

    /// One month of the station's schedule carried with the tests, read with the clock pinned
    /// inside it (`-kjnow`), so the tests need neither the archive's live month file nor the
    /// date they run on.
    private var scheduleFile: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/programming-2026-10.json").path
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
            app.launchArguments = ["-kjskin", skin, "-kjtab", "transmission", "-kjschedulefile", scheduleFile, "-kjnow", "2026-10-15T14:10:00+05:00", "-kjsubtitlefile", subtitleFile]
            kjLaunch(app)
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
            XCTAssertTrue(control.isSelected, "right lights the Subtitles control")
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

    /// Lights the strip's Captions control the way the remote does since 2026-11-04: right on the
    /// bare picture opens the guide, so Select lights it. A first Select only wakes the strip when
    /// it had hidden; a second then lights Captions. Never a third, which would work the control.
    private func lightCaptions(_ control: XCUIElement) {
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        if !(control.exists && control.isSelected) {
            XCUIRemote.shared.press(.select)
            kjPause(0.8)
        }
    }

    func testReceiverCaptionsSignedOut() throws {
        let app = XCUIApplication()
        // ABN News by name, so the list is the recording (`-kjfixturesonly`): live, it left the dial
        // on 2026-11-15 (CI 43756089230). Its stream is still live; kjTuneUntilPlaying moves past it.
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "receiver", "-kjcaptiontestsignedout", "YES", "-kj-caption-mode", "off",
                               "-kjfixturesonly", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focusedRegion = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach indus in the region list")
        XCTAssertEqual(focusedRegion.identifier, "region-indus")
        XCUIRemote.shared.press(.select)

        // ABN News, the first television channel by name: Pakistan, so Urdu by the country rule, so offered.
        let abn = app.buttons["channel-swept-pk-abn-news"]
        XCTAssertTrue(abn.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocus(abn, app: app), "ABN News must take focus")
        XCUIRemote.shared.press(.select)
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        // The strip offers its controls over a playing channel: ABN News, or when its carrier does
        // not reach the runner, the next Pakistani channel down (Urdu by the country rule). DD
        // Kashir also plays on the runner, and Kashmiri offers no captions (CI on PR 79, 2026-11-16).
        try kjTuneUntilPlaying(app, tries: 10) { $0.hasPrefix("swept-pk-") || $0.hasPrefix("indus-") }
        kjPause(8)
        let control = app.buttons["captionsControl"]
        lightCaptions(control)
        XCTAssertTrue(control.exists, "a live channel in a language the recogniser takes offers captions")
        XCTAssertTrue(control.isSelected, "Select lights the Captions control")
        XCTAssertTrue(control.label.hasPrefix("Captions"), control.label)
        kjScreenshot("live-1-captions-control-focused", app: app)
        XCUIRemote.shared.press(.select)
        let sentence = app.staticTexts["Sign in under Account to use live captions."]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5), "signed out, the site's sentence and no request")
        XCTAssertEqual(control.label, "Captions", "signed out, no demand started")
        XCTAssertEqual((control.value as? String)?.uppercased(), "ON", "the requested setting remains On while sign-in is required")
        kjScreenshot("live-2-signed-out-sentence", app: app)
        // Five seconds after the choice the strip hides; captions and the saved setting remain.
        XCTAssertTrue(waitFor(8) { !control.exists }, "hidden controls are also absent from accessibility traversal")
        kjScreenshot("live-2b-strip-hidden", app: app)
        // Left or right on the bare picture opens the guide (owner, 2026-11-04); Select wakes the
        // strip and lights CC, and one more Select works it.
        lightCaptions(control)
        XCTAssertTrue(control.isSelected, "Select lights the Captions control again")
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        XCTAssertEqual((control.value as? String)?.uppercased(), "OFF", "an unavailable session still lets the viewer save Off")
        XCUIRemote.shared.press(.left)
        // Back over a playing picture may hide the strip before it leaves: press until the player
        // is gone, never more than twice. (The region page's cards stay in the tree under the
        // player, so they cannot tell.)
        for _ in 0..<2 where state.exists {
            XCUIRemote.shared.press(.menu)
            kjPause(1)
        }
        XCTAssertTrue(state.waitForNonExistence(timeout: 10), "Back leaves the player")

        // DD Kashir: Kashmiri is not on the live recogniser, so one line and no control. Its card
        // is drawn only once the shelf scrolls near it.
        let kashir = app.buttons["channel-india-dd-kashir"]
        XCTAssertTrue(kjFocus(abn, app: app), "ABN News takes focus again")
        for _ in 0..<20 where !kashir.exists {
            XCUIRemote.shared.press(.right)
            kjPause(0.4)
        }
        XCTAssertTrue(kashir.waitForExistence(timeout: 10), "DD Kashir is on the Indus television shelf")
        XCTAssertTrue(kjFocus(kashir, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        XCTAssertTrue(waitFor(45) { state.label == "Playing" }, "DD Kashir must be playing for the strip to offer its controls: \(state.label)")
        kjPause(8)
        let kashirControl = app.buttons["captionsControl"]
        lightCaptions(kashirControl)
        XCTAssertTrue(kashirControl.exists, "CC remains discoverable for unsupported channels")
        XCTAssertTrue(kashirControl.isSelected, "Select lights the Captions control")
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        XCTAssertEqual((app.buttons["captionsControl"].value as? String)?.uppercased(), "OFF", "the house strip exposes its off value in uppercase")
        XCTAssertTrue(app.staticTexts["No captions: Kashmiri is not on the live recogniser."].exists, "the line says why")
        kjScreenshot("live-3-kashmiri-no-control", app: app)
    }

    /// Opening the app plays nothing (owner, 2026-10-29: "it goes straight to playing a channel,
    /// which is not what I want. I need to be able to select a channel and then play it"). Surf is
    /// focused, so Select starts a channel. This test reversed the 2026-10-08 one that required a
    /// channel to start without Select.
    func testReceiverPlaysNothingUntilAChannelIsChosen() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "receiver"]
        kjLaunch(app, autoplay: true)
        let state = app.staticTexts["playerState"]
        let surf = app.buttons["shuffle"]
        var surfLoaded = surf.waitForExistence(timeout: 60)
        // The live index can fail while the simulator reconnects between launches. Retry only
        // that explicit offline state once; keep every navigation and playback assertion below.
        if !surfLoaded, app.staticTexts["The Internet connection appears to be offline."].exists {
            let retry = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Try again")).firstMatch
            XCTAssertTrue(kjFocus(retry, app: app), "the offline receiver offers Try again")
            XCUIRemote.shared.press(.select)
            surfLoaded = surf.waitForExistence(timeout: 60)
        }
        XCTAssertTrue(surfLoaded, "the front shows Surf")
        XCTAssertFalse(state.waitForExistence(timeout: 20), "no player opens by itself")
        let focusedSurf = NSPredicate { _, _ in surf.hasFocus }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focusedSurf, object: nil)], timeout: 10), .completed,
                       "Surf has focus at launch")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(state.waitForExistence(timeout: 90), "Select on Surf opens a channel")
    }

    func testFilmPreviewEnglishTrack() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        // Off under the old shared key: a film must not read it (the Razia bug read Persian there).
        // The film's own key is blanked, so a choice an earlier run left on this device is not read.
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day", "-kj-of-subtitles", "off",
                               "-kj-of-subtitles.filmfarsi-trailers-vol-1-khajistan", ""]
        kjLaunch(app)
        // Filmfarsi Trailers vol. 1: its public preview announces an English track.
        let film = app.buttons["film-filmfarsi-trailers-vol-1-khajistan"]
        // The films are a shelf, and a lazy one: a card far along does not exist until focus
        // brings it near. Onto the shelf by its first card, then along it to the one wanted.
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        for _ in 0..<40 where !(film.exists && film.hasFocus) {
            XCUIRemote.shared.press(.right)
            kjPause(0.5)
        }
        XCTAssertTrue(film.exists && film.hasFocus, "the film must take focus")
        XCUIRemote.shared.press(.select)

        let control = app.buttons["subtitlesControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 45), "a preview whose manifest carries a track offers the control")
        XCTAssertEqual(control.label, "Subtitles · English",
                       "with nothing remembered for this film, English starts on; the shared Off is not read")
        let caption = app.descendants(matching: .any)["caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60), "the track's text must reach the house view")
        kjScreenshot("film-1-subtitle-over-panel", app: app)
        kjPause(4)   // the panel hides
        if caption.exists { kjScreenshot("film-2-subtitle-alone", app: app) }
    }

    /// "Yellow text" subtitles (owner, 2026-11-17): yellow text with a black edge and no plate, on a
    /// film's preview. The look is checked on the screenshot.
    func testYellowTextSubtitlesOnAFilm() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "grove", "-kj-caption-style", "bare",
                               "-kj-of-subtitles.filmfarsi-trailers-vol-1-khajistan", "en"]
        kjLaunch(app)
        let film = app.buttons["film-filmfarsi-trailers-vol-1-khajistan"]
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        for _ in 0..<40 where !(film.exists && film.hasFocus) {
            XCUIRemote.shared.press(.right)
            kjPause(0.5)
        }
        XCTAssertTrue(film.exists && film.hasFocus, "the film must take focus")
        XCUIRemote.shared.press(.select)
        let caption = app.descendants(matching: .any)["caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60), "the track's text reaches the house view")
        // The caption reports the look it is drawn in: over a film's picture, the viewer's choice.
        XCTAssertEqual(caption.value as? String, "bare", "Yellow text is drawn over the picture")
        kjPause(4)   // the panel hides, so the text sits on the picture
        kjScreenshot("film-subtitles-text-only", app: app)
    }

    /// The full film's controls, reached with the remote while the picture keeps focus (owner,
    /// 2026-11-15: no CC on Razia, no way to stop). The preview plays as the full film here.
    func testFullFilmControlsAreLitWithTheRemote() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        // Off for this film, English under the old shared key: the film's own choice must win.
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day", "-kjfilmasfull", "YES",
                               "-kj-of-subtitles.filmfarsi-trailers-vol-1-khajistan", "off", "-kj-of-subtitles", "en"]
        kjLaunch(app)
        let film = app.buttons["film-filmfarsi-trailers-vol-1-khajistan"]
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        for _ in 0..<40 where !(film.exists && film.hasFocus) {
            XCUIRemote.shared.press(.right)
            kjPause(0.5)
        }
        XCTAssertTrue(film.exists && film.hasFocus, "the film must take focus")
        XCUIRemote.shared.press(.select)

        // The preview's panel: Watch the full film is focused, and Stop is offered beside it.
        let watch = app.buttons["watchFullFilm"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45), "the offer opens")
        XCTAssertTrue(app.buttons["stopControl"].exists, "the preview offers Stop")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in watch.hasFocus }, object: nil)], timeout: 30),
                       .completed, "Watch the full film takes focus")
        XCUIRemote.shared.press(.select)

        let subtitles = app.descendants(matching: .any)["subtitlesControl"]
        let stop = app.descendants(matching: .any)["stopControl"]
        XCTAssertTrue(subtitles.waitForExistence(timeout: 45), "the full film carries its subtitle control")
        XCTAssertFalse(subtitles.isSelected, "nothing is lit until the remote moves to it")
        // Read while nothing is lit, when the face carries the ↓ hint: the spoken label must not.
        XCTAssertEqual(subtitles.label, "Subtitles · Off", "the film's own Off wins over the shared English; no ↓ in the label")
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertTrue(subtitles.isSelected, "Down lights Subtitles")
        kjPause(3.5)
        XCTAssertTrue(subtitles.isSelected, "a lit control stays past the panel's 2.6 s, so Select can still work it")
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        XCTAssertEqual(subtitles.label, "Subtitles · English", "Select on the lit control moves to the next choice")
        for _ in 0..<3 where !stop.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(stop.isSelected, "Right walks to Stop")
        kjScreenshot("film-full-controls-stop-lit", app: app)

        // Back closes the bottom bar, letting go of the lit control (owner, 2026-11-17); with the
        // bar closed, the next Back stops the film and closes the screen.
        XCUIRemote.shared.press(.menu)
        kjPause(0.8)
        XCTAssertFalse(app.staticTexts["playerState"].exists, "the first Back closes the bottom bar")
        XCTAssertTrue(app.descendants(matching: .any)["filmPicture"].exists, "and the film is still on")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 20), "the next Back stops the film")
        XCTAssertFalse(app.descendants(matching: .any)["filmPicture"].exists, "the player is gone")
    }

    /// The full film moves as Apple's player moves it (owner, 2026-11-17: "all controls should work
    /// like apple tv player"): a click skips ten seconds, a held arrow scans, Play/Pause pauses. A
    /// swipe cannot be sent from XCUIRemote; the scrub is checked on the Apple TV.
    func testFullFilmMovesLikeApplesPlayer() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day", "-kjfilmasfull", "YES"]
        kjLaunch(app)
        let film = app.buttons["film-filmfarsi-trailers-vol-1-khajistan"]
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        for _ in 0..<40 where !(film.exists && film.hasFocus) {
            XCUIRemote.shared.press(.right)
            kjPause(0.5)
        }
        XCTAssertTrue(film.exists && film.hasFocus, "the film must take focus")
        XCUIRemote.shared.press(.select)
        let watch = app.buttons["watchFullFilm"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45), "the offer opens")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in watch.hasFocus }, object: nil)], timeout: 30),
                       .completed, "Watch the full film takes focus")
        XCUIRemote.shared.press(.select)

        let state = app.staticTexts["playerState"]
        let playing = NSPredicate { _, _ in (try? state.snapshot())?.label == "Playing" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 45), .completed, "the film plays")

        // The bar's value is the second the film is at; any press brings the panel and the bar up.
        let bar = app.descendants(matching: .any)["filmProgress"]
        func at() -> Int { Int(((try? bar.snapshot())?.value as? String) ?? "") ?? -1 }
        func waitUntil(_ why: String, timeout: TimeInterval = 10, _ test: @escaping (Int) -> Bool) {
            let met = NSPredicate { _, _ in test(at()) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: met, object: nil)], timeout: timeout), .completed,
                           "\(why) (at \(at()))")
        }
        // Paused first, so playback adds nothing and each move must land exactly.
        XCUIRemote.shared.press(.playPause)
        let paused = NSPredicate { _, _ in (try? state.snapshot())?.label == "Paused" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: paused, object: nil)], timeout: 10), .completed, "Play/Pause pauses")
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows with the panel")
        let still = at()
        kjPause(2)
        XCTAssertEqual(at(), still, "a paused film stays where it is")
        XCUIRemote.shared.press(.right)
        waitUntil("a click right goes forward ten seconds") { $0 == still + 10 }
        XCUIRemote.shared.press(.left)
        waitUntil("a click left goes back ten seconds") { $0 == still }

        // A held arrow is read through GameController, which XCUIRemote does not reach, on the
        // simulator or on the Apple TV (measured 2026-11-17: a 2.5 s hold on the device came in as
        // one click). Hold-to-scan and swipe-to-scrub are checked by hand with the Siri Remote.

        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 10), .completed, "and plays again")

        #if !targetEnvironment(simulator)
        // Playing, quick clicks add up as Apple's do: the next is not lost while the last buffers.
        // Device only: on the simulator the stream does not buffer after a seek, so this passed
        // with the old rule too (measured twice) and could not fail there.
        let rolling = at()
        for _ in 0..<3 { XCUIRemote.shared.press(.right) }
        waitUntil("three quick clicks right go thirty seconds on") { $0 >= rolling + 28 }
        #endif
    }

    /// Full screen from the corner window opens the film over whatever is on top: here, over the
    /// player the shelf opened as a cover, which a SwiftUI cover on the root cannot reach.
    func testRestoredFilmOpensOverACover() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day", "-kjrestoreover", "YES"]
        kjLaunch(app)
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        XCUIRemote.shared.press(.select)
        let watch = app.buttons["watchFullFilm"]
        XCTAssertTrue(watch.waitForExistence(timeout: 30), "the first player opens as a cover")
        // The reopened player asks for the full film at once: signed out it says why, which only
        // the reopened screen does without a press.
        let note = app.staticTexts["filmNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 30), "the film reopens over the cover")
        kjScreenshot("film-restored-over-cover", app: app)
        // Signed out, the note is up while the screen is still sliding in, before focus has moved
        // into it: a Back pressed then was lost, or reached the cover underneath (failed 2 of 3 on
        // the base commit too). Back once the screen has settled, as a viewer would.
        kjPause(1.5)
        XCUIRemote.shared.press(.menu)
        kjPause(1.5)
        XCTAssertFalse(note.exists, "Back closes the reopened screen")
        XCTAssertTrue(watch.exists, "the cover under it is still there")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 20), "and the next Back reaches the shelf")
    }
}
