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
    /// The skin on screen. It follows `skinChoice`, and the hour when the choice is Automatic.
    private(set) var skin: Skin
    /// The root screen on show. The launch argument `-kjtab <name>` picks the one a UI test starts on.
    var section: Section
    let auth: AuthStore
    let receiver: ReceiverStore
    let transmission: TransmissionStore
    let pnv: PicsVidsStore
    /// Likes and saves, on the account (`passport_saves`), shared with the website and the dashboard.
    let saves: SavesStore
    /// The Reading Room: the shelf feed, the page server and the reader's pages.
    let reading: ReadingStore
    /// The Receiver's open region, if any. Held here rather than in the view so Back from the
    /// top bar, which sits outside the Receiver's stack, pops the region instead of leaving the app.
    var receiverPath: [ReceiverIndex.Region] = []
    /// Where a Top Shelf link asked to go. The screen it names reads it and clears it.
    var link: DeepLink?
    /// The Screening Room's films, read from vod.json with the preview password.
    let films: FilmStore
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
        let films = FilmStore(auth: auth)
        self.films = films
        // The shelf's module index sits behind the site password like vod.json, so it is read from the same origin.
        self.reading = ReadingStore(auth: auth, origin: films.origin)
        self.captions = LiveCaptionSession(auth: auth)
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
        case "account": self.section = .account
        default: self.section = .receiver
        }
        watchTheSky()
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

    /// Looks at the clock once a minute and, on Automatic, changes the skin when the hour
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
