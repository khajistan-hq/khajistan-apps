import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The pigeon flying over the live picture while the channel hard-cuts behind it (owner,
/// 2026-10-06: "hard cut is ok from one channel to next ... and the pigeon transition on it",
/// using the flights they starred in Higgsfield; "use the longer one only for channels that take
/// longer than 8-10 secs to load").
///
/// Each flight is the bird alone, HEVC with alpha, with a sidecar saying its length and `cut`:
/// the last moment the bird covers the most of the screen, which is where the channel changes
/// if the new one is ready (tvos/scripts/flights/, KJ_OVERLAY=1).
@MainActor @Observable
final class PigeonOverlay {
    struct Flight: Equatable {
        let name: String
        let url: URL
        let length: Double
        let cut: Double
        /// How much of the screen the bird covers at `cut`. Under half, there is nothing to hide the
        /// cut behind, so the channel cuts the moment it is ready.
        let cutCover: Double
        var waitsForCover: Bool { cutCover >= 0.5 }
    }

    /// Short flights carry an ordinary change; the long ones only a channel that took 8 s or
    /// more to tune here before.
    static let short = ["across", "swerve", "hover", "lift"]
    static let long = ["loop", "twirl"]
    static let slowChannel = 8.0

    /// A flight is on screen.
    private(set) var showing = false
    /// The flight on screen, or the last one.
    private(set) var current: Flight?
    let player = AVPlayer()

    @ObservationIgnored private var flights: [String: Flight] = [:]
    @ObservationIgnored private var turn = 0
    @ObservationIgnored private var last: String?
    @ObservationIgnored private var armed: Flight?
    @ObservationIgnored private var ended: Signal?

    init() {
        // A flight must never take the audio session from the signal under it.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        for name in Self.short + Self.long { if let flight = Self.load(name) { flights[name] = flight } }
    }

    /// The flight for a channel expected to take `expected` seconds, turning through its pool and
    /// never the one that flew last.
    func pick(expected: Double) -> Flight? {
        let pool = (expected >= Self.slowChannel ? Self.long : Self.short).compactMap { flights[$0] }
        let options = pool.filter { $0.name != last }
        guard !options.isEmpty || !pool.isEmpty else { return nil }
        turn += 1
        let list = options.isEmpty ? pool : options
        return list[turn % list.count]
    }

    /// Loads a flight at its first frame, paused, decoder warmed, so it starts the instant it is
    /// asked for.
    func arm(_ flight: Flight) async {
        if armed == flight, player.currentTime() == .zero { return }
        let item = AVPlayerItem(url: flight.url)
        player.replaceCurrentItem(with: item)
        while item.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard item.status == .readyToPlay else { armed = nil; return }
        _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await player.preroll(atRate: 1)
        if player.currentItem === item { armed = flight }
    }

    /// Plays the armed flight over the picture. Returns at once; `waitForEnd` returns when the
    /// bird has gone.
    func start() {
        guard let flight = armed, let item = player.currentItem else { return }
        last = flight.name
        current = flight
        armed = nil
        let done = Signal()
        ended = done
        var tokens: [NSObjectProtocol] = []
        for name in [AVPlayerItem.didPlayToEndTimeNotification, .AVPlayerItemFailedToPlayToEndTime] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { _ in
                Task { @MainActor in done.fire() }
            })
        }
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(flight.length + 1))
            done.fire()
        }
        Task { @MainActor [weak self] in
            await done.wait()
            timeout.cancel()
            tokens.forEach(NotificationCenter.default.removeObserver)
            guard let self, self.ended === done else { return }
            self.showing = false
            self.player.pause()
        }
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { showing = true }
        player.play()
        #if DEBUG
        let probe = VideoProbe(item: item), began = ContinuousClock.now
        Task { @MainActor in
            await done.wait()
            print("KJFLIGHT \(flight.name) len=\(String(format: "%.2f", flight.length)) wall=\(ContinuousClock.now - began) \(probe.finish())")
        }
        #endif
    }

    /// Seconds into the flight on screen.
    var elapsed: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var isFlying: Bool { showing }

    func waitForEnd() async {
        await ended?.wait()
    }

    /// Takes the bird off at once.
    func clear() {
        ended?.fire()
        ended = nil
        showing = false
        player.pause()
    }

    private static func load(_ name: String) -> Flight? {
        let tiers = Self.tierOrder
        guard let url = tiers.lazy.compactMap({ Bundle.main.url(forResource: "flight-\(name)-alpha-\($0)", withExtension: "mov") }).first,
              let meta = Bundle.main.url(forResource: "flight-\(name)", withExtension: "json"),
              let data = try? Data(contentsOf: meta),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let length = json["length"], let cut = json["cut"] else { return nil }
        return Flight(name: name, url: url, length: length, cut: cut, cutCover: json["cutCover"] ?? 0)
    }

    /// 1080 where the box decodes it in time, 720 on the Apple TV HD unless measured otherwise.
    private static var tierOrder: [String] {
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "kjflighttier") { return [forced, "1080", "720"] }
        #endif
        return ["1080", "720"]
    }
}

/// How long each channel took to tune here, from asking to playing. Kept on the device, a running
/// average per channel, so a channel known to be slow gets a long flight.
enum TuneTimes {
    private static let key = "kj.tuneTimes.v4"

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

/// A one-shot signal any number of waiters can await; `wait()` returns at once once fired.
@MainActor
final class Signal {
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

/// The pigeon over everything beneath it, while a flight is on screen.
struct PigeonOverlayLayer: View {
    let overlay: PigeonOverlay

    var body: some View {
        // Always in the tree, so the flight's first frame is drawn before it is shown.
        PlayerLayerView(player: overlay.player, gravity: .resizeAspectFill)
            .ignoresSafeArea()
            .opacity(overlay.showing ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// For on-device measurement: which video frames of a flight were ready on time, sampled on a
/// display link of its own thread, so a busy main thread cannot hide or fake a skip.
final class VideoProbe: NSObject, @unchecked Sendable {
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    private let item: AVPlayerItem
    private let lock = NSLock()
    private var link: CADisplayLink?
    private var thread: Thread?
    private var lastPTS = -1.0, frames = 0, skipped = 0

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
        let t = output.itemTime(forHostTime: l.targetTimestamp)
        guard output.hasNewPixelBuffer(forItemTime: t), output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) != nil else { return }
        let pts = t.seconds
        if lastPTS >= 0, pts - lastPTS > 1.5 / 24 { skipped += Int(((pts - lastPTS) * 24).rounded()) - 1 }
        frames += 1
        lastPTS = pts
    }

    func finish() -> String {
        lock.lock(); link?.invalidate(); let r = "video=\(frames) skipped=\(skipped)"; lock.unlock()
        thread?.cancel()
        item.remove(output)
        return r
    }
}
#endif
