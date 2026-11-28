import Foundation

enum PlaybackState { case playing, tuning, idle, paused }
enum SharedNowPlaying { static var title: String? }
/// AVPlayer's mute, the one part of it the window's Pause touches.
final class StubAVPlayer: NSObject { var isMuted = false }
final class PlayerController {
    var state: PlaybackState = .playing
    let player = StubAVPlayer()
    func stop() { state = .idle; SharedNowPlaying.title = nil }
    func pause() { state = .paused }
    var settling: CheckedContinuation<Void, Never>?
    var holdsSettle = false
    func settled() async {
        if holdsSettle { await withCheckedContinuation { settling = $0 } }
    }
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
    enum Phase { case idle, onAir, needsSignIn, tuning }
    var phase = Phase.onAir
    var offAirWatch: Watch? = Watch()
    var slotWatch: Watch? = Watch()
    var refusalWatch: Watch? = Watch()
    var channelNumber = 5
    func channelName(_ number: Int) -> String { "Channel \(number)" }
    var rejoined = 0
    func rejoinLive() async { rejoined += 1 }
    var signed = ["viewer": (url: URL(string: "https://example.invalid/old")!, until: Date.distantFuture)]
    var generation = 0
    private(set) var accessRevision = 0
    // PRODUCTION_STOP
    // PRODUCTION_BEGIN_TUNE
    // PRODUCTION_ACCESS_INVALIDATION
    // PRODUCTION_WARM
}
struct ScheduleCache { static let shared = ScheduleCache(); func clear() {} }
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
    var previewPassword: String?
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
final class ReceiverStore {
    var credentialChanges = 0
    /// The app reads whether the dial changed (a whole-dial radio is then turned off); here it never does.
    @discardableResult func credentialDidChange() -> Bool { credentialChanges += 1; return false }
}
final class PictureInPicture {
    var title = ""
    var captions: (() -> String?)?
    var captionLabel: (() -> String?)?
    var onCaptionToggle: (() -> Void)?
    var skin: (() -> Int)?
    var onSetPlaying: ((Bool) -> Void)?
    var controller: PlayerController?
    var rejoinsOnPlay = false
    var onHandOff: (() -> Void)?
    var hasFileCaptions: (() -> Bool)?
    var drawsIntoPicture = false
    var onStart: (() -> Void)?
    var onFail: ((String) -> Void)?
    var onRestore: (() -> Void)?
    var onEnd: (() -> Void)?
    var stopped = false
    func start(_ player: NSObject) -> Bool { true }
    func stop() { stopped = true }
    func letGo() {}
}
final class RecordedSubtitles {
    var tracks: [Int] = [1]
    var text: String? = "a line"
    var label = "Subtitles · English"
    var isHandedOff = false
    var hasFile = false
    var cycled = 0
    var handedOff = 0
    func cycle() { cycled += 1 }
    func handOff() { handedOff += 1; isHandedOff = true }
}

/// The window's subtitles: read by `captions`, ended when the window restores or closes.
final class ProgrammeSubtitleFollower {
    let subtitles: RecordedSubtitles
    let loaded: String?
    var ended = false
    init(_ subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel, loaded: String?) {
        self.subtitles = subtitles
        self.loaded = loaded
        Probe.lastFollower = self
    }
    func text() -> String? { subtitles.text }
    var cleared = false
    func end(clearing: Bool = true) { ended = true; cleared = clearing }
}
/// A radio kept playing while the viewer is elsewhere; only what the credential handler touches.
final class RadioAway {
    var pip: PictureInPicture?
    let controller = PlayerController()
}
final class AppModel {
    var skin = 0
    var radioAway: RadioAway?
    var restoringTransmission: Int?
    enum Section { case transmission }
    enum Link { case channel(Int) }
    var transmissionPiP: PictureInPicture?
    let transmission = TransmissionStore()
    var auth: AuthStore { transmission.auth }
    let reading = ReadingStore()
    let receiver = ReceiverStore()
    var receiverPath: [Int] = []
    let publicReceiver = PlayerController()
    var section = Section.transmission
    var link: Link?
    // PRODUCTION_ACCESS_OBSERVER
    func installPreviewObserver() {
        // PRODUCTION_PREVIEW_OBSERVER
    }
}
final class Probe {
    static var lastFollower: ProgrammeSubtitleFollower?
    var subtitles = RecordedSubtitles()
    var subtitleKey: String? = "programme-1"
    var windowSubtitleKey: String? = "programme-1"
    var channel = 5
    var close: (() -> Void)? = nil
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
// A refresh the server refuses clears the session mid-tune: the screen asks for sign-in.
let refused = Probe()
refused.model.auth.session = nil
refused.model.auth.revokeAccess()
let asksSignIn = refused.store.phase == .needsSignIn
print("\(asksSignIn ? "PASS" : "FAIL") session cleared while watching asks for sign-in")
if !asksSignIn { failures += 1 }
let notWatching = Probe()
notWatching.store.phase = .idle
notWatching.model.auth.session = nil
notWatching.model.auth.revokeAccess()
let staysIdle = notWatching.store.phase == .idle
print("\(staysIdle ? "PASS" : "FAIL") session cleared while not watching stays idle")
if !staysIdle { failures += 1 }
let idle = Probe()
idle.store.playerA.state = .idle
idle.store.playerB.state = .idle
SharedNowPlaying.title = "Public Receiver"
idle.model.auth.revokeAccess()
let receiverMetadataPreserved = SharedNowPlaying.title == "Public Receiver"
    && idle.store.generation == 1 && idle.store.signed.isEmpty
print("\(receiverMetadataPreserved ? "PASS" : "FAIL") idle Transmission invalidation preserves Receiver Now Playing")
if !receiverMetadataPreserved { failures += 1 }
// The window carries the programme's subtitles, and lets go of them when it restores or closes.
let carried = Probe()
carried.startPictureInPicture()
let follower = Probe.lastFollower!
let windowReads = carried.pip.captions?() == "a line" && carried.pip.title == "Channel 5"
    && follower.loaded == "programme-1"
let windowFollows = carried.pip.controller === carried.store.player && carried.pip.rejoinsOnPlay
print("\(windowFollows ? "PASS" : "FAIL") the window's own Play rejoins the broadcast; its Pause is followed by the channel's player")
if !windowFollows { failures += 1 }
print("\(windowReads ? "PASS" : "FAIL") window reads the programme's subtitles, named for the channel")
if !windowReads { failures += 1 }
carried.pip.onCaptionToggle?()
let noLabelBeforeHandOff = carried.pip.captionLabel?() == nil
carried.pip.onHandOff?()
let barWorksSubtitles = noLabelBeforeHandOff && carried.pip.captionLabel?() == "Subtitles · English" && follower.subtitles.cycled == 1
    && follower.subtitles.handedOff == 1
print("\(barWorksSubtitles ? "PASS" : "FAIL") the window hands the stream's track to tvOS; the bar names and cycles it, and not before")
if !barWorksSubtitles { failures += 1 }
// A file is offered only once it is drawn into the picture; a stream fallen back to a file never.
let file = Probe()
file.subtitles.hasFile = true
file.startPictureInPicture()
let fileHidden = file.pip.captionLabel?() == nil && file.pip.hasFileCaptions?() == true
file.pip.drawsIntoPicture = true
let fileShown = file.pip.captionLabel?() == "Subtitles · English"
print("\(fileHidden && fileShown ? "PASS" : "FAIL") a file's subtitles are offered on the bar only while drawn into the picture")
if !(fileHidden && fileShown) { failures += 1 }
// The window's own Play rejoins the broadcast live.
let rejoin = Probe()
rejoin.startPictureInPicture()
rejoin.pip.onStart?()
rejoin.pip.onSetPlaying?(true)
// A Play queued in a window that closes before it runs does not start the channel again (CodeRabbit, PR 82).
let closedFirst = Probe()
closedFirst.startPictureInPicture()
closedFirst.pip.onStart?()
closedFirst.pip.onSetPlaying?(true)
closedFirst.pip.onEnd?()
// Full screen asks for the channel to open over whatever is on top.
let restoreTop = Probe()
restoreTop.startPictureInPicture()
restoreTop.pip.onStart?()
restoreTop.pip.onRestore?()
let opensOnTop = restoreTop.model.restoringTransmission == 5
print("\(opensOnTop ? "PASS" : "FAIL") full screen opens the channel over whatever is on top")
if !opensOnTop { failures += 1 }
carried.pip.onStart?()
carried.pip.onRestore?()
let restoreKeeps = follower.ended && !follower.cleared
print("\(restoreKeeps ? "PASS" : "FAIL") full screen stops the window's follower and leaves its subtitle up until it closes")
if !restoreKeeps { failures += 1 }
let unloaded = Probe()
unloaded.subtitles.tracks = []
unloaded.startPictureInPicture()
let reloads = Probe.lastFollower!.loaded == nil
print("\(reloads ? "PASS" : "FAIL") subtitles still loading are loaded again by the window")
if !reloads { failures += 1 }
let closed = Probe()
closed.startPictureInPicture()
closed.pip.onStart?()
closed.pip.onEnd?()
let closedEnds = Probe.lastFollower!.ended && Probe.lastFollower!.cleared && closed.model.transmissionPiP == nil
print("\(closedEnds ? "PASS" : "FAIL") closing the window ends its subtitles and the channel")
if !closedEnds { failures += 1 }
func waitForBoundary(_ ready: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !ready() {
        if ContinuousClock.now >= deadline { return false }
        await Task.yield()
    }
    return true
}
Task {
    // Pause pressed while the channel retunes, then Play before the picture comes: Play wins.
    let retune = Probe()
    retune.startPictureInPicture()
    retune.store.player.state = .tuning
    retune.store.player.holdsSettle = true
    retune.pip.onSetPlaying?(false)
    _ = await waitForBoundary { retune.store.player.settling != nil }
    retune.pip.onSetPlaying?(true)
    retune.store.player.state = .playing
    retune.store.player.settling?.resume()
    for _ in 0..<20 { await Task.yield() }
    let playWins = retune.store.player.state == .playing
    print("\(playWins ? "PASS" : "FAIL") Pause then Play while the channel retunes ends playing")
    if !playWins { failures += 1 }
    // A Pause pressed in the first half of a rejoin, while the player is idle (signing, loading):
    // it waits for the new picture, then pauses it (Fable round 9).
    let early = Probe()
    early.startPictureInPicture()
    early.pip.onStart?()
    early.store.player.state = .idle
    early.store.phase = .tuning
    early.pip.onSetPlaying?(false)
    for _ in 0..<5 { await Task.yield() }
    let waitedForPicture = early.store.player.state == .idle
    early.store.phase = .onAir
    early.store.player.player.isMuted = false   // the rejoin's attach unmutes
    early.store.player.state = .playing
    _ = await waitForBoundary { early.store.player.state == .paused }
    let earlyPaused = waitedForPicture && early.store.player.state == .paused && early.store.player.player.isMuted
    print("\(earlyPaused ? "PASS" : "FAIL") a Pause pressed while the rejoin is still loading pauses the new picture, muted")
    if !earlyPaused { failures += 1 }
    // A Pause pressed while the rejoin loads, then the window goes (a card opens the channel full
    // screen): the screen that opens is not paused by it (Fable round 10).
    let gone = Probe()
    gone.startPictureInPicture()
    gone.pip.onStart?()
    gone.store.player.state = .idle
    gone.store.phase = .tuning
    gone.pip.onSetPlaying?(false)
    gone.model.transmissionPiP = nil
    gone.store.phase = .onAir
    gone.store.player.state = .playing
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(300))
    let screenPlays = gone.store.player.state == .playing
    print("\(screenPlays ? "PASS" : "FAIL") a Pause from a window that has gone does not pause the screen that replaced it")
    if !screenPlays { failures += 1 }
    // A Pause alone while it retunes pauses it once the picture has come.
    let alone = Probe()
    alone.startPictureInPicture()
    alone.pip.onStart?()
    alone.store.player.state = .tuning
    alone.store.player.holdsSettle = true
    alone.pip.onSetPlaying?(false)
    _ = await waitForBoundary { alone.store.player.settling != nil }
    alone.store.player.state = .playing
    alone.store.player.settling?.resume()
    _ = await waitForBoundary { alone.store.player.state == .paused }
    let pauseKept = alone.store.player.state == .paused
    print("\(pauseKept ? "PASS" : "FAIL") a Pause pressed while the channel retunes pauses it once it plays")
    if !pauseKept { failures += 1 }
    _ = await waitForBoundary { rejoin.store.rejoined == 1 }
    let rejoined = rejoin.store.rejoined == 1
    print("\(rejoined ? "PASS" : "FAIL") Play (the bar's, the remote's or the window's own) rejoins the channel live")
    if !rejoined { failures += 1 }
    try? await Task.sleep(for: .milliseconds(200))
    let staysClosed = closedFirst.store.rejoined == 0
    print("\(staysClosed ? "PASS" : "FAIL") a Play queued in a window that has closed does not rejoin")
    if !staysClosed { failures += 1 }
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
