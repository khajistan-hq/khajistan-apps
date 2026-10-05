import Foundation
import Observation

/// The Khajistan Radio mixes: the public register, fetched once and kept, with what may be offered.
@MainActor @Observable
final class MixesStore {
    private(set) var mixes: [Mix] = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    @ObservationIgnored private var fetchedAt: Date?
    private let urlSession: URLSession

    private static let staleAfter: TimeInterval = 600

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    func load() async {
        guard !isLoading else { return }
        if !mixes.isEmpty, let at = fetchedAt, Date().timeIntervalSince(at) < Self.staleAfter { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await urlSession.data(from: Mixes.registerURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw ReceiverStoreError.http(code) }
            let register: MixRegister
            do {
                register = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(MixRegister.self, from: data)
                }.value
            } catch {
                throw ReceiverStoreError.unreadable
            }
            mixes = Mixes.playable(register.mixes)
            loadError = nil
            fetchedAt = Date()
        } catch {
            if Task.isCancelled { return }
            // A list already held stays; only a missing one is an error to show.
            if mixes.isEmpty { loadError = error.localizedDescription }
        }
    }
}
