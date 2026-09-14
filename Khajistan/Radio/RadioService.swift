import Foundation

actor RadioService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    enum Failure: LocalizedError {
        case response(Int), unavailable, insecureStream
        var errorDescription: String? {
            switch self {
            case .response(let code): "The receiver returned HTTP \(code). Please try again."
            case .unavailable: "This station is currently unavailable on the receiver."
            case .insecureStream: "This station does not provide an HTTPS stream for native playback. Use the web receiver to check its availability."
            }
        }
    }
    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let url = URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(type, from: data)
    }
    func catalogue() async throws -> [RadioChannel] {
        async let feed = fetch(ReceiverFeed.self, path: "/data/open-frequencies/receiver.json")
        async let denied = fetch(DeniedFeed.self, path: "/data/open-frequencies/denylist.json")
        async let offAir = fetch(OffAirFeed.self, path: "/data/open-frequencies/off-air-suspects.json")
        async let health = fetch(HealthFeed.self, path: "/data/open-frequencies/health.json")
        return try await RadioCatalogue.available(feed: feed, denied: denied, offAir: offAir, health: health)
    }
    func resolve(_ channel: RadioChannel) async throws -> URL {
        // Read the current safety feeds on every tune; a previously displayed row can be withdrawn.
        guard let current = try await catalogue().first(where: { $0.id == channel.id }), let stream = current.stream else { throw Failure.unavailable }
        struct Carrier: Decodable { let url: URL }
        let (data, response) = try await session.data(from: RadioCatalogue.carrierURL(streamID: stream.id))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw Failure.unavailable }
        let url = try JSONDecoder().decode(Carrier.self, from: data).url
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw Failure.insecureStream }
        return url
    }
}
