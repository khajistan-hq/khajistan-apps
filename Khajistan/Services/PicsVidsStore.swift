import Foundation
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

/// The Born Digital stream, read as /browse-archive.html reads it (see Core/PicsVids.swift): the
/// roster of vetted accounts first, then pages of `pnv_media` for those accounts only. The filters
/// are the page's own, and picking one starts the stream over.
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
    private(set) var items: [PnvRow] = []
    /// The exact count for the current filters, once the first page has said.
    private(set) var total: Int?
    private(set) var isDone = false
    private(set) var isLoadingMore = false
    private(set) var pageError: String?
    private(set) var kind: PnvKind?
    private(set) var region: String?
    private(set) var noticeVisible = false

    @ObservationIgnored private var roster: [PnvAccount] = []
    @ObservationIgnored private var accountsByKey: [String: PnvAccount] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var seen = Set<String>()
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
            phase = .failed("The archive did not answer.")
            return
        }
        accountsByKey = Dictionary(roster.map { ($0.account_key, $0) }, uniquingKeysWith: { first, _ in first })
        regions = PnvRegions.ordered(Set(PnvRegions.accountKeysByRegion(roster).keys))
        summary = PnvAPI.summary(roster: roster, facets: nil)
        noticeVisible = await shouldShowNotice()
        phase = .ready
        // The counts are a nicety; the stream stands without them.
        Task { [weak self] in await self?.loadFacets() }
        await reload()
    }

    private func loadFacets() async {
        guard let facets = try? await fetch(PnvFacets.self, PnvAPI.facetsRequest()) else { return }
        summary = PnvAPI.summary(roster: roster, facets: facets)
    }

    // MARK: - Filters

    func select(kind: PnvKind?) async {
        guard kind != self.kind else { return }
        self.kind = kind
        await reload()
    }

    func select(region: String?) async {
        guard region != self.region else { return }
        self.region = region
        await reload()
    }

    private func reload() async {
        generation += 1
        items = []
        seen = []
        total = nil
        offset = 0
        isDone = false
        isLoadingMore = false
        pageError = nil
        await loadMore()
    }

    func retry() async {
        if case .failed = phase {
            await start()
        } else {
            pageError = nil
            await loadMore()
        }
    }

    // MARK: - Paging

    func loadMore() async {
        guard phase == .ready, !isLoadingMore, !isDone else { return }
        let gen = generation
        // No roster, or a region nobody is filed under: nothing to ask for.
        guard let keys = PnvAPI.accountKeys(roster: roster, region: region) else {
            isDone = true
            return
        }
        isLoadingMore = true
        pageError = nil
        let request = PnvAPI.pageRequest(keys: keys, kind: kind, offset: offset, wantCount: total == nil)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard gen == generation else { return }
            let http = response as? HTTPURLResponse
            guard let code = http?.statusCode, (200..<300).contains(code) else { throw ReceiverStoreError.http(http?.statusCode ?? 0) }
            let rows = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode([PnvRow].self, from: data)
            }.value
            guard gen == generation else { return }
            if let counted = PnvAPI.total(fromContentRange: http?.value(forHTTPHeaderField: "Content-Range")) { total = counted }
            for row in rows where seen.insert(row.media_key).inserted { items.append(row) }
            offset += rows.count
            if rows.count < PnvAPI.pageSize { isDone = true }
            isLoadingMore = false
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            isLoadingMore = false
            pageError = "The archive did not answer."
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
