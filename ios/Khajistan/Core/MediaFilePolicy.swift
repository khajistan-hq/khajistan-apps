import Foundation

/// Ordinary browser files are separate from protected films. This is a defense against known
/// media paths/formats, not DRM or a content classifier. Licensed offline assets must NEVER
/// enter this generic file path, even under a document name.
enum MediaFilePolicy {
    static let message = "Films play inside Khajistan. Video files cannot be downloaded or shared from the browser."
    private static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "mpg", "mpeg", "m2v", "ts", "m2ts",
        "m3u8", "m3u", "mpd", "movpkg", "m4s", "key", "ckc", "spc", "flv", "ogv"
    ]

    static func isMediaURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host == "videodelivery.net" || host.hasSuffix(".videodelivery.net")
            || host == "cloudflarestream.com" || host.hasSuffix(".cloudflarestream.com")
            || mediaExtensions.contains(url.pathExtension.lowercased())
            || path.contains("/functions/v1/vod-") || path.contains("/functions/v1/screening-access")
    }

    static func isFilmPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path == "/film" || path.hasPrefix("/film/") || path == "/film.html"
            || path.hasPrefix("/screening-room") || isMediaURL(url)
    }

    static func allowsBrowserDownload(url: URL?, page: URL?, mime: String?, filename: String) -> Bool {
        guard !isFilmPage(page), let url, ["https", "blob"].contains(url.scheme?.lowercased() ?? ""), !isMediaURL(url),
              !mediaExtensions.contains((filename as NSString).pathExtension.lowercased()) else { return false }
        let type = (mime ?? "").lowercased().split(separator: ";").first.map(String.init) ?? ""
        return !type.hasPrefix("video/") && !["application/vnd.apple.mpegurl", "application/x-mpegurl",
            "audio/mpegurl", "audio/x-mpegurl", "application/dash+xml"].contains(type)
    }

    /// Applies to existing downloads too, retaining ordinary books, images and documents.
    static func canPreviewOrExport(_ file: URL) -> Bool {
        guard file.isFileURL, let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 512) else { return false }
        return hasExportableHeader(bytes, extension: file.pathExtension)
    }

    static func hasExportableHeader(_ bytes: Data, extension ext: String) -> Bool {
        guard !mediaExtensions.contains(ext.lowercased()) else { return false }
        // ISO base media/QuickTime, Matroska/WebM, AVI, MPEG PS/TS and FLV.
        let tag = String(decoding: bytes.dropFirst(4).prefix(4), as: UTF8.self)
        if ["ftyp", "moov", "mdat", "wide"].contains(tag) { return false }
        if bytes.starts(with: [0x1a, 0x45, 0xdf, 0xa3]) || bytes.starts(with: [0, 0, 1, 0xba]) { return false }
        if bytes.starts(with: Data("FLV".utf8)) { return false }
        if bytes.starts(with: Data("RIFF".utf8)), String(decoding: bytes.dropFirst(8).prefix(4), as: UTF8.self) == "AVI " { return false }
        if bytes.count > 188, bytes[bytes.startIndex] == 0x47, bytes[bytes.startIndex + 188] == 0x47 { return false }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#EXTM3U") || text.contains("<MPD") { return false }
        return true
    }
}
