import XCTest
@testable import KhajistanCore

final class PreviewPageTests: XCTestCase {
    func testProtectedPageAvoidsRedirectThatDropsAuthorization() {
        let original = URL(string: "https://khajistan-archive.pages.dev/madrassa.html?q=a%2Fb#reference")!
        XCTAssertEqual(KJURL.canonicalSitePage(original).absoluteString,
                       "https://khajistan-archive.pages.dev/madrassa?q=a%2Fb#reference")
    }

    func testDataFilesAndOtherOriginsAreUnchanged() {
        for text in ["https://khajistan-archive.pages.dev/data/lughat.json",
                     "https://example.com/madrassa.html", "http://khajistan-archive.pages.dev/madrassa.html",
                     "https://khajistan-archive.pages.dev:8443/madrassa.html",
                     "http://127.0.0.1:8831/madrassa.html"] {
            let url = URL(string: text)!
            XCTAssertEqual(KJURL.canonicalSitePage(url), url)
        }
    }
    func testBrowserExchangesPreviewPasswordForCookieWithoutPuttingItInURL() throws {
        let url = URL(string: "https://khajistan-archive.pages.dev/publications.html?q=a%2Fb#books")!
        let request = ArchiveURL.previewRequest(url, password: "p&+=é")
        XCTAssertEqual(request.url?.absoluteString, "https://khajistan-archive.pages.dev/gate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
                       "password=p%26%2B%3D%C3%A9&next=%2Fpublications%3Fq%3Da%252Fb%23books")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testBrowserNeverSendsPreviewPasswordToAnotherOrigin() {
        for text in ["https://example.com/publications.html", "http://khajistan-archive.pages.dev/publications.html",
                     "https://khajistan-archive.pages.dev:8443/publications.html",
                     "https://person@khajistan-archive.pages.dev/publications.html"] {
            let request = ArchiveURL.previewRequest(URL(string: text)!, password: "private")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
        }
        XCTAssertNil(ArchiveURL.previewRequest(ArchiveURL.base, password: nil).httpBody)
        XCTAssertNil(ArchiveURL.previewRequest(ArchiveURL.base, password: "").httpBody)
    }

    func testEncodedHTMLSuffixesDoNotCorruptPercentEncoding() {
        for path in ["madrassa.%68tml", "madrassa%2Ehtml", "madrassa%2ehtml"] {
            let url = URL(string: "https://khajistan-archive.pages.dev/" + path)!
            XCTAssertEqual(KJURL.canonicalSitePage(url), url)
        }
    }

    @MainActor
    func testClearWaitsForInFlightCookieWriteAndRejectsStaleNavigation() async {
        let queue = PreviewNavigationQueue()
        var release: CheckedContinuation<Void, Never>?
        var started = false
        var cookie = false
        var navigated = false
        queue.replace { isCurrent in
            started = true
            // Models a cookie-store callback that completes even after task cancellation.
            await withCheckedContinuation { release = $0 }
            cookie = true
            if isCurrent() { navigated = true }
        }
        while !started { await Task.yield() }
        queue.replace { _ in cookie = false }
        release?.resume()
        await queue.wait()
        XCTAssertFalse(cookie, "Clear runs after the old cookie write finishes")
        XCTAssertFalse(navigated, "the old load cannot navigate after Clear")
    }

    @MainActor
    func testNewNavigationWaitsForStaleWorkAndOwnsFinalState() async {
        let queue = PreviewNavigationQueue()
        var release: CheckedContinuation<Void, Never>?
        var started = false
        var events: [String] = []
        queue.replace { isCurrent in
            started = true
            await withCheckedContinuation { release = $0 }
            events.append("old response")
            if isCurrent() { events.append("old navigation") }
        }
        while !started { await Task.yield() }
        queue.replace { isCurrent in
            events.append("clear old cookie")
            if isCurrent() { events.append("new navigation") }
        }
        release?.resume()
        await queue.wait()
        XCTAssertEqual(events, ["old response", "clear old cookie", "new navigation"])
    }

    @MainActor
    func testClearStillRunsWhenImmediatelyFollowedByNavigation() async {
        let queue = PreviewNavigationQueue()
        var events: [String] = []
        queue.replace(alwaysRun: true) { _ in events.append("clear") }
        queue.replace { _ in events.append("navigate") }
        await queue.wait()
        XCTAssertEqual(events, ["clear", "navigate"])
    }

}
