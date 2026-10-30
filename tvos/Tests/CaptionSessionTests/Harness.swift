// Compiles the actual service and shared caption core against in-memory platform boundaries.
// No DNS, HTTP, websocket, account, or paid caption worker is contacted.
import Foundation

enum SupabaseRoute { static let base = URL(string: "https://caption-test.invalid")! }

@MainActor final class AuthStore {
    var isSignedIn = true
    func validAccessToken() async throws -> String { "synthetic-test-token" }
}

@MainActor final class PlayerController {
    enum State { case playing, paused }
    var state = State.playing
    struct CaptionClock {
        let now: Double
        let behindLive: Double
        let programDate: Date?
        let window: ClosedRange<Double>?
    }
    var now = 100.0
    var behind = 24.0
    var window: ClosedRange<Double>? = nil
    var program = true
    var seeks: [Double] = []
    var pendingSeek: (@MainActor () -> Void)?
    var lateSeekCompletion: (@MainActor () -> Void)?
    var cancelledSeeks = 0
    var captionClock: CaptionClock? {
        CaptionClock(now: now, behindLive: behind, programDate: program ? Date(timeIntervalSince1970: 900 + now) : nil, window: window)
    }
    func seekBack(by seconds: Double, completion: @escaping @MainActor () -> Void) {
        seeks.append(seconds)
        lateSeekCompletion = completion
        pendingSeek = { [self] in now -= seconds; behind += seconds; completion() }
    }
    func cancelCaptionSeek() { cancelledSeeks += 1; pendingSeek = nil }
    func completeSeek() { let held = pendingSeek; pendingSeek = nil; held?() }
}

@MainActor final class URLSessionWebSocketTask {
    enum Message { case string(String), data(Data) }
    enum CloseCode { case goingAway }
    private var frames: [Message] = []
    private var waiter: CheckedContinuation<Message, Error>?
    private(set) var cancelled = false
    private(set) var sent: [String] = []
    func resume() {}
    func send(_ message: Message) async throws {
        guard !cancelled else { throw URLError(.cancelled) }
        if case .string(let text) = message { sent.append(text) }
    }
    func receive() async throws -> Message {
        guard !cancelled else { throw URLError(.cancelled) }
        if !frames.isEmpty { return frames.removeFirst() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func push(_ text: String) {
        guard !cancelled else { return }
        if let held = waiter { waiter = nil; held.resume(returning: .string(text)) }
        else { frames.append(.string(text)) }
    }
    func cancel(with: CloseCode, reason: Data?) {
        cancelled = true
        let held = waiter; waiter = nil
        held?.resume(throwing: URLError(.cancelled))
    }
}

@MainActor final class Network {
    static var current = Network()
    var sockets: [URLSessionWebSocketTask] = []
    var requests: [String] = []
    var stallRecovery = false
    var recoveryWaiters: [CheckedContinuation<Void, Never>] = []
    var translationWaiters: [CheckedContinuation<Void, Never>] = []
    var translations = 0
    var translationReturnsNil = false
    var recoveryRequests = 0
    var recoveryRows: [[String: Any]] = []
    func releaseRecovery() { let held = recoveryWaiters; recoveryWaiters = []; held.forEach { $0.resume() } }
    func releaseTranslations() { let held = translationWaiters; translationWaiters = []; held.forEach { $0.resume() } }
    func data(_ request: URLRequest) async -> (Data, URLResponse) {
        let url = request.url!
        requests.append(url.path)
        var body: Any = []
        if url.path.contains("request-captions") {
            let sent = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            body = ["allowed": true, "billing_mode": "enforced", "unlimited": true,
                    "session_id": sent["session_id"] ?? NSNull(),
                    "lease_expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(120)),
                    "heartbeat_seconds": 60]
        } else if url.path.contains("translate-caption") {
            translations += 1
            if translationReturnsNil {
                body = ["english": NSNull()]
            } else {
                // Deliberately ignores cancellation, like an uncooperative response/auth boundary.
                await withCheckedContinuation { translationWaiters.append($0) }
                body = ["english": "EXPIRED TRANSLATION MUST NEVER APPEAR"]
            }
        } else if url.path.contains("live_caption_wire") {
            recoveryRequests += 1
            if stallRecovery { await withCheckedContinuation { recoveryWaiters.append($0) } }
            body = recoveryRows
        } else if url.path.contains("caption-accuracy") {
            body = ["extended_regions": [], "languages": [:], "by_channel": [:]] as [String: Any]
        }
        return (try! JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor final class URLSession {
    private let network: Network
    init(configuration: URLSessionConfiguration) { network = Network.current }
    func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        let socket = URLSessionWebSocketTask(); network.sockets.append(socket); return socket
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { await network.data(request) }
    func data(from url: URL) async throws -> (Data, URLResponse) { await network.data(URLRequest(url: url)) }
}

struct TestFailure: Error, CustomStringConvertible { let description: String }
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}
@MainActor func eventually(_ message: String, timeout: Double = 2, _ condition: @escaping @MainActor () -> Bool) async throws {
    let until = ContinuousClock.now.advanced(by: .seconds(timeout))
    while !condition() && ContinuousClock.now < until { try await Task.sleep(for: .milliseconds(20)) }
    try check(condition(), message)
}

@MainActor func channel(_ id: String = "caption-test") throws -> Channel {
    let object: [String: Any] = ["id": id, "name": "Fixture", "mediaType": "tv", "primaryLanguage": "Urdu",
                               "languageCode": "ur", "country": "Pakistan", "regionIds": ["indus"],
                               "streams": [["id": "fixture-stream"]], "activeStreamId": "fixture-stream"]
    return try JSONDecoder().decode(Channel.self, from: JSONSerialization.data(withJSONObject: object))
}
func subscribed(_ id: String = "caption-test") -> String {
    "{\"topic\":\"realtime:captions:\(id)\",\"event\":\"phx_reply\",\"payload\":{\"status\":\"ok\"}}"
}
func row(_ id: Int, text: String, at: Double = 100, english: Bool = true, channel: String = "caption-test", event: String = "INSERT", native: String = "خبر", uncertain: Bool = false) -> String {
    let record: [String: Any] = ["id": id, "channel_id": channel, "text": native, "english": english ? text : "", "uncertain": uncertain,
                               "lang": "ur", "final": true, "program_epoch": 900 + at,
                               "at_epoch": Date().timeIntervalSince1970, "spoken_seconds": 2]
    let object: [String: Any] = ["topic": "realtime:captions:\(channel)", "event": "postgres_changes",
                               "payload": ["data": ["type": event, "record": record]]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

/// UPDATE is a changed copy of the original wire frame, retaining its exact source timestamps.
func update(_ original: String, text: String, native: String? = nil, uncertain: Bool? = nil, at: Double? = nil) -> String {
    var object = try! JSONSerialization.jsonObject(with: Data(original.utf8)) as! [String: Any]
    var payload = object["payload"] as! [String: Any]
    var data = payload["data"] as! [String: Any]
    var record = data["record"] as! [String: Any]
    record["english"] = text
    if let native { record["text"] = native }
    if let uncertain { record["uncertain"] = uncertain }
    if let at { record["program_epoch"] = 900 + at }
    data["record"] = record
    data["type"] = "UPDATE"
    payload["data"] = data
    object["payload"] = payload
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

@MainActor struct Fixture {
    let network: Network
    let player: PlayerController
    let service: LiveCaptionSession
    init() throws {
        network = Network(); Network.current = network
        player = PlayerController()
        service = LiveCaptionSession(auth: AuthStore())
        service.attach(try channel(), player: player)
    }
    func start() async throws {
        service.toggle()
        try await eventually("service should start socket") { !network.sockets.isEmpty }
        network.sockets.last!.push(subscribed())
    }
    func finish() {
        service.detach()
        network.releaseRecovery()
        network.releaseTranslations()
    }
}

@main struct CaptionSessionHarness {
    @MainActor static func main() async {
        var failed = 0
        let allTests: [(String, @MainActor () async throws -> Void)] = [
            ("websocket reconnects while REST stalls", reconnect),
            ("translation absolute deadline and late result", translationDeadline),
            ("seek completion preserves source anchor", seekPlacement),
            ("stop fences delayed response and seek", stopFences),
            ("retune fences old captions and reconnect", retuneFences),
            ("seek watchdog and late completion", seekWatchdog),
            ("non-seekable programme-clock captions remain available", nonSeekable),
            ("fresh REST fallback adapts hold", freshRecovery),
            ("stale REST fallback cannot rewind", staleRecovery),
            ("REST delivers while socket is offline", offlineRecovery),
            ("English UPDATE unblocks ordered captions once", updateUnblocks),
            ("English UPDATE fallback nil waits until deadline", nilFallbackDeadline),
            ("English UPDATE rejects changed or uncertain source", unsafeUpdates),
            ("English UPDATE cannot cross a retune", updateRetune),
            ("short HLS window keeps fresh speech readable", shortWindow),
            ("fresh REST receipt survives translation wait", receiptFreshness)
        ]
        let filter = ProcessInfo.processInfo.environment["KJ_CAPTION_TEST_FILTER"]
        let tests = allTests.filter { entry in filter.map { entry.0.contains($0) } ?? true }
        guard !tests.isEmpty else { print("FAIL no tests matched filter"); exit(1) }
        for (name, test) in tests {
            do { try await test(); print("PASS \(name)") }
            catch { failed += 1; print("FAIL \(name): \(error)") }
        }
        print("Caption session: \(tests.count - failed)/\(tests.count) passed; no external network")
        exit(failed == 0 ? 0 : 1)
    }

    @MainActor static func updateUnblocks() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        let socket = f.network.sockets[0]
        let original = row(80, text: "", english: false)
        socket.push(original)
        try await eventually("missing English starts translation") { f.network.translations == 1 }
        socket.push(row(81, text: "Second sentence.", at: 104))
        try await Task.sleep(for: .milliseconds(150))
        try check(f.service.text == nil, "later ready sentence waits for the first")
        socket.push(update(original, text: "First updated sentence."))
        try await eventually("same-id English UPDATE must unblock its pending source") { f.service.text == "First updated sentence." }
        socket.push(update(original, text: "DUPLICATE MUST NOT REPLAY"))
        f.network.releaseTranslations()
        try await Task.sleep(for: .milliseconds(150))
        f.player.now = 102.5
        try await eventually("rendered update must not replay after its readable interval") { f.service.text == nil }
        f.player.now = 104
        try await eventually("second sentence retains source order and time") { f.service.text == "Second sentence." }
        try check(f.network.translations == 1, "an English update does not start another translation")
    }

    @MainActor static func nilFallbackDeadline() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.network.translationReturnsNil = true
        try await f.start()
        let socket = f.network.sockets[0]
        let original = row(82, text: "", english: false)
        socket.push(original)
        try await eventually("fallback request answered nil") { f.network.translations == 1 }
        socket.push(row(83, text: "After deadline sentence.", at: 104))
        f.player.now = 104
        try await Task.sleep(for: .milliseconds(250))
        try check(f.service.text == nil, "nil fallback cannot discard pending source before wire update deadline")
        try await eventually("nil fallback still expires at the absolute eight-second deadline", timeout: 8.2) {
            f.service.text == "After deadline sentence."
        }
        socket.push(update(original, text: "EXPIRED UPDATE MUST NOT REPLAY"))
        try await Task.sleep(for: .milliseconds(150))
        f.player.now = 107
        try await eventually("expired English update cannot replay after newer speech") { f.service.text == nil }
    }

    @MainActor static func unsafeUpdates() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        let socket = f.network.sockets[0]
        let original = row(84, text: "", english: false)
        socket.push(original)
        try await eventually("pending source exists") { f.network.translations == 1 }
        for unsafe in [update(original, text: "UNCERTAIN UPDATE", uncertain: true),
                       update(original, text: "CHANGED SOURCE", native: "دوسری خبر"),
                       update(original, text: "CHANGED TIME", at: 101)] {
            socket.push(unsafe)
            try await Task.sleep(for: .milliseconds(150))
            try check(f.service.text == nil, "uncertain or source-changing update cannot supply pending English")
        }
        socket.push(update(original, text: "Verified source identity."))
        try await eventually("rejected changes must leave the original pending source recoverable") {
            f.service.text == "Verified source identity."
        }
    }

    @MainActor static func updateRetune() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        let old = f.network.sockets[0]
        let original = row(85, text: "", english: false)
        old.push(original)
        try await eventually("old pending translation exists") { f.network.translations == 1 }
        f.service.attach(try channel("update-new-channel"), player: f.player)
        f.service.toggle()
        try await eventually("retune opens replacement") { f.network.sockets.count == 2 }
        let current = f.network.sockets[1]
        current.push(subscribed("update-new-channel"))
        // Feed old-topic data through the current transport as well as the canceled transport.
        current.push(update(original, text: "OLD UPDATE"))
        old.push(update(original, text: "OLD UPDATE"))
        f.network.releaseTranslations()
        current.push(row(86, text: "Current channel only.", channel: "update-new-channel"))
        try await eventually("only current source renders") { f.service.text == "Current channel only." }
        f.player.now = 103
        try await eventually("old update has not queued behind current caption") { f.service.text == nil }
    }

    @MainActor static func receiptFreshness() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.player.window = 88...108
        f.player.behind = 8
        f.network.stallRecovery = true
        try await f.start()
        try await eventually("fresh source awaits REST delivery") { !f.network.recoveryWaiters.isEmpty }
        var record = recoveryRecord(89, text: "", createdAge: 0)
        record["program_epoch"] = 992.0
        f.network.recoveryRows = [record]
        f.network.releaseRecovery()
        try await eventually("fresh recovered source waits for English") { f.network.translations == 1 }
        let object: [String: Any] = ["topic": "realtime:captions:caption-test", "event": "postgres_changes",
                                   "payload": ["data": ["type": "INSERT", "record": record]]]
        let original = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        try await Task.sleep(for: .seconds(6))
        try check(f.service.text == nil, "untranslated source does not paint before the update")
        f.network.sockets[0].push(update(original, text: "English after six seconds."))
        try await eventually("receipt freshness must survive six-second translation wait before eight-second deadline", timeout: 1) {
            f.service.text == "English after six seconds."
        }
        try check(f.service.note.localizedCaseInsensitiveContains("approximate"), "short-window timing remains honestly approximate")
        try check(f.player.seeks.isEmpty, "translation wait cannot force an unsafe short-window seek")
    }

    @MainActor static func shortWindow() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.player.window = 88...108
        f.player.behind = 8
        f.network.stallRecovery = true
        try await f.start()
        f.network.sockets[0].push(row(87, text: "Fresh short-window speech.", at: 92))
        try await eventually("8s-late fresh source must remain readable in a 20s HLS window") {
            f.service.text == "Fresh short-window speech."
        }
        try check(f.player.seeks.isEmpty, "cannot rewind beyond the stream's safe window")
        try check(f.service.note.localizedCaseInsensitiveContains("approximate"), "must disclose approximate timing")
        f.player.now = 103
        try await eventually("fresh line clears after its reading interval") { f.service.text == nil }
        try await eventually("backfill request is suspended") { !f.network.recoveryWaiters.isEmpty }
        var old = recoveryRecord(88, text: "OLD SHORT-WINDOW BACKFILL", createdAge: 20)
        old["program_epoch"] = 992.0
        f.network.recoveryRows = [old]
        f.network.releaseRecovery()
        try await Task.sleep(for: .milliseconds(200))
        try check(f.service.text == nil && f.player.seeks.isEmpty, "stale short-window recovery must still drop")
    }

    @MainActor static func reconnect() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.network.stallRecovery = true
        try await f.start()
        try await eventually("REST recovery should be suspended") { !f.network.recoveryWaiters.isEmpty }
        f.network.sockets[0].push(row(1, text: "First socket speech."))
        try await eventually("live websocket must paint without waiting for REST") { f.service.text == "First socket speech." }
        f.network.sockets[0].cancel(with: .goingAway, reason: nil)
        try await eventually("closed feed must reconnect within two seconds", timeout: 2.5) { f.network.sockets.count == 2 }
        try check(f.network.sockets[0].cancelled, "only replacement socket remains open")
        f.network.sockets[1].push(subscribed())
        f.player.now = 103
        f.network.sockets[1].push(row(2, text: "Replacement socket speech.", at: 103))
        try await eventually("replacement feed should paint immediately") { f.service.text == "Replacement socket speech." }
        f.service.detach()
        let connections = f.network.sockets.count
        try await Task.sleep(for: .milliseconds(1300))
        try check(f.network.sockets.count == connections, "stop must not reconnect")
        try check(f.network.sockets.allSatisfy(\.cancelled), "stop closes every socket")
        try check(f.service.text == nil, "stop clears caption")
    }

    @MainActor static func translationDeadline() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        let socket = f.network.sockets[0]
        socket.push(row(10, text: "", english: false))
        try await eventually("translation should be awaiting its response") { f.network.translations == 1 }
        socket.push(row(11, text: "Ready subsequent speech.", at: 104))
        f.player.now = 104
        try await Task.sleep(for: .milliseconds(300))
        try check(f.service.text == nil, "ready speech cannot overtake the unresolved earlier sentence")
        try await eventually("head must expire by eight seconds plus one tick", timeout: 8.2) { f.service.text == "Ready subsequent speech." }
        f.network.releaseTranslations()
        try await Task.sleep(for: .milliseconds(200))
        try check(f.service.text == "Ready subsequent speech.", "expired response must not replay or overwrite")
    }

    @MainActor static func seekPlacement() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.player.window = 0...200
        try await f.start()
        f.network.sockets[0].push(row(20, text: "Source at ninety four.", at: 94))
        try await eventually("late source should request a ten-second hold") { f.player.pendingSeek != nil }
        try check(f.player.seeks == [10], "seek must reserve source lateness plus margin")
        try check(f.service.text == nil, "cannot paint from the pre-seek clock")
        f.player.completeSeek()
        try check(f.player.now == 90, "fixture seek completed at ninety")
        try await Task.sleep(for: .milliseconds(150))
        try check(f.service.text == nil, "source is still four seconds ahead")
        f.player.now = 94
        try await eventually("source cue paints at ninety four, not old playhead one hundred") { f.service.text == "Source at ninety four." }
    }

    @MainActor static func seekWatchdog() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.player.window = 0...200
        try await f.start()
        f.network.sockets[0].push(row(50, text: "Seek timeout speech.", at: 96))
        try await eventually("seek pending") { f.player.pendingSeek != nil }
        let late = f.player.lateSeekCompletion
        try await eventually("stalled seek must release caption processing after eight seconds", timeout: 8.5) {
            f.player.cancelledSeeks == 1 && f.service.text == "Seek timeout speech."
        }
        f.player.now = 103
        f.network.sockets[0].push(row(51, text: "After timeout speech.", at: 103))
        try await eventually("current speech should flow after seek timeout") { f.service.text == "After timeout speech." }
        late?()
        try await Task.sleep(for: .milliseconds(200))
        try check(f.service.text == "After timeout speech.", "late seek callback cannot restart or alter placement")
        try check(f.player.seeks.count == 1, "watchdog must not enter a repeated rewind loop")
    }

    @MainActor static func nonSeekable() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        f.network.sockets[0].push(row(60, text: "Nonseekable current speech.", at: 80))
        try await eventually("late caption with PDT but no seek window remains readable") { f.service.text == "Nonseekable current speech." }
        try check(f.player.seeks.isEmpty, "cannot rewind a nonseekable carrier")
    }

    @MainActor static func recoveryRecord(_ id: Int, text: String, createdAge: Double?) -> [String: Any] {
        var result: [String: Any] = ["id": id, "channel_id": "caption-test", "text": "خبر", "english": text,
                                     "lang": "ur", "final": true, "at_epoch": Date().timeIntervalSince1970 - 32,
                                     "spoken_seconds": 2]
        if let createdAge {
            result["created_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-createdAge))
        }
        return result
    }

    @MainActor static func freshRecovery() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.player.program = false
        f.player.window = 0...200
        f.network.stallRecovery = true
        try await f.start()
        try await eventually("REST request is awaiting its response") { !f.network.recoveryWaiters.isEmpty }
        f.network.recoveryRows = [recoveryRecord(70, text: "Fresh REST source speech.", createdAge: 0)]
        f.network.releaseRecovery()
        try await eventually("fresh fallback lag32/hold24 must adapt instead of dropping forever") { f.player.pendingSeek != nil }
        try check(f.player.seeks.count == 1 && f.player.seeks[0] >= 12 && f.player.seeks[0] <= 14,
                  "fresh REST must reserve measured lag plus four-second margin")
        f.player.completeSeek()
        // The fixed source clock maps to approximately92; use the middle of its readable interval.
        f.player.now = 92.5
        try await eventually("fresh recovered speech must display after adaptive seek") { f.service.text == "Fresh REST source speech." }
    }

    @MainActor static func staleRecovery() async throws {
        for age in [Optional(20.0), nil] {
            let f = try Fixture(); defer { f.finish() }
            f.player.program = false
            f.player.window = 0...200
            f.network.stallRecovery = true
            try await f.start()
            try await eventually("backfill request suspended") { !f.network.recoveryWaiters.isEmpty }
            f.network.recoveryRows = [recoveryRecord(71, text: "Obsolete recovered speech.", createdAge: age)]
            f.network.releaseRecovery()
            try await Task.sleep(for: .milliseconds(200))
            try check(f.player.seeks.isEmpty, "stale or undated REST rows cannot rewind playback")
            try check(f.service.text == nil, "obsolete fallback cannot displace current speech")
        }
    }

    @MainActor static func offlineRecovery() async throws {
        let f = try Fixture(); defer { f.finish() }
        f.network.stallRecovery = true
        try await f.start()
        try await eventually("offline fixture has recovery request") { !f.network.recoveryWaiters.isEmpty }
        f.network.sockets[0].cancel(with: .goingAway, reason: nil)
        var record = recoveryRecord(72, text: "REST while offline.", createdAge: 0)
        record["program_epoch"] = 1000.0
        f.network.recoveryRows = [record]
        f.network.releaseRecovery()
        try await eventually("REST must deliver without an active socket", timeout: 0.8) { f.service.text == "REST while offline." }
        try check(f.network.sockets.count == 1 && f.network.sockets[0].cancelled,
                  "caption came from REST before reconnect opened another socket")
    }

    @MainActor static func retuneFences() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        let old = f.network.sockets[0]
        old.push(row(40, text: "", english: false))
        try await eventually("old channel translation started") { f.network.translations == 1 }
        f.service.attach(try channel("new-channel"), player: f.player)
        f.service.toggle()
        try await eventually("retune creates one new connection") { f.network.sockets.count == 2 }
        let current = f.network.sockets[1]
        current.push(subscribed("new-channel"))
        current.push(row(41, text: "New channel speech.", channel: "new-channel"))
        f.network.releaseTranslations()
        old.push(row(42, text: "OLD CHANNEL MUST NOT APPEAR"))
        try await eventually("only new station captions display") { f.service.text == "New channel speech." }
        try check(old.cancelled, "retune cancels the old socket")
        try await Task.sleep(for: .milliseconds(1200))
        try check(f.network.sockets.count == 2, "old reconnect loop must not open a third socket")
        try check(f.service.text == "New channel speech.", "old translator cannot overwrite new channel")
    }

    @MainActor static func stopFences() async throws {
        let f = try Fixture(); defer { f.finish() }
        try await f.start()
        f.network.sockets[0].push(row(30, text: "", english: false))
        try await eventually("translation started") { f.network.translations == 1 }
        f.service.detach()
        f.network.releaseTranslations()
        try await Task.sleep(for: .milliseconds(200))
        try check(f.service.text == nil && !f.service.isOn, "late translation cannot restart stopped session")
        let second = try Fixture(); defer { second.finish() }
        second.player.window = 0...200
        try await second.start()
        second.network.sockets[0].push(row(31, text: "Old seek.", at: 94))
        try await eventually("seek started") { second.player.pendingSeek != nil }
        let positionBeforeStop = second.player.now
        second.service.detach()
        try check(second.player.cancelledSeeks == 1, "stop must cancel the actual pending player seek")
        second.player.completeSeek()
        try check(second.player.now == positionBeforeStop, "cancelled seek cannot move playback after stop")
        try await Task.sleep(for: .milliseconds(200))
        try check(second.service.text == nil && !second.service.isOn, "seek callback cannot revive stopped session")
    }
}
