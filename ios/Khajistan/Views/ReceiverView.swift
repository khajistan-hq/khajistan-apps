import SwiftUI
import UIKit

/// RECEIVER, the website's /open-frequencies on a phone: live television, radio and public cameras
/// by region on the map, and Khajistan Transmission's two channels. The Khajistan Radio mixes are
/// not a section here (owner, 2026-10-06): they play on Transmission's channel 2. Everything is read from the public files the
/// website reads (Core/Receiver.swift, Services/ReceiverStore.swift).
struct ReceiverView: View {
    enum Part: String, CaseIterable, Identifiable {
        case live, cameras, transmission
        var id: String { rawValue }
        var title: String {
            switch self {
            case .live: return "Live"
            case .cameras: return "Cameras"
            case .transmission: return "Transmission"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var part: Part = UserDefaults.standard.string(forKey: "kjpart").flatMap(Part.init(rawValue:)) ?? .live
    @State private var fullScreen = false
    /// Which full-screen view is up, fixed when it opens: read live from the tuner, turning the
    /// receiver off mid-dismissal swapped in an empty live view for a frame.
    @State private var fullScreenTransmission = false

    var body: some View {
        VStack(spacing: 0) {
            // On, the set stays above the page while the reader browses; off, it is the top of
            // the page and scrolls away with it.
            if model.tuner.source != nil {
                device
                    .padding(.horizontal, KJLayout.inset)
                    .kjColumn(KJLayout.wideWidth)
                    .padding(.vertical, 8)
            }
            page
        }
        .fullScreenCover(isPresented: $fullScreen) {
            if fullScreenTransmission { TransmissionPlayerView() } else { ReceiverPlayerView() }
        }
    }

    private var device: some View {
        ReceiverDevice(part: $part, fullScreen: Binding(get: { fullScreen }, set: { open in
            if open {
                if case .transmission = model.tuner.source { fullScreenTransmission = true } else { fullScreenTransmission = false }
            }
            fullScreen = open
        }))
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHead("Receiver", line: "Live television, live radio and public cameras from the Middle World.")
                figures
                if model.tuner.source == nil { device }
                switch part {
                case .live: LiveSection()
                case .cameras: CamerasSection()
                case .transmission: TransmissionSection()
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn(KJLayout.wideWidth)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await model.receiver.loadIndex() }
    }

    /// The four figures of the receiver index, laid out before they arrive so nothing moves.
    private var figures: some View {
        let totals = model.receiver.index?.totals
        func value(_ n: Int?) -> String { n.map { $0.formatted() } ?? "\u{2014}" }
        let items = [("Live now", value(totals?.live)), ("Television", value(totals?.byMedium["tv"])),
                     ("Radio", value(totals?.byMedium["radio"])), ("Cameras", value(totals?.byMedium["camera"]))]
        // One row while the four fit; two rows of two at large type.
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.0) { Figure(label: $0.0, value: $0.1).fixedSize() }
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { Figure(label: items[0].0, value: items[0].1); Figure(label: items[1].0, value: items[1].1) }
                GridRow { Figure(label: items[2].0, value: items[2].1); Figure(label: items[3].0, value: items[3].1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live

/// The map and the region on it: tap a region (or its name in the strip) and its television,
/// radio and cameras are listed under it. A channel plays in the docked screen, whose next and
/// previous move through the list it came from.
private struct LiveSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage("kj.extendedAtlas") private var extended = false
    @Environment(\.horizontalSizeClass) private var sizeClass
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

    private var index: ReceiverIndex? { model.receiver.index }

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: the map beside the region's channels, so the list starts at the top of the
                // page instead of under a full-width map (design review, 2026-10-07).
                HStack(alignment: .top, spacing: 40) {
                    atlas.frame(maxWidth: .infinity, alignment: .leading)
                    regionBlock.frame(width: 400, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    atlas
                    regionBlock
                }
            }
        }
        .task(id: extended) { await loadMap() }
        .task(id: selected) { await loadRegion() }
    }

    // MARK: Map and strip

    private var atlas: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfSettings()
            HouseSwitch(title: "Beyond the atlas", detail: "The wider Islamicate, Rumelia to Nusantara", isOn: $extended)
                .accessibilityIdentifier("beyondTheAtlas")
            map
            strip
        }
    }

    private var map: some View {
        ZStack {
            if let composed {
                RegionMapView(map: composed, highlighted: selected) { id in choose(id) }
            } else if let message = mapError ?? model.receiver.indexError {
                problem(message) { Task { await model.receiver.loadIndex(); await loadMap() } }
            } else {
                // The core map's own shape holds the space while it loads.
                Color.clear.aspectRatio(10.0 / 7.0, contentMode: .fit)
                    .overlay { TuningLoader("Loading the receiver\u{2026}") }
            }
        }
        // The strip under the map is the accessible way to choose; the map is one element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Region map. Choose a region from the list under it.")
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Regions")
            .onChange(of: selected) { _, id in withAnimation(.kj) { reader.scrollTo(id, anchor: .center) } }
            .onChange(of: composed?.regions.count) { reader.scrollTo(selected, anchor: .center) }
        }
        .frame(height: 44)
    }

    private func choose(_ id: String) {
        guard id != selected else { return }
        selected = id
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
                    Text(regionLabel).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
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
                        medium = kind
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
                        model.tuner.play(channel, in: list)
                    } label: {
                        ChannelRow(channel: channel)
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)))
                    .accessibilityIdentifier("channel-\(channel.id)")
                    if channel.id != list.last?.id { HouseRule() }
                }
            }
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
            // The list arrives below the strip, out of VoiceOver's way: say that it did.
            UIAccessibility.post(notification: .announcement, argument: "\(regionLabel): \(list.count) channels")
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
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    /// The channel on the set: it carries the speaker mark, so the list shows where the dial is.
    private var isOn: Bool {
        if case .live(let on) = model.tuner.source { return on.id == channel.id }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isOn {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
                Text(channel.name).kjName().lineLimit(2)
            }
            if !channel.place.isEmpty { Kicker(channel.place).lineLimit(1) }
            if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                Text(broadcaster).kjSmall(faint: true).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}


// MARK: - Shuffle

/// What the receiver's Surf key finds: a live channel at random, of this medium, from this part
/// of the atlas. Kept on the device (owner, 2026-10-07).
private struct SurfSettings: View {
    @AppStorage(ShuffleMedium.key) private var mediumRaw = ShuffleMedium.tv.rawValue
    @AppStorage(ShuffleScope.key) private var scopeRaw = ShuffleScope.main.rawValue

    private var medium: ShuffleMedium { ShuffleMedium(rawValue: mediumRaw) ?? .tv }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Kicker("Surf")
                Text("A live \(medium == .tv ? "television" : "radio") channel at random").kjSmall(faint: true)
            }
            chips(ShuffleMedium.allCases.map { ($0.rawValue, $0.label) }, current: mediumRaw, id: "shuffle-medium") { mediumRaw = $0 }
            chips(ShuffleScope.allCases.map { ($0.rawValue, $0.label) }, current: scopeRaw, id: "shuffle-scope") { scopeRaw = $0 }
        }
    }

    private func chips(_ items: [(String, String)], current: String, id: String, set: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { item in
                    Button { set(item.0) } label: { Text(item.1).kjKicker() }
                        .buttonStyle(HouseTabStyle(isCurrent: item.0 == current))
                        .accessibilityIdentifier("\(id)-\(item.0)")
                }
            }
        }
        .padding(.horizontal, -12)
    }
}

// MARK: - Cameras

/// Every public camera the receiver carries, by region, the main atlas first (owner, 2026-10-07:
/// "make cctv show up in the reciever"). A camera plays in the docked screen; next and previous
/// move through its region's cameras.
private struct CamerasSection: View {
    @Environment(AppModel.self) private var model
    @State private var lists: [String: [Channel]] = [:]
    @State private var failed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let index = model.receiver.index {
                let regions = CameraRegions.ordered(index)
                Text("\(CameraRegions.total(index).formatted()) cameras in \(regions.count) regions").kjSmall(faint: true)
                    .accessibilityIdentifier("camerasTotal")
                ForEach(regions) { region in
                    VStack(alignment: .leading, spacing: 8) {
                        HouseRule()
                        Text(region.label).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        if let list = lists[region.id], list.isEmpty {
                            Text("No cameras here right now.").kjSmall(faint: true)
                        } else if let list = lists[region.id] {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(list) { channel in
                                    Button { model.tuner.play(channel, in: list) } label: {
                                        ChannelRow(channel: channel)
                                    }
                                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)))
                                    .accessibilityIdentifier("camera-\(channel.id)")
                                }
                            }
                        } else if failed.contains(region.id) {
                            Text("These cameras did not load.").kjSmall(faint: true)
                        } else {
                            TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 60)
                        }
                    }
                    .task { await load(region.id) }
                }
            } else {
                TuningLoader("Loading the receiver\u{2026}").frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func load(_ region: String) async {
        guard lists[region] == nil else { return }
        do {
            lists[region] = try await model.receiver.channels(regionId: region, cameras: true)
        } catch {
            failed.insert(region)
        }
    }
}
