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
        .task(id: model.tab) {
            guard model.tab == .receiver else { return }
            await model.tuner.receiverOpened(isActive: { model.tab == .receiver })
        }
        .onChange(of: model.tab) { _, tab in
            if tab != .receiver { model.tuner.receiverClosed() }
        }
        .onChange(of: model.receiver.playbackEpoch) { _, _ in
            model.tuner.stop()
            fullScreen = false
        }
        .fullScreenCover(isPresented: $fullScreen) {
            Group {
                if fullScreenTransmission { TransmissionPlayerView() } else { ReceiverPlayerView() }
            }
            .environment(model)
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
                LargeTitle(title: "Receiver", line: "Live television, live radio and public cameras from the Middle World.")
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
        .accessibilityIdentifier("receiverCatalogue")
        .scrollDismissesKeyboard(.interactively)
        .task {
            await model.receiver.loadIndex()
            // The count walks every region. Surf must not wait for that walk.
            model.receiver.watchHealthClock()
            await model.playIfOpening()
        }
    }

    /// The four figures of the receiver index, laid out before they arrive so nothing moves.
    private var figures: some View {
        func value(_ n: Int?) -> String { n.map { $0.formatted() } ?? "\u{2026}" }
        let items = [("Live now", value(model.receiver.liveNow)), ("Television", value(model.receiver.televisionNow)),
                     ("Radio", value(model.receiver.radioNow)), ("Cameras", value(model.receiver.camerasNow))]
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
    /// The hiss of a dial between stations, while a finger slides across the map.
    @State private var hiss = StaticNoise()

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
        .onDisappear {
            model.receiver.cancelChannels(regionId: selected, cameras: false)
            model.receiver.cancelChannels(regionId: selected, cameras: true)
        }
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
                RegionMapView(map: composed, highlighted: selected, onTap: choose,
                              onScrub: { passing in
                                  hiss.set(passing == nil ? 0 : StaticNoise.tuningLevel)
                              },
                              liveCount: { model.receiver.regionLiveCount(regionId: $0) })
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
                                Text(region.label)
                                Text(ReceiverRules.regionLiveFigure(verified: model.receiver.regionLiveCount(regionId: region.id)))
                                    .monospacedDigit().opacity(0.7)
                            }
                        }
                        .buttonStyle(ChipStyle(on: region.id == selected))
                        .padding(.trailing, 8)
                        .id(region.id)
                        .accessibilityIdentifier("region-\(region.id)")
                        .accessibilityLabel(ReceiverRules.regionChipAccessibility(label: region.label,
                            verified: model.receiver.regionLiveCount(regionId: region.id)))
                    }
                }
            }
            .scrollClipDisabled()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Regions")
            .onChange(of: selected) { _, id in withAnimation(.kj) { reader.scrollTo(id, anchor: .center) } }
            .onChange(of: composed?.regions.count) { reader.scrollTo(selected, anchor: .center) }
        }
        .frame(height: 44)
    }

    /// Chooses a region and tunes it, from the map or the strip: the map is a dial (Radio Garden's
    /// lesson). The region on the set moves to its next channel; another region starts on one of
    /// its channels of the Surf medium, drawn at random as Surf draws.
    private func choose(_ id: String) {
        tune(region: id)
        guard id != selected else { return }
        selected = id
    }

    private func tune(region id: String) {
        if model.tuner.channel?.regionIds?.contains(id) == true, model.tuner.canStep {
            model.tuner.step(1)
            return
        }
        Task {
            guard let all = try? await model.receiver.channels(regionId: id, cameras: false) else { return }
            let medium = UserDefaults.standard.string(forKey: ShuffleMedium.key).flatMap(ShuffleMedium.init(rawValue:)) ?? .tv
            let pool = all.filter { $0.mediaType == medium.rawValue }
            let list = pool.isEmpty ? all : pool
            guard let channel = list.randomElement() else { return }
            model.tuner.play(channel, in: list)
        }
    }

    // MARK: The region

    private var regionLabel: String {
        index?.regions.first { $0.id == selected }?.label
            ?? composed?.regions.first { $0.id == selected }?.label ?? selected
    }

    private var hasCameras: Bool { index?.cameraURL(regionId: selected) != nil }

    /// Liked and saved rows use the same gate as the rest of the dial. Rows appear as each probe succeeds.
    private var liveChannels: [Channel] { model.receiver.shown(regionId: selected, cameras: false) }
    private var liveCameras: [Channel] { model.receiver.shown(regionId: selected, cameras: true) }

    private var media: [String] {
        var found: [String] = []
        if liveChannels.contains(where: { $0.mediaType == "tv" }) { found.append("tv") }
        if liveChannels.contains(where: { $0.mediaType == "radio" }) { found.append("radio") }
        if hasCameras { found.append("camera") }
        return found
    }

    private var shown: [Channel] {
        let list = medium == "camera" ? liveCameras : liveChannels.filter { $0.mediaType == medium }
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
                if model.receiver.walkFinished(regionId: selected, cameras: false) {
                    let line = ReceiverRules.verifiedMediumLine(
                        tv: model.receiver.verifiedChannels(regionId: selected, medium: "tv").count,
                        radio: model.receiver.verifiedChannels(regionId: selected, medium: "radio").count,
                        camera: model.receiver.walkFinished(regionId: selected, cameras: true)
                            ? model.receiver.shown(regionId: selected, cameras: true).count : nil)
                    if !line.isEmpty { Text(line).kjSmall(faint: true) }
                } else {
                    Text("\u{2026}").kjSmall(faint: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("regionTitle")
            if loadedRegion == selected && media.count > 1 { mediumSwitch }
            if liveChannels.count + liveCameras.count > 10 {
                SearchField(prompt: "Name, place or language", text: $filter, id: "channelFilter")
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
                        Text(switchTitle(kind))
                    }
                    .buttonStyle(ChipStyle(on: medium == kind))
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("medium-\(kind)")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func switchTitle(_ kind: String) -> String {
        let title = ReceiverRules.mediumLabel(kind)
        let count: Int? = kind == "camera"
            ? (model.receiver.walkFinished(regionId: selected, cameras: true) ? liveCameras.count : nil)
            : (model.receiver.walkFinished(regionId: selected, cameras: false)
                ? liveChannels.filter { $0.mediaType == kind }.count : nil)
        return count.map { "\(title) \($0)" } ?? "\(title) \u{2026}"
    }

    @ViewBuilder
    private var list: some View {
        if let listError {
            problem(listError) { Task { await loadRegion(force: true) } }
        } else if (loading || loadedRegion != selected) && shown.isEmpty {
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
    /// A walk that still has unprobed rows is asked again, a bounded number of times, once a
    /// slot has had time to free. The region is not marked loaded until that walk finishes.
    private func loadRegion(force: Bool = false) async {
        guard force || loadedRegion != selected else { return }
        await model.receiver.loadIndex()
        let region = selected
        loading = true
        listError = nil
        filter = ""
        camerasLoaded = false
        cameraChannels = []
        var attempt = 0
        var list: [Channel] = []
        var finished = false
        while !Task.isCancelled && region == selected {
            attempt += 1
            do {
                list = try await model.receiver.channels(regionId: region, cameras: false)
            } catch {
                if Task.isCancelled || region != selected { return }
                listError = error.localizedDescription
                break
            }
            guard region == selected else { return }
            channels = list
            if model.receiver.walkFinished(regionId: region, cameras: false) {
                finished = true
                break
            }
            guard ReceiverRules.shouldRetryUnfinishedWalk(attempt: attempt, unprobed: 1) else { break }
            try? await Task.sleep(for: .seconds(ReceiverRules.unfinishedWalkDelay()))
        }
        guard region == selected else { return }
        if finished {
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
        }
        if region == selected { loading = false }
    }

    private func loadCameras() async {
        guard !camerasLoaded else { return }
        let region = selected
        var attempt = 0
        while !Task.isCancelled && region == selected {
            attempt += 1
            do {
                let list = try await model.receiver.channels(regionId: region, cameras: true)
                guard region == selected else { return }
                cameraChannels = list
            } catch {
                if Task.isCancelled { return }
                listError = error.localizedDescription
                return
            }
            if model.receiver.walkFinished(regionId: region, cameras: true) {
                camerasLoaded = true
                return
            }
            guard ReceiverRules.shouldRetryUnfinishedWalk(attempt: attempt, unprobed: 1) else { return }
            try? await Task.sleep(for: .seconds(ReceiverRules.unfinishedWalkDelay()))
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

    /// A live guide's row, as YouTube TV sets one: the medium's mark on a plate, the name, where
    /// it is from, and LIVE in the accent on the channel playing now.
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? palette.band : palette.lift)
                .frame(width: 52, height: 40)
                .overlay {
                    Image(systemName: isOn ? "speaker.wave.2.fill" : Self.symbol(channel.mediaType))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? palette.onBand : palette.ink)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.system(.body, weight: .semibold)).lineLimit(2)
                let line = [channel.place, channel.broadcaster.flatMap { $0.isEmpty || $0 == channel.name ? nil : $0 }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                if !line.isEmpty { Text(line).kjSmall(faint: true).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if isOn {
                Text("LIVE").font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.onBand)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(palette.band, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    static func symbol(_ mediaType: String) -> String {
        switch mediaType.lowercased() {
        case "radio": return "radio"
        case "camera": return "video"
        default: return "tv"
        }
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
                Text("Surf").font(.system(.subheadline, weight: .bold))
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
                    Button { set(item.0) } label: { Text(item.1) }
                        .buttonStyle(ChipStyle(on: item.0 == current))
                        .padding(.trailing, 8)
                        .accessibilityIdentifier("\(id)-\(item.0)")
                }
            }
        }
        .scrollClipDisabled()
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
                Text(model.receiver.camerasNow.map { "\($0.formatted()) cameras in \(regions.count) regions" } ?? "\u{2026}")
                    .kjSmall(faint: true)
                    .accessibilityIdentifier("camerasTotal")
                ForEach(regions) { region in
                    VStack(alignment: .leading, spacing: 8) {
                        HouseRule()
                        Text(region.label).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        let live = model.receiver.shown(regionId: region.id, cameras: true)
                        if model.receiver.walkFinished(regionId: region.id, cameras: true) && live.isEmpty {
                            Text("No cameras here right now.").kjSmall(faint: true)
                        } else if live.isEmpty && !failed.contains(region.id) {
                            Text("\u{2026}").kjSmall(faint: true)
                        } else if failed.contains(region.id) && live.isEmpty {
                            Text("These cameras did not load.").kjSmall(faint: true)
                        } else if !live.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(live) { channel in
                                    Button { model.tuner.play(channel, in: live) } label: {
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
        .onDisappear {
            guard let index = model.receiver.index else { return }
            for region in CameraRegions.ordered(index) {
                model.receiver.cancelChannels(regionId: region.id, cameras: true)
            }
        }
    }

    private func load(_ region: String) async {
        guard lists[region] == nil else { return }
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            do {
                _ = try await model.receiver.channels(regionId: region, cameras: true)
            } catch {
                if Task.isCancelled { return }
                failed.insert(region)
                return
            }
            let rows = model.receiver.shown(regionId: region, cameras: true)
            if ReceiverRules.assignCameraList(shown: rows.map(\.id), walkFinished: model.receiver.walkFinished(regionId: region, cameras: true)) != nil {
                lists[region] = rows
                return
            }
            guard ReceiverRules.shouldRetryUnfinishedWalk(attempt: attempt, unprobed: 1) else { return }
            try? await Task.sleep(for: .seconds(ReceiverRules.unfinishedWalkDelay()))
        }
    }
}
