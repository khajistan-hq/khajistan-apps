import Foundation

// The dancer's two rules that are not drawing: when he may appear at all (the reverent rule),
// and whether what is playing carries a BEAT (the gate). Both are ported line for line from the
// website — isReverentChannel() in archive/scripts/open-frequencies.js, and trackBeat(),
// tempo(), scoreBeat() and groove() in archive/scripts/kj-scope.js — so the two surfaces of one
// station answer the same question the same way. Foundation only: the core tests run them.

// MARK: - Reverence

/// Religious respect (owner hard rule): the dancer never runs while Quranic recitation is
/// playing. "Reverent" is decided ONLY from a channel's own self-description (name, native name,
/// broadcaster), never inferred about content the receiver cannot verify. A person's ruling on
/// the record beats the name test: `reverent: true` or `visualiser: false` keeps him off a
/// station whose name says nothing (owner, 2026-09-04).
enum Reverence {
    private static let latin = try! NSRegularExpression(
        pattern: "qur.?an|koran|recitation|tilawa\\s*h?|nida\\s*al-?islam",
        options: [.caseInsensitive]
    )
    private static let arabic = ["قرآن", "قران", "تلاوة", "نداء الاسلام", "نداء الإسلام"]

    static func isReverent(name: String?, nativeName: String?, broadcaster: String?,
                           reverent: Bool? = nil, visualiser: Bool? = nil) -> Bool {
        if reverent == true || visualiser == false { return true }
        return [name, nativeName, broadcaster].compactMap { $0 }.filter { !$0.isEmpty }.contains { value in
            let whole = NSRange(value.startIndex..., in: value)
            if latin.firstMatch(in: value, range: whole) != nil { return true }
            // The site strips U+064B–U+0670 (harakat, the superscript alef) and the tatweel.
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: value.unicodeScalars.filter {
                !((0x064B...0x0670).contains($0.value) || $0.value == 0x0640)
            })
            let stripped = String(scalars) as NSString
            return arabic.contains { stripped.range(of: $0, options: .literal).location != NSNotFound }
        }
    }
}

extension Channel {
    var isReverent: Bool {
        Reverence.isReverent(name: name, nativeName: nativeName, broadcaster: broadcaster,
                             reverent: reverent, visualiser: visualiser)
    }
}

// MARK: - The beat

/// The website's beat tracker. Fed one analyser spectrum at a time (`feed`), as kj-scope.js's
/// trackBeat() is fed one getByteFrequencyData() per animation frame, and told when time passes
/// with no new spectrum (`advance`), which is trackBeat()'s "the analyser has not ticked" branch.
/// All times are milliseconds on one clock, the audio's own.
///
/// It produces three things the dancer reads: a phase-locked beat clock (`phase`, `count`,
/// `period`) his limbs land on, `beat` and `groove` — the comb-autocorrelation score of the
/// onset envelope and its smoothed value — and `lastOnset`, which `grooving(at:on:)` needs.
struct BeatTracker {
    private(set) var phase = 0.0
    private(set) var count = 0
    private(set) var period = 0.5
    private(set) var conf = 0.0
    /// The best comb score of the last eight seconds, and its .7/.3 smoothing.
    private(set) var beat = 0.0
    private(set) var groove = 0.0
    private(set) var lastOnset = -Double.infinity

    private var last: Double?
    private var prev: [UInt8] = []
    private var flux: [Double] = []
    private var fluxT: [Double] = []
    private var onsets: [Double] = []
    /// The onset envelope: 20 ms bins, eight seconds deep, the loudest frame in each bin.
    private(set) var envelope: [Double] = []
    private var acc = 0.0
    private var binT: Double?
    private var nextScore = 0.0

    init() {}

    /// Is there a BEAT, as opposed to a sound? Harder to come on than to stay on, so a quiet bar
    /// does not send him off; the last onset must be recent, so a track that ends does not
    /// leave him dancing to the silence.
    func grooving(at now: Double, on: Bool) -> Bool {
        groove > (on ? 0.14 : 0.20) && (now - lastOnset) < 2500
    }

    /// Time passed with no new spectrum: the clock free-wheels and confidence decays.
    mutating func advance(to now: Double) {
        let dt = stepTime(now)
        if fluxT.isEmpty { return }
        conf = max(0, conf - dt * 0.1)
        tick(dt)
    }

    /// One new analyser spectrum (getByteFrequencyData's bytes) at `now`.
    mutating func feed(_ spectrum: [UInt8], at now: Double) {
        // A clock that ran back more than a second is a new signal (a seek, a handover): start
        // again. A frame a few milliseconds behind the last is only late, and is read as it is.
        if let last, now < last - 1000 { self = BeatTracker() }
        let dt = stepTime(now)
        let n = spectrum.count * 3 / 4
        var sum = 0.0, same = true
        if prev.count != n {
            prev = Array(spectrum.prefix(n))
            same = false
        } else {
            for i in 0..<n {
                let d = Int(spectrum[i]) - Int(prev[i])
                if d != 0 { same = false }
                if d > 0 { sum += Double(d) }
                prev[i] = spectrum[i]
            }
        }
        let value = n > 0 ? sum / Double(n) : 0

        // A spectrum that has not moved is the analyser not having ticked, not a silent frame,
        // and stays out of the statistics; the clock still advances on it.
        if same && !fluxT.isEmpty {
            conf = max(0, conf - dt * 0.1)
            tick(dt)
            return
        }
        flux.append(value)
        fluxT.append(now)
        while let first = fluxT.first, now - first > 1500 {
            flux.removeFirst()
            fluxT.removeFirst()
        }
        // A clock that jumped two seconds starts the envelope again rather than replaying one
        // stale frame across the seconds it missed.
        if binT == nil || now - binT! > 2000 {
            binT = now
            envelope.removeAll(keepingCapacity: true)
            acc = 0
        }
        if value > acc { acc = value }
        while now - binT! >= 20 {
            envelope.append(acc)
            if envelope.count > 400 { envelope.removeFirst() }
            acc = 0
            binT! += 20
        }
        if now >= nextScore && envelope.count >= 200 {
            nextScore = now + 500
            beat = BeatTracker.score(envelope)
            groove = groove * 0.7 + beat * 0.3
        }
        let mean = flux.reduce(0, +) / Double(max(flux.count, 1))
        let sd = (flux.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(flux.count, 1))).squareRoot()

        if value > mean + sd * 1.4 && value > 0.35 && now - lastOnset > 130 {
            lastOnset = now
            onsets.append(now)
            if onsets.count > 40 { onsets.removeFirst() }
            tempo()
            // Nudge toward the nearest beat rather than resetting, so one missed or spurious
            // onset bends the clock instead of making the figure stutter.
            let err = phase > 0.5 ? phase - 1 : phase
            phase -= err * 0.35
            if phase < 0 { phase += 1 }
            conf = min(1, conf + 0.12)
        } else {
            conf = max(0, conf - dt * 0.1)
        }
        tick(dt)
    }

    /// scoreBeat(): the normalised autocorrelation of the onset envelope at its best lag between
    /// .3 and 1.0 s (15–50 bins), each lag scored together with its double, so a bar counts twice
    /// and a stray repeat does not. NOT smoothed — a 5-bin kernel lifted a newsreader over the
    /// bar on the site (2026-09-18). Measured there on real recordings: Attan and a 1928 78 rpm
    /// side median .19–.28; five dialogue clips never above .17 at their 90th percentile.
    static func score(_ e: [Double]) -> Double {
        let n = e.count
        guard n > 0 else { return 0 }
        let mean = e.reduce(0, +) / Double(n)
        let z = e.map { $0 - mean }
        let energy = z.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-6 else { return 0 }
        var cache = [Int: Double]()
        func ac(_ lag: Int) -> Double {
            if let hit = cache[lag] { return hit }
            var c = 0.0
            if lag < n { for k in lag..<n { c += z[k] * z[k - lag] } }
            cache[lag] = c / energy
            return c / energy
        }
        var best = 0.0
        for lag in 15...50 {
            let v = (ac(lag) + ac(2 * lag)) / 2
            if v > best { best = v }
        }
        return best
    }

    private mutating func stepTime(_ now: Double) -> Double {
        let dt = last.map { min(0.1, (now - $0) / 1000) } ?? 0.016
        last = now
        return max(0, dt)
    }

    private mutating func tick(_ dt: Double) {
        phase += dt / period
        while phase >= 1 { phase -= 1; count += 1 }
    }

    /// Onsets → tempo: the period between .3 and 1 s that the recent onsets fit best.
    private mutating func tempo() {
        var best = 0.0, bestScore = 0.0
        for step in 0...70 {
            let p = 0.30 + Double(step) * 0.01
            var score = 0.0
            for i in 1..<max(onsets.count, 1) {
                for j in max(0, i - 6)..<i {
                    let gap = (onsets[i] - onsets[j]) / 1000
                    if gap < 0.2 || gap > 4 { continue }
                    let mult = gap / p, near = abs(mult - mult.rounded())
                    if mult.rounded() >= 1 && near < 0.12 { score += 1 - near / 0.12 }
                }
            }
            if score > bestScore { bestScore = score; best = p }
        }
        if best > 0 && bestScore > 4 { period = period * 0.7 + best * 0.3 }
    }
}
