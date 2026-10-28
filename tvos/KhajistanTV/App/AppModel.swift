import Foundation
import Observation

private enum DefaultsKey {
    static let extendedAtlas = "kj.extendedAtlas"
    static let startTab = "kjtab"
    static let skinChoice = "kj.skin"
    /// A launch argument, "-kjskin grove", that sets the choice as if it were made in Account.
    static let launchSkin = "kjskin"
}

@MainActor @Observable
final class AppModel {
    /// The skin on screen. It follows `skinChoice`, and the sun (Sky.theme) when the choice is Automatic.
    private(set) var skin: Skin
    /// The root screen on show. The launch argument `-kjtab <name>` picks the one a UI test starts on.
    var section: Section
    let auth: AuthStore
    let receiver: ReceiverStore
    let transmission: TransmissionStore
    let pnv: PicsVidsStore
    /// Likes and saves, on the account (`passport_saves`), shared with the website and the dashboard.
    let saves: SavesStore
    /// Chat: the website's rooms, and this account's handle and age acknowledgement.
    let chat: ChatStore
    /// The Reading Room: the shelf feed, the page server and the reader's pages.
    let reading: ReadingStore
    /// The Receiver's open region, if any. Held here rather than in the view so Back from the
    /// top bar, which sits outside the Receiver's stack, pops the region instead of leaving the app.
    var receiverPath: [ReceiverIndex.Region] = []
    /// A region opened from the front's Cameras shelf: its page leads with its cameras.
    var camerasFirst: String?
    /// Where a Top Shelf link asked to go. The screen it names reads it and clears it.
    var link: DeepLink?
    /// A title the Rooms door asked the Reading Room to open (its page, or the reader at this
    /// device's place). The Reading Room opens it once its shelf is in hand, and clears it.
    var readingLink: ReadingLink?
    /// A radio channel left playing when its player closed: Sonos's small player, under every
    /// screen, until it is turned off or another signal starts.
    var radioAway: RadioAway?
    /// The Screening Room's films, read from vod.json with the preview password.
    let films: FilmStore
    /// ROOMS: the Bazaar's shelf, the Madrassa's sources and the research databases, read from
    /// the site's own files (SiteFeed) as the phone reads them.
    let bazaar: SiteFeed<[BazaarItem]>
    let bazaarSwap: SiteFeed<[String: String]>
    let madrassaEntries: SiteFeed<[MadrassaEntry]>
    let madrassaPosts: SiteFeed<[MadrassaPost]>
    let lughat: SiteFeed<[LughatEntry]>
    /// The Bazaar's bag on this device, the phone's own store. Checkout is the shop's page, opened
    /// on the phone from a code: nothing is paid on the remote.
    let bag = BagStore()
    @ObservationIgnored private var databaseFeeds: [ArchiveDatabase: SiteFeed<[DBRecord]>] = [:]

    /// The preview password's header for a picture on the site's own host, nil anywhere else.
    func siteAuthorization(for url: URL) -> String? { bazaar.authorization(for: url) }

    /// A research database's records, read the first time it is opened.
    func database(_ db: ArchiveDatabase) -> SiteFeed<[DBRecord]> {
        if let feed = databaseFeeds[db] { return feed }
        let origin = SiteOrigin.current
        let feed = SiteFeed<[DBRecord]>(auth: auth, paths: db.paths, origin: origin) { files in try db.records(files, origin: origin) }
        databaseFeeds[db] = feed
        return feed
    }
    /// The wing wipes and the sign-on ident. One player for the life of the app.
    let clips = StationClips()
    /// The pigeon over the live picture at a Receiver channel change.
    let pigeon = PigeonOverlay()
    /// Live captions on the receiver's player. One at a time, as there is one player at a time.
    let captions: LiveCaptionSession

    /// "Beyond the atlas", persisted on the device and off by default. The value lives in
    /// UserDefaults, so the registrar is told by hand when it is read and when it changes.
    var extendedAtlas: Bool {
        get {
            access(keyPath: \.extendedAtlas)
            return UserDefaults.standard.bool(forKey: DefaultsKey.extendedAtlas)
        }
        set {
            withMutation(keyPath: \.extendedAtlas) {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.extendedAtlas)
            }
        }
    }

    /// Automatic or one of the three skins, chosen in Account and kept on the device. Changing it
    /// changes the skin at once.
    var skinChoice: SkinChoice {
        get {
            access(keyPath: \.skinChoice)
            return SkinChoice(stored: UserDefaults.standard.string(forKey: DefaultsKey.skinChoice))
        }
        set {
            withMutation(keyPath: \.skinChoice) {
                UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.skinChoice)
            }
            skin = newValue.skin(at: Date(), calendar: .current)
        }
    }

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.receiver = ReceiverStore()
        self.transmission = TransmissionStore(auth: auth)
        self.pnv = PicsVidsStore(auth: auth)
        self.saves = SavesStore(auth: auth)
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
        self.chat = ChatStore(auth: auth)
        let films = FilmStore(auth: auth)
        self.films = films
        // The shelf's module index sits behind the site password like vod.json, so it is read from the same origin.
        self.reading = ReadingStore(auth: auth, origin: films.origin)
        self.captions = LiveCaptionSession(auth: auth)
        #if DEBUG
        // `-kjforgetplaces YES`: a UI test starts with no Continue, whatever an earlier run read.
        if UserDefaults.standard.bool(forKey: "kjforgetplaces") { UserDefaults.standard.removeObject(forKey: "kj.readingPlaces") }
        // `-kjemptybag YES`: a UI test starts with an empty bag, whatever an earlier run put in it.
        if UserDefaults.standard.bool(forKey: "kjemptybag") { bag.empty() }
        #endif
        if let launched = UserDefaults.standard.string(forKey: DefaultsKey.launchSkin) {
            UserDefaults.standard.set(SkinChoice(stored: launched).rawValue, forKey: DefaultsKey.skinChoice)
        }
        self.skin = SkinChoice(stored: UserDefaults.standard.string(forKey: DefaultsKey.skinChoice))
            .skin(at: Date(), calendar: .current)
        // Read once. Xcode turns the launch arguments "-kjtab transmission" into this default.
        switch UserDefaults.standard.string(forKey: DefaultsKey.startTab) {
        case "transmission": self.section = .transmission
        case "reading": self.section = .reading
        case "picsvids" where StoreBuild.includes(.picsvids): self.section = .picsvids
        case "chat" where StoreBuild.includes(.chat): self.section = .chat
        case "rooms": self.section = .rooms
        case "account": self.section = .account
        default: self.section = .receiver
        }
        watchTheSky()
        // Which way the database answers, decided while the first screen draws.
        Task.detached(priority: .userInitiated) { await SupabaseRoute.settle() }
    }

    /// Stops the radio left playing under the screens: one signal at a time, so every player
    /// calls this as it starts its own.
    func silenceRadio() {
        radioAway?.controller.stop()
        radioAway = nil
    }

    /// A `khajistan://` link from the Top Shelf. Anything that does not parse is ignored.
    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .receiver, .region: section = .receiver
        case .transmission, .channel: section = .transmission
        }
        self.link = link
    }

    /// Looks at the clock once a minute and, on Automatic, changes the skin when the sun
    /// crosses a band.
    private func watchTheSky() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                let next = self.skinChoice.skin(at: Date(), calendar: .current)
                if next != self.skin { self.skin = next }
            }
        }
    }
}
