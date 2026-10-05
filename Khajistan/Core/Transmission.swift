import Foundation

/// How a Khajistan TV `play_url` becomes something the player can open. Mirrors resolve() in
/// archive/scripts/kj-transmission-auth.js: the server checks the viewer's session before it
/// issues any media, and the app only builds the two requests and validates what comes back.
enum PlayRoute: Equatable, Sendable {
    /// Any other https URL is played as it is.
    case direct(URL)
    /// The tv-play function: GET with the session, answer is {"url":"https://…"}.
    case tvPlay(URL)
    /// A Cloudflare Stream manifest: trade the 32-hex uid for a signed token, then rebuild the
    /// URL on the stream host from that token and `suffix` ("manifest/video.m3u8").
    case stream(uid: String, suffix: String)
}

enum Transmission {
    private static let supabaseHost =
        URLComponents(url: KJConfig.supabase, resolvingAgainstBaseURL: false)?.host?.lowercased() ?? ""
    private static let streamSuffix = "manifest/video.m3u8"

    /// Classifies a play_url. Nil for anything that must not be fetched: not https, credentials in
    /// the URL, unparseable, or a stream-host URL that is not exactly /<32 hex>/manifest/video.m3u8.
    static func route(for playURL: String) -> PlayRoute? {
        guard let url = URL(string: playURL),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        let path = parts.percentEncodedPath
        if host == KJConfig.streamHost {
            guard let uid = streamUID(inPath: path) else { return nil }
            return .stream(uid: uid, suffix: streamSuffix)
        }
        if host == supabaseHost, parts.port == nil || parts.port == 443, path == "/functions/v1/tv-play" {
            return .tvPlay(url)
        }
        return .direct(url)
    }

    /// The request that turns a route into media access. Nil for `.direct`, which needs none.
    /// A GET carrying the viewer's access token, never cached. The site's fetch also refuses
    /// redirects; URLRequest cannot say so, so the caller's session delegate should.
    static func request(for route: PlayRoute, accessToken: String) -> URLRequest? {
        let url: URL
        switch route {
        case .direct:
            return nil
        case .tvPlay(let target):
            url = target
        case .stream(let uid, _):
            var parts = URLComponents(url: KJConfig.supabase.appendingPathComponent("functions/v1/tv-stream-token"),
                                      resolvingAgainstBaseURL: false)
            parts?.percentEncodedQuery = "uid=" + KJURL.encodeQueryValue(uid)
            guard let built = parts?.url else { return nil }
            url = built
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct TokenBody: Decodable { let token: String? }

    /// The playable URL out of the server's answer. `.tvPlay`: {"url"} that must be https with no
    /// credentials. `.stream`: {"token"} of [A-Za-z0-9_.-]+ placed on the stream host. `.direct`
    /// has nothing to resolve and returns its own URL.
    static func carrier(from data: Data, route: PlayRoute) throws -> URL {
        switch route {
        case .direct(let url):
            return url
        case .tvPlay:
            return try ReceiverRules.carrier(from: data)
        case .stream(_, let suffix):
            guard let token = (try? JSONDecoder().decode(TokenBody.self, from: data))?.token,
                  isToken(token),
                  let url = URL(string: "https://\(KJConfig.streamHost)/\(token)/\(suffix)") else {
                throw CarrierError.malformed
            }
            return url
        }
    }

    static func scheduleURL(month: String) -> URL {
        KJConfig.site.appendingPathComponent("data/khajistan-tv/programming-\(month).json")
    }

    /// The preview gate's HTTP Basic header value.
    static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    /// "/<32 lowercase hex>/manifest/video.m3u8" and nothing else, returning the uid.
    private static func streamUID(inPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty,
              parts[2] == "manifest", parts[3] == "video.m3u8", parts[1].utf8.count == 32,
              parts[1].utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }) else { return nil }
        return String(parts[1])
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
                || $0 == 95 || $0 == 46 || $0 == 45
        }
    }
}
