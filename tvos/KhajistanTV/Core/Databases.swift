import Foundation

// The Madrassa's research databases (databases.html): eight systems, each read from the file its
// own page reads. Every record becomes one shape, `DBRecord`, without losing what its database
// carries: the fields are listed in the database's own order and named in its own terms, and a
// record's link is the source the database cites. Metadata-only databases never gain a play
// button; a reference index is not the Receiver.

struct DBRecord: Identifiable, Hashable, Sendable {
    struct Field: Hashable, Sendable {
        let label: String
        let value: String
    }

    let id: String
    let title: String
    /// The title in its own script, where the database gives one.
    let native: String?
    /// One line under the title: who, when, where.
    let subtitle: String
    /// Facet name to value, for filtering ("Language" → "Urdu").
    let facets: [String: String]
    let fields: [Field]
    let image: URL?
    /// The source the database cites for this record, or a scan in the Reading Room.
    let link: URL?
    let linkLabel: String?
    /// Folded, lower-cased text the search reads.
    let searchText: String
}

/// One database file, and how its records read.
enum ArchiveDatabase: String, CaseIterable, Identifiable, Sendable {
    case pakistanMusic, nationalBroadcasts, logos, iranianCinema, pakistaniCinema, turkishCinema,
         screenMarks, pakistaniDramas, arabicMusic, persianMusic, censorCertificates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pakistanMusic: return "Pakistan Music Index"
        case .nationalBroadcasts: return "National Broadcast Register"
        case .logos: return "Logos of the Middle World"
        case .iranianCinema: return "Iranian Cinema"
        case .pakistaniCinema: return "Pakistani Cinema"
        case .turkishCinema: return "Yeşilçam Seks Furyası"
        case .screenMarks: return "Screen Marks"
        case .pakistaniDramas: return "Pakistani Dramas"
        case .arabicMusic: return "Arabic Music Index"
        case .persianMusic: return "Persian Music Index"
        case .censorCertificates: return "Film Censor Certificates"
        }
    }

    /// The file(s) the database's own page reads, on the site.
    var paths: [String] {
        switch self {
        case .pakistanMusic: return ["data/radio/tracks.json"]
        case .nationalBroadcasts: return ["data/signal-room/national-services.json"]
        case .logos: return ["data/logos.json", "data/logos-thumbs.json"]
        case .iranianCinema: return ["cinema/iranian-cinema/data/films.json"]
        case .pakistaniCinema: return ["cinema/pakistani-cinema/data/films.json"]
        case .turkishCinema: return ["cinema/turkish-cinema/yesilcam-seks-furyasi/data/films.json"]
        case .screenMarks: return ["cinema/idents/data/screen-marks.json"]
        case .pakistaniDramas: return ["television/pakistani-dramas/data/dramas.json"]
        case .arabicMusic: return ["data/arabic-music-index.json"]
        case .persianMusic: return ["data/persian-music-index.json"]
        case .censorCertificates: return ["censor-certificates.html"]
        }
    }

    /// The database's own page on the website.
    var page: String {
        switch self {
        case .pakistanMusic: return "pakistan-music-index.html"
        case .nationalBroadcasts: return "national-broadcasts.html"
        case .logos: return "logos.html"
        case .iranianCinema: return "cinema/iranian-cinema/"
        case .pakistaniCinema: return "cinema/pakistani-cinema/"
        case .turkishCinema: return "cinema/turkish-cinema/yesilcam-seks-furyasi/"
        case .screenMarks: return "cinema/idents/"
        case .pakistaniDramas: return "television/pakistani-dramas/"
        case .arabicMusic: return "arabic-music-index.html"
        case .persianMusic: return "persian-music-index.html"
        case .censorCertificates: return "censor-certificates.html"
        }
    }

    /// Whether the records are catalogue data with no recording behind them in the app.
    var isMetadataOnly: Bool {
        switch self {
        case .pakistanMusic, .arabicMusic, .persianMusic: return true
        default: return false
        }
    }

    /// The facets the list offers, in order.
    var facetNames: [String] {
        switch self {
        case .pakistanMusic: return ["Language", "Decade"]
        case .nationalBroadcasts: return ["Country", "Medium"]
        case .logos: return ["Region", "Country"]
        case .iranianCinema, .pakistaniCinema, .turkishCinema: return ["Decade", "Language"]
        case .screenMarks: return ["Region", "Type"]
        case .pakistaniDramas: return ["Channel", "Decade"]
        case .arabicMusic: return ["Era", "Source"]
        case .persianMusic: return ["Era", "Format"]
        case .censorCertificates: return ["Decade", "Language"]
        }
    }

    /// The records of the file(s), in the order `paths` names them.
    func records(_ files: [Data], origin: URL = KJConfig.site) throws -> [DBRecord] {
        guard files.count == paths.count else { throw DBError.unreadable }
        if self == .censorCertificates {
            return CensorCertificates.records(fromHTML: String(decoding: files[0], as: UTF8.self), origin: origin)
        }
        let root = try JSONSerialization.jsonObject(with: files[0])
        switch self {
        case .pakistanMusic: return DBRead.list(root).compactMap(DBRead.pakistanTrack)
        case .nationalBroadcasts: return DBRead.list(root, key: "services").compactMap(DBRead.service)
        case .logos:
            let thumbs = (try? JSONSerialization.jsonObject(with: files[1])) as? [String: Any]
            let level2 = Set((thumbs?["files"] as? [String]) ?? [])
            return DBRead.list(root, key: "records").compactMap { DBRead.logo($0, level2: level2, origin: origin) }
        case .iranianCinema: return DBRead.list(root).compactMap(DBRead.iranianFilm)
        case .pakistaniCinema: return DBRead.list(root).compactMap(DBRead.pakistaniFilm)
        case .turkishCinema: return DBRead.list(root, key: "records").compactMap(DBRead.turkishFilm)
        case .screenMarks: return DBRead.list(root, key: "records").enumerated().compactMap { DBRead.screenMark($1, index: $0) }
        case .pakistaniDramas: return DBRead.list(root).compactMap(DBRead.drama)
        case .arabicMusic: return DBRead.list(root, key: "records").compactMap(DBRead.arabicRecord)
        case .persianMusic:
            let dicts = (root as? [String: Any])?["dicts"] as? [String: Any] ?? [:]
            return DBRead.list(root, key: "records").compactMap { DBRead.persianRecord($0, dicts: dicts) }
        case .censorCertificates: return []
        }
    }
}

/// The eight systems as databases.html numbers them, each with its databases.
enum DatabaseShelf: Int, CaseIterable, Identifiable, Sendable {
    case music = 1, broadcasts, logos, cinema, television, arabic, persian, censor

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .music: return "Pakistan Music Index"
        case .broadcasts: return "National Broadcast Register"
        case .logos: return "Logos of the Middle World"
        case .cinema: return "Cinema of the Middle World"
        case .television: return "Television of the Middle World"
        case .arabic: return "Arabic Music Index"
        case .persian: return "Persian Music Index"
        case .censor: return "Film Censor Certificates"
        }
    }

    /// databases.html's own line for each card.
    var line: String {
        switch self {
        case .music: return "Recording, performer, label and release records. Metadata only; no playable audio."
        case .broadcasts: return "Named national television and radio services across the thirty Khajistan Receiver territories."
        case .logos: return "Company, product, institutional, state and screen marks organized for comparative research."
        case .cinema: return "Country and tradition-based cinema research portals, including Iranian, Pakistani and Turkish cinema."
        case .television: return "National television and drama indexes. This is historical/reference data, not the live receiver."
        case .arabic: return "Arabic recorded music from 1903 shellac to the present, unified from five open research collections \u{2014} maqam and iqa where documented."
        case .persian: return "Iranian recorded music and the Radio Iran broadcasts, unified from five open research collections \u{2014} dastgah, instrument, and the sung poem identified and cited."
        case .censor: return "Pakistani censor certificates 1960\u{2013}1997. Each sheet scanned front and back, with every cut the Board ordered transcribed word for word and Urdu given in English."
        }
    }

    var kicker: String {
        switch self {
        case .music, .arabic, .persian: return "Recording metadata"
        case .broadcasts: return "Broadcast-service register"
        case .logos: return "Visual identity index"
        case .cinema: return "National cinema indexes"
        case .television: return "Television indexes"
        case .censor: return "State film records"
        }
    }

    var databases: [ArchiveDatabase] {
        switch self {
        case .music: return [.pakistanMusic]
        case .broadcasts: return [.nationalBroadcasts]
        case .logos: return [.logos]
        case .cinema: return [.iranianCinema, .pakistaniCinema, .turkishCinema, .screenMarks]
        case .television: return [.pakistaniDramas]
        case .arabic: return [.arabicMusic]
        case .persian: return [.persianMusic]
        case .censor: return [.censorCertificates]
        }
    }
}

enum DBError: Error { case unreadable }

/// Searching and filtering a database's records.
enum DBQuery {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Every word of the query must appear; the facets chosen must all match.
    static func filter(_ records: [DBRecord], text: String, facets: [String: String]) -> [DBRecord] {
        let words = fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        return records.filter { record in
            facets.allSatisfy { record.facets[$0.key] == $0.value }
                && words.allSatisfy { record.searchText.contains($0) }
        }
    }

    /// The values a facet takes across these records, most common first, then by name.
    static func values(_ facet: String, in records: [DBRecord]) -> [(value: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in records { if let value = record.facets[facet] { counts[value, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { ($0.count, $1.value) > ($1.count, $0.value) }
    }
}

/// Reading the files' loose JSON: numbers and strings mixed, lists where text is expected, and
/// "None", "nan" or "" where nothing is known. A value that says nothing is nil, never a word.
enum DBRead {
    static func list(_ root: Any, key: String? = nil) -> [[String: Any]] {
        if let key { return ((root as? [String: Any])?[key] as? [[String: Any]]) ?? [] }
        return (root as? [[String: Any]]) ?? []
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["", "none", "null", "nan", "unknown", "[]"].contains(trimmed.lowercased()) ? nil : trimmed
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            if double == double.rounded(), let whole = Int(exactly: double) { return String(whole) }
            return String(double)
        case let list as [Any]:
            let parts = list.compactMap { text($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        default:
            return nil
        }
    }

    static func year(_ value: Any?) -> Int? {
        guard let text = text(value), let year = Int(text.prefix(4)), (1800...2100).contains(year) else { return nil }
        return year
    }

    static func decade(_ year: Int?) -> String? { year.map { "\($0 / 10 * 10)s" } }

    static func url(_ value: Any?) -> URL? {
        guard let text = text(value), let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
        return url
    }

    static func make(id: String, title: String?, native: String? = nil, subtitle: [String?], facets: [String: String?],
                     fields: [(String, String?)], image: URL? = nil, link: URL?, linkLabel: String? = "Source") -> DBRecord? {
        // No record is dropped for want of a title: the databases' own pages say so instead.
        let title = (title?.isEmpty == false ? title : nil) ?? "[untitled \u{2014} source gives no title]"
        // A code-style value ("strong_source_verified") is shown with spaces; no word is changed.
        func readable(_ value: String) -> String {
            value.range(of: #"^[a-z]+(_[a-z]+)+$"#, options: .regularExpression) != nil ? value.replacingOccurrences(of: "_", with: " ") : value
        }
        let kept = fields.compactMap { label, value in value.map { DBRecord.Field(label: label, value: readable($0)) } }
        let facetValues = facets.compactMapValues { $0 }
        let search = ([title, native ?? ""] + kept.map(\.value)).joined(separator: " ")
        return DBRecord(id: id, title: title, native: native, subtitle: subtitle.compactMap { $0 }.joined(separator: " \u{00B7} "),
                        facets: facetValues, fields: kept, image: image, link: link, linkLabel: link == nil ? nil : linkLabel,
                        searchText: DBQuery.fold(search))
    }

    static func pakistanTrack(_ r: [String: Any]) -> DBRecord? {
        let year = self.year(r["y"])
        return make(id: text(r["id"]) ?? UUID().uuidString, title: text(r["t"]),
                    subtitle: [text(r["a"]), year.map(String.init)],
                    facets: ["Language": text(r["l"]), "Decade": decade(year) ?? text(r["d"]).map { $0 + "s" }],
                    fields: [("Performer", text(r["a"])), ("Album", text(r["al"])), ("Year", year.map(String.init)),
                             ("Language", text(r["l"])), ("Film", text(r["f"])), ("Mood", text(r["mood"])), ("Theme", text(r["theme"])), ("Record", text(r["id"]))],
                    link: nil)
    }

    /// national-broadcasts.html's service card, in its own words: the evidence state named, the
    /// reception line it prints for every service, the jurisdiction, notes and the source checked.
    static func service(_ r: [String: Any]) -> DBRecord? {
        let medium = text(r["medium"]) == "television" ? "Television" : "Radio"
        let evidence = text(r["evidence_status"]) == "verified_national_terrestrial" ? "Terrestrial evidence reviewed" : "Official service \u{00B7} carriage review"
        let source = [text(r["source_label"]), text(r["source_checked_at"])].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return make(id: text(r["id"]) ?? UUID().uuidString, title: text(r["name"]),
                    subtitle: [text(r["broadcaster"]), text(r["country_name"]), medium],
                    facets: ["Country": text(r["country_name"]), "Medium": medium],
                    fields: [("Broadcaster", text(r["broadcaster"])), ("Service", "\(medium) \u{00B7} \(text(r["country_name"]) ?? "")"),
                             ("Evidence", evidence), ("Reception", "Directory only \u{00B7} no stream asserted"),
                             ("Broadcast jurisdiction", text(r["broadcast_jurisdiction"])), ("Source checked", text(r["source_checked_at"])),
                             ("Review note", text(r["note"])), ("Editorial territory", text(r["country_scope_note"])),
                             ("Source", source.isEmpty ? nil : source)],
                    link: url(r["official_source_url"]), linkLabel: "Official source")
    }

    /// logos.html: only `review == false` with an image file; level-2 files have a WebP thumb,
    /// the rest are small originals used as they are. An SVG original has no picture here.
    static func logo(_ r: [String: Any], level2: Set<String>, origin: URL) -> DBRecord? {
        guard (r["review"] as? Bool) == false, let file = text(r["image_file"]), file.hasPrefix("assets/logos/") else { return nil }
        let relative = String(file.dropFirst("assets/logos/".count))
        var shown = file
        if level2.contains(relative), let dot = file.lastIndex(of: "."), let slash = file.lastIndex(of: "/") {
            shown = String(file[..<slash]) + "/thumb/" + String(file[file.index(after: slash)..<dot]) + ".webp"
        }
        let image = shown.lowercased().hasSuffix(".svg") ? nil : URL(string: shown, relativeTo: origin)?.absoluteURL
        return make(id: text(r["id"]) ?? file, title: text(r["name"]),
                    subtitle: [text(r["country"]), text(r["category"])],
                    facets: ["Region": text(r["region"]), "Country": text(r["country"])],
                    fields: [("Country", text(r["country"])), ("Region", text(r["region"])), ("Category", text(r["category"])),
                             ("Type", text(r["type"])), ("Origin", text(r["origin"])), ("Artist", text(r["artist"])), ("Licence", text(r["license"]))],
                    image: image, link: url(r["source_url"]))
    }

    static func iranianFilm(_ r: [String: Any]) -> DBRecord? {
        let year = self.year(r["year"])
        return make(id: "ir-" + (text(r["id"]) ?? UUID().uuidString), title: text(r["title"]) ?? text(r["title_romanized"]) ?? text(r["title_fa"]), native: text(r["title_fa"]),
                    subtitle: [text(r["title_romanized"]), year.map(String.init), text(r["genre"])],
                    facets: ["Decade": decade(year), "Language": text(r["language"])],
                    fields: [("Romanized", text(r["title_romanized"])), ("Year", year.map(String.init)), ("Genre", text(r["genre"])),
                             ("Runtime", text(r["runtime"]).map { $0 + " min" }), ("Language", text(r["language"])),
                             ("Synopsis", text(r["synopsis_en"])), ("Review", text(r["review_status"]))],
                    link: url(r["source_url"]))
    }

    static func pakistaniFilm(_ r: [String: Any]) -> DBRecord? {
        let year = (r["year_unknown"] as? Bool) == true ? nil : self.year(r["year"])
        return make(id: "pk-" + (text(r["pid"]) ?? UUID().uuidString), title: text(r["title"]),
                    subtitle: [year.map(String.init) ?? "Year unknown", text(r["language"]), text(r["genre"])],
                    facets: ["Decade": decade(year), "Language": text(r["language"])],
                    fields: [("Year", year.map(String.init)), ("Language", text(r["language"]) ?? text(r["languages"])),
                             ("Genre", text(r["genre"])), ("Studio", text(r["studio"])), ("Made in", text(r["made_in"])),
                             ("Box office", text(r["box_office"])), ("Review", text(r["review_status"]))],
                    link: url(r["source_url"]))
    }

    static func turkishFilm(_ r: [String: Any]) -> DBRecord? {
        let year = self.year(r["year"])
        return make(id: "tr-" + (text(r["id"]) ?? UUID().uuidString), title: text(r["title_tr"]) ?? text(r["title_original"]) ?? text(r["title_en_literal"]),
                    subtitle: [text(r["title_en_literal"]), year.map(String.init)],
                    facets: ["Decade": decade(year), "Language": text(r["language"])],
                    fields: [("Literal title", text(r["title_en_literal"])), ("Year", year.map(String.init)), ("Cast", text(r["cast_display"])),
                             ("Production", text(r["production_company"])), ("Runtime", text(r["runtime_minutes"]).map { $0 + " min" }),
                             ("Synopsis", text(r["synopsis_short"])), ("Censorship", text(r["censorship_notes"])),
                             ("Verification", text(r["verification_status"]))],
                    link: nil)
    }

    static func screenMark(_ r: [String: Any], index: Int) -> DBRecord? {
        make(id: "sm-\(index)", title: text(r["title"]) ?? text(r["original_title"]), native: text(r["original_title"]),
             subtitle: [text(r["country"]), text(r["year_start"]), text(r["logo_type"])],
             facets: ["Region": text(r["region"]), "Type": text(r["logo_type"])],
             fields: [("Country", text(r["country"])), ("Region", text(r["region"])), ("From", text(r["year_start"])),
                      ("Type", text(r["logo_type"])), ("Organization", text(r["organization_type"])), ("Script", text(r["script"])),
                      ("Language", text(r["language"])), ("Motifs", text(r["visual_motifs"])), ("Description", text(r["description"]))],
             link: url(r["source_url"]))
    }

    static func drama(_ r: [String: Any]) -> DBRecord? {
        let year = self.year(r["year"])
        return make(id: "dr-" + (text(r["id"]) ?? UUID().uuidString), title: text(r["title"]) ?? text(r["title_native"]), native: text(r["title_native"]),
                    subtitle: [text(r["channel"]), year.map(String.init)],
                    facets: ["Channel": text(r["channel"]), "Decade": decade(year)],
                    fields: [("Channel", text(r["channel"])), ("Year", year.map(String.init)), ("Genre", text(r["genre"])),
                             ("Episodes", text(r["episodes"])), ("Status", text(r["status"])), ("Cast", text(r["cast"])),
                             ("Director", text(r["director"])), ("Writer", text(r["writer"])), ("Synopsis", text(r["synopsis_en"]))],
                    link: url(r["source_url"]))
    }

    /// arabic-music-index.html: the title is `t`, else the Arabic-script `tar`, else the page's own
    /// "[untitled — source gives no title]"; the performer is `a`, else `aar`. No record is dropped.
    static func arabicRecord(_ r: [String: Any]) -> DBRecord? {
        let latin = text(r["t"]), arabic = text(r["tar"])
        let performer = text(r["a"]) ?? text(r["aar"])
        return make(id: text(r["id"]) ?? UUID().uuidString, title: latin ?? arabic ?? "[untitled \u{2014} source gives no title]",
                    native: latin != nil ? arabic : nil,
                    subtitle: [performer, text(r["lb"]), text(r["co"])],
                    facets: ["Era": text(r["era"]), "Source": text(r["src"])],
                    fields: [("Performer", performer), ("Year", text(r["y"])), ("Era", text(r["era"])), ("Country", text(r["co"])),
                             ("Format", text(r["fmt"])), ("Label", text(r["lb"])), ("Album", text(r["al"])), ("Composer", text(r["c"])),
                             ("Lyricist", text(r["ly"])), ("Maqam", text(r["mq"])), ("Iqa", text(r["iq"])), ("Source", text(r["src"])),
                             ("Record", text(r["id"]))],
                    link: url(r["u"]))
    }

    /// persian-music-index.json stores repeated values as indexes into `dicts` (D[k][r[k]]). The
    /// title is `t`, else the Persian-script `tfa`, else "[untitled — source gives no title]"; the
    /// performer is `a`, else `afa` (persian-music-index.html).
    static func persianRecord(_ r: [String: Any], dicts: [String: Any]) -> DBRecord? {
        func value(_ key: String) -> String? {
            if let index = r[key] as? Int, let table = dicts[key] as? [Any], table.indices.contains(index) { return text(table[index]) }
            return text(r[key])
        }
        let latin = text(r["t"]), persian = text(r["tfa"])
        let performer = value("a") ?? value("afa")
        return make(id: text(r["id"]) ?? UUID().uuidString, title: latin ?? persian ?? "[untitled \u{2014} source gives no title]",
                    native: latin != nil ? persian : nil,
                    subtitle: [performer, text(r["y"]), value("fmt")],
                    facets: ["Era": value("era"), "Format": value("fmt")],
                    fields: [("Performer", performer), ("Year", text(r["y"])), ("Era", value("era")), ("Format", value("fmt")),
                             ("Label", value("lb")), ("Publisher", value("cu")), ("Place", value("loc")), ("Album", value("al")),
                             ("Poem", value("pn")), ("Instrument", value("in")), ("Dastgah", value("dg")), ("Source", value("src")),
                             ("Record", text(r["id"]))],
                    link: url(value("u")))
    }
}

/// censor-certificates.html carries its 52 certificates inline, as <article> blocks with data
/// attributes; the scans are pages of the Reading Room's censor-records module.
enum CensorCertificates {
    static func records(fromHTML html: String, origin: URL) -> [DBRecord] {
        let articles = html.components(separatedBy: "<article ").dropFirst()
        return articles.compactMap { chunk in
            let block = chunk.components(separatedBy: "</article>").first ?? chunk
            let head = String(block.prefix { $0 != ">" })
            func attribute(_ name: String) -> String? {
                guard let range = head.range(of: name + "=\"") else { return nil }
                let rest = head[range.upperBound...]
                return DBRead.text(String(rest.prefix { $0 != "\"" }))
            }
            func span(_ cls: String) -> String? {
                guard let range = block.range(of: "<span class=\"\(cls)\"") else { return nil }
                let after = block[range.upperBound...]
                guard let open = after.firstIndex(of: ">") else { return nil }
                let inner = after[after.index(after: open)...].prefix { $0 != "<" }
                return DBRead.text(decode(String(inner)))
            }
            let urdu: String? = {
                guard let range = block.range(of: "class=\"ur\"") else { return nil }
                let after = block[range.upperBound...]
                guard let open = after.firstIndex(of: ">") else { return nil }
                return DBRead.text(decode(String(after[after.index(after: open)...].prefix { $0 != "<" })))
            }()
            let year = DBRead.year(attribute("data-year"))
            let cuts = attribute("data-n")
            let scan: URL? = {
                guard let range = block.range(of: "href=\"/reading-room?") else { return nil }
                let query = block[range.upperBound...].prefix { $0 != "\"" }
                // A Reading Room address is the archive's own, whichever origin the files came from.
                return URL(string: "reading-room?" + decode(String(query)), relativeTo: KJConfig.site)?.absoluteURL
            }()
            return DBRead.make(id: attribute("id") ?? UUID().uuidString, title: attribute("data-title").map(decode), native: urdu,
                               subtitle: [span("sm"), year.map(String.init), attribute("data-lang"), cuts.map { $0 == "0" ? "no cuts" : "\($0) cuts" }],
                               facets: ["Decade": attribute("data-dec"), "Language": attribute("data-lang")],
                               fields: [("English title", span("sm")), ("Year", year.map(String.init)), ("Language", attribute("data-lang")),
                                        ("Category", attribute("data-cat")), ("Cuts ordered", cuts), ("Cut for", attribute("data-cats")),
                                        ("Office", attribute("data-office")), ("Officer", attribute("data-officer").map(decode))],
                               link: scan, linkLabel: "The certificate in the Reading Room")
        }
    }

    static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}
