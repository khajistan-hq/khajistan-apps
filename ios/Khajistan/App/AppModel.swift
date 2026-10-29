import SwiftUI
import Observation
import StoreKit

/// The bottom bar's doors (owner brief, 2026-10-27): HOME, ROOMS (every room of the website's
/// menu, the native ones drawn here), the RECEIVER, the LIBRARY (account, saved work, what is on
/// this device) and SEARCH.
enum AppTab: String, CaseIterable, Identifiable {
    case home, rooms, receiver, library, search

    var id: String { rawValue }

    /// The tab bar's icon (SF Symbols: monochrome, in the text's colour).
    var symbol: String {
        switch self {
        case .home: return "house"
        case .rooms: return "square.grid.2x2"
        case .receiver: return "dot.radiowaves.left.and.right"
        case .library: return "books.vertical"
        case .search: return "magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .rooms: return "Rooms"
        case .receiver: return "Receiver"
        case .library: return "Library"
        case .search: return "Search"
        }
    }

    /// The bar door a native room lives on; nil for a room that opens inside ROOMS or over the
    /// tabs (chat).
    init?(_ room: NativeRoom) {
        switch room {
        case .receiver: self = .receiver
        case .yours: self = .library
        case .picsVids, .chat, .reading, .screening, .bazaar, .madrassa: return nil
        }
    }

    /// `-kjtab <name>`, with the names the bar had before 2026-10-27 still read, so old UI test
    /// launches and saved launch arguments land where they meant to.
    init?(launchName: String) {
        switch launchName {
        case "yours", "account": self = .library
        case "picsVids": self = .rooms
        default: self.init(rawValue: launchName)
        }
    }
}

@MainActor @Observable
final class AppModel {
    var library = LibraryState()
    /// A sentence for the house banner.
    var message: String?
    var isShowingBrowser = false
    /// Chat opens over the tabs, as the browser does.
    var isShowingChat = false
    /// The region Pics/Vids shows: a region token, or `PicsVidsStore.allRegions` for all of them.
    /// The phone draws one grid under a region filter; the store keeps one feed per key.
    var pnvRegion = PicsVidsStore.allRegions
    var tab: AppTab
    /// The room open in ROOMS, nil for the list of rooms. Kept while another bar door is on show,
    /// so coming back finds the room where it was left.
    var room: NativeRoom?
    /// Each room's own stack of pushed screens, kept per room for the same reason.
    var roomPaths: [NativeRoom: [RoomRoute]] = [:]
    /// The skin on screen: the sky's, or the reader's pick while the sky is in the band it was
    /// made under (Sky.resolve, the website's rule).
    private(set) var skin: Skin = .day
    /// The pick in force, nil when the skin is the sky's own (Automatic).
    private(set) var skinPick: Skin?

    /// The App Store storefront's country code, nil until StoreKit has answered. The Reading Room
    /// page's own membership offer follows it (`showsJoin`; elsewhere the page is tagged `app=1`).
    /// `-kjstorefront GBR` on the command line stands in for it in UI tests.
    private(set) var storefrontCode: String?
    var showsJoin: Bool { JoinOffer.isOffered(storefront: storefrontCode) }

    /// The in-app browser, made on first use or once launch has settled (`init`): a WKWebView made
    /// in `init` held up the first screen.
    var browser: ArchiveBrowser {
        if let madeBrowser { return madeBrowser }
        let made = ArchiveBrowser()
        made.onVisit = { [weak self] url, title in self?.updateLibrary { $0.visit(url, title: title) } }
        if let skinScript { made.applySkin(script: skinScript) }
        madeBrowser = made
        return made
    }
    @ObservationIgnored private var madeBrowser: ArchiveBrowser?
    /// The website's skin keys as last read, for a browser made after them.
    @ObservationIgnored private var skinScript: String?
    let auth: AuthStore
    let receiver = ReceiverStore()
    /// The Receiver list's thumbnails: stills this device takes from the live streams, in memory only.
    let stills: LiveStills
    let transmission: TransmissionStore
    let pnv: PicsVidsStore
    /// The channel-change pigeon. One player for the life of the app.
    let clips = StationClips()
    /// What the Receiver tab is playing, docked or full screen.
    let captions: LiveCaptionSession
    let tuner: ReceiverTuner
    let chat: ChatStore
    /// The Screening Room's films, read from vod.json; full films through vod-token.
    let films: FilmStore
    /// The Reading Room: the shelf feed, the page server and the reader's pages.
    let reading: ReadingStore
    /// Saves on the account (`passport_saves`), shared with the website and the Apple TV.
    let saves: SavesStore
    /// The Bazaar's shelf (data/catalog.json) and this device's bag for the shop's checkout.
    let bazaar: SiteFeed<[BazaarItem]>
    let bag = BagStore()
    let bazaarSwap: SiteFeed<[String: String]>
    /// The Madrassa: the page's reference entries, the writings feed and the Street Dictionary.
    let madrassaEntries: SiteFeed<[MadrassaEntry]>
    let madrassaPosts: SiteFeed<[MadrassaPost]>
    let lughat: SiteFeed<[LughatEntry]>
    /// The research databases, each read the first time it is opened.
    @ObservationIgnored private var databaseFeeds: [ArchiveDatabase: SiteFeed<[DBRecord]>] = [:]

    private let libraryFile: LibraryFile
    private var libraryReadable = false
    /// `-kjskin grove` on the command line: a skin for screenshots, never stored.
    private let forcedSkin: Skin?
    /// True until the app has put a channel on at launch. The app opens on RECEIVER with something
    /// already playing (Pluto TV's lesson); `-kjautoplay NO` keeps it quiet for UI tests.
    private var playsAtLaunch: Bool

    init() {
        let auth = AuthStore()
        self.auth = auth
        transmission = TransmissionStore(auth: auth)
        captions = LiveCaptionSession(auth: auth)
        stills = LiveStills(receiver: receiver)
        tuner = ReceiverTuner(clips: clips, receiver: receiver, transmission: transmission, captions: captions)
        pnv = PicsVidsStore(auth: auth)
        chat = ChatStore(auth: auth)
        let films = FilmStore(auth: auth)
        self.films = films
        reading = ReadingStore(auth: auth, origin: films.origin)
        saves = SavesStore(auth: auth)
        bazaar = SiteFeed(auth: auth, path: Bazaar.cataloguePath) { data in
            Bazaar.offered(try JSONDecoder().decode(BazaarCatalogue.self, from: data).products)
        }
        bazaarSwap = SiteFeed(auth: auth, path: Bazaar.swapPath) { data in try Bazaar.swapMap(data) }
        madrassaEntries = SiteFeed(auth: auth, path: MadrassaEntries.pagePath) { data in
            guard let entries = MadrassaEntries.entries(fromPage: String(decoding: data, as: UTF8.self)) else { throw DBError.unreadable }
            return entries
        }
        madrassaPosts = SiteFeed(auth: auth, path: MadrassaWritings.feedPath) { data in
            MadrassaWritings.knowledge(try JSONDecoder().decode([MadrassaPost].self, from: data))
        }
        lughat = SiteFeed(auth: auth, path: Lughat.path) { data in try JSONDecoder().decode(LughatFile.self, from: data).entries }
        let defaults = UserDefaults.standard
        forcedSkin = defaults.string(forKey: "kjskin").flatMap(Skin.init(rawValue:))
        playsAtLaunch = defaults.object(forKey: "kjautoplay") == nil || defaults.bool(forKey: "kjautoplay")
        let launchTab = defaults.string(forKey: "kjtab")
        tab = launchTab.flatMap(AppTab.init(launchName:)) ?? .receiver
        if launchTab == "picsVids", StoreBuild.includes(.picsVids) { room = .picsVids }
        // `-kjroom reading`: open ROOMS on a room, for UI tests and screenshots.
        if let launchRoom = defaults.string(forKey: "kjroom").flatMap(NativeRoom.init(rawValue:)),
           launchRoom.opensInRooms, StoreBuild.includes(launchRoom) {
            room = launchRoom
            tab = .rooms
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        libraryFile = LibraryFile(url: support.appendingPathComponent("Khajistan/library.json"))
        do { library = try libraryFile.read(); libraryReadable = true }
        catch { message = "Your saved pages could not be read. The existing file has been kept. \(error.localizedDescription)" }
        refreshSkin()
        // WebKit's page process starts once the first screen is up, so the first page opened still
        // does not wait for it. A browser already opened has its process and a page not to replace.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.madeBrowser == nil else { return }
            self.browser.warm()
        }
        watchTheSky()
        watchTheStorefront(forced: defaults.string(forKey: "kjstorefront"))
        // Which way the database answers, decided while the first screen draws.
        Task.detached(priority: .userInitiated) { await SupabaseRoute.settle() }
    }

    // MARK: - Storefront

    /// Reads the storefront at launch and again whenever the App Store changes it.
    private func watchTheStorefront(forced: String?) {
        if let forced { storefrontCode = forced; return }
        Task { [weak self] in
            if let current = await Storefront.current { self?.storefrontCode = current.countryCode }
            for await next in Storefront.updates { self?.storefrontCode = next.countryCode }
        }
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
        let script = Sky.webScript(chosen: chosen, band: band, at: now, timeZone: zone)
        skinScript = script
        madeBrowser?.applySkin(script: script)
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

    // MARK: - Opening

    /// Once per launch, when the app opened on RECEIVER and nothing is on: Surf picks a channel,
    /// with the reader's Surf settings, so the first screen is a live signal rather than a page.
    /// Not under VoiceOver: sound that starts by itself talks over the screen reader (WCAG 1.4.2),
    /// so the set opens on standby and Surf is one control away.
    func playIfOpening() async {
        guard playsAtLaunch else { return }
        playsAtLaunch = false
        guard tab == .receiver, tuner.source == nil, !UIAccessibility.isVoiceOverRunning else { return }
        await tuner.surf()
    }

    // MARK: - Rooms

    /// A website page in the in-app browser. Only the archive's own two hosts open here. Off the
    /// US storefront the page carries `app=1`, so the website hides its offers too.
    func open(_ url: URL) {
        guard ArchiveURL.isArchive(url) else { return }
        // A Reading Room address (?m=title&issue=&p=) opens the native reader, as the site's does.
        if let route = ReadingLinks.route(url), StoreBuild.includes(.reading) {
            open(.reading, at: [route])
            return
        }
        openWebsite(url)
    }

    /// A website page in the house browser, even where the app has a native room for it: for the
    /// "on the website" controls, whose point is the page itself.
    func openWebsite(_ url: URL) {
        guard ArchiveURL.isArchive(url) else { return }
        browser.load(showsJoin ? url : JoinOffer.tagged(url))
        isShowingBrowser = true
    }

    /// A door from the website's menu: a room the app draws itself switches tab, the rest is web.
    func open(_ destination: ArchiveDestination) {
        // A link into a room this build leaves out (StoreBuild) goes nowhere, web included.
        guard StoreBuild.includes(destination) else {
            message = "\(destination.title) is not in this edition of the app."
            return
        }
        if let room = destination.nativeRoom {
            open(room)
        } else {
            open(destination.url)
        }
    }

    /// A room the app draws itself: on its own bar door, pushed in ROOMS, or over the tabs.
    func open(_ room: NativeRoom, at route: [RoomRoute]? = nil) {
        guard StoreBuild.includes(room) else {
            message = "This room is not in this edition of the app."
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            if room == .chat {
                isShowingChat = true
            } else if let tab = AppTab(room) {
                self.tab = tab
            } else {
                self.room = room
                if let route { roomPaths[room] = route }
                self.tab = .rooms
            }
        }
    }

    /// The preview password's header for a picture on the site's own host, nil anywhere else.
    func siteAuthorization(for url: URL) -> String? { bazaar.authorization(for: url) }

    /// A research database's records, read once per preview password.
    func database(_ db: ArchiveDatabase) -> SiteFeed<[DBRecord]> {
        if let feed = databaseFeeds[db] { return feed }
        let origin = SiteOrigin.current
        let feed = SiteFeed<[DBRecord]>(auth: auth, paths: db.paths, origin: origin) { files in try db.records(files, origin: origin) }
        databaseFeeds[db] = feed
        return feed
    }

    /// Where reading or watching stopped, kept on this device.
    func record(_ place: Resume) { updateLibrary { $0.record(place) } }

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
