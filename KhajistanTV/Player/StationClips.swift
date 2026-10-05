import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The house pigeon, crossing the screen when a channel changes.
///
/// Five flights, generated for the apps and lifted off their backdrop so the app paints the
/// skin's ground behind the bird (tvos/scripts/flights/, FLIGHTS.json). Owner, 2026-10-05: "4-5
/// is good of varying lengths but our mascot needs to be consistent in look"; "the pigeon do
/// flamboyant swirling and twirling to cross ... when the transition needs to be long".
///
/// - A **change** flight carries every channel change, in rotation, so no two changes in a row
///   look the same: Across (the website's wing wipe, remade), Approach, Swoop.
/// - A **wait** flight crosses the held ground when the next signal is still tuning after the
///   change flight has gone, Twirl and Spiral in turn, until the picture is ready; the picture
///   then cuts in.
///
/// Each flight is HEVC with alpha in up to three sizes; the device plays the largest it can play
/// smoothly (see `Tier`). Two players, one per role, each prerolled before it is needed, both
/// layers always in the view tree.
@MainActor @Observable
final class StationClips {
    enum Flight: String, CaseIterable {
        case across, approach, swoop, twirl, spiral
        static let change: [Flight] = [.across, .approach, .swoop]
        static let wait: [Flight] = [.twirl, .spiral]
    }

    /// Which size of each flight this device plays. Measured on the owner's Apple TV HD (A8),
    /// 2026-10-05: 1080p HEVC with alpha decodes at 24-32 fps against the clips' 24, 720p at
    /// 44-48. A 4K-capable box on a 4K screen plays 2160 where a flight has it.
    enum Tier: String {
        case p720 = "720", p1080 = "1080", p2160 = "2160"

        static let device: Tier = {
            var info = utsname()
            uname(&info)
            let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            // AppleTV5,3 is the Apple TV HD: no hardware for HEVC with alpha at 1080p.
            if machine.hasPrefix("AppleTV5") { return .p720 }
            return UIScreen.main.nativeBounds.width >= 3800 ? .p2160 : .p1080
        }()

        var fallbacks: [Tier] {
            switch self {
            case .p2160: return [.p2160, .p1080, .p720]
            case .p1080: return [.p1080, .p720]
            case .p720: return [.p720]
            }
        }
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

    static func url(_ flight: Flight) -> URL? {
        for tier in Tier.device.fallbacks {
            if let url = Bundle.main.url(forResource: "flight-\(flight.rawValue)-\(tier.rawValue)", withExtension: "mov") {
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
        // The first frame may already carry part of the bird: it comes in over a tenth of a second.
        withAnimation(.easeIn(duration: 0.1)) { _ = visible.insert(role) }
        player.play()
        await latch.wait()
        timeout.cancel()
        NotificationCenter.default.removeObserver(ended)
        NotificationCenter.default.removeObserver(failed)
        if mine == generation { self.latch = nil }
        player.pause()
        visible.remove(role)
        Task { await arm(role) }
    }

    /// Loads the role's next flight in rotation at its first frame, paused, decoder warmed.
    private func arm(_ role: Role) async {
        let list = role == .change ? Flight.change : Flight.wait
        let index = role == .change ? nextChange : nextWait
        let flight = list[index % list.count]
        if role == .change { nextChange += 1 } else { nextWait += 1 }
        guard let url = Self.url(flight) else { return }
        let player = player(role)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        while item.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard item.status == .readyToPlay else { return }
        _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await player.preroll(atRate: 1)
        if role == .change { armedChange = flight } else { armedWait = flight }
    }
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
