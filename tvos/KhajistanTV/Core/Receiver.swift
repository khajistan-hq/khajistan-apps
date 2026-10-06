import Foundation

// MARK: - Index

/// data/open-frequencies/receiver-index.json: which regions exist, which have a shard file, and
/// how many channels of each medium a shard holds. Only the fields the app reads are declared.
struct ReceiverIndex: Decodable, Sendable {
    struct Region: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let kind: String
        let tier: String
    }

    struct Counts: Decodable, Hashable, Sendable {
        let channels: Int
        let live: Int
        let byMedium: [String: Int]
    }

    let regions: [Region]
    let regionFiles: [String: String]
    let cameraFiles: [String: String]?
    let regionCounts: [String: Counts]
    let totals: Counts

    /// Regions that have a shard file, in index order. A region without one (a people's
    /// region that files under its states) is not a place to tune.
    var listedRegions: [Region] {
        regions.filter { regionFiles[$0.id] != nil }
    }

    func shardURL(regionId: String) -> URL? {
        regionFiles[regionId].flatMap(KJURL.sitePath)
    }

    func cameraURL(regionId: String) -> URL? {
        cameraFiles?[regionId].flatMap(KJURL.sitePath)
    }

    /// "65 television · 61 radio · 24 cameras". Zeros are left out, singular for one, and the
    /// line is empty when the region has nothing to count.
    func mediumLine(regionId: String) -> String {
        guard let byMedium = regionCounts[regionId]?.byMedium else { return "" }
        let media: [(key: String, one: String, many: String)] = [
            ("tv", "television", "television"),
            ("radio", "radio", "radio"),
            ("camera", "camera", "cameras"),
        ]
        return media.compactMap { medium -> String? in
            guard let count = byMedium[medium.key], count > 0 else { return nil }
            return "\(count) \(count == 1 ? medium.one : medium.many)"
        }.joined(separator: " · ")
    }
}

// MARK: - Channels

struct Channel: Decodable, Identifiable, Hashable, Sendable {
    struct Stream: Decodable, Hashable, Sendable {
        let id: String
        let format: String?
    }

    let id: String
    /// The website's name for the channel in links and saves (`channel:<slug>`), and the names it
    /// answered to before a rename. Both are in the region shards.
    let slug: String?
    let legacyIds: [String]?
    let name: String
    let nativeName: String?
    let mediaType: String
    let primaryLanguage: String?
    let regionIds: [String]?
    let country: String?
    let territory: String?
    let broadcaster: String?
    let streams: [Stream]
    let activeStreamId: String?
    /// A language a person verified, and the one the STT worker detected (kj-captions-live.js
    /// effectiveLangCode() reads both before `primaryLanguage`).
    let languageCode: String?
    let detectedLanguageName: String?
    let attributionText: String?
    let publicationStatus: String?
    let healthStatus: String?
    let manualDisabled: Bool?
    let description: String?
    let genres: [String]?
    /// A person's ruling that the dancer stays off this channel (open-frequencies.js
    /// isReverentChannel). Absent on every record today; honoured when present.
    let reverent: Bool?
    let visualiser: Bool?

    /// The stream the channel says is live. Nil when none is named or the name matches nothing.
    var activeStream: Stream? {
        guard let activeStreamId else { return nil }
        return streams.first { $0.id == activeStreamId }
    }

    /// Country and language for a caption line. A language nobody has verified is not shown.
    var place: String {
        [country, primaryLanguage]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Not yet verified" }
            .joined(separator: " · ")
    }
}

/// A region shard: data/open-frequencies/regions/<region>.json (and <region>-camera.json).
struct RegionShard: Decodable, Sendable {
    let region: String
    let channels: [Channel]
}

// MARK: - Withdrawal controls

struct Denylist: Decodable, Sendable { let disabledChannelIds: [String] }
struct OffAir: Decodable, Sendable { let offAirChannelIds: [String] }

struct Health: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let channelId: String
        let status: String
        let deliveryRatio: Double?
    }

    let results: [Result]
}

/// The three withdrawal feeds folded into what the eligibility rules look up. Any of them may
/// be missing (offline, not yet fetched): a missing feed withdraws nothing.
struct Controls: Sendable {
    let denied: Set<String>
    let health: [String: Health.Result]

    init(denylist: Denylist?, offAir: OffAir?, health: Health?) {
        denied = Set(denylist?.disabledChannelIds ?? []).union(offAir?.offAirChannelIds ?? [])
        // Last record wins, as it does on the iOS radio lane.
        self.health = Dictionary((health?.results ?? []).map { ($0.channelId, $0) },
                                 uniquingKeysWith: { _, latest in latest })
    }

    static let empty = Controls(denylist: nil, offAir: nil, health: nil)
}

/// Why a carrier answer was refused.
enum CarrierError: Error, Equatable, Sendable {
    /// The body is not the shape the endpoint documents (bad JSON, missing or malformed field).
    case malformed
    /// A well-formed answer that fails policy: not https, credentials in the URL, no host.
    case rejected
}

// MARK: - Rules

enum ReceiverRules {
    /// Below this share of the expected stream a carrier cannot hold playback (the site's
    /// MIN_DELIVERY_RATIO).
    private static let minimumDeliveryRatio = 0.5

    /// Channels the receiver may offer, sorted by name. A channel is dropped when it is not
    /// published, is switched off, is on the denylist or the off-air list, is graded offline or
    /// blocked, delivers under half the expected stream, or has no active stream. The health
    /// feed's grade outranks the channel's own `healthStatus`. A repeated id is kept once, at
    /// its first eligible occurrence.
    static func eligible(_ channels: [Channel], controls: Controls) -> [Channel] {
        var seen = Set<String>()
        var kept: [Channel] = []
        for channel in channels {
            if let published = channel.publicationStatus, published != "published" { continue }
            if channel.manualDisabled == true { continue }
            if controls.denied.contains(channel.id) { continue }
            let check = controls.health[channel.id]
            let status = check?.status ?? channel.healthStatus
            if status == "offline" || status == "blocked" { continue }
            if (check?.deliveryRatio ?? 1) < minimumDeliveryRatio { continue }
            if channel.activeStream == nil { continue }
            if !seen.insert(channel.id).inserted { continue }
            kept.append(channel)
        }
        return kept.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// GET site/api/frequency?stream=<streamId>. The id is opaque, so it is encoded as one.
    static func carrierURL(streamID: String) -> URL {
        var parts = URLComponents(url: KJConfig.site.appendingPathComponent("api/frequency"),
                                  resolvingAgainstBaseURL: false)!
        parts.percentEncodedQuery = "stream=" + KJURL.encodeQueryValue(streamID)
        return parts.url!
    }

    private struct CarrierBody: Decodable { let url: String? }

    /// The resolver's answer, `{"stream":"…","url":"https://…"}`, reduced to the validated URL.
    static func carrier(from data: Data) throws -> URL {
        guard let text = (try? JSONDecoder().decode(CarrierBody.self, from: data))?.url,
              let url = URL(string: text) else { throw CarrierError.malformed }
        guard validCarrier(url) else { throw CarrierError.rejected }
        return url
    }

    /// https, a host, and no credentials. Nothing else about a carrier is the app's to judge.
    static func validCarrier(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty else { return false }
        return parts.user == nil && parts.password == nil
    }

    /// Tiers shown before the viewer switches on the extensions.
    static let tiersOnByDefault: Set<String> = ["heartbeat", "core"]

    static func mediumLabel(_ mediaType: String) -> String {
        switch mediaType.lowercased() {
        case "tv": return "Television"
        case "radio": return "Radio"
        case "camera": return "Cameras"
        default: return mediaType.prefix(1).uppercased() + mediaType.dropFirst()
        }
    }
}
