import Foundation

// Drives the app's own PicsVidsStore against answers this file gives (run.sh): the region shelf
// must survive one 500 from a busy server, and must still give up on a refusal. The Receiver's
// list gets one second try after a dropped connection (CI, 2026-11-03: a TLS handshake
// dropped once and the Receiver sat on "The receiver has not loaded" for the rest of the test).

final class Stub: URLProtocol, @unchecked Sendable {
    /// An HTTP status, 0 for "the connection timed out", -1 for "the TLS handshake failed", or -2
    /// for "the host does not resolve".
    nonisolated(unsafe) static var mediaAnswers: [Int] = []
    nonisolated(unsafe) static var mediaRequests = 0
    nonisolated(unsafe) static var indexAnswers: [Int] = []
    nonisolated(unsafe) static var indexRequests = 0
    nonisolated(unsafe) static var probeRequests = 0

    static let tlsText = "A TLS error caused the secure connection to fail."

    static func failure(_ status: Int) -> URLError? {
        switch status {
        case 0: return URLError(.timedOut)
        // The wording URLSession gives this failure on a device, so the screen's text can be checked.
        case -1: return URLError(.secureConnectionFailed, userInfo: [NSLocalizedDescriptionKey: tlsText])
        case -2: return URLError(.cannotFindHost)
        default: return nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let path = request.url?.path ?? ""
        var status = 200
        var body = Data("[]".utf8)
        var headers = ["Content-Type": "application/json"]
        if request.httpMethod == "HEAD" {
            Stub.probeRequests += 1
        } else if path.hasSuffix("/pnv_accounts") {
            body = Data(#"[{"slug":"a","account_key":"a","region_token":"egypt"}]"#.utf8)
        } else if path.hasSuffix("/pnv_media") {
            Stub.mediaRequests += 1
            status = Stub.mediaAnswers.isEmpty ? 206 : Stub.mediaAnswers.removeFirst()
            if let failure = Stub.failure(status) {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            if status < 300 {
                body = Data(#"[{"media_key":"m1","kind":"image","width":10,"height":10,"account_key":"a"}]"#.utf8)
                headers["Content-Range"] = "0-0/1"
            } else {
                body = Data(#"{"message":"canceling statement due to statement timeout"}"#.utf8)
            }
        } else if path.hasSuffix("/receiver-index.json") {
            Stub.indexRequests += 1
            status = Stub.indexAnswers.isEmpty ? 200 : Stub.indexAnswers.removeFirst()
            if let failure = Stub.failure(status) {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            body = Data(#"{"regions":[],"regionFiles":{},"regionCounts":{},"totals":{"channels":0,"live":0,"byMedium":{}}}"#.utf8)
        } else if path.hasSuffix("/rpc/pnv_facets") {
            status = 500
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct PnvRetryHarness {
    @MainActor static func main() async {
        var failures = 0
        // The route probe answers from the stub too, so nothing here reaches the network.
        SupabaseRoute.probeConfiguration = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Stub.self]
            return config
        }
        func run(_ answers: [Int], expectItems: Int, expectRequests: Int, _ name: String) async {
            Stub.mediaAnswers = answers
            Stub.mediaRequests = 0
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Stub.self]
            let auth = AuthStore()   // the store holds it unowned
            let store = PicsVidsStore(auth: auth, configuration: config)
            await store.start()
            await store.loadMore(region: "egypt")
            let feed = store.feed("egypt")
            // A shelf that gives up says so and stops loading; one that recovers carries no error.
            let settled = !feed.isLoading && (expectItems == 0) == (feed.error != nil)
            let ok = feed.items.count == expectItems && Stub.mediaRequests == expectRequests && settled
            print((ok ? "PASS " : "FAIL ") + name + " (rows \(feed.items.count), requests \(Stub.mediaRequests), error \(feed.error ?? "none"))")
            if !ok { failures += 1 }
            withExtendedLifetime(auth) {}
        }
        await run([500], expectItems: 1, expectRequests: 2, "one 500 from a busy server is asked again")
        await run([500, 503], expectItems: 1, expectRequests: 3, "two in a row are asked again")
        await run([500, 500, 500], expectItems: 0, expectRequests: 3, "three in a row: the shelf says so")
        await run([404], expectItems: 0, expectRequests: 1, "a refusal is not asked again")
        await run([0], expectItems: 1, expectRequests: 2, "a timed-out connection is asked again")
        await run([-1], expectItems: 1, expectRequests: 2, "a failed TLS handshake is asked again")
        await run([-2], expectItems: 0, expectRequests: 1, "a host that does not resolve is not asked again")

        func receiver(_ answers: [Int], loads: Bool, expectRequests: Int, shows: String? = nil, _ name: String) async {
            Stub.indexAnswers = answers
            Stub.indexRequests = 0
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Stub.self]
            let store = ReceiverStore(configuration: config)
            await store.loadIndex()
            let ok = (store.index != nil) == loads && (store.indexError == nil) == loads && Stub.indexRequests == expectRequests
                && (shows == nil || store.indexError == shows)
            print((ok ? "PASS " : "FAIL ") + name + " (loaded \(store.index != nil), requests \(Stub.indexRequests), error \(store.indexError ?? "none"))")
            if !ok { failures += 1 }
        }
        await receiver([-1], loads: true, expectRequests: 2, "receiver list: a failed TLS handshake is asked again once")
        await receiver([0], loads: false, expectRequests: 1, "receiver list: a timed-out request is not sent again (SupabaseRoute: only a dropped one is)")
        await receiver([-1, -1], loads: false, expectRequests: 2, shows: Stub.tlsText, "receiver list: two failures in a row, the screen says why")
        await receiver([404], loads: false, expectRequests: 1, "receiver list: an answer from the server is not asked again")
        await receiver([-2], loads: false, expectRequests: 1, "receiver list: a host that does not resolve is not asked again")
        let offline = Stub.probeRequests > 0
        print((offline ? "PASS " : "FAIL ") + "the route probe was answered by the stub (\(Stub.probeRequests) probes)")
        if !offline { failures += 1 }
        exit(failures == 0 ? 0 : 1)
    }
}
