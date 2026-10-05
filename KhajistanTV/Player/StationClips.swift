import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The channel change: the skin's ground covers the picture while the pigeon flies at the
/// viewer, holds while the next signal tunes, and lifts off it as the pigeon flies away.
///
/// The two flights are HEVC with alpha (tvos/scripts/make-pigeon-flight.py), so the pigeon is
/// drawn over whatever ground the skin of the hour paints: yellow by day, green at night, pink at
/// dawn and dusk. They play on a player of their own, so a flight never disturbs the signal.
@MainActor @Observable
final class StationClips {
    enum Clip: String {
        /// Flies at the viewer: plays as the ground comes up over the picture.
        case flightIn = "flight-in"
        /// Flies up and away: plays as the ground lifts off the new picture.
        case flightOut = "flight-out"

        /// The longest a flight may hold the screen, so a file that stalls cannot trap the viewer.
        fileprivate var cap: Duration { .seconds(4) }
    }

    /// The flight on screen, if any. `StationClipLayer` draws the player while this is set.
    private(set) var showing: Clip?
    /// How much of the ground covers the picture, 0 to 1. Animated by `cover` and `uncover`.
    private(set) var coverage: Double = 0
    /// What the held ground says while the next signal tunes: the channel on its way.
    private(set) var caption: String?
    let player = AVPlayer()

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

    /// The pigeon flies in and the ground comes up with it. Returns once the picture is covered.
    func flyIn(caption: String?) async {
        cover(caption: caption)
        await play(.flightIn)
    }

    /// The ground lifts and the pigeon flies off the new picture. Returns when the flight ends.
    func flyOut() async {
        uncover()
        await play(.flightOut)
    }

    /// Plays a flight and returns when it ends, fails, is skipped or cleared, or runs out of time.
    /// Never throws; a flight that is not in the bundle returns at once. Reduce Motion leaves the
    /// flights out and keeps the ground's fade.
    func play(_ clip: Clip) async {
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
        stopPlayer()
        showing = nil
    }

    /// Ends the flight that is playing now. `play` returns; the ground stays where it is.
    func skip() {
        latch?.open()
    }

    /// Ends the flight, stops the player and takes the ground off the screen at once.
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

/// The ground and the pigeon, over everything beneath them. The flight is drawn at the screen's
/// height in its own 9:16 frame, never stretched past its pixels.
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
                PlayerLayerView(player: clips.player)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
