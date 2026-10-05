import SwiftUI
import Observation

/// The bottom bar's doors. HOME carries the website's whole menu; the other three are the rooms
/// the app draws itself.
enum AppTab: String, CaseIterable, Identifiable {
    case home, receiver, picsVids, yours

    var id: String { rawValue }

    /// The website's own door names (kj-chrome.js), and ACCOUNT as the Apple TV app names it.
    var title: String {
        switch self {
        case .home: return "Home"
        case .receiver: return "Receiver"
        case .picsVids: return "Pics/Vids"
        case .yours: return "Account"
        }
    }

    init(_ room: NativeRoom) {
        switch room {
        case .receiver: self = .receiver
        case .picsVids: self = .picsVids
        case .yours: self = .yours
        }
    }
}

@MainActor @Observable
final class AppModel {
    var library = LibraryState()
    /// A sentence for the house banner.
    var message: String?
    var isShowingBrowser = false
    var tab: AppTab
    /// The skin on screen: the sky's, or the reader's pick while the sky is in the band it was
    /// made under (Sky.resolve, the website's rule).
    private(set) var skin: Skin = .day
    /// The pick in force, nil when the skin is the sky's own (Automatic).
    private(set) var skinPick: Skin?

    let browser = ArchiveBrowser()
    let auth: AuthStore
    let receiver = ReceiverStore()
    let transmission: TransmissionStore
    let pnv: PicsVidsStore
    let mixes = MixesStore()
    /// The channel-change pigeon. One player for the life of the app.
    let clips = StationClips()

    private let libraryFile: LibraryFile
    private var libraryReadable = false
    /// `-kjskin grove` on the command line: a skin for screenshots, never stored.
    private let forcedSkin: Skin?

    init() {
        let auth = AuthStore()
        self.auth = auth
        transmission = TransmissionStore(auth: auth)
        pnv = PicsVidsStore(auth: auth)
        let defaults = UserDefaults.standard
        forcedSkin = defaults.string(forKey: "kjskin").flatMap(Skin.init(rawValue:))
        tab = defaults.string(forKey: "kjtab").flatMap(AppTab.init(rawValue:)) ?? .home
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        libraryFile = LibraryFile(url: support.appendingPathComponent("Khajistan/library.json"))
        do { library = try libraryFile.read(); libraryReadable = true }
        catch { message = "Your saved pages could not be read. The existing file has been kept. \(error.localizedDescription)" }
        browser.onVisit = { [weak self] url, title in self?.updateLibrary { $0.visit(url, title: title) } }
        refreshSkin()
        browser.warm()
        watchTheSky()
    }

    // MARK: - Skin

    /// Picks a skin, or Automatic with nil. Stored as the website stores it: the pick, and the
    /// band the sky was in when it was made.
    func chooseSkin(_ pick: Skin?) {
        let defaults = UserDefaults.standard
        if let pick {
            defaults.set(pick.rawValue, forKey: Sky.themeKey)
            defaults.set(Sky.theme(at: Date(), timeZone: .current).rawValue, forKey: Sky.bandKey)
        } else {
            defaults.removeObject(forKey: Sky.themeKey)
            defaults.removeObject(forKey: Sky.bandKey)
        }
        withAnimation(.easeInOut(duration: 0.3)) { refreshSkin() }
    }

    /// Reads the sky and the stored pick again. Cheap; run on a timer and on return to the app.
    func refreshSkin() {
        let now = Date()
        let zone = TimeZone.current
        let defaults = UserDefaults.standard
        var chosen = defaults.string(forKey: Sky.themeKey)
        var band = defaults.string(forKey: Sky.bandKey)
        if let forcedSkin {
            chosen = forcedSkin.rawValue
            band = Sky.theme(at: now, timeZone: zone).rawValue
        }
        let resolved = Sky.resolve(chosen: chosen, band: band, at: now, timeZone: zone)
        skinPick = Sky.isHonoured(chosen: chosen, band: band, at: now, timeZone: zone) ? resolved : nil
        if resolved != skin { skin = resolved }
        browser.applySkin(script: Sky.webScript(chosen: chosen, band: band, at: now, timeZone: zone))
    }

    /// The website re-reads its sky every minute; so does the app.
    private func watchTheSky() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.6)) { self.refreshSkin() }
            }
        }
    }

    // MARK: - Rooms

    /// A website page in the in-app browser. Only the archive's own two hosts open here.
    func open(_ url: URL) {
        guard ArchiveURL.isArchive(url) else { return }
        browser.load(url)
        isShowingBrowser = true
    }

    /// A door from the website's menu: a room the app draws itself switches tab, the rest is web.
    func open(_ destination: ArchiveDestination) {
        if let room = destination.nativeRoom {
            withAnimation(.kj) { tab = AppTab(room) }
        } else {
            open(destination.url)
        }
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
