import XCTest

/// A first-time visitor's walk through every tab, scrolled, and one step into what each offers,
/// photographed at every step for judging how easy the app is to find your way around.
final class TourUITests: XCTestCase {
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-kjskin", "day", "-kjstorefront", "USA"]
        app.launch()
        sleep(10)
        shot("tour-00-launch", app)
        let bar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'"))
        let tabs = (0..<bar.count).map { bar.element(boundBy: $0).identifier }
        for (index, id) in tabs.enumerated() {
            app.buttons[id].tap(); sleep(4)
            shot("tour-\(index + 1)-\(id)-a", app)
            app.swipeUp(); sleep(2)
            shot("tour-\(index + 1)-\(id)-b", app)
            app.swipeUp(); sleep(2)
            shot("tour-\(index + 1)-\(id)-c", app)
            app.swipeUp(); sleep(2)
            shot("tour-\(index + 1)-\(id)-d", app)
        }
        // The taps a child makes on the Receiver: a region, then the set's other two tabs.
        app.buttons["tab-receiver"].tap(); sleep(3)
        let region = app.buttons["region-maghreb"]
        for _ in 0..<6 where !(region.exists && region.isHittable) { app.swipeUp(); sleep(1) }
        if region.exists && region.isHittable { region.tap(); sleep(6); shot("tour-6-receiver-tap-region", app) }
        // Only where the button can be tapped, as the region and the website are: after a region
        // opens, a slow runner can leave the parts scrolled under the header (CI, PR 9).
        for part in ["part-cameras", "part-transmission"] where app.buttons[part].exists && app.buttons[part].isHittable {
            app.buttons[part].tap(); sleep(6); shot("tour-6-receiver-\(part)", app)
        }
        if app.buttons["part-live"].isHittable { app.buttons["part-live"].tap(); sleep(1) }
        // A room that opens the website, and the way back.
        if app.buttons["tab-rooms"].exists {
            app.buttons["tab-rooms"].tap()
        } else {   // a phone's bar has no ROOMS: HOME's "Every room" opens it
            app.buttons["tab-home"].tap()
            let link = app.buttons["homeAllRooms"]
            let floor = app.buttons["tab-home"].frame.minY - 4
            for _ in 0..<16 where !(link.exists && !link.frame.isEmpty && link.frame.maxY < floor) { app.swipeUp(); sleep(1) }
            link.tap()
        }
        sleep(2)
        let web = app.buttons["destination-about"]
        for _ in 0..<6 where !(web.exists && web.isHittable) { app.swipeUp(); sleep(1) }
        if web.exists && web.isHittable { web.tap(); sleep(8); shot("tour-7-rooms-website", app) }
        // One step in: the first thing a child would tap on Home.
        app.buttons[tabs[0]].tap(); sleep(2)
        app.swipeDown(); app.swipeDown(); sleep(2)
        let first = app.scrollViews.firstMatch.buttons.firstMatch
        if first.exists && first.isHittable { first.tap(); sleep(6); shot("tour-9-home-first-tap", app) }
        XCTAssertTrue(app.state == .runningForeground)
    }
}
