import Foundation

/// The time where a live channel broadcasts from (owner, 2026-11-19: "show local time on live
/// channels"). Read from the channel's country, with the territory where a country runs on more
/// than one clock. A channel whose clock cannot be told (the diaspora, an unknown country) gets
/// no time rather than a guessed one.
enum LocalTime {
    /// Country (as the registry writes it) → IANA zone. One zone per country; the few that span
    /// zones are settled in `zone(for:)`.
    // ponytail: one zone per country; a country added to the registry shows no time until it is listed here.
    static let zones: [String: String] = [
        "Afghanistan": "Asia/Kabul", "Albania": "Europe/Tirane", "Algeria": "Africa/Algiers",
        "Armenia": "Asia/Yerevan", "Azerbaijan": "Asia/Baku", "Bahrain": "Asia/Bahrain",
        "Bangladesh": "Asia/Dhaka", "Benin": "Africa/Porto-Novo", "Bosnia and Herzegovina": "Europe/Sarajevo",
        "Brunei": "Asia/Brunei", "Burkina Faso": "Africa/Ouagadougou", "Chad": "Africa/Ndjamena",
        "China": "Asia/Shanghai", "Comoros": "Indian/Comoro", "Côte d'Ivoire": "Africa/Abidjan",
        "Cyprus": "Asia/Nicosia", "DR Congo": "Africa/Kinshasa", "Egypt": "Africa/Cairo",
        "Eritrea": "Africa/Asmara", "Ethiopia": "Africa/Addis_Ababa", "Georgia": "Asia/Tbilisi",
        "Greece": "Europe/Athens", "Guinea": "Africa/Conakry", "Guinea-Bissau": "Africa/Bissau",
        "Guyana": "America/Guyana", "India": "Asia/Kolkata", "NW India": "Asia/Kolkata",
        "Indonesia": "Asia/Jakarta", "Iran": "Asia/Tehran", "Iraq": "Asia/Baghdad", "Israel": "Asia/Jerusalem",
        "Italy": "Europe/Rome", "Jordan": "Asia/Amman", "Kazakhstan": "Asia/Almaty", "Kosovo": "Europe/Belgrade",
        "Kuwait": "Asia/Kuwait", "Kyrgyzstan": "Asia/Bishkek", "Lebanon": "Asia/Beirut",
        "Liberia": "Africa/Monrovia", "Libya": "Africa/Tripoli", "Malaysia": "Asia/Kuala_Lumpur",
        "Maldives": "Indian/Maldives", "Mali": "Africa/Bamako", "Malta": "Europe/Malta",
        "Mauritania": "Africa/Nouakchott", "Mayotte": "Indian/Mayotte", "Montenegro": "Europe/Podgorica",
        "Morocco": "Africa/Casablanca", "Niger": "Africa/Niamey", "Nigeria": "Africa/Lagos",
        "North Macedonia": "Europe/Skopje", "Oman": "Asia/Muscat", "Pakistan": "Asia/Karachi",
        "Palestine": "Asia/Gaza", "Philippines": "Asia/Manila", "Portugal": "Europe/Lisbon",
        "Puntland": "Africa/Mogadishu", "Qatar": "Asia/Qatar", "Romania": "Europe/Bucharest",
        "Russia": "Europe/Moscow", "Abkhazia": "Europe/Moscow", "Saudi Arabia": "Asia/Riyadh",
        "Senegal": "Africa/Dakar", "Sierra Leone": "Africa/Freetown", "Singapore": "Asia/Singapore",
        "Somalia": "Africa/Mogadishu", "Somaliland": "Africa/Mogadishu", "South Africa": "Africa/Johannesburg",
        "South Sudan": "Africa/Juba", "Spain": "Europe/Madrid", "Sri Lanka": "Asia/Colombo",
        "Sudan": "Africa/Khartoum", "Suriname": "America/Paramaribo", "Syria": "Asia/Damascus",
        "Tajikistan": "Asia/Dushanbe", "Tanzania": "Africa/Dar_es_Salaam", "Thailand": "Asia/Bangkok",
        "The Gambia": "Africa/Banjul", "Trinidad and Tobago": "America/Port_of_Spain", "Tunisia": "Africa/Tunis",
        "Turkmenistan": "Asia/Ashgabat", "Türkiye": "Europe/Istanbul", "United Arab Emirates": "Asia/Dubai",
        "Uzbekistan": "Asia/Tashkent", "Vietnam": "Asia/Ho_Chi_Minh", "Yemen": "Asia/Aden",
    ]

    /// The channel's clock, or nil when it cannot be told.
    static func zone(for channel: Channel) -> TimeZone? {
        let country = channel.country?.trimmingCharacters(in: .whitespaces) ?? ""
        let territory = channel.territory ?? ""
        // Bali runs an hour ahead of Java and Sumatra, where the rest of the registry's
        // Indonesian stations are.
        if country == "Indonesia", territory.contains("Denpasar") { return TimeZone(identifier: "Asia/Makassar") }
        // Bashkortostan is on Yekaterinburg time; Tatarstan and the North Caucasus on Moscow's.
        if country == "Russia" {
            let words = [channel.name, channel.nativeName ?? "", channel.broadcaster ?? "", territory].joined(separator: " ")
            if ["Bashk", "Башк", "Ufa", "Уфа"].contains(where: words.contains) { return TimeZone(identifier: "Asia/Yekaterinburg") }
        }
        return zones[country].flatMap(TimeZone.init(identifier:))
    }

    /// "21:42 local time", or nil.
    static func label(for channel: Channel, at date: Date = Date()) -> String? {
        guard let zone = zone(for: channel) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = zone
        format.dateFormat = "HH:mm"
        return "\(format.string(from: date)) local time"
    }
}

extension Channel {
    /// The place, then the time there: "Iran · Persian · 21:42 local time".
    func placeAndTime(at date: Date = Date()) -> String {
        [place, LocalTime.label(for: self, at: date) ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
