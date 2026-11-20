import XCTest

/// The preview password opens the whole Receiver dial, and clearing it closes it, with the
/// Receiver already loaded and no relaunch (owner, 2026-11-17: "bring all channels back on apple
/// tv"). The site serves the whole dial only to a session that signed in with its password, so
/// this reads the live site: set TEST_RUNNER_KJ_PREVIEW_PASSWORD to run it. XCUITest logs typed
/// text, so the password is written into the result bundle: delete the bundle after a run.
final class StaffDialUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPasswordOpensAndClosesTheWholeDial() throws {
        guard let password = ProcessInfo.processInfo.environment["KJ_PREVIEW_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("reads the live site with the site password; set TEST_RUNNER_KJ_PREVIEW_PASSWORD")
        }
        let app = XCUIApplication()
        // No recorded fixtures: the sign-in and both dials are the live site's.
        app.launchArguments = ["-kjnoautoplay", "YES", "-kjtab", "account"]
        app.launch()
        clearPassword(app)

        let publicCount = try liveNow(app)
        let publicRows = regionCounts(app)
        kjScreenshot("staff-dial-1-public", app: app)

        open("account", app)
        let set = app.buttons["Set"]
        XCTAssertTrue(set.waitForExistence(timeout: 10), "Account offers to set the preview password")
        XCTAssertTrue(kjFocus(set, app: app), "the remote reaches Set")
        XCUIRemote.shared.press(.select)
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Set opens the password field")
        XCTAssertTrue(kjFocus(field, app: app), "the remote reaches the field")
        XCUIRemote.shared.press(.select)
        kjPause(1.5)
        app.typeText(password)
        XCUIRemote.shared.press(.menu)   // closes the keyboard
        kjPause(1)
        let save = app.buttons["Save"]
        XCTAssertTrue(kjFocus(save, app: app), "the remote reaches Save")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 10), "the password is saved")

        let wholeCount = try liveNow(app, otherThan: publicCount)
        XCTAssertGreaterThan(wholeCount, publicCount, "the password opens the whole dial")
        let wholeRows = regionCounts(app, otherThan: publicRows)
        // The region the whole dial adds most to: its page is read from its own shard.
        let region = try XCTUnwrap(wholeRows.max { a, b in
            (a.value - (publicRows[a.key] ?? 0)) < (b.value - (publicRows[b.key] ?? 0))
        }?.key, "the region rows show live counts")
        let wholeShelves = shelfTotal(app, region: region)
        kjScreenshot("staff-dial-2-whole", app: app)

        clearPassword(app)
        let afterClear = try liveNow(app, otherThan: wholeCount)
        XCTAssertEqual(afterClear, publicCount, "clearing the password closes the whole dial again")
        // The region page's shelves are read from the region's shard, not the index: they must be
        // read again from the public dial too.
        let publicShelves = shelfTotal(app, region: region, otherThan: wholeShelves)
        XCTAssertGreaterThan(wholeShelves, publicShelves, "\(region)'s shelves are read again from the public dial")
        kjScreenshot("staff-dial-3-public-again", app: app)
    }

    private func open(_ section: String, _ app: XCUIApplication) {
        let tab = app.buttons["nav-\(section)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "the top bar shows \(section)")
        XCTAssertTrue(kjFocus(tab, app: app), "the remote reaches \(section)")
        XCUIRemote.shared.press(.select)
        kjPause(1)
    }

    private func clearPassword(_ app: XCUIApplication) {
        open("account", app)
        let clear = app.buttons["Clear"]
        guard clear.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(kjFocus(clear, app: app), "the remote reaches Clear")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Set"].waitForExistence(timeout: 10), "the password is cleared")
    }

    /// The live count on each of the Receiver's region rows, by region id, read once the rows
    /// are on screen and differ from `otherThan` (the redraw on a dial change is not instant).
    private func regionCounts(_ app: XCUIApplication, otherThan previous: [String: Int]? = nil) -> [String: Int] {
        open("receiver", app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let deadline = Date().addingTimeInterval(60)
        var counts: [String: Int] = [:]
        while Date() < deadline {
            counts = [:]
            for row in rows.allElementsBoundByIndex {
                let count = Int(((row.value as? String) ?? "").filter(\.isNumber)) ?? 0
                if count > 0 { counts[row.identifier.replacingOccurrences(of: "region-", with: "")] = count }
            }
            if !counts.isEmpty, counts != previous { return counts }
            kjPause(1)
        }
        XCTFail("the region rows' live counts did not change")
        return counts
    }

    /// The channels on a region page's Television and Radio shelves, as their headers count them,
    /// read once the total differs from `otherThan`. Back returns to the Receiver.
    private func shelfTotal(_ app: XCUIApplication, region: String, otherThan previous: Int? = nil) -> Int {
        open("receiver", app)
        XCTAssertTrue(kjFocusRegion(app, region), "focus reaches \(region) in the region list")
        XCUIRemote.shared.press(.select)
        let headers = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES '^(Television|Radio)[, ]+[0-9]+$'"))
        let deadline = Date().addingTimeInterval(60)
        var total = 0
        while Date() < deadline {
            total = headers.allElementsBoundByIndex.reduce(0) { $0 + (Int($1.label.filter(\.isNumber)) ?? 0) }
            if total > 0, total != previous { break }
            kjPause(1)
        }
        if total == 0 || total == previous { XCTFail("\(region)'s shelves did not change from \(previous.map(String.init) ?? "nothing")") }
        XCUIRemote.shared.press(.menu)
        kjPause(1)
        return total
    }

    /// The Receiver's "Live now" count, read once it differs from `otherThan`.
    private func liveNow(_ app: XCUIApplication, otherThan previous: Int? = nil) throws -> Int {
        open("receiver", app)
        let figure = app.descendants(matching: .any)["receiverLiveNow"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if figure.exists {
                let digits = figure.label.filter(\.isNumber)
                if let count = Int(digits), count > 0, count != previous { return count }
            }
            kjPause(1)
        }
        XCTFail("the Live now count did not change from \(previous.map(String.init) ?? "nothing"): \(figure.exists ? figure.label : "not on screen")")
        return previous ?? 0
    }
}
