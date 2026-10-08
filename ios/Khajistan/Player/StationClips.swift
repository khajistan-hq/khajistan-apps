import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The channel change on the phone and iPad: the website receiver's tuning pigeon. The skin's
/// ground comes up over the picture and the grooming pigeon loops in its middle while the new
/// signal tunes, then both lift off as the picture plays. It is the bird the site shows over its
/// player while a channel connects or buffers (archive/open-frequencies.html `.tuning-pigeon`,
/// assets/home-pigeon/grooming.webp, owner 2026-10-04), at the site's size: a quarter of the
/// width, 96 to 200 points. The flying pigeon is the Apple TV's alone (owner, 2026-10-07).
///
/// The loop is a 300x276 HEVC movie with alpha (ios/scripts/make-tuning-pigeon.sh), played by
/// AVPlayerLooper, so the decoder draws it; the WebP's 208 frames decoded and held would be
/// ~69 MB. Reduce Motion holds it on one frame.
@MainActor @Observable
final class StationClips {
    /// No flight on the phone; kept so callers that skip a flight in progress still compile.
    var showing: Bool { false }
    /// How much of the ground covers the picture, 0 to 1. Animated by `cover` and `uncover`.
    private(set) var coverage: Double = 0
    /// The channel on its way, for VoiceOver; the site prints no words beside the bird.
    private(set) var caption: String?
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false

    let player = AVQueuePlayer()
    @ObservationIgnored private var looper: AVPlayerLooper?

    init() {
        // The bird must never take the audio session from the signal under it.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        if let url = Bundle.main.url(forResource: "tuning-pigeon", withExtension: "mov") {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }

    /// Brings the ground and the pigeon up over the picture. `animated: false` puts them there at
    /// once, for a screen that opens on a signal still tuning.
    func cover(caption: String?, animated: Bool = true) {
        if animated {
            withAnimation(.easeIn(duration: 0.3)) { coverage = 1; self.caption = caption }
        } else {
            coverage = 1
            self.caption = caption
        }
        startLoop()
    }

    /// Lifts the ground and the pigeon off the picture.
    func uncover() {
        withAnimation(.easeInOut(duration: 0.5)) { coverage = 0; caption = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if coverage == 0 { player.pause() }
        }
    }

    /// The change itself: the ground and the pigeon come up and the caller tunes at once, behind
    /// them, so the wait is the signal's and never the bird's. They stay until the caller uncovers.
    func flyThrough(caption: String?, covered: @escaping @MainActor () -> Void = {}) async {
        // At once, as the site shows .tuning-pigeon: a fade-in run while the new stream starts
        // lagged to a second on the main thread, and the half-up layer read the bird as green.
        cover(caption: caption, animated: false)
        covered()
    }

    /// Nothing is in flight on the phone to cut short.
    func skip() {}

    /// Takes the ground and the pigeon off the screen at once.
    func clear() {
        player.pause()
        caption = nil
        coverage = 0
    }

    private func startLoop() {
        if UIAccessibility.isReduceMotionEnabled {
            player.pause()
        } else if player.rate == 0 {
            player.play()
        }
    }
}

/// The ground and the pigeon, over everything beneath them.
struct StationClipLayer: View {
    let clips: StationClips
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let side = min(max(proxy.size.width * 0.24, 96), 200)
            ZStack {
                palette.ground
                    .ignoresSafeArea()
                PlayerLayerView(player: clips.player, gravity: .resizeAspect)
                    .frame(width: side, height: side * 276 / 300)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(clips.coverage)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clips.caption.map { "Tuning \($0)" } ?? "")
        .accessibilityHidden(clips.coverage == 0)
    }
}
