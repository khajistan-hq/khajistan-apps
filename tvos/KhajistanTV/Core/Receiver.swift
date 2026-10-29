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
/// Until both the denylist and the off-air list have loaded once, every row is withheld.
/// A loaded file that names nobody withdraws nobody. Health does not work that way:
/// a missing or stale `health.json` withdraws every row the probe has not verified.
struct Controls: Sendable {
    let denied: Set<String>
    let health: [String: Health.Result]
    /// True once `denylist.json` has decoded. A failed first fetch is false.
    let denylistLoaded: Bool
    /// True once `off-air-suspects.json` has decoded. A failed first fetch is false.
    let offAirLoaded: Bool
    /// True when `health.json` decoded. A failed fetch is false.
    let healthLoaded: Bool
    /// True when `generatedAt` is no older than two hours at `now`.
    let healthFresh: Bool

    /// `treatAsFresh` is for a debug launch that must not depend on the live file's age.
    /// Production calls leave it false, so a stale file still withdraws every row.
    init(denylist: Denylist?, offAir: OffAir?, health: Health?, now: Date = Date(), treatAsFresh: Bool = false) {
        denylistLoaded = denylist != nil
        offAirLoaded = offAir != nil
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
    /// How long a successful health fetch is kept before the next look.
    static let controlHold: TimeInterval = 600
    /// How soon to ask again after a health fetch fails. The other two files do not start this clock.
    static let healthRetry: TimeInterval = 15
    /// How much of an HLS playlist is read before an unfinished body is unverifiable.
    static let playlistReadCap = 256 * 1024
    /// How many masters a variant may point through. Deeper than this is not verified.
    static let masterDepth = 3
    /// LiveRadio's preroll. The sample lasts this long, and a byte has to arrive at the end of it.
    static let streamMinDuration: TimeInterval = 1.5
    /// LiveRadio's stall. Twelve seconds with no bytes is a dead carrier. It is not a bitrate.
    static let streamStall: TimeInterval = 12
    /// How far LiveRadio reads before it gives up looking for a frame. The probe keeps at most
    /// this many bytes. It is not a minimum rate: 64 KB over 12 s is about 5.5 KB/s, and a
    /// 32 kbps mount is about 4 KB/s.
    static let streamFirstBytes = 65536

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

    /// One deadline for the sample and the silence after it. At least the preroll plus
    /// LiveRadio's stall. A mount that sends nothing in that time is skipped, not cached dead.
    /// The 6 s request timeout must not be a second, shorter deadline.
    static func probeOuterWait(timeout: TimeInterval) -> TimeInterval {
        max(timeout, streamMinDuration + streamStall)
    }

    /// How long a walk waits for a free slot. A holder may read a carrier and a chain of
    /// masters, each up to `probeOuterWait`, before it gives the slot back.
    static func slotWait(timeout: TimeInterval) -> TimeInterval {
        probeOuterWait(timeout: timeout) * Double(masterDepth + 1)
    }

    /// Channels a slot timeout never started. They stay retryable. The walk is not finished
    /// while any of them are still unprobed.
    static func unstarted<T>(_ pending: [T], from index: Int) -> [T] {
        guard index >= 0, index < pending.count else { return [] }
        return Array(pending.dropFirst(index))
    }

    static func mayMarkWalkFinished(unprobed: Int) -> Bool { unprobed == 0 }

    /// A timed-out or cancelled read is skipped. Any other failure can be dead.
    static func failedReadIsCancelled(timedOut: Bool, taskCancelled: Bool) -> Bool {
        timedOut || taskCancelled
    }

    /// How long a pass or a failure is remembered. The playback URL is not dropped on this clock
    /// while the id is still verified.
    static let verdictMemory: TimeInterval = 600

    /// What a tune may do with a remembered carrier. Age does not drop a URL the id still holds
    /// as verified. A verified id with no URL left is probed again, and that miss is not a withdrawal.
    enum TuneMemory: Equatable {
        case play
        case reprobe
        case refuse
    }

    struct CarrierMemory: Equatable {
        var verified = false
        var playback: URL?
        var verdictAt: Date?

        mutating func pass(url: URL, at: Date) {
            verified = true
            playback = url
            verdictAt = at
        }

        /// Drops the verdict once it is older than `memory`. The playback URL stays while verified.
        mutating func age(to now: Date, memory: TimeInterval = ReceiverRules.verdictMemory) {
            if let at = verdictAt, now.timeIntervalSince(at) >= memory {
                verdictAt = nil
            }
            if !verified { playback = nil }
        }

        func tune(_ fresh: URL) -> TuneMemory {
            if let playback {
                return playback.absoluteString == fresh.absoluteString ? .play : .refuse
            }
            // Still verified, but the remembered URL is gone. Probe again. Do not withdraw.
            if verified { return .reprobe }
            return .refuse
        }
    }

    static func withdrawsOnResolveMiss(_ decision: TuneMemory) -> Bool {
        decision == .refuse
    }

    /// A confirm may insert only in the probe epoch it captured before the probe.
    static func confirmStillCurrent(capturedEpoch: Int, epochNow: Int) -> Bool {
        capturedEpoch == epochNow
    }

    /// The player may open `fresh` only when it is the carrier the probe already checked.
    /// A different answer from the carrier endpoint is a playlist this session has not read.
    static func playbackMatches(probed: URL?, fresh: URL) -> Bool {
        probed?.absoluteString == fresh.absoluteString
    }

    /// Ordered probe writes. A commit lands only for the epoch it began in and the generation
    /// still current for that id. Dropping memory moves the epoch and does not hand generation
    /// numbers out again, so a write that was in flight cannot match a number that starts over.
    struct ProbeLedger {
        struct Ticket: Equatable {
            var epoch: Int
            var generation: Int
        }

        private var generation: [String: Int] = [:]
        private var epoch = 0
        private var value: [String: Bool] = [:]

        mutating func begin(_ id: String) -> Ticket {
            let next = (generation[id] ?? 0) + 1
            generation[id] = next
            return Ticket(epoch: epoch, generation: next)
        }

        /// Forgets every verdict and moves the epoch forward. Generation numbers stay.
        mutating func drop() {
            value.removeAll()
            epoch += 1
        }

        @discardableResult
        mutating func commit(_ id: String, live: Bool?, ticket: Ticket) -> Bool {
            guard ticket.epoch == epoch, ticket.generation == generation[id] else { return false }
            if let live { value[id] = live } else { value.removeValue(forKey: id) }
            return true
        }

        func live(_ id: String) -> Bool? { value[id] }
    }

    /// What a health refetch does. A failed fetch keeps the previous file and does not start
    /// the ten-minute clock. The next look is `healthRetry` later. A file that arrived replaces
    /// the previous one and starts the clock.
    enum ControlRefresh: Equatable {
        case skip
        case keep(retryAfter: TimeInterval)
        case replace
    }

    static func controlRefresh(now: Date, clock: Date?, retryAt: Date?, healthArrived: Bool) -> ControlRefresh {
        if let clock, now.timeIntervalSince(clock) < controlHold { return .skip }
        if let retryAt, now < retryAt { return .skip }
        if healthArrived { return .replace }
        return .keep(retryAfter: healthRetry)
    }

    /// Fresh to stale drops every row this session has verified. A later fresh file starts over.
    static func clearSessionAfterFreshnessFlip(wasFresh: Bool, isFresh: Bool) -> Bool {
        wasFresh && !isFresh
    }

    /// Walks that were on screen when health aged out. Each is probed again, and the old verdicts are dropped.
    static func regionsToReprobe(_ keys: Set<String>) -> Set<String> { keys }

    /// A published figure counts a walk only after that walk has finished.
    static func countsTowardFigure(key: String, finished: Set<String>) -> Bool {
        finished.contains(key)
    }

    /// Session probe memory. A stale flip drops it, or a remembered failure would block the new probe.
    struct ProbeMemory: Equatable {
        private var values: [String: Bool] = [:]
        mutating func remember(_ id: String, live: Bool) { values[id] = live }
        mutating func drop() { values.removeAll() }
        func blocks(_ id: String) -> Bool { values[id] != nil }
    }

    /// A feed that failed to load leaves the previous copy in place.
    static func keptFeed<T>(_ fetched: T?, previous: T?) -> T? { fetched ?? previous }

    /// A 403 or 429 is retried inside the walk that asked, and a cancelled walk does not retry.
    static func awaitHostRetry(skipped: Int, retriesLeft: Int, cancelled: Bool) -> Bool {
        skipped > 0 && retriesLeft > 0 && !cancelled
    }

    /// The number on a region chip. Nil until that region's walk has finished. The index live
    /// total is not a stand-in.
    static func regionLiveFigure(verified: Int?) -> String {
        verified.map { $0.formatted() } ?? "\u{2026}"
    }

    /// VoiceOver for that chip. The same mark until the walk finishes, then the verified count.
    static func regionChipAccessibility(label: String, verified: Int?) -> String {
        if let verified {
            return "\(label), \(verified.formatted()) live"
        }
        return "\(label), \u{2026}"
    }

    /// The live line on the map plate.
    static func regionPlateLine(verified: Int?) -> String {
        if let verified {
            return "\(verified.formatted()) LIVE"
        }
        return "\u{2026}"
    }

    /// Channels the receiver may offer, sorted by name.
    ///
    /// A row is kept only when both withdrawal files have loaded, and the row is published,
    /// switched on, absent from the denylist and the off-air list, has an active stream,
    /// and delivers at least half the expected stream. An empty loaded file withdraws nobody.
    /// The grade has to be `online`, or `degraded` on television and radio. Unknown,
    /// intermittent, missing, offline, blocked and `blocked_vantage` rows are never kept, and
    /// a degraded camera is not either. Any other status string is not playable either: a grade
    /// this build does not know stays off the dial. The health feed's grade outranks the
    /// channel's own `healthStatus` once
    /// `health.json` has loaded. That grade counts only while `generatedAt` is no more than
    /// five minutes ahead and no more than two hours behind. A loaded file that is not fresh
    /// withdraws every row. A file that has never loaded withdraws every row too: the shard's
    /// own `healthStatus` is not a fallback. A fresh grade is not enough on its
    /// own: `verified` must contain the id. A repeated id is kept once, at its first
    /// eligible occurrence.
    static func eligible(_ channels: [Channel], controls: Controls, verified: Set<String> = [], allowWithoutHealth: Bool = false) -> [Channel] {
        var seen = Set<String>()
        var kept: [Channel] = []
        for channel in channels {
            // Neither withdrawal file has loaded: show nothing. An empty loaded file withdraws nobody.
            guard controls.denylistLoaded, controls.offAirLoaded else { continue }
            // A missing health file shows nothing, unless a debug launch has asked to grade the shard.
            if !(controls.healthLoaded && controls.healthFresh) && !allowWithoutHealth { continue }
            if controls.healthLoaded && !controls.healthFresh { continue }
            guard held(channel, controls: controls) else { continue }
            if !verified.contains(channel.id) { continue }
            if !seen.insert(channel.id).inserted { continue }
            kept.append(channel)
        }
        return kept.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Rows whose grade is allowed on the dial. When health is fresh these are the rows to show.
    /// When it is not, these are the rows the probe may verify. Nothing else is probed.
    static func probeCandidates(_ channels: [Channel], controls: Controls, allowWithoutHealth: Bool = false) -> [Channel] {
        eligible(channels, controls: controls, verified: Set(channels.map(\.id)), allowWithoutHealth: allowWithoutHealth)
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

    /// An HLS playlist is live when it has a segment and has not ended.
    /// A header alone is not enough. A master (`#EXT-X-STREAM-INF` and no segment) is not live
    /// until its media playlist is read. `#EXT-X-ENDLIST` is not live, with or without segments,
    /// wherever it sits in the body. `truncated` means the read stopped before the playlist
    /// ended, so an end tag may still be coming: that body is not live.
    static func playlistIsLive(_ data: Data, truncated: Bool = false) -> Bool {
        if truncated { return false }
        guard let cleaned = playlistText(data) else { return false }
        guard cleaned.hasPrefix("#EXTM3U") else { return false }
        if cleaned.contains("#EXT-X-ENDLIST") { return false }
        if isMasterPlaylist(cleaned) { return false }
        let segment = cleaned.contains("#EXTINF") || cleaned.contains("#EXT-X-BYTERANGE") || cleaned.contains("#EXT-X-MAP")
        return segment
    }

    /// A master names variants and carries no segments. Every rendition has to be read.
    static func isMasterPlaylist(_ data: Data) -> Bool {
        guard let cleaned = playlistText(data) else { return false }
        return isMasterPlaylist(cleaned)
    }

    /// Every rendition a player might select: the URI after each `#EXT-X-STREAM-INF`,
    /// and the `URI` of each `#EXT-X-MEDIA`.
    static func renditionReferences(in data: Data) -> [String] {
        guard let cleaned = playlistText(data) else { return [] }
        var refs: [String] = []
        var afterStream = false
        for raw in cleaned.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                afterStream = true
                continue
            }
            if line.hasPrefix("#EXT-X-MEDIA") {
                afterStream = false
                if let uri = mediaAttributeURI(line) { refs.append(uri) }
                continue
            }
            if afterStream {
                if line.isEmpty || line.hasPrefix("#") { continue }
                refs.append(line)
                afterStream = false
            }
        }
        return refs
    }

    /// A relative rendition resolves against the playlist's final URL, after redirects.
    static func renditionBase(requested: URL, redirected: URL?) -> URL { redirected ?? requested }

    static func resolveRendition(_ reference: String, against finalURL: URL) -> URL? {
        URL(string: reference, relativeTo: finalURL)?.absoluteURL
    }

    /// The first variant, kept for callers that only need one. Nil when the master has none.
    static func firstVariantURL(in data: Data, relativeTo base: URL) -> URL? {
        renditionReferences(in: data).first.flatMap { resolveRendition($0, against: base) }
    }

    /// One fetched playlist. `finalURL` is `http.url ??` the URL that was requested.
    struct FetchedPlaylist: Equatable {
        var data: Data
        var finalURL: URL
        var truncated: Bool
    }

    /// A media playlist is live or not. A master lists the rendition URLs still to read.
    enum RenditionStep: Equatable {
        case media(Bool)
        case master([URL])
    }

    static func nextRendition(_ playlist: FetchedPlaylist) -> RenditionStep {
        if playlist.truncated { return .media(false) }
        guard let text = playlistText(playlist.data), text.hasPrefix("#EXTM3U") else { return .media(false) }
        if text.contains("#EXT-X-ENDLIST") { return .media(false) }
        let refs = renditionReferences(in: playlist.data)
        if refs.isEmpty { return .media(playlistIsLive(playlist.data)) }
        var urls: [URL] = []
        for ref in refs {
            guard let url = resolveRendition(ref, against: playlist.finalURL) else { return .media(false) }
            urls.append(url)
        }
        return .master(urls)
    }

    /// Live only when every rendition is a live media playlist. A nested master is read up to
    /// `masterDepth`. One dead rendition fails the whole master, so the player is never handed
    /// a playlist that still contains an unverified choice.
    static func allRenditionsLive(_ root: FetchedPlaylist, depth: Int = 0, fetch: (URL) -> FetchedPlaylist?) -> Bool {
        switch nextRendition(root) {
        case .media(let ok):
            return ok
        case .master(let urls):
            if depth >= masterDepth || urls.isEmpty { return false }
            for url in urls {
                guard let child = fetch(url) else { return false }
                if !allRenditionsLive(child, depth: depth + 1, fetch: fetch) { return false }
            }
            return true
        }
    }

    private static func mediaAttributeURI(_ line: String) -> String? {
        guard let start = line.range(of: "URI=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let uri = rest[..<end]
        return uri.isEmpty ? nil : String(uri)
    }

    private static func isMasterPlaylist(_ cleaned: String) -> Bool {
        let segment = cleaned.contains("#EXTINF") || cleaned.contains("#EXT-X-BYTERANGE") || cleaned.contains("#EXT-X-MAP")
        return cleaned.contains("#EXT-X-STREAM-INF") && !segment
    }

    private static func playlistText(_ data: Data) -> String? {
        let slice = data.prefix(playlistReadCap)
        guard let text = String(data: slice, encoding: .utf8)
                ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        return text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A non-HLS body is a live mount only while bytes are still arriving.
    /// A content length is a file. A body that has ended is a file, including one with no
    /// content length. Hitting a read cap is not the same as a body that is still open.
    /// What remains has to be ICY, chunked, or open-ended, and a byte has to arrive at the
    /// end of the preroll (`streamMinDuration`). There is no bitrate floor. `streamStall` is
    /// how long LiveRadio waits with no bytes before calling the carrier dead, and
    /// `streamFirstBytes` is only how much of the body is kept.
    struct StreamSignal: Equatable {
        var icy: Bool = false
        var contentLength: Int? = nil
        var chunked: Bool = false
        /// No content length and not chunked. The body runs until the server closes it.
        var openEnded: Bool = false
        /// True when the body finished. The default is a finished body, so a caller that
        /// names no stream signal does not pass.
        var bodyEnded: Bool = true
        /// A byte arrived at or after the sample deadline. A cap is not this.
        var stillArriving: Bool = false
        var elapsed: TimeInterval = 0
        var bytes: Int = 0
    }

    static func nonHLSIsLive(_ signal: StreamSignal) -> Bool {
        if signal.contentLength != nil { return false }
        if signal.bodyEnded { return false }
        let transfer = signal.icy || signal.chunked || signal.openEnded
        guard transfer, signal.stillArriving else { return false }
        // No bitrate floor. `streamStall` (twelve seconds with no bytes) is when LiveRadio
        // calls a carrier dead. `streamFirstBytes` is only how much of the body is kept.
        // A 32 kbps mount is about 4 KB/s, which is under 64 KB across those twelve seconds.
        guard signal.elapsed >= streamMinDuration, signal.bytes > 0 else { return false }
        return true
    }

    /// What a probe may treat as a live body. 403 is refused. HLS must be a real media playlist.
    /// Anything else needs a media content type and a stream signal, and an HTML or JSON body is not a stream.
    static func responseIsLive(status: Int, contentType: String?, body: Data, hls: Bool,
                               playlistTruncated: Bool = false, signal: StreamSignal = StreamSignal()) -> Bool {
        if status == 403 || !(200..<300).contains(status) { return false }
        if hls { return playlistIsLive(body, truncated: playlistTruncated) }
        let type = (contentType ?? "").lowercased()
        if type.contains("text/html") || type.contains("application/json") || type.contains("text/json") { return false }
        if markupOrJSON(body) { return false }
        guard mediaContentType(type), !body.isEmpty else { return false }
        return nonHLSIsLive(signal)
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
    /// is not a substitute. A file that never loaded does not reach this function for a row
    /// the dial might show.
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
