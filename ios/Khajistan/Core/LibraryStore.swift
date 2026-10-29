import Foundation

struct SavedPage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    let date: Date
    init(url: URL, title: String, date: Date = .now) {
        id = UUID(); self.url = url; self.title = title; self.date = date
    }
}

/// Where reading or watching stopped, on this device. It names the object by its stable identity
/// (a title slug and issue key, a film handle), never by a page or stream URL, which expire and
/// carry access. Whether the viewer may still read or watch it is asked again on every open.
struct Resume: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case reading, film }
    let kind: Kind
    /// The title slug (reading) or film handle (film).
    let ref: String
    /// The issue key, for reading.
    var part: String?
    /// The page number (reading) or seconds in (film).
    var position: Double
    var title: String
    var detail: String
    var date: Date

    var id: String { kind.rawValue + "|" + ref }
}

/// A page marked in the reader: the title slug, the issue key and the page number, never a page
/// URL. Kept on this device beside the reading places.
struct PageMark: Codable, Hashable, Sendable {
    let title: String
    let issue: String
    let page: Int
    var date: Date
}

struct LibraryState: Codable, Equatable, Sendable {
    var bookmarks: [SavedPage] = []
    var history: [SavedPage] = []
    /// Newest first, one per title or film.
    var resume: [Resume] = []
    /// Pages marked in the reader, newest first.
    var pageMarks: [PageMark] = []

    init() {}

    /// Every field is optional on reading, so a library written before a field existed still
    /// opens (the file is never thrown away for being older than the app).
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bookmarks = try values.decodeIfPresent([SavedPage].self, forKey: .bookmarks) ?? []
        history = try values.decodeIfPresent([SavedPage].self, forKey: .history) ?? []
        resume = try values.decodeIfPresent([Resume].self, forKey: .resume) ?? []
        pageMarks = try values.decodeIfPresent([PageMark].self, forKey: .pageMarks) ?? []
    }

    /// Keeps the newest place for this object, at the front, and at most forty places.
    mutating func record(_ place: Resume) {
        resume.removeAll { $0.id == place.id }
        resume.insert(place, at: 0)
        resume = Array(resume.prefix(40))
    }

    func place(_ kind: Resume.Kind, _ ref: String) -> Resume? {
        resume.first { $0.kind == kind && $0.ref == ref }
    }

    /// Marks the page, or takes the mark off when it is there.
    mutating func togglePageMark(title: String, issue: String, page: Int, date: Date = .now) {
        if let index = pageMarks.firstIndex(where: { $0.title == title && $0.issue == issue && $0.page == page }) {
            pageMarks.remove(at: index)
        } else {
            pageMarks.insert(PageMark(title: title, issue: issue, page: page, date: date), at: 0)
        }
    }

    /// The marked pages of one issue, in page order.
    func pageMarks(title: String, issue: String) -> [Int] {
        pageMarks.filter { $0.title == title && $0.issue == issue }.map(\.page).sorted()
    }

    mutating func visit(_ url: URL, title: String) {
        guard ArchiveURL.isSaveable(url) else { return }
        history.removeAll { $0.url == url }
        history.insert(SavedPage(url: url, title: title), at: 0)
        history = Array(history.prefix(100))
    }

    mutating func toggleBookmark(_ url: URL, title: String) {
        guard ArchiveURL.isSaveable(url) else { return }
        if let index = bookmarks.firstIndex(where: { $0.url == url }) { bookmarks.remove(at: index) }
        else { bookmarks.insert(SavedPage(url: url, title: title), at: 0) }
    }
}

struct LibraryFile {
    let url: URL
    func read() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryState() }
        return try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: url))
    }
    func write(_ state: LibraryState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var directory = url.deletingLastPathComponent()
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

enum DownloadName {
    static func safe(_ suggested: String) -> String {
        let leaf = suggested.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? "download"
        let cleaned = leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result != ".", result != "..", !result.hasPrefix(".") else { return "download" }
        let suffix = (result as NSString).pathExtension
        let extensionPart = !suffix.isEmpty && suffix.utf8.count < 20 ? "." + suffix : ""
        var stem = extensionPart.isEmpty ? result : String(result.dropLast(extensionPart.count))
        while stem.utf8.count + extensionPart.utf8.count > 220 { stem.removeLast() }
        return (stem.isEmpty ? "download" : stem) + extensionPart
    }
}
