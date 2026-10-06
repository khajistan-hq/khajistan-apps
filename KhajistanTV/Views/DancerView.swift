import Observation
import QuartzCore
import SwiftUI

/// The dancer over the ground while sound with no picture plays: a receiver radio channel, or a
/// Khajistan Transmission programme that is audio only (all of channel 2, and channel 1's
/// records). The website's terms, from open-frequencies.js and video.html:
///
/// - driven only by the samples of the playing signal (`SignalTap`), never by a timer;
/// - never over a picture, never on a reverent channel — the caller decides both and simply
///   does not ask `PlayerController` to listen;
/// - only where the samples can be read: an HLS carrier gives no tap, and then there is no
///   dancer and nothing in his place;
/// - he comes on only to a BEAT (`BeatTracker`), sits out a voice, and goes off by an exit when
///   the beat stops or the channel does (`DancerStage`);
/// - Reduce Motion shows no dancer, as the site hides its canvas for a reduced-motion visitor.
///
/// `behind` is what he dances in front of — the radio's name, the programme's title. It drops
/// back to 26% while he is drawing, as the site's wordmark does (`.scope-live`).
struct DancerLayer<Behind: View>: View {
    let controller: PlayerController
    @ViewBuilder let behind: () -> Behind

    @State private var scope = DancerScope()
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let signal = reduceMotion ? nil : controller.signal
        TimelineView(.animation(minimumInterval: nil, paused: !scope.ticking)) { timeline in
            let render = scope.update(
                playTime: controller.playTimeMS, audible: controller.audible,
                wall: timeline.date.timeIntervalSinceReferenceDate * 1000
            )
            ZStack {
                // What the dancer would cover moves out of his way while he dances: to the top
                // right, smaller and at full strength, and back to the centre when he stops
                // (owner, 2026-10-06: the faded text behind him "should appear somewhere else and
                // maybe in full"). The strip and captions hold the bottom, so the top it is.
                behind()
                    .scaleEffect(render.drawing ? 0.45 : 1, anchor: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: render.drawing ? .topTrailing : .center)
                    .padding(.top, render.drawing ? 64 : 0)
                    .padding(.trailing, render.drawing ? KJLayout.inset : 0)
                    .animation(.smooth(duration: 0.6), value: render.drawing)
                Canvas { ctx, size in
                    scope.paint(render, in: ctx, size: size, colours: Pen.Colours(green: palette.band, ink: palette.ink))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .dancerProbe(scope.status)
            }
        }
        .onChange(of: signal.map(ObjectIdentifier.init), initial: true) {
            scope.connect(signal, wall: CACurrentMediaTime() * 1000)
        }
    }
}

private extension View {
    /// The dancer is decoration (the site marks its canvas aria-hidden). Debug builds expose his
    /// state and the draw time to the UI tests, which have no other way to see him.
    @ViewBuilder func dancerProbe(_ status: String) -> some View {
        #if DEBUG
        accessibilityElement()
            .accessibilityIdentifier("dancer")
            .accessibilityLabel("Dancer")
            .accessibilityValue(status)
        #else
        accessibilityHidden(true)
        #endif
    }
}

/// Everything the dancer knows from one frame to the next: the beat tracker, the stage, and the
/// signal he is listening to. Updated once per display frame by `DancerLayer`.
@MainActor @Observable
final class DancerScope {
    struct Render {
        var frame: DancerStage.Frame = .blank
        var cast = DancerCast.base
        var side = 1.0
        var signal = DancerSignal()
        var drawing: Bool { frame != .blank }
    }

    /// Whether the timeline should run: a signal to listen to, or an exit still playing.
    private(set) var ticking = false
    @ObservationIgnored private(set) var status = "absent"

    @ObservationIgnored private var signal: SignalTap?
    @ObservationIgnored private var tracker = BeatTracker()
    @ObservationIgnored private var stage = DancerStage()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var spectrum = [UInt8](repeating: 0, count: SignalTap.bins)
    @ObservationIgnored private var rms = 0.0
    @ObservationIgnored private var level = 0.0
    @ObservationIgnored private var heard = false
    @ObservationIgnored private var leaving = false
    @ObservationIgnored private var audioNow: Double?
    /// The player's clock less the last spectrum's stamp: how far the dancer is behind the sound.
    @ObservationIgnored private var lag = 0.0
    @ObservationIgnored private var paintTimes: [Double] = []
    /// What this frame's update (tap read, beat tracking, stage) cost, added to the paint time.
    @ObservationIgnored private var updateMS = 0.0
    @ObservationIgnored private var paintStats = ""

    /// A new signal, or none. A new one starts the stage empty (an exit still running is cut, as
    /// on the site); losing the signal sends a dancer who is on off by an exit.
    func connect(_ new: SignalTap?, wall: Double) {
        guard new !== signal else { return }
        if new != nil {
            tracker = BeatTracker()
            stage.reset()
            seq = 0
            spectrum = [UInt8](repeating: 0, count: SignalTap.bins)
            rms = 0; level = 0; heard = false; leaving = false; audioNow = nil
        } else {
            leaving = stage.leave(now: wall)
        }
        signal = new
        ticking = new != nil || leaving
    }

    /// One display frame: read the spectra the audio has reached, run the beat tracker, and step
    /// the stage. Returns what to paint.
    func update(playTime: Double?, audible: Bool, wall: Double) -> Render {
        let began = CACurrentMediaTime()
        defer { updateMS = (CACurrentMediaTime() - began) * 1000 }
        guard let signal else {
            guard leaving else { return idle("absent") }
            let frame = stage.stepLeaving(now: wall)
            if frame == .blank { finishLeaving() }
            return render(frame, rate: 44100, status: "leave")
        }
        let frames = signal.take(after: &seq, upTo: playTime)
        for f in frames {
            // A spectrum the tap could not place in item time is read as arriving now.
            let time = f.time.isFinite ? f.time : (playTime ?? (audioNow ?? 0) + 1000 / 60)
            tracker.feed(f.spectrum, at: time)
            spectrum = f.spectrum
            rms = f.rms
            audioNow = time
        }
        if let playTime, let now = audioNow { lag = playTime - now }
        if frames.isEmpty, let playTime, let now = audioNow, playTime > now {
            tracker.advance(to: playTime)
            audioNow = playTime
        }
        // The tap reads before the player's volume, so the reference is full scale.
        if rms > 0.0015 { heard = true }
        let target = min(1, pow(max(0, rms) * 2.6, 0.7))
        level = target > level ? target : level + (target - level) * 0.16
        guard audible && heard else { return idle(heard ? "quiet" : "listening") }
        let now = audioNow ?? 0
        let frame = stage.step(now: wall, grooving: { [tracker] on in tracker.grooving(at: now, on: on) },
                               beat: tracker.beat, groove: tracker.groove, count: tracker.count)
        return render(frame, rate: signal.sampleRate, status: stage.name.rawValue)
    }

    func paint(_ r: Render, in ctx: GraphicsContext, size: CGSize, colours: Pen.Colours) {
        guard r.drawing else { return }
        let start = CACurrentMediaTime()
        var pen = Pen(ctx, colours: colours)
        let w = Double(size.width), h = Double(size.height)
        switch r.frame {
        case .blank:
            break
        case .dance(let move):
            drawDancer(&pen, w: w, h: h, cast: r.cast, move: move, signal: r.signal)
        case .piece(let name, let kind, let u):
            drawPiece(&pen, stage: name, kind: kind, u: u, side: r.side, cast: r.cast,
                      beatPhase: r.signal.phase, on: Stage(w: w, h: h))
        }
        record((CACurrentMediaTime() - start) * 1000 + updateMS)
    }

    // MARK: -

    private func render(_ frame: DancerStage.Frame, rate: Double, status name: String) -> Render {
        let bands = DancerScope.bands(spectrum, rate: rate)
        var move = ""
        if case .dance(let m) = frame { move = " move=\(m)" }
        if case .piece(_, let kind, _) = frame { move = " piece=\(kind)" }
        status = "stage=\(name)\(move) lag_ms=\(Int(lag)) beat=\(String(format: "%.2f", tracker.beat)) groove=\(String(format: "%.2f", tracker.groove))\(paintStats)"
        return Render(frame: frame, cast: DancerCast.named(stage.cast), side: stage.side,
                      signal: DancerSignal(phase: tracker.phase, count: tracker.count,
                                           bass: bands.0, mid: bands.1, treble: bands.2, level: level))
    }

    private func idle(_ name: String) -> Render {
        status = "stage=\(name) beat=\(String(format: "%.2f", tracker.beat)) groove=\(String(format: "%.2f", tracker.groove))"
        return Render()
    }

    /// The exit has played out. The timeline stops on the next turn of the run loop, not inside
    /// this view update.
    private func finishLeaving() {
        leaving = false
        Task { @MainActor [weak self] in
            guard let self, self.signal == nil, !self.leaving else { return }
            self.ticking = false
        }
    }

    /// Frame times (update + paint, main thread) over the last 240 frames, for the probe. The
    /// render server's rasterising of the Canvas is not in it.
    private func record(_ ms: Double) {
        paintTimes.append(ms)
        guard paintTimes.count >= 240 else { return }
        let sorted = paintTimes.sorted()
        paintStats = String(format: " frame_ms_p50=%.2f p95=%.2f max=%.2f", sorted[sorted.count / 2],
                            sorted[sorted.count * 95 / 100], sorted.last ?? 0)
        paintTimes.removeAll(keepingCapacity: true)
    }

    /// kj-scope.js bands(3, …): three log-spaced bands from 45 Hz to 16 kHz, each the mean of its
    /// spectrum bytes over 255.
    static func bands(_ freq: [UInt8], rate: Double) -> (Double, Double, Double) {
        let count = 3, binCount = freq.count
        guard binCount > 1 else { return (0, 0, 0) }
        let per = (rate / 2) / Double(binCount), lo = 45.0, hi = min(16000, rate / 2)
        var e = [Int](repeating: 0, count: count + 1)
        for i in 0...count {
            e[i] = min(binCount - 1, Int((lo * pow(hi / lo, Double(i) / Double(count)) / per).rounded()))
            if i > 0 && e[i] <= e[i - 1] { e[i] = min(binCount - 1, e[i - 1] + 1) }
        }
        func band(_ i: Int) -> Double {
            let from = e[i], to = max(from + 1, e[i + 1])
            var sum = 0
            for j in from..<min(to, binCount) { sum += Int(freq[j]) }
            return Double(sum) / Double(to - from) / 255
        }
        return (band(0), band(1), band(2))
    }
}
