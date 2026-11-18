import XCTest

/// The regions must be walkable with the remote: each press down or up the A–Z list beside the
/// map lands on a new region, and the walk never leaves the list. Records the walk so a stuck
/// list shows as a repeat (owner, 2026-10-05: stuck on Horn; the list is the front's one way to a
/// region since 2026-11-17).
final class MapNavigationUITests: XCTestCase {
    func testRegionListWalksBothWays() {
        let app = XCUIApplication()
        kjLaunch(app)
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        kjPause(2)
        let count = regions.count
        XCTAssertGreaterThanOrEqual(count, 8, "the list carries every region with channels")
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(kjFocusRegion(app, regions.element(boundBy: 0).identifier.replacingOccurrences(of: "region-", with: "")),
                      "focus must reach the first region in the list")

        var visited = Set<String>()
        var log: [String] = []
        // Down to the last row and back up four: every press moves, and none leaves the list.
        let walk: [XCUIRemote.Button] = Array(repeating: .down, count: count - 1) + Array(repeating: .up, count: 4)
        for press in walk {
            let before = focused.exists ? focused.identifier : ""
            XCUIRemote.shared.press(press)
            // Focus moves on an animation; read it once it has settled, up to a second later.
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline, (focused.exists ? focused.identifier : "") == before {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            let id = focused.exists ? focused.identifier : "(off list)"
            XCTAssertNotEqual(id, before, "\(press == .down ? "down" : "up") must move to a new region; walk: \(log)")
            visited.insert(id)
            log.append("\(press == .down ? "D" : "U")→\(id)")
        }
        print("MAPWALK " + log.joined(separator: " "))
        kjScreenshot("map-list", app: app)
        XCTAssertFalse(visited.contains("(off list)"), "up and down must stay on the regions; walk: \(log)")
        XCTAssertEqual(visited.count, count - 1, "the walk reaches every region below the first; walk: \(log)")
    }
}
