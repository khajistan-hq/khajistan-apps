import Foundation

// Drives the app's own PicsVidsStore against answers this file gives (run.sh): the region shelf
// must survive one 500 from a busy server, and must still give up on a refusal.

final class Stub: URLProtocol, @unchecked Sendable {
    /// An HTTP status, or 0 for "the connection timed out".
    nonisolated(unsafe) static var mediaAnswers: [Int] = []
    nonisolated(unsafe) static var mediaRequests = 0
    /// When set, pnv_media answers as the shuffle permutation would: these keys, filtered by the
    /// request's own `shuffle_key=gt.` / `lt.`, ascending, at most `limit`. The size probe gets
    /// `roomSize`, or a 500 when it is nil.
    nonisolated(unsafe) static var shuffleKeys: [Int]?
    nonisolated(unsafe) static var roomSize: Int?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let path = request.url?.path ?? ""
        var status = 200
        var body = Data("[]".utf8)
        var headers = ["Content-Type": "application/json"]
        if path.hasSuffix("/pnv_accounts") {
            body = Data(#"[{"slug":"a","account_key":"a","region_token":"egypt"}]"#.utf8)
        } else if path.hasSuffix("/pnv_media"), let keys = Stub.shuffleKeys {
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let filters = items.filter { $0.name == "shuffle_key" }.compactMap(\.value)
            if items.contains(where: { $0.name == "order" && $0.value == "shuffle_key.desc" }) {
                if let room = Stub.roomSize { body = Data("[{\"shuffle_key\":\(room)}]".utf8) } else { status = 500 }
            } else {
                let gt = filters.first { $0.hasPrefix("gt.") }.flatMap { Int($0.dropFirst(3)) } ?? Int.min
                let lt = filters.first { $0.hasPrefix("lt.") }.flatMap { Int($0.dropFirst(3)) } ?? Int.max
                let limit = items.first { $0.name == "limit" }.flatMap { $0.value }.flatMap(Int.init) ?? 1000
                let page = keys.filter { $0 > gt && $0 < lt }.sorted().prefix(limit)
                let rows = page.map { "{\"media_key\":\"k\($0)\",\"kind\":\"image\",\"account_key\":\"a\",\"shuffle_key\":\($0)}" }
                body = Data(("[" + rows.joined(separator: ",") + "]").utf8)
            }
        } else if path.hasSuffix("/pnv_media") {
            Stub.mediaRequests += 1
            status = Stub.mediaAnswers.isEmpty ? 206 : Stub.mediaAnswers.removeFirst()
            if status == 0 {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            if status < 300 {
                body = Data(#"[{"media_key":"m1","kind":"image","width":10,"height":10,"account_key":"a"}]"#.utf8)
                headers["Content-Range"] = "0-0/1"
            } else {
                body = Data(#"{"message":"canceling statement due to statement timeout"}"#.utf8)
            }
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

        // The shuffle walk, against a room of 1,000 slots holding 250 objects (more than two
        // pages of 120): from any start, every object once, in one rotation of key order.
        func shuffled(room: Int?, _ name: String) async {
            var keys = Set<Int>()
            while keys.count < 250 { keys.insert(Int.random(in: 1...1000)) }
            Stub.shuffleKeys = Array(keys)
            Stub.roomSize = room
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Stub.self]
            let auth = AuthStore()
            let store = PicsVidsStore(auth: auth, configuration: config)
            await store.start()
            store.setShuffled(true)
            var asks = 0
            while !store.feed("egypt").isDone, asks < 20 { await store.loadMore(region: "egypt"); asks += 1 }
            let got = store.feed("egypt").items.compactMap(\.shuffle_key)
            let sorted = keys.sorted()
            let pivot = got.first.flatMap { sorted.firstIndex(of: $0) } ?? 0
            let rotation = Array(sorted[pivot...] + sorted[..<pivot])
            let ok = store.feed("egypt").isDone && got.count == 250 && Set(got) == keys && got == rotation
            if !ok {
                print("FAIL \(name) (rows \(got.count), distinct \(Set(got).count), done \(store.feed("egypt").isDone))")
                failures += 1
            }
            withExtendedLifetime(auth) {}
        }
        for _ in 0..<40 { await shuffled(room: 1000, "shuffle walk from a random start") }
        await shuffled(room: nil, "shuffle walk when the size probe fails (starts at 1, no wrap)")
        print(failures == 0 ? "PASS shuffle walk: 41 walks, every object once, in key order from its start" : "")
        Stub.shuffleKeys = nil
        exit(failures == 0 ? 0 : 1)
    }
}
