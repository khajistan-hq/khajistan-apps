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

    @ObservationIgnored private var extendedShapes: RegionShapes?
    @ObservationIgnored private var controls = Controls.empty
    @ObservationIgnored private var controlsFetchedAt: Date?
    @ObservationIgnored private var indexFetchedAt: Date?
    @ObservationIgnored private var shards: [String: [Channel]] = [:]
    /// Why the whole dial is not on screen though a preview password is saved. Nil otherwise.
    private(set) var signInNote: String?
    /// Moves whenever the dial on hand changes kind (whole or public). The Receiver is drawn
    /// afresh on it, so no shelf keeps a list read from the other one.
    private(set) var dialID = 0
    @ObservationIgnored private var wholeDial = false
    /// The whole dial was on hand at some point since the last password change, so a channel
    /// still playing may be one the public dial does not carry, even after a refresh fell back.
    @ObservationIgnored private var servedWhole = false
    /// Players open over the Receiver. A dial change found by a refresh waits until none is, so
    /// a channel being watched is not closed by the redraw.
    @ObservationIgnored private var playersOpen = 0
    @ObservationIgnored private var redrawWaiting = false
    /// Which dial the Receiver on screen was drawn from.
    @ObservationIgnored private var drawnWhole = false
    @ObservationIgnored private var indexFailedAt: Date?
    /// The preview password the dial on hand was read for, and the one the site refused, which is
    /// not sent again until it changes (ten wrong passwords lock the site's sign-in for everyone
    /// on this network for ten minutes).
    @ObservationIgnored private var dialPassword: String?
    @ObservationIgnored private var refused: String?
    /// Moves on every password change. A fetch begun under an older one does not keep its answer,
    /// so a list read before sign-in is never kept after it, nor the other way.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loading: (password: String?, task: Task<Void, Never>)?
    @ObservationIgnored private var retry: Task<Void, Never>?
    private let urlSession: URLSession
    /// The preview password, read when the index loads.
    private let previewPassword: @MainActor () -> String?

    /// How long a fetched index or set of feeds is trusted before the next look.
    private static let staleAfter: TimeInterval = 600

    /// The site serves the whole dial only to a request that carries its password cookie, and
    /// the confirmed broadcaster streams alone to every other (owner, 2026-11-16; _worker.js
    /// holdsSitePassword). With a preview password set, the index is asked for through the site's
    /// own sign-in, POST /gate, which sets that cookie in this session for every later request.
    init(previewPassword: @escaping @MainActor () -> String? = { nil }) {
        self.previewPassword = previewPassword
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config.answeringFromFixtures())
    }

    private nonisolated static func dataURL(_ file: String) -> URL {
        KJConfig.site.appendingPathComponent("data/open-frequencies/\(file)")
    }

    /// Reads the index if the one on hand is stale or was read for another password. A second
    /// call while one is under way for the same password waits on it.
    func loadIndex() async {
        let password = previewPassword()
        if password != dialPassword {
            credentialDidChange()
            dialPassword = password
        }
        if let loading, loading.password == password {
            await loading.task.value
            return
        }
        if index != nil, let at = indexFetchedAt, Date().timeIntervalSince(at) < Self.staleAfter { return }
        let started = generation
        let task = Task { await self.fetchIndex(password: password, generation: started) }
        loading = (password, task)
        await task.value
        if loading?.task == task { loading = nil }
    }

    /// With a password, the index is read through the site's sign-in on every refresh (at most
    /// once in `staleAfter`), so a changed site password or an expired cookie is noticed within
    /// minutes. The site counts only failed sign-ins against its lock.
    private func fetchIndex(password: String?, generation: Int) async {
        var started = generation
        // A sign-in cancelled by a sign-out may still have stored its cookie.
        if password == nil { deleteSiteCookies() }
        if index == nil { indexError = nil }
        // Kept outside the read below: a throttled sign-in is tried again even when the public
        // fallback read fails too.
        var retry = false
        do {
            var reply: (Data, URLResponse)?
            var note: String?
            var whole = false
            if let password, password != refused {
                let outcome = await gate(password)
                // A sign-in answered after the password changed belongs to the old password: its
                // refusal must not delete the cookie the new password's sign-in has stored.
                guard started == self.generation, !Task.isCancelled else { return }
                switch outcome {
                case .signedIn(let answer):
                    reply = answer
                    whole = true
                case .refused:
                    refused = password
                    deleteSiteCookies()
                    note = Self.refusedNote
                    // The whole dial on hand can no longer be opened: it goes now, so a failed
                    // public read below cannot leave its channels listed.
                    if wholeDial {
                        dialKindChanged(to: false)
                        index = nil
                        indexFetchedAt = nil
                        started = self.generation
                    }
                    signInNote = note
                case .tryLater:
                    // The cookie from an earlier sign-in, if any, still opens the whole dial.
                    whole = wholeDial && hasSiteCookie
                    retry = true
                    if !whole { note = "Not every channel could be opened just now. Trying again in a minute." }
                }
            } else if password != nil {
                note = Self.refusedNote
            }
            if reply == nil {
                // Only a read meant for the whole dial carries the site cookie. A sign-in cancelled
                // by a sign-out can store its cookie after every delete; this read never sends it.
                reply = try await urlSession.data(for: dialRequest(Self.dataURL("receiver-index.json"), whole: whole))
            }
            guard let reply else { throw ReceiverStoreError.unreadable }
            let (data, response) = reply
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
            guard started == self.generation, !Task.isCancelled else { return }
            if whole { servedWhole = true }
            if whole != wholeDial { dialKindChanged(to: whole) }
            index = decoded
            indexError = nil
            signInNote = note
            indexFetchedAt = Date()
            shards.removeAll()
            indexFailedAt = nil
            if retry { scheduleRetry(generation: self.generation) }
        } catch {
            if Task.isCancelled || started != self.generation { return }
            if retry { scheduleRetry(generation: self.generation) }
            indexFailedAt = Date()
            // A list already on screen stays; only a missing list is an error to show.
            if index == nil { indexError = error.localizedDescription }
        }
    }

    /// The dial on hand changes kind (whole or public). Region downloads and a feeds read under
    /// way came from the other dial, so the generation moves and none of them is kept. The redraw
    /// is a separate matter: it waits while a player is open over the Receiver.
    private func dialKindChanged(to whole: Bool) {
        wholeDial = whole
        generation += 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        shards.removeAll()
        if playersOpen > 0 { redrawWaiting = whole != drawnWhole } else { redraw() }
        controls = .empty
        controlsFetchedAt = nil
    }

    private static let refusedNote = "The preview password did not open every channel. Check it under Account."
    private static let retryAfter: Duration = .seconds(60)

    /// A sign-in that was throttled or did not answer is tried again in a minute, whether or not
    /// anything on screen asks. One retry waits at a time.
    private func scheduleRetry(generation started: Int) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryAfter)
            guard !Task.isCancelled, let self, started == self.generation else { return }
            self.indexFetchedAt = nil
            await self.loadIndex()
        }
    }

    /// Every Receiver read but the sign-in goes through here. The site splits the index, the
    /// region shards, the withdrawal feeds and the carrier lookup by its password cookie
    /// (_worker.js DIAL_FILES, ID_FEEDS, /api/frequency), so a read sends and stores the cookie
    /// only while the whole dial is on hand: a sign-in cancelled by Clear can store its cookie
    /// after every delete, and no public read then carries it.
    private func dialRequest(_ url: URL, whole: Bool? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = whole ?? wholeDial
        return request
    }

    private func deleteSiteCookies() {
        let storage = urlSession.configuration.httpCookieStorage
        storage?.cookies(for: KJConfig.site)?.forEach { storage?.deleteCookie($0) }
    }

    private enum Gate { case signedIn((Data, URLResponse)), refused, tryLater }

    /// Signs in with the preview password. POST /gate redirects to `next` with the cookie set,
    /// so on success the redirect is the whole dial's index.
    private func gate(_ password: String) async -> Gate {
        var request = URLRequest(url: KJConfig.site.appendingPathComponent("gate"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let indexPath = Self.dataURL("receiver-index.json").path
        let field = { (value: String) in value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
        request.httpBody = Data("password=\(field(password))&next=\(field(indexPath))".utf8)
        guard let reply = try? await urlSession.data(for: request) else { return .tryLater }
        switch ReceiverRules.gateOutcome(status: (reply.1 as? HTTPURLResponse)?.statusCode ?? 0,
                                         landedOn: reply.1.url?.path, next: indexPath, cookieSet: hasSiteCookie) {
        case .signedIn: return .signedIn(reply)
        case .refused: return .refused
        case .tryLater: return .tryLater
        }
    }

    private var hasSiteCookie: Bool {
        urlSession.configuration.httpCookieStorage?.cookies(for: KJConfig.site)?.contains { $0.name == "kj_gate" } == true
    }

    /// A new or removed preview password: the site cookie goes, the dial on hand goes (so every
    /// shelf is drawn again from the new one), and nothing fetched before this is kept.
    /// Returns whether the whole dial was on hand since the last change, so a channel still
    /// playing from it can be turned off.
    @discardableResult
    func credentialDidChange() -> Bool {
        let wasWhole = servedWhole
        servedWhole = false
        // A new password is sent once; one the site refused before is tried again only when
        // entered again.
        refused = nil
        deleteSiteCookies()
        generation += 1
        wholeDial = false
        indexFailedAt = nil
        // Nothing is open over the Receiver while the password changes; a count a player never
        // gave back must not hold a later redraw.
        playersOpen = 0
        redraw()
        loading?.task.cancel()
        loading = nil
        retry?.cancel()
        retry = nil
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        index = nil
        indexFetchedAt = nil
        signInNote = nil
        controls = .empty
        controlsFetchedAt = nil
        shards.removeAll()
        return wasWhole
    }

    /// A list or a tune asked for before the index was read for the current password waits for
    /// that read, so its own request carries the cookie (or none) the new dial was read with. A
    /// routine refresh with a dial on hand is not waited for.
    private func settleDial() async {
        let failedRecently = indexFailedAt.map { Date().timeIntervalSince($0) < 30 } ?? false
        if previewPassword() != dialPassword || (index == nil && !failedRecently) { await loadIndex() }
    }

    func playerDidOpen() { playersOpen += 1 }

    func playerDidClose() {
        playersOpen = max(0, playersOpen - 1)
        if playersOpen == 0, redrawWaiting { redraw() }
    }

    private func redraw() {
        redrawWaiting = false
        drawnWhole = wholeDial
        dialID += 1
    }

    /// The channels of one region that the receiver may offer. `cameras` picks the camera
    /// shard instead of the television and radio one.
    /// Region downloads under way, by shard key, so a second ask waits on the first.
    @ObservationIgnored private var inFlight: [String: Task<[Channel], Error>] = [:]

    func channels(regionId: String, cameras: Bool) async throws -> [Channel] {
        await settleDial()
        guard let index else { throw ReceiverStoreError.indexNotLoaded }
        let started = generation
        let key = cameras ? regionId + "-camera" : regionId
        let raw: [Channel]
        if let cached = shards[key] {
            raw = cached
        } else if let pending = inFlight[key] {
            // The guide's prefetch and a turn can ask for the same region at once: one download.
            raw = try await pending.value
        } else {
            guard let url = cameras ? index.cameraURL(regionId: regionId) : index.shardURL(regionId: regionId) else {
                return []
            }
            let session = urlSession
            let request = dialRequest(url)
            let load = Task { () throws -> [Channel] in
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw ReceiverStoreError.http(code) }
                do {
                    return try await Task.detached(priority: .userInitiated) {
                        try JSONDecoder().decode(RegionShard.self, from: data)
                    }.value.channels
                } catch {
                    throw ReceiverStoreError.unreadable
                }
            }
            inFlight[key] = load
            defer { if inFlight[key] == load { inFlight[key] = nil } }
            raw = try await load.value
            guard started == generation else { throw CancellationError() }
            shards[key] = raw
        }
        await refreshControlsIfStale()
        // A list read for the dial before a password change or a dial change is not handed out
        // after it, whether it came from the cache, a shared download or this one.
        guard started == generation else { throw CancellationError() }
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
        let (data, response) = try await urlSession.data(for: dialRequest(KJConfig.site.appendingPathComponent("data/\(file)")))
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
        await settleDial()
        await refreshControlsIfStale()
        guard ReceiverRules.eligible([channel], controls: controls).first != nil,
              let stream = channel.activeStream else {
            throw ReceiverStoreError.notOnDial
        }
        #if DEBUG
        // `-kjdeadchannels a,b` makes those channels fail as a dead signal does, so moving on
        // from one can be seen in the simulator, where a really dead channel is hard to find.
        if UserDefaults.standard.string(forKey: "kjdeadchannels")?.split(separator: ",").contains(Substring(channel.id)) == true {
            throw ReceiverStoreError.unplayable
        }
        #endif
        #if DEBUG
        if let fixture = try KJFixtureProtocol.mediaURL(for: channel.mediaType) { return fixture }
        #endif
        let (data, response) = try await urlSession.data(for: dialRequest(ReceiverRules.carrierURL(streamID: stream.id)))
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
        async let denylist: Denylist? = Self.fetchOptional(Denylist.self, from: dialRequest(denylistURL), using: session)
        async let offAir: OffAir? = Self.fetchOptional(OffAir.self, from: dialRequest(offAirURL), using: session)
        async let health: Health? = Self.fetchOptional(Health.self, from: dialRequest(healthURL), using: session)
        let started = generation
        let (denied, suspects, graded) = await (denylist, offAir, health)
        guard !Task.isCancelled, started == generation else { return }
        // A stale health file is ignored as a missing one is: it would withdraw channels on old news.
        let fresh = graded.flatMap { $0.isFresh(at: Date()) ? $0 : nil }
        controls = Controls(denylist: denied, offAir: suspects, health: fresh)
        if denied != nil || suspects != nil || graded != nil { controlsFetchedAt = Date() }
    }

    private nonisolated static func fetchOptional<T: Decodable & Sendable>(
        _ type: T.Type, from request: URLRequest, using session: URLSession
    ) async -> T? {
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
