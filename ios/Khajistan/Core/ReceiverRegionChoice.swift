import Foundation

/// A map/strip selection uses the chosen region's eligible catalogue, even after global Surf.
struct ReceiverRegionChoice {
    let channel: Channel
    let list: [Channel]

    static func choose(from eligible: [Channel], currentID: String?, medium: ShuffleMedium) -> Self? {
        let preferred = eligible.filter { medium.includes($0.mediaType) }
        // Preserve the existing region-dial fallback when its requested medium is absent.
        let list = preferred.isEmpty ? eligible : preferred
        guard !list.isEmpty else { return nil }
        let channel: Channel
        if let currentID, let position = list.firstIndex(where: { $0.id == currentID }) {
            channel = list[(position + 1) % list.count]
        } else {
            channel = list.randomElement()!
        }
        return Self(channel: channel, list: list)
    }
}
