import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The channel change: the website's wing wipe, on the skin's colour. The pigeon flies at the
/// viewer over the skin's ground until a wing fills the screen; the wing holds while the next
/// signal tunes; the wing sweeps off the new picture.
///
/// The two halves are HEVC with alpha (tvos/scripts/make-pigeon-wipe.py, from the same Higgsfield
/// clip and the same cut as archive/assets/tv/khajistan-wing-wipe-*.mp4), so the ground behind
/// the pigeon is whatever the skin paints: yellow by day, green at night, pink at dawn and dusk.
/// They play on a player of their own, so the wipe never disturbs the signal.
@MainActor @Observable
final class StationClips {
    enum Clip: String {
        /// Flies at the viewer until a wing fills the screen (1.6 s); its last frame is held.
        case wipeIn = "wipe-in"
        /// The wing sweeps off (0.9 s).
        case wipeOut = "wipe-out"

        /// The longest a clip may hold the screen, so a file that stalls cannot trap the viewer.
        fileprivate var cap: Duration { .seconds(4) }
    }

    /// The flight on screen, if any. `StationClipLayer` draws the player while this is set.
    private(set) var showing: Clip?
    /// How much of the ground covers the picture, 0 to 1. Animated by `cover` and `uncover`.
    private(set) var coverage: Double = 0
    /// What the held ground says while the next signal tunes: the channel on its way.
    private(set) var caption: String?
    let player = AVPlayer()
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false

    /// Every play gets a number. A play that wakes to find it is no longer the newest leaves the
    /// screen to the newer one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var latch: Latch?

    init() {
        // A flight must never take the audio session from the signal under it.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    /// Brings the ground up over the picture with `caption` on it. `animated: false` puts it
    /// there at once, for a screen that opens on a signal still tuning.
    func cover(caption: String?, animated: Bool = true) {
        self.caption = caption
        if animated {
            withAnimation(.easeIn(duration: 0.35)) { coverage = 1 }
        } else {
            coverage = 1
        }
    }

    /// Lifts the ground off the picture.
    func uncover() {
        caption = nil
        withAnimation(.easeOut(duration: 0.7)) { coverage = 0 }
    }

    /// The pigeon flies in over the ground, which comes up with it, and the wing that fills the
    /// screen at the end is held there. Returns once the screen is covered.
    func wipeIn() async {
        cover(caption: nil)
        await play(.wipeIn, holdLastFrame: true)
    }

    /// The ground fades from under the held wing (unseen behind it, a plain fade with Reduce
    /// Motion) and the wing sweeps off the picture.
    func wipeOut() async {
        uncover()
        await play(.wipeOut)
    }

    /// Plays half of the wipe and returns when it ends, fails, is skipped or cleared, or runs out
    /// of time. `holdLastFrame` leaves it on screen: the wing that covers the screen stays until
    /// the next `play` or `clear`. Never throws; a clip that is not in the bundle returns at once.
    /// Reduce Motion leaves the wipe out and keeps the ground's fade.
    func play(_ clip: Clip, holdLastFrame: Bool = false) async {
        if UIAccessibility.isReduceMotionEnabled { return }
        guard let url = Bundle.main.url(forResource: clip.rawValue, withExtension: "mov") else { return }

        generation += 1
        let mine = generation
        self.latch?.open()
        let latch = Latch()
        self.latch = latch

        let item = AVPlayerItem(url: url)
        let endings = [Notification.Name.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime].map { name in
            NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { _ in
                Task { @MainActor in latch.open() }
            }
        }
        let failure = item.observe(\.status, options: [.new]) { observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor in latch.open() }
        }
        let timeout = Task {
            do { try await Task.sleep(for: clip.cap) } catch { return }
            latch.open()
        }

        player.replaceCurrentItem(with: item)
        showing = clip
        player.play()
        await latch.wait()

        timeout.cancel()
        failure.invalidate()
        for token in endings { NotificationCenter.default.removeObserver(token) }

        guard mine == generation else { return }
        self.latch = nil
        if holdLastFrame {
            // Left early (skipped, or out of time) the wing is part-way across. The last frame is
            // the one that covers the screen. The seek is not awaited: it can only be late.
            if item.duration.isNumeric {
                player.seek(to: item.duration, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
            }
        } else {
            stopPlayer()
            showing = nil
        }
    }

    /// Ends the clip that is playing now. `play` returns; a held wing and the ground stay.
    func skip() {
        latch?.open()
    }

    /// Ends the clip, stops the player and takes the wing and the ground off the screen at once.
    func clear() {
        generation += 1
        latch?.open()
        latch = nil
        stopPlayer()
        showing = nil
        caption = nil
        coverage = 0
    }

    private func stopPlayer() {
        player.pause()
        player.replaceCurrentItem(with: nil)
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
            if clips.showing != nil {
                // Fill: on a screen that is not exactly 16:9 the wing still reaches every edge.
                PlayerLayerView(player: clips.player, gravity: .resizeAspectFill)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
