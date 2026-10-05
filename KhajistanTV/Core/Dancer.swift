import Foundation

// The dancer's choreography and stage machine, ported from archive/scripts/kj-scope.js (the
// "dancer" style). What he does and when; how he looks is Views/DancerView.swift. Nothing here
// invents a move or a piece the website does not have.

// MARK: - Moves and cast

enum DancerMoves {
    /// One move per two bars, drawn at random. The regional entries are stylised silhouettes of a
    /// characteristic posture, not documented choreography, named after the dance.
    static let all = ["Running man", "Dabke", "Bhangra", "Attan", "Bandari", "Halay", "Shimmy",
                      "Twerk", "Horse trot", "Lasso", "Pole spin", "Side shuffle", "Fist pumps",
                      "High kicks", "Spin out", "Kolo", "Cocek", "Rachenitsa",
                      "Eskista", "Kawliya", "Kambala", "Krumping", "Voguing"]
    /// The moves that bounce off the floor.
    static let hop: Set<String> = ["Running man", "Dabke", "Bhangra", "Attan", "Horse trot", "High kicks",
                                   "Kolo", "Rachenitsa", "Kambala", "Krumping"]
    /// The hair dance IS the hair, so only the long-haired figure draws it.
    static let hairOnly: Set<String> = ["Kawliya"]
    /// Owner, 2026-09-09: randomise the moves, and make him twerk.
    static let weight: [String: Int] = ["Twerk": 4]

    /// The next move: drawn from a bag with Twerk weighted up and the current move left out, so
    /// no move repeats back to back. `random` is in [0, 1).
    static func next(in list: [String], after current: Int, random: Double) -> Int {
        var bag: [Int] = []
        for (i, move) in list.enumerated() {
            if i == current && list.count > 1 { continue }
            bag.append(contentsOf: repeatElement(i, count: weight[move] ?? 1))
        }
        guard !bag.isEmpty else { return 0 }
        return bag[min(bag.count - 1, Int(random * Double(bag.count)))]
    }

    /// The list a figure may draw from: everything but what it cannot dance.
    static func list(for cast: DancerCast) -> [String] {
        guard !cast.skip.isEmpty else { return all }
        let allowed = all.filter { !cast.skip.contains($0) }
        return allowed.isEmpty ? all : allowed
    }
}

/// A body: proportions as fractions of the figure's height, and its physics.
struct DancerCast: Equatable, Sendable {
    var scale = 1.0, limbW = 1.0, headR = 0.07, torso = 0.30, thigh = 0.21, shin = 0.20
    var armLen = 0.19, foreLen = 0.17, shoulderW = 0.105, hipW = 0.075
    var bounce = 1.0, bassGain = 1.0, lean = 1.0
    var cycle = 8
    var hair = false
    var skip: Set<String> = []

    /// Two figures, drawn at the entrance and kept for the whole set.
    static let base = DancerCast(skip: DancerMoves.hairOnly)
    /// Lighter build, hair down past the shoulders, and the only one who dances Kawliya.
    static let hairy = DancerCast(scale: 0.97, limbW: 0.95, bounce: 1.08, hair: true)
    static let keys = ["base", "hairy"]
    static func named(_ key: String) -> DancerCast { key == "hairy" ? hairy : base }
}

// MARK: - The stage

/// The pieces that bring him on, take him off, and give him a break, with their lengths in ms.
enum DancerPieces {
    static let enter: [(String, Double)] = [("walk", 1700), ("rope", 1600), ("slide", 1500),
                                            ("kicked", 1900), ("trapdoor", 1500), ("cartwheel", 1600)]
    static let exit: [(String, Double)] = [("arrow", 2600), ("slap", 4200), ("hook", 1700),
                                           ("trapdoor", 1600), ("broom", 2300), ("bow", 1800)]
    static let smoke: [(String, Double)] = [("cigarette", 7200), ("yoga", 17000), ("tea", 8600),
                                            ("phone", 11000), ("rolling", 10500)]
}

/// Owner, 2026-09-04: the dancer enters when the receiver comes on and leaves, playfully, when
/// it goes off. He is `off` until the signal carries a BEAT, comes on by an entrance, dances
/// (`on`), takes a break now and then (`smoke`), and goes by an exit when the beat stops or the
/// channel does. A voice alone never brings him on. Times are wall-clock milliseconds.
struct DancerStage {
    enum Name: String, Sendable { case off, enter, on, smoke, leave }

    /// What to draw this frame.
    enum Frame: Equatable {
        case blank
        case dance(move: String)
        case piece(Name, kind: String, u: Double)
    }

    private(set) var name = Name.off
    private(set) var kind: String?
    private(set) var t0 = 0.0
    private(set) var dur = 0.0
    private(set) var side = 1.0
    private(set) var cast = "base"
    private var wantSince: Double?
    private var lostSince: Double?
    private var smokeAt: Double?
    private var lastEnter: String?, lastLeave: String?, lastBreak: String?
    private var move = 0
    private var lastBar = 0

    var random: () -> Double

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    /// A new signal: the stage starts empty (the last pieces are remembered, so the next one differs).
    mutating func reset() {
        name = .off; kind = nil; t0 = 0; dur = 0; side = 1; cast = "base"
        wantSince = nil; lostSince = nil; smokeAt = nil
        move = 0; lastBar = 0
    }

    /// One frame of draw.dancer with a signal attached. `grooving(on)` is the beat gate with the
    /// hysteresis for the current state; `beat` and `groove` the tracker's raw and smoothed score;
    /// `count` the beat clock's beat number.
    mutating func step(now: Double, grooving: (Bool) -> Bool, beat: Double, groove: Double, count: Int) -> Frame {
        if grooving(name != .off) {
            lostSince = nil
            if wantSince == nil { wantSince = now }
        } else {
            wantSince = nil
            if lostSince == nil { lostSince = now }
        }
        if name == .off {
            // The analysis window remains the evidence gate. A strong, sustained rhythm enters
            // promptly; ambiguous sound keeps the full second that stops short speech peaks.
            let hold: Double = beat >= 0.55 && groove >= 0.40 ? 250 : 1000
            guard let since = wantSince, now - since >= hold else { return .blank }
            begin(.enter, now: now)
        } else if name != .leave, let lost = lostSince, now - lost > 5000 {
            // The music stopped: he goes. Five seconds, because a real song has lulls.
            begin(.leave, now: now)
        }
        if name == .on {
            // A break every 45–105 seconds of dancing.
            if smokeAt == nil { smokeAt = now + 45000 + random() * 60000 }
            if now < smokeAt! { return .dance(move: currentMove(count: count)) }
            begin(.smoke, now: now)
        }
        return playPiece(now: now)
    }

    /// The signal is gone. True when there is a figure to see off — keep calling `stepLeaving`
    /// until it returns `.blank`. False when he was never on, so nothing is owed.
    mutating func leave(now: Double, kind: String? = nil) -> Bool {
        if name == .off { return false }
        if name != .leave { begin(.leave, kind: kind, now: now) }
        return true
    }

    /// One frame of the exit with no signal under it.
    mutating func stepLeaving(now: Double) -> Frame {
        guard name == .leave else { return .blank }
        return playPiece(now: now)
    }

    /// Bring him on by a named entrance, or send him for a named break (the site's desk hooks).
    mutating func begin(_ stage: Name, kind wanted: String? = nil, now: Double) {
        let table: [(String, Double)]
        let last: String?
        switch stage {
        case .enter: table = DancerPieces.enter; last = lastEnter
        case .smoke: table = DancerPieces.smoke; last = lastBreak
        default: table = DancerPieces.exit; last = lastLeave
        }
        var chosen = wanted.flatMap { w in table.first { $0.0 == w } }
        if chosen == nil {
            let options = table.filter { $0.0 != last }
            chosen = options[min(options.count - 1, Int(random() * Double(options.count)))]
        }
        let piece = chosen!
        switch stage {
        case .enter: lastEnter = piece.0
        case .smoke: lastBreak = piece.0
        default: lastLeave = piece.0
        }
        name = stage == .enter || stage == .smoke ? stage : .leave
        kind = piece.0
        t0 = now
        dur = piece.1
        side = random() < 0.5 ? -1 : 1
        // Who walks on is decided once, at the entrance, and holds through the set.
        if stage == .enter { cast = DancerCast.keys[min(DancerCast.keys.count - 1, Int(random() * Double(DancerCast.keys.count)))] }
    }

    private mutating func playPiece(now: Double) -> Frame {
        guard let kind else { return .blank }
        let u = min(1, max(0, (now - t0) / dur))
        let frame = Frame.piece(name, kind: kind, u: u)
        guard u >= 1 else { return frame }
        if name == .enter || name == .smoke {
            name = .on
            smokeAt = nil
            return frame
        }
        reset()
        return .blank
    }

    /// The move for this beat: a new one is drawn every `cycle` beats.
    private mutating func currentMove(count: Int) -> String {
        let figure = DancerCast.named(cast)
        let list = DancerMoves.list(for: figure)
        let bar = count / figure.cycle
        if bar != lastBar {
            lastBar = bar
            move = DancerMoves.next(in: list, after: move, random: random())
        }
        return list[min(move, list.count - 1)]
    }
}
