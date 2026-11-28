import AVFoundation
import CoreGraphics
import UIKit

/// Draws the house caption plate into a file programme's frames while it plays in the
/// picture-in-picture window.
///
/// tvOS opens the window only on an AVPlayerLayer: a window fed from the app's own frames
/// (AVSampleBufferDisplayLayer) is never "possible" on Apple TV (Apple TV HD, 2026-11-17: possible
/// false with frames on screen; the same on every tvOS since 15, jazzychad/PiPBugDemo). The house
/// caption view stays with the closed screen, so the plate goes into the picture itself, through
/// the item's video composition, which the window shows. Seen on the Apple TV HD the same day:
/// the plate in the window, in the skin's colours.
///
/// Only a file plays through a video composition; a stream (HLS) does not, and carries its
/// subtitles as a track that tvOS draws itself in the skin's colours (RecordedSubtitles.handOff).
/// A frame with no caption is passed through untouched; with one, it is copied and the plate drawn
/// over its own rectangle, on the CPU, so nothing here needs the GPU while the app is in the background.
final class HouseCaptionCompositor: NSObject, AVVideoCompositing {
    struct Caption: Equatable {
        var text: String
        var skin: Skin
        /// The viewer's choice: the plate, or yellow text with a black edge (CaptionStyle).
        var style: CaptionStyle = .current
    }

    /// The caption to draw now, nil for none. ponytail: one shared caption, as there is one window
    /// at a time; per-window captions need the composition's instruction to carry one.
    static func show(_ caption: Caption?) { lock.withLock { current = caption } }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: Caption?

    private let cacheLock = NSLock()
    private var plate: (key: String, image: CGImage, rect: CGRect)?

    var sourcePixelBufferAttributes: [String: any Sendable]? { [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let track = request.sourceTrackIDs.first?.int32Value, let source = request.sourceFrame(byTrackID: track) else {
            request.finish(with: NSError(domain: "HouseCaptionCompositor", code: 1))
            return
        }
        guard let caption = Self.lock.withLock({ Self.current }), let out = request.renderContext.newPixelBuffer(),
              let plate = plate(caption, width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source)) else {
            request.finish(withComposedVideoFrame: source)
            return
        }
        // A frame that could not be copied is passed through as it came, not drawn on a blank one.
        guard Self.copy(source, into: out) else {
            request.finish(withComposedVideoFrame: source)
            return
        }
        Self.draw(on: out) { context in
            // Core Graphics counts from the bottom; the plate's rect counts from the top.
            let height = CGFloat(CVPixelBufferGetHeight(out))
            context.draw(plate.image, in: CGRect(x: plate.rect.minX, y: height - plate.rect.maxY, width: plate.rect.width, height: plate.rect.height))
        }
        request.finish(withComposedVideoFrame: out)
    }

    /// The plate for `caption` on a frame this size, drawn once and kept while the caption shows.
    private func plate(_ caption: Caption, width: Int, height: Int) -> (key: String, image: CGImage, rect: CGRect)? {
        let key = "\(caption.text)\u{1F}\(caption.skin)\u{1F}\(caption.style)\u{1F}\(width)x\(height)"
        return cacheLock.withLock {
            if let plate, plate.key == key { return plate }
            guard let made = Self.plate(caption, frame: CGSize(width: width, height: height)) else { return nil }
            plate = (key, made.image, made.rect)
            return plate
        }
    }

    /// True when the whole picture was copied.
    private static func copy(_ source: CVPixelBuffer, into out: CVPixelBuffer) -> Bool {
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(out, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(out) else { return false }
        let fromRow = CVPixelBufferGetBytesPerRow(source), toRow = CVPixelBufferGetBytesPerRow(out)
        let rows = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(out))
        if fromRow == toRow {
            memcpy(to, from, fromRow * rows)
        } else {
            for row in 0..<rows { memcpy(to + row * toRow, from + row * fromRow, min(fromRow, toRow)) }
        }
        return true
    }

    private static func draw(on buffer: CVPixelBuffer, _ body: (CGContext) -> Void) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        body(context)
    }

    /// The plate alone, as an image its own size, and where it sits on a frame of `frame` size
    /// (origin top left). Nil for an empty caption.
    static func plate(_ caption: Caption, frame: CGSize) -> (image: CGImage, rect: CGRect)? {
        let size = PiPCaptionLayout.fontSize(frameWidth: frame.width)
        guard size > 0, !CaptionText.lines(caption.text).isEmpty else { return nil }
        let text = attributed(caption, fontSize: size)
        let measured = text.boundingRect(with: CGSize(width: PiPCaptionLayout.textWidth(frameWidth: frame.width), height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let (plate, textRect) = PiPCaptionLayout.plate(text: CGSize(width: ceil(measured.width), height: ceil(measured.height)),
                                                       fontSize: size, frame: frame)
        let bare = caption.style == .bare
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !bare
        let image = UIGraphicsImageRenderer(size: plate.size, format: format).image { drawing in
            if !bare {
                colour(caption.skin.captionPlateHex).setFill()
                drawing.fill(CGRect(origin: .zero, size: plate.size))
            }
            text.draw(with: textRect.offsetBy(dx: -plate.minX, dy: -plate.minY), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return image.cgImage.map { ($0, plate) }
    }

    /// The caption as CaptionView sets it: semibold system type, centred, each line on its own
    /// direction so Urdu, Persian and Arabic read right to left.
    static func attributed(_ caption: Caption, fontSize: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let bare = caption.style == .bare
        let ink = colour(bare ? Skin.bareCaptionHex : caption.skin.captionTextHex)
        let out = NSMutableAttributedString()
        let lines = CaptionText.lines(caption.text)
        for (index, line) in lines.enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.baseWritingDirection = CaptionText.isRightToLeft(line) ? .rightToLeft : .leftToRight
            paragraph.lineSpacing = PiPCaptionLayout.lineSpacing(fontSize: fontSize)
            paragraph.paragraphSpacing = PiPCaptionLayout.lineSpacing(fontSize: fontSize)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
            // Text only: a black edge, as the full-screen view's, so it reads on the picture.
            if bare {
                attributes[.strokeColor] = UIColor.black
                attributes[.strokeWidth] = -4.0
            }
            out.append(NSAttributedString(string: index + 1 < lines.count ? line + "\n" : line, attributes: attributes))
        }
        return out
    }

    private static func colour(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
