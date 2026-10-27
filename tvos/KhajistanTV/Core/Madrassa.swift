import Foundation
import JavaScriptCore

// The Madrassa (madrassa.html): its reference entries, its writings and forensics, and the Street
// Dictionary (lughat.html), read from the same sources the pages read. Nothing is summarised here:
// an essay is shown whole, from the body the feed carries, and a dictionary entry with every field
// its record gives, its sensitivity and review state included.

// MARK: - Reference entries

/// One entry of madrassa.html's ENTRIES.
struct MadrassaEntry: Decodable, Identifiable, Hashable, Sendable {
    struct Press: Decodable, Hashable, Sendable {
        /// Link, headline, and the source line.
        let u: String
        let h: String
        let s: String?
    }

    let id: String
    let cat: String
    let title: String
    let sub: String?
    let desc: String?
    let href: String?
    let img: String?
    let alt: String?
    let press: [Press]?
}

enum MadrassaEntries {
    static let pagePath = "madrassa.html"

    /// The ENTRIES literal, cut out of the page and evaluated as the page itself evaluates it
    /// (JavaScriptCore), then read as JSON. The page is the only list: the app keeps no copy.
    static func entries(fromPage html: String) -> [MadrassaEntry]? {
        guard let start = html.range(of: "var ENTRIES = [") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: "\n];") else { return nil }
        let literal = "[" + rest[..<end.lowerBound] + "\n]"
        guard let context = JSContext() else { return nil }
        context.exceptionHandler = { _, _ in }
        guard let json = context.evaluateScript("JSON.stringify(\(literal))")?.toString(),
              json != "undefined", let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([MadrassaEntry].self, from: data)
    }
}

// MARK: - Writings and forensics

/// One post of data/journal-posts.json.
struct MadrassaPost: Decodable, Identifiable, Hashable, Sendable {
    let title: String
    let handle: String
    let blog: String?
    let publishedAt: String?
    let theme: String?
    let image: String?
    let imageAlt: String?
    let summary: String?
    let body: String?
    let kind: String?
    let tags: [String]?

    var id: String { (blog ?? "") + "/" + handle }
}

enum MadrassaWritings {
    static let feedPath = "data/journal-posts.json"
    /// WRI_LABEL in madrassa.html.
    static let labels = ["ARCHIVE FORENSICS": "Forensics", "PRESS & PUBLICATIONS": "Essay", "FILMS & SCREENINGS": "Film Writing", "NEWS & DISPATCHES": "Essay"]

    /// The Madrassa's writings: knowledge posts only, newest first, as the page lists them.
    static func knowledge(_ posts: [MadrassaPost]) -> [MadrassaPost] {
        posts.filter { $0.kind == "knowledge" }.sorted { ($0.publishedAt ?? "") > ($1.publishedAt ?? "") }
    }

    static func label(_ post: MadrassaPost) -> String { labels[post.theme ?? ""] ?? "Writing" }

    static func isForensics(_ post: MadrassaPost) -> Bool { label(post) == "Forensics" }

    /// Under the Forensics heading the "Archive Forensics:" prefix is dropped, as on the page.
    static func listTitle(_ post: MadrassaPost) -> String {
        guard isForensics(post) else { return post.title }
        return post.title.replacingOccurrences(of: #"^\s*Archive Forensics\s*[:：]\s*"#, with: "", options: .regularExpression)
    }

    /// The post's page on the website (article.html?b=&h=).
    static func pagePath(_ post: MadrassaPost) -> String {
        "article.html?b=\(KJURL.encodeQueryValue(post.blog ?? "announcements"))&h=\(KJURL.encodeQueryValue(post.handle))"
    }
}

// MARK: - The body, as blocks

/// An article body broken into what a native screen draws: headings, paragraphs (with their
/// links), quotations, list items, table rows (a transcript's columns), images, and a note where
/// the source embeds a player the app cannot draw. Scripts, styles and forms are not carried.
enum ArticleBlock: Hashable, Sendable {
    case heading(String)
    case paragraph(AttributedString)
    case quote(AttributedString)
    case item(AttributedString)
    case row([String])
    case image(URL, alt: String?)
    case embed
    case rule
}

enum ArticleHTML {
    private static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "ul", "ol",
                                                 "table", "tbody", "thead", "tr", "td", "th", "figure", "figcaption", "section",
                                                 "article", "details", "summary", "header", "footer", "aside", "hr", "pre"]
    private static let embedTags: Set<String> = ["iframe", "audio", "video", "object", "embed"]

    /// Block-level split of a feed body in one pass over its tags, so every run of text lands in a
    /// block whatever element holds it. Text is kept whole; nothing is shortened.
    static func blocks(_ html: String) -> [ArticleBlock] {
        var cleaned = html
        for tag in ["script", "style", "noscript", "svg", "form", "button"] {
            cleaned = cleaned.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        cleaned = cleaned.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>") else { return [] }
        let ns = cleaned as NSString
        var out: [ArticleBlock] = []
        var buffer = ""
        var kind = "p"
        var cells: [String]?
        var cell = ""
        var lastEmbed = false

        func flush() {
            let text = inline(buffer)
            buffer = ""
            guard !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if cells != nil { cell += String(text.characters); return }
            lastEmbed = false
            switch kind {
            case "h1", "h2", "h3", "h4", "h5", "h6", "summary": out.append(.heading(String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)))
            case "blockquote": out.append(.quote(text))
            case "li": out.append(.item(text))
            default: out.append(.paragraph(text))
            }
        }

        var cursor = 0
        for match in regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            buffer += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            let closing = ns.substring(with: match.range(at: 1)) == "/"
            let tag = ns.substring(with: match.range(at: 2)).lowercased()
            let attributes = ns.substring(with: match.range(at: 3))
            if tag == "img" {
                flush()
                if let block = image(attributes) { out.append(block) }
            } else if embedTags.contains(tag) {
                if !closing, !lastEmbed { flush(); out.append(.embed); lastEmbed = true }
            } else if tag == "tr" {
                flush()
                if closing {
                    if let row = cells, row.contains(where: { !$0.isEmpty }) { out.append(.row(row)); lastEmbed = false }
                    cells = nil
                } else {
                    cells = []
                }
            } else if tag == "td" || tag == "th" {
                flush()
                if closing, cells != nil {
                    cells?.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                    cell = ""
                }
            } else if tag == "hr" {
                flush()
                out.append(.rule)
            } else if blockTags.contains(tag) {
                flush()
                kind = closing ? "p" : tag
            } else if tag == "br" {
                buffer += "<br>"
            } else if tag == "a" {
                buffer += closing ? "</a>" : "<a \(attributes)>"
            }
        }
        buffer += ns.substring(from: cursor)
        flush()
        // A rule at either end, or two together, separates nothing.
        var tidy: [ArticleBlock] = []
        for block in out where !(block == .rule && (tidy.isEmpty || tidy.last == .rule)) { tidy.append(block) }
        while tidy.last == .rule { tidy.removeLast() }
        return tidy
    }

    private static func image(_ attributes: String) -> ArticleBlock? {
        guard let src = attribute("src", in: attributes), let url = URL(string: src), url.scheme == "https" else { return nil }
        return .image(url, alt: attribute("alt", in: attributes))
    }

    /// Plain text of a fragment, for summaries and search.
    static func text(_ html: String) -> String {
        String(inline(html).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A fragment's text with its links kept as links; every other tag is dropped.
    static func inline(_ html: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive]))
        while let open = rest.range(of: "<a ", options: .caseInsensitive) {
            result += AttributedString(plain(String(rest[..<open.lowerBound])))
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.firstIndex(of: ">"), let end = afterOpen.range(of: "</a>", options: .caseInsensitive) else {
                rest = afterOpen
                continue
            }
            let attributes = String(afterOpen[..<close])
            var label = AttributedString(plain(String(afterOpen[afterOpen.index(after: close)..<end.lowerBound])))
            if let href = attribute("href", in: attributes), let url = URL(string: href), ["https", "http"].contains(url.scheme ?? "") {
                label.link = url
            }
            result += label
            rest = afterOpen[end.upperBound...]
        }
        result += AttributedString(plain(String(rest)))
        return result
    }

    private static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(stripped).replacingOccurrences(of: "[ \\t\\r\\f]+", with: " ", options: .regularExpression)
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return decodeEntities(String(tag[range]))
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        let named = ["&nbsp;": "\u{00A0}", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                     "&mdash;": "\u{2014}", "&ndash;": "\u{2013}", "&hellip;": "\u{2026}", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
                     "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}"]
        for (entity, char) in named { out = out.replacingOccurrences(of: entity, with: char) }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var built = ""
            var cursor = 0
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                built += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let hex = ns.substring(with: match.range(at: 1)) == "x"
                let digits = ns.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) { built.append(Character(scalar)) }
                cursor = match.range.location + match.range.length
            }
            built += ns.substring(from: cursor)
            out = built
        }
        // Last, so an escaped entity ("&amp;lt;") reads as written, not as a second entity.
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - The Street Dictionary

/// One entry of data/lughat.json. Every field is optional because the corpus is: an entry carries
/// what its source gave, and no more.
struct LughatEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let lang: String?
    let word: String?
    let translit: String?
    let meaning: String?
    let gloss: String?
    let example: String?
    let region: String?
    let register: [String]?
    let pos: String?
    let domain: String?
    let by: String?
    let source: String?
    let sourceUrl: String?
    let sensitivity: String?
    let verify: Verify?
    let slur: Bool?
    let access: String?
    let concept: String?

    /// `verify` is `true` on some entries and a sentence on others.
    struct Verify: Decodable, Hashable, Sendable {
        let note: String?
        init(from decoder: Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let flag = try? box.decode(Bool.self) { note = flag ? "" : nil }
            else { note = try? box.decode(String.self) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, lang, word, translit, meaning, gloss, example, region, register, pos, domain, by, source, sourceUrl
        case sensitivity, verify, slur, access, concept
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        func s(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 } }
        lang = s(.lang); word = s(.word); translit = s(.translit); meaning = s(.meaning); gloss = s(.gloss)
        example = s(.example); region = s(.region); pos = s(.pos); domain = s(.domain); by = s(.by); source = s(.source)
        sourceUrl = s(.sourceUrl); sensitivity = s(.sensitivity); access = s(.access); concept = s(.concept)
        register = (try? c.decodeIfPresent([String].self, forKey: .register)) ?? s(.register).map { [$0] }
        verify = try? c.decodeIfPresent(Verify.self, forKey: .verify)
        slur = try? c.decodeIfPresent(Bool.self, forKey: .slur)
    }

    /// Whether the entry is marked for review (lughat.html's verify badge).
    var needsVerifying: Bool { verify?.note != nil }
}

struct LughatFile: Decodable, Sendable {
    let entries: [LughatEntry]
}

enum Lughat {
    static let path = "data/lughat.json"

    /// lughat.html sets High and Restricted entries apart, under its own heading and note, and
    /// removes nothing.
    static func isSetApart(_ entry: LughatEntry) -> Bool {
        ["high", "restricted"].contains((entry.sensitivity ?? "").lowercased())
    }

    static let setApartHeading = "ARCHIVAL \u{2014} Historical, Legal & High-Sensitivity Terms"
    static let setApartNote = "These terms are documented for historical, legal, and research purposes. They are not presented as casual identity language. Handle with care \u{2014} community review required before any public use."

    /// The languages the corpus names, most entries first.
    static func languages(_ entries: [LughatEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries { if let lang = entry.lang { counts[lang, default: 0] += 1 } }
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    static func matches(_ entry: LughatEntry, _ query: String) -> Bool {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return true }
        return [entry.word, entry.translit, entry.meaning, entry.gloss, entry.region, entry.concept].compactMap { $0 }
            .contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) }
    }
}
