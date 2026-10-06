#if DEBUG
import SwiftUI
import UIKit

/// For measuring scroll smoothness on a device: main-thread display-link frames, how many came
/// late (a gap over one and a half refreshes), and the worst gap. Read by ScrollPerfUITests from
/// a hidden label, refreshed once a second so the meter costs next to nothing.
@MainActor @Observable
final class FrameMeter {
    static let shared = FrameMeter()
    private(set) var summary = "frames=0 late=0 worstMs=0"
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var late = 0
    @ObservationIgnored private var worst: CFTimeInterval = 0
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ l: CADisplayLink) {
        if last > 0 {
            let gap = l.timestamp - last
            frames += 1
            if gap > 1.5 * (l.targetTimestamp - l.timestamp) { late += 1 }
            worst = max(worst, gap)
        }
        last = l.timestamp
        if l.timestamp - lastPublish > 1 {
            lastPublish = l.timestamp
            summary = "frames=\(frames) late=\(late) worstMs=\(Int(worst * 1000))"
            print("KJMETER \(summary)")
        }
    }
}

struct FrameMeterLabel: View {
    let meter = FrameMeter.shared

    var body: some View {
        Text(meter.summary)
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityIdentifier("frameMeter")
            .onAppear { meter.start() }
    }
}
#endif
