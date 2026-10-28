import Foundation

/// How the apps reach the database: straight to the project's host, or through the site's `/sb/`
/// proxy where that host cannot be reached. Owner, 2026-10-27: on the owner's home network the Apple
/// TV resolved the host correctly but every connection to its two Cloudflare addresses was dropped,
/// while the site answered in 0.2 s; Reading Room and Pics/Vids spun for 45 s and failed.
///
/// The route is decided by asking both at once and kept for the next launch, so a later launch
/// starts on the way that last worked and checks again behind it. An address the server hands back
/// (a signed page, a stored file) is moved onto the route with `routed(_:)`.
enum SupabaseRoute {
    enum Path: String, Sendable {
        case direct, proxy
        /// Neither answered: the screens say so at once rather than wait out their timeouts.
        case unreachable
    }

    static let host = "qojysegeddztsxdmhjfb.supabase.co"
    #if DEBUG
    /// `-kjsbdirect <url>` and `-kjsbproxy <url>` stand in for the two ways in a debug build, so a
    /// blocked host and a working proxy can be tried on any network.
    static let directBase = URL(string: UserDefaults.standard.string(forKey: "kjsbdirect") ?? "") ?? URL(string: "https://\(host)")!
    static let proxyBase = URL(string: UserDefaults.standard.string(forKey: "kjsbproxy") ?? "") ?? KJConfig.site.appendingPathComponent("sb")
    #else
    static let directBase = URL(string: "https://\(host)")!
    static let proxyBase = KJConfig.site.appendingPathComponent("sb")
    #endif
    /// What a screen says when neither way answers.
    static let unreachableText = "Khajistan can't reach its archive from this network right now. Check the connection, then try again."

    private static let key = "kj.supabaseRoute"
    /// How long either way gets to answer before it counts as unreachable.
    private static let probeLimit: TimeInterval = 2.5
    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen = Path(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .direct
    nonisolated(unsafe) private static var settling: Task<Path, Never>?
    nonisolated(unsafe) private static var decidedAt = Date.distantPast
    /// While neither way answers, how often a request may ask again before it fails at once.
    private static let recheckEvery: TimeInterval = 10

    static var path: Path { lock.withLock { chosen } }
    /// Where requests go now. Unreachable keeps the direct address: a request still fails fast.
    static var base: URL { base(for: path) }

    static func base(for path: Path) -> URL { path == .proxy ? proxyBase : directBase }

    static func routed(_ url: URL) -> URL { routed(url, via: path) }

    /// An address on the route from a path and query that start with "/". Joined as text: resolving
    /// "/rest/…" against the proxy's base would start again from the site's root and lose "/sb".
    static func url(_ pathAndQuery: String) -> URL? { url(pathAndQuery, via: path) }

    static func url(_ pathAndQuery: String, via path: Path) -> URL? {
        URL(string: base(for: path).absoluteString + pathAndQuery)
    }

    /// The same project address on the given route: on the proxy, the site's host with `/sb` before
    /// the path; direct, the project's host. The query is untouched; anything else is left alone.
    static func routed(_ url: URL, via path: Path) -> URL {
        let project = unrouted(url)
        guard path == .proxy, project.host == host,
              var parts = URLComponents(url: project, resolvingAgainstBaseURL: false) else { return project }
        parts.scheme = proxyBase.scheme
        parts.host = proxyBase.host
        parts.port = proxyBase.port
        parts.percentEncodedPath = proxyBase.path + parts.percentEncodedPath
        return parts.url ?? url
    }

    /// A project address as the project names it: one on the proxy (or a debug stand-in) goes back
    /// to the project's own host. Anything else is returned as it is.
    static func unrouted(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let onProxy = url.host == proxyBase.host && url.port == proxyBase.port
            && parts.percentEncodedPath.hasPrefix(proxyBase.path + "/")
        let onStandIn = url.host == directBase.host && url.host != host
        guard onProxy || onStandIn else { return url }
        if onProxy { parts.percentEncodedPath = String(parts.percentEncodedPath.dropFirst(proxyBase.path.count)) }
        parts.scheme = "https"
        parts.host = host
        parts.port = nil
        return parts.url ?? url
    }

    /// The route to start on: the one kept from the last launch, checked again behind it; on a
    /// first launch, the probe's answer (at most `probeLimit`).
    static func ready() async -> Path {
        // Nothing answered last time: ask again now, as the screen opens (at most `probeLimit`).
        if path == .unreachable {
            lock.withLock { settling = nil }
            return await settle()
        }
        if UserDefaults.standard.string(forKey: key) != nil {
            Task.detached(priority: .utility) { _ = await settle() }
            return path
        }
        return await settle()
    }

    /// Asks both ways once per launch; a second caller waits for the same answer.
    @discardableResult
    static func settle() async -> Path {
        let task: Task<Path, Never> = lock.withLock {
            if let settling { return settling }
            let made = Task.detached(priority: .userInitiated) { await decide() }
            settling = made
            return made
        }
        return await task.value
    }

    /// A request on the project could not connect: ask both ways again, and say whether there is now
    /// a working route other than the one that failed, so the caller can try once more on it.
    static func reconsider(after error: Error) async -> Bool {
        guard isUnreachable(error) else { return false }
        let before = path
        lock.withLock { settling = nil }
        let after = await settle()
        return after != before && after != .unreachable
    }

    /// Sends a request on the route: a project address is moved onto it; one that cannot connect
    /// asks both ways again and is sent once more if another way now answers. With no way open,
    /// a project request fails at once instead of waiting out its timeout.
    static func data(for request: URLRequest, session: URLSession, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        var routedRequest = request
        routedRequest.url = request.url.map { routed($0) }
        let onProject = request.url.map(isProject) ?? false
        if onProject, path == .unreachable {
            // Ask again now and then, so the apps come back by themselves when the network does.
            let stale = lock.withLock { Date().timeIntervalSince(decidedAt) > recheckEvery }
            if stale {
                lock.withLock { settling = nil }
                _ = await settle()
            }
            if path == .unreachable { throw URLError(.cannotConnectToHost) }
            routedRequest.url = request.url.map { routed($0) }
        }
        do {
            return try await session.data(for: routedRequest, delegate: delegate)
        } catch {
            guard onProject, await reconsider(after: error) else { throw error }
            routedRequest.url = request.url.map { routed($0) }
            return try await session.data(for: routedRequest, delegate: delegate)
        }
    }

    /// The project's own host, or the proxy's path on the site.
    static func isProject(_ url: URL) -> Bool {
        url.host == host || url.host == directBase.host || (url.host == proxyBase.host && url.path.hasPrefix(proxyBase.path + "/"))
    }

    /// Errors that mean the address could not be reached, as against an answer that came back.
    static func isUnreachable(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.cannotConnectToHost, .timedOut, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
                .secureConnectionFailed].contains(code)
    }

    /// Any answer from the project means it is there; the proxy counts only when it is the proxy that
    /// answered (until the site carries it, `/sb/` is the site's own 404) and it reached the project.
    static func answers(status: Int, routeHeader: String?, viaProxy: Bool) -> Bool {
        guard viaProxy else { return status > 0 }
        return routeHeader == "sb-proxy" && status < 500
    }

    private static func decide() async -> Path {
        async let direct = probe(viaProxy: false)
        async let proxy = probe(viaProxy: true)
        // Direct wins whenever it answers: the proxy is the way round a blocked host, not a preference.
        let result: Path
        if await direct { result = .direct } else { result = await proxy ? .proxy : .unreachable }
        lock.withLock { chosen = result; decidedAt = Date() }
        // Written on the main thread: a change to the defaults is announced on the thread that made
        // it, and the screens that watch them (and @AppStorage) must hear it there.
        if result != .unreachable { await MainActor.run { UserDefaults.standard.set(result.rawValue, forKey: key) } }
        return result
    }

    private static func probe(viaProxy: Bool) async -> Bool {
        var request = URLRequest(url: base(for: viaProxy ? .proxy : .direct).appendingPathComponent("rest/v1/"))
        request.timeoutInterval = probeLimit
        // Only the status matters: no body crosses either way.
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = probeLimit
        config.timeoutIntervalForResource = probeLimit + 0.5
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return answers(status: http.statusCode, routeHeader: http.value(forHTTPHeaderField: "x-kj-route"), viaProxy: viaProxy)
    }
}
