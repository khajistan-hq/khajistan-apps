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
    /// Bumped when health ages out, so a channel that was playing stops until a new probe.
    private(set) var playbackEpoch = 0

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
    /// Bumped when health goes from fresh to stale, so a walk that started earlier cannot reveal.
    @ObservationIgnored private var probeEpoch = 0
    /// When a failed health fetch may be tried again. It is not the ten-minute clock.
    @ObservationIgnored private var healthRetryAt: Date?
    @ObservationIgnored private let probe = ReceiverProbe()
    private let urlSession: URLSession

    /// How long a fetched index is trusted before the next look. Health uses `ReceiverRules.controlHold`.
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
    func channels(regionId: String, cameras: Bool, bypassProbeCache: Bool = false) async throws -> [Channel] {
        let key = cameras ? regionId + "-camera" : regionId
        if let existing = channelLoads[key] { return try await existing.value }
        let token = (loadToken[key] ?? 0) + 1
        loadToken[key] = token
        let task = Task { try await self.loadChannels(regionId: regionId, cameras: cameras, key: key, token: token, bypassProbeCache: bypassProbeCache) }
        channelLoads[key] = task
        defer { if channelLoads[key] == task { channelLoads[key] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            _ = Task { @MainActor in
                if self.loadToken[key] == token { self.loadToken[key] = token + 1 }
            }
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
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjnoprobe") { return }
        #endif
        guard clockTask == nil else { return }
        clockTask = Task { await self.healthClock() }
    }

    /// True when this channel may be shown, including a liked or saved one.
    func lists(_ channel: Channel) -> Bool {
        _ = dialGeneration
        guard !withdrawn.contains(channel.id) else { return false }
        return ReceiverRules.eligible([channel], controls: controls(), verified: verified, allowWithoutHealth: probesOff).first != nil
    }

    /// Debug launches pass `-kjnoprobe`. Release builds compile this as false.
    private var probesOff: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "kjnoprobe")
        #else
        false
        #endif
    }

    /// The channel failed to play. It leaves the dial until a later probe succeeds.
    func withdraw(_ id: String) {
        withdrawn.insert(id)
        verified.remove(id)
        offerings = offerings.mapValues { $0.filter { $0.id != id } }
        dialGeneration += 1
        enqueueProbe { await self.probe.remember(id, live: false) }
        publishCounts()
    }

    /// Clears the failure so a new probe may run. Does not mark the row verified.
    /// The forget waits its turn on the probe queue, so a remember already queued cannot land after it.
    func restore(_ id: String) async {
        withdrawn.remove(id)
        verified.remove(id)
        await enqueueProbe { await self.probe.forget(id) }.value
    }

    /// Probes one channel the viewer asked for again. True only when that probe says it is live
    /// and the probe epoch is still the one captured before the probe. A stale flip in the
    /// middle drops the result instead of inserting it.
    func confirm(_ channel: Channel) async -> Bool {
        await refreshControlsIfStale()
        await restore(channel.id)
        guard ReceiverRules.probeCandidates([channel], controls: controls()).first != nil else { return false }
        let epoch = probeEpoch
        let live = await probe.verify([channel], bypassCache: true).live
        guard ReceiverRules.confirmStillCurrent(capturedEpoch: epoch, epochNow: probeEpoch) else { return false }
        guard !Task.isCancelled, live.contains(channel.id), !withdrawn.contains(channel.id) else { return false }
        guard ReceiverRules.confirmStillCurrent(capturedEpoch: epoch, epochNow: probeEpoch) else { return false }
        verified.insert(channel.id)
        dialGeneration += 1
        guard ReceiverRules.confirmStillCurrent(capturedEpoch: epoch, epochNow: probeEpoch) else {
            verified.remove(channel.id)
            return false
        }
        return lists(channel)
    }

    /// Verified rows of `medium` already on the dial for this region. Does not start a probe.
    func verifiedChannels(regionId: String, medium: String) -> [Channel] {
        shown(regionId: regionId, cameras: medium == "camera").filter { $0.mediaType == medium }
    }

    private func controls(now: Date = Date()) -> Controls {
        // UI tests launch with `-kjnoprobe`. The live health file is often older than two hours,
        // and a stale file would blank the dial before any row could be shown. The grades still apply.
        Controls(denylist: denylistFile, offAir: offAirFile, health: healthFile, now: now, treatAsFresh: probesOff)
    }

    @discardableResult
    private func enqueueProbe(_ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = probeChain
        let task = Task {
            await previous.value
            await work()
        }
        probeChain = task
        return task
    }

    private func healthClock() async {
        var previous = controls().healthFresh
        while !Task.isCancelled {
            let fresh = controls().healthFresh
            if ReceiverRules.clearSessionAfterFreshnessFlip(wasFresh: previous, isFresh: fresh) {
                clearSession()
            }
            if fresh != previous {
                previous = fresh
                publishCounts()
                dialGeneration += 1
            }
            let wait = freshnessWait()
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    /// Fresh health has aged out. Nothing verified under it may stay, and the next fresh file
    /// has to be probed again before a row can show.
    private func clearSession() {
        let open = ReceiverRules.regionsToReprobe(Set(offerings.keys).union(walksFinished))
        probeEpoch += 1
        verified = []
        offerings = [:]
        walksFinished = []
        televisionNow = nil
        radioNow = nil
        camerasNow = nil
        liveNow = nil
        playbackEpoch += 1
        for key in open {
            channelLoads[key]?.cancel()
            channelLoads[key] = nil
            loadToken[key] = (loadToken[key] ?? 0) + 1
        }
        probe.dropMemory()
        for key in open {
            let cameras = key.hasSuffix("-camera")
            let regionId = cameras ? String(key.dropLast("-camera".count)) : key
            Task { _ = try? await self.channels(regionId: regionId, cameras: cameras, bypassProbeCache: true) }
        }
    }

    /// Verified rows for one region once its walks have finished. Nil until then, so the chip
    /// shows the loading mark instead of the index total.
    func regionLiveCount(regionId: String) -> Int? {
        _ = dialGeneration
        guard walkFinished(regionId: regionId, cameras: false) else { return nil }
        let cameras = index?.cameraURL(regionId: regionId) != nil
        if cameras && !walkFinished(regionId: regionId, cameras: true) { return nil }
        return shown(regionId: regionId, cameras: false).count
            + (cameras ? shown(regionId: regionId, cameras: true).count : 0)
    }

    private func freshnessWait() -> Double {
        guard let stamp = healthFile?.generatedAtDate else { return 30 }
        let remain = stamp.addingTimeInterval(ReceiverRules.healthMaxAge).timeIntervalSinceNow
        if remain <= 0 { return 30 }
        return min(max(remain + 0.5, 1), 30)
    }

    private func loadChannels(regionId: String, cameras: Bool, key: String, token: Int, bypassProbeCache: Bool = false) async throws -> [Channel] {
        guard let index else { throw ReceiverStoreError.indexNotLoaded }
        let epoch = probeEpoch
        let raw = try await rawChannels(regionId: regionId, cameras: cameras, key: key, index: index)
        try Task.checkCancellation()
        guard loadToken[key] == token, probeEpoch == epoch else { return shown(regionId: regionId, cameras: cameras) }
        await refreshControlsIfStale()
        guard probeEpoch == epoch else { return shown(regionId: regionId, cameras: cameras) }
        offerings[key] = offerings[key] ?? []
        dialGeneration += 1
        let folded = controls()
        let candidates = ReceiverRules.probeCandidates(raw, controls: folded, allowWithoutHealth: probesOff)
        if !probesOff && (!folded.healthLoaded || !folded.healthFresh) {
            guard probeEpoch == epoch else { return shown(regionId: regionId, cameras: cameras) }
            walksFinished.insert(key)
            publishCounts()
            dialGeneration += 1
            return []
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjnoprobe") {
            for channel in candidates where !withdrawn.contains(channel.id) {
                reveal(channel.id, key: key, token: token, raw: raw, epoch: epoch)
            }
            guard !Task.isCancelled, loadToken[key] == token, probeEpoch == epoch else { return shown(regionId: regionId, cameras: cameras) }
            walksFinished.insert(key)
            publishCounts()
            dialGeneration += 1
            return shown(regionId: regionId, cameras: cameras)
        }
        #endif
        let report = await probe.verify(candidates, bypassCache: bypassProbeCache) { [weak self] id in
            await self?.reveal(id, key: key, token: token, raw: raw, epoch: epoch)
        }
        guard !Task.isCancelled, loadToken[key] == token, probeEpoch == epoch else { return shown(regionId: regionId, cameras: cameras) }
        if ReceiverRules.mayMarkWalkFinished(unprobed: report.unprobed.count) {
            walksFinished.insert(key)
            publishCounts()
        }
        dialGeneration += 1
        return shown(regionId: regionId, cameras: cameras)
    }

    private func reveal(_ id: String, key: String, token: Int, raw: [Channel], epoch: Int) {
        guard probeEpoch == epoch, loadToken[key] == token, !withdrawn.contains(id) else { return }
        guard let channel = raw.first(where: { $0.id == id }) else { return }
        guard ReceiverRules.probeCandidates([channel], controls: controls(), allowWithoutHealth: probesOff).first != nil else { return }
        verified.insert(id)
        guard lists(channel) else {
            verified.remove(id)
            return
        }
        var rows = offerings[key] ?? []
        guard !rows.contains(where: { $0.id == id }) else { return }
        rows.append(channel)
        rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        offerings[key] = rows
        dialGeneration += 1
    }

    /// Each medium is published only after a walk of that medium has finished.
    /// A zero is withheld while another walk of that medium is still running, so the figure
    /// never reads 0 from a walk that has not finished.
    private func publishCounts() {
        var television = 0
        var radio = 0
        var cameras = 0
        var sawBroadcast = false
        var sawCameras = false
        for (key, rows) in offerings where ReceiverRules.countsTowardFigure(key: key, finished: walksFinished) {
            let listed = rows.filter { !withdrawn.contains($0.id) && lists($0) }
            if key.hasSuffix("-camera") {
                sawCameras = true
                cameras += listed.filter { $0.mediaType == "camera" }.count
            } else {
                sawBroadcast = true
                television += listed.filter { $0.mediaType == "tv" }.count
                radio += listed.filter { $0.mediaType == "radio" }.count
            }
        }
        let broadcastPending = channelLoads.keys.contains { !$0.hasSuffix("-camera") && !walksFinished.contains($0) }
        let camerasPending = channelLoads.keys.contains { $0.hasSuffix("-camera") && !walksFinished.contains($0) }
        if sawBroadcast {
            televisionNow = (television == 0 && broadcastPending) ? nil : television
            radioNow = (radio == 0 && broadcastPending) ? nil : radio
        }
        if sawCameras {
            camerasNow = (cameras == 0 && camerasPending) ? nil : cameras
        }
        let known = [televisionNow, radioNow, camerasNow].compactMap { $0 }
        liveNow = known.isEmpty ? nil : known.reduce(0, +)
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
        let fresh: URL
        do {
            fresh = try ReceiverRules.carrier(from: data)
        } catch {
            throw ReceiverStoreError.unplayable
        }
        // Debug launches do not probe. A release play opens only the carrier whose renditions passed.
        if probesOff { return fresh }
        return try await playbackURL(for: channel, fresh: fresh)
    }

    /// The remembered carrier when it still matches. A verified id whose URL has aged out of
    /// the ten-minute verdict is probed again. That miss does not withdraw the row: the caller
    /// withdraws on throw, and an expired entry alone does not throw.
    private func playbackURL(for channel: Channel, fresh: URL) async throws -> URL {
        let remembered = probe.playback(for: channel.id)
        switch ReceiverRules.CarrierMemory(verified: verified.contains(channel.id), playback: remembered).tune(fresh) {
        case .play:
            return fresh
        case .refuse:
            throw ReceiverStoreError.notOnDial
        case .reprobe:
            let epoch = probeEpoch
            let live = await probe.verify([channel], bypassCache: true).live
            guard ReceiverRules.confirmStillCurrent(capturedEpoch: epoch, epochNow: probeEpoch),
                  live.contains(channel.id),
                  let probed = probe.playback(for: channel.id),
                  ReceiverRules.playbackMatches(probed: probed, fresh: fresh) else {
                throw ReceiverStoreError.notOnDial
            }
            return fresh
        }
    }

    /// Denylist, off-air list and health, fetched together. A failed health fetch keeps the
    /// previous file, which then ages out on its own stamp. The ten-minute clock starts only
    /// when health arrives. The other two files do not start it, and a miss is tried again shortly.
    private func refreshControlsIfStale() async {
        let now = Date()
        if case .skip = ReceiverRules.controlRefresh(now: now, clock: controlsFetchedAt, retryAt: healthRetryAt, healthArrived: true) {
            return
        }
        let session = urlSession
        let denylistURL = Self.dataURL("denylist.json")
        let offAirURL = Self.dataURL("off-air-suspects.json")
        let healthURL = Self.dataURL("health.json")
        async let denylist: Denylist? = Self.fetchOptional(Denylist.self, from: denylistURL, using: session)
        async let offAir: OffAir? = Self.fetchOptional(OffAir.self, from: offAirURL, using: session)
        async let health: Health? = Self.fetchOptional(Health.self, from: healthURL, using: session)
        let (denied, suspects, graded) = await (denylist, offAir, health)
        denylistFile = ReceiverRules.keptFeed(denied, previous: denylistFile)
        offAirFile = ReceiverRules.keptFeed(suspects, previous: offAirFile)
        switch ReceiverRules.controlRefresh(now: now, clock: nil, retryAt: nil, healthArrived: graded != nil) {
        case .replace:
            healthFile = graded
            controlsFetchedAt = now
            healthRetryAt = nil
        case .keep(let retryAfter):
            healthRetryAt = now.addingTimeInterval(retryAfter)
        case .skip:
            break
        }
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
