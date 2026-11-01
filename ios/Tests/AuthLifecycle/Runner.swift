import Foundation

final class ControlledProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var pending: [ControlledProtocol] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Task { @MainActor in Self.pending.append(self) } }
    override func stopLoading() {} // Late provider responses intentionally remain deliverable.
    @MainActor func answer(user: String = "a", expired: Bool = false, status: Int = 200, malformed: Bool = false) {
        let payload: [String: Any] = ["access_token": "token-\(user)-\(UUID())", "refresh_token": "refresh-\(user)",
            "expires_at": Date().timeIntervalSince1970 + (expired ? -60 : 3600),
            "user": ["id": user, "email": "\(user)@example.invalid", "role": "authenticated"]]
        let data = malformed ? Data("not-json".utf8) : try! JSONSerialization.data(withJSONObject: payload)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main struct Runner {
    @MainActor static func next() async -> ControlledProtocol {
        let deadline = Date().addingTimeInterval(3)
        while ControlledProtocol.pending.isEmpty && Date() < deadline { await Task.yield() }
        precondition(!ControlledProtocol.pending.isEmpty, "expected a synthetic request")
        return ControlledProtocol.pending.removeFirst()
    }
    @MainActor static func make() -> AuthStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledProtocol.self]
        return AuthStore(urlSession: URLSession(configuration: config), loadStoredSession: false)
    }
    @MainActor static func signIn(_ store: AuthStore, user: String = "a", expired: Bool = false) async throws {
        let task = Task { try await store.signIn(email: "\(user)@example.invalid", password: "synthetic") }
        await next().answer(user: user, expired: expired)
        try await task.value
    }
    @MainActor static func main() async throws {
        let store = make()
        try await signIn(store, expired: true)
        let initial = store.accessGeneration
        let refresh = Task { try await store.validAccessToken() }
        let delayed = await next()
        let logout = Task { await store.signOut() }
        let logoutRequest = await next()
        precondition(store.session == nil && store.accessGeneration != initial)
        delayed.answer(); logoutRequest.answer()
        _ = try? await refresh.value; await logout.value
        precondition(store.session == nil, "old refresh resurrected sign-out")
        print("PASS: logout survives late refresh")

        let older = Task { try await store.signIn(email: "a@example.invalid", password: "synthetic") }
        let oldRequest = await next()
        try await signIn(store, user: "b")
        let newerGeneration = store.accessGeneration
        oldRequest.answer(user: "a")
        do { try await older.value; fatalError("stale sign-in should fail") } catch {}
        precondition(store.session?.userId == "b" && store.accessGeneration == newerGeneration)
        print("PASS: latest sign-in owns session and persisted credentials")

        try await signIn(store, expired: true)
        let first = Task { try await store.validAccessToken() }
        let request = await next()
        let second = Task { try await store.validAccessToken() }
        for _ in 0..<100 { await Task.yield() }
        precondition(ControlledProtocol.pending.isEmpty, "duplicate refresh request")
        request.answer(user: "a")
        let tokens = try await (first.value, second.value)
        precondition(tokens.0 == tokens.1)
        print("PASS: concurrent page requests share one refresh")

        try await signIn(store, expired: true)
        let transient = Task { try await store.validAccessToken() }
        await next().answer(status: 503)
        _ = try? await transient.value
        precondition(store.session?.userId == "a")
        print("PASS: transient provider outage preserves account")

        for (status, user, malformed) in [(200, "a", true), (200, "unexpected", false), (302, "a", false)] {
            let uncertain = Task { try await store.validAccessToken() }
            await next().answer(user: user, status: status, malformed: malformed)
            _ = try? await uncertain.value
            precondition(store.session?.userId == "a", "malformed response must not destroy offline access")
        }
        print("PASS: malformed, wrong-user and redirect responses preserve account")

        let denied = Task { try await store.validAccessToken() }
        await next().answer(status: 401)
        _ = try? await denied.value
        precondition(store.session == nil)
        print("PASS: explicit refresh refusal clears account")
    }
}
