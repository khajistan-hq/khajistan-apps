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

    @ObservationIgnored private var extendedShapes: RegionShapes?
    @ObservationIgnored private var controls = Controls.empty
    @ObservationIgnored private var controlsFetchedAt: Date?
    @ObservationIgnored private var indexFetchedAt: Date?
    @ObservationIgnored private var shards: [String: [Channel]] = [:]
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

    func loadIndex() async {
        guard !isLoading else { return }
        if index != nil, let at = indexFetchedAt, Date().timeIntervalSince(at) < Self.staleAfter { return }
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

    /// The channels of one region that the receiver may offer. `cameras` picks the camera
    /// shard instead of the television and radio one.
    func channels(regionId: String, cameras: Bool) async throws -> [Channel] {
        guard let index else { throw ReceiverStoreError.indexNotLoaded }
        let key = cameras ? regionId + "-camera" : regionId
        let raw: [Channel]
        if let cached = shards[key] {
            raw = cached
        } else {
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
            raw = shard.channels
            shards[key] = raw
        }
        await refreshControlsIfStale()
        return ReceiverRules.eligible(raw, controls: controls)
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
        guard ReceiverRules.eligible([channel], controls: controls).first != nil,
              let stream = channel.activeStream else {
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
        controls = Controls(denylist: denied, offAir: suspects, health: graded)
        if denied != nil || suspects != nil || graded != nil { controlsFetchedAt = Date() }
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
