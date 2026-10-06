import SwiftUI

/// The skin's colour with a channel's name on it, over the picture while a screen opens on a
/// signal still tuning, and for a film. It comes and goes with a cut. The channel change itself
/// is the pigeon over the live picture (PigeonOverlay); the website's wing wipe that this file
/// played until 2026-10-06 is retired from the apps (owner: the Transmission too, "do 2 as
/// recommended").
@MainActor @Observable
final class StationClips {
    /// Set after the sign-on, and kept for the life of the app.
    var signOnPlayed = false
    private(set) var coverage: Double = 0
    private(set) var caption: String?

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

    func clear() {
        coverage = 0
        caption = nil
    }
}

/// The skin's colour with a name, over everything beneath it, while it is up.
struct StationClipLayer: View {
    let clips: StationClips
    @Environment(\.palette) private var palette

    var body: some View {
        if clips.coverage > 0 {
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
        }
    }
}
