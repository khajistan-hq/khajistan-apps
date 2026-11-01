import Foundation
import Observation

enum AuthStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Sign-in is unavailable right now." }
}

/// The viewer's sign-in and the preview password, both kept in the keychain.
@MainActor @Observable
final class AuthStore {
    private(set) var session: Session?
    private(set) var previewPassword: String?
    /// Changes on sign-in/sign-out, including returning to the same account.
    private(set) var accessGeneration = UUID()
    @ObservationIgnored private var operation = UUID()
    @ObservationIgnored private var refresh: (id: UUID, task: Task<Session, Error>)?

    private let urlSession: URLSession

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private enum Account {
        static let session = "session"
        static let preview = "preview"
    }

    init(urlSession: URLSession? = nil, loadStoredSession: Bool = true) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        self.urlSession = urlSession ?? URLSession(configuration: config)

        #if DEBUG
        // UI tests leave real keychain credentials untouched and cannot obtain a billing token.
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { return }
        #endif
        if loadStoredSession, let data = Keychain.read(Account.session),
           let stored = try? JSONDecoder().decode(Session.self, from: data) {
            session = stored
        }
        OfflineFilmAccountScope.shared.restore(session?.userId)
        if loadStoredSession, let data = Keychain.read(Account.preview),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            previewPassword = text
        }
    }

    func signIn(email: String, password: String) async throws {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { throw AuthStoreError.unavailable }
        #endif
        let attempt = beginOperation()
        let (data, response) = try await urlSession.data(for: AuthAPI.passwordRequest(email: email, password: password))
        guard attempt == operation else { throw CancellationError() }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            throw AuthError.server(AuthAPI.errorMessage(from: data) ?? "Sign-in failed (HTTP \(code)).")
        }
        let fresh = try AuthAPI.session(from: data, now: Date())
        replaceSession(fresh)
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
    /// only an explicit refresh refusal drops the session; transient failures preserve it.
    func validAccessToken() async throws -> String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtestsignedout") { throw AuthStoreError.unavailable }
        #endif
        guard let current = session else {
            throw AuthError.server("Sign in to watch Khajistan TV.")
        }
        if !current.isExpired(at: Date()) { return current.accessToken }
        if let refresh { return try await refresh.task.value.accessToken }
        let attempt = operation, id = UUID()
        let task = Task<Session, Error> { [self] in
            defer { if refresh?.id == id { refresh = nil } }
            let (data, response) = try await urlSession.data(for: AuthAPI.refreshRequest(refreshToken: current.refreshToken))
            // Neither an old success nor an old refusal can overwrite a newer login/logout.
            guard attempt == operation, session?.userId == current.userId else { throw CancellationError() }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 500 || code == 429 || code == 408 { throw AuthStoreError.unavailable }
            if code == 400 || code == 401 || code == 403 {
                clearSession()
                throw AuthError.server("Sign in again.")
            }
            guard (200..<300).contains(code), let fresh = try? AuthAPI.session(from: data, now: Date()),
                  fresh.userId == current.userId else { throw AuthStoreError.unavailable }
            session = fresh
            persist(fresh)
            return fresh
        }
        refresh = (id, task)
        return try await task.value.accessToken
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

    @discardableResult
    private func beginOperation() -> UUID {
        operation = UUID()
        refresh?.task.cancel()
        refresh = nil
        return operation
    }

    private func replaceSession(_ fresh: Session) {
        accessGeneration = UUID()
        OfflineFilmAccountScope.shared.change(to: fresh.userId)
        session = fresh
    }

    private func clearSession() {
        beginOperation()
        accessGeneration = UUID()
        OfflineFilmAccountScope.shared.change(to: nil)
        session = nil
        Keychain.delete(Account.session)
    }
}
