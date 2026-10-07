import Foundation

/// The website's own menu (SITEMAP and DOORS in archive/scripts/kj-chrome.js, read 2026-10-05):
/// the doors in the bar's order, each door's rooms, the site's labels and one-line descriptions
/// verbatim. Staff consoles are not in the menu and are not here.
struct ArchiveDestination: Identifiable, Hashable, Sendable {
    let id: String
    /// The door it sits under, as the bar names it.
    let door: String
    let title: String
    let subtitle: String
    let path: String
    var url: URL { URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL }

    /// The rooms the app draws itself; every other room is the live website.
    var nativeRoom: NativeRoom? {
        switch id {
        case "receiver": return .receiver
        case "picsnvids": return .picsVids
        case "chat": return .chat
        case "passport": return .yours
        default: return nil
        }
    }

    static let all: [Self] = [
        .init(id: "home", door: "HOME", title: "Home", subtitle: "Explore by region", path: "/"),
        .init(id: "publications", door: "PUBLICATIONS", title: "Publications", subtitle: "Khajistan Press — books, catalogues and printed editions", path: "/publications.html"),
        .init(id: "reading", door: "READING ROOM", title: "Reading Room", subtitle: "Digitized periodicals, posters and books · deep-zoom reader", path: "/reading-room.html"),
        .init(id: "madrassa", door: "READING ROOM", title: "Madrassa", subtitle: "The reference wing — street dictionary, indices and writings", path: "/madrassa.html"),
        .init(id: "cinema", door: "RECEIVER", title: "Screening Room", subtitle: "The 32 films — on demand, rental, purchase & institutional licensing", path: "/screening-room.html"),
        .init(id: "receiver", door: "RECEIVER", title: "Khajistan Receiver", subtitle: "Live regional television and radio, and the Khajistan Radio mixes", path: "/open-frequencies"),
        .init(id: "listening-desk", door: "RECEIVER", title: "Listening Desk", subtitle: "Share what you heard — audio & video speech evidence", path: "/listening-desk.html"),
        .init(id: "picsnvids", door: "PICS/VIDS", title: "Pics/Vids", subtitle: "Born Digital Media", path: "/browse-archive.html"),
        .init(id: "chat", door: "CHAT", title: "Chat", subtitle: "Chat rooms by region", path: "/chat"),
        .init(id: "wall", door: "WALL", title: "Wall", subtitle: "A shared pile and a printable zine", path: "/wall/"),
        .init(id: "toshakhana", door: "BAZAAR", title: "Rare Books & Ephemera", subtitle: "Originals the archive holds — rare books, sets and loose paper", path: "/toshakhana.html"),
        .init(id: "bazaar", door: "BAZAAR", title: "Bazaar", subtitle: "Prints, objects, apparel and stickers", path: "/bazaar.html"),
        .init(id: "downloads", door: "BAZAAR", title: "Downloads", subtitle: "Digital editions and files, delivered to your account", path: "/digital/"),
        .init(id: "about", door: "ABOUT", title: "About Khajistan", subtitle: "What this is, who makes it, and why", path: "/about.html"),
        .init(id: "passport", door: "ABOUT", title: "Your Khajistan", subtitle: "Account, membership, downloads and saved work", path: "/dashboard.html"),
        .init(id: "desk", door: "ABOUT", title: "Human Desk", subtitle: "Hear, see and read what the machines could not finish", path: "/human-desk.html"),
        .init(id: "submit", door: "ABOUT", title: "Send Us Your Records", subtitle: "Tapes, print and recordings you hold, for the archive", path: "/submit.html"),
        .init(id: "map", door: "MAP", title: "Map", subtitle: "Region chapters of the archive", path: "/region.html"),
        .init(id: "country", door: "MAP", title: "By country", subtitle: "One country across the archive", path: "/country.html"),
    ]

    /// The doors in menu order, each with its rooms.
    static var doors: [(door: String, rooms: [Self])] {
        var order: [String] = []
        for destination in all where !order.contains(destination.door) { order.append(destination.door) }
        return order.map { door in (door, all.filter { $0.door == door }) }
    }
}

/// A room of the website the app draws natively, and the bottom-bar door that holds it.
enum NativeRoom: String, CaseIterable, Sendable {
    case receiver, picsVids, yours, chat
}

/// Reading Room All Access, sold by the website's own checkout (scripts/kj-join.js): a link with
/// `?join=<plan>` resumes it after sign-in. No price is written into the app; the site states it.
enum JoinPlan: String, CaseIterable, Sendable {
    case monthly, annual

    var label: String { self == .monthly ? "Monthly" : "Annual" }
    var url: URL {
        var parts = URLComponents(url: ArchiveURL.base.appendingPathComponent("reading-room.html"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "join", value: rawValue)]
        return parts.url!
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
}

enum ArchiveURL {
    static let base = URL(string: "https://khajistan-archive.pages.dev")!
    static let hosts: Set<String> = ["khajistan-archive.pages.dev", "archive.khajistan.com"]

    static func isArchive(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && hosts.contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
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
