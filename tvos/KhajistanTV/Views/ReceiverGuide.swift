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

/// Transmission's guide: a time grid, as a live TV app lays its schedule out (owner, 2026-11-17:
/// "it needs to be showing schedule on an hourly basis"). Channels run down the side, three hours
/// run across under half-hour marks, and each programme is a block as long as it airs. One block
/// is lit; Up and Down change the channel, Left and Right the programme (GuideGrid). It rises from
/// the bottom over the picture as the Receiver's does (owner, 2026-11-14).
struct TransmissionGuide: View {
    struct Row: Hashable {
        let number: Int
        let name: String
        let soundOnly: Bool
        /// The programme on air now, as the strip's headline names it: a run of short items is
        /// named for its show, and the guide's headline adds this to it.
        var onNow: String?
        /// What the channel airs from the half hour now is in, filled as the row comes into view.
        /// Empty while the month it needs is not held: the row reads Loading.
        var slots: [GuideSlot]
    }
    let rows: [Row]
    let current: Int
    let grid: GuideGrid
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let channelWidth: CGFloat = 380
    static let rowHeight: CGFloat = 80
    static let markHeight: CGFloat = 40

    private var keys: [GuideKey] {
        ReceiverGuide.window(count: rows.count, lit: grid.row).map { GuideKey(index: $0, id: "ch\(rows[$0].number)") }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Guide \u{00B7} Khajistan Transmission \u{00B7} \(Self.dayLabel(grid.windowStart)) \u{00B7} \(StationClock.tzLabel)")
                headline
                GeometryReader { geo in
                    let width = max(1, geo.size.width - Self.channelWidth)
                    VStack(alignment: .leading, spacing: 0) {
                        marks(width: width)
                        ForEach(keys, id: \.self) { key in
                            row(rows[key.index], lit: key.index == grid.row, width: width)
                        }
                    }
                }
                .frame(height: Self.markHeight + Self.rowHeight * CGFloat(keys.count))
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: .all)
            .animation(CardMotion.rows(reduceMotion: reduceMotion), value: keys)
            .animation(CardMotion.scroll(reduceMotion: reduceMotion), value: grid)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transmissionGuide")
        }
        .allowsHitTesting(false)
    }

    /// The lit programme in full, over the grid: a short programme's block is too narrow for its
    /// title. Its name, then the channel and its times; off air, when the channel is back.
    private var headline: some View {
        let row = rows.indices.contains(grid.row) ? rows[grid.row] : nil
        let slot = row.flatMap { r in grid.lit(in: r.slots).map { r.slots[$0] } }
        let channel = row?.name ?? ""
        // Nothing read at or after the lit moment (not read yet, or the month after not held): the
        // row is waiting for its reading, never off air.
        let loading = slot == nil
        var parts = [channel]
        if let slot, slot.isOffAir {
            parts.append(Self.back(slot, now: grid.now).map { "back at \($0)" } ?? "off air")
        } else if let slot {
            parts.append("\(Self.clock(slot.start))\u{2013}\(Self.clock(slot.end)) \(StationClock.tzLabel)")
            // A run is named for its show; the programme on air inside it is named too.
            if slot.grouped, slot.contains(grid.now), let onNow = row?.onNow, !onNow.isEmpty, onNow != slot.title {
                parts.append("now: \(onNow)")
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(loading ? "Loading" : (slot?.title ?? "Off air")).kjName(32).lineLimit(1)
            Text(parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")).kjSmall(faint: true).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guideHeadline")
    }

    /// When an off-air stretch ends, "03:10 PKT", with its day when that is not the day of `now`.
    /// A stretch that runs past the hours the guide reads ends where they end, so its return is the
    /// clock's own answer (StationClock.returnLabel), which knows the days beyond; nil when the
    /// schedule held has no return.
    static func back(_ slot: GuideSlot, now: Date) -> String? {
        guard slot.isOffAir else { return nil }
        if slot.openEnd { return slot.returnLabel }
        guard slot.end < now.addingTimeInterval(GuideGrid.horizon + GuideGrid.span) else { return nil }
        let at = "\(clock(slot.end)) \(StationClock.tzLabel)"
        return StationClock.stationNow(slot.end).iso == StationClock.stationNow(now).iso ? at : "\(at) on \(dayLabel(slot.end))"
    }

    /// Where a moment sits across the window, in points from the timeline's left edge.
    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(grid.windowStart) / GuideGrid.span) * width
    }

    /// The half-hour marks, each over the place its time falls.
    private func marks(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(grid.marks, id: \.self) { mark in
                Text(Self.clock(mark)).kjSmall(faint: true).monospacedDigit()
                    .offset(x: Self.channelWidth + x(mark, width: width) + 12)
            }
            nowMark(width: width)
        }
        .frame(height: Self.markHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Now, as a short accent bar under the time marks while it is in the window. Not a line
    /// through the rows: an off-air stretch has no plate, and a line crossed its words.
    @ViewBuilder
    private func nowMark(width: CGFloat) -> some View {
        let at = x(grid.now, width: width)
        if at >= 0, at <= width {
            Rectangle().fill(palette.accent)
                .frame(width: 4, height: 12)
                .offset(x: Self.channelWidth + at - 2, y: Self.markHeight - 12)
                .accessibilityHidden(true)
        }
    }

    private func row(_ row: Row, lit: Bool, width: CGFloat) -> some View {
        let litSlot = lit ? grid.lit(in: row.slots) : nil
        let shown = row.slots.indices.filter { row.slots[$0].end > grid.windowStart && row.slots[$0].start < grid.windowEnd }
        return HStack(spacing: 0) {
            // LIVE marks the channel tuned, while something is on it.
            let onNow = row.slots.first { $0.contains(grid.now) }.map { !$0.isOffAir } ?? false
            ChannelCell(number: row.number, name: row.name, soundOnly: row.soundOnly,
                        live: row.number == current && onNow, lit: lit, plate: lit && litSlot == nil)
                .frame(width: Self.channelWidth, alignment: .leading)
            ZStack(alignment: .topLeading) {
                if shown.isEmpty {
                    Text("Loading").kjSmall(faint: true).padding(.horizontal, 14)
                        .frame(height: Self.rowHeight - 8, alignment: .leading)
                }
                // Keyed by start, so a block keeps its place and its text when the rows are read again.
                ForEach(shown.map { (index: $0, slot: row.slots[$0]) }, id: \.slot.start) { item in
                    let index = item.index
                    let slot = item.slot
                    let left = max(0, x(slot.start, width: width))
                    let right = min(width, x(slot.end, width: width))
                    let lit = index == litSlot
                    // A lit block is never narrower than its plate can be seen.
                    GuideBlock(slot: slot, lit: lit, opensBefore: slot.start < grid.windowStart, now: grid.now)
                        .frame(width: max(lit ? 24 : 0, right - left - 6), height: Self.rowHeight - 8, alignment: .leading)
                        .offset(x: left)
                        .accessibilityIdentifier("guide-ch\(row.number)-\(index)")
                }
            }
            .frame(width: width, height: Self.rowHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: Self.rowHeight)
    }

    /// "12:30", in station time.
    static func clock(_ date: Date) -> String {
        StationClock.clockLabel(StationClock.stationNow(date).minutes)
    }

    /// "Monday 17 November", the station day the window starts on.
    static func dayLabel(_ date: Date) -> String {
        let iso = StationClock.stationNow(date).iso
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: StationClock.utcOffsetMinutes * 60) ?? .gmt
        guard let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return iso }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_GB")
        format.dateFormat = "EEEE d MMMM"
        return format.string(from: day)
    }
}

/// A channel on the guide's side: its number, its mark and its name, LIVE on the one tuned.
private struct ChannelCell: View {
    let number: Int
    let name: String
    let soundOnly: Bool
    let live: Bool
    let lit: Bool
    /// The lit row whose time holds nothing to light: the cell takes the plate itself.
    let plate: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let look = plate ? palette.onFocusPlate : palette
        HStack(spacing: 16) {
            Text("\(number)").kjKicker().monospacedDigit().frame(width: 44, alignment: .trailing)
            MediumMark(medium: soundOnly ? "radio" : "tv", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.short(name, number: number)).kjName(26).lineLimit(1)
                if live { Kicker("\u{25CF} Live") }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: TransmissionGuide.rowHeight - 8)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .background(plate ? palette.focusPlate : palette.focusPlate.opacity(0))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-ch\(number)")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// "Channel 5 · Mehfil" reads "Mehfil" beside its number.
    static func short(_ name: String, number: Int) -> String {
        let prefix = "Channel \(number) \u{00B7} "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }
}

/// One programme in the grid, or a stretch off air: its title and its times. The lit block takes
/// the focus plate, a programme the lift plate, off air no plate at all.
private struct GuideBlock: View {
    let slot: GuideSlot
    let lit: Bool
    /// The programme began before the window's left edge.
    let opensBefore: Bool
    let now: Date
    @Environment(\.palette) private var palette

    var body: some View {
        let look = lit ? palette.onFocusPlate : palette
        // Off air reads when the channel is back, not a running time.
        let times = slot.isOffAir
            ? TransmissionGuide.back(slot, now: now).map { "back at \($0)" } ?? ""
            : "\(TransmissionGuide.clock(slot.start))\u{2013}\(TransmissionGuide.clock(slot.end))"
        VStack(alignment: .leading, spacing: 4) {
            Text(slot.title ?? "Off air").kjName(24).lineLimit(1)
                .foregroundStyle(slot.isOffAir && !lit ? look.faint : look.ink)
            Text(opensBefore && !slot.isOffAir ? "\u{2039} \(times)" : times).kjSmall(faint: true).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.palette, look)
        // The plate alone, without the 1.03 lift a row takes: a block can be most of the screen
        // wide, and lifted it ran past its own edge.
        .background(lit ? palette.focusPlate : (slot.isOffAir ? palette.lift.opacity(0) : palette.lift))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot.isOffAir ? (times.isEmpty ? "Off air" : "Off air, \(times)") : "\(slot.title ?? ""), \(times) \(StationClock.tzLabel)")
        .accessibilityAddTraits(lit ? .isSelected : [])
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
            let line = [channel.place, broadcaster].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
            if !line.isEmpty { Text(line).kjBody().multilineTextAlignment(.center) }
            // The kicker above already says "Now playing"; the line is the song alone.
            Text(song.isEmpty ? NowPlaying.unavailable : song)
                .kjSmall(faint: song.isEmpty).multilineTextAlignment(.center)
        }
        .padding(.horizontal, KJLayout.inset)
    }
}
