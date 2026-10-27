import XCTest

/// ROOMS with the Siri Remote: into the databases, the National Broadcast Register (the one
/// database file the site serves without its password, so this reads live data), a record opened
/// whole, and Menu back out; then the Bazaar, which without the site password says so.
final class RoomsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDatabasesRecordAndALockedRoomWithTheRemote() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "rooms", "-kjskin", "grove"]
        kjLaunch(app)

        let databases = app.buttons["tvroom-databases"]
        XCTAssertTrue(databases.waitForExistence(timeout: 15), "Rooms lists the databases")
        XCTAssertTrue(kjFocus(databases, app: app), "the remote reaches Databases")
        kjScreenshot("tv-rooms", app: app)
        XCUIRemote.shared.press(.select)

        let register = app.buttons["tvdb-nationalBroadcasts"]
        XCTAssertTrue(register.waitForExistence(timeout: 10), "the eight systems are listed")
        XCTAssertTrue(kjFocus(register, app: app), "the remote reaches the register")
        XCUIRemote.shared.press(.select)

        let count = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of 257 records'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 40), "the register's 257 services load from the live site")
        kjScreenshot("tv-database", app: app)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvrecord-'")).firstMatch
        XCTAssertTrue(kjFocus(first, app: app), "the remote reaches the first record")
        XCUIRemote.shared.press(.select)
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Broadcaster: '")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "a record opens with its fields named")
        kjScreenshot("tv-record", app: app)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(count.waitForExistence(timeout: 5), "Menu returns to the list")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(register.waitForExistence(timeout: 5), "Menu returns to the systems")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(databases.waitForExistence(timeout: 5), "Menu returns to Rooms")

        let bazaar = app.buttons["tvroom-bazaar"]
        XCTAssertTrue(kjFocus(bazaar, app: app), "the remote reaches the Bazaar")
        XCUIRemote.shared.press(.select)
        let locked = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'behind the site password'")).firstMatch
        let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvproduct-'")).firstMatch
        let shown = NSPredicate { _, _ in locked.exists || shelf.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 30), .completed,
                       "the Bazaar shows its shelf, or says it is behind the password; never an empty room")
        kjScreenshot("tv-bazaar", app: app)
    }
}
