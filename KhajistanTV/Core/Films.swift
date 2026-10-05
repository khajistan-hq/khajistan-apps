import Foundation

// The Screening Room's films: data/khajistan-tv/vod.json, read as archive/scripts/open-frequencies.js
// reads it (filmChannel, marqueeOffer, slideTitle, broadcastRegionFor, requestFilmToken, denyText,
// accessLine, playFullFilm). Only the fields the receiver reads are declared. `stream_uid`, the
// full film's own id, is deliberately not one of them: the full film is reached only through a
// token vod-token mints for a signed-in, entitled viewer.

struct Film: Decodable, Identifiable, Hashable, Sendable {
    let handle: String
    let title: String?
    let year: Int?
    let country: String?
    let region: String?
    let poster: String?
    let publisher: String?
    let preview_uid: String?
    let preview_seconds: Int?
    let runtime_minutes: Int?
    let languages: Languages?
    let rent: Double?
    let buy: Double?
    let licence_price: Double?

    var id: String { handle }

    /// vod.json carries `languages` as a list on most films and as text on a few; the site joins
    /// a list with ", " and takes text as it is.
    struct Languages: Decodable, Hashable, Sendable {
        let text: String

        init(from decoder: Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let list = try? box.decode([String].self) {
                text = list.joined(separator: ", ")
            } else {
                text = try box.decode(String.self)
            }
        }
    }
}

struct FilmCatalogue: Decodable, Sendable {
    let films: [Film]
}

/// What vod-token answered: a token for the full film, or the status that refused it.
enum FilmAccess: Equatable, Sendable {
    case granted(token: String, kind: String?, expiresAt: String?)
    case refused(status: Int)
}

enum Films {
    static let cataloguePath = "/data/khajistan-tv/vod.json"
    /// The same Cloudflare Stream customer host the site's STREAM_BASE names.
    static let streamBase = "https://\(KJConfig.streamHost)"
    static let tokenFunction = KJConfig.supabase.appendingPathComponent("functions/v1/vod-token")
    static let attribution = "A film Khajistan owns and distributes."

    static func catalogueURL(origin: URL) -> URL {
        origin.appendingPathComponent(String(cataloguePath.dropFirst()))
    }

    /// filmChannels(): a film with no handle or no title is not offered.
    static func offered(_ films: [Film]) -> [Film] {
        films.filter { !$0.handle.trimmingCharacters(in: .whitespaces).isEmpty && !($0.title ?? "").isEmpty }
    }

    /// marqueeOffer(): the only place the receiver quotes money, read off the film's own record.
    static func offer(_ film: Film) -> String? {
        if let rent = film.rent { return "Rent $\(jsNumber(rent)) \u{00B7} 48 hours to finish" }
        if film.licence_price != nil { return "Institutional licence \u{00B7} by inquiry on the film's page" }
        return nil
    }

    /// slideTitle(): the year is appended only where the title does not already say it.
    static func displayTitle(_ film: Film) -> String {
        let title = film.title ?? ""
        guard let year = film.year, !title.contains(String(year)) else { return title }
        return "\(title) (\(year))"
    }

    /// "105 minutes · Urdu · Pakistan": what the record gives, nothing when it gives nothing.
    static func detail(_ film: Film) -> String {
        [film.runtime_minutes.map { "\($0) minutes" }, film.languages?.text, film.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }

    /// broadcastRegionFor() on the film's `region`: a receiver region id passes through, a
    /// site key ("persia") becomes the receiver's ("parsistan"). A film with no region is filed
    /// nowhere. `known` is the receiver index's region ids, the registry the site lists by hand.
    static func filedRegion(_ raw: String?, known: Set<String>) -> String? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        if known.contains(key) { return key }
        // siteRegionFor()'s aliases, then the site-key -> receiver-region table.
        let site = ["mashriq": "arabia", "parsistan": "persia", "fars": "persia", "maghreb": "egypt",
                    "central-asia": "khorasan", "central asia": "khorasan", "qafqaz": "caucasus"][key] ?? key
        return ["persia": "parsistan", "egypt": "maghreb", "caucasus": "qafqaz"][site] ?? site
    }

    /// The public sixty-second clip, when the film has one.
    static func previewURL(_ film: Film) -> URL? {
        guard let uid = film.preview_uid, isStreamID(uid) else { return nil }
        return URL(string: "\(streamBase)/\(uid)/manifest/video.m3u8")
    }

    /// The poster as the site files it, on `origin`. A path that names another host is nil.
    static func posterURL(_ film: Film, origin: URL) -> URL? {
        guard let path = film.poster, path.hasPrefix("/"), !path.hasPrefix("//"),
              var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        parts.percentEncodedPath = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { KJURL.encodeQueryValue(String($0).removingPercentEncoding ?? String($0)) }
            .joined(separator: "/")
        return parts.url
    }

    /// The film's own page, where it is rented, bought or licensed: `/film/<handle>`.
    static func pageURL(_ film: Film) -> URL {
        URL(string: KJConfig.site.absoluteString + "/film/" + KJURL.encodeQueryValue(film.handle))!
    }

    // MARK: - vod-token

    /// requestFilmToken(): POST {"film_handle"} with the viewer's session, never cached.
    static func tokenRequest(handle: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: tokenFunction)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["film_handle": handle])
        return request
    }

    private struct TokenBody: Decodable {
        let token: String?
        let kind: String?
        let expires_at: String?
    }

    /// A non-2xx is its status; a 2xx without a token reads as 409, as on the site.
    static func access(status: Int, body: Data) -> FilmAccess {
        guard (200..<300).contains(status) else { return .refused(status: status) }
        guard let parsed = try? JSONDecoder().decode(TokenBody.self, from: body),
              let token = parsed.token, !token.isEmpty else { return .refused(status: 409) }
        return .granted(token: token, kind: parsed.kind, expiresAt: parsed.expires_at)
    }

    /// playFullFilm(): the signed manifest on the stream host.
    static func fullFilmURL(token: String) -> URL? {
        URL(string: "\(streamBase)/\(KJURL.encodeQueryValue(token))/manifest/video.m3u8")
    }

    // MARK: - What the receiver says

    /// The SKUs that can charge a price, keyed by price: open-frequencies.js VARIANTS, which
    /// mirrors screening-room.html and film.html. No SKU at a price, no "Rent it here". A core
    /// test reads the site's own table and fails when this copy falls out of step.
    static let variants: [String: [Int: String]] = [
        "rent": [6: "50071506125014"],
        "buy": [20: "50071508844758", 14: "50074714013910"],
    ]

    static func variant(_ kind: String, _ price: Double?) -> String? {
        guard let price, price == price.rounded() else { return nil }
        return variants[kind]?[Int(price)]
    }

    static let faultText = "Playback is unavailable \u{2014} a fault on our side, not with your access. If you need this film now, write to info@khajistan.com"

    /// denyText(): 401 is a sign-in, 403 is a purchase, everything else is ours and says so.
    static func denyText(_ film: Film, status: Int) -> String {
        switch status {
        case 401:
            return "Sign in to the Khajistan account that holds this film, then press Watch the full film again."
        case 403:
            if variant("rent", film.rent) != nil { return "This film is not on your Khajistan account yet. Rent it here, then press Watch the full film again." }
            if variant("buy", film.buy) != nil { return "This film is not on your Khajistan account yet. Buy it here, then press Watch the full film again." }
            if film.licence_price != nil { return "This film is licensed rather than sold. Screening and institutional terms are by inquiry." }
            return "This film is not on your Khajistan account yet."
        default:
            return faultText
        }
    }

    /// accessLine(): what the viewer is watching on, in their own terms.
    static func accessLine(kind: String?, expiresAt: String?, timeZone: TimeZone = .current) -> String {
        if kind == "staff" { return "Staff access" }
        if kind == "subscription" { return "All Access annual" }
        if let expiresAt, let until = parseISO(expiresAt) {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = timeZone
            format.dateFormat = "MMM d, h:mm a"
            return (kind == "rent" ? "Rented \u{00B7} until " : "Yours until ") + format.string(from: until)
        }
        if kind == "rent" { return "Rented" }
        if kind == "buy" || kind == "purchase" { return "Bought \u{2014} yours to keep" }
        return "On your Khajistan account"
    }

    // MARK: - Helpers

    /// JavaScript's String(number) for the prices the record carries: 6 is "6", 6.5 is "6.5".
    static func jsNumber(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    private static func isStreamID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) }
    }

    private static func parseISO(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
