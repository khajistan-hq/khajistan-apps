import SwiftUI

/// The receiver's front, and the front is the map. At left, what the receiver is and how much is
/// on air; at right, the regions to open. The switch under the figures widens the map beyond the
/// atlas.
struct ReceiverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var composed: ComposedMap?
    @State private var mapError: String?
    @State private var shuffled: ShufflePick?
    @State private var shuffling = false
    @AppStorage(ShuffleMedium.key) private var mediumRaw = ShuffleMedium.tv.rawValue
    @AppStorage(ShuffleScope.key) private var scopeRaw = ShuffleScope.main.rawValue
    @State private var surfNote: String?
    /// The front opens with Surf focused: one press to a picture (owner, 2026-10-08).
    @FocusState private var surfFocused: Bool
    /// Once per launch: coming back from a region keeps the focus on the region.
    @State private var surfFocusedAtLaunch = false

    var body: some View {
        @Bindable var model = model
        return NavigationStack(path: $model.receiverPath) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.ground.ignoresSafeArea())
                .foregroundStyle(palette.ink)
                .navigationDestination(for: ReceiverIndex.Region.self) { region in
                    ChannelsView(region: region, camerasFirst: model.camerasFirst == region.id)
                }
        }
        // The stack clips to the safe area too, so it runs to the edge with the front's scroll view.
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(item: $shuffled) { pick in
            ReceiverPlayerView(channel: pick.channel, list: pick.list)
        }
        // The id restarts the load when the switch moves, so the map follows it.
        .task(id: model.extendedAtlas) { await load() }
        // vod.json opens with the preview password, so a password entered later loads it.
        .task(id: model.auth.previewPassword) { await model.films.load() }
        // Read again when the index lands: a link that opened the app arrives before it.
        .task(id: PendingLink(link: model.link, indexReady: model.receiver.index != nil)) { follow(model.link) }
    }

    private struct PendingLink: Hashable {
        let link: DeepLink?
        let indexReady: Bool
    }

    /// A Top Shelf link: the receiver's front, or one region's page over it. A region link waits
    /// for the index; one the index does not list opens the front.
    private func follow(_ link: DeepLink?) {
        switch link {
        case .receiver:
            model.receiverPath = []
            model.link = nil
        case .region(let id):
            guard let index = model.receiver.index else { return }
            model.receiverPath = index.regions.first(where: { $0.id == id }).map { [$0] } ?? []
            model.link = nil
        default:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        if let index = model.receiver.index {
            // The page scrolls. First the front, the sidebar beside the map and its strip; then
            // the shelves, full width, as the TV app lays its rows. A press down from the strip
            // scrolls to them (owner, 2026-10-06: they "should expand into their contents on
            // home page", and "behave like apple tv native films/tv app").
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 60) {
                        sidebar(index)
                        mapArea
                    }
                    .padding(.bottom, 12)
                    camerasRow(index)
                    filmsRow
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.top, 32)
                .padding(.bottom, KJLayout.inset)
            }
            // The page runs to the screen's edge, so the first shelf peeks under the front
            // instead of being cut flat at the safe-area line.
            .ignoresSafeArea(.container, edges: .bottom)
            .kjTopFade()
            .defaultFocus($surfFocused, true)
        } else if let message = model.receiver.indexError {
            failure(message)
        } else {
            TuningLoader("Loading the receiver\u{2026}")
        }
    }

    // MARK: - Sidebar

    private func sidebar(_ index: ReceiverIndex) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Receiver")
                .kjDisplay()
            Text("Live television, live radio and public cameras from the Middle World.")
                .kjBody()
            surf
            Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 20) {
                GridRow {
                    Figure(label: "Live now", value: figure(index.totals.live))
                    Figure(label: "Television", value: figure(index.totals.byMedium["tv"]))
                }
                GridRow {
                    Figure(label: "Radio", value: figure(index.totals.byMedium["radio"]))
                    Figure(label: "Cameras", value: figure(index.totals.byMedium["camera"]))
                }
            }
            HouseSwitch(title: "Beyond the atlas", detail: "The wider Islamicate, Rumelia to Nusantara", isOn: extendedBinding)
                .accessibilityIdentifier("beyondTheAtlas")
                // The plate's padding is pulled back so the switch sits on the page margin.
                .padding(.leading, -26)
        }
        // Full height, so the focus section reaches down beside the region strip: a press left
        // off the strip's west end lands on the switch. Sized to its content it ended above
        // the strip, and the switch could not be reached with the remote at all.
        .frame(width: 560, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
    }

    private func figure(_ count: Int?) -> String {
        (count ?? 0).formatted()
    }

    private var extendedBinding: Binding<Bool> {
        Binding(
            get: { model.extendedAtlas },
            set: { model.extendedAtlas = $0 }
        )
    }

    // MARK: - Map

    private var mapArea: some View {
        AtlasPanel(composed: composed, mapError: mapError, failure: { AnyView(failure($0)) }, open: open)
    }

    // MARK: - Surf

    /// A live channel at random, one press from the front (owner, 2026-10-06: "easily accessible
    /// channel shuffle button in the home page"), of the medium and from the part of the atlas
    /// chosen under it, kept on the device as the phone keeps them (owner, 2026-10-07). The region
    /// is drawn by how many channels of that medium it carries; up and down then surf that region.
    /// Called Surf, as the website's receiver and the phone call it.
    private var surf: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await shuffle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(shuffling ? "Surfing\u{2026}" : "Surf").kjKicker()
                    Text(surfLine).kjSmall(faint: true)
                }
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 26, bottom: 14, trailing: 26)))
            .focused($surfFocused)
            // The top bar and the strip each claim the first focus; this one is placed last.
            .task {
                guard !surfFocusedAtLaunch, model.receiverPath.isEmpty else { return }
                surfFocusedAtLaunch = true
                try? await Task.sleep(for: .milliseconds(300))
                surfFocused = true
            }
            .accessibilityIdentifier("shuffle")
            .disabled(shuffling || model.receiver.index == nil)
            // The plate's padding is pulled back so the label sits on the page margin.
            .padding(.leading, -26)
            chips(ShuffleMedium.allCases.map { ($0.rawValue, $0.label) }, current: mediumRaw, id: "shuffle-medium") { mediumRaw = $0 }
            // "Main atlas · Extended atlas · Everywhere" is wider than the sidebar; the line above
            // says "atlas", so the chips can drop it.
            chips(ShuffleScope.allCases.map { ($0.rawValue, $0.label.replacingOccurrences(of: " atlas", with: "")) },
                  current: scopeRaw, id: "shuffle-scope") { scopeRaw = $0 }
            if let surfNote { Text(surfNote).kjSmall(faint: true) }
        }
    }

    private var medium: ShuffleMedium { ShuffleMedium(rawValue: mediumRaw) ?? .tv }

    /// One line that fits the sidebar; the chips under it say which medium and which atlas.
    private let surfLine = "A live channel at random from the atlas"
    private var scope: ShuffleScope { ShuffleScope(rawValue: scopeRaw) ?? .main }

    private func chips(_ items: [(String, String)], current: String, id: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button { set(item.0) } label: { Text(item.1).kjKicker() }
                    .buttonStyle(HouseTabStyle(isCurrent: item.0 == current))
                    .accessibilityIdentifier("\(id)-\(item.0)")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
    }

    private func shuffle() async {
        guard let index = model.receiver.index, !shuffling else { return }
        shuffling = true
        surfNote = nil
        defer { shuffling = false }
        let weights = ShufflePick.weights(index, medium: medium, scope: scope)
        // Up to three regions, in case one's list will not load.
        for _ in 0..<3 {
            guard let region = ShufflePick.region(weights) else { break }
            guard let list = try? await model.receiver.channels(regionId: region, cameras: false) else { continue }
            let pool = list.filter { $0.mediaType == medium.rawValue }
            if let channel = pool.randomElement() {
                shuffled = ShufflePick(channel: channel, list: pool)
                return
            }
        }
        surfNote = "Nothing to surf there right now."
    }

    // MARK: - Cameras

    /// Every region with public cameras, main atlas first, each opening its page on its cameras
    /// (owner, 2026-10-07: "make cctv show up in the reciever").
    @ViewBuilder
    private func camerasRow(_ index: ReceiverIndex) -> some View {
        let regions = CameraRegions.ordered(index)
        if !regions.isEmpty {
            Shelf("Cameras", count: "\(CameraRegions.total(index).formatted()) in \(regions.count) regions") {
                ForEach(regions) { region in
                    Button {
                        model.camerasFirst = region.id
                        model.receiverPath.append(region)
                    } label: {
                        CardPlate(width: ChannelCard.width, height: ChannelCard.height) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(region.label).kjName().lineLimit(2)
                                Spacer(minLength: 0)
                                if let count = index.regionCounts[region.id]?.byMedium["camera"] {
                                    Text("\(count.formatted()) \(count == 1 ? "camera" : "cameras")").kjSmall(faint: true)
                                }
                            }
                        }
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("cameras-\(region.id)")
                }
            }
            .accessibilityIdentifier("shelf-cameras")
        }
    }

    // MARK: - The Screening Room

    /// The Screening Room, every film as the site's On Demand carries them, on a shelf of posters.
    @ViewBuilder
    private var filmsRow: some View {
        let films = model.films.films
        if !films.isEmpty {
            FilmShelf(
                title: "The Screening Room",
                count: "\(films.count) \(films.count == 1 ? "film" : "films") on demand",
                films: films
            )
            .accessibilityIdentifier("screeningRoom")
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 28) {
            Text(message)
                .kjBody()
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("Try again").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opens a region from the strip. The region is the index's own line for it; a map shape the
    /// index has no line for is still opened, as what the map says it is.
    private func open(_ mapRegion: MapRegion) {
        guard let index = model.receiver.index else { return }
        let region = index.regions.first { $0.id == mapRegion.id }
            ?? ReceiverIndex.Region(
                id: mapRegion.id, label: mapRegion.label,
                kind: mapRegion.isPeople ? "people" : "state",
                tier: mapRegion.isExtension ? "islamicate" : "core"
            )
        model.receiverPath.append(region)
    }

    // MARK: - Loading

    private func load() async {
        await model.receiver.loadIndex()
        if Task.isCancelled { return }
        guard model.receiver.index != nil else { return }
        await loadMap()
    }

    /// Fetches the shapes the switch calls for and composes them with the index. A map already on
    /// screen stays until its replacement is ready; composing runs off the main actor.
    private func loadMap() async {
        let extended = model.extendedAtlas
        mapError = nil
        do {
            let shapes = try await model.receiver.mapShapes(extended: extended)
            guard let index = model.receiver.index else { return }
            let map = await Task.detached(priority: .userInitiated) {
                RegionMapRules.compose(core: shapes.core, extended: shapes.extended, index: index, showExtensions: extended)
            }.value
            if Task.isCancelled { return }
            if let map {
                composed = map
            } else {
                mapError = "The receiver sent a map that could not be read."
            }
        } catch {
            if Task.isCancelled { return }
            mapError = error.localizedDescription
        }
    }
}

/// The map and the strip of regions under it, with the strip's focus. Kept in a view of its own
/// so a step along the strip re-evaluates only this, not the whole front with its shelves of
/// cards (2026-10-06: every step re-evaluated the page, measured as late frames on the owner's
/// Apple TV HD).
private struct AtlasPanel: View {
    let composed: ComposedMap?
    let mapError: String?
    let failure: (String) -> AnyView
    let open: (MapRegion) -> Void
    @FocusState private var focusedRegion: String?

    var body: some View {
        Group {
            if let mapError {
                failure(mapError)
            } else if let composed {
                VStack(alignment: .leading, spacing: 24) {
                    RegionMapView(map: composed, highlighted: focusedRegion)
                        .frame(height: 600)
                    regionStrip(composed)
                }
                // Room for a focused plate's lift at the top edge.
                .padding(.top, 8)
            } else {
                TuningLoader("Loading the receiver\u{2026}")
                    .frame(maxWidth: .infinity, minHeight: 600)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusSection()
        .defaultFocus($focusedRegion, "indus")
        #if DEBUG
        // `-kjautowalk YES` steps focus along the region strip, for measuring on a device with
        // no one at the remote (FrameMeter prints how many frames come late meanwhile).
        .task(id: composed == nil) {
            guard UserDefaults.standard.bool(forKey: "kjautowalk"), let composed else { return }
            let ids = composed.regions.filter(\.opensChannels)
                .sorted { ($0.centroid.x, $0.centroid.y) < ($1.centroid.x, $1.centroid.y) }.map(\.id)
            try? await Task.sleep(for: .seconds(4))
            print("KJWALK start")
            for id in ids + ids.reversed() {
                focusedRegion = id
                try? await Task.sleep(for: .milliseconds(300))
            }
            print("KJWALK end")
        }
        #endif
    }

    /// Every region that opens channels, west to east by where it sits on the map, so a press
    /// right on the remote moves east across the map. Focus here is what the map highlights.
    private func regionStrip(_ map: ComposedMap) -> some View {
        let regions = map.regions
            .filter(\.opensChannels)
            .sorted { ($0.centroid.x, $0.centroid.y) < ($1.centroid.x, $1.centroid.y) }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(regions) { region in
                    Button {
                        open(region)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(region.label).kjKicker()
                            if let live = region.live {
                                Text(live.formatted()).kjSmall(faint: true).monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)))
                    .focused($focusedRegion, equals: region.id)
                    .accessibilityIdentifier("region-\(region.id)")
                    .accessibilityLabel(region.live.map { "\(region.label), \($0) live" } ?? region.label)
                }
            }
            // The plates' padding is pulled back so the first label sits on the map's margin.
            .padding(.horizontal, -22)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        // Clipped on the left, so a strip scrolled east does not run over the sidebar.
        .mask {
            Rectangle().padding(.leading, -22).padding(.trailing, -200).padding(.vertical, -60)
        }
        .frame(height: 96)
    }
}
