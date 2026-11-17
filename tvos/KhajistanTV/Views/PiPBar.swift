import SwiftUI

/// The picture in the corner window, as a band along the foot of the screen while the viewer
/// browses: what is playing, Full screen, Play/Pause and Close. The window itself cannot take the
/// remote's focus (only tvOS's own menu, behind the TV button, reaches it), so the bar is how the
/// window is worked from inside the app (owner, 2026-11-17: "hard to navigate into small pip window
/// and click it back up to full screen"). Full screen is lit as the window opens, so one press of
/// Select brings the picture back; Down reaches the bar from any page after that.
///
/// It stops short of the right-hand 40% of the screen, where tvOS puts the window by default, so
/// the window does not cover it.
struct PiPBar: View {
    let pip: PictureInPicture
    var focus: FocusState<Bool>.Binding
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "pip")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(palette.onBand.opacity(0.16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(pip.title).kjName(30).lineLimit(1)
                Text("Picture in picture \u{00B7} " + (pip.isPlaying ? "Playing" : "Paused")).kjSmall().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { pip.restore() } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: KJType.kicker, weight: .black))
                    .textCase(.uppercase)
            }
            .buttonStyle(OnBandStyle())
            .focused(focus)
            .accessibilityIdentifier("pipBarFullScreen")
            Button { pip.setPlaying(!pip.isPlaying) } label: {
                Image(systemName: pip.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .bold)).frame(width: 60)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel(pip.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("pipBarToggle")
            Button { pip.close() } label: {
                Label("Close", systemImage: "xmark")
                    .font(.system(size: KJType.kicker, weight: .black))
                    .textCase(.uppercase)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel("Close picture in picture")
            .accessibilityIdentifier("pipBarClose")
        }
        .foregroundStyle(palette.onBand)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(palette.band)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KJLayout.inset)
        .padding(.bottom, 24)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pipBar")
    }
}
