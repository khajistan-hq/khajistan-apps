import XCTest

/// What every remote-driven UI test needs: a kept screenshot, a pause that lets focus settle, and
/// a walk toward an element by the Siri Remote's presses.
extension XCTestCase {
    func kjScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func kjPause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// From the top bar to the Receiver's region strip: Down onto the front (it lands on its first
    /// control, Shuffle, or on the strip), then Right off the sidebar onto the strip. Never presses
    /// Select, so nothing on the way is switched.
    @discardableResult
    func kjFocusStrip(_ app: XCUIApplication) -> Bool {
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let shuffle = app.buttons["shuffle"]
        for _ in 0..<4 where !focused.exists && !shuffle.hasFocus { XCUIRemote.shared.press(.down); kjPause(0.3) }
        for _ in 0..<6 where !focused.exists { XCUIRemote.shared.press(.right); kjPause(0.3) }
        return focused.exists
    }

    /// Presses toward `element` until it has focus, steering by where it sits against the focused
    /// control. Returns whether it got there.
    @discardableResult
    func kjFocus(_ element: XCUIElement, app: XCUIApplication, limit: Int = 40) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard element.exists, focused.exists else {
                XCUIRemote.shared.press(.down)
                kjPause(0.4)
                continue
            }
            let target = element.frame, here = focused.frame
            let dx = target.midX - here.midX, dy = target.midY - here.midY
            // A different row first (up or down), then along the row.
            if abs(dy) > max(here.height, target.height) * 0.6 {
                XCUIRemote.shared.press(dy > 0 ? .down : .up)
            } else {
                XCUIRemote.shared.press(dx > 0 ? .right : .left)
            }
            kjPause(0.4)
        }
        return element.exists && element.hasFocus
    }
}
