import XCTest

/// Home carries every part of Khajistan (owner, 2026-10-29: "all nav carousels should show up in
/// home", and one "should be able to move down a page in home"). From the region strip, a press
/// down at a time walks the shelves under the front to the last one; each shelf reached is
/// photographed. Transmission, the Reading Room and Pics/Vids need no password and must be there;
/// the Madrassa, the Bazaar and Chat are reported when their feeds answer.
final class HomeRowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return element.exists ? element.identifier : "(none)"
    }

    /// The shelf a focused card belongs to, by its identifier.
    private func shelf(of id: String) -> String? {
        let prefixes: [(String, String)] = [
            ("home-door-", "doors"), ("cameras-", "cameras"), ("film-", "films"), ("home-transmission-", "transmission"),
            ("rr-title-", "reading"), ("home-all-the Reading Room", "reading"),
            ("home-pnv-", "picsvids"), ("home-all-Pics/Vids", "picsvids"),
            ("home-post-", "madrassa"), ("home-all-the Madrassa", "madrassa"),
            ("home-product-", "bazaar"), ("home-all-the Bazaar", "bazaar"), ("home-chat-", "chat"),
        ]
        return prefixes.first { id.hasPrefix($0.0) }?.1
    }

    func testDownWalksEveryShelfOnHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjtab", "receiver", "-kjnoautoplay", "YES"]
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60), "the front draws its regions")
        kjPause(8)   // the shelves load a moment after the front
        XCTAssertTrue(kjFocusStrip(app), "focus reaches the region strip")
        var reached: [String] = []
        for _ in 0..<16 {
            XCUIRemote.shared.press(.down)
            kjPause(1.2)
            guard let name = shelf(of: focusedID(app)) else { continue }
            if reached.last != name {
                reached.append(name)
                kjScreenshot("home-\(reached.count)-\(name)", app: app)
            }
        }
        print("KJHOME reached: \(reached.joined(separator: " > "))")
        for required in ["doors", "transmission", "reading", "picsvids"] {
            XCTAssertTrue(reached.contains(required), "down reaches the \(required) shelf; reached \(reached)")
        }

        // Up walks back to the front.
        for _ in 0..<16 where !focusedID(app).hasPrefix("region-") && focusedID(app) != "beyondTheAtlas" {
            XCUIRemote.shared.press(.up)
            kjPause(0.6)
        }
        let back = focusedID(app)
        XCTAssertTrue(back.hasPrefix("region-") || back == "beyondTheAtlas", "up returns to the front, got \(back)")
    }
}
