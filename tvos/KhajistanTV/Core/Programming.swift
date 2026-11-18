import Foundation

/// data/khajistan-tv/programming-YYYY-MM.json, the month's schedule. Only the fields the app
/// reads are declared; the file carries more.
///
/// `slot.programmes` are INTEGER INDEXES into `programme_order`, not ids. `programmes` is keyed
/// by id. Numerics that can be fractional are Double; `start_minute`, `minutes`, `number` and
/// `channel` are whole numbers in every month on disk and are Int.
struct Programming: Decodable, Sendable {
    struct Meta: Decodable, Sendable {
        struct ChannelInfo: Decodable, Identifiable, Hashable, Sendable {
            let id: String
            let number: Int
            let name: String
            let line: String?
        }

        let channels: [ChannelInfo]
    }

    struct Show: Decodable, Hashable, Sendable {
        let slug: String
        let name: String
        let line: String?
        let channel: String?
    }

    struct Programme: Decodable, Hashable, Sendable {
        let id: String
        /// Five vinyl rips in the real schedule carry no `title` key. They decode with an empty
        /// title rather than failing the whole month; a surface that shows a title should fall
        /// back to the show name when this is empty.
        let title: String
        let seconds: Double?
        let nominal_minutes: Double?
        let clean_start: Double?
        let clean_end: Double?
        let show: String?
        let channel: Int?
        let play_url: String?
        let audio_only: Bool?
        let custodian: String?
        let transfer: String?
        let work_kind: String?
        let country: String?
        let description: String?
        /// A prepared WebVTT file on the site, e.g. /assets/tv-subtitles/<id>.en.vtt (video.html).
        let subtitle_url: String?
        /// The standardized name build_programming.py writes (owner, 2026-11-08: "names need to
        /// be standardized"). Absent where a title could not be cleaned into one: a surface then
        /// shows the show's name, as every surface did before. Last, with a default, so the
        /// memberwise initialiser the tests use is unchanged.
        var display_title: String? = nil
        /// The year the record carries; shown after the country on the strip (owner, 2026-11-15).
        var year: Int? = nil
        /// The checked English or Roman form of a name in Arabic, Persian or Urdu script, shown on
        /// a line of its own under it, as the Receiver does (owner, 2026-11-08: "original and
        /// translation"; 2026-11-17 on the Apple TV: "name of film should also be in roman"). On a
        /// handful of records it runs the other way (a Latin name, its Urdu form); the site prints
        /// those too, so this does.
        var display_title_en: String? = nil

        /// The second line under the name, only where the name is the programme's own title and
        /// the two differ.
        var secondTitle: String? {
            guard let shown = display_title?.trimmingCharacters(in: .whitespacesAndNewlines), !shown.isEmpty,
                  let en = display_title_en?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty, en != shown else { return nil }
            return en
        }
    }

    struct Slot: Decodable, Hashable, Sendable {
        let start: String
        let start_minute: Int
        let minutes: Int
        let show: String
        let programmes: [Int]
        /// Since 2026-11-08 a strip carries whole programmes and the next starts the second they
        /// end, so the site writes the strip in seconds (fractional), and an evening strip can run
        /// past midnight. A file built before that has minutes only. kj-station-clock.js reads
        /// these first (slotStart / slotLength); so does every reading in StationClock.
        var start_second: Double? = nil
        var seconds: Double? = nil

        var startSecond: Double { start_second ?? Double(start_minute * 60) }
        var lengthSeconds: Double { seconds ?? Double(minutes * 60) }
        var endSecond: Double { startSecond + lengthSeconds }
    }

    struct Day: Decodable, Sendable {
        let date: String
        let weekday: String?
        let channels: [String: [Slot]]
    }

    let _meta: Meta
    let shows: [String: Show]
    let programme_order: [String]
    let programmes: [String: Programme]
    let days: [Day]
    /// The last day of the previous month, so a strip still running after midnight on the 1st
    /// is found (the site writes it since 2026-11-08). Nil in older files.
    var prev_day: Day? = nil
    /// The next month's first strip per channel, so Up next crosses the month end (the site
    /// writes it since 2026-11-16, owner: "Builder carries next_day"). Nil in older files.
    var next_day: Day? = nil
}

// The decoder lives in an extension so the memberwise initialiser stays available to previews
// and tests. Every field but `title` decodes strictly: a wrong type there is a real fault.
extension Programming.Programme {
    private enum CodingKeys: String, CodingKey {
        case id, title, seconds, nominal_minutes, clean_start, clean_end, show, channel
        case play_url, audio_only, custodian, transfer, work_kind, country, description, subtitle_url
        case display_title, display_title_en, year
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
        seconds = try values.decodeIfPresent(Double.self, forKey: .seconds)
        nominal_minutes = try values.decodeIfPresent(Double.self, forKey: .nominal_minutes)
        clean_start = try values.decodeIfPresent(Double.self, forKey: .clean_start)
        clean_end = try values.decodeIfPresent(Double.self, forKey: .clean_end)
        show = try values.decodeIfPresent(String.self, forKey: .show)
        channel = try values.decodeIfPresent(Int.self, forKey: .channel)
        play_url = try values.decodeIfPresent(String.self, forKey: .play_url)
        audio_only = try values.decodeIfPresent(Bool.self, forKey: .audio_only)
        custodian = try values.decodeIfPresent(String.self, forKey: .custodian)
        transfer = try values.decodeIfPresent(String.self, forKey: .transfer)
        work_kind = try values.decodeIfPresent(String.self, forKey: .work_kind)
        country = try values.decodeIfPresent(String.self, forKey: .country)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        subtitle_url = try values.decodeIfPresent(String.self, forKey: .subtitle_url)
        display_title = try values.decodeIfPresent(String.self, forKey: .display_title)
        // Read leniently: a field the strip only decorates with must never fail the month.
        display_title_en = (try? values.decodeIfPresent(String.self, forKey: .display_title_en)) ?? nil
        year = (try? values.decodeIfPresent(Int.self, forKey: .year)) ?? nil
    }
}

// The strip's and the guide's naming rules, here rather than in the view so the core tests reach them.
extension OnAir {
    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The headline's second line (Programme.secondTitle), only while the headline is the
    /// programme's own name and not the show standing in for it.
    var secondTitle: String? {
        guard let now = nowName, now == Self.trimmed(programme?.display_title) else { return nil }
        return programme?.secondTitle
    }

    /// The guide's one line for a channel: what is on, with its second name after it. The name is
    /// isolated (U+2068 … U+2069) so a Persian title keeps the Roman form on its own side.
    var guideLine: String {
        let name = nowName ?? show?.name ?? ""
        guard let second = secondTitle else { return name }
        return "\u{2068}" + name + "\u{2069} \u{00B7} " + second
    }

    /// The year for the detail line, unless a name on the strip already carries it ("Abadan
    /// (1971)"): open-frequencies.js gives a title that contains its year no second one.
    func shownYear(headline: String) -> String? {
        guard let year = programme?.year.map(String.init) else { return nil }
        return [headline, secondTitle ?? ""].contains { $0.contains(year) } ? nil : year
    }
}
