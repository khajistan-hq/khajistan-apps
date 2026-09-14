import XCTest

final class KhajistanUITests: XCTestCase {
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeNavigationAndArchiveGate() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["archiveSearch"].waitForExistence(timeout: 10))
        screenshot("01-Explore", app: app)
        app.buttons["destination-reading"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["closeBrowser"].exists)
        let web = app.webViews.firstMatch
        let gate = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Enter the archive")).firstMatch
        let reading = web.staticTexts["Reading Room"].firstMatch
        let loaded = NSPredicate { _, _ in gate.exists || reading.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 45), .completed,
                       "The website must render its password gate or Reading Room, not merely mount WebKit")
        screenshot(gate.exists ? "02-Archive-password-gate" : "02-Reading-Room", app: app)
        app.buttons["closeBrowser"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Saved"].waitForExistence(timeout: 5))
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

    func testSavedPageSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["destination-receiver"].tap()
        let save = app.buttons["Save page"]
        let remove = app.buttons["Remove saved page"]
        let canSave = NSPredicate { _, _ in save.exists || remove.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: canSave, object: nil)], timeout: 30), .completed)
        if remove.exists { remove.tap() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        app.buttons["closeBrowser"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "open-frequencies")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Saved page must survive app relaunch")
        screenshot("07-Saved-page", app: app)
    }

}
