import ImageIO
import UIKit

/// Pictures for Pics/Vids: fetched, shrunk to what the screen can use, and kept. A picture is tried
/// at each address in turn (the site's srcCandidates), so a file that is gone does not blank a tile
/// that has a thumbnail.
final class PnvImages: @unchecked Sendable {
    static let shared = PnvImages()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        session = URLSession(configuration: config)
        cache.countLimit = 400
    }

    /// The first candidate that loads, no larger than `maxPixel` on its long side. Nil when none does
    /// or the task is cancelled. `authorization` is sent with each request (the preview gate's
    /// Basic header, for the Screening Room's posters while the site is behind it).
    func image(_ candidates: [URL], maxPixel: Int, authorization: String? = nil) async -> UIImage? {
        for url in candidates {
            if Task.isCancelled { return nil }
            let key = url as NSURL
            if let hit = cache.object(forKey: key) { return hit }
            var request = URLRequest(url: url)
            if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = Self.downsample(data, maxPixel: maxPixel) else { continue }
            cache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
