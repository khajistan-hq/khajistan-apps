import Foundation

// Pics/Vids: the Born Digital stream at /browse-archive.html. Everything here mirrors the site's
// own code, read 2026-10-05, and says which file and what it copied:
//   scripts/kj-browse-archive.js  the query, the roster gate, the ordering, the facets, the captions
//   scripts/kj-media.js           how a row becomes an image or a video URL
//   scripts/kj-adult-notice.js    the notice and its suppression rule
//   scripts/kj-regions.js         the region labels
// The app adds no filter and widens nothing: a row is shown only if its account is on the
// pnv_accounts roster, exactly as the page does it.

// MARK: - Rows

/// One row of the `pnv_media` view, the columns the page selects (kj-browse-archive.js COLS) less
/// the three it never reads back (child_index, feed_rank, and the keyset column of Shuffle).
struct PnvRow: Decodable, Identifiable, Hashable, Sendable {
    let media_key: String
    let account: String?
    let account_key: String?
    let shortcode: String?
    let kind: String
    let resource_type: String?
    let media_host: String?
    let resource_endpoint: String?
    let width: Int?
    let height: Int?
    let taken_at: String?
    let corpus: String?
    let da_id: Int?

    var id: String { media_key }
    var isVideo: Bool { kind == "video" }
    /// Khajistan TV's own born-digital half: the poster is an object, the video is not.
    var isKtv: Bool { media_host == "ktv" }

    /// Height over width, or nil when the row does not say (the site then lets the image decide).
    var aspect: Double? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return Double(w) / Double(h)
    }
}

/// An account on the roster. A row is published only if its account is here.
struct PnvAccount: Decodable, Hashable, Sendable {
    let slug: String
    let handle: String?
    let platform: String?
    let region_token: String?
    let country: String?
    let corpus: String?
    let account_key: String
}

/// `rpc('pnv_facets')`: the totals and per-account counts the page's summary line is built from.
struct PnvFacets: Decodable, Sendable {
    struct Totals: Decodable, Sendable { let media: Int? }
    struct AccountCount: Decodable, Sendable { let slug: String; let media: Int? }
    let totals: Totals?
    let accounts: [AccountCount]?
}

enum PnvKind: String, CaseIterable, Sendable {
    case image, video

    /// The site's button labels (browse-archive.html: Everything / Pictures / Videos).
    var label: String { self == .image ? "Pictures" : "Videos" }
}

// MARK: - URLs (kj-media.js)

/// How a row becomes a URL. Three hosts, told apart by `media_host` (kj-media.js header):
/// Supabase public storage (the default), Cloudflare R2, and `ktv`.
enum PnvMedia {
    static let storage = "https://qojysegeddztsxdmhjfb.supabase.co/storage/v1/object/public"
    static let functions = "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1"
    static let r2 = "https://pub-717724c730914707b0f97e6bcc443a21.r2.dev"

    /// JavaScript's encodeURIComponent: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ).
    static func encodeComponent(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// R2 keys carry slashes that must survive, so each segment is encoded on its own.
    static func encodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { encodeComponent(String($0)) }.joined(separator: "/")
    }

    private static func stem(_ row: PnvRow) -> String? {
        guard let s = row.resource_endpoint, !s.isEmpty else { return nil }
        return s
    }

    private static func url(_ text: String?) -> URL? {
        text.flatMap { URL(string: $0) }
    }

    /// Khajistan TV's one still per programme: thumb, medium and poster at once.
    private static func ktvStill(_ s: String) -> String {
        "\(storage)/khajistan-tv-posters/\(encodePath(s)).jpg"
    }

    /// The small still: grid thumbnails.
    static func thumb(_ row: PnvRow) -> URL? {
        guard let s = stem(row) else { return nil }
        if row.isKtv { return url(ktvStill(s)) }
        if row.media_host == "r2" {
            return url("\(r2)/\(encodePath(s + (row.resource_type == "video" ? "_thumb_sm.webp" : "_sm.webp")))")
        }
        return url("\(storage)/khajistan-digital-archive-sm/\(encodePath(s)).webp")
    }

    /// The medium still (KJMedia.mediumThumb with no slot width, which is how the page calls it).
    /// Supabase has one thumbnail bucket, so it answers with the small URL.
    static func medium(_ row: PnvRow) -> URL? {
        guard let s = stem(row) else { return nil }
        if row.isKtv { return url(ktvStill(s)) }
        if row.media_host == "r2" {
            return url("\(r2)/\(encodePath(s + (row.resource_type == "video" ? "_thumb_med.webp" : "_med.webp")))")
        }
        return thumb(row)
    }

    /// A video's poster frame. A row that is not a video has none.
    static func poster(_ row: PnvRow) -> URL? {
        guard row.resource_type == "video", let s = stem(row) else { return nil }
        if row.isKtv { return url(ktvStill(s)) }
        if row.media_host == "r2" { return url("\(r2)/\(encodePath(s + "_thumb.jpg"))") }
        return url("\(storage)/khajistan-digital-archive-sm/\(encodePath(s)).webp")
    }

    /// The object itself: the picture, or the video file. For `ktv` the video is not an object
    /// anywhere; this is the tv-play address, which needs the viewer's session.
    static func full(_ row: PnvRow) -> URL? {
        guard let s = stem(row) else { return nil }
        if row.isKtv { return url("\(functions)/tv-play?id=\(encodeComponent(s))") }
        let ext = row.resource_type == "video" ? ".mp4" : ".jpg"
        if row.media_host == "r2" { return url("\(r2)/\(encodePath(s + ext))") }
        return url("\(storage)/khajistan-digital-archive/\(encodePath(s))\(ext)")
    }

    /// What a grid tile draws (kj-browse-archive.js tile()): a video's poster or thumb, a
    /// picture's medium or thumb.
    static func tile(_ row: PnvRow) -> URL? {
        row.isVideo ? (poster(row) ?? thumb(row)) : (medium(row) ?? thumb(row))
    }

    /// What the viewer tries, in order (the page's srcCandidates for a picture): the file, then
    /// the medium, then the small one. Duplicates are dropped.
    static func pictureCandidates(_ row: PnvRow) -> [URL] {
        var seen = Set<URL>()
        return [full(row), medium(row), thumb(row)].compactMap { $0 }.filter { seen.insert($0).inserted }
    }
}

// MARK: - Regions (kj-regions.js)

enum PnvRegions {
    /// The page folds Egypt-the-country into Mashriq (FLAG-184, owner 2026-09-09): FOLD.
    static func fold(_ token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        return token == "egypt-nile" ? "arabia" : token
    }

    /// KJ_REGIONS.label(): the key `egypt` is the Maghreb (kj-regions.js:62). An unknown key
    /// stands for itself, as the site's label() returns it.
    static func label(_ token: String) -> String {
        switch token {
        case "arabia": return "Mashriq"
        case "persia": return "Persia"
        case "khorasan": return "Khorasan"
        case "indus": return "Indus"
        case "egypt": return "Maghreb"
        case "anatolia": return "Anatolia"
        default: return token
        }
    }

    /// Tabs read west to east, as the Receiver's strip does. A token the roster carries that is
    /// not named here follows, alphabetically.
    static let westToEast = ["egypt", "arabia", "anatolia", "persia", "khorasan", "indus"]

    static func ordered(_ tokens: Set<String>) -> [String] {
        westToEast.filter(tokens.contains) + tokens.subtracting(westToEast).sorted()
    }

    /// token -> account keys, folded. Accounts with no token belong to no region.
    static func accountKeysByRegion(_ accounts: [PnvAccount]) -> [String: [String]] {
        var by: [String: [String]] = [:]
        for account in accounts {
            guard let token = fold(account.region_token) else { continue }
            by[token, default: []].append(account.account_key)
        }
        return by
    }
}

// MARK: - The query (kj-browse-archive.js)

enum PnvAPI {
    static let columns = "media_key,account,account_key,shortcode,child_index,kind,resource_type,media_host,resource_endpoint,width,height,tags,taken_at,corpus,feed_rank,da_id"
    static let pageSize = 60

    private static func rest(_ pathAndQuery: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "/rest/v1/" + pathAndQuery, relativeTo: KJConfig.supabase)!.absoluteURL)
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// The roster. A row is shown only if its account is on it (fail closed: no roster, nothing).
    static func accountsRequest() -> URLRequest {
        rest("pnv_accounts?select=slug,handle,url,platform,region,region_token,country,corpus,account_key")
    }

    /// `sb.rpc('pnv_facets')`.
    static func facetsRequest() -> URLRequest {
        var request = rest("rpc/pnv_facets")
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// A PostgREST list member: bare when it is plain, quoted when it is not.
    static func listMember(_ value: String) -> String {
        let plain = !value.isEmpty && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 95 || $0 == 45
        }
        if plain { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// One page of the feed: `.in('account_key', keys)`, the kind filter when there is one, ordered
    /// feed_rank then corpus (which interleaves the two halves of the room), `limit` and `offset`
    /// as `.range()` writes them. The first page asks for the exact count.
    static func pageRequest(keys: [String], kind: PnvKind?, offset: Int, wantCount: Bool) -> URLRequest {
        var parts = ["select=" + columns, "account_key=in.(" + keys.map(listMember).joined(separator: ",") + ")"]
        if let kind { parts.append("kind=eq.\(kind.rawValue)") }
        parts += ["order=feed_rank.asc,corpus.asc", "limit=\(pageSize)", "offset=\(offset)"]
        var request = rest("pnv_media?" + parts.joined(separator: "&"))
        if wantCount { request.setValue("count=exact", forHTTPHeaderField: "Prefer") }
        return request
    }

    /// The total out of `Content-Range: 0-59/99474`. "*" (an unknown total) and anything else is nil.
    static func total(fromContentRange header: String?) -> Int? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        return Int(header[header.index(after: slash)...])
    }

    /// The account keys a view may draw from: the whole roster, one region's share of it, or none
    /// (nil) when the region has no accounts. Mirrors accountKeys() in the page.
    static func accountKeys(roster: [PnvAccount], region: String?) -> [String]? {
        if roster.isEmpty { return nil }
        guard let region else { return roster.map(\.account_key) }
        let keys = PnvRegions.accountKeysByRegion(roster)[region] ?? []
        return keys.isEmpty ? nil : keys
    }

    // MARK: Summary line

    /// "99,474 pictures and videos · 81 accounts · 6 regions", or "81 accounts" when the counts
    /// did not load (fillLists() in the page). An account counts unless the facets give it zero.
    static func summary(roster: [PnvAccount], facets: PnvFacets?) -> String {
        let byAccount = Dictionary((facets?.accounts ?? []).map { ($0.slug, $0.media) }, uniquingKeysWith: { first, _ in first })
        let active = roster.filter { account in
            guard let n = byAccount[account.account_key] else { return true }
            return n == nil || n! > 0
        }.count
        let regions = PnvRegions.accountKeysByRegion(roster).count
        if let total = facets?.totals?.media {
            return "\(total.formatted()) pictures and videos \u{00B7} \(active) accounts \u{00B7} \(regions) regions"
        }
        return "\(roster.count) accounts"
    }

    // MARK: Captions

    /// A caption sits beside the row, not on it: dba_posts.caption for the account half,
    /// digital_archive.description for the other. Khajistan TV rows have neither.
    static func captionRequest(for row: PnvRow) -> URLRequest? {
        if row.corpus == "dba", let code = row.shortcode, !code.isEmpty {
            return rest("dba_posts?select=shortcode,caption&shortcode=in.(\(listMember(code)))")
        }
        if let id = row.da_id {
            return rest("digital_archive?select=id,description&id=in.(\(id))")
        }
        return nil
    }

    private struct CaptionRow: Decodable {
        let caption: String?
        let description: String?
    }

    /// The text the viewer prints: links and hashtags taken out and whitespace collapsed, as the
    /// page does. Nil when nothing is left.
    static func caption(from data: Data) -> String? {
        guard let first = (try? JSONDecoder().decode([CaptionRow].self, from: data))?.first,
              let raw = first.caption ?? first.description else { return nil }
        return cleanCaption(raw)
    }

    static func cleanCaption(_ raw: String) -> String? {
        var text = raw
        for pattern in ["https?://\\S+", "#[^\\s#]+"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Whether an account has already confirmed 18+ (pics-n-vids.js reads the same column for the
    /// same reason): the signed-in viewer's own profile row, read with their own token. Nil when
    /// the id is not a plain id, so a malformed one cannot add filters.
    static func profileRequest(userId: String, accessToken: String) -> URLRequest? {
        guard !userId.isEmpty, userId.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || $0 == 45 }) else { return nil }
        var request = rest("profiles?select=nsfw_age_confirmed&id=eq.\(userId)")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Viewer metadata

    /// "Picture · Mashriq · Aug 27, 2026 · 1170×2080", the viewer's one line (adapt() in the page).
    static func metaLine(for row: PnvRow, regionToken: String?, date: (String) -> String?) -> String {
        var pieces = [row.isVideo ? "Video" : "Picture"]
        if let regionToken, !regionToken.isEmpty { pieces.append(PnvRegions.label(regionToken)) }
        if let taken = row.taken_at, let text = date(taken) { pieces.append(text) }
        if let w = row.width, let h = row.height, w > 0 { pieces.append("\(w)\u{00D7}\(h)") }
        return pieces.joined(separator: " \u{00B7} ")
    }
}

// MARK: - The stream's layout (kj-browse-archive.js place())

enum PnvLayout {
    /// Column assignment: each row goes to the shortest column so far, a row's height being its
    /// own shape (height over width, 1 when unknown) plus a 0.03 gutter. Rows only ever append,
    /// so adding a page never moves a tile already placed.
    static func columns(_ rows: [PnvRow], count: Int) -> [[PnvRow]] {
        guard count > 0 else { return [] }
        var cols = Array(repeating: [PnvRow](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for row in rows {
            var shortest = 0
            for k in 1..<count where heights[k] < heights[shortest] { shortest = k }
            heights[shortest] += (row.aspect.map { 1 / $0 } ?? 1) + 0.03
            cols[shortest].append(row)
        }
        return cols
    }
}

// MARK: - The adult notice (kj-adult-notice.js)

/// The notice is not a gate. It states what the archive holds and gets out of the way: no overlay,
/// nothing blocked, nothing granted. The wording is the policy file's, verbatim.
enum AdultNotice {
    static let key = "kj_adult_notice"
    static let heading = "This archive holds adult material."
    static let body = "Khajistan keeps the printed and recorded record of the region as it was made \u{2014} including sexology, erotica, film and material that was censored at the time. Some of it is explicit."
    static let dontAskAgain = "Don\u{2019}t ask again"
    static let ok = "OK"

    /// shouldShow() in the site's file. `stored` is the device store ("dismissed" is never again),
    /// `session` the session store ("ok" is not again this session), `confirmed18` an account that
    /// has already confirmed 18+, which never sees it.
    static func shouldShow(stored: String?, session: String?, confirmed18: Bool) -> Bool {
        if confirmed18 { return false }
        if stored == "dismissed" { return false }
        if session == "ok" { return false }
        return true
    }
}
