import SwiftUI
import UIKit

/// The receiver's map, drawn as the website draws it at /open-frequencies: the shapes from the
/// shape files in the two house greens, the people's regions hatched, regions with no channels
/// dimmed, labels in yellow with a black halo, and the focused region outlined with its label on
/// a yellow plate. One Canvas draws all of it. The map is a picture, not a control: the remote
/// walks the strip of regions under it (ReceiverView), because tvOS moves focus only to a target
/// lying straight along the press, and from most labels on a map there is none. On the owner's
/// Apple TV focus stuck on one region (2026-10-05).
struct RegionMapView: View {
    let map: ComposedMap
    /// The region the strip under the map has focus on: outlined, with its label on a plate.
    let highlighted: String?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let key = RegionMapLayout.key(map, size: proxy.size)
            let layout = RegionMapLayout.cached(map, size: proxy.size, key: key)
            ZStack {
                // The map itself is drawn once and kept as one picture; moving focus along the
                // strip redraws only the outline and the plate on top (2026-10-06: every step
                // redrew every shape, hatch and haloed label, about one late frame per step on
                // the owner's Apple TV HD).
                RegionMapBase(map: map, layout: layout, palette: palette, key: key, skin: palette.ground.description)
                    .equatable()
                Canvas { context, _ in
                    RegionMapPainter(map: map, layout: layout, palette: palette, focusedID: highlighted, mode: .focus).paint(&context)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RegionMapBase: View, Equatable {
    let map: ComposedMap
    let layout: RegionMapLayout
    let palette: Palette
    let key: String
    let skin: String

    static func == (a: Self, b: Self) -> Bool { a.key == b.key && a.skin == b.skin }

    var body: some View {
        Canvas { context, _ in
            RegionMapPainter(map: map, layout: layout, palette: palette, focusedID: nil, mode: .base).paint(&context)
        }
        .drawingGroup()
    }
}

// MARK: - Type

/// One size and weight of map type, in the two forms that must agree: SwiftUI's, which draws it
/// in the Canvas, and UIKit's, which measures it outside the Canvas so the focus buttons can be
/// placed over the labels before anything is drawn.
private struct MapFace {
    let size: CGFloat
    let weight: Font.Weight
    let uiWeight: UIFont.Weight
    let em: CGFloat

    /// The website's main label, scaled for a television; `crowded` is the size it falls back to.
    static let label = MapFace(size: 18, weight: .black, uiWeight: .black, em: 0.01)
    static let crowded = MapFace(size: 15, weight: .black, uiWeight: .black, em: 0.01)
    /// The three lines of the plate under the focused region.
    static let plateName = MapFace(size: 26, weight: .black, uiWeight: .black, em: 0.01)
    static let plateNative = MapFace(size: 24, weight: .semibold, uiWeight: .semibold, em: 0)
    static let plateLive = MapFace(size: 24, weight: .black, uiWeight: .black, em: 0.05)

    func text(_ string: String) -> Text {
        Text(string).font(.system(size: size, weight: weight)).tracking(size * em)
    }

    func measure(_ string: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: uiWeight),
            .kern: size * em,
        ]
        let box = (string as NSString).size(withAttributes: attributes)
        return CGSize(width: ceil(box.width), height: ceil(box.height))
    }
}

// MARK: - Layout

private struct RegionMapLabel: Identifiable {
    let region: MapRegion
    let text: String
    let face: MapFace
    let center: CGPoint
    let box: CGSize
    /// False for a label with no clear place on the map. It is not drawn there; its region is
    /// still a focus target, and focus puts the name on the plate.
    let isDrawn: Bool

    var id: String { region.id }
}

/// Where the map sits in its frame, and where each label stands. A value, so the Canvas and the
/// focus buttons are built from the same answer.
private struct RegionMapLayout {
    /// Measuring every label is the costly part; a map at a size is laid out once.
    @MainActor private static var cache: [String: RegionMapLayout] = [:]

    static func key(_ map: ComposedMap, size: CGSize) -> String {
        "\(map.regions.map(\.id).joined(separator: ","))|\(Int(size.width))x\(Int(size.height))"
    }

    @MainActor static func cached(_ map: ComposedMap, size: CGSize, key: String) -> RegionMapLayout {
        if let hit = cache[key] { return hit }
        let made = RegionMapLayout(map: map, size: size)
        if cache.count > 8 { cache.removeAll() }
        cache[key] = made
        return made
    }

    let size: CGSize
    /// Points per viewBox unit. The viewBox is fitted whole into the frame and centred.
    let scale: CGFloat
    /// Where viewBox (0, 0) lands in the frame.
    let offset: CGPoint
    let labels: [RegionMapLabel]

    init(map: ComposedMap, size: CGSize) {
        self.size = size
        let box = map.viewBox
        guard size.width > 0, size.height > 0 else {
            scale = 0
            offset = .zero
            labels = []
            return
        }
        let scale = min(size.width / CGFloat(box.width), size.height / CGFloat(box.height))
        let offset = CGPoint(
            x: (size.width - CGFloat(box.width) * scale) / 2 - CGFloat(box.minX) * scale,
            y: (size.height - CGFloat(box.height) * scale) / 2 - CGFloat(box.minY) * scale
        )
        self.scale = scale
        self.offset = offset
        labels = Self.place(map.regions, scale: scale, offset: offset, bounds: size)
    }

    /// Labels for every region that opens channels and for the people's regions, at their
    /// centroids. Regions that open channels go first, the busiest first, so when two labels
    /// would sit on each other the quieter one is the one that moves: down then up by its own
    /// height and a margin, then twice that, and if it still lands on another it is drawn smaller.
    /// One that has no clear place even then is left off the map, as the website's extended atlas
    /// leaves off names that do not fit ("too messy", owner, 2026-09-06): focus shows it.
    private static func place(_ regions: [MapRegion], scale: CGFloat, offset: CGPoint, bounds: CGSize) -> [RegionMapLabel] {
        let wanted = regions.enumerated().filter { $0.element.opensChannels || $0.element.isPeople }
        let ordered = wanted.sorted { a, b in
            if a.element.opensChannels != b.element.opensChannels { return a.element.opensChannels }
            let liveA = a.element.live ?? 0
            let liveB = b.element.live ?? 0
            if liveA != liveB { return liveA > liveB }
            return a.offset < b.offset
        }

        var taken: [CGRect] = []
        var placed: [RegionMapLabel] = []
        for (_, region) in ordered {
            let text = region.label.uppercased()
            let anchor = CGPoint(
                x: offset.x + CGFloat(region.centroid.x) * scale,
                y: offset.y + CGFloat(region.centroid.y) * scale
            )
            var chosen: RegionMapLabel?
            search: for face in [MapFace.label, MapFace.crowded] {
                let box = face.measure(text)
                for nudge in [0, 1, -1, 2, -2] as [CGFloat] {
                    let center = inside(CGPoint(x: anchor.x, y: anchor.y + nudge * (box.height + 6)), box: box, bounds: bounds)
                    if !taken.contains(where: { $0.intersects(footprint(center: center, box: box, face: face)) }) {
                        chosen = RegionMapLabel(region: region, text: text, face: face, center: center, box: box, isDrawn: true)
                        break search
                    }
                }
            }
            if let chosen {
                taken.append(footprint(center: chosen.center, box: chosen.box, face: chosen.face))
                placed.append(chosen)
            } else {
                // Nowhere clear, at either size. Moving it far enough to be clear would name the
                // wrong region, and drawing it on another label would spoil both, so it is left
                // off. It takes no room from the others, and if its region opens channels the
                // focus target stays where the region is and focus puts the name on the plate.
                let box = MapFace.crowded.measure(text)
                placed.append(RegionMapLabel(
                    region: region, text: text, face: .crowded, center: inside(anchor, box: box, bounds: bounds),
                    box: box, isDrawn: false
                ))
            }
        }
        return placed
    }

    func point(_ p: MapPoint) -> CGPoint {
        CGPoint(x: offset.x + CGFloat(p.x) * scale, y: offset.y + CGFloat(p.y) * scale)
    }

    /// The region's own extent on screen. Null when it has no points.
    func extent(of region: MapRegion) -> CGRect {
        var extent = CGRect.null
        for polygon in region.polygons {
            for p in polygon {
                let q = point(p)
                extent = extent.union(CGRect(x: q.x, y: q.y, width: 0, height: 0))
            }
        }
        return extent
    }

    /// What a label keeps clear: its capitals, the black halo round them and a little air. The
    /// box the text is measured in is taller than its capitals (about 74% of the size), and every
    /// name on the map is set in capitals, so measuring the whole line would turn away labels
    /// that fit.
    private static func footprint(center: CGPoint, box: CGSize, face: MapFace) -> CGRect {
        let width = box.width + 8
        let height = face.size * 0.74 + 8
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// `center`, moved if need be so a box of this size stays inside the frame.
    private static func inside(_ center: CGPoint, box: CGSize, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(center.x, box.width / 2), max(bounds.width - box.width / 2, box.width / 2)),
            y: min(max(center.y, box.height / 2), max(bounds.height - box.height / 2, box.height / 2))
        )
    }
}

// MARK: - Painting

private struct RegionMapPainter {
    let map: ComposedMap
    let layout: RegionMapLayout
    let palette: Palette
    let focusedID: String?
    /// The map (shapes and every label), or only what focus adds over it (outline and plate).
    let mode: Mode

    enum Mode { case base, focus }

    func paint(_ context: inout GraphicsContext) {
        guard layout.scale > 0 else { return }
        switch mode {
        case .base:
            paintShapes(context)
            paintLabels(context)
        case .focus:
            paintOutline(context)
            if let focusedID, let label = layout.labels.first(where: { $0.region.id == focusedID }) {
                paintPlate(for: label, in: context)
            }
        }
    }

    private func paintOutline(_ context: GraphicsContext) {
        guard let focusedID, let region = map.regions.first(where: { $0.id == focusedID }) else { return }
        var world = context
        world.translateBy(x: layout.offset.x, y: layout.offset.y)
        world.scaleBy(x: layout.scale, y: layout.scale)
        world.stroke(
            Self.path(region.outline), with: .color(palette.onBand),
            style: StrokeStyle(lineWidth: 3.5, lineJoin: .round)
        )
    }

    // MARK: Shapes, drawn in viewBox units

    private func paintShapes(_ context: GraphicsContext) {
        var world = context
        world.translateBy(x: layout.offset.x, y: layout.offset.y)
        world.scaleBy(x: layout.scale, y: layout.scale)

        let shapes = map.regions.map { Self.path($0.polygons) }
        let evenOdd = FillStyle(eoFill: true)

        for (region, shape) in zip(map.regions, shapes) {
            var layer = world
            layer.opacity = Self.opacity(of: region)
            layer.fill(shape, with: .color(region.fill == .deep ? palette.mapDeep : palette.mapTint), style: evenOdd)
            if region.isPeople { Self.hatch(shape, in: layer) }
        }

        // The page ground between neighbours, drawn once every fill is down so no fill covers it.
        let gap = StrokeStyle(lineWidth: 1.2, lineJoin: .round)
        for shape in shapes {
            world.stroke(shape, with: .color(palette.ground), style: gap)
        }

    }

    /// An extension is half there, and so is a region that opens nothing.
    private static func opacity(of region: MapRegion) -> Double {
        if region.isExtension { return 0.5 }
        return region.opensChannels ? 1 : 0.48
    }

    private static func path(_ polygons: [[MapPoint]]) -> Path {
        var path = Path()
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in polygon.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            path.closeSubpath()
        }
        return path
    }

    /// The website's hatch: a 9-unit tile turned 45 degrees with a 3.2-unit black stripe at 32%,
    /// so stripes lie 9 units apart square on, and their phase is the same on every shape. They
    /// are laid across the shape's bounds and clipped to the shape.
    private static func hatch(_ shape: Path, in layer: GraphicsContext) {
        var clipped = layer
        clipped.clip(to: shape, style: FillStyle(eoFill: true))
        let bounds = shape.boundingRect
        let root2 = 2.0.squareRoot()
        let reach = 9 * root2
        // Each stripe is the line y = x + b, and b runs over every value that crosses the bounds.
        let low = Double(bounds.minY - bounds.maxX)
        let high = Double(bounds.maxY - bounds.minX)
        var stripes = Path()
        var tile = Int((low / reach).rounded(.down)) - 1
        while true {
            let b = root2 * (9 * Double(tile) + 1.6)
            if b > high + reach { break }
            stripes.move(to: CGPoint(x: bounds.minX - 10, y: bounds.minX - 10 + b))
            stripes.addLine(to: CGPoint(x: bounds.maxX + 10, y: bounds.maxX + 10 + b))
            tile += 1
        }
        clipped.stroke(stripes, with: .color(.black.opacity(0.32)), lineWidth: 3.2)
    }

    // MARK: Labels, drawn in points

    private func paintLabels(_ context: GraphicsContext) {
        // Every label: the focused one's plate is drawn over it, on the layer above.
        for label in layout.labels where label.isDrawn {
            paintLabel(label, in: context)
        }
    }

    private static let haloOffsets: [CGPoint] = (0..<8).map { step in
        let angle = Double(step) * Double.pi / 4
        return CGPoint(x: 2 * cos(angle), y: 2 * sin(angle))
    }

    private func paintLabel(_ label: RegionMapLabel, in context: GraphicsContext) {
        let resolved = context.resolve(label.face.text(label.text))
        if label.region.isPeople {
            // A people's region is a facet, not a place to tune: its name is dimmed, no halo.
            var dimmed = resolved
            dimmed.shading = .color(.black.opacity(0.82))
            context.draw(dimmed, at: label.center, anchor: .center)
            return
        }
        var halo = resolved
        halo.shading = .color(.black)
        for offset in Self.haloOffsets {
            context.draw(halo, at: CGPoint(x: label.center.x + offset.x, y: label.center.y + offset.y), anchor: .center)
        }
        var face = resolved
        face.shading = .color(palette.onBand)
        context.draw(face, at: label.center, anchor: .center)
    }

    /// The website's callout: the name, the native name and the live count in black on yellow.
    private func paintPlate(for label: RegionMapLabel, in context: GraphicsContext) {
        let region = label.region
        var rows: [(face: MapFace, string: String, size: CGSize)] = []
        rows.append((.plateName, label.text, MapFace.plateName.measure(label.text)))
        if let native = region.native {
            rows.append((.plateNative, native, MapFace.plateNative.measure(native)))
        }
        if let live = region.live {
            let line = "\(live.formatted()) LIVE"
            rows.append((.plateLive, line, MapFace.plateLive.measure(line)))
        }

        let across: CGFloat = 14
        let down: CGFloat = 10
        let gap: CGFloat = 3
        let width = (rows.map { $0.size.width }.max() ?? 0) + 2 * across
        let height = rows.reduce(2 * down) { $0 + $1.size.height } + gap * CGFloat(rows.count - 1)
        // Centred on the label. A region smaller than its plate would be buried under it, outline
        // and all, so there the plate stands just above the region, or below when the map has no
        // room above. Either way it is moved in if it would run off the map.
        var plate = CGRect(x: label.center.x - width / 2, y: label.center.y - height / 2, width: width, height: height)
        let extent = layout.extent(of: region)
        if !extent.isNull, width > 0.6 * extent.width || height > 0.6 * extent.height {
            let above = plate.offsetBy(dx: 0, dy: extent.minY - 6 - plate.maxY)
            let below = plate.offsetBy(dx: 0, dy: extent.maxY + 6 - plate.minY)
            if above.minY >= 0 {
                plate = above
            } else if below.maxY <= layout.size.height {
                plate = below
            }
        }
        plate.origin.x = min(max(plate.minX, 0), max(layout.size.width - width, 0))
        plate.origin.y = min(max(plate.minY, 0), max(layout.size.height - height, 0))
        context.fill(Path(plate), with: .color(palette.onBand))

        var top = plate.minY + down
        for row in rows {
            var text = context.resolve(row.face.text(row.string))
            text.shading = .color(.black)
            context.draw(text, at: CGPoint(x: plate.midX, y: top), anchor: .top)
            top += row.size.height + gap
        }
    }
}
