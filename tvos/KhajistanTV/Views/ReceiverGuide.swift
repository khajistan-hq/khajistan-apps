import SwiftUI

/// The Receiver's guide, laid out as Transmission's is (owner, 2026-11-28: "design it the same
/// way as transmission"): the whole screen in the house palette, the picture playing on in a small
/// window at top left (the player's own picture, moved there by ReceiverPlayerView: this view only
/// keeps its place), the lit channel described beside it, and under them a row of plates per
/// channel of the shelf the viewer came from. A live channel has no schedule, so where Transmission
/// has its time grid each row carries the channel's place and language.
/// The remote lights a row (the player's surface keeps focus, as it does for Captions and Like);
/// Select tunes it behind the pigeon; Left and Right turn the region.
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

    /// The channels on screen at once, as on Transmission's guide.
    static let rowCount = TransmissionGuide.rowCount
    /// The channel's plate, wider than Transmission's: the row has no time grid to make room for.
    static let channelShare: CGFloat = 0.55

    /// Where the picture window sits: the same place as on Transmission's guide.
    static func pictureRect(in size: CGSize) -> CGRect { TransmissionGuide.pictureRect(in: size) }

    /// Keyed by channel, so a press slides the rows along as a list scrolls.
    private var keys: [GuideKey] {
        Self.window(count: list.count, lit: lit, rows: Self.rowCount).map { GuideKey(index: $0, id: list[$0].id) }
    }

    var body: some View {
        // The local times read the clock: drawn again on the minute, as the strip's are.
        TimelineView(.everyMinute) { context in
            guide(now: context.date)
        }
        .background(palette.ground)
        .ignoresSafeArea()
        // The guide itself carries the name, so a test can read where it sits.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receiverGuide")
        .allowsHitTesting(false)
    }

    private func guide(now: Date) -> some View {
        GeometryReader { geo in
            let picture = Self.pictureRect(in: geo.size)
            let width = max(1, geo.size.width - 2 * picture.minX)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 40) {
                    // The picture's place. The player draws its own layer here.
                    Color.clear.frame(width: picture.width, height: picture.height).accessibilityHidden(true)
                    panel(now: now)
                }
                .frame(height: picture.height)
                .padding(.bottom, 12)
                header(width: width)
                // Only the rows that fit, around the lit one: a region holds up to ~500 channels,
                // and drawing them all on every press made the guide slow (owner, 2026-11-04).
                // The rows' space is always seven rows high, so a region turn into, out of or across
                // an empty region says Loading or "No …" inside it and nothing jumps.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        let channel = list[key.index]
                        ReceiverGuideRow(number: key.index + 1, channel: channel,
                                         live: key.id == current.id, lit: key.index == lit,
                                         channelWidth: width * Self.channelShare, id: key.id, now: now)
                    }
                }
                .frame(width: width, height: CGFloat(Self.rowCount) * TransmissionGuide.rowHeight, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if loading {
                        Text("Loading").kjSmall().padding(.horizontal, 14).padding(.top, 20)
                    } else if list.isEmpty {
                        Text("No \(ReceiverRules.mediumLabel(medium).lowercased()) in \(title).").kjSmall()
                            .padding(.horizontal, 14).padding(.top, 20)
                    }
                }
                // A region turn empties the list until the next region loads, so it cuts rather
                // than running the rows out and back (Bugbot on PR 79).
                .transaction(value: loading) { $0.animation = nil }
            }
            .padding(.horizontal, picture.minX)
            .padding(.top, picture.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(CardMotion.rows(reduceMotion: reduceMotion), value: keys)
            .animation(CardMotion.scroll(reduceMotion: reduceMotion), value: lit)
        }
    }

    /// Beside the picture: the Receiver and the medium, then the lit channel's name, its number,
    /// place and language, and its description.
    private func panel(now: Date) -> some View {
        let channel = list.indices.contains(lit) && !loading ? list[lit] : nil
        let facts = channel.map { c in
            ["Channel \(lit + 1)", c.placeAndTime(at: now), c.genres?.first, c.id == current.id ? "\u{25CF} Live" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        } ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            Kicker("Khajistan Receiver \u{00B7} " + ReceiverRules.mediumLabel(medium))
            VStack(alignment: .leading, spacing: 8) {
                Text(channel?.name ?? (loading ? "Loading" : title)).kjName(52).lineLimit(2).minimumScaleFactor(0.7)
                if !facts.isEmpty { Text(facts).kjSmall().lineLimit(2) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("guideHeadline")
            if let about = channel?.description, !about.isEmpty {
                Text(about).kjBody().lineLimit(4)
                    .accessibilityIdentifier("guideChannelLine")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The band over the rows: the region (with its turn marks) and its count, then what the
    /// rows' second plate carries.
    private func header(width: CGFloat) -> some View {
        let look = palette.onBandPlate
        let gap = TransmissionGuide.gap
        return HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(turns ? "\u{2039} " + title + " \u{203A}" : title).kjKicker(look.ink).lineLimit(1)
                    .accessibilityIdentifier("guideRegion")
                if !loading { Text("\(list.count)").kjKicker(look.ink).monospacedDigit() }
            }
            .padding(.horizontal, 14)
            .frame(width: width * Self.channelShare - gap, height: TransmissionGuide.markHeight - gap, alignment: .leading)
            .background(palette.band, ignoresSafeAreaEdges: [])
            .padding(.trailing, gap)
            Text("Place \u{00B7} Language").kjKicker(look.ink).lineLimit(1)
                .padding(.horizontal, 14)
                .frame(width: width * (1 - Self.channelShare) - gap, height: TransmissionGuide.markHeight - gap, alignment: .leading)
                .background(palette.band, ignoresSafeAreaEdges: [])
                .padding(.trailing, gap)
        }
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .frame(height: TransmissionGuide.markHeight, alignment: .top)
    }

    /// The rows on screen: `rows` of them with the lit one in the middle, held against the ends.
    static func window(count: Int, lit: Int, rows: Int = 5) -> [Int] {
        guard count > 0 else { return [] }
        let start = max(0, min(lit - rows / 2, count - rows))
        return Array(start..<min(count, start + rows))
    }
}

/// Transmission's guide: the whole screen, laid out as a television guide channel was in the
/// early 2000s (owner, 2026-11-24: "Full screen with smaller video icon", "in the khajistan
/// palate"). The picture plays on in a small window at top left (the player's own picture, moved
/// there by TransmissionPlayerView: this view only keeps its place), the lit cell is described
/// beside it, and under them runs the time grid of 2026-11-17: a header of three half hours, a
/// row per channel, a cell for the channel and a block per programme as long as it airs.
/// Every cell is a filled plate with a gap round it; nothing is outlined. One cell is lit; Up and
/// Down change the channel, Left and Right walk the channel's cell and its programmes (GuideGrid).
struct TransmissionGuide: View {
    struct Row: Hashable {
        let number: Int
        let name: String
        /// The channel's own line from the schedule (ChannelInfo.line).
        let line: String?
        let soundOnly: Bool
        /// The programme on air now, as the strip's headline names it: a run of short items is
        /// named for its show, and its block adds this to it.
        var onNow: String?
        /// What the channel airs from the half hour now is in, filled as the row comes into view.
        /// Empty while the month it needs is not held: the row reads Loading.
        var slots: [GuideSlot]
    }
    let rows: [Row]
    let current: Int
    let grid: GuideGrid
    /// The lit programme's kind line from the schedule ("Qawwali · Pakistan · 1984"), if any.
    let kind: String?
    /// The kicker over the panel: the station and its counts (TransmissionStore.stationLine).
    var station: String = "Khajistan Transmission"
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room for a name such as "Old TV — Maghreb" on one line, and a long one on two.
    static let channelWidth = CGFloat(GuideGrid.channelPoints)
    /// The narrowest a cell is drawn: its title's first word and its times, never cut short.
    /// Shorter programmes are folded into a neighbour, "+N" (GuideGrid.cells).
    static let cellWidth = CGFloat(GuideGrid.cellPoints)
    static let rowHeight: CGFloat = 80
    static let markHeight: CGFloat = 40
    /// The space between two plates, which is all that separates them.
    static let gap: CGFloat = 4
    /// The channels on screen at once, under the top band.
    static let rowCount = 7
    /// The top band's share of the screen's height: the picture window and the lit cell's words.
    static let bandShare: CGFloat = 0.38

    /// Where the picture window sits on a screen of `size`, in the screen's own points: 16:9, as
    /// tall as the top band under its margin. The player moves its picture to exactly this.
    static func pictureRect(in size: CGSize) -> CGRect {
        let top: CGFloat = 40
        let height = max(1, size.height * bandShare - top)
        return CGRect(x: KJLayout.inset, y: top, width: height * 16 / 9, height: height)
    }

    private var keys: [GuideKey] {
        ReceiverGuide.window(count: rows.count, lit: grid.row, rows: Self.rowCount).map { GuideKey(index: $0, id: "ch\(rows[$0].number)") }
    }

    var body: some View {
        GeometryReader { geo in
            let picture = Self.pictureRect(in: geo.size)
            let width = max(1, geo.size.width - 2 * picture.minX - Self.channelWidth)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 40) {
                    // The picture's place. The player draws its own layer here, black behind a
                    // picture and the ground behind a dancer or an off-air card.
                    Color.clear.frame(width: picture.width, height: picture.height).accessibilityHidden(true)
                    panel
                }
                .frame(height: picture.height)
                .padding(.bottom, 12)
                marks(width: width)
                ForEach(keys, id: \.self) { key in
                    row(rows[key.index], lit: key.index == grid.row, width: width)
                }
            }
            .padding(.horizontal, picture.minX)
            .padding(.top, picture.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(CardMotion.rows(reduceMotion: reduceMotion), value: keys)
            .animation(CardMotion.scroll(reduceMotion: reduceMotion), value: grid)
        }
        .background(palette.ground)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transmissionGuide")
        .allowsHitTesting(false)
    }

    /// Beside the picture: the station and the clock, then the lit cell. A programme reads its
    /// title, then its times, what kind of thing it is and its channel; a channel's own cell reads
    /// "Channel 5 · Mehfil". Under either, the channel's line from the schedule.
    private var panel: some View {
        let row = rows.indices.contains(grid.row) ? rows[grid.row] : nil
        let slot = grid.onChannel ? nil : row.flatMap { r in grid.lit(in: r.slots).map { r.slots[$0] } }
        let channel = row.map { "Channel \($0.number) \u{00B7} \(ChannelCell.short($0.name, number: $0.number))" } ?? ""
        var title = channel
        var facts: [String?] = []
        if let slot, slot.isOffAir {
            title = "Off air"
            facts = [Self.back(slot, now: grid.now).map { "back at \($0)" }, channel]
        } else if let slot {
            title = slot.title ?? ""
            let onAir = slot.grouped && slot.contains(grid.now) ? row?.onNow : nil
            facts = ["\(Self.clock(slot.start))\u{2013}\(Self.clock(slot.end)) \(StationClock.tzLabel)",
                     slot.grouped ? slot.itemsLabel : nil,
                     onAir.flatMap { $0.isEmpty || $0 == slot.title ? nil : "now \($0)" },
                     kind, row.map { "Channel \($0.number)" }]
        } else if !grid.onChannel {
            // Nothing read at or after the lit moment (not read yet, or the month after not held):
            // the row is waiting for its reading, never off air.
            title = "Loading"
            facts = [channel]
        }
        let line = facts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(station).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 16)
                Kicker("\(Self.clock(grid.now)) \(StationClock.tzLabel)").monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).kjName(52).lineLimit(2).minimumScaleFactor(0.7)
                // Full-strength ink: the faint tier read as grey by day (owner, 2026-11-24).
                if !line.isEmpty { Text(line).kjSmall().lineLimit(2) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("guideHeadline")
            if let about = row?.line, !about.isEmpty {
                Text(about).kjBody().lineLimit(4)
                    .accessibilityIdentifier("guideChannelLine")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// When an off-air stretch ends, with its day when that is not today (GuideSlot.back).
    static func back(_ slot: GuideSlot, now: Date) -> String? { slot.back(now: now) }

    /// Where a moment sits across the window, in points from the timeline's left edge.
    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(grid.windowStart) / GuideGrid.span) * width
    }

    /// The header: the station day over the channels, then a band plate per half hour.
    private func marks(width: CGFloat) -> some View {
        let look = palette.onBandPlate
        let column = width / CGFloat(max(1, grid.marks.count))
        return HStack(spacing: 0) {
            Text(Self.dayLabel(grid.windowStart)).kjSmall().lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(width: Self.channelWidth - Self.gap, height: Self.markHeight - Self.gap, alignment: .leading)
                .background(palette.band, ignoresSafeAreaEdges: [])
                .padding(.trailing, Self.gap)
            ForEach(grid.marks, id: \.self) { mark in
                Text(Self.clock(mark)).kjKicker(look.ink).monospacedDigit()
                    .padding(.horizontal, 14)
                    .frame(width: column - Self.gap, height: Self.markHeight - Self.gap, alignment: .leading)
                    .background(palette.band, ignoresSafeAreaEdges: [])
                    .padding(.trailing, Self.gap)
            }
        }
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .frame(height: Self.markHeight, alignment: .top)
        .accessibilityHidden(true)
    }

    private func row(_ row: Row, lit: Bool, width: CGFloat) -> some View {
        let litSlot = lit && !grid.onChannel ? grid.lit(in: row.slots) : nil
        // The gap is taken off each block's width when drawn, so the fold counts it too.
        let cells = grid.cells(row.slots, minimum: Double((Self.cellWidth + Self.gap) / width) * GuideGrid.span)
        return HStack(spacing: 0) {
            // LIVE marks the channel tuned, while something is on it.
            let onNow = row.slots.first { $0.contains(grid.now) }.map { !$0.isOffAir } ?? false
            // The channel's cell is the lit one when Left reached it, or when the row's time holds
            // nothing to light.
            ChannelCell(number: row.number, name: row.name, soundOnly: row.soundOnly,
                        live: row.number == current && onNow, plate: lit && litSlot == nil)
                .frame(width: Self.channelWidth - Self.gap, alignment: .leading)
                .padding(.trailing, Self.gap)
            ZStack(alignment: .topLeading) {
                if cells.isEmpty {
                    Text("Loading").kjSmall().padding(.horizontal, 14)
                        .frame(height: Self.rowHeight - Self.gap, alignment: .leading)
                }
                // Keyed by start, so a block keeps its place and its text when the rows are read again.
                ForEach(cells, id: \.start) { cell in
                    let left = max(0, x(cell.start, width: width))
                    let right = min(width, x(cell.end, width: width))
                    let lit = litSlot.map(cell.holds) ?? false
                    // The lit cell names the lit programme, so Right inside a fold reads each in turn.
                    // An off-air stretch folded into a programme's cell does not name the cell "Off air".
                    let litNames = litSlot.map { !row.slots[$0].isOffAir || row.slots[cell.lead].isOffAir } ?? false
                    let named = lit && litNames ? litSlot ?? cell.lead : cell.lead
                    GuideBlock(slot: row.slots[named], more: cell.more(naming: named, in: row.slots),
                               start: cell.start, end: cell.end, lit: lit,
                               windowStart: grid.windowStart, now: grid.now, onNow: row.onNow)
                        .frame(width: max(0, right - left - Self.gap), height: Self.rowHeight - Self.gap, alignment: .leading)
                        .offset(x: left)
                        .accessibilityIdentifier("guide-ch\(row.number)-\(cell.first)")
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
    static func dayLabel(_ date: Date) -> String { StationClock.dayName(date) }
}

/// A channel's own cell at the left of its row, on a band plate: its number, its mark and its
/// name, LIVE on the one tuned. Lit, it takes the lit plate (Palette.litAmongBands).
private struct ChannelCell: View {
    let number: Int
    let name: String
    let soundOnly: Bool
    let live: Bool
    /// The cell itself is the lit one, not a programme on its row.
    let plate: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let look = plate ? palette.litAmongBands : palette.onBandPlate
        HStack(spacing: 16) {
            Text("\(number)").kjKicker().monospacedDigit().frame(width: 44, alignment: .trailing)
            MediumMark(medium: soundOnly ? "radio" : "tv", size: 40)
            // The name whole at the largest size that fits, on up to two lines, beside LIVE too:
            // "National Iranian Radio and Television" (Fable, round 9). Only when no size fits is it
            // cut, and the cell says so ("cut"), which the UI tests refuse.
            ViewThatFits(in: .vertical) {
                nameStack(size: 26)
                nameStack(size: 22)
                nameStack(size: 19)
                nameStack(size: 16)
                nameStack(size: 16, cut: true).accessibilityValue("cut")
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: TransmissionGuide.rowHeight - TransmissionGuide.gap)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .background(look.ground, ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-ch\(number)")
        .accessibilityAddTraits(plate ? .isSelected : [])
    }

    /// The name wrapped at `size`, as tall as it needs, or cut at two lines.
    private func nameStack(size: CGFloat, cut: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.short(name, number: number)).kjName(size)
                .lineLimit(cut ? 2 : nil)
                .fixedSize(horizontal: false, vertical: !cut)
            if live { Kicker("\u{25CF} Live") }
        }
    }

    /// "Channel 5 · Mehfil" reads "Mehfil" beside its number.
    static func short(_ name: String, number: Int) -> String {
        let prefix = "Channel \(number) \u{00B7} "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }
}

/// One programme in the grid, or a stretch off air: its title and its times. The lit block takes
/// the focus plate, a programme the lift plate, off air no plate at all. A run of short
/// programmes reads its show, then how many it holds and the one on air.
private struct GuideBlock: View {
    /// The slot the cell is named for: the lit one, or the one that takes most of the cell.
    let slot: GuideSlot
    /// The other programmes folded into the cell.
    let more: Int
    /// The cell's extent, which is the slot's own unless others are folded in.
    let start: Date
    let end: Date
    let lit: Bool
    /// The window's left edge: times that begin before it are marked "‹".
    let windowStart: Date
    let now: Date
    /// The programme on air on this channel, for a run that is airing.
    let onNow: String?
    @Environment(\.palette) private var palette

    var body: some View {
        let look = lit ? palette.onFocusPlate : palette
        // A lone off-air stretch reads when the channel is back. Otherwise the times: the lit
        // programme's own, or the whole cell's when others are folded in.
        let (from, to) = lit || more == 0 ? (slot.start, slot.end) : (start, end)
        let times = slot.isOffAir && more == 0
            ? slot.back(now: now, short: true).map { "back at \($0)" } ?? ""
            : "\(TransmissionGuide.clock(from))\u{2013}\(TransmissionGuide.clock(to))"
        // A run: "12 songs · now Jugni" under the show's name, in place of the times, which the
        // panel over the grid carries while the run is lit.
        let run = slot.grouped ? slot.runLabel(onNow: slot.contains(now) ? onNow : nil) : nil
        let under = run.map { String($0.dropFirst((slot.title ?? "").count + 3)) }
            ?? (from < windowStart && !(slot.isOffAir && more == 0) ? "\u{2039} \(times)" : times)
        VStack(alignment: .leading, spacing: 4) {
            // The others folded into the cell are said in words, and only where the title and
            // the words both fit whole; a bare "+1" told a viewer nothing (owner, 2026-11-24).
            ViewThatFits(in: .horizontal) {
                if more > 0 {
                    HStack(spacing: 10) {
                        Text(slot.title ?? "Off air").kjName(24).lineLimit(1).fixedSize()
                        Text("and \(more) more").kjSmall().lineLimit(1).fixedSize()
                    }
                }
                Text(slot.title ?? "Off air").kjName(24).lineLimit(1)
            }
            // Ink at full strength on every line: no dimmed tier in the grid (owner, 2026-11-24).
            Text(under).kjSmall().monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        // The plate alone, without the 1.03 lift a row takes: a block can be most of the screen
        // wide, and lifted it ran past its own edge.
        .background(lit ? palette.focusPlate : (slot.isOffAir ? palette.lift.opacity(0) : palette.lift), ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((slot.isOffAir ? (times.isEmpty ? "Off air" : "Off air, \(times)") : "\(slot.title ?? ""), \(times) \(StationClock.tzLabel)")
                            + (run.map { _ in ", \(under)" } ?? "")
                            + (more > 0 ? ", and \(more) more" : ""))
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// One channel in the Receiver's guide: its own plate (number, mark, name, LIVE on the one
/// playing) and a plate with its place and language, as Transmission's rows are plates with a gap
/// round them. The lit row takes the lit plate on its channel and the focus plate beside it.
private struct ReceiverGuideRow: View {
    let number: Int
    let channel: Channel
    let live: Bool
    let lit: Bool
    let channelWidth: CGFloat
    let id: String
    /// The minute the guide was drawn for, so the local time moves on with the clock.
    let now: Date
    @Environment(\.palette) private var palette

    var body: some View {
        let gap = TransmissionGuide.gap
        let height = TransmissionGuide.rowHeight - gap
        let cell = lit ? palette.litAmongBands : palette.onBandPlate
        let side = lit ? palette.onFocusPlate : palette
        // The place, its language and the time there (Channel.placeAndTime), as the strip reads it.
        let where_ = channel.placeAndTime(at: now)
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("\(number)").kjKicker().monospacedDigit().frame(width: 52, alignment: .trailing)
                MediumMark(medium: channel.mediaType, size: 40)
                Text(channel.name).kjName(26).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if live { Kicker("\u{25CF} Live").fixedSize() }
            }
            .padding(.horizontal, 12)
            .frame(width: channelWidth - gap, height: height, alignment: .leading)
            .environment(\.palette, cell)
            .foregroundStyle(cell.ink)
            .background(cell.ground, ignoresSafeAreaEdges: [])
            .padding(.trailing, gap)
            Text(where_).kjSmall().lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: height, alignment: .leading)
                .environment(\.palette, side)
                .foregroundStyle(side.ink)
                .background(lit ? palette.focusPlate : palette.lift, ignoresSafeAreaEdges: [])
                .padding(.trailing, gap)
        }
        .frame(height: TransmissionGuide.rowHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-\(id)")
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
