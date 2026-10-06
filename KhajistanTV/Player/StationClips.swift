import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The station's own short films: the website's wing wipe, in and out, bundled with the app and
/// played on a player of their own, so a clip never disturbs the signal underneath it.
///
/// Owner, 2026-10-06: "bring back the very first iteration, hard cut no need to fade video, only
/// fade audio, i dont like any of the new you made all day today." This is that first version:
/// the wing crosses and holds, the channel tunes behind it, the wing leaves, and the picture cuts
/// in. Only the sound fades (PlayerController). The day's Higgsfield flights, cover flights and
/// colour fades are gone; their record is tvos/scripts/flights/FLIGHTS.json.
@MainActor @Observable
final class StationClips {
    enum Clip: String {
        case wingIn = "wing-wipe-in"
        case wingOut = "wing-wipe-out"

        /// The longest a clip may hold the screen, so a file that stalls cannot trap the viewer.
        fileprivate var cap: Duration { .seconds(4) }
    }

    /// The clip on screen, if any. `StationClipLayer` draws the player while this is set.
    private(set) var showing: Clip?
    let player = AVPlayer()
    /// Set by callers after the sign-on, and kept for the life of the app.
    var signOnPlayed = false
    /// The skin's colour with a name on it, for a screen that opens on a signal still tuning, and
    /// for a film. It comes and goes with a cut.
    private(set) var coverage: Double = 0
    private(set) var caption: String?

    /// Every play gets a number. A play that wakes to find it is no longer the newest leaves the
    /// screen to the newer one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var latch: Latch?

    /// Plays a bundled clip and returns when it ends, fails, is skipped or cleared, or runs out of
    /// time. `holdLastFrame` leaves it on screen: the wing that covers the screen stays covering
    /// it until the next `play` or `clear`. Never throws; a clip that is not in the bundle returns
    /// at once. Reduce Motion cuts the wipes.
    func play(_ clip: Clip, holdLastFrame: Bool = false) async {
        if UIAccessibility.isReduceMotionEnabled { return }
        guard let url = Bundle.main.url(forResource: clip.rawValue, withExtension: "mp4") else { return }

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

    /// Puts the skin's colour over the picture with `caption` on it.
    func cover(caption: String?, animated: Bool = false) {
        coverage = 1
        self.caption = caption
    }

    /// Takes the skin's colour off the picture: a cut.
    func uncover() {
        coverage = 0
        caption = nil
    }

    /// Ends the clip that is playing now. `play` returns; a held frame stays.
    func skip() {
        latch?.open()
    }

    /// Ends the clip that is playing, stops the player and takes the layer off the screen.
    func clear() {
        generation += 1
        latch?.open()
        latch = nil
        stopPlayer()
        showing = nil
        coverage = 0
        caption = nil
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

/// Draws the station clip over everything beneath it while one is showing, and the skin's colour
/// with a name while a screen opens on a signal still tuning. The clips are opaque station media
/// and play as they are.
struct StationClipLayer: View {
    let clips: StationClips
    @Environment(\.palette) private var palette

    var body: some View {
        if clips.showing != nil {
            ZStack {
                palette.ground.ignoresSafeArea()
                PlayerLayerView(player: clips.player)
                    .ignoresSafeArea()
            }
            .accessibilityHidden(true)
        } else if clips.coverage > 0 {
            ZStack {
                palette.ground.ignoresSafeArea()
                if let caption = clips.caption {
                    VStack(spacing: 16) {
                        Kicker("Tuning")
                        Text(caption)
                            .kjDisplay(KJType.headline, tracking: -0.055)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, KJLayout.inset)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}
