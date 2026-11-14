import Foundation

/// The website's own menu (SITEMAP and DOORS in archive/scripts/kj-chrome.js, read 2026-11-01):
/// the doors in the bar's order, each door's rooms, the site's labels, each with one
/// plain line of what is in it. Staff consoles are not in the menu and are not here.
struct ArchiveDestination: Identifiable, Hashable, Sendable {
    let id: String
    /// The door it sits under, as the bar names it.
    let door: String
    let title: String
    let subtitle: String
    let path: String
    var url: URL { URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL }

    /// The rooms the app draws itself; every other room is the live website.
    var nativeRoom: NativeRoom? { NativeRoom.allCases.first { $0.destinationID == id } }

    static let all: [Self] = [
        .init(id: "home", door: "HOME", title: "Home", subtitle: "Explore by region", path: "/"),
        .init(id: "publications", door: "PUBLICATIONS", title: "Publications", subtitle: "Books and catalogues Khajistan prints", path: "/publications.html"),
        .init(id: "reading", door: "READING ROOM", title: "Reading Room", subtitle: "Old magazines, posters and books to read", path: "/reading-room.html"),
        .init(id: "madrassa", door: "READING ROOM", title: "Madrassa", subtitle: "Look up words, names and places", path: "/madrassa.html"),
        .init(id: "databases", door: "DATABASES", title: "Databases", subtitle: "Searchable records across the Middle World", path: "/databases.html"),
        .init(id: "music-index", door: "DATABASES", title: "Pakistani Music Database", subtitle: "Recordings, performers, labels and releases", path: "/pakistan-music-index.html"),
        .init(id: "national-broadcasts", door: "DATABASES", title: "National Broadcast Register", subtitle: "National television and radio services", path: "/national-broadcasts.html"),
        .init(id: "logos", door: "DATABASES", title: "Logos of the Middle World", subtitle: "Company, product, state and screen marks", path: "/logos.html"),
        .init(id: "cinema-index", door: "DATABASES", title: "Cinema of the Middle World", subtitle: "Iranian, Pakistani and Turkish film indexes", path: "/cinema/"),
        .init(id: "television", door: "DATABASES", title: "Television of the Middle World", subtitle: "National television and drama indexes", path: "/television/"),
        .init(id: "arabicmusic", door: "DATABASES", title: "Arabic Music Index", subtitle: "Arabic recorded music from 1903 shellac on", path: "/arabic-music-index.html"),
        .init(id: "persianmusic", door: "DATABASES", title: "Persian Music Index", subtitle: "Iranian recorded music and Radio Iran broadcasts", path: "/persian-music-index.html"),
        .init(id: "censor", door: "DATABASES", title: "Film Censor Certificates", subtitle: "Pakistani certificates and their transcribed cuts", path: "/censor-certificates.html"),
        .init(id: "leaflets", door: "DATABASES", title: "American War Propaganda Leaflets", subtitle: "Leaflets dropped over Japan, Iraq, Afghanistan and more", path: "/leaflets.html"),
        .init(id: "cinema", door: "RECEIVER", title: "Screening Room", subtitle: "32 films to watch", path: "/screening-room.html"),
        .init(id: "receiver", door: "RECEIVER", title: "Khajistan Receiver", subtitle: "Live TV and radio from the region", path: "/open-frequencies"),
        .init(id: "listening-desk", door: "RECEIVER", title: "Listening Desk", subtitle: "Tell us what you heard in a recording", path: "/listening-desk.html"),
        .init(id: "picsnvids", door: "PICS/VIDS", title: "Pics/Vids", subtitle: "Photos and videos made for the internet", path: "/browse-archive.html"),
        .init(id: "chat", door: "CHAT", title: "Chat", subtitle: "Chat rooms by region", path: "/chat"),
        .init(id: "wall", door: "WALL", title: "Wall", subtitle: "A shared pile of pictures, and a zine to print", path: "/wall/"),
        .init(id: "life", door: "LIFE", title: "Life", subtitle: "A neighbourhood to live in, with other people", path: "/life"),
        .init(id: "toshakhana", door: "BAZAAR", title: "Rare Books & Ephemera", subtitle: "Old books and loose paper the archive holds", path: "/toshakhana.html"),
        .init(id: "bazaar", door: "BAZAAR", title: "Bazaar", subtitle: "Prints, stickers, clothes and things to buy", path: "/bazaar.html"),
        .init(id: "downloads", door: "BAZAAR", title: "Downloads", subtitle: "Digital books and files you bought", path: "/digital/"),
        .init(id: "about", door: "ABOUT", title: "About Khajistan", subtitle: "What Khajistan is and who makes it", path: "/about.html"),
        .init(id: "passport", door: "ABOUT", title: "Your Khajistan", subtitle: "Your account and what you saved", path: "/dashboard.html"),
        .init(id: "desk", door: "ABOUT", title: "Human Desk", subtitle: "Help check what the machines could not read", path: "/human-desk.html"),
        .init(id: "submit", door: "ABOUT", title: "Send Us Your Records", subtitle: "Send us tapes, print or recordings you have", path: "/submit.html"),
        .init(id: "map", door: "MAP", title: "Map", subtitle: "The archive, region by region", path: "/region.html"),
        .init(id: "country", door: "MAP", title: "By country", subtitle: "The archive, country by country", path: "/country.html"),
    ]

    /// The doors in menu order, each with its rooms.
    static var doors: [(door: String, rooms: [Self])] {
        var order: [String] = []
        for destination in all where !order.contains(destination.door) { order.append(destination.door) }
        return order.map { door in (door, all.filter { $0.door == door }) }
    }
}

/// A room of the website the app draws natively. A room is listed here only once its native
/// screen exists; until then its door opens the live website, so no door leads to a stand-in.
enum NativeRoom: String, CaseIterable, Sendable {
    case receiver, picsVids, yours, chat, reading, screening, bazaar, madrassa

    /// The website menu entry (ArchiveDestination.id) the room stands in for.
    var destinationID: String {
        switch self {
        case .receiver: return "receiver"
        case .picsVids: return "picsnvids"
        case .yours: return "passport"
        case .chat: return "chat"
        case .reading: return "reading"
        case .screening: return "cinema"
        case .bazaar: return "bazaar"
        case .madrassa: return "madrassa"
        }
    }

    /// The room's icon on Home (SF Symbols: monochrome, in the text's colour).
    var symbol: String {
        switch self {
        case .receiver: return "dot.radiowaves.left.and.right"
        case .picsVids: return "photo.on.rectangle"
        case .yours: return "books.vertical"
        case .chat: return "bubble.left.and.bubble.right"
        case .reading: return "book"
        case .screening: return "film"
        case .bazaar: return "bag"
        case .madrassa: return "graduationcap"
        }
    }

    /// The room's picture on Home and in Rooms (owner, 2026-10-28: "picture first … like how apple
    /// tv has photos or images for section"): one of the archive's own, bundled, so Home starts no
    /// download for it. Nil where the room has none and keeps its icon.
    var picture: String? {
        switch self {
        case .picsVids: return "RoomPicsVids"
        case .chat: return "RoomChat"
        case .reading: return "RoomReading"
        case .screening: return "RoomScreening"
        case .bazaar: return "RoomBazaar"
        case .madrassa: return "RoomMadrassa"
        case .receiver, .yours: return nil
        }
    }

    /// Whether the room opens inside ROOMS (pushed on its stack) rather than on a bar door of its
    /// own (Receiver, Library) or over the whole app (Chat).
    var opensInRooms: Bool {
        switch self {
        case .receiver, .yours, .chat: return false
        case .picsVids, .reading, .screening, .bazaar, .madrassa: return true
        }
    }
}

/// Where the membership links are offered: the United States storefront only (StoreKit's
/// `Storefront.countryCode`, ISO 3166-1 alpha-3). Until the storefront is known the answer is no,
/// so a slow or failed read never shows a link outside the US.
enum JoinOffer {
    static let storefront = "USA"

    static func isOffered(storefront countryCode: String?) -> Bool {
        countryCode?.uppercased() == storefront
    }

    /// The same page with `app=1`, which the website reads (kj-theme-boot.js) to hide its own
    /// offers and code field for the rest of the visit. Added where the app offers none itself.
    static func tagged(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (parts.queryItems ?? []).filter { $0.name != "app" }
        items.append(URLQueryItem(name: "app", value: "1"))
        parts.queryItems = items
        return parts.url ?? url
    }
}

enum ArchiveURL {
    static let base = URL(string: "https://khajistan-archive.pages.dev")!
    static let hosts: Set<String> = ["khajistan-archive.pages.dev", "archive.khajistan.com"]

    static func isArchive(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && hosts.contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    /// A file may be saved only from the archive's own hosts: an https archive URL, or a blob the
    /// archive page made (`blob:https://<archive host>/<id>`). Anything else a page links, frames
    /// or redirects to is not saved, whatever WebKit would download.
    static func allowsDownload(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme?.lowercased() == "blob" {
            let origin = url.absoluteString.dropFirst("blob:".count)
            return URL(string: String(origin)).map(isArchive) ?? false
        }
        return isArchive(url)
    }

    /// The existing preview password answers only the archive's own HTTPS Basic gate,
    /// once. It is never a credential for a linked site, a proxy or a different auth scheme.
    static func canAnswerPreviewChallenge(_ space: URLProtectionSpace, previousFailures: Int) -> Bool {
        previousFailures == 0 && !space.isProxy()
            && space.authenticationMethod == NSURLAuthenticationMethodHTTPBasic
            && space.protocol?.lowercased() == "https" && space.port == 443
            && hosts.contains(space.host.lowercased())
    }

    /// The website's rooms an App Store build leaves out (owner rulings 2026-10-06, StoreBuild):
    /// Pics/Vids at /canvas, every route that forwards to it and /board/<id> (the same page served
    /// under its own path by _worker.js, no redirect), Chat, and the Wall with its zines.
    /// Hiding the app's own doors is not enough: the site's menu inside the browser links them.
    static let leftOutOfStoreBuild: Set<String> = [
        "chat", "wall", "zines",
        "canvas", "board", "pics-n-vids", "browse", "browse-archive", "born-digital", "digital-borne-archive",
    ]

    /// Whether `url` is an archive page an App Store build must not open, by its first path
    /// segment with any `.html` dropped, so /wall/x, /Chat and /chat.html all count.
    static func isLeftOutOfStoreBuild(_ url: URL) -> Bool {
        guard isArchive(url), let first = url.pathComponents.dropFirst().first?.lowercased() else { return false }
        let room = first.hasSuffix(".html") ? String(first.dropLast(5)) : first
        return leftOutOfStoreBuild.contains(room)
    }

    static func search(_ query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var parts = URLComponents(url: base.appendingPathComponent("search.html"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts.url
    }

    // Accept only an explicit HTTPS archive URL; never turn an arbitrary scheme into navigation.
    static func deepLink(_ url: URL) -> URL? {
        if isArchive(url) { return url }
        guard url.scheme == "khajistan", url.host == "open",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: value), isArchive(target) else { return nil }
        return target
    }

    // Avoid persisting OAuth tokens, signed URLs, password gates or account pages in history.
    static func isSaveable(_ url: URL) -> Bool {
        guard isArchive(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let path = (url.path.removingPercentEncoding ?? url.path).lowercased()
        guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let privatePaths = ["/gate", "/dashboard", "/accounts", "/auth", "/login", "/reset", "/downloads", "/checkout"]
        guard !privatePaths.contains(where: { path.hasPrefix($0) }) else { return false }
        // Store only known public navigation parameters. Unknown parameters may be credentials.
        let publicKeys: Set<String> = ["q", "id", "issue", "slug", "handle", "b", "h", "page", "p", "title", "region", "country", "collection", "channel", "station", "board", "view", "medium"]
        let sensitive = ["token", "password", "secret", "signature", "credential", "api_key", "session", "jwt", "auth="]
        if let fragment = parts.fragment {
            let anchorCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            guard fragment.unicodeScalars.allSatisfy(anchorCharacters.contains),
                  !sensitive.contains(where: { fragment.lowercased().contains($0) }) else { return false }
        }
        return (parts.queryItems ?? []).allSatisfy { item in
            let value = (item.value ?? "").lowercased()
            return publicKeys.contains(item.name) && !value.contains("://")
                && !sensitive.contains(where: { value.contains($0) })
        }
    }
}
