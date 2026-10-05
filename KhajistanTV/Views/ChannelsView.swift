import SwiftUI

/// One region: television, radio and, where the region has them, cameras. The switch carries the counts.
struct ChannelsView: View {
    let region: ReceiverIndex.Region

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var medium = "tv"
    @State private var channels: [Channel] = []
    @State private var cameraChannels: [Channel] = []
    @State private var mainLoaded = false
    @State private var camerasLoaded = false
    @State private var loading = true
    @State private var errorText: String?
    @State private var playing: Channel?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 28), count: 4)

    private var hasCameras: Bool {
        model.receiver.index?.cameraURL(regionId: region.id) != nil
    }

    /// The Screening Room's films filed to this region, as the site's On Demand files them.
    private var films: [Film] {
        model.films.films(in: region.id, known: Set(model.receiver.index?.regions.map(\.id) ?? []))
    }

    /// The media this region carries, in switch order. A medium with nothing in it is not offered.
    private var media: [String] {
        var found: [String] = []
        if channels.contains(where: { $0.mediaType == "tv" }) { found.append("tv") }
        if channels.contains(where: { $0.mediaType == "radio" }) { found.append("radio") }
        if hasCameras { found.append("camera") }
        if !films.isEmpty { found.append("vod") }
        return found
    }

    /// What the grid shows for the chosen medium. The camera shard is its own list.
    private var shown: [Channel] {
        medium == "camera" ? cameraChannels : channels.filter { $0.mediaType == medium }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                if mainLoaded && media.count > 1 {
                    mediumSwitch
                }
                results
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 40)
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await start() }
        .task { await model.films.load() }
        .fullScreenCover(item: $playing) { channel in
            ReceiverPlayerView(channel: channel, list: shown)
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

    // MARK: - Medium switch

    private var mediumSwitch: some View {
        HStack(spacing: 12) {
            ForEach(media, id: \.self) { kind in
                Button {
                    choose(kind)
                } label: {
                    Text(switchTitle(kind)).kjKicker()
                }
                .buttonStyle(HouseTabStyle(isCurrent: medium == kind))
                .accessibilityIdentifier("medium-\(kind)")
            }
        }
        // The tab's plate padding is pulled back so its text sits on the page margin.
        .padding(.leading, -22)
    }

    /// "Television 39". A medium counts what the receiver may offer, so the camera shard, which is
    /// fetched only when asked for, shows the index's own count until it has arrived.
    private func switchTitle(_ kind: String) -> String {
        // The site's switch calls a film medium On Demand (open-frequencies.html, data-medium="vod").
        if kind == "vod" { return "On Demand \(films.count)" }
        let title = ReceiverRules.mediumLabel(kind)
        let count: Int?
        if kind == "camera" {
            count = camerasLoaded ? cameraChannels.count : model.receiver.index?.regionCounts[region.id]?.byMedium["camera"]
        } else {
            count = channels.filter { $0.mediaType == kind }.count
        }
        return count.map { "\(title) \($0)" } ?? title
    }

    private func choose(_ kind: String) {
        medium = kind
        if kind == "camera" && !camerasLoaded {
            Task { await loadCameras() }
        }
    }

    // MARK: - Channels

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
        } else if medium == "vod" {
            FilmGrid(films: films)
        } else if loading {
            TuningLoader("Loading\u{2026}")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if shown.isEmpty {
            Text("No \(ReceiverRules.mediumLabel(medium).lowercased()) here right now.")
                .kjBody()
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                ForEach(shown) { channel in
                    Button {
                        playing = channel
                    } label: {
                        card(channel)
                    }
                    .buttonStyle(HouseButtonStyle())
                    .accessibilityIdentifier("channel-\(channel.id)")
                }
            }
            // The cards' plate padding is pulled back so their text sits on the page margin.
            .padding(.horizontal, -26)
        }
    }

    /// The label of a channel's button. It styles itself through the palette in its own
    /// environment, which the button re-skins under focus, so nothing here names a colour.
    private func card(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(channel.name)
                .kjName()
                .lineLimit(2)
            if !channel.place.isEmpty {
                Kicker(channel.place)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                Text(broadcaster)
                    .kjSmall(faint: true)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }

    // MARK: - Loading

    /// Loads the television and radio shard, then the camera shard when that is where the
    /// region opens. Safe to run again: each step skips what it already has.
    private func start() async {
        await loadMain()
        if mainLoaded && medium == "camera" && !camerasLoaded && errorText == nil {
            await loadCameras()
        }
    }

    private func loadMain() async {
        guard !mainLoaded else { return }
        loading = true
        errorText = nil
        do {
            let list = try await model.receiver.channels(regionId: region.id, cameras: false)
            channels = list
            mainLoaded = true
            if list.contains(where: { $0.mediaType == "tv" }) {
                medium = "tv"
            } else if list.contains(where: { $0.mediaType == "radio" }) {
                medium = "radio"
            } else {
                // A region with neither opens on its cameras when it has any.
                medium = hasCameras ? "camera" : "radio"
            }
        } catch {
            if Task.isCancelled { return }
            errorText = error.localizedDescription
        }
        if medium != "camera" || errorText != nil { loading = false }
    }

    private func loadCameras() async {
        guard !camerasLoaded else { return }
        loading = true
        errorText = nil
        do {
            cameraChannels = try await model.receiver.channels(regionId: region.id, cameras: true)
            camerasLoaded = true
        } catch {
            if Task.isCancelled { return }
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func retry() async {
        errorText = nil
        await start()
    }
}
