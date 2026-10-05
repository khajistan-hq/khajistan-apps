import XCTest

/// The Top Shelf is drawn by the Home Screen, not by the app: launch the app so it is installed
/// and on the Home Screen, press Home, walk focus to its icon, and photograph what the Home
/// Screen shows above the row while the icon is focused.
final class TopShelfUITests: XCTestCase {
    func testTopShelfShowsWhileTheIconHasFocus() {
        XCUIApplication().launch()
        XCUIRemote.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 20), "the Home Screen must come up")

        let icon = home.descendants(matching: .any).matching(NSPredicate(format: "label == 'Khajistan'")).firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 20), "the Khajistan icon must be on the Home Screen")
        // The top row starts at its first icon; walk right to Khajistan, then left if it was passed.
        for press in Array(repeating: XCUIRemote.Button.right, count: 12) + Array(repeating: .left, count: 12) {
            if icon.hasFocus { break }
            XCUIRemote.shared.press(press)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        XCTAssertTrue(icon.hasFocus, "the Khajistan icon must take focus")

        // At first the Home Screen shows the static image while it asks the extension; then the
        // carousel. Photograph the first moment, then twice more so the carousel's turn shows too.
        for (n, wait) in [0.5, 12.0, 10.0].enumerated() {
            RunLoop.current.run(until: Date().addingTimeInterval(wait))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "top-shelf-\(n)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        // Up from the icon opens the carousel full screen, with the system's own title and buttons.
        XCUIRemote.shared.press(.up)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        // Then right through the slides: the receiver, then the transmission.
        for n in 1...3 {
            let full = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            full.name = "top-shelf-full-screen-\(n)"
            full.lifetime = .keepAlways
            add(full)
            XCUIRemote.shared.press(.right)
            RunLoop.current.run(until: Date().addingTimeInterval(3))
        }
        // The extension's slides are cells titled by ShelfFeed; the static image has none.
        let slide = home.cells.matching(NSPredicate(
            format: "label ENDSWITH ' live now' OR label BEGINSWITH 'Channel ' OR label == 'Two scheduled channels'")).firstMatch
        XCTAssertTrue(slide.exists, "the Top Shelf must show the extension's carousel, not only the static image")
        print("TOPSHELF " + home.debugDescription)
        XCUIRemote.shared.press(.menu)
    }
}
