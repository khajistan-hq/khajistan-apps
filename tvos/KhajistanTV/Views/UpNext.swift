import SwiftUI

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
