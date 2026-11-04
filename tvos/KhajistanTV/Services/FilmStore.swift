import Foundation
import Observation

/// The Screening Room's catalogue and the full-film question. vod.json is LAUNCH_RESTRICTED in
/// archive/_worker.js, before launch and after it, so it opens only with the preview password.
/// When it refuses, the public list is asked instead: vod-public.json, the same films reduced
/// to the shelf and the sixty-second preview, which the gate opens when the site launches (owner,
/// 2026-10-29). Before launch both refuse and the room says it is locked. A full film is asked of
/// vod-token by handle either way.
@MainActor @Observable
final class FilmStore {
    enum State: Equatable {
        case idle, loading, ready
        /// vod.json answered 401: no preview password, or a wrong one.
        case locked
        case failed(String)
    }

    private(set) var films: [Film] = []
    private(set) var state: State = .idle
    /// The password the held catalogue was read with, so a new one reloads it.
    @ObservationIgnored private var loadedWith: String??
    private unowned let auth: AuthStore
    private let urlSession: URLSession

    /// Where vod.json and the posters are read from. The website, except in a Debug build started
    /// with `-kjfilms http://127.0.0.1:<port>`: a local server of the archive tree, which is how the
    /// UI tests reach the catalogue without the site password. Nothing but a loopback host is taken.
    let origin: URL

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
        origin = Self.debugOrigin() ?? SiteOrigin.current
    }

    private static func debugOrigin() -> URL? {
        #if DEBUG
        guard let text = UserDefaults.standard.string(forKey: "kjfilms"), let url = URL(string: text),
              let host = url.host, ["127.0.0.1", "localhost"].contains(host) else { return nil }
        return url
        #else
        return nil
        #endif
    }

    /// The preview gate's header when a password is held and the origin is the site.
    var authorization: String? {
        guard origin == KJConfig.site, let password = auth.previewPassword else { return nil }
        return Transmission.basicAuthorization(user: KJConfig.previewUser, password: password)
    }

    /// Films filed to a receiver region, in the catalogue's order.
    func films(in regionId: String, known: Set<String>) -> [Film] {
        films.filter { Films.filedRegion($0.region, known: known) == regionId }
    }

    /// Fetches the catalogue once per preview password. Safe to call again.
    func load() async {
        let password = auth.previewPassword
        if state == .loading { return }
        if state == .ready || state == .locked, loadedWith == .some(password) { return }
        state = .loading
        var request = URLRequest(url: Films.catalogueURL(origin: origin))
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        do {
            var (data, response) = try await urlSession.data(for: request)
            var code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 401 behind the password; 404 if a launched site answers the restricted path so.
            if code == 401 || code == 404 {
                var open = URLRequest(url: Films.publicCatalogueURL(origin: origin))
                if let authorization { open.setValue(authorization, forHTTPHeaderField: "Authorization") }
                (data, response) = try await urlSession.data(for: open)
                code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // Refused (before launch) is locked; anything else that is not 200 is an outage,
                // which fails and is tried again, never read as a wrong password.
                if code == 404 { code = 401 }
            }
            loadedWith = .some(password)
            if code == 401 {
                films = []
                state = .locked
                return
            }
            guard code == 200 else { throw ReceiverStoreError.http(code) }
            let catalogue = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(FilmCatalogue.self, from: data)
            }.value
            films = Films.offered(catalogue.films)
            state = .ready
        } catch {
            loadedWith = nil
            // A catalogue already held stays on screen.
            state = films.isEmpty ? .failed(error.localizedDescription) : .ready
        }
    }

    /// Asks vod-token for the full film, as the site's requestFilmToken does: no session is a 401
    /// without a request, and a network failure is status 0, which reads as a fault.
    func requestFullFilm(_ film: Film) async -> FilmAccess {
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch {
            return .refused(status: error is AuthError ? 401 : 0)
        }
        do {
            let (data, response) = try await urlSession.data(for: Films.tokenRequest(handle: film.handle, accessToken: token),
                                                             delegate: RefuseRedirects())
            return Films.access(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch {
            return .refused(status: 0)
        }
    }
}
