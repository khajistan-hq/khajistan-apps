import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The house pigeon, crossing the screen when a channel changes.
///
/// Seven flights, generated for the apps, lifted off their backdrop and laid on each skin's
/// ground (tvos/scripts/flights/, FLIGHTS.json). Owner, 2026-10-05: "our mascot needs to be
/// consistent in look"; "5-7 transitions ... lean more in to the flamboyance"; "real pigeon
/// movements like twirling in air and pigeon showmanship".
///
/// - A **change** flight carries every channel change, in rotation, so no two changes in a row
///   look the same: the two "into us" flights (Across, the website's wing wipe remade, and
///   Approach) alternate with the four flamboyant ones (Twirl, Display, Spiral, Roller). Owner,
///   2026-10-05: "why are you not using the twirl ones you made?" — they had been held for slow
///   signals only, so a fast channel never showed them. Swoop and Rise were removed by the owner.
///   A press during a flight ends it, so a long one never holds up someone changing channels.
/// - A **wait** flight crosses the held ground when the next signal is still tuning after the
///   change flight has gone, the flamboyant four in turn, never the one that just flew, until
///   the picture is ready; the picture then cuts in.
///
/// Each flight is ordinary opaque video, one file per skin, so every device decodes it in
/// hardware: HEVC with alpha dropped frames by the third on the Apple TV HD (2026-10-05). The
/// skin's ground also sits under the players, so the hand-off at either end is the same
/// colour. Two players, one per role, each prerolled before it is needed, both layers always
/// in the view tree.
@MainActor @Observable
final class StationClips {
    enum Flight: String, CaseIterable {
        // Approach was removed (owner, 2026-10-06: the feet, head-on toward us, "too ugly").
        case across, wing, twirl, roller, spiral, display
        /// Every flight can carry a change; which one is fitted to the channel's tune time.
        static let change: [Flight] = [.across, .wing, .twirl, .display, .spiral, .roller]
        static let wait: [Flight] = [.roller, .spiral, .twirl, .display]
        /// Ends with the pigeon's wing filling the screen: the channel cuts in behind it.
        var endsCovered: Bool { self == .wing }
    }

    /// Which size of each flight this device plays: H.264 at 1080, or HEVC at 2160 on a 4K
    /// box driving a 4K screen, where the flight has a 4K source. The Apple TV HD (AppleTV5)
    /// has no hardware HEVC decoder and always plays 1080.
    enum Tier: String {
        case p1080 = "1080", p2160 = "2160"

        @MainActor static let device: Tier = {
            var info = utsname()
            uname(&info)
            let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if machine.hasPrefix("AppleTV5") { return .p1080 }
            return UIScreen.main.nativeBounds.width >= 3800 ? .p2160 : .p1080
        }()

        var fallbacks: [Tier] { self == .p2160 ? [.p2160, .p1080] : [.p1080] }
    }

    enum Role { case change, wait }

    /// The roles whose flight is on screen.
    private(set) var visible: Set<Role> = []
    /// A flight is on screen.
    var showing: Bool { !visible.isEmpty }
    /// How much of the ground covers the picture, 0 to 1. Animated by `cover` and `uncover`.
    private(set) var coverage: Double = 0
    /// What the ground says while a signal tunes: the channel on its way.
    private(set) var caption: String?
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false
    /// The skin whose ground the flights are drawn on. A change re-arms both roles with the
    /// same flights in the new colour.
    var skin: Skin = .day {
        didSet {
            guard skin != oldValue else { return }
            // A role whose flight is on screen re-arms in the new colour when it lands.
            let change = armedChange, wait = armedWait
            Task {
                if !visible.contains(.change) { await arm(.change, again: change) }
                if !visible.contains(.wait) { await arm(.wait, again: wait) }
            }
        }
    }

    let changePlayer = AVPlayer()
    let waitPlayer = AVPlayer()

    @ObservationIgnored private var nextChange = 0
    @ObservationIgnored private var nextWait = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var latch: Latch?
    @ObservationIgnored private var armedChange: Flight?
    @ObservationIgnored private var armedWait: Flight?
    /// The flight on screen last, so a wait flight never repeats the change flight before it.
    @ObservationIgnored private var lastFlown: Flight?
    /// Each flight's length, read from its file, for fitting a flight to a tune time.
    @ObservationIgnored private var lengths: [Flight: Double] = [:]
    /// A change flight that ended on the full wing, held there until the picture cuts in.
    @ObservationIgnored private var heldWing = false
    @ObservationIgnored private var tuneKey: String?
    @ObservationIgnored private var tuneExpected: Double = 2
    @ObservationIgnored private var coveredAt: ContinuousClock.Instant?
    @ObservationIgnored private var readyAt: ContinuousClock.Instant?
    @ObservationIgnored private var readyWatch: Task<Void, Never>?

    init() {
        for player in [changePlayer, waitPlayer] {
            // A flight must never take the audio session from the signal under it.
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            // A bundled file needs no buffer; waiting for one is a late first frame.
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
        }
        Task {
            for flight in Flight.allCases {
                guard let url = Self.url(flight, skin: .day),
                      let time = try? await AVURLAsset(url: url).load(.duration) else { continue }
                lengths[flight] = time.seconds
            }
            await arm(.change)
            await arm(.wait)
        }
    }

    func player(_ role: Role) -> AVPlayer { role == .change ? changePlayer : waitPlayer }

    static func url(_ flight: Flight, skin: Skin) -> URL? {
        for tier in Tier.device.fallbacks {
            if let url = Bundle.main.url(forResource: "flight-\(flight.rawValue)-\(skin.rawValue)-\(tier.rawValue)", withExtension: "mp4") {
                return url
            }
        }
        return nil
    }

    // MARK: - The ground

    /// Brings the ground up over the picture with `caption` on it. `animated: false` puts it
    /// there at once, for a screen that opens on a signal still tuning.
    func cover(caption: String?, animated: Bool = true) {
        if animated {
            // A slow rise (owner, 2026-10-06: "make the background slowly fade in and out").
            withAnimation(.easeInOut(duration: 0.6)) { coverage = 1; self.caption = caption }
        } else {
            coverage = 1
            self.caption = caption
        }
    }

    /// Takes the ground off the picture, revealing the new channel. Only the skin's colour fades
    /// (owner, 2026-10-06: "the fade in and out i was talking about the skin color/background
    /// only"); the bird never does. A wing held over the screen cuts straight to the picture:
    /// the wing is what hides the change.
    func uncover() {
        if heldWing {
            heldWing = false
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) { coverage = 0; caption = nil; visible = [] }
            changePlayer.pause()
            Task { await arm(.change) }
            return
        }
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { visible = [] }
        withAnimation(.easeInOut(duration: 0.8)) { coverage = 0; caption = nil }
    }

    // MARK: - Flights

    /// A channel change: the ground comes up as a change flight crosses it. The flight is the
    /// one whose length best fits how long this channel took to tune here last time (`key`,
    /// `TuneTimes`; `fallback` for a channel never tuned here), so a slow channel gets a long
    /// flight (owner, 2026-10-05: "if something tunes in 5 secs we use an animation
    /// accordingly"). `covered` runs once the ground hides the old picture (0.38 s), so the
    /// caller tunes behind the bird, and `ready` is timed from then. Returns when the bird has
    /// left, with the ground up and carrying `caption`, or with the wing held over the screen.
    /// Reduce Motion keeps the ground and leaves the bird out.
    func flyThrough(caption: String?, key: String? = nil, fallback: Double = 2,
                    covered: @escaping @MainActor () -> Void = {},
                    ready: (@MainActor () async -> Void)? = nil) async {
        cover(caption: nil)
        let mine = begin()
        tuneKey = key
        tuneExpected = key.map { TuneTimes.expected($0, fallback: fallback) } ?? fallback
        readyWatch?.cancel()
        readyWatch = nil
        readyAt = nil
        let coverTask = Task { @MainActor in
            // The old picture is hidden once the ground is most of the way up.
            try? await Task.sleep(for: .milliseconds(500))
            coveredAt = .now
            covered()
            watch(ready, mine: mine)
        }
        if !UIAccessibility.isReduceMotionEnabled {
            let flight = pickChange()
            // The skin's colour rises alone first; the bird flies once it is up. The flight
            // loads meanwhile.
            let rising = ContinuousClock.now
            if armedChange != flight { await arm(.change, again: flight) }
            let left = 0.6 - (ContinuousClock.now - rising).seconds
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            if let armed = await take(.change) { await run(.change, flight: armed, mine: mine) }
        }
        // The caller's tuning starts behind the ground whatever happened to the bird.
        await coverTask.value
        guard mine == generation else { return }
        withAnimation(.easeIn(duration: 0.25)) { self.caption = caption }
    }

    /// While the next signal is still tuning, wait flights cross the held ground in turn until
    /// `ready` returns. Then the bird is taken off at once: the caller cuts the picture in. A
    /// wing held over the screen stays only if the picture is ready to cut in behind it.
    func holdUntil(_ ready: @escaping @MainActor () async -> Void) async {
        let mine = generation
        if readyWatch == nil { watch(ready, mine: mine) }
        if heldWing {
            try? await Task.sleep(for: .milliseconds(30))
            if readyAt == nil, mine == generation { releaseWing() }
        }
        let flights = Task { @MainActor [weak self] in
            // A brief beat on the bare ground first: most signals arrive within it, and then no
            // second bird is wanted.
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled, let self, mine == self.generation {
                guard !UIAccessibility.isReduceMotionEnabled, var flight = await self.take(.wait) else { return }
                if flight == self.lastFlown {
                    await self.arm(.wait)
                    guard let next = await self.take(.wait) else { return }
                    flight = next
                }
                if Task.isCancelled { return }
                await self.run(.wait, flight: flight, mine: mine)
            }
        }
        await readyWatch?.value
        flights.cancel()
        guard mine == generation else { return }
        if visible.contains(.wait) {
            latch?.open()
            waitPlayer.pause()
            visible.remove(.wait)
        }
        if let tuneKey, let coveredAt, let readyAt {
            let took = (readyAt - coveredAt).seconds
            #if DEBUG
            print("KJTUNE \(tuneKey) expected=\(String(format: "%.1f", tuneExpected)) took=\(String(format: "%.1f", took))")
            // A forced slow tune is a test, not a measurement.
            if UserDefaults.standard.integer(forKey: "kjslowtune") == 0 { TuneTimes.record(tuneKey, seconds: took) }
            #else
            TuneTimes.record(tuneKey, seconds: took)
            #endif
        }
    }

    /// Times the signal from the moment it was asked for; `holdUntil` starts it instead for a
    /// caller that did not pass `ready` to `flyThrough`.
    private func watch(_ ready: (@MainActor () async -> Void)?, mine: Int) {
        guard let ready, readyWatch == nil else { return }
        readyWatch = Task { @MainActor [weak self] in
            await ready()
            guard let self, mine == self.generation else { return }
            self.readyAt = .now
        }
    }

    /// The change flight fitted to the tune time this channel is expected to take.
    private func pickChange() -> Flight {
        let available = Flight.change.filter { Self.url($0, skin: skin) != nil }
        nextChange += 1
        let flight = FlightChoice.pick(available, lengths: lengths, want: tuneExpected, exclude: lastFlown, turn: nextChange) ?? .across
        #if DEBUG
        print("KJPICK want=\(String(format: "%.1f", tuneExpected)) -> \(flight.rawValue)")
        #endif
        return flight
    }

    /// The wing comes off: the ground with TUNING shows while the signal is still on its way.
    private func releaseWing() {
        heldWing = false
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { _ = visible.remove(.change) }
        changePlayer.pause()
        Task { await arm(.change) }
    }

    /// Ends the flight that is on screen now; the ground stays.
    func skip() {
        latch?.open()
    }

    /// Takes the bird and the ground off the screen at once and readies the flights again.
    func clear() {
        _ = begin()
        heldWing = false
        readyWatch?.cancel()
        readyWatch = nil
        changePlayer.pause()
        waitPlayer.pause()
        visible = []
        caption = nil
        coverage = 0
        Task {
            await arm(.change)
            await arm(.wait)
        }
    }

    private func begin() -> Int {
        generation += 1
        latch?.open()
        latch = nil
        return generation
    }

    /// The flight armed for a role, arming it now if nothing is (a press before the first arm).
    private func take(_ role: Role) async -> Flight? {
        if (role == .change ? armedChange : armedWait) == nil { await arm(role) }
        let flight = role == .change ? armedChange : armedWait
        if role == .change { armedChange = nil } else { armedWait = nil }
        return flight
    }

    /// Plays the role's armed flight from its first frame and returns when it ends, is skipped
    /// or superseded, or runs a second past its length; then arms the next one.
    private func run(_ role: Role, flight: Flight, mine: Int) async {
        let player = player(role)
        guard let item = player.currentItem else { return }
        lastFlown = flight
        let latch = Latch()
        self.latch = latch
        let ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in latch.open() }
        }
        let failed = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in latch.open() }
        }
        let length = item.duration.isNumeric ? item.duration.seconds : 10
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(length + 1)) } catch { return }
            latch.open()
        }
        // The flight is opaque. A change flight comes up over the picture with the ground, so
        // the old picture goes the way the ground takes it; a wait flight is already on ground.
        // The flight's own ground is the skin's colour, already up behind it: it appears at once,
        // and the bird is solid from its first frame.
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { _ = visible.insert(role) }
        player.play()
        #if DEBUG
        let probe = FrameProbe(item: item); let began = ContinuousClock.now
        #endif
        await latch.wait()
        #if DEBUG
        let dropped = item.accessLog()?.events.map(\.numberOfDroppedVideoFrames).reduce(0, +) ?? -1
        print("KJFLIGHT \(flight.rawValue) tier=\(Tier.device.rawValue) len=\(String(format: "%.2f", length)) wall=\(ContinuousClock.now - began) dropped=\(dropped) \(probe.finish())")
        #endif
        timeout.cancel()
        NotificationCenter.default.removeObserver(ended)
        NotificationCenter.default.removeObserver(failed)
        if mine == generation { self.latch = nil }
        player.pause()
        if flight.endsCovered, role == .change, mine == generation {
            // The last frame is the wing filling the screen: it stays until the cut.
            heldWing = true
            return
        }
        visible.remove(role)
        Task { await arm(role) }
    }

    /// Loads the role's next flight in rotation (or `again`, in the current skin) at its first
    /// frame, paused, decoder warmed.
    private func arm(_ role: Role, again: Flight? = nil) async {
        let flight: Flight
        if let again {
            flight = again
        } else {
            let list = role == .change ? Flight.change : Flight.wait
            flight = list[(role == .change ? nextChange : nextWait) % list.count]
            if role == .change { nextChange += 1 } else { nextWait += 1 }
        }
        if role == .change { armedChange = nil } else { armedWait = nil }
        guard let url = Self.url(flight, skin: skin) else { return }
        let player = player(role)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        while item.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard item.status == .readyToPlay else { return }
        _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await player.preroll(atRate: 1)
        // A later arm (a skin change) has replaced this one.
        guard player.currentItem === item else { return }
        if role == .change { armedChange = flight } else { armedWait = flight }
    }
}

#if DEBUG
/// For on-device measurement: which video frames of a flight were ready on time, sampled on a
/// display link of its own thread so a busy main thread cannot hide or fake a skip, and how
/// late the main thread ran. Counts are by the quarter second of the flight.
@MainActor
final class FrameProbe: NSObject {
    private let video: VideoProbe
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0, last: CFTimeInterval = 0
    private var ui = 0, uiLate: [Int: Int] = [:]
    init(item: AVPlayerItem) {
        video = VideoProbe(item: item)
        super.init()
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ l: CADisplayLink) {
        if start == 0 { start = l.timestamp }
        if last > 0 {
            ui += 1
            if l.timestamp - last > 1.5 / 60 { uiLate[Int((l.timestamp - start) * 4), default: 0] += 1 }
        }
        last = l.timestamp
    }
    func finish() -> String {
        link?.invalidate()
        return "ui=\(ui) ui_late[\(Self.fmt(uiLate))] \(video.finish())"
    }
    nonisolated static func fmt(_ d: [Int: Int]) -> String { d.keys.sorted().map { "\(Double($0) / 4)s:\(d[$0]!)" }.joined(separator: ",") }
}

final class VideoProbe: NSObject, @unchecked Sendable {
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    private let item: AVPlayerItem
    private let lock = NSLock()
    private var link: CADisplayLink?
    private var thread: Thread?
    private var start: CFTimeInterval = 0, lastPTS = -1.0, frames = 0, ticks = 0, gaps: [Int: Int] = [:]
    init(item: AVPlayerItem) {
        self.item = item
        super.init()
        item.add(output)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
            self.lock.withLock { self.link = link }
            link.add(to: .current, forMode: .default)
            while !Thread.current.isCancelled { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }
    @objc private func tick(_ l: CADisplayLink) {
        lock.lock(); defer { lock.unlock() }
        if start == 0 { start = l.timestamp }
        ticks += 1
        let t = output.itemTime(forHostTime: l.targetTimestamp)
        guard output.hasNewPixelBuffer(forItemTime: t), output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) != nil else { return }
        let pts = t.seconds
        if lastPTS >= 0, pts - lastPTS > 1.5 / 24 {
            gaps[Int((l.timestamp - start) * 4), default: 0] += Int(((pts - lastPTS) * 24).rounded()) - 1
        }
        frames += 1
        lastPTS = pts
    }
    func finish() -> String {
        lock.lock(); link?.invalidate(); let r = "ticks=\(ticks) video=\(frames) video_skipped[\(FrameProbe.fmt(gaps))]"; lock.unlock()
        thread?.cancel()
        item.remove(output)
        return r
    }
}
#endif

/// How long each channel took to tune here, from the ground hiding the old picture to the new
/// one ready. Kept on the device, a running average per channel, so the next change to it gets
/// a flight of about that length.
enum TuneTimes {
    private static let key = "kj.tuneTimes.v3"

    static func expected(_ channel: String, fallback: Double) -> Double {
        (UserDefaults.standard.dictionary(forKey: key)?[channel] as? Double) ?? fallback
    }

    static func record(_ channel: String, seconds: Double) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        let before = all[channel] as? Double
        all[channel] = before.map { $0 * 0.5 + seconds * 0.5 } ?? seconds
        // ponytail: unbounded per-channel dictionary; a few thousand doubles at most.
        UserDefaults.standard.set(all, forKey: key)
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// A one-shot latch: `wait()` returns once `open()` has been called, however many times and
/// whichever came first. One waiter.
@MainActor
private final class Latch {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

/// The ground and the pigeon, over everything beneath them. The flights are 16:9 and fill the
/// screen, so the bird's edges are the screen's own edges.
struct StationClipLayer: View {
    let clips: StationClips
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground
                .opacity(clips.coverage)
                .ignoresSafeArea()
            if let caption = clips.caption, clips.coverage > 0 {
                VStack(spacing: 16) {
                    Kicker("Tuning")
                    Text(caption)
                        .kjDisplay(KJType.headline, tracking: -0.055)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, KJLayout.inset)
                .opacity(clips.coverage)
            }
            // Always in the tree, so each player's first frame is drawn before it is shown.
            PlayerLayerView(player: clips.waitPlayer, gravity: .resizeAspectFill)
                .ignoresSafeArea()
                .opacity(clips.visible.contains(.wait) ? 1 : 0)
            PlayerLayerView(player: clips.changePlayer, gravity: .resizeAspectFill)
                .ignoresSafeArea()
                .opacity(clips.visible.contains(.change) ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
