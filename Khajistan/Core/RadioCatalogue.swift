import Foundation

struct RadioChannel: Decodable, Identifiable, Hashable, Sendable {
    struct Stream: Decodable, Hashable, Sendable { let id: String; let format: String }
    let id: String
    let name: String
    let mediaType: String
    let country: String?
    let primaryLanguage: String?
    let streams: [Stream]
    let activeStreamId: String?
    let publicationStatus: String
    let healthStatus: String?
    let manualDisabled: Bool?
    let attributionText: String?

    var stream: Stream? { streams.first { $0.id == activeStreamId } }
    var location: String { [country, primaryLanguage].compactMap { $0 }.filter { !$0.isEmpty && $0 != "Not yet verified" }.joined(separator: " · ") }
}

struct ReceiverFeed: Decodable { let channels: [RadioChannel] }
struct DeniedFeed: Decodable { let disabledChannelIds: [String] }
struct OffAirFeed: Decodable { let offAirChannelIds: [String] }
struct HealthFeed: Decodable {
    struct Result: Decodable { let channelId: String; let status: String; let deliveryRatio: Double? }
    let results: [Result]
}

struct RadioCatalogue {
    static func available(feed: ReceiverFeed, denied: DeniedFeed, offAir: OffAirFeed, health: HealthFeed) -> [RadioChannel] {
        let blocked = Set(denied.disabledChannelIds + offAir.offAirChannelIds)
        let checks = Dictionary(health.results.map { ($0.channelId, $0) }, uniquingKeysWith: { _, last in last })
        var seen = Set<String>()
        return feed.channels.filter { channel in
            let latest = checks[channel.id]
            let status = latest?.status ?? channel.healthStatus
            return channel.mediaType == "radio" && channel.publicationStatus == "published"
                && channel.manualDisabled != true && !blocked.contains(channel.id)
                && status != "blocked" && status != "offline"
                && (latest?.deliveryRatio ?? 1) >= 0.5
                && channel.stream != nil && seen.insert(channel.id).inserted
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func carrierURL(streamID: String) -> URL {
        var parts = URLComponents(url: ArchiveURL.base.appendingPathComponent("api/frequency"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "stream", value: streamID)]
        return parts.url!
    }
}
