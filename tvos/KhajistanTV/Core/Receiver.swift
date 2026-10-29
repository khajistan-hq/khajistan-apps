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
    /// The receiver payload carries explicit transcription/translation rights refusals.
    var captionsDenied: Bool? = nil

    /// The attribution's first clause, "Direct broadcast by …", which is what a player prints
    /// (owner, 2026-10-08). The rest of the record's sentence stays in the data and on the website.
    var sourceLine: String? {
        guard let attributionText else { return nil }
        let first = attributionText.split(separator: ";", maxSplits: 1).first.map(String.init) ?? attributionText
        let line = first.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

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

    /// When `health.json` was written. Absent or unreadable means the grade cannot be trusted.
    let generatedAt: String?
    let results: [Result]

    var generatedAtDate: Date? {
        generatedAt.flatMap(ReceiverRules.parseStamp)
    }
}

/// The three withdrawal feeds folded into what the eligibility rules look up.
/// A missing denylist or off-air list withdraws nothing. Health does not work that way:
/// a missing or stale `health.json` withdraws every row the probe has not verified.
struct Controls: Sendable {
    let denied: Set<String>
    let health: [String: Health.Result]
    /// True when `health.json` decoded. A failed fetch is false.
    let healthLoaded: Bool
    /// True when `generatedAt` is no older than two hours at `now`.
    let healthFresh: Bool

    /// `treatAsFresh` is for a debug launch that must not depend on the live file's age.
    /// Production calls leave it false, so a stale file still withdraws every row.
    init(denylist: Denylist?, offAir: OffAir?, health: Health?, now: Date = Date(), treatAsFresh: Bool = false) {
        denied = Set(denylist?.disabledChannelIds ?? []).union(offAir?.offAirChannelIds ?? [])
        // Last record wins, as it does on the iOS radio lane.
        self.health = Dictionary((health?.results ?? []).map { ($0.channelId, $0) },
                                 uniquingKeysWith: { _, latest in latest })
        healthLoaded = health != nil
        if treatAsFresh && health != nil {
            healthFresh = true
        } else if let stamp = health?.generatedAtDate {
            healthFresh = ReceiverRules.healthIsFresh(generatedAt: stamp, now: now)
        } else {
            healthFresh = false
        }
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

    /// A grade older than this is not fresh. The clock is read again while the dial is up.
    static let healthMaxAge: TimeInterval = 2 * 60 * 60
    /// A stamp this far ahead of the device is still accepted. Further ahead is not fresh.
    static let healthFutureSkew: TimeInterval = 5 * 60

    /// Fresh only when the stamp is not more than five minutes ahead and not more than two hours behind.
    static func healthIsFresh(generatedAt stamp: Date, now: Date) -> Bool {
        stamp.timeIntervalSince(now) <= healthFutureSkew && now.timeIntervalSince(stamp) <= healthMaxAge
    }

    /// A failed play may withdraw and skip only while that tune is still the one on screen.
    /// A newer tune means the viewer has moved on: do neither.
    static func mayActOnFailure(failedID: String, tuneRevision: Int, currentRevision: Int, showingID: String) -> Bool {
        tuneRevision == currentRevision && showingID == failedID
    }

    /// How many probes one host may have in flight, and how a 403 or 429 is remembered.
    struct HostBudget: Equatable {
        static let cap = 2
        static let retryLimit = 3
        static let backoff: TimeInterval = 30

        enum Admit: Equatable { case go, skip, giveUp }

        private var flying: [String: Int] = [:]
        private var until: [String: Date] = [:]
        private var strikes: [String: Int] = [:]

        mutating func begin(host: String, now: Date) -> Admit {
            if (strikes[host] ?? 0) >= Self.retryLimit { return .giveUp }
            if let until = until[host], now < until { return .skip }
            if (flying[host] ?? 0) >= Self.cap { return .skip }
            flying[host, default: 0] += 1
            return .go
        }

        mutating func end(host: String, throttled: Bool, now: Date) {
            flying[host] = max(0, (flying[host] ?? 1) - 1)
            guard throttled else { return }
            let count = (strikes[host] ?? 0) + 1
            strikes[host] = count
            until[host] = count >= Self.retryLimit
                ? .distantFuture
                : now.addingTimeInterval(Self.backoff)
        }
    }

    /// A skipped probe is not a failure. The row stays hidden and can be tried again.
    enum ProbeMark: Equatable { case live, dead, skipped }

    static func probeMark(status: Int?, skipped: Bool, bodyLive: Bool) -> ProbeMark {
        if skipped { return .skipped }
        if status == 403 || status == 429 { return .skipped }
        return bodyLive ? .live : .dead
    }

    /// Ordered probe writes. A commit whose generation is no longer current does not land.
    struct ProbeLedger {
        private var generation: [String: Int] = [:]
        private var value: [String: Bool] = [:]

        mutating func begin(_ id: String) -> Int {
            let next = (generation[id] ?? 0) + 1
            generation[id] = next
            return next
        }

        @discardableResult
        mutating func commit(_ id: String, live: Bool?, generation gen: Int) -> Bool {
            guard gen == self.generation[id] else { return false }
            if let live { value[id] = live } else { value.removeValue(forKey: id) }
            return true
        }

        func live(_ id: String) -> Bool? { value[id] }
    }

    /// Channels the receiver may offer, sorted by name.
    ///
    /// A row is kept only when it is published, switched on, absent from the denylist and the
    /// off-air list, has an active stream, and delivers at least half the expected stream.
    /// The grade has to be `online`, or `degraded` on television and radio. Unknown,
    /// intermittent, missing, offline, blocked and `blocked_vantage` rows are never kept, and
    /// a degraded camera is not either. Any other status string is not playable either: a grade
    /// this build does not know stays off the dial. The health feed's grade outranks the
    /// channel's own `healthStatus` once
    /// `health.json` has loaded. That grade counts only while `generatedAt` is no more than
    /// five minutes ahead and no more than two hours behind. A loaded file that is not fresh
    /// withdraws every row. When the file did not load, a row is kept only if this session's
    /// probe verified it and the shard grade is allowed. A fresh grade is not enough on its
    /// own: `verified` must contain the id. A repeated id is kept once, at its first
    /// eligible occurrence.
    static func eligible(_ channels: [Channel], controls: Controls, verified: Set<String> = []) -> [Channel] {
        var seen = Set<String>()
        var kept: [Channel] = []
        for channel in channels {
            guard held(channel, controls: controls) else { continue }
            if controls.healthLoaded && !controls.healthFresh { continue }
            if !verified.contains(channel.id) { continue }
            if !seen.insert(channel.id).inserted { continue }
            kept.append(channel)
        }
        return kept.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Rows whose grade is allowed on the dial. When health is fresh these are the rows to show.
    /// When it is not, these are the rows the probe may verify. Nothing else is probed.
    static func probeCandidates(_ channels: [Channel], controls: Controls) -> [Channel] {
        eligible(channels, controls: controls, verified: Set(channels.map(\.id)))
    }

    /// The next row in `list` after `id`, wrapping once, that is not in `excluding`.
    /// Nil when every other row is excluded: that scope has no signal left.
    static func nextLive(after id: String, in list: [Channel], excluding: Set<String>) -> Channel? {
        guard let start = list.firstIndex(where: { $0.id == id }) else {
            return list.first { !excluding.contains($0.id) }
        }
        guard list.count > 1 else { return nil }
        for step in 1..<list.count {
            let channel = list[(start + step) % list.count]
            if !excluding.contains(channel.id) { return channel }
        }
        return nil
    }

    /// An HLS playlist is live when it has a segment or a variant stream and has not ended.
    /// A header alone is not enough. `#EXT-X-ENDLIST` is not live, with or without segments.
    static func playlistIsLive(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(8192), encoding: .utf8)
                ?? String(data: data.prefix(8192), encoding: .isoLatin1) else { return false }
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("#EXTM3U") else { return false }
        let segment = cleaned.contains("#EXTINF") || cleaned.contains("#EXT-X-BYTERANGE") || cleaned.contains("#EXT-X-MAP")
        let variant = cleaned.contains("#EXT-X-STREAM-INF")
        // A playlist that has ended is not a live signal, even if it still lists segments.
        if cleaned.contains("#EXT-X-ENDLIST") { return false }
        return segment || variant
    }

    /// What a probe may treat as a live body. 403 is refused. HLS must be a real playlist.
    /// Anything else needs a media content type, and an HTML or JSON body is not a stream.
    static func responseIsLive(status: Int, contentType: String?, body: Data, hls: Bool) -> Bool {
        if status == 403 || !(200..<300).contains(status) { return false }
        if hls { return playlistIsLive(body) }
        let type = (contentType ?? "").lowercased()
        if type.contains("text/html") || type.contains("application/json") || type.contains("text/json") { return false }
        if markupOrJSON(body) { return false }
        guard mediaContentType(type), !body.isEmpty else { return false }
        return true
    }

    private static func mediaContentType(_ type: String) -> Bool {
        if type.hasPrefix("audio/") || type.hasPrefix("video/") { return true }
        return type.contains("application/ogg") || type.contains("application/octet-stream")
            || type.contains("application/flac")
    }

    private static func markupOrJSON(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(64), encoding: .utf8)
                ?? String(data: data.prefix(64), encoding: .isoLatin1) else { return false }
        let start = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return start.hasPrefix("<") || start.hasPrefix("{") || start.hasPrefix("[")
    }

    /// `health.json`'s `generatedAt`, internet date time, with or without fractional seconds.
    static func parseStamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// Published, not switched off, not withdrawn, a usable stream, and a grade the dial may show.
    private static func held(_ channel: Channel, controls: Controls) -> Bool {
        if let published = channel.publicationStatus, published != "published" { return false }
        if channel.manualDisabled == true { return false }
        if controls.denied.contains(channel.id) { return false }
        let check = controls.health[channel.id]
        if let check {
            // Once a health row exists, a missing delivery ratio is not a pass.
            guard let ratio = check.deliveryRatio, ratio >= minimumDeliveryRatio else { return false }
        }
        if channel.activeStream == nil { return false }
        return gradeAllows(channel, controls: controls)
    }

    /// `online` for any medium, `degraded` for television and radio. Everything else is refused.
    /// That includes a missing grade, `offline`, `blocked`, `blocked_vantage` (the health job's
    /// 403 or geo-block), and any status string this build has not been taught. The refusal is
    /// an allow-list, so a future grade stays off the dial until a build names it.
    /// Once health has loaded, a row with no result is missing: the shard's own `healthStatus`
    /// is not a substitute. When the file did not load, the shard status is all there is, and
    /// it still has to be one of those two grades.
    private static func gradeAllows(_ channel: Channel, controls: Controls) -> Bool {
        let status: String?
        if controls.healthLoaded {
            status = controls.health[channel.id]?.status
        } else {
            status = channel.healthStatus
        }
        switch status?.lowercased() {
        case "online":
            return true
        case "degraded":
            let medium = channel.mediaType.lowercased()
            return medium == "tv" || medium == "radio"
        case nil, "offline", "blocked", "blocked_vantage", "unknown", "intermittent", "missing":
            return false
        default:
            return false
        }
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

    /// "12 television · 4 radio · 3 cameras", zeros left out. A nil camera count means that
    /// shard has not finished, so cameras are left out of this line.
    static func verifiedMediumLine(tv: Int, radio: Int, camera: Int?) -> String {
        let media: [(count: Int?, one: String, many: String)] = [
            (tv, "television", "television"),
            (radio, "radio", "radio"),
            (camera, "camera", "cameras"),
        ]
        return media.compactMap { item -> String? in
            guard let count = item.count, count > 0 else { return nil }
            return "\(count) \(count == 1 ? item.one : item.many)"
        }.joined(separator: " · ")
    }

    static func mediumLabel(_ mediaType: String) -> String {
        switch mediaType.lowercased() {
        case "tv": return "Television"
        case "radio": return "Radio"
        case "camera": return "Cameras"
        default: return mediaType.prefix(1).uppercased() + mediaType.dropFirst()
        }
    }
}

/// One automatic start for each visit to Receiver, never for a render or a player dismissal.
/// An async picker must present only while its original ticket is still current.
struct ReceiverOpeningPlayback {
    private var revision = 0
    private var attempted = false

    mutating func begin(active: Bool, ready: Bool, explicitDestination: Bool) -> Int? {
        guard active else {
            revision += 1
            attempted = false
            return nil
        }
        guard ready, !attempted else { return nil }
        attempted = true
        guard !explicitDestination else { return nil }
        return revision
    }

    mutating func manualInteraction() {
        revision += 1
        attempted = true
    }

    func admits(_ ticket: Int) -> Bool { ticket == revision && attempted }
}

/// A resolver may finish after Pause; only the latest explicit playback intent may attach it.
struct ReceiverTuneIntent {
    private var revision = 0
    private var wantsPlayback = false

    mutating func begin() -> Int {
        revision += 1
        wantsPlayback = true
        return revision
    }

    mutating func cancel() {
        revision += 1
        wantsPlayback = false
    }

    func admits(_ ticket: Int) -> Bool { wantsPlayback && ticket == revision }
}
