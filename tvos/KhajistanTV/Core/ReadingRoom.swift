import Foundation

// The Reading Room, as the website's reading-room.html and scripts/reading-room-app.js read it.
// Everything here is pure: rows in, titles out, answers in, decisions out. The network lives in
// Services/ReadingStore.swift. Line numbers below are reading-room-app.js as of 2026-10-06.
//
// What the app takes from the site and what it asks the server:
//   - WHICH titles exist: the reading_room_catalogue() RPC (the shelf is rr_catalogue_mv behind
//     it), grouped into titles as boot() groups it (:2017-2113). Nothing is read from
//     digital_archive_collections or digital_archive that the site's anonymous visitor cannot
//     read, and a row hidden from the catalogue is never asked for.
//   - WHO may read a page: the reading-room-page edge function, which is the gate. The app never
//     keeps its own list of free, account-open or members' titles (the site keeps three, in
//     lockstep with the function, :1400-1520); it asks the function and shows its answer. A
//     title's access line is the answer the function gives an anonymous visitor for a page past
//     the free preview, so it cannot disagree with what a page request then does.

// MARK: - Catalogue rows

/// One issue of a collection, as the RPC lists it. `childSlug` is set by the absorb pass when a
/// per-issue collection holds the better copy of this issue (:2037).
struct RRIssueRow: Decodable, Equatable, Sendable {
    var id: String?
    var label: String?
    var pages: Int
    var childSlug: String?

    init(id: String?, label: String?, pages: Int, childSlug: String? = nil) {
        self.id = id
        self.label = label
        self.pages = pages
        self.childSlug = childSlug
    }

    private enum CodingKeys: String, CodingKey { case id, label, pages }

    /// `Number(i.pages) || 0`: a count may arrive as a number or as text, and anything else is 0.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try? box.decode(String.self, forKey: .id)
        label = try? box.decode(String.self, forKey: .label)
        if let whole = try? box.decode(Int.self, forKey: .pages) {
            pages = whole
        } else if let fraction = try? box.decode(Double.self, forKey: .pages), fraction.isFinite {
            pages = Int(fraction)
        } else if let text = try? box.decode(String.self, forKey: .pages), let whole = Int(text) {
            pages = whole
        } else {
            pages = 0
        }
    }
}

/// One row of reading_room_catalogue(): a collection and the issues it serves.
struct RRCollection: Decodable, Equatable, Sendable {
    let collection_slug: String
    let collection_title: String?
    let collection_region: String?
    var issues: [RRIssueRow]?

    init(slug: String, title: String?, region: String?, issues: [RRIssueRow]?) {
        collection_slug = slug
        collection_title = title
        collection_region = region
        self.issues = issues
    }
}

/// A feed row that does not decode is dropped, never the whole feed: one bad row must not empty the shelf.
struct RRLossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Titles

/// One issue of a title, addressed by the storage folder it lives in.
struct RRIssue: Equatable, Identifiable, Sendable {
    /// Where the pages are: the collection's slug, or the child collection's that holds a better copy.
    let slug: String
    /// The issue id as stored; empty for a collection ingested as one issue.
    let id: String
    let label: String
    let pages: Int
    /// Position in its title, which is what tells two issues with one id apart.
    let index: Int

    var key: String { "\(slug)|\(id)|\(index)" }
}

/// One title on the shelf: a publication, which may be several collections (:2079-2113).
struct RRTitle: Equatable, Identifiable, Sendable {
    let slug: String
    let name: String
    let native: String
    let region: String
    let memberSlugs: [String]
    let issues: [RRIssue]

    var id: String { slug }

    var pageTotal: Int { issues.reduce(0) { $0 + $1.pages } }

    /// Era where a title has one (none comes from the feed), else the region's name, else nothing (:2389).
    var byline: String { RRRegions.label(region) }

    /// The page the card shows: the declared cover page, else the first page (rrCoverPage, :1499).
    var coverPage: Int { RRPath.coverPages[slug] ?? 1 }
}

/// Region tokens, as the shelf names them (REGION_DISPLAY :1028, RR_REGION_UMBRELLA :2417).
enum RRRegions {
    static let display: [String: String] = [
        "arabia": "Mashriq", "egypt": "Maghreb", "persia": "Persia", "indus": "Indus",
        "hindustan": "Delhi \u{00B7} Awadh", "dakhan": "Dakhan", "khorasan": "Khorasan",
        "anatolia": "Anatolia", "british-india": "British India",
    ]
    /// A finer token answers to its umbrella.
    static let umbrella: [String: String] = [
        "arabia": "arabia", "levant": "arabia", "mesopotamia": "arabia",
        "egypt": "egypt", "maghreb": "egypt",
        "persia": "persia", "iran": "persia",
        "indus": "indus", "hindustan": "hindustan", "dakhan": "dakhan", "khorasan": "khorasan",
        "anatolia": "anatolia", "british-india": "british-india",
    ]
    /// The order the rows take when the module index is not available: west to east, as the receiver lists regions.
    static let order = ["arabia", "egypt", "anatolia", "persia", "khorasan", "indus", "hindustan", "dakhan", "british-india"]

    /// A display name, or nothing: an unfiled title shows a blank where a slug would be wrong (:2400-2420).
    static func label(_ token: String) -> String {
        display[token] ?? umbrella[token].flatMap { display[$0] } ?? ""
    }
}

// MARK: - Grouping

private struct RRFamily {
    let slug: String
    let prefix: String
    let name: String
    let native: String
    /// 'split' takes rrSplitTitle's parenthetical; 'strip' takes the title minus the family name.
    let split: Bool
}

enum RRCatalogue {
    /// The declared families (RR_SLUG_FAMILIES :1193): publications whose every issue is its own collection.
    private static let families = [
        RRFamily(slug: "gol-agha", prefix: "gol-agha-", name: "Gol Agha", native: "\u{06AF}\u{0644}\u{200C}\u{0622}\u{0642}\u{0627}", split: false),
        RRFamily(slug: "28-cinema", prefix: "28-cinema-", name: "Cinema", native: "\u{0633}\u{06CC}\u{0646}\u{0645}\u{0627}", split: false),
        RRFamily(slug: "49-film-and-art", prefix: "49-film-and-art-", name: "Film and Art", native: "\u{0641}\u{06CC}\u{0644}\u{0645} \u{0648} \u{0647}\u{0646}\u{0631}", split: true),
        RRFamily(slug: "molla-nasraddin", prefix: "molla-nasraddin-", name: "Molla Nasredin", native: "\u{0645}\u{0644}\u{0627} \u{0646}\u{0635}\u{0631}\u{0627}\u{0644}\u{062F}\u{06CC}\u{0646}", split: true),
        RRFamily(slug: "nigar", prefix: "nigar-", name: "Nigar", native: "\u{0646}\u{06AF}\u{0627}\u{0631}", split: false),
    ]

    private static let editionLanguages: Set<String> = [
        "arabic", "urdu", "persian", "farsi", "pashto", "dari", "english", "punjabi", "sindhi", "balochi",
        "turkish", "kurdish", "hebrew", "azerbaijani", "french", "russian",
    ]

    /// rrIsEditionLanguage (:1160): a language in the parenthesis names a different object, not a different issue.
    static func isEditionLanguage(_ label: String?) -> Bool {
        editionLanguages.contains((label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: whole) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// rrSplitTitle (:1126): [family, label] only where the title declares its label itself.
    static func splitTitle(_ title: String) -> (base: String, label: String)? {
        if let m = firstMatch(#"^(.*?)\s*\((.+)\)\s*$"#, in: title), let base = m[1], let label = m[2], !trimmed(base).isEmpty {
            return (trimmed(base), trimmed(label))
        }
        for separator in [" \u{2014} ", " \u{2013} "] {
            if let range = title.range(of: separator), range.lowerBound > title.startIndex {
                return (trimmed(String(title[..<range.lowerBound])), trimmed(String(title[range.upperBound...])))
            }
        }
        if let m = firstMatch(#"^(.*?),\s*(part\s+\S+)\s*$"#, in: title, options: [.caseInsensitive]),
           let base = m[1], let label = m[2], !trimmed(base).isEmpty {
            return (trimmed(base), trimmed(label))
        }
        return nil
    }

    /// rrTitleKey (:1142): case, spacing and punctuation only. Letters and digits in any script survive.
    static func titleKey(_ title: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in title.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                out.append(scalar)
            default:
                break
            }
        }
        return String(out)
    }

    /// rrFamilyLabel (:1212): the issue designator out of the recorded title, never invented.
    private static func familyLabel(_ family: RRFamily, title: String?, slug: String) -> String {
        let text = trimmed(title ?? "")
        if family.split, let parts = splitTitle(text), !parts.label.isEmpty { return parts.label }
        if text.lowercased().hasPrefix(family.name.lowercased()) {
            let rest = text.dropFirst(family.name.count)
                .drop(while: { " \t\n:\u{2014}\u{2013}-".contains($0) })
            let cleaned = trimmed(String(rest))
            if !cleaned.isEmpty { return cleaned }
        }
        return text.isEmpty ? slug : text
    }

    private static func pageTotal(_ collection: RRCollection) -> Int {
        (collection.issues ?? []).reduce(0) { $0 + $1.pages }
    }

    private struct Member {
        let collection: RRCollection
        let label: String?
    }

    private struct Bucket {
        var family: RRFamily?
        var base: String
        var region: String?
        var members: [Member]
    }

    /// The titles the shelf shows for a catalogue feed, in the order boot() builds them (:2017-2113).
    /// The seeds the site keeps for 24 titles (names and issue labels typed by hand) are not read.
    static func titles(from feed: [RRCollection]) -> [RRTitle] {
        var cols = feed
        var index: [String: Int] = [:]
        for (i, c) in cols.enumerated() { index[c.collection_slug] = i }

        // A per-issue collection its own parent already carries is absorbed into that parent (:2022-2032).
        var absorbed: [(child: String, parent: Int, match: Int)] = []
        var absorbedSlugs = Set<String>()
        for c in cols {
            let s = c.collection_slug
            var cut = s.firstIndex(of: "-")
            while let at = cut, at > s.startIndex {
                if let parentIndex = index[String(s[..<at])] {
                    let suffix = String(s[s.index(after: at)...])
                    if let match = (cols[parentIndex].issues ?? []).firstIndex(where: { ($0.id ?? "") == suffix }) {
                        absorbed.append((s, parentIndex, match))
                        absorbedSlugs.insert(s)
                        break
                    }
                }
                cut = s[s.index(after: at)...].firstIndex(of: "-")
            }
        }
        // The parent serves the child's own copy where that copy is at least as complete (:2037).
        for a in absorbed {
            guard let childIndex = index[a.child] else { continue }
            let own = pageTotal(cols[childIndex])
            if own >= cols[a.parent].issues![a.match].pages {
                cols[a.parent].issues![a.match].childSlug = a.child
                cols[a.parent].issues![a.match].pages = own
            }
        }

        var order: [String] = []
        var buckets: [String: Bucket] = [:]
        for c in cols where !absorbedSlugs.contains(c.collection_slug) {
            let slug = c.collection_slug
            let title = c.collection_title ?? ""
            if let family = families.first(where: { slug.hasPrefix($0.prefix) }) {
                let key = "f:" + family.slug
                if buckets[key] == nil {
                    order.append(key)
                    buckets[key] = Bucket(family: family, base: family.name, region: c.collection_region, members: [])
                }
                buckets[key]!.members.append(Member(collection: c, label: familyLabel(family, title: title, slug: slug)))
                continue
            }
            // A title with no designator buckets on the title itself, a language designator stays in the key.
            let parts = splitTitle(title)
            let head: String
            if let parts, isEditionLanguage(parts.label) {
                head = trimmed(title)
            } else {
                head = parts?.base ?? trimmed(title)
            }
            let tkey = titleKey(head)
            let key = tkey.isEmpty ? "s:" + slug : "g:" + tkey + "|" + (c.collection_region ?? "")
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = Bucket(family: nil, base: head, region: c.collection_region, members: [])
            }
            buckets[key]!.members.append(Member(collection: c, label: parts?.label))
        }

        return order.compactMap { key in buckets[key].flatMap(makeTitle) }
    }

    private static func makeTitle(_ bucket: Bucket) -> RRTitle? {
        guard let head = bucket.members.first?.collection else { return nil }
        let grouped = bucket.family != nil || (!bucket.base.isEmpty && bucket.members.count > 1)
        let members: [Member]
        if grouped {
            // Numeric collation, so Weekly No.9 sorts before No.10 (:2085).
            members = bucket.members.enumerated().sorted { a, b in
                let order = a.element.collection.collection_slug.compare(
                    b.element.collection.collection_slug, options: [.numeric], range: nil, locale: Locale(identifier: "en"))
                return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
            }.map(\.element)
        } else {
            members = bucket.members
        }
        let cardSlug = bucket.family?.slug ?? head.collection_slug
        let headTitle = (head.collection_title ?? "").isEmpty ? head.collection_slug : head.collection_title!
        let title = grouped ? bucket.base : headTitle
        let native: String
        if let family = bucket.family {
            native = family.native
        } else {
            native = firstMatch("[\u{0600}-\u{06FF}][^()]*", in: title)?[0].map(trimmed) ?? ""
        }
        let name = isEditionLanguage(splitTitle(title)?.label)
            ? trimmed(title)
            : trimmed(title.components(separatedBy: "(")[0])
        var issues: [RRIssue] = []
        for member in members {
            let c = member.collection
            let rows = c.issues ?? []
            for row in rows {
                let rawId = row.id ?? ""
                let label: String
                if let override = member.label, !override.isEmpty, rows.count == 1 {
                    label = override
                } else if let own = row.label, !own.isEmpty, own != c.collection_slug {
                    label = own
                } else if let override = member.label, !override.isEmpty {
                    label = override
                } else {
                    label = rawId.isEmpty ? "Issue" : rawId
                }
                issues.append(RRIssue(
                    slug: row.childSlug ?? c.collection_slug,
                    id: row.childSlug != nil ? "" : (rawId == c.collection_slug ? "" : rawId),
                    label: label, pages: max(row.pages, 0), index: issues.count))
            }
        }
        let region = (head.collection_region ?? "").isEmpty ? "unknown" : head.collection_region!
        return RRTitle(slug: cardSlug, name: name, native: native, region: region,
                       memberSlugs: members.map { $0.collection.collection_slug }, issues: issues)
    }
}

// MARK: - Where a page lives

enum RRPath {
    /// Four-digit page ids: the University of Pennsylvania consignment was ingested with `-p0001` (:335).
    static let pad4: Set<String> = [
        "naujawano-mein-jinsi-khauf-aur-iska-tadaruk-karwan-e-adab-pu",
        "urdu-afsane-mein-jins-ki-riwayat-poorab-academy",
    ]

    /// Collections whose objects sit under another folder (RR_STORAGE_FOLDER :1070). An endpoint is where a file IS.
    static let storageFolder: [String: String] = {
        var map: [String: String] = [:]
        for slug in ["akhbar-e-jahan", "chitrali", "devta", "dhanak", "family", "film-asia", "hum-nashin",
                     "international-film", "mujahid", "palak", "roman", "rubi", "sadiyon-ka-beta", "shama",
                     "shatir", "shikari", "show-business", "starlight", "tiger", "tv-times", "ujala", "waheed-murad"] {
            map["oak-" + slug] = "oak-digests"
        }
        map["shama-delhi"] = "shama-periodical"
        map["oak-shama-delhi"] = "oak-digests"
        return map
    }()

    /// Titles whose first page is not their cover (RR_COVER_PAGE :1459). The scans are untouched; this picks the card's page.
    static let coverPages: [String: Int] = [
        "badee-jantri-kanpur-1899": 2, "badee-jantri-kanpur-1904": 4, "khursheed-e-aalam-jantri-1936": 2,
        "mashhoor-e-aalam-jantri-1923": 3, "taqweem-e-yak-sad-wa-do-sala": 2,
        "tilism-e-hoshruba": 2, "deewan-rekhti": 2,
        "dewaan-e-jan-sahib": 6, "tarikh-i-rikhti": 5, "tazkirah-rekhti": 2,
        "ajaib-al-makhluqat-qazvini": 2,
        "asrar-i-qasimi-matn-kamil": 2, "naqsh-i-sulaymani-kamil": 2,
        "tilism-i-iskandar-1": 3, "majmua-khatti-66": 3, "mujarrabat-al-dayrabi": 5,
        "ziya-al-absar": 2,
        "peykar": 2, "majmua-aqlam-ghariba": 2, "dorushayi-az-maktab-eslam": 2,
        "forugh-e-elm": 2, "maaref": 2, "peyk-e-cinema": 2,
        "moslemin": 4, "majmua-tilism-iskandar": 5, "jami-al-daawat-kabir": 6, "khawass-al-hayawan": 4,
    ]

    private static func pad(_ slug: String, _ page: Int, extra: Set<String>) -> String {
        let width = (pad4.contains(slug) || extra.contains(slug)) ? 4 : 3
        let text = String(page)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// issueEp (:1095): `<folder>/<stem>-pNNN`. `extra` holds the slugs a four-digit retry has proved.
    static func endpoint(_ issue: RRIssue, page: Int, extra: Set<String> = []) -> String {
        let slug = issue.slug
        var id = issue.id
        if let folder = storageFolder[slug], !id.isEmpty { return "\(folder)/\(id)-p\(pad(slug, page, extra: extra))" }
        if id == slug { id = "" }
        let stem = id.isEmpty ? "\(slug)-p\(pad(slug, page, extra: extra))" : "\(slug)-\(id)-p\(pad(slug, page, extra: extra))"
        return "\(slug)/\(stem)"
    }

    /// signedUrl()'s retry (:126): a three-digit page that is not found may be a four-digit object.
    static func fourDigitTwin(of endpoint: String) -> (slug: String, path: String)? {
        guard let slash = endpoint.firstIndex(of: "/") else { return nil }
        let slug = String(endpoint[..<slash])
        let leaf = endpoint[endpoint.index(after: slash)...]
        guard !pad4.contains(slug), leaf.count > 4 else { return nil }
        let digits = leaf.suffix(3)
        let stem = leaf.dropLast(3)
        guard digits.allSatisfy(\.isNumber), stem.hasSuffix("-p") else { return nil }
        return (slug, "\(slug)/\(stem)0\(digits)")
    }

    /// The stem every page of an issue shares: its page-1 endpoint without the `-p001` (rrLoadPageMap :3458).
    static func issuePrefix(_ issue: RRIssue, extra: Set<String> = []) -> String {
        let first = endpoint(issue, page: 1, extra: extra)
        guard let range = first.range(of: #"-p0*1$"#, options: .regularExpression) else { return first }
        return String(first[..<range.lowerBound])
    }

    /// The first page the card of a title shows: its declared cover page for the first issue, else page 1.
    static func coverEndpoint(_ title: RRTitle, extra: Set<String> = []) -> String? {
        guard let first = title.issues.first else { return nil }
        return endpoint(first, page: title.coverPage, extra: extra)
    }

    /// An issue's own cover in the title view: the title's cover page for the first issue, page 1 for the rest (:6676).
    static func issueCoverEndpoint(_ title: RRTitle, _ issue: RRIssue, extra: Set<String> = []) -> String {
        endpoint(issue, page: issue.index == 0 ? title.coverPage : 1, extra: extra)
    }

    /// A page past the free preview, to ask what an anonymous visitor may read: three, or one past a declared
    /// cover. `skipping` asks for a later page, for the title whose page 3 is not on the shelf (a page taken
    /// off it answers 404 before any gate is consulted). A title with no issue long enough has none, and its
    /// access line is left out rather than guessed.
    static func probeEndpoint(_ title: RRTitle, skipping: Int = 0, extra: Set<String> = []) -> String? {
        let page = max(title.coverPage, 2) + 1 + skipping
        guard let issue = title.issues.first(where: { $0.pages >= page }) else { return nil }
        return endpoint(issue, page: page, extra: extra)
    }
}

// MARK: - The page server's answers

/// What reading-room-page said about one page. The function is the gate: its status and body are
/// the decision, and nothing here second-guesses them (supabase/functions/reading-room-page/index.ts, decide()).
struct RRPageAnswer: Equatable, Sendable {
    let status: Int
    let url: URL?
    let gated: Bool
    let accountRequired: Bool
    let rightsPending: Bool
    let outsideScope: Bool
    let annualRequired: Bool
    let closed: Bool
    /// Seconds the signed URL lives, as the server set it: shorter near a reading window's close.
    let ttl: Int?

    /// How long this answer may be reused before the server is asked again: an allowed page for
    /// eight minutes or its own URL's life less ten seconds, whichever is shorter; a rights hold for
    /// eight minutes; a gate for one minute, so a pass bought elsewhere opens the page soon. Any
    /// other answer (a fault, a rate limit, a missing page) is not reused at all.
    var reuseFor: TimeInterval? {
        switch status {
        case 200:
            let life = min(480, ttl.map { TimeInterval($0 - 10) } ?? 480)
            return life > 0 ? life : nil
        case 451: return 480
        case 401, 403: return 60
        default: return nil
        }
    }

    /// A signed URL must name Supabase storage on the project's own host; any other address is not an answer.
    static func isProjectURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == KJConfig.supabase.host
    }

    init(status: Int, object: [String: Any]) {
        self.status = status
        if let text = object["url"] as? String, let url = URL(string: text), Self.isProjectURL(url) {
            self.url = url
        } else {
            url = nil
        }
        gated = object["gated"] as? Bool ?? false
        accountRequired = object["accountRequired"] as? Bool ?? false
        rightsPending = object["rightsPending"] as? Bool ?? false
        outsideScope = object["outsideScope"] as? Bool ?? false
        annualRequired = object["annualRequired"] as? Bool ?? false
        closed = (object["error"] as? String) == "reading_room_closed"
        ttl = object["ttl"] as? Int
    }

    /// A single-path answer: the HTTP status and the body.
    static func parse(status: Int, body: Data) -> RRPageAnswer {
        RRPageAnswer(status: status, object: (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])
    }

    /// A batch answer: one entry per path, each with its own status (`{"results": {path: {status, ...}}}`).
    static func parseBatch(_ body: Data) -> [String: RRPageAnswer] {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let results = root["results"] as? [String: Any] else { return [:] }
        var out: [String: RRPageAnswer] = [:]
        for (path, value) in results {
            guard let entry = value as? [String: Any], let status = entry["status"] as? Int else { continue }
            out[path] = RRPageAnswer(status: status, object: entry)
        }
        return out
    }
}

/// How a title is offered to an anonymous visitor (magCard :2385-2416).
enum RRAccess: Equatable, Sendable {
    case open
    case accountOpen
    case members
    case rightsPending

    /// The access line on a card, in the shelf's own words.
    var tag: String {
        switch self {
        case .open: return "Free \u{2014} read in full"
        case .accountOpen: return "Free \u{2014} sign in to read"
        case .members: return "Members"
        case .rightsPending: return "Rights pending"
        }
    }

    /// The anonymous answer for a page past the preview. Nil where the function gave no verdict (a page
    /// that does not exist, a fault): no line is better than a guessed one.
    static func classify(_ answer: RRPageAnswer?) -> RRAccess? {
        guard let answer else { return nil }
        switch answer.status {
        case 200: return .open
        case 451: return .rightsPending
        case 401: return answer.accountRequired ? .accountOpen : .members
        case 403: return .members
        default: return nil
        }
    }
}

/// What the reader does with one page's answer.
enum RRPageOutcome: Equatable, Sendable {
    case page(URL)
    /// A free title that wants an account (401 with accountRequired).
    case signIn
    /// A paid title, and the viewer does not hold the pass (401 or 403, gated).
    case members
    /// Rights pending: the site returns 451 and shows no page.
    case rights
    /// A residency reading window is closed.
    case closed
    /// The scan is not in the archive (404).
    case missing
    /// A fault on the server's side, worth a second try.
    case unavailable

    static func decide(_ answer: RRPageAnswer) -> RRPageOutcome {
        if answer.status == 451 || answer.rightsPending { return .rights }
        if answer.status == 200, let url = answer.url { return .page(url) }
        if answer.status == 401 && answer.accountRequired { return .signIn }
        if answer.closed { return .closed }
        if answer.status == 401 || answer.status == 403 || answer.gated { return .members }
        if answer.status == 404 { return .missing }
        return .unavailable
    }
}

// MARK: - Requests

enum RRAPI {
    static let pageFunction = KJConfig.supabase.appendingPathComponent("functions/v1/reading-room-page")
    static let feedPage = 1000

    private static func request(_ pathAndQuery: String, method: String = "GET", token: String? = nil, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: pathAndQuery, relativeTo: KJConfig.supabase)!.absoluteURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    /// One page of the shelf feed, ordered by collection_slug. The order is what makes paging correct,
    /// and a feed of exactly `feedPage` rows has not ended (FLAG-026, :1851-1946).
    static func catalogueRequest(offset: Int) -> URLRequest {
        request("/rest/v1/rpc/reading_room_catalogue?order=collection_slug.asc&limit=\(feedPage)&offset=\(offset)",
                method: "POST", body: Data("{}".utf8))
    }

    /// The collections held back for rights: cover only, every other page 451 (rrLoadRightsPending :1655).
    static func rightsRequest() -> URLRequest {
        request("/rest/v1/digital_archive_collections?select=collection_slug&rights_pending=eq.true&order=collection_slug.asc")
    }

    /// Custodian lines, as the title view's Provenance control reads them (rrLoadProvenance :1608).
    static func provenanceRequest(offset: Int) -> URLRequest {
        request("/rest/v1/digital_archive_collections?select=collection_slug,provenance_source,source_upstream,collection_tags"
                + "&or=(provenance_source.not.is.null,source_upstream.not.is.null,collection_tags.not.is.null)"
                + "&order=collection_slug.asc&limit=\(feedPage)&offset=\(offset)")
    }

    /// The live page numbers of an issue (rr_issue_pages, :3461): numbers only, hide and visibility applied by the database.
    static func pageNumbersRequest(prefix: String) -> URLRequest {
        let body = (try? JSONSerialization.data(withJSONObject: ["prefix": prefix])) ?? Data("{}".utf8)
        return request("/rest/v1/rpc/rr_issue_pages", method: "POST", body: body)
    }

    /// The pages of a collection that carry a content warning: the rows the site's reader reads (:7822),
    /// narrowed to the one state that warns (public_warning), visible pages only.
    static func sensitiveRequest(collection: String) -> URLRequest {
        request("/rest/v1/digital_archive?select=resource_endpoint,sensitive_flags"
                + "&collection_slug=eq.\(KJURL.encodeQueryValue(collection))&hide=eq.false&visibility_state=eq.public_warning")
    }

    /// One page: the viewer's token when signed in, the public key otherwise (:101-112).
    static func pageRequest(path: String, size: String, accessToken: String?) -> URLRequest {
        let body = (try? JSONSerialization.data(withJSONObject: ["path": path, "size": size])) ?? Data("{}".utf8)
        return pageCall(body: body, token: accessToken)
    }

    /// Up to 64 pages in one call, each answered on its own (the batch form, v37).
    static let batchLimit = 64
    static func batchRequest(paths: [String], size: String, accessToken: String?) -> URLRequest {
        let body = (try? JSONSerialization.data(withJSONObject: ["paths": Array(paths.prefix(batchLimit)), "size": size])) ?? Data("{}".utf8)
        return pageCall(body: body, token: accessToken)
    }

    private static func pageCall(body: Data, token: String?) -> URLRequest {
        var call = request("/functions/v1/reading-room-page", method: "POST", token: token, body: body)
        call.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return call
    }

    static func pageNumbers(from data: Data) -> [Int]? {
        try? JSONDecoder().decode([Int].self, from: data)
    }

    static func titles(fromFeed data: Data) -> [RRCollection]? {
        (try? JSONDecoder().decode([RRLossy<RRCollection>].self, from: data))?.compactMap(\.value)
    }

    static func slugs(fromRights data: Data) -> Set<String>? {
        struct Row: Decodable { let collection_slug: String }
        return (try? JSONDecoder().decode([RRLossy<Row>].self, from: data)).map { Set($0.compactMap { $0.value?.collection_slug }) }
    }
}

// MARK: - Provenance

struct RRProvenanceRow: Decodable, Equatable, Sendable {
    let collection_slug: String
    let provenance_source: String?
    let source_upstream: String?
    var collection_tags: [String]? = nil
}

/// The order of titles on a shelf, as the site ranks both shelves (owner, 2026-09-17: "the most
/// rare and khajistan scanned items should be on top", "the stamped ones always in bottom of the
/// lists"; reading-room-app.js rrRankKey :3104): tagged `rare` by the owner, then digitised by
/// Khajistan, then the rest, then a card whose cover is a library's stamp, slip or a blank board.
/// Each run keeps the order it had.
enum RRRank {
    /// RR_STAMPED (:1586), the site's hand-kept list.
    static let stamped: Set<String> = [
        "dar-al-islam", "dar-al-salam", "moslemin", "peykar",
        "majmua-tilism-iskandar", "majmua-aqlam-ghariba",
        "asrar-i-qasimi-khatti", "niru-ye-havayi-artesh-shahanshahi",
        "kandahar-majalla", "al-jihad-peshawar", "subh-i-ummid",
        "tilism-e-hoshruba",
        "majma-al-daawat-121", "majma-al-daawat-129", "hamidiye-1059", "jami-al-daawat-kabir",
        "dorushayi-az-maktab-eslam", "forugh-e-elm", "maaref", "peyk-e-cinema",
        "raml-awfaq-ghariba", "raml-khatti", "masjed-e-azam", "khawass-al-hayawan", "sharh-dua-qaritha",
    ]

    /// 0 rare, 1 Khajistan scan, 2 the rest, 3 stamped. Stamped is the card's own slug, and
    /// outranks everything; rare and Khajistan are the best of the title's members.
    static func key(_ title: RRTitle, provenance: [String: RRProvenanceRow]) -> Int {
        if stamped.contains(title.slug) { return 3 }
        let rows = (title.memberSlugs.isEmpty ? [title.slug] : title.memberSlugs).compactMap { provenance[$0] }
        if rows.contains(where: { ($0.collection_tags ?? []).contains { $0.lowercased() == "rare" } }) { return 0 }
        if rows.contains(where: RRProvenance.isKhajistanScan) { return 1 }
        return 2
    }

    static func ranked(_ titles: [RRTitle], provenance: [String: RRProvenanceRow]) -> [RRTitle] {
        titles.enumerated()
            .sorted { (key($0.element, provenance: provenance), $0.offset) < (key($1.element, provenance: provenance), $1.offset) }
            .map(\.element)
    }

    static func ranked(_ tabs: [RRTab], provenance: [String: RRProvenanceRow]) -> [RRTab] {
        tabs.map { tab in
            RRTab(id: tab.id, name: tab.name, native: tab.native, depth: tab.depth,
                  rows: tab.rows.map { RRRow(id: $0.id, name: $0.name, titles: ranked($0.titles, provenance: provenance)) })
        }
    }
}

enum RRProvenance {
    static func rows(from data: Data) -> [RRProvenanceRow]? {
        (try? JSONDecoder().decode([RRLossy<RRProvenanceRow>].self, from: data))?.compactMap(\.value)
    }

    /// rrIsKhajistanScan (:1605): digitised by Khajistan. A title received from upstream is not.
    static func isKhajistanScan(_ row: RRProvenanceRow) -> Bool {
        (row.source_upstream ?? "").isEmpty && (row.provenance_source ?? "").range(of: "khajistan", options: .caseInsensitive) != nil
    }
}

// MARK: - Page numbers

enum RRPageMap {
    /// What the display positions of an issue stand for. A feed of live page numbers that is exactly 1...N
    /// changes nothing; any other (a page taken off the shelf leaves a hole) makes position i show stored
    /// page nums[i-1], and the issue's page count becomes the count of live pages (rrLoadPageMap :3455).
    static func resolve(_ numbers: [Int]?, declared: Int) -> (pages: Int, map: [Int]?) {
        guard let numbers, !numbers.isEmpty else { return (declared, nil) }
        if numbers.count == declared && numbers.last == numbers.count { return (declared, nil) }
        return (numbers.count, numbers)
    }

    static func stored(_ position: Int, map: [Int]?) -> Int {
        guard let map, !map.isEmpty else { return position }
        return map[min(max(1, position), map.count) - 1]
    }
}

// MARK: - A content warning

enum RRSensitive {
    private static let labels: [String: String] = [
        "blood": "blood", "dead_body": "a dead body", "war_casualty": "war casualties",
        "graphic_violence": "graphic violence", "possible_violence": "possible violence",
        "injury": "injury", "humiliation": "humiliation", "hate_symbol": "a hate symbol",
        "nudity": "nudity", "minor": "a minor", "child": "a child", "weapon": "a weapon",
    ]

    private struct Row: Decodable {
        let resource_endpoint: String
        let sensitive_flags: [String]?
    }

    /// The warned pages of a collection: endpoint to flags. A page with no flags is not warned (:7843).
    static func flags(from data: Data) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for row in ((try? JSONDecoder().decode([RRLossy<Row>].self, from: data)) ?? []).compactMap(\.value) {
            let flags = (row.sensitive_flags ?? []).filter { !$0.isEmpty }
            if !flags.isEmpty { out[row.resource_endpoint] = flags }
        }
        return out
    }

    /// rrSensPhrase (:7851): plain, factual, in the order given, each named once.
    static func phrase(_ flags: [String]) -> String {
        var seen = Set<String>()
        var named: [String] = []
        for flag in flags {
            let text = labels[flag] ?? flag.replacingOccurrences(of: "_", with: " ")
            if seen.insert(text).inserted { named.append(text) }
        }
        if named.isEmpty { return "material some readers will not want to see unannounced" }
        if named.count == 1 { return named[0] }
        return named.dropLast().joined(separator: ", ") + " and " + named[named.count - 1]
    }

    static func sentence(_ flags: [String]) -> String { "This page shows \(phrase(flags))." }
}

// MARK: - Shelves

struct RRModuleDef: Decodable, Equatable, Sendable {
    let key: String
    let name: String
    let native: String?
}

struct RRShelfDef: Decodable, Equatable, Sendable {
    let key: String
    let name: String
}

/// data/rr-modules.json: the language a collection is filed under and the shelf inside it. Assignment
/// only; every count is totalled from the titles.
struct RRModuleIndex: Decodable, Equatable, Sendable {
    struct Assignment: Decodable, Equatable, Sendable {
        let module: String?
        let shelf: String?
    }

    let modules: [RRModuleDef]
    let shelves: [RRShelfDef]
    let assign: [String: Assignment]

    static func parse(_ data: Data) -> RRModuleIndex? {
        guard let index = try? JSONDecoder().decode(RRModuleIndex.self, from: data), !index.modules.isEmpty else { return nil }
        return index
    }
}

struct RRRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let titles: [RRTitle]
}

struct RRTab: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let native: String?
    /// "N titles · M issues · P pages · K cover-only, pending rights" (rrDepthLine :2576).
    let depth: String
    let rows: [RRRow]
}

enum RRShelves {
    /// A title with no module is Unfiled (RR_UNFILED :2503).
    static let unfiledKey = "unfiled"

    static func isRights(_ title: RRTitle, rights: Set<String>) -> Bool { rights.contains(title.slug) }

    /// The room's own three figures, rights-held titles left out of them and named beside (:2576).
    static func depthLine(_ titles: [RRTitle], rights: Set<String>) -> String {
        let held = titles.filter { isRights($0, rights: rights) }
        let readable = titles.filter { !isRights($0, rights: rights) }
        let issues = readable.reduce(0) { $0 + $1.issues.count }
        let pages = readable.reduce(0) { $0 + $1.pageTotal }
        var parts = ["\(readable.count.formatted()) title\(readable.count == 1 ? "" : "s")",
                     "\(issues.formatted()) issue\(issues == 1 ? "" : "s")"]
        if pages > 0 { parts.append("\(pages.formatted()) pages") }
        var line = parts.joined(separator: " \u{00B7} ")
        if !held.isEmpty { line += " \u{00B7} \(held.count.formatted()) cover-only, pending rights" }
        return line
    }

    /// renderModuleIndex (:2622): a tab per language that holds titles, a row per shelf in the index's own
    /// order (the romance shelf is not offered, as on the site), Unfiled last. Without the index the room
    /// is one tab of every title, in a row per region.
    static func tabs(titles: [RRTitle], index: RRModuleIndex?, rights: Set<String>) -> [RRTab] {
        guard let index else {
            let all = [RRTab(id: "all", name: "All titles", native: nil, depth: depthLine(titles, rights: rights),
                             rows: regionRows(titles))]
            return titles.isEmpty ? [] : all
        }
        let shelfOrder = index.shelves.map(\.key) + [unfiledKey]
        let shelfName = { (key: String) -> String in
            if key == unfiledKey { return "Unfiled" }
            if let def = index.shelves.first(where: { $0.key == key }) { return def.name }
            return key.split(whereSeparator: { "-_".contains($0) }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        var tabs: [RRTab] = []
        for module in index.modules {
            let own = titles.filter { index.assign[$0.slug]?.module == module.key }
            guard !own.isEmpty else { continue }
            tabs.append(RRTab(id: module.key, name: module.name, native: module.native,
                              depth: depthLine(own, rights: rights),
                              rows: shelfRows(own, index: index, order: shelfOrder, name: shelfName)))
        }
        let known = Set(index.modules.map(\.key))
        let loose = titles.filter { title in
            guard let module = index.assign[title.slug]?.module else { return true }
            return !known.contains(module)
        }
        if !loose.isEmpty {
            tabs.append(RRTab(id: unfiledKey, name: "Unfiled", native: nil, depth: depthLine(loose, rights: rights),
                              rows: [RRRow(id: unfiledKey, name: "Unfiled", titles: loose)]))
        }
        return tabs
    }

    private static func shelfRows(_ titles: [RRTitle], index: RRModuleIndex, order: [String], name: (String) -> String) -> [RRRow] {
        var byShelf: [String: [RRTitle]] = [:]
        var firstSeen: [String] = []
        for title in titles {
            let key = index.assign[title.slug]?.shelf ?? unfiledKey
            if byShelf[key] == nil { firstSeen.append(key) }
            byShelf[key, default: []].append(title)
        }
        let position = { (key: String) -> Int in (order.firstIndex(of: key).map { $0 + 1 }) ?? 99 }
        return firstSeen.filter { $0 != "romance" }
            .enumerated().sorted { a, b in
                let pa = position(a.element), pb = position(b.element)
                return pa == pb ? a.offset < b.offset : pa < pb
            }
            .map { RRRow(id: $0.element, name: name($0.element), titles: byShelf[$0.element] ?? []) }
    }

    private static func regionRows(_ titles: [RRTitle]) -> [RRRow] {
        var byRegion: [String: [RRTitle]] = [:]
        for title in titles { byRegion[RRRegions.umbrella[title.region] ?? "other", default: []].append(title) }
        return (RRRegions.order + ["other"]).compactMap { key in
            guard let list = byRegion[key], !list.isEmpty else { return nil }
            return RRRow(id: key, name: RRRegions.display[key] ?? "Other", titles: list)
        }
    }
}

// MARK: - The site's own words

enum RRWords {
    static let heading = "Reading Room"
    static let lede = "Magazines, books and printed matter from the Middle World, page by page."

    /// The gate the site draws for a paid title (:8180): the preview read, what the issue runs to, who can open it.
    /// The gate on a members' title. Membership is not sold on the TV (owner, 2026-10-06: "dont
    /// allow people to get reading room subscription on the apple tv app, make them go to our site
    /// for that"): the gate names the address once, in its sentence, and no price is
    /// quoted here. There is no code to scan: the QR codes came out on 2026-10-06.
    static func membersGate(titleName: String, issueLabel: String, pages: Int) -> (heading: String, text: String) {
        let issue = (issueLabel.isEmpty || issueLabel.lowercased().hasPrefix("unknown")) ? "" : " (\(issueLabel))"
        return ("Membership required",
                "You've read the free preview \u{2014} the first 2 pages of \u{201C}\(titleName)\u{201D}\(issue). The full issue runs \(pages) pages and is open to members. "
                + "Membership is taken on khajistan.com.")
    }

    /// The gate for a free title that wants an account (:8170).
    static func accountGate(titleName: String, issueLabel: String, pages: Int) -> (heading: String, text: String) {
        let issue = (issueLabel.isEmpty || issueLabel.lowercased().hasPrefix("unknown")) ? "" : " (\(issueLabel))"
        return ("Free to read \u{2014} sign in to continue",
                "You've seen the cover of \u{201C}\(titleName)\u{201D}\(issue). All \(pages) pages are free \u{2014} a Khajistan account is all it takes. No Pass, no payment.")
    }

    static let signInDoor = "Sign in \u{2014} free"

    static let residencyHeading = "Residency reading hours"
    static let residencyText = "Full Reading Room access is included from 9 am to 8 pm New York time each day during your residency. Free previews remain available. Reading only; downloads are unavailable."

    /// A page the server cannot find (:8236): said only where the reader is entitled to it.
    static func missingPage(_ page: Int) -> String { "Page \(page) unavailable \u{2014} not yet in the archive" }

    /// The banner on a rights-held title (:6650-6665).
    static let rightsHeading = "Preserved \u{00B7} not published"
    static func rightsBody(issueCount: Int, khajistanScanned: Bool) -> String {
        let issues = issueCount > 1 ? "all \(issueCount) issues" : "the one issue"
        let held = khajistanScanned
            ? "Khajistan has digitised and preserved \(issues) of this title."
            : "\(issues.prefix(1).uppercased() + issues.dropFirst()) of this title \(issueCount > 1 ? "are" : "is") preserved."
        return held + " Covers are shown for identification; the pages are not available to read \u{2014} including to members \u{2014} until rights for this material are cleared."
    }
    static let researchersAsk = "Researchers may request supervised access"

    /// The line under a rights-held title's name: "N issues · M pages preserved, cover only" (:6624).
    static func depth(issues: Int, pages: Int, held: Bool) -> String {
        var line = "\(issues.formatted()) issue\(issues == 1 ? "" : "s")"
        if pages > 0 { line += " \u{00B7} \(pages.formatted()) pages" }
        return line + (held ? " preserved, cover only" : "")
    }
}

// MARK: - The site's addresses

enum RRSite {
    static func modulesURL(origin: URL) -> URL {
        origin.appendingPathComponent("data/rr-modules.json")
    }
}
