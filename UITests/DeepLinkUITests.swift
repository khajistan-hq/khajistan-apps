import XCTest

/// The links the Top Shelf's slides carry open the screen they name, and a link that is not one
/// changes nothing.
final class DeepLinkUITests: XCTestCase {
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTopShelfLinksOpenTheirScreens() throws {
        let app = XCUIApplication()
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the receiver must load")

        app.open(try XCTUnwrap(URL(string: "khajistan://receiver/indus")))
        // A region page is shelves of channels: its first card is what marks it open.
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 60), "khajistan://receiver/indus must open a region page")
        XCTAssertTrue(app.staticTexts["Indus"].exists, "the region page must be Indus")
        screenshot("link-receiver-indus", app: app)

        app.open(try XCTUnwrap(URL(string: "khajistan://transmission")))
        let state = app.descendants(matching: .any)["transmissionState"]
        XCTAssertTrue(state.waitForExistence(timeout: 60), "khajistan://transmission must open the station page")
        screenshot("link-transmission", app: app)

        // XCUIApplication.open relaunches the app, so each link below lands on a fresh launch, whose
        // screen is the receiver's front. A link that is not one, and a region the index does not
        // list, must leave it there.
        for text in ["khajistan://library", "khajistan://receiver/nowhere", "khajistan://transmission/3"] {
            app.open(try XCTUnwrap(URL(string: text)))
            XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "\(text) must leave the receiver's front")
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            XCTAssertFalse(tv.exists, "\(text) must not open a region page")
            XCTAssertFalse(state.exists, "\(text) must not open the station page")
        }
        screenshot("link-refused", app: app)
    }
}
