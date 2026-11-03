import Foundation
import Observation
#if canImport(TVServices)
import TVServices
#endif

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

        if let data = Keychain.read(Account.session),
           let stored = try? JSONDecoder().decode(Session.self, from: data) {
            session = stored
        }
        if let data = Keychain.read(Account.preview),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            previewPassword = text
            // Stored before the Top Shelf could read it: moved into the shared group.
            _ = try? Keychain.write(data, account: Account.preview, shared: true)
        }
    }

    func signIn(email: String, password: String) async throws {
        authOperation += 1
        let operation = authOperation
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
    }

    /// Signs in with the one-time token hash a phone approved for this TV (TVSignIn): the server
    /// answers as it does a password sign-in, and the session is kept the same way.
    func signIn(tokenHash: String) async throws {
        authOperation += 1
        let operation = authOperation
        let (data, response) = try await urlSession.data(for: TVSignIn.verifyRequest(tokenHash: tokenHash))
        guard operation == authOperation else { throw AuthStoreError.unavailable }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            throw AuthError.server(AuthAPI.errorMessage(from: data) ?? "Sign-in failed (HTTP \(code)).")
        }
        let fresh = try AuthAPI.session(from: data, now: Date())
        if session?.userId == fresh.userId { invalidateAccess() }
        session = fresh
        persist(fresh)
    }

    /// Signs out here first, then tells the server. A failed request changes nothing for the viewer.
    func signOut() async {
        let token = session?.accessToken
        clearSession()
        guard let token else { return }
        _ = try? await urlSession.data(for: AuthAPI.logoutRequest(accessToken: token))
    }

    /// A token that is good now: the stored one, or a refreshed one. When the refresh fails
    /// the session is dropped, because a refresh token is not worth keeping once refused.
    func validAccessToken() async throws -> String {
        guard let current = session else {
            throw AuthError.server("Sign in to watch Khajistan TV.")
        }
        if !current.isExpired(at: Date()) { return current.accessToken }
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
        _ = try? Keychain.write(Data(password.utf8), account: Account.preview, shared: true)
        Self.topShelfChanged()
    }

    func clearPreviewPassword() {
        previewPassword = nil
        Keychain.delete(Account.preview)
        Self.topShelfChanged()
    }

    /// The Top Shelf's transmission slides read the preview password, so they are drawn again.
    private static func topShelfChanged() {
        #if canImport(TVServices)
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

    private func persist(_ fresh: Session) {
        guard let data = try? JSONEncoder().encode(fresh) else { return }
        _ = try? Keychain.write(data, account: Account.session)
    }

    private func clearSession() {
        authOperation += 1
        session = nil
        Keychain.delete(Account.session)
    }
}
