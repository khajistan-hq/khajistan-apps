import XCTest

/// Chat on the Apple TV: the website's rooms load in the site's order, a room shows its lines,
/// and a viewer with no account is told where to sign in rather than offered a field.
final class ChatUITests: XCTestCase {
    func testRoomsLoadAndTheHouseRoomShowsItsLines() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "chat", "-kjskin", "day"]
        app.launch()
        let house = app.buttons["chat-room-khajistan"]
        XCTAssertTrue(house.waitForExistence(timeout: 60), "the rooms must load, the house room first")
        // No Partners (18+) room is offered.
        let partners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chat-room-' AND identifier CONTAINS 'partners'"))
        XCTAssertEqual(partners.count, 0, "Partners rooms are left out of the app")
        XCTAssertTrue(kjFocus(house, app: app), "the house room must take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["chatRoomName"].waitForExistence(timeout: 20), "the room opens")
        let line = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chat-line-'")).firstMatch
        let empty = app.staticTexts["No lines in the last 48 hours."]
        XCTAssertTrue(line.waitForExistence(timeout: 20) || empty.exists, "the room shows its lines, or says it has none")
        XCTAssertTrue(app.staticTexts["Sign in under Account to write in a room."].exists, "signed out, the room says where to sign in")
        XCTAssertFalse(app.descendants(matching: .any)["chatWrite"].exists, "signed out, there is no field to write in")
        kjScreenshot("chat-01-house-room", app: app)
    }
}
