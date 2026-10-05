import SwiftUI

/// RECEIVER, the website's /open-frequencies on a phone: live television, radio and public cameras
/// by region on the map, Khajistan Transmission's two channels, and the Khajistan Radio mixes, as
/// the site carries all three in one receiver. Everything is read from the public files the
/// website reads (Core/Receiver.swift, Services/ReceiverStore.swift).
struct ReceiverView: View {
    enum Part: String, CaseIterable, Identifiable {
        case live, transmission, radio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .live: return "Live"
            case .transmission: return "Transmission"
            case .radio: return "Khajistan Radio"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var part: Part = UserDefaults.standard.string(forKey: "kjpart").flatMap(Part.init(rawValue:)) ?? .live

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHead("Receiver", line: "Live television, live radio and public cameras from the Middle World.")
                figures
                parts
                switch part {
                case .live: LiveSection()
                case .transmission: TransmissionSection()
                case .radio: MixesSection()
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await model.receiver.loadIndex() }
    }

    /// The four figures of the receiver index, laid out before they arrive so nothing moves.
    private var figures: some View {
        let totals = model.receiver.index?.totals
        func value(_ n: Int?) -> String { n.map { $0.formatted() } ?? "\u{2014}" }
        return HStack(alignment: .top, spacing: 12) {
            Figure(label: "Live now", value: value(totals?.live))
            Figure(label: "Television", value: value(totals?.byMedium["tv"]))
            Figure(label: "Radio", value: value(totals?.byMedium["radio"]))
            Figure(label: "Cameras", value: value(totals?.byMedium["camera"]))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.kj, value: totals?.live)
    }

    private var parts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Part.allCases) { item in
                    Button {
                        withAnimation(.kj) { part = item }
                    } label: {
                        Text(item.title).kjKicker()
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: part == item))
                    .accessibilityIdentifier("part-\(item.rawValue)")
                }
            }
        }
        .padding(.horizontal, -12)
    }
}

// MARK: - Live

/// The map and the region on it: tap a region (or its name in the strip) and its television,
/// radio and cameras are listed under it. A channel opens full screen, where a swipe up or down
/// moves through the list it came from.
private struct LiveSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage("kj.extendedAtlas") private var extended = false
    @State private var composed: ComposedMap?
    @State private var mapError: String?
    @State private var selected = UserDefaults.standard.string(forKey: "kjregion") ?? "indus"
    @State private var medium = "tv"
    @State private var channels: [Channel] = []
    @State private var cameraChannels: [Channel] = []
    @State private var loadedRegion: String?
    @State private var camerasLoaded = false
    @State private var loading = false
    @State private var listError: String?
    @State private var filter = ""
    @State private var playing: PlayerChoice?

    struct PlayerChoice: Identifiable {
        let channel: Channel
        let list: [Channel]
        var id: String { channel.id }
    }

    private var index: ReceiverIndex? { model.receiver.index }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HouseSwitch(title: "Beyond the atlas", detail: "The wider Islamicate, Rumelia to Nusantara", isOn: $extended)
                .accessibilityIdentifier("beyondTheAtlas")
            map
            strip
            regionBlock
        }
        .task(id: extended) { await loadMap() }
        .task(id: selected) { await loadRegion() }
        .fullScreenCover(item: $playing) { choice in
            ReceiverPlayerView(channel: choice.channel, list: choice.list)
        }
    }

    // MARK: Map and strip

    private var map: some View {
        ZStack {
            if let composed {
                RegionMapView(map: composed, highlighted: selected) { id in choose(id) }
                    .transition(.opacity)
            } else if let message = mapError ?? model.receiver.indexError {
                problem(message) { Task { await model.receiver.loadIndex(); await loadMap() } }
            } else {
                // The core map's own shape holds the space while it loads.
                Color.clear.aspectRatio(10.0 / 7.0, contentMode: .fit)
                    .overlay { TuningLoader("Loading the receiver\u{2026}") }
            }
        }
        .animation(.easeOut(duration: 0.25), value: composed == nil)
        // The strip under the map is the accessible way to choose; the map is one element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Region map")
        .accessibilityIdentifier("receiverMap")
    }

    /// Every region that opens channels, west to east as it sits on the map.
    private var regions: [MapRegion] {
        (composed?.regions ?? []).filter(\.opensChannels)
            .sorted { ($0.centroid.x, $0.centroid.y) < ($1.centroid.x, $1.centroid.y) }
    }

    private var strip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(regions) { region in
                        Button {
                            choose(region.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(region.label).kjKicker()
                                if let live = region.live { Text(live.formatted()).kjSmall(faint: true).monospacedDigit() }
                            }
                        }
                        .buttonStyle(HouseTabStyle(isCurrent: region.id == selected))
                        .id(region.id)
                        .accessibilityIdentifier("region-\(region.id)")
                        .accessibilityLabel(region.live.map { "\(region.label), \($0) live" } ?? region.label)
                    }
                }
            }
            .padding(.horizontal, -12)
            .onChange(of: selected) { _, id in withAnimation(.kj) { reader.scrollTo(id, anchor: .center) } }
            .onChange(of: composed?.regions.count) { reader.scrollTo(selected, anchor: .center) }
        }
        .frame(height: 44)
    }

    private func choose(_ id: String) {
        guard id != selected else { return }
        withAnimation(.kj) { selected = id }
    }

    // MARK: The region

    private var regionLabel: String {
        index?.regions.first { $0.id == selected }?.label
            ?? composed?.regions.first { $0.id == selected }?.label ?? selected
    }

    private var hasCameras: Bool { index?.cameraURL(regionId: selected) != nil }

    private var media: [String] {
        var found: [String] = []
        if channels.contains(where: { $0.mediaType == "tv" }) { found.append("tv") }
        if channels.contains(where: { $0.mediaType == "radio" }) { found.append("radio") }
        if hasCameras { found.append("camera") }
        return found
    }

    private var shown: [Channel] {
        let list = medium == "camera" ? cameraChannels : channels.filter { $0.mediaType == medium }
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return list }
        return list.filter { "\($0.name) \($0.place) \($0.broadcaster ?? "")".localizedCaseInsensitiveContains(needle) }
    }

    private var regionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HouseRule()
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(regionLabel).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(1)
                    // Native script is never letter-spaced: tracking breaks the joins.
                    if let native = model.receiver.nativeName(for: selected) {
                        Text(native).font(.system(KJType.title, weight: .bold)).foregroundStyle(palette.faint).lineLimit(1)
                    }
                }
                if let line = index?.mediumLine(regionId: selected), !line.isEmpty { Text(line).kjSmall(faint: true) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("regionTitle")
            if loadedRegion == selected && media.count > 1 { mediumSwitch }
            if channels.count + cameraChannels.count > 10 {
                HouseInputField("Find a channel") {
                    TextField("", text: $filter, prompt: Text("Name, place or language").foregroundStyle(palette.faint))
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("channelFilter")
                }
            }
            list
        }
    }

    private var mediumSwitch: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(media, id: \.self) { kind in
                    Button {
                        withAnimation(.kj) { medium = kind }
                        if kind == "camera" && !camerasLoaded { Task { await loadCameras() } }
                    } label: {
                        Text(switchTitle(kind)).kjKicker()
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: medium == kind))
                    .accessibilityIdentifier("medium-\(kind)")
                }
            }
        }
        .padding(.horizontal, -12)
    }

    private func switchTitle(_ kind: String) -> String {
        let title = ReceiverRules.mediumLabel(kind)
        let count = kind == "camera"
            ? (camerasLoaded ? cameraChannels.count : index?.regionCounts[selected]?.byMedium["camera"])
            : channels.filter { $0.mediaType == kind }.count
        return count.map { "\(title) \($0)" } ?? title
    }

    @ViewBuilder
    private var list: some View {
        if let listError {
            problem(listError) { Task { await loadRegion(force: true) } }
        } else if loading || loadedRegion != selected {
            TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 120)
        } else if shown.isEmpty {
            Text(filter.isEmpty ? "No \(ReceiverRules.mediumLabel(medium).lowercased()) here right now." : "Nothing here matches.")
                .kjBody()
                .padding(.vertical, 12)
        } else {
            let list = shown
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(list) { channel in
                    Button {
                        playing = PlayerChoice(channel: channel, list: list)
                    } label: {
                        ChannelRow(channel: channel)
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)))
                    .accessibilityIdentifier("channel-\(channel.id)")
                    if channel.id != list.last?.id { HouseRule() }
                }
            }
            .transition(.opacity)
        }
    }

    private func problem(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).kjBody()
            Button(action: retry) { Text("Try again").kjKicker() }
                .buttonStyle(HouseButtonStyle(solid: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Loading

    private func loadMap() async {
        await model.receiver.loadIndex()
        guard let index = model.receiver.index else { return }
        let wanted = extended
        do {
            let shapes = try await model.receiver.mapShapes(extended: wanted)
            let map = await Task.detached(priority: .userInitiated) {
                RegionMapRules.compose(core: shapes.core, extended: shapes.extended, index: index, showExtensions: wanted)
            }.value
            if Task.isCancelled { return }
            mapError = map == nil ? "The receiver sent a map that could not be read." : nil
            composed = map
        } catch {
            if Task.isCancelled { return }
            if composed == nil { mapError = error.localizedDescription }
        }
    }

    /// The region's television and radio shard, and its camera shard when it opens on cameras.
    private func loadRegion(force: Bool = false) async {
        guard force || loadedRegion != selected else { return }
        await model.receiver.loadIndex()
        let region = selected
        loading = true
        listError = nil
        filter = ""
        camerasLoaded = false
        cameraChannels = []
        do {
            let list = try await model.receiver.channels(regionId: region, cameras: false)
            guard region == selected else { return }
            channels = list
            if list.contains(where: { $0.mediaType == medium }) && medium != "camera" {
                // Stay on the medium the reader was on.
            } else if list.contains(where: { $0.mediaType == "tv" }) {
                medium = "tv"
            } else if list.contains(where: { $0.mediaType == "radio" }) {
                medium = "radio"
            } else {
                medium = hasCameras ? "camera" : "tv"
            }
            if medium == "camera" { await loadCameras() }
            loadedRegion = region
        } catch {
            if Task.isCancelled || region != selected { return }
            listError = error.localizedDescription
        }
        if region == selected { loading = false }
    }

    private func loadCameras() async {
        guard !camerasLoaded else { return }
        let region = selected
        do {
            let list = try await model.receiver.channels(regionId: region, cameras: true)
            guard region == selected else { return }
            cameraChannels = list
            camerasLoaded = true
        } catch {
            if Task.isCancelled { return }
            listError = error.localizedDescription
        }
    }
}

/// One channel: its name, the place as a kicker, the broadcaster when it is someone else.
struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(channel.name).kjName().lineLimit(2)
            if !channel.place.isEmpty { Kicker(channel.place).lineLimit(1) }
            if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                Text(broadcaster).kjSmall(faint: true).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
