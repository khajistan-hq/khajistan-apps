import SwiftUI

/// The Receiver's guide, as a live TV app lays one (YouTube TV's guide): every channel of the shelf
/// the viewer came from as a row, its number, its medium's mark on a plate, the name and the place,
/// and LIVE on the one playing. It rises from the bottom over the picture, which plays on above it
/// (owner, 2026-11-14: "make the guide come from bottom up rather than from the left").
/// The remote lights a row (the player's surface keeps focus, as it does for Captions and Like);
/// Select tunes it behind the pigeon.
struct ReceiverGuide: View {
    let list: [Channel]
    let current: Channel
    let lit: Int
    let medium: String
    /// The region shown, and whether left and right reach others.
    let title: String
    let turns: Bool
    let loading: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Guide \u{00B7} " + ReceiverRules.mediumLabel(medium))
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(turns ? "\u{2039} " + title + " \u{203A}" : title).kjName(38)
                        .lineLimit(1)
                        .accessibilityIdentifier("guideRegion")
                    if !loading { Text("\(list.count)").kjSmall(faint: true) }
                }
                if loading {
                    Text("Loading").kjSmall(faint: true)
                } else if list.isEmpty {
                    Text("No \(ReceiverRules.mediumLabel(medium).lowercased()) in \(title).").kjSmall(faint: true)
                }
                // Only the rows that fit, around the lit one: a region holds up to ~500 channels,
                // and drawing them all on every press made the guide slow (owner, 2026-11-04).
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.window(count: list.count, lit: lit), id: \.self) { index in
                        GuideRow(number: index + 1, name: list[index].name, place: list[index].place,
                                 medium: list[index].mediaType, id: list[index].id,
                                 live: list[index].id == current.id, lit: index == lit)
                        Hairline()
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            // The panel itself carries the name, so a test can read where it sits.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("receiverGuide")
        }
        .allowsHitTesting(false)
    }

    /// The rows on screen: `rows` of them with the lit one in the middle, held against the ends.
    static func window(count: Int, lit: Int, rows: Int = 5) -> [Int] {
        guard count > 0 else { return [] }
        let start = max(0, min(lit - rows / 2, count - rows))
        return Array(start..<min(count, start + rows))
    }
}

/// Transmission's guide: every channel of the station, its number, its name and what the clock
/// has on it now, LIVE on the one tuned. It rises from the bottom over the picture as the
/// Receiver's does (owner, 2026-11-14), and the remote walks it the same way.
struct TransmissionGuide: View {
    struct Row: Hashable {
        let number: Int
        let name: String
        /// What is on now, or when the channel returns.
        let now: String
        let soundOnly: Bool
    }
    let rows: [Row]
    let current: Int
    let lit: Int
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Guide \u{00B7} Khajistan Transmission")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ReceiverGuide.window(count: rows.count, lit: lit), id: \.self) { index in
                        let row = rows[index]
                        GuideRow(number: row.number, name: row.name, place: row.now,
                                 medium: row.soundOnly ? "radio" : "tv", id: "ch\(row.number)",
                                 live: row.number == current, lit: index == lit)
                        Hairline()
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transmissionGuide")
        }
        .allowsHitTesting(false)
    }
}

/// One channel in a guide (the Receiver's or Transmission's). The lit row takes the focus plate
/// and its text the plate's colours.
struct GuideRow: View {
    let number: Int
    let name: String
    /// The line under the name: the place, or on Transmission what is on now.
    let place: String
    let medium: String
    let id: String
    let live: Bool
    let lit: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let look = lit ? palette.onFocusPlate : palette
        HStack(spacing: 22) {
            Text("\(number)").kjKicker().monospacedDigit().frame(width: 60, alignment: .trailing)
            MediumMark(medium: medium)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).kjName(30).lineLimit(1)
                if !place.isEmpty { Text(place).kjSmall(faint: true).lineLimit(1) }
            }
            Spacer(minLength: 12)
            if live { Kicker("\u{25CF} Live").fixedSize() }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .background(lit ? palette.focusPlate : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-\(id)")
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
    /// The song on air (NowPlaying), or "" while there is none.
    var song: String = ""

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
            // The kicker above already says "Now playing"; the line is the song alone.
            Text(song.isEmpty ? NowPlaying.unavailable : song)
                .kjSmall(faint: song.isEmpty).multilineTextAlignment(.center)
        }
        .padding(.horizontal, KJLayout.inset)
    }
}
