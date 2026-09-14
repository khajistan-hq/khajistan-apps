import XCTest

final class KhajistanUITests: XCTestCase {
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeNavigationAndBrowserPresentation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["archiveSearch"].waitForExistence(timeout: 10))
        screenshot("01-Explore", app: app)
        app.buttons["destination-reading"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["closeBrowser"].exists)
        screenshot("02-Archive-browser", app: app)
        app.buttons["closeBrowser"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Keep a page"].waitForExistence(timeout: 5))
        screenshot("03-Library", app: app)
        app.tabBars.buttons["Passport"].tap()
        XCTAssertTrue(app.buttons["Open Passport"].waitForExistence(timeout: 5))
        screenshot("04-Passport", app: app)
    }

    func testRadioDirectoryAndPlayback() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Radio"].tap()
        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("City FM89")
        let namedStation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "City FM89")).firstMatch
        XCTAssertTrue(namedStation.waitForExistence(timeout: 60), "Current receiver should list City FM89")
        screenshot("05-Radio-directory", app: app)
        namedStation.tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout: 60), "AVPlayer must reach actual playback state")
        screenshot("06-Radio-playing", app: app)
        app.buttons["Pause radio"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
    }
}
