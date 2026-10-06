import SwiftUI

/// The strips after now on one channel, as the website's console bar and channel cards write
/// them: the start in Pakistan time, then the show. The first is the one up next and reads
/// larger, unless the list is what follows a strip named elsewhere. A strip whose show the schedule has lost keeps its
/// time, as on the site.
struct UpNextList: View {
    let title: String
    let strips: [ScheduleStrip]
    var emphasizesFirst = true

    var body: some View {
        if !strips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Kicker(title)
                ForEach(Array(strips.enumerated()), id: \.offset) { item in
                    row(item.element, first: emphasizesFirst && item.offset == 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("upNext")
        }
    }

    @ViewBuilder
    private func row(_ strip: ScheduleStrip, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            if first {
                Text(strip.startLabel).kjName().monospacedDigit()
                Text(strip.show?.name ?? "").kjName().lineLimit(1)
            } else {
                Text(strip.startLabel).kjBody().monospacedDigit()
                Text(strip.show?.name ?? "").kjBody().lineLimit(1)
            }
        }
    }
}

/// A band plate in the corner of the picture for the last minute of a slot, while the overlay is
/// hidden: what the channel turns to, and when. The overlay carries the same line when it is up,
/// so the two are never on screen together.
struct HandoverNotice: View {
    let air: OnAir
    let next: ScheduleStrip?
    let overlayVisible: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long before the end of a slot the notice comes up. A DEBUG build takes
    /// `-kjhandoverlead <seconds>`, so a UI test can photograph it at any time of day.
    static var lead: Int {
        #if DEBUG
        let set = UserDefaults.standard.integer(forKey: "kjhandoverlead")
        if set > 0 { return set }
        #endif
        return 60
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = StationClock.secondsLeft(in: air, at: TransmissionStore.now(context.date))
            let showing = !overlayVisible && next != nil && (left.map { $0 <= Self.lead } ?? false)
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                if showing, let next {
                    Text(text(next))
                        .kjKicker(palette.onBand)
                        .lineLimit(1)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 26)
                        .background(palette.band)
                        .padding(.trailing, KJLayout.inset)
                        .padding(.bottom, 60)
                        .transition(.opacity)
                        .accessibilityIdentifier("handoverNotice")
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: showing)
        }
        .allowsHitTesting(false)
    }

    private func text(_ next: ScheduleStrip) -> String {
        var line = "Up next \(next.startLabel) \(StationClock.tzLabel)"
        if let show = next.show?.name, !show.isEmpty { line += " \u{00B7} \(show)" }
        return line
    }
}
