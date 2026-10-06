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

struct LibraryState: Codable, Equatable, Sendable {
    var bookmarks: [SavedPage] = []
    var history: [SavedPage] = []

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
