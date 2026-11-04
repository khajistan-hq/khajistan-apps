import SwiftUI

/// The Receiver's guide, as a live TV app lays one (YouTube TV's guide): every channel of the shelf
/// the viewer came from as a row, its number, its medium's mark on a plate, the name and the place,
/// and LIVE on the one playing. It opens over the left of the picture, which plays on beside it.
/// The remote lights a row (the player's surface keeps focus, as it does for Captions and Like);
/// Select tunes it behind the pigeon.
struct ReceiverGuide: View {
    let list: [Channel]
    let current: Channel
    let lit: Int
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Guide")
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(ReceiverRules.mediumLabel(current.mediaType)).kjName(38)
                    Text("\(list.count)").kjSmall(faint: true)
                }
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        // Not lazy: the lit row must exist for the first scroll, and a shelf holds
                        // tens of channels, not thousands.
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, channel in
                                GuideRow(number: index + 1, channel: channel, live: channel.id == current.id, lit: index == lit)
                                    .id(index)
                                Hairline()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollDisabled(true)
                    .onAppear { proxy.scrollTo(lit, anchor: .center) }
                    .onChange(of: lit) { withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(lit, anchor: .center) } }
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 56)
            .frame(width: 900, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receiverGuide")
    }
}

/// One channel in the guide. The lit row takes the focus plate and its text the plate's colours.
private struct GuideRow: View {
    let number: Int
    let channel: Channel
    let live: Bool
    let lit: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let look = lit ? palette.onFocusPlate : palette
        HStack(spacing: 22) {
            Text("\(number)").kjKicker().monospacedDigit().frame(width: 60, alignment: .trailing)
            MediumMark(medium: channel.mediaType)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name).kjName(30).lineLimit(1)
                if !channel.place.isEmpty { Text(channel.place).kjSmall(faint: true).lineLimit(1) }
            }
            Spacer(minLength: 12)
            if live { Kicker("\u{25CF} Live").fixedSize() }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .background(lit ? palette.focusPlate : .clear)
        .scaleEffect(lit ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-\(channel.id)")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// A medium's mark on a plate: ink, with the glyph in the ground's colour, so on a focus plate
/// (whose palette re-skins) it inverts with the rest of the card.
struct MediumMark: View {
    let medium: String
    var size: CGFloat = 52
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: Self.symbol(medium))
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(palette.ground)
            .frame(width: size, height: size)
            .background(palette.ink)
            .accessibilityHidden(true)
    }

    static func symbol(_ medium: String) -> String {
        switch medium.lowercased() {
        case "tv": return "tv"
        case "radio": return "radio"
        case "camera": return "video"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Radio's Now Playing, centred on the ground while the station plays: the mark, NOW PLAYING, the
/// station's name large, and where it broadcasts from. The dancer moves it aside while he dances.
struct RadioNowPlaying: View {
    let channel: Channel

    var body: some View {
        VStack(spacing: 20) {
            MediumMark(medium: "radio", size: 112)
            Kicker("\u{25CF} Now playing \u{00B7} Live radio")
            Text(channel.name)
                .kjDisplay()
                .multilineTextAlignment(.center)
            let broadcaster = channel.broadcaster == channel.name ? nil : channel.broadcaster
            let line = [channel.place, broadcaster].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
            if !line.isEmpty { Text(line).kjBody().multilineTextAlignment(.center) }
        }
        .padding(.horizontal, KJLayout.inset)
    }
}
