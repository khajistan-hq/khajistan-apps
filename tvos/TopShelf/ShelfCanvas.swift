import CoreGraphics
import CoreText
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
private typealias SystemFont = UIFont
#else
import AppKit
private typealias SystemFont = NSFont
#endif

/// One opaque bitmap drawn in points, top-down, at `scale` pixels per point. The Top Shelf's
/// pictures are drawn on it twice: by the extension at run time and, for the static images, by
/// scripts/make-top-shelf.sh on the Mac. It only knows CoreGraphics and CoreText, so the two agree.
struct ShelfCanvas {
    enum Weight { case black, semibold, regular }
    enum Align { case left, center, right }

    let context: CGContext
    /// The size in points.
    let size: CGSize
    let scale: CGFloat

    init?(width: CGFloat, height: CGFloat, scale: CGFloat, ground: UInt32) {
        let pixelsWide = Int((width * scale).rounded()), pixelsHigh = Int((height * scale).rounded())
        guard pixelsWide > 0, pixelsHigh > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        // Points, top-down.
        ctx.translateBy(x: 0, y: CGFloat(pixelsHigh))
        ctx.scaleBy(x: scale, y: -scale)
        context = ctx
        size = CGSize(width: width, height: height)
        self.scale = scale
        fill(CGRect(origin: .zero, size: size), ground)
    }

    static func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    func fill(_ rect: CGRect, _ hex: UInt32, alpha: CGFloat = 1) {
        context.setFillColor(Self.colour(hex, alpha))
        context.fill(rect)
    }

    /// An image fitted whole into `rect`, keeping its proportions, centred.
    func draw(_ image: CGImage, fitting rect: CGRect) {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var box = rect
        if rect.width / rect.height > aspect {
            box.size.width = rect.height * aspect
            box.origin.x = rect.midX - box.width / 2
        } else {
            box.size.height = rect.width / aspect
            box.origin.y = rect.midY - box.height / 2
        }
        context.saveGState()
        context.translateBy(x: box.minX, y: box.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: box.size))
        context.restoreGState()
    }

    // MARK: Type

    static func font(_ size: CGFloat, _ weight: Weight) -> CTFont {
        let w: SystemFont.Weight
        switch weight {
        case .black: w = .black
        case .semibold: w = .semibold
        case .regular: w = .regular
        }
        return SystemFont.systemFont(ofSize: size, weight: w) as CTFont
    }

    static func line(_ string: String, size: CGFloat, weight: Weight, em: CGFloat, hex: UInt32, alpha: CGFloat = 1) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size, weight),
            NSAttributedString.Key(kCTKernAttributeName as String): size * em,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour(hex, alpha),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// One line of type whose cap height starts at `top`. Wider than `maxWidth`, it is set smaller,
    /// down to 60% (SwiftUI's minimumScaleFactor in the app); still wider, it is cut with an ellipsis.
    /// Returns the box it took: x and width as set, y from `top` to the baseline plus descent.
    @discardableResult
    func text(_ string: String, size: CGFloat, weight: Weight, em: CGFloat = 0, hex: UInt32, alpha: CGFloat = 1,
              x: CGFloat, top: CGFloat, align: Align = .left, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGRect {
        var setSize = size
        var line = Self.line(string, size: setSize, weight: weight, em: em, hex: hex, alpha: alpha)
        let natural = Self.width(of: line)
        if natural > maxWidth {
            setSize = max(size * 0.6, size * maxWidth / natural)
            line = Self.line(string, size: setSize, weight: weight, em: em, hex: hex, alpha: alpha)
            if Self.width(of: line) > maxWidth {
                let ellipsis = Self.line("\u{2026}", size: setSize, weight: weight, em: em, hex: hex, alpha: alpha)
                line = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis) ?? line
            }
        }
        return place(line, size: setSize, x: x, top: top, align: align)
    }

    /// Words wrapped onto at most `maxLines` lines of `width`, the last cut with an ellipsis.
    /// Returns the bottom of the last line.
    @discardableResult
    func paragraph(_ string: String, size: CGFloat, weight: Weight, em: CGFloat = 0, hex: UInt32, alpha: CGFloat = 1,
                   x: CGFloat, top: CGFloat, width: CGFloat, leading: CGFloat = 1.25, maxLines: Int = 3, align: Align = .left) -> CGFloat {
        var lines: [String] = []
        var current = ""
        for word in string.split(separator: " ") {
            let trial = current.isEmpty ? String(word) : current + " " + word
            if Self.width(of: Self.line(trial, size: size, weight: weight, em: em, hex: hex)) <= width || current.isEmpty {
                current = trial
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines - 1)) + [lines.dropFirst(maxLines - 1).joined(separator: " ")]
        }
        var bottom = top
        for (i, text) in lines.enumerated() {
            bottom = self.text(text, size: size, weight: weight, em: em, hex: hex, alpha: alpha,
                               x: x, top: top + CGFloat(i) * size * leading, align: align, maxWidth: width).maxY
        }
        return bottom
    }

    private func place(_ line: CTLine, size: CGFloat, x: CGFloat, top: CGFloat, align: Align) -> CGRect {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let font = Self.font(size, .regular)
        let cap = CTFontGetCapHeight(font)
        let left: CGFloat
        switch align {
        case .left: left = x
        case .center: left = x - width / 2
        case .right: left = x - width
        }
        let baseline = top + cap
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: left, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
        return CGRect(x: left, y: top, width: width, height: cap + descent)
    }

    // MARK: Output

    func png() -> Data? {
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - The map

extension ShelfCanvas {
    /// The receiver's map as the app draws it (RegionMapView), without its labels: the two greens,
    /// the people's regions hatched, regions that open nothing at 48%, extensions at 50%, the
    /// ground between neighbours. `highlight` is outlined in yellow. Fitted whole into `rect`.
    /// Returns where a viewBox point lands, so a caller can place a label at a centroid.
    @discardableResult
    func map(_ map: ComposedMap, in rect: CGRect, skin: Skin, highlight: String? = nil) -> (MapPoint) -> CGPoint {
        let box = map.viewBox
        let s = min(rect.width / CGFloat(box.width), rect.height / CGFloat(box.height))
        let ox = rect.midX - CGFloat(box.width) * s / 2 - CGFloat(box.minX) * s
        let oy = rect.midY - CGFloat(box.height) * s / 2 - CGFloat(box.minY) * s
        let ctx = context
        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy)
        ctx.scaleBy(x: s, y: s)
        let paths = map.regions.map { Self.path($0.polygons) }
        for (region, path) in zip(map.regions, paths) {
            let alpha: CGFloat = region.isExtension ? 0.5 : (region.opensChannels ? 1 : 0.48)
            ctx.setFillColor(Self.colour(region.fill == .deep ? skin.mapDeepHex : Skin.mapTintHex, alpha))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            if region.isPeople { hatch(path) }
        }
        ctx.setStrokeColor(Self.colour(skin.groundHex))
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        for path in paths {
            ctx.addPath(path)
            ctx.strokePath()
        }
        if let highlight, let region = map.regions.first(where: { $0.id == highlight }) {
            ctx.setStrokeColor(Self.colour(Skin.onBandHex))
            ctx.setLineWidth(3.5)
            ctx.addPath(Self.path(region.outline))
            ctx.strokePath()
        }
        ctx.restoreGState()
        return { CGPoint(x: ox + CGFloat($0.x) * s, y: oy + CGFloat($0.y) * s) }
    }

    private static func path(_ polygons: [[MapPoint]]) -> CGPath {
        let path = CGMutablePath()
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in polygon.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
        return path
    }

    /// The website's hatch, as RegionMapView draws it: 3.2-unit black stripes at 32%, 9 units apart
    /// at 45 degrees, clipped to the shape.
    private func hatch(_ shape: CGPath) {
        let ctx = context
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip(using: .evenOdd)
        let bounds = shape.boundingBoxOfPath
        let root2 = 2.0.squareRoot(), reach = 9 * root2
        let low = Double(bounds.minY - bounds.maxX), high = Double(bounds.maxY - bounds.minX)
        var tile = Int((low / reach).rounded(.down)) - 1
        while true {
            let b = CGFloat(root2 * (9 * Double(tile) + 1.6))
            if Double(b) > high + reach { break }
            ctx.move(to: CGPoint(x: bounds.minX - 10, y: bounds.minX - 10 + b))
            ctx.addLine(to: CGPoint(x: bounds.maxX + 10, y: bounds.maxX + 10 + b))
            tile += 1
        }
        ctx.setStrokeColor(Self.colour(0x000000, 0.32))
        ctx.setLineWidth(3.2)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
