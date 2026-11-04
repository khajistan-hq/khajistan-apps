import SwiftUI

/// The receiver's front, and the front is the map. At left, what the receiver is and how much is
/// on air; at right, the regions to open. The switch under the figures widens the map beyond the
/// atlas.
struct ReceiverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var composed: ComposedMap?
    @State private var mapError: String?
    /// Each camera region's cameras to take a still from, and the ones asked for now.
    @State private var cameraPicks: [String: [Channel]] = [:]
    @State private var cameraWanted: [Channel] = []
    @State private var shuffled: ShufflePick?
    @State private var shuffling = false
    @State private var surfTask: Task<Void, Never>?
    @State private var surfRevision = 0
    @AppStorage(ShuffleMedium.key) private var mediumRaw = ShuffleMedium.all.rawValue
    @AppStorage(SurfGenre.key) private var genreRaw = SurfGenre.any.rawValue
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
            ReceiverPlayerView(channel: pick.channel, list: pick.list, surfChoice: pick.surfChoice)
        }
        .onDisappear { cancelSurf() }
        .onChange(of: mediumRaw) { cancelSurf() }
        .onChange(of: genreRaw) { cancelSurf() }
        .onChange(of: model.extendedAtlas) { cancelSurf() }
        .onChange(of: model.receiverPath) { cancelSurf() }
        // The id restarts the load when the switch moves, so the map follows it.
        .task(id: model.extendedAtlas) { await load() }
        // Nothing plays until it is chosen (owner, 2026-10-29: "it goes straight to playing a
        // channel, which is not what I want. I need to be able to select a channel and then play
        // it"). Surf is focused at launch, so a channel is still one press away.
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
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Two bands, owner 2026-10-29 ("symmetrically ... make the map bigger"): the
                    // sidebar beside the map, then the region cards across the full width, on
                    // the same grid as the shelves under them.
                    AtlasPanel(composed: composed, mapError: mapError, failure: { AnyView(failure($0)) }, open: open,
                               leading: AnyView(sidebar(index)),
                               // Focus on the strip: the strip at the foot of the screen and the
                               // map above it, so the region it lights is in view, never a sliver
                               // of the map under the top bar.
                               stripFocused: { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(AtlasPanel.stripAnchor, anchor: .bottom) } })
                        .padding(.bottom, 12)
                    HomeSections()
                    camerasRow(index)
                    filmsRow
                    HomeRows()
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.top, 32)
                .padding(.bottom, KJLayout.inset)
            }
            // The page runs to the screen's edge, so the first shelf peeks under the front
            // instead of being cut flat at the safe-area line.
            .ignoresSafeArea(.container, edges: .bottom)
            }
            .kjTopFade()
            .defaultFocus($surfFocused, true)
            // Back from deep in the front (a shelf, the strip) goes to Surf first; Back from
            // Surf leaves the app, as tvOS does from a root screen.
            .onExitCommand(perform: surfFocused ? nil : { surfFocused = true })
        } else if let message = model.receiver.indexError {
            failure(message)
        } else {
            TuningLoader("Loading the receiver\u{2026}")
        }
    }

    // MARK: - Sidebar

    private func sidebar(_ index: ReceiverIndex) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            // Less to read (owner, 2026-10-29: "simplified its too much text"): the name, Surf,
            // one count and the switch. The pictures are under the map.
            Text("Receiver")
                .kjDisplay()
            surf
            Figure(label: "Live now", value: figure(index.totals.live))
            HouseSwitch(title: "Beyond the atlas", detail: "More places, from the Balkans to Indonesia", isOn: extendedBinding)
                .accessibilityIdentifier("beyondTheAtlas")
                // The plate's padding is pulled back so the switch sits on the page margin.
                .padding(.leading, -26)
        }
        // The strip runs under it now, so a press up from the strip reaches the switch.
        .frame(width: 520, alignment: .leading)
        .focusSection()
    }

    private func figure(_ count: Int?) -> String {
        (count ?? 0).formatted()
    }

    private var extendedBinding: Binding<Bool> {
        Binding(
            get: { model.extendedAtlas },
            set: {
                model.extendedAtlas = $0
            }
        )
    }

    // MARK: - Surf

    /// A live channel at random, one press from the front (owner, 2026-10-06: "easily accessible
    /// channel shuffle button in the home page"), of the medium and from the part of the atlas
    /// chosen under it, kept on the device as the phone keeps them (owner, 2026-10-07). Up and down
    /// then surf every channel of that choice (owner, 2026-10-29: "true surf").
    /// Called Surf, as the website's receiver and the phone call it.
    private var surf: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                surfTask = Task { await shuffle() }
            } label: {
                // The shuffle mark says what Surf does before the word has been learnt.
                Label(shuffling ? "Surfing\u{2026}" : "Surf", systemImage: "shuffle").kjKicker()
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
            chips(SurfGenre.allCases.map { ($0.rawValue, $0.label) }, current: genreRaw, id: "surf-genre") { genreRaw = $0 }
            if let surfNote { Text(surfNote).kjSmall(faint: true) }
        }
    }

    private var medium: ShuffleMedium { .stored(mediumRaw) }
    private var genre: SurfGenre { .stored(genreRaw) }
    private var choiceNow: SurfChoice { SurfChoice(medium: medium, scope: scope, genre: genre) }

    /// Surf follows the Beyond the atlas switch: the atlas when it is off, everywhere when it is on.
    /// One control for both (owner, 2026-10-29), where the front had a switch and a row of chips.
    private var scope: ShuffleScope { model.extendedAtlas ? .everywhere : .main }

    private func chips(_ items: [(String, String)], current: String, id: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button {
                    set(item.0)
                } label: { Text(item.1).kjKicker() }
                    .buttonStyle(HouseTabStyle(isCurrent: item.0 == current))
                    .accessibilityIdentifier("\(id)-\(item.0)")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
    }

    private func shuffle() async {
        guard let index = model.receiver.index, !shuffling, !Task.isCancelled, model.receiverPath.isEmpty else { return }
        surfRevision += 1
        let revision = surfRevision
        shuffling = true
        surfNote = nil
        defer { if revision == surfRevision { shuffling = false } }
        let choice = choiceNow
        let catalogue = await ShufflePick.catalogue(index, medium: choice.medium, scope: choice.scope, genre: choice.genre) { region in
            try? await model.receiver.channels(regionId: region, cameras: false)
        }
        guard !Task.isCancelled, revision == surfRevision, model.receiverPath.isEmpty,
              choice == choiceNow else { return }
        model.surfHistory.update(catalogue, for: choice)
        if let channel = model.surfHistory.next(for: choice) {
            if !catalogue.isComplete { surfNote = "Some atlas lists could not load. Surf will retry them next time." }
            shuffled = ShufflePick(channel: channel, list: catalogue.channels, surfChoice: choice)
            return
        }
        surfNote = catalogue.isComplete ? "Nothing to surf there right now." : "You have visited the available channels. Try Surf again to load the rest of the atlas."
    }

    private func cancelSurf() {
        surfRevision += 1
        surfTask?.cancel()
        surfTask = nil
        shuffling = false
    }

    // MARK: - Cameras

    /// Every region with public cameras, main atlas first, each opening its page on its cameras
    /// (owner, 2026-10-07: "make cctv show up in the reciever").
    @ViewBuilder
    private func camerasRow(_ index: ReceiverIndex) -> some View {
        let regions = CameraRegions.ordered(index)
        if !regions.isEmpty {
            Shelf("Street cameras", count: "\(CameraRegions.total(index).formatted()) live, by region") {
                ForEach(regions) { region in
                    Button {
                        model.camerasFirst = region.id
                        model.receiverPath.append(region)
                    } label: {
                        // The region's name over a still from one of its cameras, taken on this
                        // device as the region cards' are (owner, 2026-10-29: pictures on them).
                        PictureCard(title: region.label,
                                    still: (cameraPicks[region.id] ?? []).lazy.compactMap { model.stills.image(for: $0.id) }.first,
                                    width: ChannelCard.width, height: ChannelCard.height, symbol: "video")
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("cameras-\(region.id)")
                }
            }
            .accessibilityIdentifier("shelf-cameras")
            .task(id: regions.map(\.id)) { await pickCameras(regions) }
            // Back from a region page: the stills store forgot the list when the page went.
            .onAppear { model.stills.wantToo(cameraWanted) }
        }
    }

    /// Up to three cameras per region, and the stills for them: the first of each, then a spare
    /// only where the card is still a plate (a black frame or a dead stream).
    private func pickCameras(_ regions: [ReceiverIndex.Region]) async {
        for region in regions where cameraPicks[region.id] == nil {
            guard !Task.isCancelled else { return }
            let cameras = (try? await model.receiver.channels(regionId: region.id, cameras: true)) ?? []
            cameraPicks[region.id] = Array(cameras.prefix(3))
        }
        for rank in 0..<3 {
            guard !Task.isCancelled else { return }
            let lacking = regions.filter { region in
                !(cameraPicks[region.id] ?? []).contains { model.stills.image(for: $0.id) != nil }
            }
            cameraWanted = lacking.compactMap { cameraPicks[$0.id]?.dropFirst(rank).first }
            if cameraWanted.isEmpty { return }
            model.stills.wantToo(cameraWanted)
            try? await Task.sleep(for: .seconds(Double(cameraWanted.count) * 4))
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
    /// The sidebar, beside the map.
    let leading: AnyView
    /// Called as focus comes onto the region strip from elsewhere.
    var stripFocused: () -> Void = {}
    static let stripAnchor = "atlasStrip"
    @Environment(AppModel.self) private var model
    @FocusState private var focusedRegion: String?
    /// The region lit in the A–Z list at the right of the map. Its own focus state: the strip and
    /// the list both carry every region, and one value bound to both is ambiguous.
    @FocusState private var listedRegion: String?
    /// Up to three television channels per region, by region id: the card shows the first whose
    /// still has come.
    @State private var picks: [String: [Channel]] = [:]
    /// The picks west to east: what the front asks stills for.
    @State private var wanted: [Channel] = []

    var body: some View {
        Group {
            if let mapError {
                HStack(alignment: .center, spacing: 40) { leading; failure(mapError) }
            } else if let composed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 40) {
                        leading
                        RegionMapView(map: composed, highlighted: listedRegion ?? focusedRegion)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.mapHeight)
                        regionList(composed)
                    }

                    regionStrip(composed).id(Self.stripAnchor)
                }
                // Room for a focused plate's lift at the top edge.
                .padding(.top, 8)
            } else {
                HStack(alignment: .center, spacing: 40) {
                    leading
                    TuningLoader("Loading the receiver\u{2026}")
                        .frame(maxWidth: .infinity, minHeight: Self.mapHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusSection()
        .defaultFocus($focusedRegion, "indus")
        .onChange(of: focusedRegion == nil) { _, left in if !left { stripFocused() } }
        // Back from a region page starts a fresh share and asks again for what was wanted.
        .onAppear { model.stills.beginVisit(); model.stills.want(wanted) }
        .onDisappear { model.stills.endVisit() }
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
    /// Each is a picture card (owner, 2026-10-29: "visual hook like the posters of screening room"):
    /// the region's name over a still of one of its television channels, taken on this device as
    /// the region page takes them. A region with no still yet, or no television, shows its name.
    private func regionStrip(_ map: ComposedMap) -> some View {
        let regions = map.regions
            .filter(\.opensChannels)
            .sorted { ($0.centroid.x, $0.centroid.y) < ($1.centroid.x, $1.centroid.y) }
        return ScrollView(.horizontal, showsIndicators: false) {
            // The shelves' grid: their card size and spacing, so the columns line up.
            LazyHStack(spacing: 32) {
                ForEach(regions) { region in
                    Button {
                        open(region)
                    } label: {
                        PictureCard(title: region.label,
                                    still: (picks[region.id] ?? []).lazy.compactMap { model.stills.image(for: $0.id) }.first,
                                    width: Self.cardWidth, height: Self.cardHeight)
                    }
                    .buttonStyle(HouseCardStyle())
                    .focused($focusedRegion, equals: region.id)
                    .accessibilityIdentifier("region-\(region.id)")
                    .accessibilityLabel(region.label)
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .frame(height: Self.cardHeight + 80)
        .task(id: regions.map(\.id)) { await pick(regions) }
    }

    /// Every region that opens channels, A to Z, at the right of the map (Joey, 2026-11-02: "a
    /// list on the right side of the screen that when you scroll down and highlight it,
    /// highlights that particular region"). A name lit here lights its shape on the map; Select
    /// opens the region's page, its television and its radio on shelves of their own.
    /// It repeats the picture strip under the map on purpose: asked whether to drop the strip, the
    /// owner chose to keep both (2026-11-03).
    private func regionList(_ map: ComposedMap) -> some View {
        let regions = map.regions
            .filter(\.opensChannels)
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 8) {
            Kicker("Regions A\u{2013}Z")
            ScrollView(.vertical, showsIndicators: false) {
                // Not lazy: tens of rows, and every one must exist for the remote and for tests.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(regions) { region in
                        Button {
                            open(region)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(region.label).kjName(28).lineLimit(1)
                                Spacer(minLength: 8)
                                if let live = region.live, live > 0 {
                                    Text(live.formatted()).kjSmall(faint: true).monospacedDigit()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                        .focused($listedRegion, equals: region.id)
                        .accessibilityIdentifier("regionList-\(region.id)")
                        .accessibilityLabel(region.label)
                        .accessibilityValue(region.live.map { "\($0) live" } ?? "")
                    }
                }
                // Room inside the clip for a focused row's lift.
                .padding(12)
            }
            .padding(-12)
        }
        .frame(width: Self.listWidth, height: Self.mapHeight, alignment: .topLeading)
        .focusSection()
        .accessibilityIdentifier("regionList")
    }

    static let listWidth: CGFloat = 320
    static let cardWidth = ChannelCard.width
    static let cardHeight = ChannelCard.height
    /// Was 520 beside a 560-point sidebar, with the strip under the map only.
    static let mapHeight: CGFloat = 640

    /// One television channel per region, west to east, and the stills for them. The lists are the
    /// region shards the region page reads, so opening a region afterwards reads nothing new.
    private func pick(_ regions: [MapRegion]) async {
        for region in regions where picks[region.id] == nil {
            guard !Task.isCancelled else { return }
            let channels = (try? await model.receiver.channels(regionId: region.id, cameras: false)) ?? []
            picks[region.id] = Array(channels.filter { $0.mediaType == "tv" }.prefix(6))
        }
        // First choices, then a spare only for a region whose card is still a plate (a black frame
        // or a dead stream), so no still is spent on a region that already has a picture.
        for rank in 0..<6 {
            guard !Task.isCancelled else { return }
            let lacking = regions.filter { region in
                !(picks[region.id] ?? []).contains { model.stills.image(for: $0.id) != nil }
            }
            wanted = lacking.compactMap { picks[$0.id]?.dropFirst(rank).first }
            if wanted.isEmpty { return }
            model.stills.want(wanted)
            // The plan takes one still every 1.5 s at most and gives each up to 10 s.
            try? await Task.sleep(for: .seconds(Double(wanted.count) * 4))
        }
    }
}
