import Foundation

// Khajistan visualizers (owner, 2026-11-25: "create these multiple visualizers that on demand can
// play just like how the dancer shows up in all of the audio"). Ported from visLoad() and visPick()
// in archive/scripts/open-frequencies.js: an After Hours picture plays muted under a sound channel,
// joined at a clock point, and the next picture takes over every 30 minutes. Foundation only: the
// core tests run it. The player is Views/VisualizerLayer.swift.

/// One row of data/khajistan-tv/visualizers.json.
struct VisualizerPiece: Decodable, Equatable, Sendable {
    let id: String
    let title: String?
    let category: String?
    let seconds: Double
    let play_url: String
    /// A nature piece, the only kind a reverent (devotional or Quran) channel plays.
    let reverent: Bool?
}

/// What the viewer has chosen. Sound channels cycle dancer, khajistan, off; reverent channels
/// cycle off, nature, because the dancer never plays there.
enum VisualizerMode: String, Sendable {
    case dancer, khajistan, off, nature

    static let key = "kj-visualizer"
    static let natureKey = "kj-visualizer-nature"

    /// `dancer` false is the iPhone, which has no dancer: its sound channels cycle off, khajistan.
    static func modes(reverent: Bool, dancer: Bool = true) -> [VisualizerMode] {
        reverent ? [.off, .nature] : dancer ? [.dancer, .khajistan, .off] : [.off, .khajistan]
    }

    /// The stored choice for this kind of channel; anything unknown is the default.
    static func current(reverent: Bool, stored: String?, storedNature: String?, dancer: Bool = true) -> VisualizerMode {
        let list = modes(reverent: reverent, dancer: dancer)
        let mode = VisualizerMode(rawValue: (reverent ? storedNature : stored) ?? "")
        // Owner, 2026-11-26: "for all audio channels make the khajistan viusalizer the default option" — Nature on a
        // reverent channel, on both apps. On the TV the dancer stands in while the picture is not up; on the
        // iPhone, which has no dancer, the channel's name does.
        return mode.flatMap { list.contains($0) ? $0 : nil } ?? (reverent ? .nature : .khajistan)
    }

    func next(reverent: Bool, dancer: Bool = true) -> VisualizerMode {
        let list = Self.modes(reverent: reverent, dancer: dancer)
        return list[((list.firstIndex(of: self) ?? -1) + 1) % list.count]
    }

    /// A picture plays in this mode.
    var playsPicture: Bool { self == .khajistan || self == .nature }

    var label: String {
        switch self {
        case .dancer: return "Visualizer \u{00B7} Dancer"
        case .khajistan: return "Visualizer \u{00B7} Khajistan"
        case .off: return "Visualizer \u{00B7} Off"
        case .nature: return "Visualizer \u{00B7} Nature"
        }
    }
}

enum Visualizer {
    static let path = "/data/khajistan-tv/visualizers.json"
    /// One picture per 30 minutes of the wall clock, the site's VIS_BLOCK_MS.
    static let block: TimeInterval = 30 * 60

    /// The rows the site would keep: a play address and a length.
    static func rows(from data: Data) -> [VisualizerPiece] {
        guard let rows = try? JSONDecoder().decode([Lenient].self, from: data) else { return [] }
        return rows.compactMap(\.piece).filter { !$0.play_url.isEmpty && $0.seconds > 0 && $0.seconds.isFinite }
    }

    /// The piece on now, where in it to start, and when the next one takes over. Nil when no row
    /// suits this kind of channel.
    static func pick(_ rows: [VisualizerPiece], reverent: Bool, now: Date)
        -> (piece: VisualizerPiece, offset: TimeInterval, until: Date)? {
        // Owner, 2026-11-26: every piece on a sound channel, only Nature on a religious one.
        let suited = rows.filter { !reverent || $0.reverent == true }
        guard !suited.isEmpty else { return nil }
        let t = now.timeIntervalSince1970
        let slot = Int((t / block).rounded(.down))
        let piece = suited[((slot % suited.count) + suited.count) % suited.count]
        let until = Date(timeIntervalSince1970: Double(slot + 1) * block)
        return (piece, offset(of: piece, at: now), until)
    }

    /// Owner, 2026-11-26: "make sure all visualisers play randomly so every visualiser gets a chance to be seen".
    /// A shuffle bag: a random piece this device has not shown yet; when every piece has had its turn the bag
    /// refills (never with the piece just shown, when there is a choice). Joined at a random point, and the next
    /// draw comes when the piece ends or after half an hour. `roll` and `startRoll` are in 0..<1 so tests can fix them.
    static let seenKey = "kj-visualizer-seen"
    static func draw(_ rows: [VisualizerPiece], reverent: Bool, seen: [String], roll: Double, startRoll: Double)
        -> (piece: VisualizerPiece, offset: TimeInterval, play: TimeInterval, seen: [String])? {
        // Owner, 2026-11-26: every piece on a sound channel, only Nature on a religious one.
        let suited = rows.filter { !reverent || $0.reverent == true }
        guard !suited.isEmpty else { return nil }
        var fresh = suited.filter { !seen.contains($0.id) }
        var bag = seen
        if fresh.isEmpty {
            bag = []
            fresh = suited.count > 1 ? suited.filter { $0.id != seen.last } : suited
        }
        let piece = fresh[min(fresh.count - 1, Int(roll * Double(fresh.count)))]
        let room = max(0, piece.seconds - 60)
        let offset = room * min(max(startRoll, 0), 0.999)
        let play = min(block, piece.seconds - offset)
        return (piece, offset, play, bag + [piece.id])
    }

    /// Where the picture is joined: the clock's seconds, round the piece's length.
    static func offset(of piece: VisualizerPiece, at now: Date, duration: Double? = nil) -> TimeInterval {
        let length = duration.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } ?? piece.seconds
        guard length > 0 else { return 0 }
        return now.timeIntervalSince1970.truncatingRemainder(dividingBy: length)
    }

    /// One bad row does not lose the list.
    private struct Lenient: Decodable {
        let piece: VisualizerPiece?
        init(from decoder: Decoder) throws { piece = try? VisualizerPiece(from: decoder) }
    }
}
