import Foundation

struct ArchiveDestination: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let path: String
    var url: URL { URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL }

    static let all: [Self] = [
        .init(id: "home", title: "The archive", subtitle: "Explore by region", symbol: "globe.asia.australia", path: "/"),
        .init(id: "reading", title: "Reading Room", subtitle: "Periodicals, posters and books", symbol: "book", path: "/reading-room.html"),
        .init(id: "publications", title: "Publications", subtitle: "Books published by Khajistan", symbol: "books.vertical", path: "/publications.html"),
        .init(id: "receiver", title: "Receiver", subtitle: "Television and radio", symbol: "antenna.radiowaves.left.and.right", path: "/open-frequencies"),
        .init(id: "cinema", title: "Screening Room", subtitle: "Films from the archive", symbol: "film", path: "/screening-room.html"),
        .init(id: "canvas", title: "Canvas", subtitle: "Born-digital media and shared boards", symbol: "square.grid.2x2", path: "/canvas"),
        .init(id: "bazaar", title: "Bazaar", subtitle: "Prints, objects and apparel", symbol: "bag", path: "/bazaar.html"),
        .init(id: "madrassa", title: "Madrassa", subtitle: "The reference wing", symbol: "text.book.closed", path: "/madrassa.html"),
        .init(id: "desk", title: "Human Desk", subtitle: "Contribute to the archive", symbol: "hand.raised", path: "/human-desk.html"),
        .init(id: "chat", title: "Chat", subtitle: "Conversations at Khajistan", symbol: "bubble.left.and.bubble.right", path: "/chat"),
        .init(id: "passport", title: "Passport", subtitle: "Your account and library", symbol: "person.crop.rectangle", path: "/dashboard.html"),
        .init(id: "about", title: "About Khajistan", subtitle: "Media of the Middle World", symbol: "info.circle", path: "/about.html")
    ]
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
