import XCTest

/// The Rooms door and its four rooms in the Apple TV app's shape, walked with the remote in each
/// skin: the tiles, the Screening Room's Up Next and a film's page with its one Play, a Bazaar
/// object's page, a Madrassa writing, and a database table and record. Every screen is kept as a
/// screenshot for the three-skin look.
///
/// The rooms' files are behind the site password until launch, so the walk reads a local server of
/// the archive tree named by TEST_RUNNER_KJ_SITE (`-kjsite`, and `-kjfilms` for vod.json).
final class RoomsLayoutUITests: XCTestCase {
    /// A film in vod.json with a running time, seeded as stopped twenty minutes in.
    private static let stoppedFilm = "showgirls-of-pakistan-2021-khajistan"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDay() throws { try walk("day") }
    func testGrove() throws { try walk("grove") }
    func testSmut() throws { try walk("smut") }

    /// A film's player is the third full-screen cover (Rooms door, Screening Room, film page,
    /// player). In Day, a cover that deep closed with Menu once sent SwiftUI into a layout loop
    /// under accessibility and the remote stopped answering; Menu must walk back out to the door.
    /// The loop came when tvOS itself closed the cover; the player closes itself, so this walk
    /// passed before the fix too. It guards the path; the cause is in RootView.
    func testDayFilmPlayerClosesWithMenu() throws {
        guard let site = ProcessInfo.processInfo.environment["KJ_SITE"], !site.isEmpty else {
            throw XCTSkip("the rooms' files are behind the site password; set TEST_RUNNER_KJ_SITE to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-kjtab", "rooms", "-kjskin", "day", "-kjsite", site, "-kjfilms", site,
            "-kj.filmPlaces", "<dict><key>\(Self.stoppedFilm)</key><real>1200</real></dict>",
        ]
        kjLaunch(app)
        let screening = app.buttons["tvroom-screening"]
        XCTAssertTrue(screening.waitForExistence(timeout: 15), "Rooms shows its tiles")
        XCTAssertTrue(kjFocus(screening, app: app), "the remote reaches the Screening Room")
        XCUIRemote.shared.press(.select)
        let film = app.buttons.matching(identifier: "upnext-\(Self.stoppedFilm)").firstMatch
        XCTAssertTrue(film.waitForExistence(timeout: 40), "the Screening Room lists its films")
        kjPause(3)
        XCUIRemote.shared.press(.select)
        let play = app.buttons["filmPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "a poster opens the film's page")
        kjPause(2)
        XCTAssertTrue(kjFocus(play, app: app), "the remote reaches Play")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["playerState"].waitForExistence(timeout: 10), "Play opens the player")
        kjPause(2)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Menu closes the player onto the film's page")
        kjPause(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForNonExistence(timeout: 10), "Menu returns to the room")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(screening.waitForExistence(timeout: 10), "Menu returns to Rooms")
        XCTAssertTrue(kjFocus(app.buttons["tvroom-bazaar"], app: app), "the remote still answers")
    }

    /// The music indexes are searched as the phone searches them: every word typed must be in the
    /// song's name or its metadata. Two words of a title and one of the singer's find the song.
    func testIndexSearchFindsASongByTitleAndArtist() throws {
        guard let site = ProcessInfo.processInfo.environment["KJ_SITE"], !site.isEmpty else {
            throw XCTSkip("the indexes are behind the site password; set TEST_RUNNER_KJ_SITE to a local server of the archive tree")
        }
        for skin in ["day", "grove", "smut"] {
            let app = XCUIApplication()
            app.launchArguments = ["-kjtab", "rooms", "-kjroom", "databases", "-kjskin", skin, "-kjsite", site]
            kjLaunch(app)
            let index = app.buttons["tvdb-pakistanMusic"]
            XCTAssertTrue(index.waitForExistence(timeout: 15), "the systems are listed")
            XCTAssertTrue(kjFocus(index, app: app), "the remote reaches the Pakistan Music Index")
            XCUIRemote.shared.press(.select)
            let count = app.staticTexts["tvdbCount"]
            XCTAssertTrue(count.waitForExistence(timeout: 60), "the index loads")
            let total = count.label
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "the index has a search bar")
            XCTAssertTrue(kjFocus(field, app: app), "the remote reaches the search bar")
            XCUIRemote.shared.press(.select)
            kjPause(1.5)
            app.typeText("dayem pada ghulam")
            kjPause(1)
            XCUIRemote.shared.press(.menu)
            let song = app.buttons["tvrecord-KMI-03410"]
            XCTAssertTrue(song.waitForExistence(timeout: 10), "Ghulam Ali's Dayem Pada Huwa is found")
            XCTAssertNotEqual(count.label, total, "the table narrows: \(count.label)")
            kjPause(2)
            kjScreenshot("\(skin)-11-index-search", app: app)
            app.terminate()
        }
    }

    private func walk(_ skin: String) throws {
        guard let site = ProcessInfo.processInfo.environment["KJ_SITE"], !site.isEmpty else {
            throw XCTSkip("the rooms' files are behind the site password; set TEST_RUNNER_KJ_SITE to a local server of the archive tree")
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-kjtab", "rooms", "-kjskin", skin, "-kjsite", site, "-kjfilms", site, "-kjemptybag", "YES",
            "-kj.filmPlaces", "<dict><key>\(Self.stoppedFilm)</key><real>1200</real></dict>",
        ]
        kjLaunch(app)

        let screening = app.buttons["tvroom-screening"]
        XCTAssertTrue(screening.waitForExistence(timeout: 15), "Rooms shows its tiles")
        XCTAssertTrue(app.buttons["tvroom-chat"].exists, "Chat is a tile beside the rooms")
        XCTAssertTrue(kjFocus(screening, app: app), "the remote reaches the Screening Room")
        kjScreenshot("\(skin)-01-rooms", app: app)

        // The Screening Room: Up Next from this device, then a film's page with one Play.
        XCUIRemote.shared.press(.select)
        // The door under the room lists the same film once the catalogue is loaded, so the card is
        // found by focus, which enters the room on its first shelf: Up Next.
        let film = app.buttons.matching(identifier: "upnext-\(Self.stoppedFilm)").firstMatch
        XCTAssertTrue(film.waitForExistence(timeout: 40), "the Screening Room lists its films")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Up Next'")).firstMatch.exists, "a film stopped on this device heads the room as Up Next")
        kjPause(3)
        let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertEqual(focused.identifier, "upnext-\(Self.stoppedFilm)", "focus enters the room on the stopped film")
        kjScreenshot("\(skin)-02-screening", app: app)
        XCUIRemote.shared.press(.select)
        let play = app.buttons["filmPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "a poster opens the film's page")
        XCTAssertTrue(play.label.hasPrefix("Resume from 20:00"), "the one action resumes where this device stopped: \(play.label)")
        kjPause(2)
        XCTAssertTrue(play.hasFocus, "focus starts on the one action")
        kjScreenshot("\(skin)-03-film", app: app)
        // Website: the TV has no browser, so the film's page is a code for the phone.
        let website = app.buttons["filmOnWebsite"]
        XCTAssertTrue(kjFocus(website, app: app), "the remote reaches Website")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["websiteQR"].waitForExistence(timeout: 5), "Website shows a code for the film's page")
        XCTAssertTrue(app.staticTexts["websiteAddress"].label.contains("/film/\(Self.stoppedFilm)"), "and its address")
        kjScreenshot("\(skin)-03b-website", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 5), "Menu returns to the film")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForNonExistence(timeout: 5), "Menu returns to the room")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(screening.waitForExistence(timeout: 5), "Menu returns to Rooms")
        XCTAssertTrue(app.buttons["opened-film|\(Self.stoppedFilm)"].waitForExistence(timeout: 5), "the film is under Opened lately")

        // The Bazaar: objects on soft plates with the price first; an object's page.
        let bazaar = app.buttons["tvroom-bazaar"]
        XCTAssertTrue(kjFocus(bazaar, app: app), "the remote reaches the Bazaar")
        XCUIRemote.shared.press(.select)
        let product = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvproduct-'")).firstMatch
        XCTAssertTrue(product.waitForExistence(timeout: 40), "the Bazaar lists its objects")
        kjPause(4)
        XCTAssertTrue(kjFocus(product, app: app), "the remote reaches an object")
        kjScreenshot("\(skin)-04-bazaar", app: app)
        XCUIRemote.shared.press(.select)
        let address = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'khajistan.com/products/'")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10), "an object's page names where it is bought")
        kjPause(5)
        kjScreenshot("\(skin)-05-object", app: app)
        // The bag, as On's: Add to bag, the bag with a stepper, one Checkout as a code for the
        // phone. Only where the shop answers with the object for sale today.
        let add = app.buttons["tvaddToBag"]
        if add.waitForExistence(timeout: 15) {
            XCTAssertTrue(kjFocus(add, app: app), "the remote reaches Add to bag")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["tvadded"].waitForExistence(timeout: 5), "the object goes in the bag")
            let objectBag = app.buttons["tvobjectBag"]
            XCTAssertTrue(kjFocus(objectBag, app: app), "the remote reaches the bag")
            XCUIRemote.shared.press(.select)
            let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvbagMore-'")).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5), "the bag lists the object with a stepper")
            let counted = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'tvbagCount-'")).firstMatch
            let before = Int(counted.label.components(separatedBy: " ").first ?? "") ?? 0
            XCTAssertTrue(kjFocus(more, app: app), "the remote reaches +")
            XCUIRemote.shared.press(.select)
            let stepped = NSPredicate { _, _ in counted.label.hasPrefix("\(before + 1) ") }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stepped, object: nil)], timeout: 5), .completed,
                           "+ adds one: \(counted.label)")
            kjScreenshot("\(skin)-05b-bag", app: app)
            let checkout = app.buttons["tvbagCheckout"]
            XCTAssertTrue(kjFocus(checkout, app: app), "the remote reaches Checkout")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.descendants(matching: .any)["websiteQR"].waitForExistence(timeout: 20), "Checkout is the shop's page, as a code for the phone")
            kjPause(1)
            kjScreenshot("\(skin)-05c-checkout", app: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(checkout.waitForExistence(timeout: 5), "Menu returns to the bag")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(add.waitForExistence(timeout: 5), "Menu returns to the object")
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Menu returns to the Bazaar")
        XCUIRemote.shared.press(.menu)

        // The Madrassa: serif cards, and a writing read whole.
        let madrassa = app.buttons["tvroom-madrassa"]
        XCTAssertTrue(madrassa.waitForExistence(timeout: 5))
        XCTAssertTrue(kjFocus(madrassa, app: app), "the remote reaches the Madrassa")
        XCUIRemote.shared.press(.select)
        let post = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvpost-'")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 40), "the Madrassa lists its writings")
        kjPause(4)
        XCTAssertTrue(kjFocus(post, app: app), "the remote reaches a writing")
        kjScreenshot("\(skin)-06-madrassa", app: app)
        // The room stays in the tree under the piece, so where focus is says which is on screen.
        let onCard = app.buttons.matching(NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'tvpost-'")).firstMatch
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(onCard.waitForNonExistence(timeout: 10), "a writing opens over the room")
        kjPause(3)
        XCTAssertTrue(app.buttons["tvpostSave"].exists, "a writing has Save beside its date")
        kjScreenshot("\(skin)-07-writing", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(onCard.waitForExistence(timeout: 5), "Menu returns to the Madrassa")
        XCUIRemote.shared.press(.menu)

        // The databases: tiles, a table with hairlines, a record as its properties.
        let databases = app.buttons["tvroom-databases"]
        XCTAssertTrue(databases.waitForExistence(timeout: 5))
        XCTAssertTrue(kjFocus(databases, app: app), "the remote reaches Databases")
        XCUIRemote.shared.press(.select)
        let register = app.buttons["tvdb-nationalBroadcasts"]
        XCTAssertTrue(register.waitForExistence(timeout: 10), "the systems are listed")
        XCTAssertTrue(kjFocus(register, app: app), "the remote reaches the register")
        kjScreenshot("\(skin)-08-databases", app: app)
        XCUIRemote.shared.press(.select)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvrecord-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 40), "the register's records load")
        kjScreenshot("\(skin)-09-table", app: app)

        // Notion's Filter: a property, a value, and the pill that takes itself off.
        let count = app.staticTexts["tvdbCount"]
        let total = count.label
        let filter = app.buttons["tvdbFilter"]
        XCTAssertTrue(kjFocus(filter, app: app), "the remote reaches Filter")
        XCUIRemote.shared.press(.select)
        let value = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvdbValue-'")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5), "Filter lists a property's values")
        XCTAssertTrue(kjFocus(value, app: app), "the remote reaches a value")
        kjScreenshot("\(skin)-09b-filter", app: app)
        XCUIRemote.shared.press(.select)
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tvdbPill-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the filter in force is a pill")
        let narrowed = NSPredicate { _, _ in count.label != total }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: narrowed, object: nil)], timeout: 10), .completed, "the table narrows")
        kjScreenshot("\(skin)-09c-pill", app: app)
        XCTAssertTrue(kjFocus(pill, app: app), "the remote reaches the pill")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5), "Select on the pill takes the filter off")

        // Notion's Sort.
        let sort = app.buttons["tvdbSort"]
        XCTAssertTrue(kjFocus(sort, app: app), "the remote reaches Sort")
        XCUIRemote.shared.press(.select)
        let byTitle = app.buttons["tvdbOrder-title"]
        XCTAssertTrue(byTitle.waitForExistence(timeout: 5), "Sort lists its orders")
        XCTAssertTrue(kjFocus(byTitle, app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.label.contains("A\u{2013}Z"), "the order in force is named: \(sort.label)")

        XCTAssertTrue(kjFocus(first, app: app), "the remote reaches the first record")
        XCUIRemote.shared.press(.select)
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Broadcaster: '")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "a record opens with its properties named")
        kjPause(2)
        kjScreenshot("\(skin)-10-record", app: app)
    }
}
