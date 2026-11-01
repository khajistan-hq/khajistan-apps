import XCTest

final class OfflineLibraryUITests: XCTestCase {
    func testLibraryControlsInEverySkinAndLargeText() throws {
        for skin in ["day", "grove", "smut"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["-kjtab", "yours", "-kjskin", skin, "-kjautoplay", "NO", "-kjofflineRowFixture"]
            if skin == "smut" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            if skin == "grove", max(app.frame.width, app.frame.height) > 1100 {
                XCUIDevice.shared.orientation = .landscapeLeft
                let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.frame.width > app.frame.height
                }, object: nil)
                wait(for: [landscape], timeout: 8)
            }
            let pause = app.buttons["Pause Filmfarsi — Volume One"].firstMatch
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            XCTAssertTrue(pause.isHittable)
            pause.tap()
            let resume = app.buttons["Resume Filmfarsi — Volume One"].firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 3)); XCTAssertTrue(resume.isHittable)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "offline-library-\(skin)"; shot.lifetime = .keepAlways; add(shot)
            resume.tap()
            XCTAssertTrue(app.buttons["Pause Filmfarsi — Volume One"].firstMatch.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Share"].exists)
            XCTAssertFalse(app.buttons["Export"].exists)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
