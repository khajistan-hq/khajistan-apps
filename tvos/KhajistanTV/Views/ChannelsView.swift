import SwiftUI

/// One region, laid out as the TV app lays a page: the name, then a shelf for each medium it
/// carries, television first, then radio, cameras and the films filed to it. Up and down move
/// between shelves; left and right along one.
struct ChannelsView: View {
    let region: ReceiverIndex.Region

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var channels: [Channel] = []
    @State private var cameraChannels: [Channel] = []
    @State private var mainLoaded = false
    @State private var camerasLoaded = false
    @State private var cameraError: String?
    @State private var errorText: String?
    @State private var playing: Playing?

    /// A channel chosen, and the shelf it came from: up and down in the player surf that shelf.
    private struct Playing: Identifiable {
        let channel: Channel
        let list: [Channel]
        var id: String { channel.id }
    }

    private var hasCameras: Bool {
        model.receiver.index?.cameraURL(regionId: region.id) != nil
    }

    /// The Screening Room's films filed to this region, as the site's On Demand files them.
    private var films: [Film] {
        model.films.films(in: region.id, known: Set(model.receiver.index?.regions.map(\.id) ?? []))
    }

    /// The media this region carries, in shelf order. A medium with nothing in it has no shelf.
    private var media: [String] {
        var found: [String] = []
        if channels.contains(where: { $0.mediaType == "tv" }) { found.append("tv") }
        if channels.contains(where: { $0.mediaType == "radio" }) { found.append("radio") }
        if hasCameras { found.append("camera") }
        if !films.isEmpty { found.append("vod") }
        return found
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                    .padding(.bottom, 24)
                results
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 40)
        }
        .kjTopFade()
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await start() }
        .task { await model.saves.load() }
        .task { await model.films.load() }
        .fullScreenCover(item: $playing) { choice in
            ReceiverPlayerView(channel: choice.channel, list: choice.list)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Receiver \u{2192} \(region.label)")
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                Text(region.label)
                    .kjDisplay()
                    .layoutPriority(1)
                // Native script is never letter-spaced: tracking breaks the joins in Arabic and Persian.
                if let native = model.receiver.nativeName(for: region.id) {
                    Text(native)
                        .kjDisplay(KJType.headline, tracking: 0)
                        .foregroundStyle(palette.faint)
                }
            }
        }
    }

    // MARK: - Shelves

    @ViewBuilder
    private var results: some View {
        if let message = errorText {
            VStack(alignment: .leading, spacing: 28) {
                Text(message)
                    .kjBody()
                Button {
                    Task { await retry() }
                } label: {
                    Text("Try again").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
            }
        } else if !mainLoaded {
            TuningLoader("Loading\u{2026}")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if media.isEmpty {
            Text("No channels here right now.")
                .kjBody()
        } else {
            ForEach(media, id: \.self) { kind in
                shelf(kind)
            }
        }
    }

    @ViewBuilder
    private func shelf(_ kind: String) -> some View {
        switch kind {
        case "vod":
            // The site's switch calls a film medium On Demand (open-frequencies.html, data-medium="vod").
            FilmShelf(title: "On Demand", count: "\(films.count) \(films.count == 1 ? "film" : "films")", films: films)
                .accessibilityIdentifier("shelf-vod")
        case "camera":
            cameraShelf
        default:
            let list = channels.filter { $0.mediaType == kind }
            channelShelf(kind, list)
        }
    }

    private func channelShelf(_ kind: String, _ list: [Channel]) -> some View {
        Shelf(ReceiverRules.mediumLabel(kind), count: "\(list.count)") {
            ForEach(list) { channel in
                Button {
                    playing = Playing(channel: channel, list: list)
                } label: {
                    ChannelCard(channel: channel, liked: model.saves.isSaved(channel))
                }
                .buttonStyle(HouseCardStyle())
                // No hold-for-Like menu: tvOS draws its focused item white. Like is on the player strip.
                .accessibilityIdentifier("channel-\(channel.id)")
            }
        }
        .accessibilityIdentifier("shelf-\(kind)")
    }

    /// The camera shard is its own list, fetched on its own. Until it lands the shelf holds its
    /// place with the index's own count.
    @ViewBuilder
    private var cameraShelf: some View {
        if camerasLoaded {
            channelShelf("camera", cameraChannels)
        } else {
            let count = model.receiver.index?.regionCounts[region.id]?.byMedium["camera"]
            Shelf(ReceiverRules.mediumLabel("camera"), count: count.map { "\($0)" }) {
                if let cameraError {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(cameraError).kjBody().lineLimit(2)
                        Button {
                            Task { await loadCameras() }
                        } label: {
                            Text("Try again").kjKicker()
                        }
                        .buttonStyle(HouseButtonStyle())
                    }
                    .frame(width: 900, height: ChannelCard.height, alignment: .leading)
                } else {
                    TuningLoader("Loading\u{2026}")
                        .frame(width: ChannelCard.width, height: ChannelCard.height, alignment: .leading)
                }
            }
            .accessibilityIdentifier("shelf-camera")
        }
    }

    // MARK: - Loading

    /// Loads the television and radio shard, then the camera shard where the region has one.
    /// Safe to run again: each step skips what it already has.
    private func start() async {
        await loadMain()
        #if DEBUG
        // With `-kjautochange`, a region link opens straight onto its first channel (see
        // ReceiverPlayerView), for measuring the flights on a device.
        if UserDefaults.standard.integer(forKey: "kjautochange") > 0, playing == nil {
            let tv = channels.filter { $0.mediaType == "tv" }
            if let first = tv.first ?? channels.first { playing = Playing(channel: first, list: tv.isEmpty ? channels : tv) }
        }
        #endif
        if mainLoaded && hasCameras && !camerasLoaded && cameraError == nil {
            await loadCameras()
        }
    }

    private func loadMain() async {
        guard !mainLoaded else { return }
        errorText = nil
        do {
            channels = try await model.receiver.channels(regionId: region.id, cameras: false)
            mainLoaded = true
        } catch {
            if Task.isCancelled { return }
            errorText = error.localizedDescription
        }
    }

    private func loadCameras() async {
        guard !camerasLoaded else { return }
        cameraError = nil
        do {
            cameraChannels = try await model.receiver.channels(regionId: region.id, cameras: true)
            camerasLoaded = true
        } catch {
            if Task.isCancelled { return }
            cameraError = error.localizedDescription
        }
    }

    private func retry() async {
        errorText = nil
        await start()
    }
}

/// A channel's card: the place as a kicker, the name, the broadcaster where it differs. It sits
/// on a plate, so it names no colour: the plate sets the palette its text reads.
struct ChannelCard: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 190

    let channel: Channel
    var liked = false

    var body: some View {
        CardPlate(width: Self.width, height: Self.height) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if liked {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .accessibilityLabel("Liked")
                    }
                    if !channel.place.isEmpty {
                        Kicker(channel.place)
                            .lineLimit(1)
                    }
                }
                Text(channel.name)
                    .kjName()
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                    Text(broadcaster)
                        .kjSmall(faint: true)
                        .lineLimit(1)
                }
            }
        }
    }
}
