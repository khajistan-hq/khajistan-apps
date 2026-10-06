import Foundation

// MARK: - Geometry

/// A point in the shape files' own units: SVG user space, 1000 x 700 for the core map.
struct MapPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

/// An SVG viewBox, "minX minY width height".
struct ViewBox: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double

    /// Four finite numbers separated by spaces and/or commas, with a width and a height above
    /// zero. Anything else is nil, so a box that exists can be divided by.
    init?(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard parts.count == 4,
              let minX = Double(parts[0]), let minY = Double(parts[1]),
              let width = Double(parts[2]), let height = Double(parts[3]),
              [minX, minY, width, height].allSatisfy(\.isFinite),
              width > 0, height > 0 else { return nil }
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

// MARK: - SVG path data

/// The part of SVG path data the map files use, read as straight-sided polygons.
enum SVGPath {
    /// The polygons in path data `d`: M m L l H h V v Z z and nothing else. A polygon is closed by
    /// Z, by the next moveto, or by the end of the data, and is kept only with three or more
    /// points. Coordinate pairs after M or L repeat as L (after m or l, as l), and a line drawn
    /// after Z starts a new polygon where the last one began. The read stops at the first thing it
    /// cannot read: another command letter, a malformed number, a line before any moveto. What was
    /// read stays, the polygon in progress included, which is how SVG draws a path in error.
    /// ponytail: no curves or arcs, because the site ships none; flatten C/S/Q/A here if it does.
    static func polygons(_ d: String) -> [[MapPoint]] {
        var reader = Reader(bytes: Array(d.utf8))
        do { try reader.readPath() } catch { /* stopped: keep what was read */ }
        reader.endPolygon()
        return reader.polygons
    }

    private struct Stop: Error {}

    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        var polygons: [[MapPoint]] = []
        var points: [MapPoint] = []
        var current = MapPoint(x: 0, y: 0)
        var subpathStart = MapPoint(x: 0, y: 0)
        var moved = false

        mutating func endPolygon() {
            if points.count >= 3 { polygons.append(points) }
            points = []
        }

        mutating func readPath() throws {
            while true {
                skipSeparators()
                guard position < bytes.count else { return }
                let byte = bytes[position]
                position += 1
                let relative = byte >= UInt8(ascii: "a")
                switch byte | 0x20 {                       // folded to lower case
                case UInt8(ascii: "z"):
                    endPolygon()
                    current = subpathStart
                case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"):
                    try readCommand(byte | 0x20, relative: relative)
                default:
                    throw Stop()
                }
            }
        }

        /// The argument groups after one command letter: pairs for m and l, one number for h and v.
        mutating func readCommand(_ command: UInt8, relative: Bool) throws {
            var groups = 0
            while true {
                skipSeparators()
                guard position < bytes.count, startsNumber(bytes[position]) else { break }
                switch command {
                case UInt8(ascii: "m"), UInt8(ascii: "l"):
                    let x = try number(), y = try number()
                    let target = relative ? MapPoint(x: current.x + x, y: current.y + y) : MapPoint(x: x, y: y)
                    if command == UInt8(ascii: "m") && groups == 0 { moveTo(target) } else { try lineTo(target) }
                case UInt8(ascii: "h"):
                    let x = try number()
                    try lineTo(MapPoint(x: relative ? current.x + x : x, y: current.y))
                default:
                    let y = try number()
                    try lineTo(MapPoint(x: current.x, y: relative ? current.y + y : y))
                }
                groups += 1
            }
            if groups == 0 { throw Stop() }
        }

        mutating func moveTo(_ point: MapPoint) {
            endPolygon()
            current = point
            subpathStart = point
            moved = true
        }

        /// A polygon begins where the pen stands when its first line is drawn, which is after a
        /// moveto and also after a Z.
        mutating func lineTo(_ point: MapPoint) throws {
            guard moved else { throw Stop() }
            if points.isEmpty { points = [current] }
            points.append(point)
            current = point
        }

        /// An optional sign, digits with an optional point, and an exponent only when digits
        /// follow it, so a stray "e" is left to be read (and refused) as a command letter.
        mutating func number() throws -> Double {
            skipSeparators()
            var end = position
            if end < bytes.count, isSign(bytes[end]) { end += 1 }
            var digits = 0
            while end < bytes.count, isDigit(bytes[end]) { end += 1; digits += 1 }
            if end < bytes.count, bytes[end] == UInt8(ascii: ".") {
                end += 1
                while end < bytes.count, isDigit(bytes[end]) { end += 1; digits += 1 }
            }
            guard digits > 0 else { throw Stop() }
            if end < bytes.count, (bytes[end] | 0x20) == UInt8(ascii: "e") {
                var exponentEnd = end + 1
                if exponentEnd < bytes.count, isSign(bytes[exponentEnd]) { exponentEnd += 1 }
                let exponentDigits = exponentEnd
                while exponentEnd < bytes.count, isDigit(bytes[exponentEnd]) { exponentEnd += 1 }
                if exponentEnd > exponentDigits { end = exponentEnd }
            }
            guard let value = Double(String(decoding: bytes[position..<end], as: UTF8.self)),
                  value.isFinite else { throw Stop() }
            position = end
            return value
        }

        mutating func skipSeparators() {
            while position < bytes.count, isSeparator(bytes[position]) { position += 1 }
        }

        func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
        func isSign(_ byte: UInt8) -> Bool { byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") }
        func startsNumber(_ byte: UInt8) -> Bool { isDigit(byte) || isSign(byte) || byte == UInt8(ascii: ".") }
        /// A comma, a space, or a tab, line feed, vertical tab, form feed or carriage return.
        func isSeparator(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: ",") || byte == UInt8(ascii: " ") || (0x09...0x0D).contains(byte)
        }
    }
}

// MARK: - Shape files

/// data/region-shapes.json and data/region-shapes-extended.json. Only the fields the app reads
/// are declared. The extended file has no fillColor, ref_path or native.
struct RegionShapes: Decodable, Sendable {
    struct Shape: Decodable, Identifiable, Sendable {
        let id: String
        let label: String
        let path: String
        let refPath: String?
        let fillColor: String?
        let fillRule: String?
        let centroid: [Double]
        let native: String?
        let tier: String?
        let role: String?

        private enum CodingKeys: String, CodingKey {
            case id, label, path, refPath = "ref_path", fillColor, fillRule, centroid, native, tier, role
        }
    }

    let viewBox: String
    let coreViewBox: String?
    let regions: [Shape]
}

// MARK: - Composed map

/// Which of the two map greens a region is filled with: the house green, or the lighter second
/// colour (DESIGN.md mapDeep and mapTint).
enum MapFill: Equatable, Sendable {
    case deep
    case tint
}

struct MapRegion: Identifiable, Sendable {
    let id: String
    let label: String
    /// The native-script name, nil when it is blank or only repeats the label.
    let native: String?
    let polygons: [[MapPoint]]
    /// The shape drawn for the focus ring: the file's ref_path, or `polygons` when it has none.
    let outline: [[MapPoint]]
    let centroid: MapPoint
    let fill: MapFill
    /// The receiver index calls it a people's region (kind "people").
    let isPeople: Bool
    /// It sits behind the "Beyond the atlas" switch: it came from the extended file, or it is a
    /// core shape the receiver index tiers islamicate.
    let isExtension: Bool
    /// The receiver index has a shard file for it.
    let opensChannels: Bool
    let live: Int?
}

struct ComposedMap: Sendable {
    let viewBox: ViewBox
    let regions: [MapRegion]
}

// MARK: - Rules

enum RegionMapRules {
    /// The site's paintableFill (kj-regionmap.js): a data colour whose relative luminance (sRGB,
    /// WCAG) is under 0.06 is near-black and is painted in the second green; any other colour is
    /// left to be the first. A colour that is not 3 or 6 hex digits, and no colour at all, is left
    /// alone too.
    static func fill(forData color: String?) -> MapFill {
        guard let color, let rgb = hexChannels(color) else { return .deep }
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
        return luminance < 0.06 ? .tint : .deep
    }

    /// "#RRGGBB" or "#RGB", the hash optional, as red, green and blue in 0...1. Nil for anything else.
    private static func hexChannels(_ text: String) -> [Double]? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        var nibbles: [Int] = []
        for byte in digits.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): nibbles.append(Int(byte) - 48)
            case UInt8(ascii: "a")...UInt8(ascii: "f"): nibbles.append(Int(byte) - 87)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): nibbles.append(Int(byte) - 55)
            default: return nil
            }
        }
        if nibbles.count == 3 { nibbles = nibbles.flatMap { [$0, $0] } }
        guard nibbles.count == 6 else { return nil }
        return stride(from: 0, to: 6, by: 2).map { Double(nibbles[$0] * 16 + nibbles[$0 + 1]) / 255 }
    }

    /// The map the Receiver draws. Core shapes come first in file order. A core shape the receiver
    /// index tiers islamicate (hindustan and dakhan today, the site's EXT_ONLY) is an extension on
    /// the receiver: left out unless `showExtensions`, and then drawn as one (`isExtension`, the
    /// second green) where it stands in the core file, so it comes before the extended file's
    /// shapes. A core shape the index does not list is an ordinary one. The extended file's
    /// shapes follow, in file order, only when `showExtensions` is on and the file is there,
    /// filled in the second green and skipped where the id is already a core id. An umbrella
    /// (mashriq, drawn by its members), a shape with no polygon and one whose centroid is not two
    /// numbers are left out. The viewBox is the extended file's when its shapes are shown, else
    /// the core file's; nil when the one needed does not parse. Like the site, it turns on the
    /// switch alone: with no extended file the core shapes that are extensions still appear, in
    /// the core frame.
    static func compose(core: RegionShapes, extended: RegionShapes?, index: ReceiverIndex,
                        showExtensions: Bool) -> ComposedMap? {
        let extra = showExtensions ? extended : nil
        guard let viewBox = ViewBox((extra ?? core).viewBox) else { return nil }
        func indexLine(of shape: RegionShapes.Shape) -> ReceiverIndex.Region? {
            index.regions.first(where: { $0.id == shape.id })
        }
        var regions: [MapRegion] = []
        for shape in core.regions {
            let entry = indexLine(of: shape)
            let isExtension = entry?.tier == "islamicate"
            guard showExtensions || !isExtension,
                  let region = makeRegion(shape, entry: entry, isExtension: isExtension, index: index)
            else { continue }
            regions.append(region)
        }
        if let extra {
            var taken = Set(core.regions.map(\.id))
            for shape in extra.regions where !taken.contains(shape.id) {
                guard let region = makeRegion(shape, entry: indexLine(of: shape), isExtension: true, index: index) else { continue }
                taken.insert(shape.id)
                regions.append(region)
            }
        }
        return ComposedMap(viewBox: viewBox, regions: regions)
    }

    /// `entry` is the shape's line in the receiver index, nil when the index does not list it.
    private static func makeRegion(_ shape: RegionShapes.Shape, entry: ReceiverIndex.Region?, isExtension: Bool,
                                   index: ReceiverIndex) -> MapRegion? {
        guard shape.role != "umbrella", shape.centroid.count == 2, shape.centroid.allSatisfy(\.isFinite) else { return nil }
        let polygons = SVGPath.polygons(shape.path)
        guard !polygons.isEmpty else { return nil }
        // The receiver names its regions itself (Al-Sham, Jazirat al-Arab, Horn), and the website's
        // receiver map shows those names; the shape file's own label is the fallback.
        let indexLabel = entry?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = indexLabel.isEmpty ? shape.label : indexLabel
        return MapRegion(
            id: shape.id,
            label: label,
            native: nativeName(shape.native, label: label),
            polygons: polygons,
            outline: shape.refPath.map(SVGPath.polygons) ?? polygons,
            centroid: MapPoint(x: shape.centroid[0], y: shape.centroid[1]),
            fill: isExtension ? .tint : fill(forData: shape.fillColor),
            isPeople: entry?.kind == "people",
            isExtension: isExtension,
            opensChannels: index.regionFiles[shape.id] != nil,
            live: index.regionCounts[shape.id]?.live)
    }

    private static func nativeName(_ native: String?, label: String) -> String? {
        guard let name = native?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              name.caseInsensitiveCompare(label.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        else { return nil }
        return name
    }
}
