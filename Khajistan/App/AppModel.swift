import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    var library = LibraryState()
    var message: String?
    var isShowingBrowser = false
    var selectedTab = AppTab.explore
    let browser = ArchiveBrowser()
    let radio = RadioPlayer()
    private let libraryFile: LibraryFile
    private var libraryReadable = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        libraryFile = LibraryFile(url: support.appendingPathComponent("Khajistan/library.json"))
        do { library = try libraryFile.read(); libraryReadable = true }
        catch { message = "Your saved pages could not be read. The existing file has been kept. \(error.localizedDescription)" }
        browser.onVisit = { [weak self] url, title in self?.updateLibrary { $0.visit(url, title: title) } }
    }

    func open(_ url: URL) {
        guard ArchiveURL.isArchive(url) else { return }
        radio.pause()
        browser.load(url)
        isShowingBrowser = true
    }

    func toggleSaved(_ url: URL, title: String) { updateLibrary { $0.toggleBookmark(url, title: title) } }
    func removeSaved(_ id: UUID) { updateLibrary { $0.bookmarks.removeAll { $0.id == id } } }
    func clearHistory() { updateLibrary { $0.history = [] } }

    private func updateLibrary(_ change: (inout LibraryState) -> Void) {
        guard libraryReadable else { message = "Saved pages are unavailable because the library file could not be read."; return }
        var updated = library
        change(&updated)
        do { try libraryFile.write(updated); library = updated }
        catch { message = "Could not save your library: \(error.localizedDescription)" }
    }
}

enum AppTab: Hashable { case explore, radio, library, passport }
