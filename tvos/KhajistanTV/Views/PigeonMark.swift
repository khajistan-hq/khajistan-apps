import ImageIO
import SwiftUI
import UIKit

// MARK: - The pigeon

/// The Khajistan pigeon, from the 1080px master, still when Reduce Motion is on. Its frames are
/// decoded once, off the main thread, at the size drawn, and played by a UIImageView, so Core
/// Animation steps them and the main thread does nothing per frame. Until 2026-10-06 each of its
/// 133 frames went through the main thread as a full 1080px picture, and the home screen ran at
/// about 32 frames a second with nothing moving on the owner's Apple TV HD ("a slow lag when I
/// scroll").
///
/// Shared with the phone (ios/ links this file): decoded at the screen's own density, so a 3x
/// iPhone is as sharp as a 2x television.
struct PigeonMark: View {
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        PigeonFrames(pixels: Int(size * max(displayScale, 1)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PigeonFrames: UIViewRepresentable {
    let pixels: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        Task { @MainActor in
            let frames = await PigeonFrameCache.shared.frames(pixels: pixels)
            guard let first = frames.images.first else { return }
            if reduceMotion || UIAccessibility.isReduceMotionEnabled {
                view.image = first
            } else {
                view.image = UIImage.animatedImage(with: frames.images, duration: frames.duration)
            }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}

    /// The size it is given, never the picture's own: a UIImageView reports its image's size and
    /// drew the 72pt mark at the frames' pixel size over the wordmark.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 72, height: proposal.height ?? 72)
    }
}

/// The GIF decoded once per size, shared by every pigeon mark.
private actor PigeonFrameCache {
    static let shared = PigeonFrameCache()
    private var made: [Int: (images: [UIImage], duration: TimeInterval)] = [:]

    func frames(pixels: Int) -> (images: [UIImage], duration: TimeInterval) {
        if let hit = made[pixels] { return hit }
        guard let url = Bundle.main.url(forResource: "pigeon", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ([], 0) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            images.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.04
            duration += delay > 0.011 ? delay : 0.04
        }
        made[pixels] = (images, duration)
        return (images, duration)
    }
}
