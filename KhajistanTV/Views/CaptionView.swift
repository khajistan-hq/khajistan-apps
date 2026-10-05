import SwiftUI

/// The one caption view, for live captions, programme subtitles and film tracks alike, drawn as
/// kj-captions.css draws the site's own plate: semibold system type at 2.7% of the frame's width,
/// line height 1.25, centred, one opaque plate around the block in the skin's caption colours
/// (black on yellow by day, yellow on #002800 in grove and on #6E003F in smut), no outline and no
/// shadow. Line length and line count are the cue's own: the live path cuts two lines of 42
/// characters, a prepared file arrives cut (frontend.md §7). Each line is laid out on its own
/// direction, so an Urdu, Persian or Arabic line reads right to left.
struct CaptionView: View {
    let text: String?
    let skin: Skin

    private static let size: CGFloat = 52   // 2.7% of 1920

    var body: some View {
        if let text, !text.isEmpty {
            VStack(spacing: Self.size * 0.25) {
                ForEach(Array(CaptionText.lines(text).enumerated()), id: \.offset) { line in
                    Text(line.element)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, CaptionText.isRightToLeft(line.element) ? .rightToLeft : .leftToRight)
                }
            }
            .font(.system(size: Self.size, weight: .semibold))
            .foregroundStyle(Color(hex: skin.captionTextHex))
            .padding(.horizontal, Self.size * 0.4)
            .padding(.vertical, Self.size * 0.12)
            .background(Color(hex: skin.captionPlateHex))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("caption")
        }
    }
}

/// The caption view's place on a player: centred at the bottom, and above the strip or panel
/// while one is up (`lift` is its height, zero while it is down), moving with it.
struct CaptionLayer: View {
    let text: String?
    let skin: Skin
    let lift: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CaptionView(text: text, skin: skin)
            .padding(.horizontal, 115)   // 6% of the frame, as the site's plate keeps
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, lift > 0 ? lift + 24 : 12)
            .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: lift)
            .allowsHitTesting(false)
    }
}

/// The caption control in a player strip: a kicker in the strip's own text colour, underlined while
/// on, and the inverted plate (band text on onBand) while focused, so it reads on the band in every
/// skin. It is focused only when the viewer moves to it; see the players.
struct StripChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        StripChip(label: configuration.label, isOn: isOn, isPressed: configuration.isPressed)
    }

    /// The control's face when it is not a button yet: the same look, unfocused.
    static func face<Label: View>(_ label: Label, isOn: Bool) -> some View {
        StripChip(label: label, isOn: isOn, isPressed: false)
    }
}

private struct StripChip<Label: View>: View {
    let label: Label
    let isOn: Bool
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.palette) private var palette

    var body: some View {
        let lit = isFocused || isPressed
        label
            .font(.system(size: KJType.kicker, weight: .black))
            .tracking(KJType.kicker * 0.13)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(lit ? palette.band : palette.onBand)
            .overlay(alignment: .bottom) {
                if isOn && !lit {
                    Rectangle().fill(palette.onBand).frame(height: 3).offset(y: 9)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(lit ? palette.onBand : Color.clear)
            .scaleEffect(isFocused ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
