import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The channel change: the website's wing-wipe pigeon, on the skin's colour, in one unbroken
/// flight. The pigeon flies at the viewer as the skin's ground comes up over the picture, a wing
/// passes over the camera, and it flies on out of the frame; the ground stays, saying which
/// channel is tuning, until the new picture plays, and then fades off it.
///
/// The bird never stops (owner, 2026-10-05: the wing held while a channel tuned "gets hung").
/// The two halves are HEVC with alpha (tvos/scripts/make-pigeon-wipe.py, from the same Higgsfield
/// clip and cut as archive/assets/tv/khajistan-wing-wipe-*.mp4), queued back to back on one
/// AVQueuePlayer, which plays them without a gap; the out half's first frame is the in half's
/// last. The ground is whatever the skin paints: yellow by day, green at night, pink at dawn and
/// dusk. Measured on the owner's Apple TV HD: 0 late refreshes in 5 flights (one 33 ms in a 6th
/// half), decode at 47-50 fps against the clip's 24.
@MainActor @Observable
final class StationClips {
    /// The flight on screen.
    private(set) var flying = false
    /// The flight, if one is on screen; kept so callers can tell a press during it apart.
    var showing: Bool { flying }
    /// How much of the ground covers the picture, 0 to 1. Animated by `cover` and `uncover`.
    private(set) var coverage: Double = 0
    /// What the ground says while a signal tunes: the channel on its way.
    private(set) var caption: String?
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false

    let player = AVQueuePlayer()

    /// The flight's two halves, opened once.
    @ObservationIgnored private let assets: [AVURLAsset]
    /// Every flight gets a number. One that wakes to find it is no longer the newest stops there.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var latch: Latch?
    @ObservationIgnored private var armed = false
    /// The re-queue after a flight runs in the background so the ground can lift at once.
    @ObservationIgnored private var arming: Task<Void, Never>?

    /// The longest a flight may hold the screen, so a file that stalls cannot trap the viewer.
    private static let cap: Duration = .seconds(5)

    init() {
        assets = ["wipe-in", "wipe-out"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "mov").map { AVURLAsset(url: $0) }
        }
        // A flight must never take the audio session from the signal under it.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // A bundled file needs no buffer; waiting for one is a late first frame.
        player.automaticallyWaitsToMinimizeStalling = false
        rearm()
    }

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

    /// Lifts the ground off the picture.
    func uncover() {
        withAnimation(.easeInOut(duration: 0.6)) { coverage = 0; caption = nil }
    }

    /// The pigeon flies through: the ground comes up as it flies in, a wing passes over the
    /// camera, and it flies out. Returns when it has gone, the ground still up and now carrying
    /// `caption`. `covered` is called the moment the wing covers the screen, so the caller can
    /// start tuning behind it. Reduce Motion leaves the bird out and keeps the fades.
    func flyThrough(caption: String?, covered: @escaping @MainActor () -> Void = {}) async {
        cover(caption: nil)
        guard !UIAccessibility.isReduceMotionEnabled, assets.count == 2 else {
            try? await Task.sleep(for: .milliseconds(350))
            covered()
            withAnimation(.easeIn(duration: 0.3)) { self.caption = caption }
            return
        }
        let mine = begin()
        if !armed {
            if arming == nil { rearm() }
            await arming?.value
        }
        // Another flight began while this one waited for the queue.
        guard mine == generation, armed, let first = player.items().first else { return }

        let latch = Latch()
        self.latch = latch
        // The wing covers the screen where the first half ends; the queue goes straight on.
        // `covered` runs once: there, or after the flight if it was cut short before it.
        var coveredDone = false
        let coverOnce: @MainActor () -> Void = {
            guard !coveredDone else { return }
            coveredDone = true
            covered()
        }
        let coverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: first, queue: .main
        ) { _ in Task { @MainActor in coverOnce() } }
        let last = player.items().last
        let endTokens = [Notification.Name.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime].map { name in
            NotificationCenter.default.addObserver(forName: name, object: last, queue: .main) { _ in
                Task { @MainActor in latch.open() }
            }
        }
        let timeout = Task {
            do { try await Task.sleep(for: Self.cap) } catch { return }
            latch.open()
        }
        armed = false
        withAnimation(.easeIn(duration: 0.1)) { flying = true }
        player.play()
        await latch.wait()
        timeout.cancel()
        NotificationCenter.default.removeObserver(coverToken)
        for token in endTokens { NotificationCenter.default.removeObserver(token) }
        guard mine == generation else { return }
        self.latch = nil
        coverOnce()
        // The last frame still carries the tip of the tail: it fades rather than vanishing.
        withAnimation(.easeOut(duration: 0.18)) { flying = false }
        withAnimation(.easeIn(duration: 0.3)) { self.caption = caption }
        // Re-queue once the tail has faded, without holding the caller: the ground can lift as
        // soon as the picture plays.
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            if mine == generation { rearm() }
        }
    }

    /// Ends the flight that is on screen now; the ground stays.
    func skip() {
        latch?.open()
    }

    /// Takes the bird and the ground off the screen at once and readies the flight for next time.
    func clear() {
        _ = begin()
        player.pause()
        flying = false
        caption = nil
        coverage = 0
        rearm()
    }

    private func begin() -> Int {
        generation += 1
        latch?.open()
        latch = nil
        return generation
    }

    /// Arms run one after another, never two at once: each waits for the one before it.
    private func rearm() {
        armed = false
        let previous = arming
        arming = Task {
            await previous?.value
            await arm()
        }
    }

    /// Queues both halves from their first frame, paused, with the decoder warmed (preroll), so
    /// the next press starts on time. The first decode on a cold Apple TV HD ran at 27 fps
    /// against the clip's 24, warm at 47-50 (measured on the device, 2026-10-05).
    private func arm() async {
        player.pause()
        player.removeAllItems()
        for asset in assets {
            let item = AVPlayerItem(asset: asset)
            if player.canInsert(item, after: nil) { player.insert(item, after: nil) }
        }
        guard let first = player.items().first else { return }
        while first.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard first.status == .readyToPlay else { return }
        _ = await player.preroll(atRate: 1)
        armed = true
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

/// The ground and the pigeon, over everything beneath them. The wipe is 16:9 and fills the screen,
/// so the bird's edges are the screen's own edges.
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
            // Always in the tree, so its first frame is drawn before it is shown. Fill: on a
            // screen that is not exactly 16:9 the wing still reaches every edge.
            PlayerLayerView(player: clips.player, gravity: .resizeAspectFill)
                .ignoresSafeArea()
                .opacity(clips.flying ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
