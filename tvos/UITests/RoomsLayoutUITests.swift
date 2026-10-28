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
            "-kjtab", "rooms", "-kjskin", skin, "-kjsite", site, "-kjfilms", site,
            "-kj.filmPlaces", "<dict><key>\(Self.stoppedFilm)</key><real>1200</real></dict>",
        ]
        kjLaunch(app)

        let screening = app.buttons["tvroom-screening"]
        XCTAssertTrue(screening.waitForExistence(timeout: 15), "Rooms shows its tiles")
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
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForNonExistence(timeout: 5), "Menu returns to the room")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(screening.waitForExistence(timeout: 5), "Menu returns to Rooms")

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
        XCTAssertTrue(kjFocus(first, app: app), "the remote reaches the first record")
        kjScreenshot("\(skin)-09-table", app: app)
        XCUIRemote.shared.press(.select)
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Broadcaster: '")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "a record opens with its properties named")
        kjPause(2)
        kjScreenshot("\(skin)-10-record", app: app)
    }
}
