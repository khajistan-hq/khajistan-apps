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
    }

    struct Slot: Decodable, Hashable, Sendable {
        let start: String
        let start_minute: Int
        let minutes: Int
        let show: String
        let programmes: [Int]
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
}

// The decoder lives in an extension so the memberwise initialiser stays available to previews
// and tests. Every field but `title` decodes strictly: a wrong type there is a real fault.
extension Programming.Programme {
    private enum CodingKeys: String, CodingKey {
        case id, title, seconds, nominal_minutes, clean_start, clean_end, show, channel
        case play_url, audio_only, custodian, transfer, work_kind, country, description
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
    }
}
