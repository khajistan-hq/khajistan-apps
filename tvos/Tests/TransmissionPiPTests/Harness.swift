import Foundation

enum PlaybackState { case playing, tuning, idle }
enum SharedNowPlaying { static var title: String? }
final class PlayerController {
    var state: PlaybackState = .playing
    let player = NSObject()
    func stop() { state = .idle; SharedNowPlaying.title = nil }
}
final class Watch {
    var cancelled = false
    func cancel() { cancelled = true }
}
final class TransmissionStore {
    let auth = AuthStore()
    enum Schedule { case ready }
    let schedule = Schedule.ready
    let programming: Int? = 1
    static func now() -> Date { Date() }
    static let signedLife: TimeInterval = 3600
    struct Reply { let data: Data; let status: Int }
    var replyContinuation: CheckedContinuation<Reply, Never>?
    var sendStarted = false
    func send(_ request: URLRequest, refusingRedirects: Bool) async throws -> Reply {
        sendStarted = true
        return await withCheckedContinuation { replyContinuation = $0 }
    }
    var playerA = PlayerController()
    var playerB = PlayerController()
    var player: PlayerController {
        get { playerA }
        set { playerA = newValue }
    }
    enum Phase { case idle, onAir }
    var phase = Phase.onAir
    var offAirWatch: Watch? = Watch()
    var slotWatch: Watch? = Watch()
    var refusalWatch: Watch? = Watch()
    var channelNumber = 5
    var signed = ["viewer": (url: URL(string: "https://example.invalid/old")!, until: Date.distantFuture)]
    var generation = 0
    private(set) var accessRevision = 0
    // PRODUCTION_STOP
    // PRODUCTION_BEGIN_TUNE
    // PRODUCTION_ACCESS_INVALIDATION
    // PRODUCTION_WARM
}
enum StationClock {
    struct Programme { let play_url = "signed" }
    struct Air { let programme: Programme? = Programme() }
    static func onAir(_ p: Int, channel: Int, at: Date) -> Air? { Air() }
}
enum Transmission {
    enum Route { case direct(URL), signed }
    static func route(for value: String) -> Route? { .signed }
    static func request(for route: Route, accessToken: String) -> URLRequest? {
        URLRequest(url: URL(string: "https://example.invalid/sign")!)
    }
    static func carrier(from data: Data, route: Route) throws -> URL { URL(string: "https://example.invalid/new")! }
}
final class AuthStore {
    struct Session { let userId = "same-viewer" }
    var session: Session? = Session()
    var waitForToken = false
    var tokenContinuation: CheckedContinuation<String, Never>?
    func validAccessToken() async throws -> String {
        if waitForToken { return await withCheckedContinuation { tokenContinuation = $0 } }
        return "test-token"
    }
    var accessGeneration = 0
    private var observers: [() -> Void] = []
    var onPreviewPasswordChange: (() -> Void)?
    func observeAccess(_ observer: @escaping () -> Void) -> UUID {
        observers.append(observer)
        return UUID()
    }
    func revokeAccess() {
        accessGeneration += 1
        for observer in observers { observer() }
    }
}
final class ReadingStore {
    var invalidations = 0
    func previewCredentialDidChange() { invalidations += 1 }
}
final class PictureInPicture {
    var onStart: (() -> Void)?
    var onFail: ((String) -> Void)?
    var onRestore: (() -> Void)?
    var onEnd: (() -> Void)?
    var stopped = false
    func start(_ player: NSObject) -> Bool { true }
    func stop() { stopped = true }
    func letGo() {}
}
final class AppModel {
    enum Section { case transmission }
    enum Link { case channel(Int) }
    var transmissionPiP: PictureInPicture?
    let transmission = TransmissionStore()
    var auth: AuthStore { transmission.auth }
    let reading = ReadingStore()
    let publicReceiver = PlayerController()
    var section = Section.transmission
    var link: Link?
    // PRODUCTION_ACCESS_OBSERVER
    func installPreviewObserver() {
        // PRODUCTION_PREVIEW_OBSERVER
    }
}
final class Probe {
    var model = AppModel()
    var store: TransmissionStore { model.transmission }
    var pip = PictureInPicture()
    var pipOffered = true
    var armed: Int?
    var handedToPiP = false
    var left = false
    var switching = false
    var dismissed = false
    init() {
        model.observeTransmissionAccess()
        model.installPreviewObserver()
    }
    func dismiss() { dismissed = true }
    func say(_ line: String) {}
    func wake() {}
    // PRODUCTION_METHOD
}

var failures = 0
func check(_ name: String, mutate: (Probe) -> Void, accepted: Bool) {
    let p = Probe()
    p.startPictureInPicture()
    mutate(p)
    p.pip.onStart?()
    let didAccept = p.handedToPiP && p.dismissed && p.model.transmissionPiP === p.pip
    let rejectedCleanly = !p.handedToPiP && !p.dismissed && p.model.transmissionPiP == nil && p.pip.stopped
    let passed = accepted ? didAccept && !p.pip.stopped : rejectedCleanly
    print("\(passed ? "PASS" : "FAIL") \(name)")
    if !passed { failures += 1 }
}
check("current playing session", mutate: { _ in }, accepted: true)
check("same-player programme handover", mutate: { $0.store.player.state = .tuning }, accepted: true)
check("stopped player", mutate: { $0.store.player.state = .idle }, accepted: false)
check("left before callback", mutate: { $0.left = true }, accepted: false)
check("switch in flight", mutate: { $0.switching = true }, accepted: false)
check("retune committed a new player", mutate: { $0.store.player = PlayerController() }, accepted: false)
check("leave and reopen new session", mutate: {
    $0.left = true
    $0.store.player = PlayerController()
}, accepted: false)
check("access changed before callback", mutate: { $0.model.auth.revokeAccess() }, accepted: false)
let revoked = Probe()
revoked.startPictureInPicture()
revoked.pip.onStart?()
let generation = revoked.store.generation
let watches = [revoked.store.offAirWatch!, revoked.store.slotWatch!, revoked.store.refusalWatch!]
revoked.model.auth.revokeAccess()
let revokedCleanly = revoked.model.transmissionPiP == nil && revoked.pip.stopped
    && revoked.store.player.state == .idle && revoked.store.signed.isEmpty
    && revoked.store.generation > generation
    && revoked.store.playerB.state == .idle && revoked.store.phase == .idle
    && watches.allSatisfy { $0.cancelled }
    && revoked.store.offAirWatch == nil && revoked.store.slotWatch == nil && revoked.store.refusalWatch == nil
print("\(revokedCleanly ? "PASS" : "FAIL") access revokes PiP, both players, cached carrier, tune generation and retry tasks")
if !revokedCleanly { failures += 1 }
// A late callback after revocation cannot reattach even if a new tune plays on the same controller.
revoked.store.player.state = .playing
revoked.handedToPiP = false
revoked.dismissed = false
revoked.pip.onStart?()
let stayedRevoked = revoked.model.transmissionPiP == nil && !revoked.handedToPiP && !revoked.dismissed
print("\(stayedRevoked ? "PASS" : "FAIL") late callback cannot restore revoked session")
if !stayedRevoked { failures += 1 }
let preview = Probe()
preview.startPictureInPicture()
preview.model.auth.onPreviewPasswordChange?()
preview.store.player.state = .playing
preview.pip.onStart?()
let previewRejected = !preview.handedToPiP && !preview.dismissed && preview.model.transmissionPiP == nil
    && preview.pip.stopped && preview.store.accessRevision == 1
    && preview.model.reading.invalidations == 1 && preview.model.publicReceiver.state == .playing
print("\(previewRejected ? "PASS" : "FAIL") preview invalidation rejects late start and preserves public Receiver")
if !previewRejected { failures += 1 }
preview.model.auth.onPreviewPasswordChange?()
let repeatedClear = preview.store.accessRevision == 2 && preview.model.reading.invalidations == 2
print("\(repeatedClear ? "PASS" : "FAIL") repeated preview Clear invalidates again")
if !repeatedClear { failures += 1 }
let idle = Probe()
idle.store.playerA.state = .idle
idle.store.playerB.state = .idle
SharedNowPlaying.title = "Public Receiver"
idle.model.auth.revokeAccess()
let receiverMetadataPreserved = SharedNowPlaying.title == "Public Receiver"
    && idle.store.generation == 1 && idle.store.signed.isEmpty
print("\(receiverMetadataPreserved ? "PASS" : "FAIL") idle Transmission invalidation preserves Receiver Now Playing")
if !receiverMetadataPreserved { failures += 1 }
func waitForBoundary(_ ready: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !ready() {
        if ContinuousClock.now >= deadline { return false }
        await Task.yield()
    }
    return true
}
Task {
    for stage in ["token", "reply", "valid"] {
        let store = TransmissionStore()
        store.signed.removeAll()
        store.auth.waitForToken = stage == "token"
        var finished = false
        let task = Task { await store.warm(channel: 8); finished = true }
        if stage == "token" {
            guard await waitForBoundary({ store.auth.tokenContinuation != nil }) else {
                print("FAIL token boundary was not reached"); failures += 1; task.cancel(); continue
            }
            store.accessDidChange()
            store.auth.tokenContinuation?.resume(returning: "test-token")
            guard await waitForBoundary({ finished || store.replyContinuation != nil }) else {
                print("FAIL token completion did not settle"); failures += 1; task.cancel(); continue
            }
            // The old method incorrectly proceeds to the signer; release that response so the
            // regression fails its assertion instead of hanging on the deliberately bad path.
            store.replyContinuation?.resume(returning: .init(data: Data(), status: 200))
        } else {
            guard await waitForBoundary({ store.replyContinuation != nil }) else {
                print("FAIL reply boundary was not reached"); failures += 1; task.cancel(); continue
            }
            if stage == "reply" { store.accessDidChange() }
            store.replyContinuation?.resume(returning: .init(data: Data(), status: 200))
        }
        await task.value
        let passed = stage == "valid" ? store.signed.count == 1
            : store.signed.isEmpty && (stage != "token" || !store.sendStarted)
        print("\(passed ? "PASS" : "FAIL") warm carrier \(stage) access boundary")
        if !passed { failures += 1 }
    }
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
