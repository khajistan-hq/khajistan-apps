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
            // The registry's filing word for a channel made abroad for the region reads as
            // jargon on screen; a viewer is told it is a diaspora channel.
            .map { $0 == "Borderland / diaspora" ? "Diaspora" : $0 }
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

/// Only the playback controls expire. Caption text and open menus have separate lifetimes.
/// The deadline makes an older timer harmless after a new remote interaction.
struct ReceiverControlsVisibility {
    static let idleSeconds: TimeInterval = 5
    private(set) var isVisible = true
    private var deadline: TimeInterval?

    mutating func wake(at now: TimeInterval, canHide: Bool) {
        isVisible = true
        deadline = canHide ? now + Self.idleSeconds : nil
    }

    @discardableResult
    mutating func expire(at now: TimeInterval, canHide: Bool) -> Bool {
        guard canHide, let deadline, now >= deadline else { return false }
        isVisible = false
        self.deadline = nil
        return true
    }
}

// MARK: - The song on air

/// The song on a channel, as the website's receiver shows it (open-frequencies.js
/// watchSongMetadata; owner, 2026-11-04: "shazam so our channels show metadata of songs being
/// played"). A live channel asks the now_playing() RPC, which also marks the channel wanted, so
/// the fingerprinting worker (scripts/signal-room/now_playing_worker.py) listens to it. A
/// Khajistan TV programme is a fixed file, so its songs were heard once and sit in songs.json.
enum NowPlaying {
    static let unavailable = "Current song title unavailable."
    static let pollSeconds = 20
    /// Failed calls in a row before a kept song is dropped (60 s), as on the website.
    static let misses = 3

    /// "Artist – Title", or the title alone.
    static func line(artist: String?, title: String) -> String {
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? title : artist + " \u{2013} " + title
    }

    /// What a player prints for a live channel: the song, or for radio the site's
    /// "unavailable" line; television with no song prints nothing.
    static func caption(song: String, mediaType: String) -> String? {
        if !song.isEmpty { return "Now playing: " + song }
        return mediaType == "radio" ? unavailable : nil
    }

    private struct Row: Decodable { let artist: String?; let title: String? }

    /// The RPC's answer as a line: "" when nothing is playing, nil when it could not be read.
    static func parse(_ data: Data) -> String? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        guard let row = rows.first, let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return "" }
        return line(artist: row.artist, title: title)
    }

    /// One call. Nil: the call failed.
    static func fetch(_ channelId: String) async -> String? {
        guard let url = SupabaseRoute.url("/rest/v1/rpc/now_playing"),
              let body = try? JSONSerialization.data(withJSONObject: ["p_channel": channelId]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await SupabaseRoute.data(for: request, session: .shared),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// One poll's effect on what is shown: an answer replaces the song ("" clears it at once);
    /// a failed call keeps it until `misses` failures in a row.
    static func step(kept: String, failures: Int, answer: String?) -> (kept: String, failures: Int) {
        guard let answer else { return (failures + 1 >= misses ? "" : kept, failures + 1) }
        return (answer, 0)
    }

    /// Asks every 20 s for as long as the calling task lives (a view's `.task(id:)`), handing each
    /// change to `update`. While `active` says no (paused, tuning, failed) nothing is asked, so a
    /// paused radio does not keep the worker listening for nobody.
    static func watch(_ channelId: String, active: @MainActor @escaping () -> Bool = { true },
                      update: @MainActor @escaping (String) -> Void) async {
        var state = (kept: "", failures: 0)
        while !Task.isCancelled {
            if await active() {
                state = step(kept: state.kept, failures: state.failures, answer: await fetch(channelId))
                if Task.isCancelled { return }
                let shown = state.kept
                await update(shown)
            }
            try? await Task.sleep(for: .seconds(pollSeconds))
        }
    }
}

/// songs.json: [start_s, end_s, artist, title] spans, seconds into a programme's file, keyed by
/// programme id (scripts/khajistan_tv/song_pass.py). Read once an hour, as the site does.
struct SongSpan: Decodable, Equatable, Sendable {
    let start: Double, end: Double, artist: String, title: String
    init(start: Double, end: Double, artist: String, title: String) {
        self.start = start; self.end = end; self.artist = artist; self.title = title
    }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        start = try c.decode(Double.self); end = try c.decode(Double.self)
        // A null artist is no artist; a failed decode would not move past it.
        artist = try c.decodeNil() ? "" : c.decode(String.self)
        title = try c.decode(String.self)
    }
}

/// A span that does not read is dropped alone, never the file round it.
private struct LossySpan: Decodable {
    let span: SongSpan?
    init(from decoder: Decoder) throws { span = try? SongSpan(from: decoder) }
}

actor HouseSongs {
    static let shared = HouseSongs()
    private struct File: Decodable { let songs: [String: [LossySpan]] }
    private var songs: [String: [SongSpan]] = [:]
    private var loadedAt = Date.distantPast
    private var loading: Task<[String: [SongSpan]]?, Never>?

    static func decode(_ data: Data) -> [String: [SongSpan]]? {
        (try? JSONDecoder().decode(File.self, from: data))?.songs.mapValues { $0.compactMap(\.span) }
    }

    /// The song playing `seconds` into a programme, or "".
    static func song(in spans: [SongSpan], at seconds: Double) -> String {
        guard let span = spans.first(where: { seconds >= $0.start && seconds < $0.end }) else { return "" }
        return NowPlaying.line(artist: span.artist, title: span.title)
    }

    /// Asked without the preview password first and with it on a 401, as the schedule is
    /// (TransmissionStore.fetchSchedule): the file sits behind the gate until launch.
    func spans(for programmeId: String, previewPassword: String?) async -> [SongSpan] {
        if Date().timeIntervalSince(loadedAt) > 3600 {
            // A second caller while the file is on its way waits for the same read.
            let task = loading ?? Task { await Self.read(previewPassword: previewPassword) }
            loading = task
            let read = await task.value
            loading = nil
            // A failed read keeps the songs already known and is asked again next time.
            if let read { songs = read; loadedAt = Date() }
        }
        return songs[programmeId] ?? []
    }

    private static func read(previewPassword: String?) async -> [String: [SongSpan]]? {
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        guard let url = KJURL.sitePath("/data/khajistan-tv/songs.json?h=\(hour)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        var reply = try? await URLSession.shared.data(for: request)
        if (reply?.1 as? HTTPURLResponse)?.statusCode == 401, let previewPassword {
            request.setValue(Transmission.basicAuthorization(user: KJConfig.previewUser, password: previewPassword),
                             forHTTPHeaderField: "Authorization")
            reply = try? await URLSession.shared.data(for: request)
        }
        guard let (data, response) = reply, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return decode(data)
    }
}
