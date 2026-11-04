import XCTest

/// A first-time visitor's walk through the app with the remote, photographed at every step, for
/// judging how easy the app is to find your way around. It asserts only that the app answers.
final class TourUITests: XCTestCase {
    func testTour() {
        let app = XCUIApplication()
        app.launchArguments += ["-kjskin", "day", "-kjnoautoplay", "YES"]
        app.launch()
        kjPause(8)
        kjScreenshot("tour-01-launch", app: app)
        for step in 2...5 {
            XCUIRemote.shared.press(.down); kjPause(1.5)
            kjScreenshot("tour-0\(step)-down", app: app)
        }
        XCUIRemote.shared.press(.select); kjPause(6)
        kjScreenshot("tour-06-select", app: app)
        XCUIRemote.shared.press(.select); kjPause(10)
        kjScreenshot("tour-07-select-again", app: app)
        XCUIRemote.shared.press(.down); kjPause(1.5)
        kjScreenshot("tour-08-player-down", app: app)
        XCUIRemote.shared.press(.menu); kjPause(3)
        kjScreenshot("tour-09-back", app: app)
        XCUIRemote.shared.press(.menu); kjPause(3)
        kjScreenshot("tour-10-back-again", app: app)
        // Each section of the top bar, as a first-time visitor opens it.
        app.activate(); kjPause(4)
        for (step, id) in ["nav-transmission", "nav-rooms", "nav-account"].enumerated() {
            let tab = app.buttons[id]
            guard tab.waitForExistence(timeout: 10) else { continue }
            kjFocus(tab, app: app)
            XCUIRemote.shared.press(.select); kjPause(5)
            kjScreenshot("tour-\(11 + step)-\(id)", app: app)
            XCUIRemote.shared.press(.down); kjPause(1.5)
            kjScreenshot("tour-\(11 + step)-\(id)-down", app: app)
        }
    }
}
