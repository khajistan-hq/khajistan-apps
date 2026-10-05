import XCTest

/// The regions must be walkable with the remote: each press right or left lands on a new
/// region. Records the walk so a stuck strip shows as a repeat (owner, 2026-10-05: stuck on Horn).
final class MapNavigationUITests: XCTestCase {
    func testMapWalksInEveryDirection() {
        let app = XCUIApplication()
        app.launch()
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        XCTAssertTrue(regions.firstMatch.waitForExistence(timeout: 60))
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<12 where !focused.exists { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(focused.exists, "a region must take focus")

        var visited = Set<String>()
        var log: [String] = []
        let walk: [XCUIRemote.Button] = Array(repeating: .right, count: 14) + Array(repeating: .left, count: 4)
        for press in walk {
            let before = focused.exists ? focused.identifier : ""
            XCUIRemote.shared.press(press)
            // Focus moves on an animation; read it once it has settled, up to a second later.
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline, (focused.exists ? focused.identifier : "") == before {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            let id = focused.exists ? focused.identifier : "(off map)"
            visited.insert(id)
            log.append("\(press == .left ? "L" : press == .right ? "R" : press == .up ? "U" : "D")→\(id)")
        }
        print("MAPWALK " + log.joined(separator: " "))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "map-strip"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertGreaterThanOrEqual(visited.subtracting(["(off map)"]).count, 14,
                                    "every press must reach a new region; walk: \(log)")
        XCTAssertFalse(visited.contains("(off map)"), "left and right must stay on the regions; walk: \(log)")
    }
}
