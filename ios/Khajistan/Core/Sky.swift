import Foundation

/// The three skins. Day is the sun above +6 degrees, Grove (green) is the night, below -6, and
/// Smut (pink) is dawn and dusk between them (owner ruling 2026-09-07). `groundHex` is the page
/// ground and `inkHex` the foreground; `liftHex` is the raised or pressed plate. Ground is never
/// used as a text colour on its own ground.
enum Skin: String, CaseIterable, Codable, Sendable {
    case day, grove, smut

    var groundHex: UInt32 {
        switch self {
        case .day: return 0xF3FB04
        case .grove: return 0x186409
        case .smut: return 0xC11B6B
        }
    }

    var inkHex: UInt32 {
        switch self {
        case .day: return 0x000000
        case .grove: return 0xF3FB04
        case .smut: return 0xF3FB04
        }
    }

    var liftHex: UInt32 {
        switch self {
        case .day: return 0xFFFFA0
        case .grove: return 0x004A00
        case .smut: return 0x8F1350
        }
    }

    /// The site's switch labels (kj-theme.js LABEL).
    var label: String {
        switch self {
        case .day: return "Day"
        case .grove: return "Grove"
        case .smut: return "Smut"
        }
    }
}

/// The website's sky, ported from archive/scripts/kj-theme-boot.js (KJSky, read 2026-10-05):
/// where the viewer is comes from the device's time-zone name and tzdata's coordinate for it,
/// when is the sun's elevation there, and a zone the table does not carry falls back to fixed
/// hour bands. The site's storage is mirrored key for key: `kj:theme` holds a manual pick and
/// `kj:theme:band` the sky it was made under; the pick is honoured only while the sky is still
/// in that band, then the automatic reading resumes.
enum Sky {
    static let themeKey = "kj:theme"
    static let bandKey = "kj:theme:band"

    // MARK: Where

    /// tzdata's representative coordinate per zone, whole degrees, as the site carries it.
    /// Copied verbatim from the ==TZ-TABLE-START== block of kj-theme-boot.js; copy it again
    /// when scripts/site/gen_tz_latlon.py regenerates that block.
    static let table = "~Africa|Abidjan 5 -4|Accra 6 0|Addis_Ababa 9 39|Algiers 37 3|Asmara 15 39|Bamako 13 -8|Bangui 4 19|Banjul 13 -17|Bissau 12 -16|Blantyre -16 35|Brazzaville -4 15|Bujumbura -3 29|Cairo 30 31|Casablanca 34 -8|Ceuta 36 -5|Conakry 10 -14|Dakar 15 -17|Dar_es_Salaam -7 39|Djibouti 12 43|Douala 4 10|El_Aaiun 27 -13|Freetown 8 -13|Gaborone -25 26|Harare -18 31|Johannesburg -26 28|Juba 5 32|Kampala 0 32|Khartoum 16 33|Kigali -2 30|Kinshasa -4 15|Lagos 6 3|Libreville 0 9|Lome 6 1|Luanda -9 13|Lubumbashi -12 27|Lusaka -15 28|Malabo 4 9|Maputo -26 33|Maseru -29 28|Mbabane -26 31|Mogadishu 2 45|Monrovia 6 -11|Nairobi -1 37|Ndjamena 12 15|Niamey 14 2|Nouakchott 18 -16|Ouagadougou 12 -2|Porto-Novo 6 3|Sao_Tome 0 7|Tripoli 33 13|Tunis 37 10|Windhoek -23 17~America|Adak 52 -177|Anchorage 61 -150|Anguilla 18 -63|Antigua 17 -62|Araguaina -7 -48|Argentina/Buenos_Aires -35 -58|Argentina/Catamarca -28 -66|Argentina/Cordoba -31 -64|Argentina/Jujuy -24 -65|Argentina/La_Rioja -29 -67|Argentina/Mendoza -33 -69|Argentina/Rio_Gallegos -52 -69|Argentina/Salta -25 -65|Argentina/San_Juan -32 -69|Argentina/San_Luis -33 -66|Argentina/Tucuman -27 -65|Argentina/Ushuaia -55 -68|Aruba 12 -70|Asuncion -25 -58|Atikokan 49 -92|Bahia -13 -39|Bahia_Banderas 21 -105|Barbados 13 -60|Belem -1 -48|Belize 18 -88|Blanc-Sablon 51 -57|Boa_Vista 3 -61|Bogota 5 -74|Boise 44 -116|Cambridge_Bay 69 -105|Campo_Grande -20 -55|Cancun 21 -87|Caracas 10 -67|Cayenne 5 -52|Cayman 19 -81|Chicago 42 -88|Chihuahua 29 -106|Ciudad_Juarez 32 -106|Costa_Rica 10 -84|Coyhaique -46 -72|Creston 49 -117|Cuiaba -16 -56|Curacao 12 -69|Danmarkshavn 77 -19|Dawson 64 -139|Dawson_Creek 56 -120|Denver 40 -105|Detroit 42 -83|Dominica 15 -61|Edmonton 54 -113|Eirunepe -7 -70|El_Salvador 14 -89|Fort_Nelson 59 -123|Fortaleza -4 -38|Glace_Bay 46 -60|Goose_Bay 53 -60|Grand_Turk 21 -71|Grenada 12 -62|Guadeloupe 16 -62|Guatemala 15 -91|Guayaquil -2 -80|Guyana 7 -58|Halifax 45 -64|Havana 23 -82|Hermosillo 29 -111|Indiana/Indianapolis 40 -86|Indiana/Knox 41 -87|Indiana/Marengo 38 -86|Indiana/Petersburg 38 -87|Indiana/Tell_City 38 -87|Indiana/Vevay 39 -85|Indiana/Vincennes 39 -88|Indiana/Winamac 41 -87|Inuvik 68 -134|Iqaluit 64 -68|Jamaica 18 -77|Juneau 58 -134|Kentucky/Louisville 38 -86|Kentucky/Monticello 37 -85|Kralendijk 12 -68|La_Paz -16 -68|Lima -12 -77|Los_Angeles 34 -118|Lower_Princes 18 -63|Maceio -10 -36|Managua 12 -86|Manaus -3 -60|Marigot 18 -63|Martinique 15 -61|Matamoros 26 -98|Mazatlan 23 -106|Menominee 45 -88|Merida 21 -90|Metlakatla 55 -132|Mexico_City 19 -99|Miquelon 47 -56|Moncton 46 -65|Monterrey 26 -100|Montevideo -35 -56|Montserrat 17 -62|Nassau 25 -77|New_York 41 -74|Nome 65 -165|Noronha -4 -32|North_Dakota/Beulah 47 -102|North_Dakota/Center 47 -101|North_Dakota/New_Salem 47 -101|Nuuk 64 -52|Ojinaga 30 -104|Panama 9 -80|Paramaribo 6 -55|Phoenix 33 -112|Port-au-Prince 19 -72|Port_of_Spain 11 -62|Porto_Velho -9 -64|Puerto_Rico 18 -66|Punta_Arenas -53 -71|Rankin_Inlet 63 -92|Recife -8 -35|Regina 50 -105|Resolute 75 -95|Rio_Branco -10 -68|Santarem -2 -55|Santiago -33 -71|Santo_Domingo 18 -70|Sao_Paulo -24 -47|Scoresbysund 70 -22|Sitka 57 -135|St_Barthelemy 18 -63|St_Johns 48 -53|St_Kitts 17 -63|St_Lucia 14 -61|St_Thomas 18 -65|St_Vincent 13 -61|Swift_Current 50 -108|Tegucigalpa 14 -87|Thule 77 -69|Tijuana 33 -117|Toronto 44 -79|Tortola 18 -65|Vancouver 49 -123|Whitehorse 61 -135|Winnipeg 50 -97|Yakutat 60 -140~Antarctica|Casey -66 111|Davis -69 78|DumontDUrville -67 140|Macquarie -54 159|Mawson -68 63|McMurdo -78 167|Palmer -65 -64|Rothera -68 -68|Syowa -69 40|Troll -72 3|Vostok -78 107~Arctic|Longyearbyen 78 16~Asia|Aden 13 45|Almaty 43 77|Amman 32 36|Anadyr 65 177|Aqtau 45 50|Aqtobe 50 57|Ashgabat 38 58|Atyrau 47 52|Baghdad 33 44|Bahrain 26 51|Baku 40 50|Bangkok 14 101|Barnaul 53 84|Beirut 34 36|Bishkek 43 75|Brunei 5 115|Chita 52 113|Colombo 7 80|Damascus 34 36|Dhaka 24 90|Dili -9 126|Dubai 25 55|Dushanbe 39 69|Famagusta 35 34|Gaza 32 34|Hebron 32 35|Ho_Chi_Minh 11 107|Hong_Kong 22 114|Hovd 48 92|Irkutsk 52 104|Jakarta -6 107|Jayapura -3 141|Jerusalem 32 35|Kabul 35 69|Kamchatka 53 159|Karachi 25 67|Kathmandu 28 85|Khandyga 63 136|Kolkata 23 88|Krasnoyarsk 56 93|Kuala_Lumpur 3 102|Kuching 2 110|Kuwait 29 48|Macau 22 114|Magadan 60 151|Makassar -5 119|Manila 15 121|Muscat 24 59|Nicosia 35 33|Novokuznetsk 54 87|Novosibirsk 55 83|Omsk 55 73|Oral 51 51|Phnom_Penh 12 105|Pontianak 0 109|Pyongyang 39 126|Qatar 25 52|Qostanay 53 64|Qyzylorda 45 65|Riyadh 25 47|Sakhalin 47 143|Samarkand 40 67|Seoul 38 127|Shanghai 31 121|Singapore 1 104|Srednekolymsk 67 154|Taipei 25 122|Tashkent 41 69|Tbilisi 42 45|Tehran 36 51|Thimphu 27 90|Tokyo 36 140|Tomsk 56 85|Ulaanbaatar 48 107|Urumqi 44 88|Ust-Nera 65 143|Vientiane 18 103|Vladivostok 43 132|Yakutsk 62 130|Yangon 17 96|Yekaterinburg 57 61|Yerevan 40 44~Atlantic|Azores 38 -26|Bermuda 32 -65|Canary 28 -15|Cape_Verde 15 -24|Faroe 62 -7|Madeira 33 -17|Reykjavik 64 -22|South_Georgia -54 -37|St_Helena -16 -6|Stanley -52 -58~Australia|Adelaide -35 139|Brisbane -27 153|Broken_Hill -32 141|Darwin -12 131|Eucla -32 129|Hobart -43 147|Lindeman -20 149|Lord_Howe -32 159|Melbourne -38 145|Perth -32 116|Sydney -34 151~Europe|Amsterdam 52 5|Andorra 42 2|Astrakhan 46 48|Athens 38 24|Belgrade 45 20|Berlin 52 13|Bratislava 48 17|Brussels 51 4|Bucharest 44 26|Budapest 48 19|Busingen 48 9|Chisinau 47 29|Copenhagen 56 13|Dublin 53 -6|Gibraltar 36 -5|Guernsey 49 -3|Helsinki 60 25|Isle_of_Man 54 -4|Istanbul 41 29|Jersey 49 -2|Kaliningrad 55 20|Kirov 59 50|Kyiv 50 31|Lisbon 39 -9|Ljubljana 46 15|London 52 0|Luxembourg 50 6|Madrid 40 -4|Malta 36 15|Mariehamn 60 20|Minsk 54 28|Monaco 44 7|Moscow 56 38|Oslo 60 11|Paris 49 2|Podgorica 42 19|Prague 50 14|Riga 57 24|Rome 42 12|Samara 53 50|San_Marino 44 12|Sarajevo 44 18|Saratov 52 46|Simferopol 45 34|Skopje 42 21|Sofia 43 23|Stockholm 59 18|Tallinn 59 25|Tirane 41 20|Ulyanovsk 54 48|Vaduz 47 10|Vatican 42 12|Vienna 48 16|Vilnius 55 25|Volgograd 49 44|Warsaw 52 21|Zagreb 46 16|Zurich 47 9~Indian|Antananarivo -19 48|Chagos -7 72|Christmas -10 106|Cocos -12 97|Comoro -12 43|Kerguelen -49 70|Mahe -5 55|Maldives 4 74|Mauritius -20 58|Mayotte -13 45|Reunion -21 55~Pacific|Apia -14 -172|Auckland -37 175|Bougainville -6 156|Chatham -44 -177|Chuuk 7 152|Easter -27 -109|Efate -18 168|Fakaofo -9 -171|Fiji -18 178|Funafuti -9 179|Galapagos -1 -90|Gambier -23 -135|Guadalcanal -10 160|Guam 13 145|Honolulu 21 -158|Kanton -3 -172|Kiritimati 2 -157|Kosrae 5 163|Kwajalein 9 167|Majuro 7 171|Marquesas -9 -140|Midway 28 -177|Nauru -1 167|Niue -19 -170|Norfolk -29 168|Noumea -22 166|Pago_Pago -14 -171|Palau 7 134|Pitcairn -25 -130|Pohnpei 7 158|Port_Moresby -10 147|Rarotonga -21 -160|Saipan 15 146|Tahiti -18 -150|Tarawa 1 173|Tongatapu -21 -175|Wake 19 167|Wallis -13 -176~Africa/Asmera>Africa/Asmara|America/Buenos_Aires>America/Argentina/Buenos_Aires|America/Godthab>America/Nuuk|Asia/Ashkhabad>Asia/Ashgabat|Asia/Calcutta>Asia/Kolkata|Asia/Dacca>Asia/Dhaka|Asia/Istanbul>Europe/Istanbul|Asia/Katmandu>Asia/Kathmandu|Asia/Rangoon>Asia/Yangon|Asia/Saigon>Asia/Ho_Chi_Minh|Asia/Thimbu>Asia/Thimphu|Atlantic/Faeroe>Atlantic/Faroe|Europe/Kiev>Europe/Kyiv|Europe/Nicosia>Asia/Nicosia|Europe/Uzhgorod>Europe/Kyiv|Europe/Zaporozhye>Europe/Kyiv"

    private struct Places {
        var zones: [String: (lat: Double, lon: Double)] = [:]
        var aliases: [String: String] = [:]
    }

    private static let places: Places = {
        var places = Places()
        for area in table.split(separator: "~") {
            var rows = area.split(separator: "|").map(String.init)
            guard !rows.isEmpty else { continue }
            if rows[0].contains(">") {
                // The trailing segment: old>canonical renames.
                for row in rows {
                    let pair = row.split(separator: ">", maxSplits: 1).map(String.init)
                    if pair.count == 2 { places.aliases[pair[0]] = pair[1] }
                }
                continue
            }
            let name = rows.removeFirst()
            for row in rows {
                let parts = row.split(separator: " ")
                guard parts.count == 3, let lat = Double(parts[1]), let lon = Double(parts[2]) else { continue }
                places.zones[name + "/" + parts[0]] = (lat, lon)
            }
        }
        return places
    }()

    /// The coordinate for an IANA zone name, following one rename. Nil for a zone with no area
    /// ("UTC") or one the table does not carry.
    static func position(zone: String) -> (lat: Double, lon: Double)? {
        if let hit = places.zones[zone] { return hit }
        guard let canonical = places.aliases[zone] else { return nil }
        return places.zones[canonical]
    }

    // MARK: When

    /// The sun's elevation in degrees: the site's low-precision almanac formula, line for line.
    static func elevation(at date: Date, lat: Double, lon: Double) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 * 1000 / 86_400_000 - 10957.5
        let L = (280.460 + 0.9856474 * n) * rad
        let g = (357.528 + 0.9856003 * n) * rad
        let lam = L + (1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let dec = asin(sin(eps) * sin(lam))
        let ra = atan2(cos(eps) * sin(lam), cos(lam))
        let gmst = 18.697374558 + 24.06570982441908 * n
        let ha = (gmst.truncatingRemainder(dividingBy: 24) * 15 + lon - ra / rad) * rad
        let phi = lat * rad
        return asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(ha)) / rad
    }

    // MARK: Which skin

    /// The skin the sky is wearing at `date` for a viewer in `timeZone`.
    static func theme(at date: Date, timeZone: TimeZone) -> Skin {
        if let place = position(zone: timeZone.identifier) {
            let e = elevation(at: date, lat: place.lat, lon: place.lon)
            return e > 6 ? .day : (e < -6 ? .grove : .smut)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let h = calendar.component(.hour, from: date)
        if h >= 8 && h < 17 { return .day }
        if (h >= 5 && h < 8) || (h >= 17 && h < 20) { return .smut }
        return .grove
    }

    /// The sky, unless a pick was made under the band the sky is in now (resolve() in the site).
    static func resolve(chosen: String?, band: String?, at date: Date, timeZone: TimeZone) -> Skin {
        let sky = theme(at: date, timeZone: timeZone)
        if let chosen, let pick = Skin(rawValue: chosen), band == sky.rawValue { return pick }
        return sky
    }

    /// Whether a stored pick is the one in force now.
    static func isHonoured(chosen: String?, band: String?, at date: Date, timeZone: TimeZone) -> Bool {
        guard let chosen, Skin(rawValue: chosen) != nil else { return false }
        return band == theme(at: date, timeZone: timeZone).rawValue
    }

    /// A script for the website, run before its own boot script: it writes the two keys the site
    /// resolves its skin from, so a page opened in the app wears the app's skin. A pick that is
    /// honoured now is written with its band; anything else (Automatic, or a pick the sky has moved
    /// past) removes both, leaving the site to read the same sky the app reads.
    static func webScript(chosen: String?, band: String?, at date: Date, timeZone: TimeZone) -> String {
        guard isHonoured(chosen: chosen, band: band, at: date, timeZone: timeZone),
              let pick = chosen.flatMap(Skin.init(rawValue:)), let band else {
            return "try{localStorage.removeItem('\(themeKey)');localStorage.removeItem('\(bandKey)')}catch(e){}"
        }
        return "try{localStorage.setItem('\(themeKey)','\(pick.rawValue)');localStorage.setItem('\(bandKey)','\(band)')}catch(e){}"
    }
}
