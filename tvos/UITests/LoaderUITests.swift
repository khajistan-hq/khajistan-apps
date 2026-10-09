import XCTest

/// The loaders carry the website's grooming pigeon (owner, 2026-10-08). Photographs one held on
/// screen in two skins, four frames a quarter second apart, and checks the bird moves.
final class LoaderUITests: XCTestCase {
    func testGroomingPigeonLoops() {
        for skin in ["day", "grove"] {
            let app = XCUIApplication()
            app.launchArguments += ["-kjloaderpreview", "YES", "-kjskin", skin]
            app.launch()
            let words = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Loading the receiver\u{2026}"))
            XCTAssertTrue(words.firstMatch.waitForExistence(timeout: 30), "The loader's words must show")
            sleep(2)
            var frames: [Data] = []
            for index in 0..<4 {
                let shot = app.screenshot()
                frames.append(shot.pngRepresentation)
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "loader-\(skin)-\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
                usleep(250_000)
            }
            XCTAssertGreaterThan(Set(frames).count, 1, "The grooming pigeon must move in \(skin)")
            app.terminate()
        }
    }
}
