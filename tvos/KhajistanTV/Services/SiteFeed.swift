import Foundation
import Observation

/// Where the site's own data files are read from. `-kjsite http://127.0.0.1:8831` points a debug
/// build at a local checkout of the site (scripts/dev_server.py), for tests and screenshots; only
/// a loopback address is accepted, and release builds always read the site.
enum SiteOrigin {
    static var current: URL {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "kjsite"), let url = URL(string: text),
           let host = url.host, ["127.0.0.1", "localhost"].contains(host) {
            return url
        }
        #endif
        return KJConfig.site
    }
}

/// One of the site's data files (a catalogue, an index, a dictionary), read the way the website
/// reads it. Until launch most of them sit behind the site password: with the preview password
/// set on this device they are read with it, and without it the answer is `locked`, never an
/// empty room. A failed read keeps whatever was already held on screen.
@MainActor @Observable
final class SiteFeed<Value: Sendable> {
    enum State: Equatable {
        case idle, loading, ready, locked
        case failed(String)
    }

    private(set) var value: Value?
    private(set) var state: State = .idle
    /// The files read together; the answer is `locked` if any of them is behind the password.
    let paths: [String]
    let origin: URL

    @ObservationIgnored private let decode: @Sendable ([Data]) throws -> Value
    @ObservationIgnored private unowned let auth: AuthStore
    @ObservationIgnored private let urlSession: URLSession
    /// The password the held answer was read with, so a new password reads again.
    @ObservationIgnored private var loadedWith: String??

    convenience init(auth: AuthStore, path: String, origin: URL = SiteOrigin.current, decode: @escaping @Sendable (Data) throws -> Value) {
        self.init(auth: auth, paths: [path], origin: origin) { files in try decode(files[0]) }
    }

    init(auth: AuthStore, paths: [String], origin: URL = SiteOrigin.current, decode: @escaping @Sendable ([Data]) throws -> Value) {
        self.auth = auth
        self.paths = paths
        self.origin = origin
        self.decode = decode
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    func url(_ path: String) -> URL { origin.appendingPathComponent(path) }

    /// The preview gate's header, when a password is held and the origin is the site itself.
    var authorization: String? {
        guard origin == KJConfig.site, let password = auth.previewPassword else { return nil }
        return Transmission.basicAuthorization(user: KJConfig.previewUser, password: password)
    }

    /// Reads the file once per preview password. Safe to call again; `force` reads again anyway.
    func load(force: Bool = false) async {
        let password = auth.previewPassword
        if state == .loading { return }
        if !force, state == .ready || state == .locked, loadedWith == .some(password) { return }
        state = .loading
        do {
            var files: [Data] = []
            for path in paths {
                var request = URLRequest(url: url(path))
                if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
                let (data, response) = try await urlSession.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 401 {
                    loadedWith = .some(password)
                    value = nil
                    state = .locked
                    return
                }
                guard code == 200 else { throw SiteFeedError.status(code) }
                files.append(data)
            }
            loadedWith = .some(password)
            let decode = self.decode
            value = try await Task.detached(priority: .userInitiated) { try decode(files) }.value
            state = .ready
        } catch {
            loadedWith = nil
            state = value == nil ? .failed(SiteFeedError.describe(error)) : .ready
        }
    }
}

enum SiteFeedError: Error {
    case status(Int)

    static func describe(_ error: Error) -> String {
        switch error {
        case SiteFeedError.status(let code): return "The archive answered \(code). Try again in a moment."
        case is DecodingError: return "The archive's file could not be read."
        default: return "The archive did not answer. Check the connection and try again."
        }
    }
}
