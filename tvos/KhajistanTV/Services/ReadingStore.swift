import Foundation
import Observation
import UIKit

/// What a card on the shelf, or an issue's cover, has so far: its picture and, for a title, the access
/// line the page server gave an anonymous visitor.
@MainActor @Observable
final class RRCardState {
    fileprivate(set) var image: UIImage?
    fileprivate(set) var access: RRAccess?
    /// The cover could not be had. A card says nothing about it; the plate stays.
    fileprivate(set) var failed = false
    @ObservationIgnored fileprivate var requested = false
}

/// What one page of the reader turned out to be.
enum RRPageResult {
    case image(UIImage)
    case outcome(RRPageOutcome)
}

/// The Reading Room's data: the shelf the website draws, grouped as the website groups it, and the
/// page server's answers. Read-only throughout: every request is a GET, or a POST that only asks a
/// question (the catalogue RPC, rr_issue_pages, and the page server's signing of an address).
@MainActor @Observable
final class ReadingStore {
    enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var titles: [RRTitle] = []
    private(set) var tabs: [RRTab] = []
    private(set) var rights: Set<String> = []
    private(set) var provenance: [String: RRProvenanceRow] = [:]

    @ObservationIgnored private var cards: [String: RRCardState] = [:]
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var flushing = false
    /// Slugs a four-digit retry has proved (signedUrl() :130).
    @ObservationIgnored private var pad4: Set<String> = []
    @ObservationIgnored private var warned: [String: [String: [String]]] = [:]
    @ObservationIgnored private let pages = NSCache<NSString, UIImage>()

    private unowned let auth: AuthStore
    private let urlSession: URLSession
    private let origin: URL

    private struct Job {
        let key: String
        let cover: String
        let probe: String?
        let state: RRCardState
        /// The title the probe was drawn for, so a later page can be asked for when this one is not on the shelf.
        let title: RRTitle?
    }

    init(auth: AuthStore, origin: URL) {
        self.auth = auth
        self.origin = origin
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config)
        // A page decodes to tens of megabytes; the current one, the next and the one behind.
        pages.countLimit = 3
    }

    /// The preview gate's header when a password is held and the origin is the site.
    private var authorization: String? {
        guard origin == KJConfig.site, let password = auth.previewPassword else { return nil }
        return Transmission.basicAuthorization(user: KJConfig.previewUser, password: password)
    }

    // MARK: - The shelf

    /// Loads the shelf. Safe to call on every appearance: a shelf already open is left alone.
    func start() async {
        switch phase {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        phase = .loading
        async let feed = loadFeed()
        async let rightsHeld = loadRights()
        async let index = loadModules()
        async let ranks = loadProvenance()
        guard let collections = await feed, !collections.isEmpty else {
            phase = .failed("The Reading Room did not answer.")
            return
        }
        // Rights first and awaited, as the site does: the room's figures must not count what the reader cannot open.
        rights = await rightsHeld
        let built = RRCatalogue.titles(from: collections)
        titles = built
        // Ranked before the first paint, so a shelf never reorders under the viewer.
        provenance = await ranks
        tabs = RRRank.ranked(RRShelves.tabs(titles: built, index: await index, rights: rights), provenance: provenance)
        phase = .ready
    }

    func retry() async {
        if case .failed = phase { await start() }
    }

    /// The feed, a thousand rows a page and retried: a bare call returned 1,000 of 1,036 rows once and called it success.
    private func loadFeed() async -> [RRCollection]? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(600 * Int(pow(3.0, Double(attempt - 1))))) }
            var all: [RRCollection] = []
            var failed = false
            for pageNo in 0..<64 {
                guard let rows = await fetch(RRAPI.catalogueRequest(offset: pageNo * RRAPI.feedPage), decode: RRAPI.titles(fromFeed:)) else {
                    failed = true
                    break
                }
                all.append(contentsOf: rows)
                // A short page is the only honest end of the data.
                if rows.count < RRAPI.feedPage { break }
            }
            if !failed { return all }
        }
        return nil
    }

    private func loadRights() async -> Set<String> {
        await fetch(RRAPI.rightsRequest(), decode: RRAPI.slugs(fromRights:)) ?? []
    }

    /// data/rr-modules.json. Without the preview password the site answers 401 and the room is one tab of every title.
    private func loadModules() async -> RRModuleIndex? {
        var request = URLRequest(url: RRSite.modulesURL(origin: origin))
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return RRModuleIndex.parse(data)
    }

    private func loadProvenance() async -> [String: RRProvenanceRow] {
        var all: [String: RRProvenanceRow] = [:]
        for pageNo in 0..<16 {
            guard let rows = await fetch(RRAPI.provenanceRequest(offset: pageNo * RRAPI.feedPage), decode: RRProvenance.rows(from:)) else { break }
            for row in rows { all[row.collection_slug] = row }
            if rows.count < RRAPI.feedPage { break }
        }
        return all
    }

    private func fetch<T>(_ request: URLRequest, decode: (Data) -> T?) async -> T? {
        guard let (data, response) = try? await urlSession.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return nil }
        return decode(data)
    }

    // MARK: - A title's custodian

    /// The distinct custodian lines of every member collection, in member order (:6632-6645).
    func provenanceLines(for title: RRTitle) -> [String] {
        var seen = Set<String>()
        return title.memberSlugs.compactMap { provenance[$0]?.provenance_source }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func isKhajistanScanned(_ title: RRTitle) -> Bool {
        title.memberSlugs.contains { slug in provenance[slug].map(RRProvenance.isKhajistanScan) ?? false }
    }

    func isRights(_ title: RRTitle) -> Bool { rights.contains(title.slug) }

    // MARK: - Covers and access lines

    /// The state a title's card reads. The card asks for its cover with `want`.
    func card(for title: RRTitle) -> RRCardState { state("t|" + title.slug) }

    func issueCard(_ title: RRTitle, _ issue: RRIssue) -> RRCardState { state("i|" + title.slug + "|" + issue.key) }

    private func state(_ key: String) -> RRCardState {
        if let held = cards[key] { return held }
        let made = RRCardState()
        cards[key] = made
        return made
    }

    /// A title's cover and its access line, asked for once.
    func want(_ title: RRTitle) {
        let state = card(for: title)
        guard !state.requested, let cover = RRPath.coverEndpoint(title, extra: pad4) else { return }
        state.requested = true
        queue.append(Job(key: title.slug, cover: cover, probe: RRPath.probeEndpoint(title, extra: pad4), state: state, title: title))
        scheduleFlush()
    }

    /// An issue's cover in the title view.
    func want(_ title: RRTitle, issue: RRIssue) {
        let state = issueCard(title, issue)
        guard !state.requested else { return }
        state.requested = true
        queue.append(Job(key: issue.key, cover: RRPath.issueCoverEndpoint(title, issue, extra: pad4), probe: nil, state: state, title: nil))
        scheduleFlush()
    }

    /// Wanted covers go out together: one call answers up to 32 titles (a cover and a probe each).
    private func scheduleFlush() {
        guard !flushing else { return }
        flushing = true
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            flushing = false
            while !queue.isEmpty {
                let batch = Array(queue.prefix(RRAPI.batchLimit / 2))
                queue.removeFirst(batch.count)
                await run(batch)
            }
        }
    }

    private func run(_ batch: [Job]) async {
        // Public answers: a cover is free to everyone, and the access line is what an anonymous visitor is told.
        var paths: [String] = []
        for job in batch {
            paths.append(job.cover)
            if let probe = job.probe { paths.append(probe) }
        }
        guard let answers = await signBatch(paths, token: nil) else {
            for job in batch { job.state.failed = true }
            return
        }
        // A three-digit page that is not found may be a four-digit object: one retry, then the slug is remembered.
        var twins: [String] = []
        for job in batch where answers[job.cover]?.status == 404 {
            if let twin = RRPath.fourDigitTwin(of: job.cover) { twins.append(twin.path) }
        }
        var twinAnswers: [String: RRPageAnswer] = [:]
        if !twins.isEmpty { twinAnswers = await signBatch(twins, token: nil) ?? [:] }
        var unresolved: [(state: RRCardState, title: RRTitle)] = []
        for job in batch {
            var cover = answers[job.cover]
            if let twin = RRPath.fourDigitTwin(of: job.cover), let answer = twinAnswers[twin.path], answer.status == 200 {
                pad4.insert(twin.slug)
                cover = answer
            }
            job.state.access = job.probe.flatMap { RRAccess.classify(answers[$0]) }
            if job.state.access == nil, job.probe != nil, let title = job.title, answers[job.probe!]?.status == 404 {
                unresolved.append((job.state, title))
            }
            guard let cover, case .page(let url) = RRPageOutcome.decide(cover) else {
                job.state.failed = true
                continue
            }
            let state = job.state
            Task {
                state.image = await PnvImages.shared.image([url], maxPixel: 720)
                if state.image == nil { state.failed = true }
            }
        }
        if !unresolved.isEmpty { await probeLater(unresolved) }
    }

    /// A probe page the shelf does not hold (404 comes before any gate) says nothing about access: the next
    /// pages are asked for, a few rounds, each only for the titles still unanswered.
    private func probeLater(_ pending: [(state: RRCardState, title: RRTitle)]) async {
        var pending = pending
        for skipping in 1...3 {
            let asks = pending.compactMap { item in RRPath.probeEndpoint(item.title, skipping: skipping, extra: pad4).map { (item, $0) } }
            guard !asks.isEmpty, let answers = await signBatch(asks.map(\.1), token: nil) else { return }
            pending = []
            for (item, path) in asks {
                if let access = RRAccess.classify(answers[path]) {
                    item.state.access = access
                } else if answers[path]?.status == 404 {
                    pending.append(item)
                }
            }
            if pending.isEmpty { return }
        }
    }

    private func signBatch(_ paths: [String], token: String?) async -> [String: RRPageAnswer]? {
        guard let (data, response) = try? await urlSession.data(for: RRAPI.batchRequest(paths: paths, size: "sm", accessToken: token)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return RRPageAnswer.parseBatch(data)
    }

    /// What the shelf says about a title's access: rights first (a legal refusal, not a tier), then the server's answer.
    func access(for title: RRTitle) -> RRAccess? {
        if isRights(title) { return .rightsPending }
        return card(for: title).access
    }

    // MARK: - The reader

    /// The live page numbers of an issue, and the page count they leave (rrLoadPageMap).
    func pageMap(_ issue: RRIssue) async -> (pages: Int, map: [Int]?) {
        let prefix = RRPath.issuePrefix(issue, extra: pad4)
        let numbers = await fetch(RRAPI.pageNumbersRequest(prefix: prefix), decode: RRAPI.pageNumbers(from:))
        return RRPageMap.resolve(numbers, declared: issue.pages)
    }

    /// Pages that carry a content warning, endpoint to flags. Asked once per collection; a failure means no curtain (:7822).
    func warnings(for slug: String) async -> [String: [String]] {
        if let held = warned[slug] { return held }
        warned[slug] = [:]
        let found = await fetch(RRAPI.sensitiveRequest(collection: slug), decode: { RRSensitive.flags(from: $0) }) ?? [:]
        warned[slug] = found
        return found
    }

    func endpoint(_ issue: RRIssue, page: Int) -> String {
        RRPath.endpoint(issue, page: page, extra: pad4)
    }

    /// One page at reading size. The viewer's own token goes with the request when there is one; the
    /// function decides, and its answer is what comes back.
    func page(_ issue: RRIssue, stored: Int) async -> RRPageResult {
        let token = try? await auth.validAccessToken()
        let path = endpoint(issue, page: stored)
        let key = (path + (token == nil ? "|p" : "|a")) as NSString
        if let held = pages.object(forKey: key) { return .image(held) }
        var answer = await sign(path, token: token)
        if answer?.status == 404, let twin = RRPath.fourDigitTwin(of: path), let retry = await sign(twin.path, token: token), retry.status == 200 {
            pad4.insert(twin.slug)
            answer = retry
        }
        guard let answer else { return .outcome(.unavailable) }
        switch RRPageOutcome.decide(answer) {
        case .page(let url):
            guard let image = await download(url) else { return .outcome(.unavailable) }
            pages.setObject(image, forKey: key)
            return .image(image)
        case let other:
            return .outcome(other)
        }
    }

    /// Warms the next page: signed and fetched into the cache, nothing shown.
    func prefetch(_ issue: RRIssue, stored: Int) async {
        _ = await page(issue, stored: stored)
    }

    private func sign(_ path: String, token: String?) async -> RRPageAnswer? {
        guard let (data, response) = try? await urlSession.data(for: RRAPI.pageRequest(path: path, size: "full", accessToken: token)),
              let code = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return RRPageAnswer.parse(status: code, body: data)
    }

    /// A page is shrunk to what the screen can use at 2x: 4096 on its long side.
    private func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await urlSession.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return await Task.detached(priority: .userInitiated) { PnvImages.downsample(data, maxPixel: 4096) }.value
    }
}
