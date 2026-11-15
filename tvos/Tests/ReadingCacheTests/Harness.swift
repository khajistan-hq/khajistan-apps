// Exercises the production ReadingStore; only platform images, auth and HTTP boundaries are replaced.
import Foundation
import CoreGraphics

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
    static func resumeFirst() {
        let (request, continuation) = pending.removeFirst()
        continuation.resume(returning: reply(request))
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
        await store.start()
        check(store.tabs.contains { $0.id == "arabic" }, "warm catalogue fetches missing module index")
        check(URLSession.requests.count == 1, "missing modules do not redownload public bulk catalogue")
        await store.start()
        check(URLSession.requests.count == 1, "ready shelf does not refetch on appearance")
        #if !KJ_READING_BASELINE
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
        #endif
    }
}
