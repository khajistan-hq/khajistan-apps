import AVFoundation
import CoreImage
import UIKit

/// The picture-in-picture window's picture: the player's own frames, with the house caption plate
/// drawn onto them while a caption is on.
///
/// AVPlayer's own window shows only the bare picture, so the house caption view (CaptionLayer) never
/// reached it, and a programme's prepared WebVTT file never could (owner, 2026-11-17: "pip still not
/// showing subtitles in skin"). Frames are copied off the item with AVPlayerItemVideoOutput, which
/// works on HLS, the caption is composited with Core Image, and the result is shown on an
/// AVSampleBufferDisplayLayer, which the window then carries. The sound stays AVPlayer's.
///
/// The timer runs on its own queue, not a display link, so the picture keeps moving while the app
/// is in the background and the window floats over another app.
final class PiPFramePump {
    let layer = AVSampleBufferDisplayLayer()

    struct Caption: Equatable {
        var text: String
        var skin: Skin
    }

    private let queue = DispatchQueue(label: "com.khajistan.tv.pip-frames", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    // Shared with the queue, under `lock`.
    private var output: AVPlayerItemVideoOutput?
    private var caption: Caption?
    private var windowWidth: CGFloat = 0
    private var framesShown = 0
    // The queue's own.
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var overlay: (key: String, image: CIImage)?
    private var pool: (width: Int, height: Int, pool: CVPixelBufferPool)?
    private var format: CMVideoFormatDescription?
    // The main thread's own.
    private weak var outputItem: AVPlayerItem?

    private static let pixelFormat = kCVPixelFormatType_32BGRA

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    deinit { timer?.cancel() }

    /// Frames put on the layer since `follow` began. tvOS opens the window from what it shows.
    var frames: Int { lock.withLock { framesShown } }

    /// Starts copying frames off `player`'s item. Called again whenever the item may have changed
    /// (a Transmission handover), it moves the output to the new item.
    @MainActor func follow(_ player: AVPlayer) {
        if let item = player.currentItem, item !== outputItem {
            let made = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Self.pixelFormat,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ])
            if let old = outputItem, let previous = lock.withLock({ output }) { old.remove(previous) }
            item.add(made)
            outputItem = item
            lock.withLock { output = made }
        }
        guard timer == nil else { return }
        lock.withLock { framesShown = 0 }
        let source = DispatchSource.makeTimerSource(queue: queue)
        // Polled at 60 Hz: a 24 or 25 fps picture is taken on the tick after each new frame.
        source.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    /// The caption to draw, nil for none. Read by the next frame.
    func show(_ caption: Caption?) { lock.withLock { self.caption = caption } }

    /// The window's width in pixels, as tvOS reports it, so the type is sized for the window.
    func windowDidResize(width: CGFloat) { lock.withLock { windowWidth = width } }

    /// Stops copying and lets go of the item, and clears the layer.
    @MainActor func stop() {
        timer?.cancel()
        timer = nil
        if let item = outputItem, let previous = lock.withLock({ output }) { item.remove(previous) }
        outputItem = nil
        lock.withLock { output = nil; caption = nil; framesShown = 0 }
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    // MARK: - The queue

    private func tick() {
        let (output, caption, windowWidth) = lock.withLock { (self.output, self.caption, self.windowWidth) }
        guard let output else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let shown = caption.flatMap { compose(frame, caption: $0, windowWidth: windowWidth) } ?? frame
        enqueue(shown)
    }

    private func enqueue(_ buffer: CVPixelBuffer) {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        guard renderer.isReadyForMoreMediaData, let sample = sampleBuffer(buffer) else { return }
        renderer.enqueue(sample)
        lock.withLock { framesShown += 1 }
    }

    private func sampleBuffer(_ buffer: CVPixelBuffer) -> CMSampleBuffer? {
        if format.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: buffer) }) ?? true {
            var made: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &made) == noErr
            else { return nil }
            format = made
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // No timebase on the layer: each frame is shown as it arrives, which is when AVPlayer had it.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    /// The frame with the caption plate drawn on, in a new buffer. Nil if a buffer could not be had,
    /// in which case the bare frame is shown rather than none.
    private func compose(_ frame: CVPixelBuffer, caption: Caption, windowWidth: CGFloat) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
        guard width > 0, height > 0,
              let plate = plateImage(caption, width: width, height: height, windowWidth: windowWidth),
              let out = buffer(width: width, height: height) else { return nil }
        context.render(plate.composited(over: CIImage(cvPixelBuffer: frame)), to: out)
        return out
    }

    private func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool?.width != width || pool?.height != height {
            var made: CVPixelBufferPool?
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Self.pixelFormat,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &made)
            guard let made else { return nil }
            pool = (width, height, made)
        }
        var out: CVPixelBuffer?
        guard let pool else { return nil }
        CVPixelBufferPoolCreatePixelBuffer(nil, pool.pool, &out)
        return out
    }

    /// The plate as an image the frame's size, transparent but for the plate. Drawn once per
    /// caption and kept while the same caption shows.
    private func plateImage(_ caption: Caption, width: Int, height: Int, windowWidth: CGFloat) -> CIImage? {
        let key = "\(caption.text)\u{1F}\(caption.skin)\u{1F}\(width)x\(height)\u{1F}\(Int(windowWidth))"
        if let overlay, overlay.key == key { return overlay.image }
        guard let made = Self.plate(caption, frame: CGSize(width: width, height: height), windowWidth: windowWidth) else { return nil }
        overlay = (key, made)
        return made
    }

    /// The caption plate drawn on a transparent frame-sized image (also used by the DEBUG proof).
    static func plate(_ caption: Caption, frame: CGSize, windowWidth: CGFloat) -> CIImage? {
        let size = PiPCaptionLayout.fontSize(frameWidth: frame.width, windowWidth: windowWidth)
        guard size > 0, !CaptionText.lines(caption.text).isEmpty else { return nil }
        let text = attributed(caption, fontSize: size)
        let measured = text.boundingRect(with: CGSize(width: PiPCaptionLayout.textWidth(frameWidth: frame.width),
                                                      height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let textSize = CGSize(width: ceil(measured.width), height: ceil(measured.height))
        let (plate, textRect) = PiPCaptionLayout.plate(text: textSize, fontSize: size, frame: frame)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: frame, format: format).image { drawing in
            UIColor(rgb: caption.skin.captionPlateHex).setFill()
            drawing.fill(plate)
            text.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }

    /// The caption as CaptionView sets it: semibold system type, centred, each line on its own
    /// direction so Urdu, Persian and Arabic read right to left.
    static func attributed(_ caption: Caption, fontSize: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let colour = UIColor(rgb: caption.skin.captionTextHex)
        let out = NSMutableAttributedString()
        let lines = CaptionText.lines(caption.text)
        for (index, line) in lines.enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.baseWritingDirection = CaptionText.isRightToLeft(line) ? .rightToLeft : .leftToRight
            paragraph.lineSpacing = PiPCaptionLayout.lineSpacing(fontSize: fontSize)
            paragraph.paragraphSpacing = PiPCaptionLayout.lineSpacing(fontSize: fontSize)
            out.append(NSAttributedString(string: index + 1 < lines.count ? line + "\n" : line,
                                          attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph]))
        }
        return out
    }
}

private extension UIColor {
    convenience init(rgb hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
