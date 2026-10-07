import Foundation
import os
import Observation

/// Why a Pics/Vids video could not start.
enum PnvPlaybackError: LocalizedError {
    /// A Khajistan TV row: tv-play wants a signed-in account, as it does on the Transmission page.
    case needsSignIn
    case unavailable

    var errorDescription: String? {
        switch self {
        case .needsSignIn: return "Sign in to watch Khajistan Transmission."
        case .unavailable: return "This video could not load."
        }
    }
}

/// One region's shelf: its own stream, paged on its own.
struct PnvFeed: Equatable {
    var items: [PnvRow] = []
    /// The exact count for the current kind filter, once the first page has said.
    var total: Int?
    var isDone = false
    var isLoading = false
    var error: String?
    var offset = 0
    var seen = Set<String>()

    /// True before the first page has been asked for.
    var isUntouched: Bool { offset == 0 && !isLoading && !isDone && error == nil }
}

/// The Born Digital stream, read as /browse-archive.html reads it (see Core/PicsVids.swift): the
/// roster of vetted accounts first, then pages of `pnv_media` for those accounts only. The page is
/// one shelf per region the roster carries, each with its own paging (`feeds`); the kind filter
/// is the page's own and applies to every shelf, and picking one starts every shelf over.
@MainActor @Observable
final class PicsVidsStore {
    enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Region tokens that have accounts, west to east.
    private(set) var regions: [String] = []
    private(set) var summary: String?
    /// Each region's shelf, by region token. A shelf with no entry has not been asked for.
    private(set) var feeds: [String: PnvFeed] = [:]
    private(set) var kind: PnvKind?
    private(set) var noticeVisible = false

    @ObservationIgnored private var roster: [PnvAccount] = []
    @ObservationIgnored private var accountsByKey: [String: PnvAccount] = [:]
    @ObservationIgnored private var generation = 0
    /// "ok" for this launch only, the session store of the site's notice. Never again is the
    /// device store: UserDefaults under the same key.
    @ObservationIgnored private var sessionAck: String?
    private unowned let auth: AuthStore
    private let urlSession: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config)
    }

    // MARK: - Opening

    /// Loads the roster and the first page. Safe to call on every appearance: a page already open is left alone.
    func start() async {
        switch phase {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            roster = try await fetch([PnvAccount].self, PnvAPI.accountsRequest())
        } catch {
            if Task.isCancelled { phase = .idle; return }
            Logger(subsystem: "com.khajistan.tv", category: "picsvids").error("roster, first try: \(String(describing: error), privacy: .public)")
            // One quiet second try: a cold launch sometimes loses the first request, and the page
            // should not open on an error the viewer then has to clear (QA, 2026-10-06).
            try? await Task.sleep(for: .seconds(1))
            do {
                roster = try await fetch([PnvAccount].self, PnvAPI.accountsRequest())
            } catch {
                if Task.isCancelled { phase = .idle; return }
                phase = .failed("The archive did not answer.")
                return
            }
        }
        accountsByKey = Dictionary(roster.map { ($0.account_key, $0) }, uniquingKeysWith: { first, _ in first })
        regions = PnvRegions.ordered(Set(PnvRegions.accountKeysByRegion(roster).keys))
        summary = PnvAPI.summary(roster: roster, facets: nil)
        noticeVisible = await shouldShowNotice()
        phase = .ready
        // The counts are a nicety; the stream stands without them. Each shelf asks for its own
        // first page when it comes on screen (`loadMore(region:)`).
        Task { [weak self] in await self?.loadFacets() }
    }

    private func loadFacets() async {
        guard let facets = try? await fetch(PnvFacets.self, PnvAPI.facetsRequest()) else { return }
        summary = PnvAPI.summary(roster: roster, facets: facets)
    }

    // MARK: - Filters

    /// Starts every shelf over under the new kind. The shelves on screen ask for their first
    /// pages again themselves.
    func select(kind: PnvKind?) {
        guard kind != self.kind else { return }
        self.kind = kind
        generation += 1
        feeds = [:]
    }

    func feed(_ region: String) -> PnvFeed {
        feeds[region] ?? PnvFeed()
    }

    /// Clears a shelf's error so it asks again.
    func retry() async {
        if case .failed = phase { await start() }
    }

    func retry(region: String) async {
        feeds[region]?.error = nil
        await loadMore(region: region)
    }

    // MARK: - Paging

    /// The key of the one feed that spans every region. The Apple TV app never asks for it; the
    /// phone's single grid does, under its "All" filter (ios/, which compiles this file).
    static let allRegions = ""

    /// The next page of one region's shelf: the first when it has none yet. Safe to call as often
    /// as focus nears the end; a page in flight or a finished shelf is left alone.
    func loadMore(region: String) async {
        guard phase == .ready else { return }
        var feed = feeds[region] ?? PnvFeed()
        guard !feed.isLoading, !feed.isDone, feed.error == nil else { return }
        let gen = generation
        // No roster, or a region nobody is filed under: nothing to ask for.
        guard let keys = PnvAPI.accountKeys(roster: roster, region: region == Self.allRegions ? nil : region) else {
            feed.isDone = true
            feeds[region] = feed
            return
        }
        feed.isLoading = true
        feeds[region] = feed
        let request = PnvAPI.pageRequest(keys: keys, kind: kind, offset: feed.offset, wantCount: feed.total == nil)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard gen == generation else { return }
            let http = response as? HTTPURLResponse
            guard let code = http?.statusCode, (200..<300).contains(code) else { throw ReceiverStoreError.http(http?.statusCode ?? 0) }
            let rows = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode([PnvRow].self, from: data)
            }.value
            guard gen == generation else { return }
            var next = feeds[region] ?? PnvFeed()
            if let counted = PnvAPI.total(fromContentRange: http?.value(forHTTPHeaderField: "Content-Range")) { next.total = counted }
            for row in rows where next.seen.insert(row.media_key).inserted { next.items.append(row) }
            next.offset += rows.count
            if rows.count < PnvAPI.pageSize { next.isDone = true }
            next.isLoading = false
            feeds[region] = next
        } catch {
            guard gen == generation, !Task.isCancelled else {
                // A cancelled request leaves the shelf free to ask again.
                if gen == generation { feeds[region]?.isLoading = false }
                return
            }
            feeds[region]?.isLoading = false
            feeds[region]?.error = "The archive did not answer."
        }
    }

    // MARK: - A row

    /// The region token a row files under, through its account.
    func regionToken(for row: PnvRow) -> String? {
        row.account_key.flatMap { accountsByKey[$0] }.flatMap { PnvRegions.fold($0.region_token) }
    }

    func accountHandle(for row: PnvRow) -> String {
        let account = row.account_key.flatMap { accountsByKey[$0] }
        return account?.slug ?? row.account ?? row.account_key ?? ""
    }

    func caption(for row: PnvRow) async -> String? {
        guard let request = PnvAPI.captionRequest(for: row),
              let (data, _) = try? await urlSession.data(for: request) else { return nil }
        return PnvAPI.caption(from: data)
    }

    /// The address to play. A Khajistan TV row goes through tv-play with the viewer's session, as
    /// the Transmission page does; every other row is a plain file.
    func playableURL(for row: PnvRow) async throws -> URL {
        guard let full = PnvMedia.full(row) else { throw PnvPlaybackError.unavailable }
        guard row.isKtv else { return full }
        guard auth.isSignedIn else { throw PnvPlaybackError.needsSignIn }
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch is AuthError {
            throw PnvPlaybackError.needsSignIn
        }
        let viewer = auth.session?.userId
        guard let route = Transmission.route(for: full.absoluteString),
              let request = Transmission.request(for: route, accessToken: token) else { throw PnvPlaybackError.unavailable }
        // A signer that redirects is refused, as the website's fetch does.
        let (data, response) = try await urlSession.data(for: request, delegate: RefuseRedirects())
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw PnvPlaybackError.needsSignIn }
        guard let url = try? Transmission.carrier(from: data, route: route) else { throw PnvPlaybackError.unavailable }
        // An answer is used only if the same viewer is still signed in when it arrives.
        guard viewer != nil, auth.session?.userId == viewer else { throw PnvPlaybackError.needsSignIn }
        return url
    }

    // MARK: - The adult notice

    private func shouldShowNotice() async -> Bool {
        let stored = UserDefaults.standard.string(forKey: AdultNotice.key)
        // The site's pages ask the account first: one that has confirmed 18+ never sees it.
        let confirmed = auth.isSignedIn ? await accountConfirmedAdult() : false
        return AdultNotice.shouldShow(stored: stored, session: sessionAck, confirmed18: confirmed)
    }

    private struct ProfileRow: Decodable { let nsfw_age_confirmed: Bool? }

    private func accountConfirmedAdult() async -> Bool {
        guard let token = try? await auth.validAccessToken(), let userId = auth.session?.userId,
              var request = PnvAPI.profileRequest(userId: userId, accessToken: token) else { return false }
        request.timeoutInterval = 6
        guard let (data, _) = try? await urlSession.data(for: request),
              let rows = try? JSONDecoder().decode([ProfileRow].self, from: data) else { return false }
        return rows.first?.nsfw_age_confirmed == true
    }

    /// "OK" is not again this launch; with "Don't ask again" it is never again on this device.
    func dismissNotice(dontAskAgain: Bool) {
        if dontAskAgain {
            UserDefaults.standard.set("dismissed", forKey: AdultNotice.key)
        } else {
            sessionAck = "ok"
        }
        noticeVisible = false
    }

    // MARK: - Fetching

    private func fetch<T: Decodable & Sendable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ReceiverStoreError.http(code) }
        return try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(T.self, from: data) }.value
    }
}
