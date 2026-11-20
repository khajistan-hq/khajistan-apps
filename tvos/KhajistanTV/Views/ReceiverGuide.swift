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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows' height when last drawn with a list, held while the next region loads.
    @State private var rowsHeight: CGFloat = 0

    /// Keyed by channel, so a press slides the rows along as a list scrolls.
    private var keys: [GuideKey] {
        Self.window(count: list.count, lit: lit).map { GuideKey(index: $0, id: list[$0].id) }
    }

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
                // Only the rows that fit, around the lit one: a region holds up to ~500 channels,
                // and drawing them all on every press made the guide slow (owner, 2026-11-04).
                // The rows' space keeps the height it last had with rows in it while a region turn
                // loads, and on a region with none, and says Loading or "No …" inside it. So a
                // turn into, out of or across an empty region does not drop the panel to its
                // header and jump back.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 0) {
                            GuideRow(number: key.index + 1, name: list[key.index].name, place: list[key.index].place,
                                     medium: list[key.index].mediaType, id: key.id,
                                     live: key.id == current.id, lit: key.index == lit)
                            Hairline()
                        }
                    }
                }
                // Full width, or an empty slot is 0 wide and its line is laid out in no width (Fable,
                // round 5 on PR 88). At least a line high, for a guide that opens on an empty region.
                .frame(maxWidth: .infinity, minHeight: loading || list.isEmpty ? max(rowsHeight, 44) : nil, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if loading {
                        Text("Loading").kjSmall(faint: true)
                    } else if list.isEmpty {
                        Text("No \(ReceiverRules.mediumLabel(medium).lowercased()) in \(title).").kjSmall(faint: true)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if !loading, !list.isEmpty { rowsHeight = height }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            // A region turn empties the list until the next region loads, so it cuts rather
            // than running the rows out to an empty panel and back (Bugbot on PR 79). Inner to
            // the animations below, so it wins when `loading` changes.
            .transaction(value: loading) { $0.animation = nil }
            // On the whole panel, so its ground grows and shrinks with the rows it holds.
            .animation(CardMotion.rows(reduceMotion: reduceMotion), value: keys)
            .animation(CardMotion.scroll(reduceMotion: reduceMotion), value: lit)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var keys: [GuideKey] {
        ReceiverGuide.window(count: rows.count, lit: lit).map { GuideKey(index: $0, id: "ch\(rows[$0].number)") }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Guide \u{00B7} Khajistan Transmission")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        let row = rows[key.index]
                        VStack(alignment: .leading, spacing: 0) {
                            GuideRow(number: row.number, name: row.name, place: row.now,
                                     medium: row.soundOnly ? "radio" : "tv", id: key.id,
                                     live: row.number == current, lit: key.index == lit)
                            Hairline()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            // On the whole panel, so its ground grows and shrinks with the rows it holds.
            .animation(CardMotion.rows(reduceMotion: reduceMotion), value: keys)
            .animation(CardMotion.scroll(reduceMotion: reduceMotion), value: lit)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transmissionGuide")
        }
        .allowsHitTesting(false)
    }
}

/// A guide row's identity: the channel, and where it stands in the list.
struct GuideKey: Hashable {
    let index: Int
    let id: String
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // As tvOS moves focus: the row left lets go of its plate and the row reached takes it
        // while the rows scroll; no plate travels between rows. Lifted as any focused control
        // is (DESIGN: focus is the plate at 1.03), and not under Reduce Motion.
        .background(lit ? palette.focusPlate : palette.focusPlate.opacity(0))
        .scaleEffect(lit && !reduceMotion ? 1.03 : 1)
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
            // The place and the time there, read again on the minute.
            if !channel.placeAndTime().isEmpty || !(broadcaster ?? "").isEmpty {
                TimelineView(.everyMinute) { context in
                    Text([channel.placeAndTime(at: context.date), broadcaster].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " \u{00B7} ")).kjBody().multilineTextAlignment(.center)
                }
            }
            // The kicker above already says "Now playing"; the line is the song alone.
            Text(song.isEmpty ? NowPlaying.unavailable : song)
                .kjSmall(faint: song.isEmpty).multilineTextAlignment(.center)
        }
        .padding(.horizontal, KJLayout.inset)
    }
}
