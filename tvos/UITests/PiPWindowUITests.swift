import XCTest

/// The PiP bar brings the picture back full screen in one press, closes it, works its subtitles
/// and Play/Pause, and shows over a cover as well as the root (owner, 2026-11-17: "hard to navigate
/// into small pip window and click it back up to full screen").
///
/// The simulator has no picture in picture, so `-kjpipproof` takes the window as open the moment
/// it is asked for. The window's own picture and subtitles are checked on an Apple TV
/// (`testTransmissionWindowOnAppleTV`, and the screenshots in the pull request).
final class PiPWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let film = "filmfarsi-trailers-vol-1-khajistan"

    private func openFullFilm(_ app: XCUIApplication, onAppleTV: Bool = false, extra: [String] = []) throws {
        if onAppleTV {
            // The real window: production's vod.json, read with the preview password the Apple TV holds.
            app.launchArguments = ["-kjskin", "grove", "-kjfilmasfull", "YES", "-kj-of-subtitles.\(Self.film)", "en"]
        } else {
            guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
                throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
            }
            app.launchArguments = ["-kjfilms", origin, "-kjskin", "grove", "-kjfilmasfull", "YES", "-kjpipproof", "YES",
                                   "-kj-of-subtitles.\(Self.film)", "en"] + extra
        }
        kjLaunch(app)
        let film = app.buttons["film-\(Self.film)"]
        let films = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'"))
        XCTAssertTrue(films.firstMatch.waitForExistence(timeout: 30), "vod.json must load")
        XCTAssertTrue(kjFocus(films.firstMatch, app: app), "the shelf must take focus")
        for _ in 0..<40 where !(film.exists && film.hasFocus) {
            XCUIRemote.shared.press(.right)
            kjPause(0.5)
        }
        XCUIRemote.shared.press(.select)
        let watch = app.buttons["watchFullFilm"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45), "the offer opens")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in watch.hasFocus }, object: nil)], timeout: 30),
                       .completed, "Watch the full film takes focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["caption"].waitForExistence(timeout: 60), "the film's English shows full screen")
    }

    /// Down lights the panel's first control; Right walks to PiP; Select opens the window.
    private func openWindow(_ app: XCUIApplication) {
        let pip = app.descendants(matching: .any)["pipControl"]
        XCTAssertTrue(pip.waitForExistence(timeout: 30), "the full film offers PiP")
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        for _ in 0..<4 where !pip.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(pip.isSelected, "Right walks to PiP")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["pipBar"].waitForExistence(timeout: 15), "the PiP bar comes up with the window")
    }

    /// Down from the track bar (owner, 2026-11-18: "when you touch down on the apple tv remote it
    /// should go to subtitles, stop/play and pip right now it just stays at the track bar"): the
    /// film stays paused where the swipe left it, the row lights, and PiP opens from a paused film.
    func testDownFromTheTrackBarReachesTheRowAndPausedPiPOpens() throws {
        let app = XCUIApplication()
        try openFullFilm(app, extra: ["-kjscrubopen", "YES"])
        let bar = app.descendants(matching: .any)["filmProgress"]
        let scrubLine = NSPredicate { _, _ in app.staticTexts["Select plays from here \u{00B7} Back returns"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: scrubLine, object: nil)], timeout: 30), .completed,
                       "the track bar is up")
        let reached = (try? bar.snapshot())?.value as? String
        XCTAssertNotNil(reached, "the bar reports the place, so the comparison below means something")
        kjScreenshot("film-track-bar-up", app: app)
        XCUIRemote.shared.press(.down)
        kjPause(0.8)
        let subtitles = app.descendants(matching: .any)["subtitlesControl"]
        XCTAssertTrue(subtitles.isSelected, "Down from the track bar lights the first control")
        XCTAssertFalse(app.staticTexts["Select plays from here \u{00B7} Back returns"].exists, "the track bar has let go")
        XCTAssertEqual(app.staticTexts["playerState"].label, "Paused", "the film stays paused")
        XCTAssertEqual((try? bar.snapshot())?.value as? String, reached, "where the swipe left it")
        kjScreenshot("film-down-from-track-bar", app: app)
        let playPause = app.descendants(matching: .any)["playPauseControl"]
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(playPause.isSelected && playPause.label == "Play", "Right lights Play on a paused film")
        let pip = app.descendants(matching: .any)["pipControl"]
        XCTAssertTrue(pip.exists, "PiP is offered on a paused film")
        XCUIRemote.shared.press(.right)
        kjPause(0.6)
        XCTAssertTrue(pip.isSelected, "Right lights PiP")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["pipBar"].waitForExistence(timeout: 15), "a paused film opens in the window")
    }

    func testBarComesUpLitAndBringsTheFilmBackInOnePress() throws {
        let app = XCUIApplication()
        try openFullFilm(app)
        openWindow(app)
        let fullScreen = app.buttons["pipBarFullScreen"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullScreen.hasFocus }, object: nil)], timeout: 10),
                       .completed, "Full screen is lit as the window opens")
        XCTAssertFalse(app.staticTexts["playerState"].exists, "the player screen has closed behind the window")
        kjScreenshot("pip-bar-lit", app: app)

        // One Select: the film comes back full screen, with its captions, where it had got to:
        // handed back as Apple TV does, not fetched and started again.
        kjPause(6)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["playerState"].waitForExistence(timeout: 30), "the film opens full screen again")
        let time = app.descendants(matching: .any)["filmProgress"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "the film's progress shows")
        let seconds = Int(time.value as? String ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(seconds, 6, "the film carries on from where the window had it (\(time.label)), not from the start")
        XCTAssertTrue(app.otherElements["pipBar"].waitForNonExistence(timeout: 10), "the bar goes with the window")
        XCTAssertTrue(app.descendants(matching: .any)["caption"].waitForExistence(timeout: 60), "captions come back full screen")
        kjScreenshot("pip-restored-full-screen", app: app)
    }

    /// Close ends the film; it does not reopen it (the window's restore request after a close is
    /// not the viewer asking for full screen).
    func testCloseOnTheBarEndsTheFilm() throws {
        let app = XCUIApplication()
        try openFullFilm(app)
        openWindow(app)
        let close = app.buttons["pipBarClose"]
        for _ in 0..<4 where !close.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.5) }
        XCTAssertTrue(close.hasFocus, "Right walks the bar to Close")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["pipBar"].waitForNonExistence(timeout: 10), "Close takes the bar away")
        kjPause(2)
        XCTAssertFalse(app.staticTexts["playerState"].exists, "Close ends the film rather than reopening it")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'")).firstMatch.exists, "the shelf is there")
    }

    /// A film played from its page (a cover over the root) goes to the corner and the viewer is
    /// back on the page: the bar must be there, over the page, with Full screen lit (Fable round 1:
    /// the bar lived on the root only and was hidden under every cover).
    func testBarShowsOverTheFilmPage() throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        let app = XCUIApplication()
        // A place kept for the film puts it on Rooms' Up Next row, whose cards open the film's page.
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "day", "-kjfilmasfull", "YES", "-kjpipproof", "YES",
                               "-kjtab", "rooms", "-kj.filmPlaces", "<dict><key>\(Self.film)</key><real>60</real></dict>",
                               "-kj-of-subtitles.\(Self.film)", "en"]
        kjLaunch(app)
        // Rooms → Screening Room (a cover), whose Up Next row comes first; its card opens the film's
        // page, a second cover.
        let door = app.buttons["tvroom-screening"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 30), "Rooms shows the Screening Room")
        XCTAssertTrue(kjFocus(door, app: app), "the door takes focus")
        XCUIRemote.shared.press(.select)
        // The root's Rooms page carries the same Up Next card under the cover, so the card is
        // found by focus, not by its identifier alone.
        XCTAssertTrue(app.buttons["upnext-\(Self.film)"].firstMatch.waitForExistence(timeout: 45), "Up Next carries the film")
        let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<12 where !(focused.exists && focused.identifier == "upnext-\(Self.film)") {
            XCUIRemote.shared.press(focused.exists && focused.identifier.hasPrefix("upnext-") ? .right : .down)
            kjPause(0.5)
        }
        XCTAssertEqual(focused.identifier, "upnext-\(Self.film)", "the card takes focus")
        XCUIRemote.shared.press(.select)
        let play = app.buttons["filmPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "the film's page opens")
        kjPause(1)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["caption"].waitForExistence(timeout: 60), "the film plays with its English")
        openWindow(app)
        XCTAssertTrue(play.waitForExistence(timeout: 10), "the viewer is back on the film's page")
        let fullScreen = app.buttons["pipBarFullScreen"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullScreen.hasFocus }, object: nil)], timeout: 10),
                       .completed, "Full screen is lit over the page")
        kjPause(2)
        kjScreenshot("pip-bar-over-film-page", app: app)
        // The bar's subtitle control works the window's language.
        let captions = app.buttons["pipBarCaptions"]
        XCTAssertEqual(captions.label, "Subtitles · English")
        for _ in 0..<4 where !captions.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.5) }
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        XCTAssertEqual(captions.label, "Subtitles · Off", "the bar turns the window's subtitles off")
        // Play/Pause on the remote works the window wherever focus is.
        XCUIRemote.shared.press(.playPause)
        kjPause(0.8)
        XCTAssertEqual(app.buttons["pipBarToggle"].label, "Play", "Play/Pause paused the window")
        XCUIRemote.shared.press(.playPause)
        kjPause(0.8)
        XCTAssertEqual(app.buttons["pipBarToggle"].label, "Pause")
        // Full screen from the bar over the page: the film opens over it (TopScreen), not under it.
        XCTAssertTrue(kjFocus(fullScreen, app: app), "Left walks back to Full screen")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["playerState"].waitForExistence(timeout: 30), "the film opens over the page")
        XCTAssertTrue(app.otherElements["pipBar"].waitForNonExistence(timeout: 10), "the bar goes with the window")
        kjScreenshot("pip-restored-over-film-page", app: app)
    }

    /// A Receiver channel in the window, the viewer in the Screening Room (a cover): Full screen
    /// opens the channel over the cover (Fable round 2: it opened under it, and only the sound was left).
    func testReceiverComesBackOverACover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "smut", "-kjpipproof", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(kjFocusRegion(app, "indus"), "focus must reach Indus in the region list")
        XCUIRemote.shared.press(.select)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-' AND NOT (identifier BEGINSWITH 'channel-radio-') AND label CONTAINS 'live picture'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 60), "a television channel is listed")
        XCTAssertTrue(kjFocus(tv, app: app), "the remote reaches it")
        XCUIRemote.shared.press(.select)
        try kjTuneUntilPlaying(app)
        let pip = app.buttons["pipControl"]
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        for _ in 0..<6 where !pip.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(pip.isSelected, "Right walks the strip to PiP")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["pipBar"].waitForExistence(timeout: 15), "the window opens with its bar")
        // Into the Screening Room, a cover over the root.
        let rooms = app.buttons["nav-rooms"]
        XCTAssertTrue(kjFocus(rooms, app: app), "the top bar reaches Rooms")
        XCUIRemote.shared.press(.select)
        let door = app.buttons["tvroom-screening"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 30))
        XCTAssertTrue(kjFocus(door, app: app))
        XCUIRemote.shared.press(.select)
        kjPause(2)
        let fullScreen = app.buttons["pipBarFullScreen"]
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 10), "the bar is on the cover")
        XCTAssertTrue(kjFocus(fullScreen, app: app), "Down reaches the bar's Full screen")
        kjScreenshot("pip-bar-on-screening-room", app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["currentChannel"].waitForExistence(timeout: 20), "the channel opens over the cover")
        // Handed back as it plays, as Apple TV does: no tuning first.
        XCTAssertEqual(app.staticTexts["playerState"].label, "Playing", "the playing channel is taken over, not tuned again")
        kjScreenshot("pip-receiver-over-cover", app: app)
        XCUIRemote.shared.press(.menu)
        kjPause(2)
        XCTAssertTrue(door.exists || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'upnext-' OR identifier BEGINSWITH 'film-'")).firstMatch.exists,
                      "Back returns to the Screening Room underneath")
    }

    /// The real window, on a real Apple TV signed in to an account that can watch Transmission:
    /// `TEST_RUNNER_KJ_DEVICE_PIP=<channel>`. The programme on air must carry subtitles for the
    /// plate to show; the photographs are what is checked, by eye, with the result.
    func testTransmissionWindowOnAppleTV() throws {
        guard let wanted = ProcessInfo.processInfo.environment["KJ_DEVICE_PIP"], let channel = Int(wanted) else {
            throw XCTSkip("the real window needs an Apple TV: set TEST_RUNNER_KJ_DEVICE_PIP to a channel number")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "grove", "-kjtab", "transmission"]
        kjLaunch(app)
        let first = app.buttons["transmission-channel-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 60), "the channels load")
        XCTAssertTrue(kjFocus(first, app: app), "channel 1's card takes focus")
        for _ in 1..<channel { XCUIRemote.shared.press(.right); kjPause(0.4) }
        XCUIRemote.shared.press(.select)
        let tuned = app.descendants(matching: .any)["transmissionChannel"]
        XCTAssertTrue(tuned.waitForExistence(timeout: 30), "the player opens")
        // The sign-on and the tune; the strip then hides itself, taking the state line with it.
        kjPause(30)
        kjScreenshot("device-1-full-screen", app: app)
        let pip = app.descendants(matching: .any)["pipControl"]
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        for _ in 0..<5 where !pip.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(pip.isSelected, "Right walks the strip to PiP (it is offered only while the channel plays)")
        XCUIRemote.shared.press(.select)
        let bar = app.otherElements["pipBar"]
        if !bar.waitForExistence(timeout: 20) {
            let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'picture'")).allElementsBoundByIndex.map(\.label)
            XCTFail("the window did not open: \(said)")
            return
        }
        let fullScreen = app.buttons["pipBarFullScreen"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullScreen.hasFocus }, object: nil)], timeout: 10),
                       .completed, "Full screen is lit as the window opens")
        for index in 2...5 {
            kjPause(4)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "device-\(index)-window"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(tuned.waitForExistence(timeout: 40), "one Select brings the channel back full screen")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10), "the bar goes with the window")
        kjPause(10)
        kjScreenshot("device-6-back-full-screen", app: app)
    }

    /// The real window on an Apple TV (`TEST_RUNNER_KJ_DEVICE_FILM=1`): the film's English, drawn by
    /// tvOS in the skin's colours, in the corner; the photographs are the evidence.
    func testFilmWindowOnAppleTV() throws {
        guard ProcessInfo.processInfo.environment["KJ_DEVICE_FILM"] != nil else {
            throw XCTSkip("the real window needs an Apple TV: set TEST_RUNNER_KJ_DEVICE_FILM")
        }
        let app = XCUIApplication()
        try openFullFilm(app, onAppleTV: true)
        let pip = app.descendants(matching: .any)["pipControl"]
        XCTAssertTrue(pip.waitForExistence(timeout: 30), "the full film offers PiP")
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        for _ in 0..<4 where !pip.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCUIRemote.shared.press(.select)
        kjPause(1.5)
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "film-after-pip-press"
        opened.lifetime = .keepAlways
        add(opened)
        let said = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.localizedCaseInsensitiveContains("picture") }
        XCTAssertTrue(app.otherElements["pipBar"].waitForExistence(timeout: 15), "the window opens: \(said)")
        for index in 1...10 {
            kjPause(1.5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "film-window-\(index)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["caption"].waitForExistence(timeout: 60), "back full screen, the house view draws again")
        kjScreenshot("film-back-full-screen", app: app)
    }
}
