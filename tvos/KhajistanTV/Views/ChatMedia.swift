import ImageIO
import SwiftUI
import UIKit

/// The picture a chat line carries (Core/Chat.swift ChatMedia), drawn under the line in both apps
/// (ios/ links this file). A GIF plays where it stands; a Pics/Vids object shows its picture, or
/// a video's still, and opens in the Pics/Vids viewer from the line's own control.
struct ChatMediaView: View {
    let media: ChatMedia
    /// The height it is drawn at; the width follows the picture.
    let height: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?
    @State private var failed = false

    private struct Loaded {
        let frames: [UIImage]
        let duration: Double
        let isVideo: Bool
        var aspect: CGFloat {
            guard let size = frames.first?.size, size.height > 0 else { return 1 }
            return size.width / size.height
        }
    }

    var body: some View {
        Group {
            if let loaded {
                VStack(alignment: .leading, spacing: 6) {
                    ChatFrames(frames: loaded.frames, duration: loaded.duration)
                        .frame(width: height * loaded.aspect, height: height)
                    if loaded.isVideo { Kicker("Video") }
                }
            } else if failed {
                Text("The picture did not load.").kjSmall(faint: true)
            } else {
                Text("Loading the picture\u{2026}").kjSmall(faint: true)
            }
        }
        .accessibilityHidden(true)
        .task(id: media) { await load() }
    }

    private func load() async {
        let pixels = Int(height * max(displayScale, 1) * 2)
        switch media {
        case .gif(let url):
            if let gif = await ChatMediaCache.shared.gif(url, maxPixel: pixels) {
                loaded = Loaded(frames: gif.frames, duration: gif.duration, isVideo: false)
            } else { failed = true }
        case .archive(let key):
            guard let row = await ChatMediaCache.shared.row(key) else { failed = true; return }
            let candidates = row.isVideo
                ? [PnvMedia.poster(row), PnvMedia.thumb(row)].compactMap { $0 }
                : [PnvMedia.medium(row), PnvMedia.thumb(row)].compactMap { $0 }
            if let still = await PnvImages.shared.image(candidates, maxPixel: pixels) {
                loaded = Loaded(frames: [still], duration: 0, isVideo: row.isVideo)
            } else { failed = true }
        }
    }
}

/// Frames played by a UIImageView, so Core Animation steps them and the main thread does nothing
/// per frame (the same reason PigeonMark does it). Still under Reduce Motion.
private struct ChatFrames: UIViewRepresentable {
    let frames: [UIImage]
    let duration: Double
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
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if frames.count > 1, duration > 0, !reduceMotion {
            view.image = UIImage.animatedImage(with: frames, duration: duration)
        } else {
            view.image = frames.first
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

/// Rows and GIFs by key, so a room redrawn every few seconds does not ask again. A failure is not
/// kept: the next draw tries once more.
actor ChatMediaCache {
    static let shared = ChatMediaCache()

    struct Gif: @unchecked Sendable {
        let frames: [UIImage]
        let duration: Double
    }

    /// The site's GIFs are 240 px and 20 frames; these bound a file that is not.
    private static let maxBytes = 8_000_000
    private static let maxFrames = 200

    private var rows: [String: PnvRow] = [:]
    private var gifs: [String: Gif] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// The Pics/Vids object a line names, or nil when the view does not carry it.
    func row(_ key: String) async -> PnvRow? {
        if let row = rows[key] { return row }
        guard let (data, response) = try? await session.data(for: PnvAPI.rowRequest(mediaKey: key)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let row = try? JSONDecoder().decode([PnvRow].self, from: data).first
        else { return nil }
        rows[key] = row
        return row
    }

    func gif(_ url: URL, maxPixel: Int) async -> Gif? {
        let key = "\(url.absoluteString)#\(maxPixel)"
        if let gif = gifs[key] { return gif }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.maxBytes,
              let gif = Self.decode(data, maxPixel: maxPixel)
        else { return nil }
        gifs[key] = gif
        return gif
    }

    /// Every frame at no more than `maxPixel` on its long side, never larger than stored.
    static func decode(_ data: Data, maxPixel: Int) -> Gif? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ]
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: image))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            duration += ChatMedia.gifDelay(delay)
        }
        return frames.isEmpty ? nil : Gif(frames: frames, duration: duration)
    }
}
