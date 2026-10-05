import Foundation

// The Khajistan Radio mixes: data/radio/mixtapes.json, the public register of what a mix is.
// Presentation mirrors mixChannel() as open-frequencies.js held it until 2026-08-21 (last in
// 8132243eb^:scripts/open-frequencies.js), and the labels the receiver still carries: mediumWord
// "Mixtape", mediumTag "Mix", the state word "Khajistan Radio mix", and the position time format.

struct Mix: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let subtitle: String?
    let program_block: String?
    let country: String?
    let territory: String?
    let language: String?
    let decade: String?
    let mixed_by: String?
    let play_url: String
    /// Ruled off the receiver at /tv-review.html. The register keeps the row; nothing plays it.
    let hidden: Bool?

    var name: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Khajistan Radio mix" : trimmed
    }

    /// placeLabel() in open-frequencies.js: "Territory, Country", or whichever one there is.
    var place: String? {
        let c = country?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let t = territory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let t, let c, t != c { return "\(t), \(c)" }
        return c ?? t
    }

    /// Whose labour made it: where somebody else mixed it, the line says so.
    var attribution: String {
        if let by = mixed_by?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "A Khajistan Radio mix, mixed by \(by) and carried by Khajistan."
        }
        return "A Khajistan Radio mix, made and carried by Khajistan."
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct MixRegister: Decodable, Sendable {
    let mixes: [Mix]
}

enum Mixes {
    static let registerURL = KJConfig.site.appendingPathComponent("data/radio/mixtapes.json")

    /// What may be offered, in the register's own order: not ruled off, with a playable address.
    static func playable(_ mixes: [Mix]) -> [Mix] {
        mixes.filter { $0.hidden != true && playURL($0) != nil }
    }

    static func playURL(_ mix: Mix) -> URL? {
        safePublicURL(mix.play_url)
    }

    /// safePublicUrl() in open-frequencies.js: https, a host, and not a local or private one.
    static func safePublicURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              var host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return nil }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        if octets.count == 4, !octets.contains(where: { $0 == nil }) {
            let o = octets.compactMap { $0 }
            if o[0] == 0 || o[0] == 10 || o[0] == 127 || (o[0] == 169 && o[1] == 254)
                || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168) { return nil }
        }
        return url
    }

    /// clockText() in open-frequencies.js: "84:13" is "1:24:13" past an hour, and "—:—" when
    /// the position is not known.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "\u{2014}:\u{2014}" }
        let whole = Int(seconds)
        let hours = whole / 3600, mins = (whole % 3600) / 60, secs = whole % 60
        let tail = (secs < 10 ? "0" : "") + String(secs)
        if hours > 0 { return "\(hours):\(mins < 10 ? "0" : "")\(mins):\(tail)" }
        return "\(mins):\(tail)"
    }
}
