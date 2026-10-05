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
///   look the same: Across (the website's wing wipe, remade), Approach (into us), Rise (away
///   from us, wings clapped over the back). Swoop was removed (owner, 2026-10-05: "looks like
///   it's swimming and seems 2D").
/// - A **wait** flight crosses the held ground when the next signal is still tuning after the
///   change flight has gone — Twirl, Roller (a roller pigeon's backward somersaults), Spiral,
///   Display (wing-clapping display flight) in turn — until the picture is ready; the picture
///   then cuts in.
///
/// Each flight is ordinary opaque video, one file per skin, so every device decodes it in
/// hardware: HEVC with alpha dropped frames by the third on the Apple TV HD (2026-10-05). The
/// skin's ground also sits under the players, so the hand-off at either end is the same
/// colour. Two players, one per role, each prerolled before it is needed, both layers always
/// in the view tree.
@MainActor @Observable
final class StationClips {
    enum Flight: String, CaseIterable {
        case across, approach, rise, twirl, roller, spiral, display
        static let change: [Flight] = [.across, .approach, .rise]
        static let wait: [Flight] = [.twirl, .roller, .spiral, .display]
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
            withAnimation(.easeIn(duration: 0.35)) { coverage = 1; self.caption = caption }
        } else {
            coverage = 1
            self.caption = caption
        }
    }

    /// Takes the ground off the picture. A cut by default: the pigeon is the transition, so the
    /// new picture arrives like a channel on a television, and only its sound eases up. `fade`
    /// is for a screen that opens on a signal, where nothing flew.
    func uncover(fade: Bool = false) {
        if fade {
            withAnimation(.easeInOut(duration: 0.4)) { coverage = 0; caption = nil }
        } else {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) { coverage = 0; caption = nil }
        }
    }

    // MARK: - Flights

    /// A channel change: the ground comes up as the next change flight crosses it. `covered`
    /// runs once the ground hides the old picture (0.38 s), so the caller tunes behind the bird;
    /// returns when the bird has left the screen, with the ground up and carrying `caption`.
    /// Reduce Motion keeps the ground and leaves the bird out.
    func flyThrough(caption: String?, covered: @escaping @MainActor () -> Void = {}) async {
        cover(caption: nil)
        let mine = begin()
        let coverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            covered()
        }
        if !UIAccessibility.isReduceMotionEnabled, let flight = await take(.change) {
            await run(.change, flight: flight, mine: mine)
        }
        // The caller's tuning starts behind the ground whatever happened to the bird.
        await coverTask.value
        guard mine == generation else { return }
        withAnimation(.easeIn(duration: 0.25)) { self.caption = caption }
    }

    /// While the next signal is still tuning, wait flights cross the held ground in turn until
    /// `ready` returns. Then the bird is taken off at once: the caller cuts the picture in.
    func holdUntil(_ ready: @escaping @MainActor () async -> Void) async {
        let mine = generation
        let flights = Task { @MainActor [weak self] in
            // A brief beat on the bare ground first: most signals arrive within it, and then no
            // second bird is wanted.
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled, let self, mine == self.generation {
                guard !UIAccessibility.isReduceMotionEnabled, let flight = await self.take(.wait) else { return }
                if Task.isCancelled { return }
                await self.run(.wait, flight: flight, mine: mine)
            }
        }
        await ready()
        flights.cancel()
        guard mine == generation else { return }
        if visible.contains(.wait) {
            latch?.open()
            waitPlayer.pause()
            visible.remove(.wait)
        }
    }

    /// Ends the flight that is on screen now; the ground stays.
    func skip() {
        latch?.open()
    }

    /// Takes the bird and the ground off the screen at once and readies the flights again.
    func clear() {
        _ = begin()
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
        withAnimation(.easeIn(duration: role == .change ? 0.35 : 0.1)) { _ = visible.insert(role) }
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
