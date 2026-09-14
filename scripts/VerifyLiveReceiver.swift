import Foundation

@main struct VerifyLiveReceiver {
    static func main() async throws {
        let service = RadioService()
        let channels = try await service.catalogue()
        guard !channels.isEmpty else { throw URLError(.cannotParseResponse) }
        print("Live receiver: \(channels.count) eligible radio stations decoded")
        let selected = channels.filter { $0.country == "Pakistan" }.prefix(3)
        guard selected.count == 3 else { throw URLError(.cannotParseResponse) }
        for channel in selected {
            let url = try await service.resolve(channel)
            var request = URLRequest(url: url)
            request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
            request.timeoutInterval = 15
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            var count = 0
            for try await _ in bytes { count += 1; if count == 512 { break } }
            guard count > 0 else { throw URLError(.zeroByteResource) }
            print("PASS \(channel.name): resolver + HTTPS stream bytes (\(http.statusCode))")
        }
    }
}
