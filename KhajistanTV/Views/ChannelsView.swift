import SwiftUI

/// One region: television, radio and, where the region has them, cameras.
struct ChannelsView: View {
    let region: ReceiverIndex.Region

    @Environment(AppModel.self) private var model
    @State private var medium = "tv"
    @State private var channels: [Channel] = []
    @State private var cameraChannels: [Channel] = []
    @State private var mainLoaded = false
    @State private var camerasLoaded = false
    @State private var loading = true
    @State private var errorText: String?
    @State private var playing: Channel?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)

    private var hasCameras: Bool {
        model.receiver.index?.cameraURL(regionId: region.id) != nil
    }

    /// The media this region carries, in picker order. A medium with nothing in it is not offered.
    private var media: [String] {
        var found: [String] = []
        if channels.contains(where: { $0.mediaType == "tv" }) { found.append("tv") }
        if channels.contains(where: { $0.mediaType == "radio" }) { found.append("radio") }
        if hasCameras { found.append("camera") }
        return found
    }

    /// What the grid shows for the chosen medium. The camera shard is its own list.
    private var shown: [Channel] {
        medium == "camera" ? cameraChannels : channels.filter { $0.mediaType == medium }
    }

    var body: some View {
        let palette = Palette(model.skin)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(region.label)
                    .font(KJFont.title())
                if mainLoaded && media.count > 1 {
                    Picker("Medium", selection: mediumBinding) {
                        ForEach(media, id: \.self) { kind in
                            Text(ReceiverRules.mediumLabel(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mediumPicker")
                    .frame(maxWidth: 900)
                }
                results(palette)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await start() }
        .fullScreenCover(item: $playing) { channel in
            ReceiverPlayerView(channel: channel, list: shown)
        }
    }

    @ViewBuilder
    private func results(_ palette: Palette) -> some View {
        if let message = errorText {
            Text(message)
                .font(KJFont.body())
            Button("Try again") {
                Task { await retry() }
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
        } else if loading {
            Text("Loading\u{2026}")
                .font(KJFont.body())
        } else if shown.isEmpty {
            Text("No \(ReceiverRules.mediumLabel(medium).lowercased()) here right now.")
                .font(KJFont.body())
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(shown) { channel in
                    Button {
                        playing = channel
                    } label: {
                        label(for: channel)
                    }
                    .buttonStyle(PlateButtonStyle(palette: palette))
                    .accessibilityIdentifier("channel-\(channel.id)")
                }
            }
        }
    }

    private func label(for channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(channel.name)
                .font(KJFont.bodyBold())
                .lineLimit(2)
            if !channel.place.isEmpty {
                Text(channel.place)
                    .font(KJFont.caption())
                    .lineLimit(1)
            }
            if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                Text(broadcaster)
                    .font(KJFont.caption())
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    private var mediumBinding: Binding<String> {
        Binding(
            get: { medium },
            set: { chosen in
                medium = chosen
                if chosen == "camera" && !camerasLoaded {
                    Task { await loadCameras() }
                }
            }
        )
    }

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
