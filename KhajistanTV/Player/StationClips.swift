import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The house pigeon, carrying a channel change.
///
/// Owner, 2026-10-05: "the pigeons have lost the transition effect for example a wing covering
/// the full screen"; "make sure there are varying lengths of animations to be used according to
/// the tuning time of a channel". So every flight is a **cover flight**: it opens on the pigeon's
/// wing filling the screen, the bird pulls back over the skin's ground, performs, and flies back
/// into the lens until the same wing fills the screen again (tvos/scripts/flights/, FLIGHTS.json).
///
/// - A change brings the wing up over the old picture (0.25 s) and tunes behind it.
/// - The first flight is the one whose length best fits how long this channel took to tune the
///   last time (`TuneTimes`), so a 5-second channel gets a flight of about 5 seconds.
/// - Flights chain wing to wing. At each wing, a picture that is ready cuts in behind it; one
///   that is not gets another flight, fitted to the time it still has to go, or the shortest
///   once it is overdue.
/// - A press during a flight retunes behind the bird; the flight on screen carries on.
///
/// Each flight is ordinary opaque video, one file per skin (HEVC with alpha dropped frames by
/// the third on the Apple TV HD). Two players take turns, the next one prerolled at its first
/// frame, which is the same wing the last one ended on.
@MainActor @Observable
final class StationClips {
    enum Flight: String, CaseIterable {
        case dart, swerve, roll, circle, roller, loop, display
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

    enum Role { case a, b }

    /// The player whose layer is on screen; nil when no flight is.
    private(set) var active: Role?
    /// The flight layer came up over a picture, and fades in rather than cutting.
    private(set) var entering = false
    /// A flight is on screen.
    var showing: Bool { active != nil }
    /// How much of the ground covers the picture, 0 to 1. Used where nothing flies: a screen that
    /// opens on a signal still tuning, a film, and Reduce Motion.
    private(set) var coverage: Double = 0
    /// What the ground says while a signal tunes: the channel on its way.
    private(set) var caption: String?
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false
    /// The skin whose ground the flights are drawn on. A change re-arms the idle player.
    var skin: Skin = .day {
        didSet { if skin != oldValue { Task { await arm(idle, with: pick(for: 4)) } } }
    }

    let playerA = AVPlayer()
    let playerB = AVPlayer()

    @ObservationIgnored private var lengths: [Flight: Double] = [:]
    @ObservationIgnored private var armed: [Role: (flight: Flight, skin: Skin)] = [:]
    @ObservationIgnored private var lastFlown: Flight?
    @ObservationIgnored private var rotation = 0
    @ObservationIgnored private var flightEnd: Signal?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tuneKey: String?
    @ObservationIgnored private var tuneExpected: Double = 4
    @ObservationIgnored private var coveredAt: ContinuousClock.Instant?
    /// When the signal behind the wing was ready, watched from the moment it started tuning.
    @ObservationIgnored private var readyAt: ContinuousClock.Instant?
    @ObservationIgnored private var readyWatch: Task<Void, Never>?

    init() {
        for player in [playerA, playerB] {
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
            await arm(.a, with: pick(for: 4))
        }
    }

    func player(_ role: Role) -> AVPlayer { role == .a ? playerA : playerB }
    /// The player free for the next flight: the other one while a flight is on screen, and A
    /// otherwise, which is the one kept armed between changes.
    private var idle: Role { active == .a ? .b : .a }

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
            withAnimation(.easeIn(duration: 0.35)) { coverage = 1; self.caption = caption }
        } else {
            coverage = 1
            self.caption = caption
        }
    }

    /// Takes the wing or the ground off the picture: a cut, as a channel arrives on a television.
    /// `fade` is for a screen that opens on a signal, where nothing flew.
    func uncover(fade: Bool = false) {
        tuneKey = nil
        let wasFlying = active
        if fade {
            withAnimation(.easeInOut(duration: 0.4)) { coverage = 0; caption = nil }
        } else {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) { coverage = 0; caption = nil; active = nil; entering = false }
        }
        if let wasFlying {
            player(wasFlying).pause()
            Task { await arm(.a, with: pick(for: tuneExpected)) }
        }
    }

    // MARK: - Flights

    /// A channel change. The wing comes up over the picture, `covered` runs once it hides the
    /// old picture (0.3 s) so the caller tunes behind it, and this returns when the flight is
    /// back at the wing. `key` names the channel for `TuneTimes`; `fallback` is the guess for a
    /// channel never tuned here. A flight already on screen keeps flying: `covered` runs at once
    /// and this returns at that flight's wing. Reduce Motion gets the ground and no bird.
    func flyThrough(caption: String?, key: String? = nil, fallback: Double = 4, covered: @escaping @MainActor () -> Void = {},
                    ready: (@MainActor () async -> Void)? = nil) async {
        generation += 1
        readyWatch?.cancel()
        readyWatch = nil
        readyAt = nil
        tuneKey = key
        tuneExpected = key.map { TuneTimes.expected($0, fallback: fallback) } ?? fallback
        if UIAccessibility.isReduceMotionEnabled {
            cover(caption: caption)
            try? await Task.sleep(for: .milliseconds(350))
            coveredAt = .now
            covered()
            watch(ready)
            return
        }
        if active != nil, let flightEnd {
            coveredAt = .now
            covered()
            watch(ready)
            await flightEnd.wait()
            return
        }
        let flight = pick(for: tuneExpected)
        let role = idle
        await arm(role, with: flight)
        entering = true
        let end = start(role, flight)
        try? await Task.sleep(for: .milliseconds(300))
        entering = false
        coveredAt = .now
        covered()
        watch(ready)
        await end.wait()
    }

    /// Starts timing the signal from the moment it was asked for. `holdUntil` starts it instead
    /// for a caller that did not pass `ready` here.
    private func watch(_ ready: (@MainActor () async -> Void)?) {
        guard let ready else { return }
        let mine = generation
        readyWatch = Task { @MainActor [weak self] in
            await ready()
            guard let self, !Task.isCancelled, mine == self.generation else { return }
            self.readyAt = .now
        }
    }

    /// Flies on, wing to wing, until `ready` has returned; then returns at a wing, and the caller
    /// cuts the picture in with `uncover`. A newer change takes over the loop.
    func holdUntil(_ ready: @escaping @MainActor () async -> Void) async {
        let mine = generation
        if readyWatch == nil { watch(ready) }
        if active == nil {
            await readyWatch?.value
        }
        while mine == generation, active != nil, !Task.isCancelled {
            // A signal already playing answers at once; give it the moment to say so.
            try? await Task.sleep(for: .milliseconds(30))
            if readyAt != nil { break }
            let role = idle
            // The next flight was armed while this one flew (`start`).
            let flight = armed[role]?.flight ?? pick(for: tuneExpected - elapsedSinceCovered)
            await arm(role, with: flight)
            guard mine == generation, readyAt == nil else { break }
            await start(role, flight).wait()
        }
        guard mine == generation, let tuneKey, let coveredAt, let readyAt else { return }
        let took = (readyAt - coveredAt).seconds
        #if DEBUG
        print("KJTUNE \(tuneKey) expected=\(String(format: "%.1f", tuneExpected)) took=\(String(format: "%.1f", took)) cut=\(String(format: "%.1f", elapsedSinceCovered))")
        #endif
        #if DEBUG
        // A forced slow tune is a test, not a measurement.
        if UserDefaults.standard.integer(forKey: "kjslowtune") == 0 { TuneTimes.record(tuneKey, seconds: took) }
        #else
        TuneTimes.record(tuneKey, seconds: took)
        #endif
        readyWatch = nil
    }

    private var elapsedSinceCovered: Double {
        coveredAt.map { (ContinuousClock.now - $0).seconds } ?? 0
    }

    /// Kept for the remote's handlers: a flight now runs to its wing, so a press does not end it.
    func skip() {}

    /// Takes the bird and the ground off the screen at once.
    func clear() {
        generation += 1
        tuneKey = nil
        flightEnd?.fire()
        flightEnd = nil
        playerA.pause()
        playerB.pause()
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { active = nil; entering = false; caption = nil; coverage = 0 }
        Task { await arm(.a, with: pick(for: 4)) }
    }

    /// The flight whose length best fits `want` seconds: the shortest that lasts at least that
    /// long, turning among those within a second of it, and never the one that just flew. Past
    /// due (`want` <= 0), the shortest, so the picture gets its next chance soonest.
    private func pick(for want: Double) -> Flight {
        let available = Flight.allCases.filter { Self.url($0, skin: skin) != nil }
        rotation += 1
        let flight = FlightChoice.pick(available, lengths: lengths, want: want, exclude: lastFlown, turn: rotation) ?? .allCases[0]
        #if DEBUG
        print("KJPICK want=\(String(format: "%.1f", want)) -> \(flight.rawValue) (\(lengths.count) lengths known)")
        #endif
        return flight
    }

    /// Puts the role's layer on screen at the flight's first frame (the wing) and plays it. The
    /// other layer leaves in the same frame, so the hand-over between two wings does not show.
    private func start(_ role: Role, _ flight: Flight) -> Signal {
        let end = Signal()
        flightEnd = end
        lastFlown = flight
        let player = player(role)
        let other = self.player(role == .a ? .b : .a)
        guard let item = player.currentItem else { end.fire(); return end }
        var observers: [NSObjectProtocol] = []
        for name in [AVPlayerItem.didPlayToEndTimeNotification, .AVPlayerItemFailedToPlayToEndTime] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { _ in
                Task { @MainActor in end.fire() }
            })
        }
        let length = item.duration.isNumeric ? item.duration.seconds : 12
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(length + 1))
            end.fire()
        }
        Task { @MainActor in
            await end.wait()
            timeout.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
        var cut = Transaction()
        cut.disablesAnimations = !entering
        withTransaction(cut) { active = role }
        other.pause()
        player.play()
        // Ready the other player with the flight to follow, fitted to the time left at this
        // one's wing, so a hand-over waits for nothing.
        let after = tuneExpected - elapsedSinceCovered - length
        let next = role == .a ? Role.b : Role.a
        Task { @MainActor in await arm(next, with: pick(for: after)) }
        #if DEBUG
        let probe = FrameProbe(item: item), began = ContinuousClock.now
        Task { @MainActor in
            await end.wait()
            print("KJFLIGHT \(flight.rawValue) tier=\(Tier.device.rawValue) len=\(String(format: "%.2f", length)) wall=\(ContinuousClock.now - began) \(probe.finish())")
        }
        #endif
        return end
    }

    /// Loads `flight` into the role's player at its first frame, paused, decoder warmed. A role
    /// already holding that flight in this skin is left as it is.
    private func arm(_ role: Role, with flight: Flight) async {
        guard role != active else { return }
        let player = player(role)
        if let held = armed[role], held.flight == flight, held.skin == skin, player.currentItem != nil {
            if player.currentTime() != .zero { _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) }
            return
        }
        armed[role] = nil
        guard let url = Self.url(flight, skin: skin) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        while item.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard item.status == .readyToPlay else { return }
        _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await player.preroll(atRate: 1)
        guard player.currentItem === item else { return }
        armed[role] = (flight, skin)
    }
}

/// How long each channel took to tune here, from the wing hiding the old picture to the new
/// one ready. Kept on the device, a running average per channel, so the next change to it
/// gets a flight of about that length.
enum TuneTimes {
    private static let key = "kj.tuneTimes.v2"

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

/// A one-shot signal any number of waiters can await; `wait()` returns at once once fired.
@MainActor
private final class Signal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        waiters.forEach { $0.resume() }
        waiters = []
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


/// The ground and the pigeon, over everything beneath them. The flights are 16:9 and fill the
/// screen.
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
            PlayerLayerView(player: clips.playerA, gravity: .resizeAspectFill)
                .ignoresSafeArea()
                .opacity(clips.active == .a ? 1 : 0)
            PlayerLayerView(player: clips.playerB, gravity: .resizeAspectFill)
                .ignoresSafeArea()
                .opacity(clips.active == .b ? 1 : 0)
        }
        .animation(clips.entering ? .easeIn(duration: 0.25) : nil, value: clips.active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
