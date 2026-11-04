import SwiftUI

/// A radio card's picture: a line of sound moving slowly across, drawn from the station's id so
/// each station has its own. Two periods of the wave are drawn once and slid sideways by one, so
/// a frame costs a move and no redraw. Still under Reduce Motion; stopped off screen.
struct SoundLine: View {
    let seed: String
    var lineWidth: CGFloat = 3
    /// Seconds for the wave to pass once.
    var period: Double = 4
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moving = false

    var body: some View {
        GeometryReader { geo in
            SoundWave(seed: Self.fnv(seed))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: geo.size.width * 2, height: geo.size.height)
                .offset(x: moving ? -geo.size.width : 0)
                .animation(moving ? .linear(duration: period).repeatForever(autoreverses: false) : .linear(duration: 0), value: moving)
        }
        .clipped()
        .onAppear { moving = !reduceMotion }
        .onDisappear { moving = false }
        .onChange(of: reduceMotion) { _, reduce in moving = !reduce }
        .accessibilityHidden(true)
    }

    /// A stable number from the id (String.hashValue changes every launch).
    static func fnv(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// Two identical periods of a voice-like wave across the rect: a few harmonics of the period
/// under a slow swell, so the two halves join without a seam.
private struct SoundWave: Shape {
    let seed: UInt64

    func path(in rect: CGRect) -> Path {
        var random = seed
        func next() -> Double {
            random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(random >> 11) / Double(1 << 53)
        }
        let harmonics: [(k: Double, a: Double, phase: Double)] = [3, 5, 8, 13].map { ($0, 0.35 + next() * 0.65, next() * 2 * .pi) }
        let swellPhase = next() * 2 * .pi
        let total = harmonics.reduce(0) { $0 + $1.a }
        let half = rect.width / 2
        let steps = 96
        var path = Path()
        for i in 0...(steps * 2) {
            let t = Double(i % steps) / Double(steps)
            let swell = 0.35 + 0.65 * pow(sin(.pi * t + swellPhase / 2), 2)
            let value = harmonics.reduce(0) { $0 + $1.a * sin(2 * .pi * $1.k * t + $1.phase) } / total
            let x = rect.minX + CGFloat(i) / CGFloat(steps) * half
            let y = rect.midY - CGFloat(value * swell) * rect.height / 2
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
