import Foundation

func exactOriginsAndDeepLinks() throws {
    for value in ["https://khajistan-archive.pages.dev/canvas", "https://archive.khajistan.com/read.html?id=12"] {
        try expect(ArchiveURL.isArchive(try require(URL(string: value))))
    }
    for value in ["http://khajistan-archive.pages.dev", "https://khajistan-archive.pages.dev.evil.org", "https://user:pass@khajistan-archive.pages.dev", "https://khajistan-archive.pages.dev:8080", "javascript:alert(1)", "file:///etc/passwd"] {
        try expect(!ArchiveURL.isArchive(try require(URL(string: value))))
    }
    let encoded = URL(string: "khajistan://open?url=https%3A%2F%2Fkhajistan-archive.pages.dev%2Fread.html%3Fid%3D42")!
    try expect(ArchiveURL.deepLink(encoded)?.query == "id=42")
    try expect(ArchiveURL.deepLink(URL(string: "khajistan://open?url=https://example.com")!) == nil)
}

func searchPreservesUrduAndDelimiters() throws {
    let input = "خجستان & cinema #1 + posters"
    let url = try require(ArchiveURL.search(input))
    let query = try require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    try expect(query.queryItems == [URLQueryItem(name: "q", value: input)])
    try expect(query.fragment == nil)
    try expect(ArchiveURL.search(" \n ") == nil)
}

func privatePagesNeverEnterLibrary() throws {
    var state = LibraryState()
    for path in ["/dashboard.html", "/gate?next=/", "/read.html?access_token=abc", "/read.html#refresh_token=abc", "/auth/callback?code=abc", "/downloads.html", "/?api_key=example", "/?session=example", "/?auth=example", "/?jwt=example", "/?next=https://example.com/?token=secret", "/./dashboard.html", "/x/../dashboard.html"] {
        let url = URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL
        state.visit(url, title: "Private")
        state.toggleBookmark(url, title: "Private")
    }
    try expect(state.bookmarks.isEmpty)
    try expect(state.history.isEmpty)
}

func historyDeduplicatesAndHasBoundedSize() throws {
    var state = LibraryState()
    for n in 0..<120 { state.visit(ArchiveURL.base.appendingPathComponent("item/\(n)"), title: "Item \(n)") }
    try expect(state.history.count == 100)
    let url = ArchiveURL.base.appendingPathComponent("item/50")
    state.visit(url, title: "Updated")
    try expect(state.history.count == 100)
    try expect(state.history.first?.title == "Updated")
    try expect(state.history.filter { $0.url == url }.count == 1)
    state.toggleBookmark(url, title: "Keep me")
    try expect(state.bookmarks.count == 1)
    state.toggleBookmark(url, title: "Keep me")
    try expect(state.bookmarks.isEmpty)
}

func libraryRoundTripAndCorruptFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
    try expect(try file.read() == LibraryState())
    var state = LibraryState()
    state.toggleBookmark(ArchiveURL.base, title: "خجستان")
    try file.write(state)
    try expect(try file.read() == state)
    try Data("bad json".utf8).write(to: file.url)
    var corruptRejected = false
    do { _ = try file.read() } catch { corruptRejected = true }
    try expect(corruptRejected)
    try expect(try String(contentsOf: file.url, encoding: .utf8) == "bad json")
}

func downloadNamesCannotTraverseDirectories() throws {
    try expect(DownloadName.safe("../../secret.pdf") == "secret.pdf")
    try expect(DownloadName.safe("C:\\private\\book.pdf") == "book.pdf")
    try expect(DownloadName.safe("..") == "download")
    try expect(DownloadName.safe(".env") == "download")
    try expect(DownloadName.safe("\n") == "download")
    try expect(DownloadName.safe("book\u{0000}.pdf") == "book.pdf")
    try expect(DownloadName.safe("رسالہ.pdf") == "رسالہ.pdf")
    let longName = DownloadName.safe(String(repeating: "😀", count: 180) + ".pdf")
    try expect(longName.utf8.count <= 220)
    try expect(longName.hasSuffix(".pdf"))
}

private func channel(_ id: String, status: String = "published", disabled: Bool = false, type: String = "radio", streamID: String? = "s") -> RadioChannel {
    RadioChannel(id: id, name: id, mediaType: type, country: "Pakistan", primaryLanguage: "Urdu", streams: [.init(id: "s", format: "hls")], activeStreamId: streamID, publicationStatus: status, healthStatus: "online", manualDisabled: disabled, attributionText: nil)
}

func radioGuardsRejectEachWithdrawalCase() throws {
    let feed = ReceiverFeed(channels: [channel("good"), channel("good"), channel("deny"), channel("offair"), channel("disabled", disabled: true), channel("draft", status: "draft"), channel("tv", type: "tv"), channel("missing", streamID: "absent"), channel("offline"), channel("blocked"), channel("slow")])
    let health = HealthFeed(results: [.init(channelId: "offline", status: "offline", deliveryRatio: nil), .init(channelId: "blocked", status: "blocked", deliveryRatio: nil), .init(channelId: "slow", status: "online", deliveryRatio: 0.49)])
    let result = RadioCatalogue.available(feed: feed, denied: .init(disabledChannelIds: ["deny"]), offAir: .init(offAirChannelIds: ["offair"]), health: health)
    try expect(result.map(\.id) == ["good"])
}

func carrierEncodesAnOpaqueStreamID() throws {
    let url = RadioCatalogue.carrierURL(streamID: "station+1&x=#fragment")
    try expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "stream", value: "station+1&x=#fragment")])
    try expect(url.fragment == nil)
}

private struct AssertionFailure: Error, CustomStringConvertible {
    let description: String
}
private func expect(_ condition: @autoclosure () throws -> Bool, file: String = #fileID, line: Int = #line) throws {
    guard try condition() else { throw AssertionFailure(description: "\(file):\(line) assertion failed") }
}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw AssertionFailure(description: "Required value was nil") }
    return value
}
@main struct CoreTestRunner {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("Exact origins and deep links", exactOriginsAndDeepLinks),
            ("Urdu and delimiter search encoding", searchPreservesUrduAndDelimiters),
            ("Private pages excluded from persistence", privatePagesNeverEnterLibrary),
            ("Bounded history and bookmark toggle", historyDeduplicatesAndHasBoundedSize),
            ("Disk round trip and corruption preservation", libraryRoundTripAndCorruptFile),
            ("Download traversal and Unicode limits", downloadNamesCannotTraverseDirectories),
            ("Radio withdrawal controls", radioGuardsRejectEachWithdrawalCase),
            ("Opaque stream ID encoding", carrierEncodesAnOpaqueStreamID)
        ]
        for (name, run) in tests { try run(); print("PASS \(name)") }
        print("\(tests.count) tests passed")
    }
}
