// Exercises the production ReadingStore; only platform images, auth and HTTP boundaries are replaced.
import Foundation
import CoreGraphics
import Observation

private func wasSignalled(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now()) == .success
}

final class UIImage: NSObject, @unchecked Sendable {
    var cgImage: CGImage? { nil }
    var size: CGSize { .zero }
    var scale: CGFloat { 1 }
}
enum PnvImages { static func downsample(_ data: Data, maxPixel: Int) -> UIImage? { nil } }
@MainActor final class AuthStore {
    struct Session { let accessToken: String }
    var previewPassword: String?
    var session: Session?
    func validAccessToken() async throws -> String? { nil }
}
enum Transmission {
    static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}
enum SupabaseRoute {
    enum Path: String { case direct, unreachable }
    static let host = "reading-test.invalid"
    static let base = URL(string: "https://reading-test.invalid")!
    static let path = Path.direct
    static let unreachableText = "unreachable"
    static func ready() async -> Path { .direct }
    static func url(_ path: String) -> URL? { URL(string: base.absoluteString + path) }
    static func unrouted(_ url: URL) -> URL { url }
    static func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
@MainActor final class URLSession: @unchecked Sendable {
    static var pending: [(URLRequest, CheckedContinuation<(Data, URLResponse), Error>)] = []
    static var requests: [URLRequest] = []
    static var suspend = false
    static var status = 200
    init(configuration: URLSessionConfiguration) {}
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        Self.requests.append(request)
        guard request.url?.path.hasSuffix("rr-modules.json") == true else {
            throw URLError(.unsupportedURL) // A warm catalogue must not be downloaded again.
        }
        if Self.suspend {
            return try await withCheckedThrowingContinuation { Self.pending.append((request, $0)) }
        }
        return Self.reply(request, status: Self.status)
    }
    static func reply(_ request: URLRequest, status: Int = 200) -> (Data, URLResponse) {
        (status == 200 ? Harness.modules : Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    static func timeOutFirst() {
        pending.removeFirst().1.resume(throwing: URLError(.timedOut))
    }
    static func resumeFirst(status: Int = 200) {
        let (request, continuation) = pending.removeFirst()
        continuation.resume(returning: reply(request, status: status))
    }
}

@main struct Harness {
    static let feed = Data(#"[{"collection_slug":"fixture-title","collection_title":"Fixture title","collection_region":"indus","issues":[{"id":"one","label":"One","pages":10}]}]"#.utf8)
    static let modules = Data(#"{"modules":[{"key":"arabic","name":"Arabic"}],"shelves":[{"key":"books","name":"Books"}],"assign":{"fixture-title":{"module":"arabic","shelf":"books"}}}"#.utf8)
    @MainActor static func check(_ yes: Bool, _ message: String) {
        guard yes else { print("FAIL \(message)"); exit(1) }
        print("PASS \(message)")
    }
    @MainActor static func seed() {
        RRShelfDisk.keepFeed([(RRShelfDisk.key(RRAPI.catalogueRequest(offset: 0)), feed)])
        RRShelfDisk.write(Data("[]".utf8), RRShelfDisk.key(RRAPI.rightsRequest()))
        RRShelfDisk.write(Data("[]".utf8), RRShelfDisk.key(RRAPI.provenanceRequest(offset: 0)))
    }
    @MainActor static func awaitPending() async {
        for _ in 0..<500 where URLSession.pending.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        check(!URLSession.pending.isEmpty, "module fetch reaches suspended HTTP boundary")
    }
    @MainActor static func main() async {
        seed()
        let auth = AuthStore()
        let store = ReadingStore(auth: auth, origin: KJConfig.site)
        #if !KJ_READING_BASELINE
        let initialRevision = store.loadRevision
        #endif
        await store.start()
        #if !KJ_READING_BASELINE
        check(store.loadRevision == initialRevision, "initial start keeps its observed task identity stable")
        #endif
        check(store.tabs.contains { $0.id == "arabic" }, "warm catalogue fetches missing module index")
        check(URLSession.requests.count == 1, "missing modules do not redownload public bulk catalogue")
        await store.start()
        check(URLSession.requests.count == 1, "ready shelf does not refetch on appearance")
        #if !KJ_READING_BASELINE
        check(store.loadRevision == initialRevision, "ready reuse does not change task identity")
        let changed = DispatchSemaphore(value: 0)
        withObservationTracking { _ = store.loadRevision } onChange: { changed.signal() }
        store.previewCredentialDidChange() // Empty Save reaches Clear when the password is already nil.
        check(wasSignalled(changed) && store.loadRevision != initialRevision,
              "nil-to-nil Clear observably changes the mounted shelf task identity")
        let clearedRevision = store.loadRevision
        await store.start()
        check(store.phase == .ready && store.loadRevision == clearedRevision && URLSession.requests.count == 1,
              "revision-triggered reload reuses the cached public shelf without another restart or download")
        // A gated index must never be accepted from disk, even if deletion failed or another process left one.
        let request = URLRequest(url: RRSite.modulesURL(origin: KJConfig.site))
        let gatedKey = RRShelfDisk.key(request) + " @" + KJConfig.site.absoluteString + " gated"
        auth.previewPassword = "test-only-first"
        store.previewCredentialDidChange()
        RRShelfDisk.write(modules, gatedKey)
        URLSession.status = 403
        await store.start()
        check(!store.tabs.contains { $0.id == "arabic" }, "old gated disk index cannot override a refused new credential")
        check(URLSession.requests.count == 2, "credential transition retries only module request")
        URLSession.status = 200
        URLSession.suspend = true
        auth.previewPassword = "test-only-second"
        store.previewCredentialDidChange()
        let old = Task { await store.start() }
        await awaitPending()
        auth.previewPassword = nil
        store.previewCredentialDidChange()
        check(store.tabs.isEmpty && store.phase == .idle, "Clear immediately removes protected module presentation")
        URLSession.resumeFirst()
        await old.value
        check(store.tabs.isEmpty && store.phase == .idle, "late gated response cannot publish after Clear")
        check(RRShelfDisk.read(gatedKey) == nil, "late gated response cannot recreate cleared disk index")
        // Switch again while an older password is in flight; its result must not finish the newer load.
        auth.previewPassword = "test-only-third"
        store.previewCredentialDidChange()
        let first = Task { await store.start() }
        await awaitPending()
        auth.previewPassword = "test-only-fourth"
        store.previewCredentialDidChange()
        let second = Task { await store.start() }
        for _ in 0..<500 where URLSession.pending.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        check(URLSession.pending.count == 2, "replacement credential starts its own request")
        URLSession.resumeFirst()
        await first.value
        check(store.phase == .loading && store.tabs.isEmpty, "old completion cannot finish or publish newer load")
        URLSession.resumeFirst()
        await second.value
        check(store.phase == .ready && store.tabs.contains { $0.id == "arabic" }, "current credential alone publishes module tabs")
        check(RRShelfDisk.read(gatedKey) == nil, "accepted gated modules stay in memory only")
        // A gated index that misses at first paint does not hold the shelf. It is asked for once
        // more behind the shelf, which stays ready, and lands without a loader.
        URLSession.suspend = false
        auth.previewPassword = "test-only-fifth"
        store.previewCredentialDidChange()
        URLSession.suspend = true
        let painting = Task { await store.start() }
        await awaitPending()
        URLSession.resumeFirst(status: 503)
        await painting.value
        check(store.phase == .ready && !store.tabs.contains { $0.id == "arabic" },
              "a missed gated index paints the shelf without it")
        let painted = store.tabs.map(\.id)
        await awaitPending()
        check(store.phase == .ready, "the shelf stays ready while the missed index is asked for again")
        URLSession.resumeFirst()
        for _ in 0..<500 where !store.tabs.contains(where: { $0.id == "arabic" }) { try? await Task.sleep(for: .milliseconds(10)) }
        check(store.phase == .ready && store.tabs.contains { $0.id == "arabic" }, "the late index lands on the ready shelf")
        check(Array(store.tabs.map(\.id).prefix(painted.count)) == painted, "the late tabs are added after the painted ones, not in their place")
        let afterLate = URLSession.requests.count
        URLSession.suspend = false
        await store.start()
        check(URLSession.requests.count == afterLate, "an index in hand is not asked for again")
        // A refused password is final: no late fetch, and opening again asks nothing.
        auth.previewPassword = "test-only-wrong"
        store.previewCredentialDidChange()
        URLSession.status = 401
        let beforeRefusal = URLSession.requests.count
        await store.start()
        try? await Task.sleep(for: .milliseconds(200))
        check(store.phase == .ready && URLSession.requests.count == beforeRefusal + 1, "a refused index is not asked for again")
        await store.start()
        check(URLSession.requests.count == beforeRefusal + 1, "opening the room again after a refusal asks nothing")
        // The right password after a refusal: its missed first fetch still gets the late one.
        URLSession.status = 200
        auth.previewPassword = "test-only-right"
        store.previewCredentialDidChange()
        URLSession.suspend = true
        let again = Task { await store.start() }
        await awaitPending()
        URLSession.timeOutFirst() // No answer at all, so nothing rewrites the old refusal.
        await again.value
        await awaitPending()
        URLSession.resumeFirst()
        for _ in 0..<500 where !store.tabs.contains(where: { $0.id == "arabic" }) { try? await Task.sleep(for: .milliseconds(10)) }
        check(store.tabs.contains { $0.id == "arabic" }, "a new password after a refusal gets its late index")
        URLSession.suspend = false
        #endif
    }
}
