import Foundation
import Observation

enum AuthStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Sign-in is unavailable right now." }
}

/// The viewer's sign-in and the preview password, both kept in the keychain.
@MainActor @Observable
final class AuthStore {
    private(set) var session: Session? {
        didSet { if oldValue?.userId != session?.userId { invalidateAccess() } }
    }
    private(set) var accessGeneration = 0
    @ObservationIgnored private var authOperation = 0
    @ObservationIgnored private var accessObservers: [UUID: @MainActor () -> Void] = [:]
    func observeAccess(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID(); accessObservers[id] = observer; return id
    }
    func removeAccessObserver(_ id: UUID) { accessObservers.removeValue(forKey: id) }
    private func invalidateAccess() {
        accessGeneration += 1
        for observer in Array(accessObservers.values) { observer() }
    }
    private(set) var previewPassword: String?

    private let urlSession: URLSession

    /// Set after a sign-in when the account has a verified authenticator: the session is kept, and
    /// the six-digit code is still owed before staff films play (vod-token wants aal2).
    private(set) var pendingFactorId: String?

    func verifyCode(_ typed: String) async throws {
        guard let factorId = pendingFactorId else { throw AuthError.server("Sign in again.") }
        _ = try await validAccessToken()
        guard let current = session else { throw AuthError.server("Sign in again.") }
        let fresh = try await AuthAPI.verify(typed, factorId: factorId, session: current, using: urlSession)
        session = fresh
        persist(fresh)
        pendingFactorId = nil
    }

    /// Asked outside the caller's task, so leaving the sign-in screen mid-lookup cannot cancel it
    /// into "no code owed".
    private func lookUpFactor(_ fresh: Session) async {
        let urlSession = urlSession
        let owed = await Task { await AuthAPI.factorOwed(by: fresh, using: urlSession) }.value
        // Signed out, or into another account, while it was asked: the answer is not this session's.
        guard session?.userId == fresh.userId else { return }
        pendingFactorId = owed
    }

    /// A stored aal1 session (a relaunch mid-step, Not now, or a launch that was offline) asks
    /// again for its code. Also run when a film is refused, so the refusal says the right thing.
    func rearmCode() async {
        guard session?.assurance == "aal1", (try? await validAccessToken()) != nil, let current = session else { return }
        await lookUpFactor(current)
    }

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private enum Account {
        static let session = "session"
        static let preview = "preview"
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)

        #if DEBUG
        // UI tests leave real keychain credentials untouched and cannot obtain a billing token.
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { return }
        #endif
        if let data = Keychain.read(Account.session),
           let stored = try? JSONDecoder().decode(Session.self, from: data) {
            session = stored
            Task { await rearmCode() }
        }
        if let data = Keychain.read(Account.preview),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            previewPassword = text
        }
    }

    func signIn(email: String, password: String) async throws {
        authOperation += 1
        let operation = authOperation
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { throw AuthStoreError.unavailable }
        #endif
        let (data, response) = try await urlSession.data(for: AuthAPI.passwordRequest(email: email, password: password))
        guard operation == authOperation else { throw AuthStoreError.unavailable }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            throw AuthError.server(AuthAPI.errorMessage(from: data) ?? "Sign-in failed (HTTP \(code)).")
        }
        let fresh = try AuthAPI.session(from: data, now: Date())
        if session?.userId == fresh.userId { invalidateAccess() }
        session = fresh
        persist(fresh)
        await lookUpFactor(fresh)
    }

    /// Signs out here first, then tells the server. A failed request changes nothing for the viewer.
    /// The preview password goes too, as on the Apple TV: a Mac or iPad can be shared (owner,
    /// 2026-11-14). A refused refresh keeps it; only a chosen sign-out clears it.
    func signOut() async {
        let token = session?.accessToken
        clearSession()
        clearPreviewPassword()
        guard let token else { return }
        _ = try? await urlSession.data(for: AuthAPI.logoutRequest(accessToken: token))
    }

    /// A token that is good now: the stored one, or a refreshed one. When the refresh fails
    /// the session is dropped, because a refresh token is not worth keeping once refused.
    func validAccessToken() async throws -> String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { throw AuthStoreError.unavailable }
        #endif
        guard let current = session else {
            throw AuthError.server("Sign in to watch Khajistan TV.")
        }
        if !current.isExpired(at: Date()) { return current.accessToken }
        // One refresh at a time: every caller waits on the same request. Parallel refreshes sent
        // the one refresh token several times; the losers failed, and a refusal that came back
        // first signed the viewer out. A cancelled caller still waits for the shared request
        // (25 s at most); every caller checks cancellation or a generation after it.
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await refresh(current) }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    @ObservationIgnored private var refreshTask: Task<String, Error>?

    private func refresh(_ current: Session) async throws -> String {
        // A network failure or a server fault leaves the session in place for the next try;
        // only a refusal of the refresh token ends it.
        let access = accessGeneration
        let operation = authOperation
        let (data, response) = try await urlSession.data(for: AuthAPI.refreshRequest(refreshToken: current.refreshToken))
        guard access == accessGeneration, operation == authOperation, session == current else { throw AuthStoreError.unavailable }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A server fault, a rate limit or a timeout is not a refusal: the session stays.
        if code >= 500 || code == 429 || code == 408 { throw AuthStoreError.unavailable }
        guard code < 400, let fresh = try? AuthAPI.session(from: data, now: Date()) else {
            clearSession()
            throw AuthError.server("Sign in again.")
        }
        guard fresh.userId == current.userId else { throw AuthStoreError.unavailable }
        session = fresh
        persist(fresh)
        return fresh.accessToken
    }

    /// An empty password clears it.
    func setPreviewPassword(_ password: String) {
        guard !password.isEmpty else {
            clearPreviewPassword()
            return
        }
        previewPassword = password
        _ = try? Keychain.write(Data(password.utf8), account: Account.preview)
    }

    func clearPreviewPassword() {
        previewPassword = nil
        Keychain.delete(Account.preview)
    }

    private func persist(_ fresh: Session) {
        guard let data = try? JSONEncoder().encode(fresh) else { return }
        _ = try? Keychain.write(data, account: Account.session)
    }

    private func clearSession() {
        authOperation += 1
        session = nil
        pendingFactorId = nil
        Keychain.delete(Account.session)
    }
}
