import XCTest

/// The picture-in-picture window carries the house caption plate, and the PiP bar brings it back
/// full screen in one press or closes it (owner, 2026-11-17: "pip still not showing subtitles in
/// skin and its hard to navigate into small pip window and click it back up to full screen").
///
/// The simulator has no picture in picture, so `-kjpipproof` shows the frames' layer as a corner
/// window in the app, fed exactly as tvOS's window is. The preview plays as the full film
/// (`-kjfilmasfull`) with English on, in Grove, whose plate (#002800) is a colour no other part of
/// the screen uses: the plate is found by its pixels in the corner, not assumed.
final class PiPWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let film = "filmfarsi-trailers-vol-1-khajistan"

    private func openFullFilm(_ app: XCUIApplication) throws {
        guard let origin = ProcessInfo.processInfo.environment["KJ_FILMS_ORIGIN"], !origin.isEmpty else {
            throw XCTSkip("vod.json is behind the site password; set TEST_RUNNER_KJ_FILMS_ORIGIN to a local server of the archive tree")
        }
        app.launchArguments = ["-kjfilms", origin, "-kjskin", "grove", "-kjfilmasfull", "YES", "-kjpipproof", "YES",
                               "-kj-of-subtitles.\(Self.film)", "en"]
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

    /// Pixels of the Grove caption plate (#002800) in the bottom-right third of the screen.
    private func platePixels(_ shot: XCUIScreenshot) -> Int {
        guard let cg = shot.image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in stride(from: height * 2 / 3, to: height, by: 2) {
            for x in stride(from: width * 2 / 3, to: width, by: 2) {
                let i = (y * width + x) * 4
                if bytes[i] <= 4, abs(Int(bytes[i + 1]) - 40) <= 4, bytes[i + 2] <= 4 { count += 1 }
            }
        }
        return count
    }

    func testWindowCarriesTheCaptionPlateAndComesBackInOnePress() throws {
        let app = XCUIApplication()
        try openFullFilm(app)
        openWindow(app)
        let fullScreen = app.buttons["pipBarFullScreen"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fullScreen.hasFocus }, object: nil)], timeout: 10),
                       .completed, "Full screen is lit as the window opens")
        XCTAssertFalse(app.staticTexts["playerState"].exists, "the player screen has closed behind the window")
        // A cue is up within a few seconds of the trailer; the plate is read off the corner.
        var plate = 0
        for _ in 0..<20 where plate < 200 {
            kjPause(1)
            plate = platePixels(XCUIScreen.main.screenshot())
        }
        kjScreenshot("pip-window-caption-plate", app: app)
        XCTAssertGreaterThan(plate, 200, "the house caption plate is drawn in the corner window")

        // One Select: the film comes back full screen, with its captions.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["playerState"].waitForExistence(timeout: 30), "the film opens full screen again")
        XCTAssertTrue(app.otherElements["pipBar"].waitForNonExistence(timeout: 10), "the bar goes with the window")
        XCTAssertTrue(app.descendants(matching: .any)["caption"].waitForExistence(timeout: 60), "captions come back full screen")
        kjScreenshot("pip-restored-full-screen", app: app)
    }

    /// The negative case: without a caption on, the corner shows no plate (the plate is not the
    /// picture's own colour), and the bar's Close ends the film.
    func testWindowWithSubtitlesOffShowsNoPlateAndCloseEnds() throws {
        let app = XCUIApplication()
        try openFullFilm(app)
        // Subtitles to Off: Down lights Subtitles; English → Off.
        let subtitles = app.descendants(matching: .any)["subtitlesControl"]
        XCUIRemote.shared.press(.down)
        kjPause(0.6)
        XCTAssertTrue(subtitles.isSelected, "Down lights Subtitles")
        XCUIRemote.shared.press(.select)
        kjPause(0.8)
        XCTAssertEqual(subtitles.label, "Subtitles · Off")
        XCUIRemote.shared.press(.menu)   // let go of the lit control
        kjPause(0.6)
        openWindow(app)
        kjPause(6)
        XCTAssertLessThan(platePixels(XCUIScreen.main.screenshot()), 20, "no caption, no plate")
        kjScreenshot("pip-window-no-caption", app: app)
        let close = app.buttons["pipBarClose"]
        for _ in 0..<4 where !close.hasFocus { XCUIRemote.shared.press(.right); kjPause(0.5) }
        XCTAssertTrue(close.hasFocus, "Right walks the bar to Close")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["pipBar"].waitForNonExistence(timeout: 10), "Close takes the bar away")
        kjPause(2)
        XCTAssertFalse(app.staticTexts["playerState"].exists, "Close ends the film rather than reopening it")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'film-'")).firstMatch.exists, "the shelf is there")
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
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 30), "the player opens")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Playing'"), object: state)], timeout: 90),
                       .completed, "the channel plays")
        kjPause(14)
        kjScreenshot("device-1-full-screen", app: app)
        let pip = app.descendants(matching: .any)["pipControl"]
        XCUIRemote.shared.press(.select)
        kjPause(0.6)
        for _ in 0..<5 where !pip.isSelected { XCUIRemote.shared.press(.right); kjPause(0.6) }
        XCTAssertTrue(pip.isSelected, "Right walks the strip to PiP")
        XCUIRemote.shared.press(.select)
        let bar = app.otherElements["pipBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "the window opens and the bar comes up")
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
        XCTAssertTrue(state.waitForExistence(timeout: 40), "one Select brings the channel back full screen")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10), "the bar goes with the window")
        kjPause(10)
        kjScreenshot("device-6-back-full-screen", app: app)
    }
}
