import XCTest

/// Sign in with your phone, in each skin: Account → Sign in opens on the QR and the code, focus on
/// the way out to email and password, which is one press away and comes back. The code is the
/// DEBUG fixture (`-kjsigninfixture`), so nothing is asked of the tv-sign-in function.
final class PhoneSignInUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDay() { walk("day") }
    func testGrove() { walk("grove") }
    func testSmut() { walk("smut") }

    private func walk(_ skin: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-kjtab", "account", "-kjskin", skin, "-kjsigninfixture", "YES"]
        kjLaunch(app)

        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 15), "Account offers Sign in")
        XCTAssertTrue(kjFocus(signIn, app: app), "the remote reaches Sign in")
        XCUIRemote.shared.press(.select)

        let code = app.staticTexts["tvSignInCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 10), "sign-in opens on the phone panel")
        XCTAssertEqual(code.label, "Code Q R T 4 - M X Z 7", "the code is read out a symbol at a time")
        XCTAssertTrue(app.descendants(matching: .any)["tvSignInQR"].exists, "the QR is drawn")
        XCTAssertEqual(app.staticTexts["tvSignInAddress"].label, "khajistan-archive.pages.dev/activate")
        let password = app.buttons["tvSignInUsePassword"]
        kjPause(1)
        XCTAssertTrue(password.hasFocus, "focus starts on the way to email and password")
        kjScreenshot("\(skin)-phone-sign-in", app: app)

        XCUIRemote.shared.press(.select)
        let back = app.buttons["tvSignInUsePhone"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "email and password, with the way back to the phone")
        kjScreenshot("\(skin)-password-sign-in", app: app)
        XCTAssertTrue(kjFocus(back, app: app), "the remote reaches the way back")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(code.waitForExistence(timeout: 5), "and the phone panel returns")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Menu leaves sign-in")
    }
}
