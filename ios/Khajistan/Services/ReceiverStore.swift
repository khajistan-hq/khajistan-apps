import Foundation
import Observation

/// Why a receiver call came back empty-handed. The messages are written for the viewer.
enum ReceiverStoreError: LocalizedError {
    case indexNotLoaded
    case unreadable
    case notOnDial
    case unplayable
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .indexNotLoaded: return "The receiver list has not loaded."
        case .unreadable: return "The receiver sent an answer that could not be read."
        case .notOnDial: return "This channel is not on the dial right now."
        case .unplayable: return "This signal could not be played."
        case .http(let code): return "The receiver returned HTTP \(code)."
        }
    }
}

/// The receiver's index, its region shards and the three withdrawal feeds, fetched from the
/// site. A channel is listed or it is not: everything a feed withdraws is dropped here.
@MainActor @Observable
final class ReceiverStore {
    private(set) var index: ReceiverIndex?
    private(set) var indexError: String?
    /// The core region shapes, kept once fetched: the map draws from them and a region page reads
    /// its native name from them. Tracked, so a page that asked before they arrived draws again.
    private(set) var coreShapes: RegionShapes?
    var isLoading = false

    /// Verified counts, written once when a region's probe walk finishes. Nil until then.
    private(set) var liveNow: Int?
    private(set) var televisionNow: Int?
    private(set) var radioNow: Int?
    private(set) var camerasNow: Int?
    /// Bumped when rows appear, when one is withdrawn, or when the health clock moves.
    private(set) var dialGeneration = 0

    @ObservationIgnored private var extendedShapes: RegionShapes?
    @ObservationIgnored private var denylistFile: Denylist?
    @ObservationIgnored private var offAirFile: OffAir?
    @ObservationIgnored private var healthFile: Health?
    @ObservationIgnored private var controlsFetchedAt: Date?
    @ObservationIgnored private var indexFetchedAt: Date?
    @ObservationIgnored private var shards: [String: [Channel]] = [:]
    @ObservationIgnored private var indexLoad: Task<Void, Never>?
    @ObservationIgnored private var channelLoads: [String: Task<[Channel], Error>] = [:]
    /// Ids the probe has verified and that have not since failed.
    @ObservationIgnored private var verified: Set<String> = []
    /// Ids that failed in this session. A liked or saved row with one of these ids is not shown.
    private(set) var withdrawn: Set<String> = []
    @ObservationIgnored private var offerings: [String: [Channel]] = [:]
    @ObservationIgnored private var walksFinished: Set<String> = []
    @ObservationIgnored private var loadToken: [String: Int] = [:]
    @ObservationIgnored private var probeChain: Task<Void, Never> = Task {}
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private let probe = ReceiverProbe()
    private let urlSession: URLSession

    /// How long a fetched index or set of feeds is trusted before the next look.
    private static let staleAfter: TimeInterval = 600

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    private nonisolated static func dataURL(_ file: String) -> URL {
        KJConfig.site.appendingPathComponent("data/open-frequencies/\(file)")
    }

    /// Fetches the index unless a fresh one is held. A caller that arrives while a fetch is in
    /// flight waits for that fetch rather than returning empty-handed (on a phone the map and the
    /// region list ask at the same moment).
    func loadIndex() async {
        if let inFlight = indexLoad {
            await inFlight.value
            return
        }
        if index != nil, let at = indexFetchedAt, Date().timeIntervalSince(at) < Self.staleAfter { return }
        let task = Task { await fetchIndex() }
        indexLoad = task
        await task.value
        indexLoad = nil
    }

    private func fetchIndex() async {
        isLoading = true
        defer { isLoading = false }
        if index == nil { indexError = nil }
        do {
            let (data, response) = try await urlSession.data(from: Self.dataURL("receiver-index.json"))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw ReceiverStoreError.http(code) }
            let decoded: ReceiverIndex
            do {
                decoded = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(ReceiverIndex.self, from: data)
                }.value
            } catch {
                throw ReceiverStoreError.unreadable
            }
            index = decoded
            indexError = nil
            indexFetchedAt = Date()
            shards.removeAll()
        } catch {
            if Task.isCancelled { return }
            // A list already on screen stays; only a missing list is an error to show.
            if index == nil { indexError = error.localizedDescription }
        }
    }

    /// Rows of one region revealed so far. Each successful probe adds a row; nothing is shown before that.
    func shown(regionId: String, cameras: Bool) -> [Channel] {
        _ = dialGeneration
        let key = cameras ? regionId + "-camera" : regionId
        return (offerings[key] ?? []).filter { lists($0) }
    }

    /// True once that shard's probe walk has finished, including a walk that found nothing.
    func walkFinished(regionId: String, cameras: Bool) -> Bool {
        _ = dialGeneration
        return walksFinished.contains(cameras ? regionId + "-camera" : regionId)
    }

    /// The channels of one region the receiver may offer, after probing them. `cameras` picks the
    /// camera shard. Rows appear on `shown` as each probe succeeds. Cancelling the caller stops the walk.
    func channels(regionId: String, cameras: Bool) async throws -> [Channel] {
        let key = cameras ? regionId + "-camera" : regionId
        if let existing = channelLoads[key] { return try await existing.value }
        let token = (loadToken[key] ?? 0) + 1
        loadToken[key] = token
        let task = Task { try await self.loadChannels(regionId: regionId, cameras: cameras, key: key, token: token) }
        channelLoads[key] = task
        defer { if channelLoads[key] == task { channelLoads[key] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Stops a walk the view no longer needs. Rows already verified stay verified.
    func cancelChannels(regionId: String, cameras: Bool) {
        let key = cameras ? regionId + "-camera" : regionId
        loadToken[key] = (loadToken[key] ?? 0) + 1
        channelLoads[key]?.cancel()
        channelLoads[key] = nil
    }

    /// Re-reads freshness on a timer so a grade that ages out leaves the screen without a refetch.
    func watchHealthClock() {
        guard clockTask == nil else { return }
        clockTask = Task { await self.healthClock() }
    }

    /// True when this channel may be shown, including a liked or saved one.
    func lists(_ channel: Channel) -> Bool {
        _ = dialGeneration
        guard !withdrawn.contains(channel.id) else { return false }
        return ReceiverRules.eligible([channel], controls: controls(), verified: verified).first != nil
    }

    /// The channel failed to play. It leaves the dial until a later probe succeeds.
    func withdraw(_ id: String) {
        withdrawn.insert(id)
        verified.remove(id)
        offerings = offerings.mapValues { $0.filter { $0.id != id } }
        dialGeneration += 1
        enqueueProbe { await self.probe.remember(id, live: false) }
    }

    /// Clears the failure so a new probe may run. Does not mark the row verified.
    func restore(_ id: String) {
        withdrawn.remove(id)
        verified.remove(id)
        enqueueProbe { await self.probe.forget(id) }
    }

    /// Probes one channel the viewer asked for again. True only when that probe says it is live.
    func confirm(_ channel: Channel) async -> Bool {
        await refreshControlsIfStale()
        restore(channel.id)
        guard ReceiverRules.probeCandidates([channel], controls: controls()).first != nil else { return false }
        let live = await probe.verify([channel])
        guard !Task.isCancelled, live.contains(channel.id), !withdrawn.contains(channel.id) else { return false }
        verified.insert(channel.id)
        dialGeneration += 1
        return lists(channel)
    }

    /// Verified rows of `medium` already on the dial for this region. Does not start a probe.
    func verifiedChannels(regionId: String, medium: String) -> [Channel] {
        shown(regionId: regionId, cameras: medium == "camera").filter { $0.mediaType == medium }
    }

    private func controls(now: Date = Date()) -> Controls {
        Controls(denylist: denylistFile, offAir: offAirFile, health: healthFile, now: now)
    }

    private func enqueueProbe(_ work: @escaping @Sendable () async -> Void) {
        let previous = probeChain
        probeChain = Task {
            await previous.value
            await work()
        }
    }

    private func healthClock() async {
        var previous = controls().healthFresh
        while !Task.isCancelled {
            let fresh = controls().healthFresh
            if fresh != previous {
                previous = fresh
                dialGeneration += 1
            }
            let wait = freshnessWait()
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func freshnessWait() -> Double {
        guard let stamp = healthFile?.generatedAtDate else { return 30 }
        let remain = stamp.addingTimeInterval(ReceiverRules.healthMaxAge).timeIntervalSinceNow
        if remain <= 0 { return 30 }
        return min(max(remain + 0.5, 1), 30)
    }

    private func loadChannels(regionId: String, cameras: Bool, key: String, token: Int) async throws -> [Channel] {
        guard let index else { throw ReceiverStoreError.indexNotLoaded }
        let raw = try await rawChannels(regionId: regionId, cameras: cameras, key: key, index: index)
        try Task.checkCancellation()
        guard loadToken[key] == token else { return shown(regionId: regionId, cameras: cameras) }
        await refreshControlsIfStale()
        offerings[key] = offerings[key] ?? []
        dialGeneration += 1
        let folded = controls()
        let candidates = ReceiverRules.probeCandidates(raw, controls: folded)
        if folded.healthLoaded && !folded.healthFresh {
            walksFinished.insert(key)
            publishCounts()
            dialGeneration += 1
            return []
        }
        await probe.verify(candidates) { [weak self] id in
            Task { @MainActor in
                self?.reveal(id, key: key, token: token, raw: raw)
            }
        }
        guard loadToken[key] == token else { return shown(regionId: regionId, cameras: cameras) }
        walksFinished.insert(key)
        publishCounts()
        dialGeneration += 1
        return shown(regionId: regionId, cameras: cameras)
    }

    private func reveal(_ id: String, key: String, token: Int, raw: [Channel]) {
        guard loadToken[key] == token, !withdrawn.contains(id) else { return }
        guard let channel = raw.first(where: { $0.id == id }) else { return }
        verified.insert(id)
        guard lists(channel) else { return }
        var rows = offerings[key] ?? []
        guard !rows.contains(where: { $0.id == id }) else { return }
        rows.append(channel)
        rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        offerings[key] = rows
        dialGeneration += 1
    }

    /// Writes the verified totals once, after a walk finishes. It does not probe other regions.
    private func publishCounts() {
        var television = 0, radio = 0, cameras = 0
        var any = false
        for (key, rows) in offerings where walksFinished.contains(key) {
            any = true
            for row in rows where !withdrawn.contains(row.id) && lists(row) {
                switch row.mediaType {
                case "tv": television += 1
                case "radio": radio += 1
                case "camera": cameras += 1
                default: break
                }
            }
        }
        guard any else { return }
        televisionNow = television
        radioNow = radio
        camerasNow = cameras
        liveNow = television + radio + cameras
    }

    private func rawChannels(regionId: String, cameras: Bool, key: String, index: ReceiverIndex) async throws -> [Channel] {
        if let cached = shards[key] { return cached }
        guard let url = cameras ? index.cameraURL(regionId: regionId) : index.shardURL(regionId: regionId) else {
            return []
        }
        let (data, response) = try await urlSession.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ReceiverStoreError.http(code) }
        let shard: RegionShard
        do {
            shard = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(RegionShard.self, from: data)
            }.value
        } catch {
            throw ReceiverStoreError.unreadable
        }
        shards[key] = shard.channels
        return shard.channels
    }

    /// The shape files the map is drawn from. The extended file comes only when asked for. Both are
    /// static, so each is fetched and decoded once and kept; a failed fetch is not kept and is
    /// tried again by the next call.
    func mapShapes(extended: Bool) async throws -> (core: RegionShapes, extended: RegionShapes?) {
        let core: RegionShapes
        if let cached = coreShapes {
            core = cached
        } else {
            core = try await fetchShapes("region-shapes.json")
            coreShapes = core
        }
        guard extended else { return (core, nil) }
        let wide: RegionShapes
        if let cached = extendedShapes {
            wide = cached
        } else {
            wide = try await fetchShapes("region-shapes-extended.json")
            extendedShapes = wide
        }
        return (core, wide)
    }

    /// The native-script name of a region, read from the core shape file. Nil until that file has
    /// been fetched, and when it has no name for the region or the name only repeats the label.
    func nativeName(for regionId: String) -> String? {
        guard let shape = coreShapes?.regions.first(where: { $0.id == regionId }),
              let native = shape.native?.trimmingCharacters(in: .whitespacesAndNewlines), !native.isEmpty,
              native.caseInsensitiveCompare(shape.label.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        else { return nil }
        return native
    }

    private func fetchShapes(_ file: String) async throws -> RegionShapes {
        let (data, response) = try await urlSession.data(from: KJConfig.site.appendingPathComponent("data/\(file)"))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ReceiverStoreError.http(code) }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(RegionShapes.self, from: data)
            }.value
        } catch {
            throw ReceiverStoreError.unreadable
        }
    }

    /// The carrier URL for a channel's live stream, asked for at the moment of tuning. The
    /// feeds are looked at again first: a channel that was listed a minute ago may be withdrawn.
    func resolve(_ channel: Channel) async throws -> URL {
        await refreshControlsIfStale()
        guard lists(channel), let stream = channel.activeStream else {
            throw ReceiverStoreError.notOnDial
        }
        let (data, response) = try await urlSession.data(from: ReceiverRules.carrierURL(streamID: stream.id))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ReceiverStoreError.http(code) }
        do {
            return try ReceiverRules.carrier(from: data)
        } catch {
            throw ReceiverStoreError.unplayable
        }
    }

    /// Denylist, off-air list and health, fetched together. Any of the three may fail and
    /// is then treated as absent; the clock only starts once at least one has answered.
    private func refreshControlsIfStale() async {
        if let at = controlsFetchedAt, Date().timeIntervalSince(at) < Self.staleAfter { return }
        let session = urlSession
        let denylistURL = Self.dataURL("denylist.json")
        let offAirURL = Self.dataURL("off-air-suspects.json")
        let healthURL = Self.dataURL("health.json")
        async let denylist: Denylist? = Self.fetchOptional(Denylist.self, from: denylistURL, using: session)
        async let offAir: OffAir? = Self.fetchOptional(OffAir.self, from: offAirURL, using: session)
        async let health: Health? = Self.fetchOptional(Health.self, from: healthURL, using: session)
        let (denied, suspects, graded) = await (denylist, offAir, health)
        denylistFile = denied
        offAirFile = suspects
        healthFile = graded
        if denied != nil || suspects != nil || graded != nil { controlsFetchedAt = Date() }
        dialGeneration += 1
    }

    private nonisolated static func fetchOptional<T: Decodable & Sendable>(
        _ type: T.Type, from url: URL, using session: URLSession
    ) async -> T? {
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
