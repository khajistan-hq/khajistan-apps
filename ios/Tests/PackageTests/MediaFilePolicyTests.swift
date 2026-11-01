import XCTest
@testable import KhajistanCore

final class MediaFilePolicyTests: XCTestCase {
    func testVideoDownloadsAreBlockedByEachIndependentSignal() {
        let safe = URL(string: "https://khajistan-archive.pages.dev/document.pdf")!
        for (url, page, mime, filename) in [
            ("https://customer-x.cloudflarestream.com/token/downloads/default.mp4", "/about.html", "application/pdf", "book.pdf"),
            (safe.absoluteString, "/film/volume-1", "application/pdf", "book.pdf"),
            (safe.absoluteString, "/about.html", "video/mp4", "book.pdf"),
            (safe.absoluteString, "/about.html", "application/pdf", "FILM.MOV"),
            ("blob:https://khajistan-archive.pages.dev/object", "/film/volume-1", "application/pdf", "book.pdf")
        ] {
            XCTAssertFalse(MediaFilePolicy.allowsBrowserDownload(url: URL(string: url),
                page: URL(string: "https://khajistan-archive.pages.dev" + page), mime: mime, filename: filename))
        }
        XCTAssertTrue(MediaFilePolicy.allowsBrowserDownload(url: safe, page: nil, mime: "application/pdf", filename: "book.pdf"))
    }

    func testDisguisedVideoIsBlockedAndOtherDocumentsRetainExport() {
        let mp4 = Data([0, 0, 0, 24] + Array("ftypisom".utf8))
        XCTAssertFalse(MediaFilePolicy.hasExportableHeader(mp4, extension: "pdf"))
        XCTAssertFalse(MediaFilePolicy.hasExportableHeader(Data("#EXTM3U".utf8), extension: "jpg"))
        XCTAssertTrue(MediaFilePolicy.hasExportableHeader(Data("PK-document".utf8), extension: "zip"))
        XCTAssertTrue(MediaFilePolicy.hasExportableHeader(Data("A plain text document".utf8), extension: "txt"))
        XCTAssertTrue(MediaFilePolicy.allowsBrowserDownload(url: URL(string: "https://example.test/book.pdf"),
            page: nil, mime: "application/octet-stream", filename: "book.pdf"))
        XCTAssertFalse(MediaFilePolicy.hasExportableHeader(Data("%PDF-1.7".utf8), extension: "mp4"))
        XCTAssertTrue(MediaFilePolicy.hasExportableHeader(Data("%PDF-1.7".utf8), extension: "PDF"))
    }

    func testActualOldFilesAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("document.pdf"), video = root.appendingPathComponent("video.pdf")
        try Data("%PDF-1.7".utf8).write(to: pdf)
        try Data([0, 0, 0, 24] + Array("ftypisom".utf8)).write(to: video)
        XCTAssertTrue(MediaFilePolicy.canPreviewOrExport(pdf))
        XCTAssertFalse(MediaFilePolicy.canPreviewOrExport(video))
        let link = root.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pdf)
        XCTAssertFalse(MediaFilePolicy.canPreviewOrExport(link))
    }
}
