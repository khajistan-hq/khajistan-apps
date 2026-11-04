// Compiles the actual service and shared caption core against in-memory platform boundaries.
// No DNS, HTTP, websocket, account, or paid caption worker is contacted.
import Foundation

enum SupabaseRoute { static let base = URL(string: "https://caption-test.invalid")! }

@MainActor final class AuthStore {
    var isSignedIn = true
    // The account-isolation surface LiveCaptionSession reads since main's d20ced6.
    var accessGeneration = 0
    var observers: [UUID: @MainActor () -> Void] = [:]
    func observeAccess(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID(); observers[id] = observer; return id
    }
    func removeAccessObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func changeAccount() { accessGeneration += 1; Array(observers.values).forEach { $0() } }
    func validAccessToken() async throws -> String { "synthetic-test-token" }
}

@MainActor final class PlayerController {
    enum State: Equatable { case idle, tuning, playing, paused, failed(String) }
    var onPlaybackUnavailable: (() -> Void)?
    var onPlaybackResumed: (() -> Void)?
    var state = State.playing {
        didSet {
            switch state {
            case .idle, .paused, .failed: onPlaybackUnavailable?()
            case .playing: onPlaybackResumed?()
            case .tuning: break
            }
        }
    }
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
    var programmeBase = 900.0
    var seeks: [Double] = []
    var pendingSeek: (@MainActor () -> Void)?
    var lateSeekCompletion: (@MainActor () -> Void)?
    var cancelledSeeks = 0
    var captionClock: CaptionClock? {
        CaptionClock(now: now, behindLive: behind, programDate: program ? Date(timeIntervalSince1970: programmeBase + now) : nil, window: window)
    }
    func seekBack(by seconds: Double, completion: @escaping @MainActor () -> Void = {}) {
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
    var demandActions: [String] = []
    var demandChannels: [String] = []
    var stallRecovery = false
    var recoveryWaiters: [CheckedContinuation<Void, Never>] = []
    var translationWaiters: [CheckedContinuation<Void, Never>] = []
    var translations = 0
    var translationReturnsNil = false
    var recoveryRequests = 0
    var recoveryRows: [[String: Any]] = []
    var refuseStart = false
    func releaseRecovery() { let held = recoveryWaiters; recoveryWaiters = []; held.forEach { $0.resume() } }
    func releaseTranslations() { let held = translationWaiters; translationWaiters = []; held.forEach { $0.resume() } }
    func data(_ request: URLRequest) async -> (Data, URLResponse) {
        let url = request.url!
        requests.append(url.path)
        var body: Any = []
        if url.path.contains("request-captions") {
            let sent = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            if let action = sent["action"] as? String { demandActions.append(action); demandChannels.append(sent["channel_id"] as? String ?? "") }
            body = ["allowed": !refuseStart, "reason": refuseStart ? "credits_exhausted" : NSNull(),
                    "billing_mode": "enforced", "unlimited": true,
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
    static var shared: URLSession { URLSession(configuration: .ephemeral) }
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
func row(_ id: Int, text: String, at: Double = 100, english: Bool = true, channel: String = "caption-test", event: String = "INSERT", native: String = "خبر", uncertain: Bool = false, programmeStamp: Bool = true, atEpoch: Double? = nil, createdAge: Double? = nil) -> String {
    var record: [String: Any] = ["id": id, "channel_id": channel, "text": native, "english": english ? text : "", "uncertain": uncertain,
                               "lang": "ur", "final": true, "program_epoch": 900 + at,
                               "at_epoch": atEpoch ?? Date().timeIntervalSince1970, "spoken_seconds": 2]
    if !programmeStamp { record.removeValue(forKey: "program_epoch") }
    if let createdAge { record["created_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-createdAge)) }
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

@main struct CaptionPreferenceHarness {
    @MainActor static func main() async {
        var failures = 0
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("Surf waits for slower main-atlas regions", surfLoadsAllRegions),
            ("Surf visits every stable ID once before cycle rollover", surfFullCycle),
            ("Surf adds new channels and retires unavailable channels without forgetting visits", surfCatalogueChanges),
            ("partial atlas cannot become a short repeat loop", surfPartialAtlas),
            ("Surf keeps explicit media, atlas and access filters", surfFilters),
            ("Surf preserves captions across the entire cycle and hides controls independently", surfCaptionInteraction),
            ("new installation stays off", startsOff),
            ("on survives retunes, playback reconnect and relaunch", persistsOn),
            ("explicit off survives retunes and relaunch", persistsOff),
            ("unavailable channel and signed-out state retain preference without demand", unavailable),
            ("explicit off remains possible when an enabled channel is unavailable", offWhileUnavailable),
            ("an account change forgets On, so the next account is never billed unasked", accountChangeForgetsOn),
            ("a refused start turns CC Off instead of asking on every recovery", refusalTurnsOff),
            ("a channel still tuning waits for its picture, with no wait note", tuningRetuneWaitsForPicture),
            ("controls hide after five seconds and remote interaction resets deadline", controlsDeadline),
            ("guide, focus and accessibility holds survive stale timers", controlsHold)
        ]
        for (name, test) in tests {
            do { try await test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("Caption preference: \(tests.count - failures)/\(tests.count) passed; no external network")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor static func withFixture(_ body: (UserDefaults, AuthStore, PlayerController, Network, String) async throws -> Void) async throws {
        let suite = "khajistan.caption-preference.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let network = Network(); Network.current = network
        try await body(defaults, AuthStore(), PlayerController(), network, suite)
    }

    @MainActor static func startsOff() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel(), player: player)
            try await Task.sleep(for: .milliseconds(100))
            try check(!service.isOn, "a new installation must not start caption demand")
            try check(!network.demandActions.contains("start"), "off may check balance but must not start a worker")
            service.detach()
        }
    }

    @MainActor static func persistsOn() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            var service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel("first"), player: player)
            service.toggle()
            try await eventually("first channel starts") { network.demandActions.filter { $0 == "start" }.count == 1 }
            for name in ["second", "third", "first", "first"] {
                service.attach(try channel(name), player: player)
                try check(service.isOn, "CC must remain on after tuning \(name)")
            }
            try await eventually("final rapid retune starts") { network.demandActions.filter { $0 == "start" }.count >= 2 }
            service.detach() // pause/exit still releases demand
            try check(!service.isOn && service.text == nil, "teardown stops actual caption delivery")
            try await eventually("teardown releases demand") { network.demandActions.contains("stop") }
            service = LiveCaptionSession(auth: auth, defaults: UserDefaults(suiteName: suite)!)
            // New service models a new app process: no in-memory carry state survives.
            service.attach(try channel("relaunch"), player: player)
            try check(service.isOn, "saved on preference restores after service recreation")
            service.detach()
        }
    }

    @MainActor static func accountChangeForgetsOn() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel("first"), player: player)
            service.toggle()
            try await eventually("A's captions start") { network.demandActions.filter { $0 == "start" }.count == 1 }
            auth.changeAccount()   // A signs out, B signs in on the same Apple TV
            try check(!service.isOn && !service.isEnabled, "the new account starts with CC Off")
            try check(defaults.string(forKey: CaptionRules.modeKey) == "off", "and Off is what is saved")
            service.attach(try channel("second"), player: player)
            try await Task.sleep(for: .milliseconds(150))
            try check(network.demandActions.filter { $0 == "start" }.count == 1, "B's channel change starts no paid demand")
            service.detach()
        }
    }

    @MainActor static func refusalTurnsOff() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            network.refuseStart = true
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel(), player: player)
            service.toggle()
            try await eventually("the refusal lands") { !service.isEnabled }
            try check(!service.isOn && defaults.string(forKey: CaptionRules.modeKey) == "off", "refused: Off, saved")
            for _ in 0..<3 { player.state = .tuning; player.state = .playing }
            try await Task.sleep(for: .milliseconds(150))
            try check(network.demandActions.filter { $0 == "start" }.count == 1, "buffer recoveries do not ask again")
            service.detach()
        }
    }

    @MainActor static func tuningRetuneWaitsForPicture() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel("first"), player: player)
            service.toggle()
            try await eventually("first channel starts") { network.demandActions.filter { $0 == "start" }.count == 1 }
            let next = PlayerController()
            next.state = .tuning
            service.attach(try channel("second"), player: next)
            try check(!service.note.contains("Wait for the signal"), "no instruction under a press nobody made: \(service.note)")
            try check(service.isEnabled, "the choice is kept while the channel tunes")
            next.state = .playing
            try await eventually("captions come back when the picture plays") { service.isOn }
            service.detach()
        }
    }

    @MainActor static func persistsOff() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            defaults.set("english", forKey: CaptionRules.modeKey)
            var service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel(), player: player)
            try check(service.isOn, "saved on restores")
            service.toggle()
            try check(!service.isOn, "explicit off stops the session")
            service.attach(try channel("next"), player: player)
            try check(!service.isOn, "next channel respects off")
            service.detach()
            service = LiveCaptionSession(auth: auth, defaults: defaults)
            service.attach(try channel("relaunch"), player: player)
            try check(!service.isOn, "relaunch respects off")
            service.detach()
        }
    }

    @MainActor static func unavailable() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            defaults.set("english", forKey: CaptionRules.modeKey)
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            var blocked = try channel("blocked"); blocked.captionsDenied = true
            service.attach(blocked, player: player)
            try check(!service.isOn, "saved preference cannot bypass channel eligibility")
            try check(defaults.string(forKey: CaptionRules.modeKey) == "english", "unsupported channel does not erase choice")
            auth.isSignedIn = false
            service.attach(try channel("signed-out"), player: player)
            try await Task.sleep(for: .milliseconds(100))
            try check(!service.isOn && !network.demandActions.contains("start"), "signed-out viewer must not create paid demand")
            auth.isSignedIn = true
            service.attach(try channel("eligible"), player: player)
            try check(service.isOn, "eligible signed-in playback restores saved choice")
            service.detach()
        }
    }

    @MainActor static func controlsDeadline() throws {
        var controls = ReceiverControlsVisibility()
        controls.wake(at: 0, canHide: true)
        try check(!controls.expire(at: 4.9, canHide: true) && controls.isVisible, "bar remains readable for five seconds")
        controls.wake(at: 4, canHide: true) // remote event, including an armed CC chip
        try check(!controls.expire(at: 5, canHide: true), "old timer cannot hide after a new interaction")
        try check(controls.expire(at: 9, canHide: true) && !controls.isVisible, "idle bar disappears at fresh deadline")
        controls.wake(at: 10, canHide: true)
        try check(controls.isVisible, "remote event restores hidden controls")
    }

    @MainActor static func offWhileUnavailable() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            defaults.set("english", forKey: CaptionRules.modeKey)
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            var blocked = try channel("blocked"); blocked.captionsDenied = true
            service.attach(blocked, player: player)
            try check(service.isEnabled && !service.isOn, "saved setting stays On while channel is unavailable")
            service.toggle()
            try check(!service.isEnabled && defaults.string(forKey: CaptionRules.modeKey) == "off", "CC can save Off without eligibility or auth")
            service.attach(try channel("eligible"), player: player)
            try check(!service.isOn, "eligible channel cannot undo explicit Off")
            service.toggle()
            player.state = .failed("test reconnect")
            try check(!service.isOn && service.isEnabled, "lost playback suspends demand")
            player.state = .playing
            try check(service.isOn, "reconnect restores saved On")
            service.detach()
            player.state = .paused
            player.state = .playing
            try check(!service.isOn, "detached player cannot restart demand")
        }
    }

    @MainActor static func controlsHold() throws {
        for reason in ["guide", "system focus", "VoiceOver", "Switch Control", "paused", "failed"] {
            var controls = ReceiverControlsVisibility()
            controls.wake(at: 0, canHide: true)
            try check(!controls.expire(at: 5, canHide: false) && controls.isVisible, "\(reason) cannot disappear under interaction")
            controls.wake(at: 6, canHide: false)
            try check(!controls.expire(at: 20, canHide: true), "\(reason) invalidates an older timer")
            controls.wake(at: 21, canHide: true)
            try check(!controls.expire(at: 25.9, canHide: true), "releasing \(reason) grants a fresh interval")
            try check(controls.expire(at: 26, canHide: true), "controls resume hiding after \(reason) closes")
        }
    }
}

extension CaptionPreferenceHarness {
    @MainActor static func surfIndex() throws -> ReceiverIndex {
        let text = #"{"regions":[{"id":"indus","label":"Indus","kind":"state","tier":"heartbeat"},{"id":"parsistan","label":"Parsistan","kind":"state","tier":"core"},{"id":"anatolia","label":"Anatolia","kind":"state","tier":"core"},{"id":"beyond","label":"Beyond","kind":"state","tier":"extension"}],"regionFiles":{"indus":"/i.json","parsistan":"/p.json","anatolia":"/a.json","beyond":"/b.json"},"regionCounts":{},"totals":{"channels":0,"live":0,"byMedium":{}}}"#
        return try JSONDecoder().decode(ReceiverIndex.self, from: Data(text.utf8))
    }

    @MainActor static func surfChannel(_ id: String, region: String, medium: String = "tv", extra: [String: Any] = [:]) throws -> Channel {
        var object: [String: Any] = ["id": id, "name": id, "mediaType": medium, "primaryLanguage": "Urdu",
                                    "languageCode": "ur", "country": "Pakistan", "regionIds": [region],
                                    "streams": [["id": "stream-" + id]], "activeStreamId": "stream-" + id]
        object.merge(extra) { _, new in new }
        return try JSONDecoder().decode(Channel.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @MainActor static func surfLoadsAllRegions() async throws {
        let index = try surfIndex()
        var requested = Set<String>()
        let result = await ShufflePick.catalogue(index, medium: .all, scope: .main) { region in
            requested.insert(region)
            if region == "parsistan" { try? await Task.sleep(for: .seconds(4.1)) }
            return [try! surfChannel(region, region: region)]
        }
        try check(requested == ["indus", "parsistan", "anatolia"], "default loads every main region, no extension")
        try check(Set(result.channels.map(\.id)) == requested && result.isComplete, "a region slower than the old four-second cutoff still joins Surf")
    }

    @MainActor static func surfFullCycle() throws {
        let channels = try (0..<12).map { try surfChannel("channel-\($0)", region: ["indus", "parsistan", "anatolia"][$0 % 3]) }
        var cycle = SurfCycle()
        var previous: String?
        for _ in 0..<3 {
            var ids: [String] = []
            for i in 0..<channels.count {
                let picked = cycle.next(in: channels + channels.reversed(), allowNewCycle: true)!
                if i == 0, let previous { try check(picked.id != previous, "rollover cannot immediately repeat the last channel") }
                ids.append(picked.id)
                previous = picked.id
            }
            try check(Set(ids) == Set(channels.map(\.id)), "every stable ID across all regions appears exactly once per cycle")
        }
        var history = SurfHistory()
        let choice = SurfChoice(medium: .all, scope: .main)
        var visited = Set<String>()
        for _ in channels {
            history.update(SurfCatalogue(channels: channels.shuffled(), missingRegions: []), for: choice)
            try check(visited.insert(history.next(for: choice)!.id).inserted, "reopening Surf cannot forget earlier visits")
        }
    }

    @MainActor static func surfCatalogueChanges() throws {
        let a = try surfChannel("a", region: "indus"), b = try surfChannel("b", region: "parsistan")
        let c = try surfChannel("c", region: "anatolia"), new = try surfChannel("new", region: "anatolia")
        var cycle = SurfCycle()
        cycle.visit(a.id) // explicit guide selection also counts as a visit
        let picked = cycle.next(in: [a, b, c], allowNewCycle: false)!
        let removed = picked.id == b.id ? c : b
        let changed = [a, picked, new] // the unvisited old channel is now unavailable
        try check(cycle.next(in: changed, allowNewCycle: false)?.id == "new", "a newly added channel joins before any repeat")
        try check(cycle.next(in: changed, allowNewCycle: false) == nil, "removed channels do not force a regional retry loop")
        try check(cycle.next(in: changed + [removed], allowNewCycle: false)?.id == removed.id, "an unvisited channel returning to the catalogue joins this cycle")
        try check(cycle.next(in: [], allowNewCycle: true) == nil, "empty availability cannot reset the cycle")
        try check(cycle.next(in: changed + [removed], allowNewCycle: false) == nil, "temporary disappearance does not erase earlier visits")
        var one = SurfCycle()
        try check(one.next(in: [a], allowNewCycle: true)?.id == a.id, "one channel is playable")
        try check(one.next(in: [a], allowNewCycle: true)?.id == a.id, "a one-channel complete atlas can only start its next cycle with that channel")
    }

    @MainActor static func surfPartialAtlas() async throws {
        let index = try surfIndex()
        var history = SurfHistory()
        let choice = SurfChoice(medium: .all, scope: .main)
        let partial = await ShufflePick.catalogue(index, medium: .all, scope: .main) { region in
            region == "indus" ? [try! surfChannel("indus", region: region)] : nil
        }
        try check(Set(partial.missingRegions) == ["parsistan", "anatolia"], "failed region loads remain visible in the result")
        history.update(partial, for: choice)
        try check(history.next(for: choice)?.id == "indus", "available shard can play")
        for _ in 0..<5 { try check(history.next(for: choice) == nil, "partial atlas must not loop the first region") }
        let complete = await ShufflePick.catalogue(index, medium: .all, scope: .main) { [try! surfChannel($0, region: $0)] }
        history.update(complete, for: choice)
        let remaining = [history.next(for: choice)!.id, history.next(for: choice)!.id]
        try check(Set(remaining) == ["parsistan", "anatolia"], "recovered regions are visited before the old region repeats")
    }

    @MainActor static func surfFilters() throws {
        let index = try surfIndex()
        let tv = try surfChannel("tv", region: "indus"), radio = try surfChannel("radio", region: "parsistan", medium: "radio")
        let camera = try surfChannel("camera", region: "indus", medium: "camera")
        let other = try surfChannel("outside", region: "beyond")
        let empty = try surfChannel("empty-regions", region: "indus", extra: ["regionIds": []])
        let blocked = try surfChannel("blocked", region: "indus", extra: ["publicationStatus": "hidden"])
        let offline = try surfChannel("offline", region: "indus", extra: ["healthStatus": "offline"])
        let disabled = try surfChannel("disabled", region: "indus", extra: ["manualDisabled": true])
        let noStream = try surfChannel("no-stream", region: "indus", extra: ["activeStreamId": NSNull()])
        let denied = try surfChannel("denied", region: "indus")
        let controls = Controls(denylist: Denylist(disabledChannelIds: ["denied"]), offAir: nil, health: nil)
        let eligible = ReceiverRules.eligible([tv, camera, empty, blocked, offline, disabled, noStream, denied], controls: controls)
        let lists = [(region: "indus", channels: eligible), (region: "parsistan", channels: [radio, tv]), (region: "beyond", channels: [other])]
        func ids(_ medium: ShuffleMedium, _ scope: ShuffleScope) -> Set<String> {
            Set(ShufflePick.pool(lists, index: index, medium: medium, scope: scope).map(\.id))
        }
        try check(ids(.all, .main) == ["tv", "radio", "empty-regions"], "default is all live media in main atlas, deduplicated and gated")
        try check(ids(.tv, .main) == ["tv", "empty-regions"], "explicit TV filter remains")
        try check(ids(.radio, .main) == ["radio"], "explicit radio filter remains")
        try check(ids(.all, .everywhere) == ["tv", "radio", "empty-regions", "outside"], "explicit Beyond the atlas remains")
    }

    @MainActor static func surfCaptionInteraction() async throws {
        try await withFixture { defaults, auth, player, network, suite in
            let channels = try (0..<6).map { try surfChannel("surf-\($0)", region: ["indus", "parsistan", "anatolia"][$0 % 3]) }
            var cycle = SurfCycle()
            let service = LiveCaptionSession(auth: auth, defaults: defaults)
            var controls = ReceiverControlsVisibility()
            for i in 0..<channels.count {
                let picked = cycle.next(in: channels, allowNewCycle: true)!
                let socketCount = network.sockets.count
                service.attach(picked, player: player)
                if i == 0 { service.toggle() }
                try check(service.isOn && service.isEnabled, "Surf retune retains the chosen CC setting")
                try await eventually("retune connects current channel") { network.sockets.count > socketCount }
                network.sockets.last!.push(subscribed(picked.id))
                let caption = "Current channel \(i)."
                network.sockets.last!.push(row(900 + i, text: caption, channel: picked.id))
                try await eventually("current channel caption paints") { service.text == caption }
                controls.wake(at: Double(i * 10), canHide: true)
                try check(controls.expire(at: Double(i * 10 + 5), canHide: true), "every Surf retune grants five readable seconds")
                try check(service.text == caption && service.isOn, "hiding controls cannot clear subtitles or demand")
            }
            service.detach()
        }
    }
}
