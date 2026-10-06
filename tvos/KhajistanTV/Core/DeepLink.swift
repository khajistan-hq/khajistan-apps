import Foundation

/// The places the Top Shelf can open: `khajistan://receiver`, `khajistan://receiver/<region id>`,
/// `khajistan://transmission` and `khajistan://transmission/<1 or 2>`. Anything else, including a
/// query, a fragment, a user or a port, is not a link the app follows.
enum DeepLink: Hashable, Sendable {
    case receiver
    case region(String)
    case transmission
    case channel(Int)

    static let scheme = "khajistan"

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == Self.scheme,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              let host = parts.host?.lowercased() else { return nil }
        // "/indus" and "/indus/" are one segment; "" and "/" are none.
        var text = parts.path
        if text.hasSuffix("/") { text.removeLast() }
        let path = text.isEmpty ? [] : text.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        switch (host, path.count) {
        case ("receiver", 0):
            self = .receiver
        case ("receiver", 1) where Self.isRegionID(path[0]):
            self = .region(path[0])
        case ("transmission", 0):
            self = .transmission
        case ("transmission", 1):
            guard let number = Int(path[0]), String(number) == path[0], (1...2).contains(number) else { return nil }
            self = .channel(number)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .receiver: return URL(string: "khajistan://receiver")!
        case .region(let id): return Self.isRegionID(id) ? URL(string: "khajistan://receiver/\(id)")! : DeepLink.receiver.url
        case .transmission: return URL(string: "khajistan://transmission")!
        case .channel(let number): return URL(string: "khajistan://transmission/\(number)")!
        }
    }

    /// The shape of a receiver region id: lower-case letters, digits and single hyphens.
    static func isRegionID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 40 && !text.hasPrefix("-") && !text.hasSuffix("-") && !text.contains("--")
            && text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
    }
}
