import SwiftUI

/// The receiver's front, and the front is the map. At left, Surf, how much is on air and the switch
/// that widens the map beyond the atlas; at right, the regions A to Z. The shelves follow under it.
/// Simplified on 2026-11-17 (owner, "simplify home page", choices made that day): no RECEIVER title,
/// as the top bar names the section; one row of Surf choices; the regions once as a list, with the
/// map lit for the name focused, where the picture strip under the map repeated them a third time.
struct ReceiverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var composed: ComposedMap?
    @State private var mapError: String?
    @State private var shuffled: ShufflePick?
    @State private var shuffling = false
    @State private var surfTask: Task<Void, Never>?
    @State private var surfRevision = 0
    @AppStorage(ShuffleMedium.key) private var mediumRaw = ShuffleMedium.all.rawValue
    @State private var surfNote: String?
    /// The front opens with Surf focused: one press to a picture (owner, 2026-10-08).
    @FocusState private var surfFocused: Bool
    /// The switch over the map, where Up from the first shelf lands.
    @FocusState private var switchFocused: Bool
    /// Focus is on the All · TV · Radio row. Set only as focus enters or leaves the row (ChipRow),
    /// so a step along it does not re-run the front.
    @State private var chipsFocused = false

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
        .kjFullScreenCover(item: $shuffled) { pick in
            ReceiverPlayerView(channel: pick.channel, list: pick.list, surfChoice: pick.surfChoice)
        }
        .onDisappear { cancelSurf() }
        .onChange(of: mediumRaw) { cancelSurf() }
        .onChange(of: model.extendedAtlas) { cancelSurf() }
        .onChange(of: model.receiverPath) { cancelSurf() }
        // The id restarts the load when the switch moves, so the map follows it, and when the
        // preview password changes, which decides whether the whole dial is served.
        .task(id: DialKey(extended: model.extendedAtlas, password: model.auth.previewPassword)) { await load() }
        // Nothing plays until it is chosen (owner, 2026-10-29: "it goes straight to playing a
        // channel, which is not what I want. I need to be able to select a channel and then play
        // it"). Surf is focused at launch, so a channel is still one press away.
        // vod.json opens with the preview password, so a password entered later loads it.
        .task(id: model.auth.previewPassword) { await model.films.load() }
        // Read again when the index lands: a link that opened the app arrives before it.
        .task(id: PendingLink(link: model.link, indexReady: model.receiver.index != nil)) { follow(model.link) }
    }

    private struct DialKey: Hashable {
        let extended: Bool
        let password: String?
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
            // The front opens at its top, not on the CCTV name that opened the region.
            model.camerasFirst = nil
            model.link = nil
        case .region(let id):
            guard let index = model.receiver.index else { return }
            // A linked region opens on its television, and Back from it is not a CCTV return.
            model.camerasFirst = nil
            model.receiverPath = index.regions.first(where: { $0.id == id }).map { [$0] } ?? []
            model.link = nil
        default:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        if let index = model.receiver.index {
            // The page scrolls. First the front, the sidebar beside the map and the list; then
            // the shelves, full width, as the TV app lays its rows. A press down from the front
            // scrolls to them (owner, 2026-10-06: they "should expand into their contents on
            // home page", and "behave like apple tv native films/tv app").
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                    AtlasPanel(composed: composed, mapError: mapError, failure: { AnyView(failure($0)) }, open: open,
                               leading: AnyView(sidebar(index)),
                               aboveMap: AnyView(atlasSwitch),
                               // Focus in the list: the page back at its top, so the map the list
                               // lights is whole, never a sliver under the top bar.
                               listFocused: { toTop(proxy) })
                        // Up from a shelf lands on Surf, whichever column it came from, so one
                        // more Up reaches the top bar. From the right-hand shelves it entered the
                        // A–Z list at Turkistan and walked all twelve rows first, which read on
                        // the Apple TV as Up never reaching the bar (owner, 2026-11-18: "no way
                        // to go to the nav"). Down from the bar lands on Surf as before.
                        .focusSection()
                        .defaultFocus($surfFocused, true, priority: .userInitiated)
                        .padding(.bottom, 12)
                    }
                    ThemeRow()
                    // Transmission and the Screening Room are not shelves here: each has its own
                    // door in the top bar (owner, 2026-11-19: "remov khajistan transmission and
                    // screening room from the home page of the apple tv").
                    HomeRows()
                    // Shelves above it arrive on their own fetches after it is drawn, so a name
                    // focused early is kept on screen as they push it down.
                    CCTVRow(index: index) {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(CCTVRow.anchor, anchor: .bottom) }
                    }
                    // Last on the page (owner, 2026-11-21: "put liked video at the botton of the
                    // page"). No likes, no shelf; its 12 points on top of the stack's 12 are kept
                    // off with -12, so it sits as any other shelf does.
                    LikedShelf().padding(.top, -12)
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.top, 32)
                .padding(.bottom, KJLayout.inset)
                // On the page's whole content, padding included: scrolled to, the page sits
                // exactly as it opened, with no step of the top padding.
                .id(AtlasPanel.topAnchor)
                .environment(\.shelfRaise) { anchor in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            // The page runs to the screen's edge, so the first shelf peeks under the front
            // instead of being cut flat at the safe-area line.
            .ignoresSafeArea(.container, edges: .bottom)
            // Up from the first shelf and Back both land on Surf (owner, 2026-11-18), and Down from
            // Surf reaches the switch over the map: the page back at its top for any of them, and
            // for the sidebar's chips, so the front is never left half under the bar.
            .onChange(of: surfFocused || switchFocused || chipsFocused) { _, onFront in if onFront { toTop(proxy) } }
            }
            .kjTopFade()
            // Launch focus. The front's own default (above) is for focus coming back in from the
            // shelves; this one places the first focus of the screen.
            .defaultFocus($surfFocused, true)
            // Back from deep in the front (a shelf, the list) goes to Surf first; Back from
            // Surf leaves the app, as tvOS does from a root screen. With the PiP window up, Back
            // goes on to the bar (PiPBarHost): this handler only hears Back while focus is on the
            // front, so the bar is not lit then.
            .onExitCommand(perform: surfFocused || model.activePiP != nil ? nil : { surfFocused = true })
        } else if let message = model.receiver.indexError {
            failure(message)
        } else {
            TuningLoader("Loading the receiver\u{2026}")
        }
    }

    // MARK: - Sidebar

    private func sidebar(_ index: ReceiverIndex) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            // Less to read (owner, 2026-10-29: "simplified its too much text", and 2026-11-17):
            // Surf and one count; the switch is over the map. The top bar already names the Receiver.
            surf
            Figure(label: "Live now", value: figure(index.totals.live))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("receiverLiveNow")
            if let note = model.receiver.signInNote {
                Text(note).kjBody()
                    .accessibilityIdentifier("receiverSignInNote")
            }
        }
        .frame(width: 520, alignment: .leading)
        .focusSection()
    }

    /// Above the map it widens (owner, 2026-11-20: "make the beyond the atlas above the map"), as
    /// the website's switch sits above its atlas. It was at the foot of the sidebar until then.
    private var atlasSwitch: some View {
        HouseSwitch(title: "Beyond the atlas", detail: nil, isOn: extendedBinding)
            .focused($switchFocused)
            .accessibilityIdentifier("beyondTheAtlas")
            // The plate's padding is pulled back so the switch lines up with the map's edge.
            .padding(.leading, -26)
            .frame(height: AtlasPanel.switchRow, alignment: .topLeading)
    }

    private func toTop(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(AtlasPanel.topAnchor, anchor: .top) }
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
            // The top bar and the list each claim the first focus; this one is placed last. Not
            // under the welcome: it waits for the welcome to close, or focus is lost under it.
            .task(id: model.welcomeOnScreen) {
                guard !model.welcomeOnScreen, !model.surfFocusedOnce, model.receiverPath.isEmpty else { return }
                model.surfFocusedOnce = true
                try? await Task.sleep(for: .milliseconds(300))
                surfFocused = true
            }
            .accessibilityIdentifier("shuffle")
            .disabled(shuffling || model.receiver.index == nil)
            // The plate's padding is pulled back so the label sits on the page margin.
            .padding(.leading, -26)
            // One row (owner, 2026-11-17). The genre row went: Music and Film & drama are shelves
            // under the front, and their player surfs that genre with up and down.
            chips(ShuffleMedium.allCases.map { ($0.rawValue, Self.shortLabel($0)) }, current: mediumRaw, id: "shuffle-medium") { mediumRaw = $0 }
            if let surfNote { Text(surfNote).kjSmall(faint: true) }
        }
    }

    private var medium: ShuffleMedium { .stored(mediumRaw) }
    /// Any genre, always: a genre kept on the device from the old genre row has no chip left to
    /// show it, and must not narrow Surf unseen.
    private var choiceNow: SurfChoice { SurfChoice(medium: medium, scope: scope, genre: .any) }

    /// The chips' words on the front: TV and Radio, as the row says only the one thing.
    private static func shortLabel(_ medium: ShuffleMedium) -> String {
        switch medium {
        case .all: return "All"
        case .tv: return "TV"
        case .radio: return "Radio"
        }
    }

    /// Surf follows the Beyond the atlas switch: the atlas when it is off, everywhere when it is on.
    /// One control for both (owner, 2026-10-29), where the front had a switch and a row of chips.
    private var scope: ShuffleScope { model.extendedAtlas ? .everywhere : .main }

    private func chips(_ items: [(String, String)], current: String, id: String, set: @escaping (String) -> Void) -> some View {
        ChipRow(items: items, current: current, id: id, set: set) { chipsFocused = $0 }
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

    /// Opens a region from the list. The region is the index's own line for it; a map shape the
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

/// The map and the A–Z list of regions beside it, with the list's focus. Kept in a view of its own
/// so a step along the list re-evaluates only this, not the whole front with its shelves of cards
/// (2026-10-06: every step re-evaluated the page, measured as late frames on the owner's Apple TV HD).
private struct AtlasPanel: View {
    let composed: ComposedMap?
    let mapError: String?
    let failure: (String) -> AnyView
    let open: (MapRegion) -> Void
    /// The sidebar, beside the map.
    let leading: AnyView
    /// Over the map, in its column: the Beyond the atlas switch.
    var aboveMap: AnyView? = nil
    /// Called as focus comes into the region list from elsewhere.
    var listFocused: () -> Void = {}
    static let topAnchor = "atlasTop"
    @Environment(AppModel.self) private var model
    /// The region lit in the A–Z list. The map lights the same region.
    @FocusState private var listedRegion: String?

    var body: some View {
        Group {
            if let mapError {
                // The switch stays: a wider map that failed is put back by turning it off.
                HStack(alignment: .center, spacing: 40) {
                    leading
                    VStack(alignment: .leading, spacing: 24) {
                        if let aboveMap { aboveMap.focusSection() }
                        failure(mapError)
                    }
                }
            } else if let composed {
                // One top line: Surf level with the list's heading, the map's band beside them.
                HStack(alignment: .top, spacing: 40) {
                    leading
                    VStack(alignment: .leading, spacing: 0) {
                        if let aboveMap { aboveMap.focusSection() }
                    RegionMapView(map: composed, highlighted: listedRegion)
                        .frame(maxWidth: .infinity)
                        .frame(height: aboveMap == nil ? Self.mapHeight : Self.mapHeight - Self.switchRow)
                        // For the UI tests: the region the map lights, read as the map's value.
                        .accessibilityElement()
                        .accessibilityLabel("Map")
                        .accessibilityValue(composed.regions.first { $0.id == listedRegion }?.label ?? "")
                        .accessibilityIdentifier("atlasMap")
                    }
                    regionList(composed)
                }
                // Room for a focused plate's lift at the top edge.
                .padding(.top, 8)
            } else {
                HStack(alignment: .center, spacing: 40) {
                    leading
                    VStack(alignment: .leading, spacing: 0) {
                        if let aboveMap { aboveMap.focusSection() }
                        TuningLoader("Loading the receiver\u{2026}")
                            .frame(maxWidth: .infinity, minHeight: aboveMap == nil ? Self.mapHeight : Self.mapHeight - Self.switchRow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusSection()
        .onChange(of: listedRegion == nil) { _, left in if !left { listFocused() } }
        // Each visit to the front starts a fresh share of stills for the shelves under it.
        .onAppear { model.stills.beginVisit() }
        .onDisappear { model.stills.endVisit() }
        #if DEBUG
        // `-kjautowalk YES` steps focus down the region list and back, for measuring on a device
        // with no one at the remote (FrameMeter prints how many frames come late meanwhile).
        .task(id: composed == nil) {
            guard UserDefaults.standard.bool(forKey: "kjautowalk"), let composed else { return }
            let ids = Self.listed(composed).map(\.id)
            try? await Task.sleep(for: .seconds(4))
            print("KJWALK start")
            for id in ids + ids.reversed() {
                listedRegion = id
                try? await Task.sleep(for: .milliseconds(300))
            }
            print("KJWALK end")
        }
        #endif
    }

    /// Every region that opens channels, A to Z.
    private static func listed(_ map: ComposedMap) -> [MapRegion] {
        map.regions
            .filter(\.opensChannels)
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Every region that opens channels, A to Z, at the right of the map (Joey, 2026-11-02: "a
    /// list on the right side of the screen that when you scroll down and highlight it,
    /// highlights that particular region"). A name lit here lights its shape on the map; Select
    /// opens the region's page, its television and its radio on shelves of their own. It is the
    /// front's one way to a region (owner, 2026-11-17): the picture strip that ran under the map
    /// went, and the region page carries the pictures.
    private func regionList(_ map: ComposedMap) -> some View {
        let regions = Self.listed(map)
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
                        // 44 points a row: the atlas's twelve regions fit the map's band whole,
                        // with no last row cut flat at its foot (2026-11-17; rows 50 → 44 when the
                        // band went 640 → 580, 2026-11-20).
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)))
                        .focused($listedRegion, equals: region.id)
                        .accessibilityIdentifier("region-\(region.id)")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("regionList")
    }

    static let listWidth: CGFloat = 320
    static let mapHeight: CGFloat = 580
    /// The switch's row over the map: the map gives up this much, so the front keeps its height.
    static let switchRow: CGFloat = 80
}

/// Live channels by theme across the atlas, as one row of names with no pictures (owner,
/// 2026-11-18: the News-to-Children carousels "should be shown as not carousels but simpler way no
/// thumbnails more like themes that people can click and all channels with those themes play").
/// Select on a theme plays one of its channels at random, so a stream that is down is never the
/// only way in; up and down in the player surf every channel of that theme. The themes are the region lists' own `genres`; a channel sits under every theme it
/// is tagged for. The row follows the Beyond the atlas switch.
private struct ThemeRow: View {
    private struct Kind: Identifiable {
        let id: String
        let label: String
        let tags: Set<String>
    }

    private struct Row: Identifiable {
        let kind: Kind
        let channels: [Channel]
        var id: String { kind.id }
    }

    private struct Pick: Identifiable {
        let channel: Channel
        let list: [Channel]
        let title: String
        var id: String { channel.id }
    }

    /// News first (asked for by name), then music and film, then the rest.
    private static let kinds = [
        Kind(id: "news", label: "News", tags: ["news"]),
        Kind(id: "music", label: "Music", tags: ["music"]),
        Kind(id: "film", label: "Film & drama", tags: ["film", "drama"]),
        Kind(id: "faith", label: "Faith", tags: ["faith"]),
        Kind(id: "culture", label: "Culture", tags: ["culture"]),
        Kind(id: "sport", label: "Sport", tags: ["sport"]),
        Kind(id: "children", label: "Children", tags: ["children"]),
    ]
    /// A theme with fewer channels than this is not shown yet.
    private static let fewest = 3

    @Environment(AppModel.self) private var model
    /// The All / TV / Radio chips under Surf. A theme holds only what they let through (owner,
    /// 2026-11-25: "when only tv is selected surf and themes when clicked should only show tv,
    /// same for radio").
    @AppStorage(ShuffleMedium.key) private var mediumRaw = ShuffleMedium.all.rawValue
    @State private var rows: [Row] = []
    @State private var playing: Pick?
    /// Focus coming into the row lands on the theme last focused (Back from the player: the one
    /// pressed), or on News the first time, not on whichever sits under the control it came from.
    /// tvOS did not do either reliably by itself (HomeRowsUITests, 2026-11-18: the full build
    /// lost the theme pressed, the store build came up from CCTV onto another theme).
    @FocusState private var focused: String?
    @State private var lastFocused: String?

    var body: some View {
        // A stack, not a Group: with no rows yet there would be no child to carry the task.
        VStack(alignment: .leading, spacing: 8) {
            if !rows.isEmpty {
                Text("Themes").kjName(38)
                    .accessibilityAddTraits(.isHeader)
                // Scrolls sideways if the themes ever outgrow the screen; today they fit.
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows) { row in
                        Button {
                            play(row)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.kind.label).kjName(30).lineLimit(1)
                                Text("\(row.channels.count.formatted()) live").kjSmall(faint: true).monospacedDigit()
                            }
                        }
                        .buttonStyle(HouseButtonStyle())
                        // Play/Pause plays it too, as on Apple's TV app.
                        .onPlayPauseCommand { play(row) }
                        .focused($focused, equals: row.id)
                        .accessibilityLabel("\(row.kind.label), \(row.channels.count.formatted()) live")
                        .accessibilityIdentifier("genre-\(row.id)")
                    }
                }
                // Room over and under the row for a focused plate's lift.
                .padding(.vertical, 14)
                }
                .scrollClipDisabled()
                // The first plate's padding is pulled back so its text sits on the page margin.
                .padding(.leading, -26)
                .padding(.bottom, 14)
            }
        }
        .focusSection()
        // The priority makes tvOS apply the default to a move the remote makes: without it, Down
        // from the atlas switch (over the map since 2026-11-20) landed on Culture, the theme under
        // it. News the first time, then the theme last focused.
        .defaultFocus($focused, rows.contains { $0.id == lastFocused } ? lastFocused : rows.first?.id,
                      priority: .userInitiated)
        .onChange(of: focused) { _, now in if let now { lastFocused = now } }
        .task(id: "\(model.extendedAtlas) \(mediumRaw)") { await load() }
        .kjFullScreenCover(item: $playing) { pick in
            ReceiverPlayerView(channel: pick.channel, list: pick.list, listTitle: pick.title)
        }
    }

    private func play(_ row: Row) {
        guard let channel = row.channels.randomElement() else { return }
        playing = Pick(channel: channel, list: row.channels, title: row.kind.label)
    }

    /// Every region list in the atlas shown, read together (each is cached after its first read),
    /// then sorted into the themes in region order, each channel once per theme.
    private func load() async {
        guard let index = model.receiver.index else { return }
        let scope: ShuffleScope = model.extendedAtlas ? .everywhere : .main
        let ids = index.listedRegions.filter { scope.includes(tier: $0.tier) }.map(\.id)
        var lists: [String: [Channel]] = [:]
        await withTaskGroup(of: (String, [Channel]).self) { group in
            for id in ids {
                group.addTask { @MainActor in
                    (id, (try? await model.receiver.channels(regionId: id, cameras: false)) ?? [])
                }
            }
            for await (id, list) in group { lists[id] = list }
        }
        guard !Task.isCancelled else { return }
        let medium = ShuffleMedium.stored(mediumRaw)
        let channels = ids.flatMap { lists[$0] ?? [] }.filter { medium.includes($0.mediaType) }
        rows = Self.kinds.compactMap { kind in
            var seen = Set<String>()
            let shelf = channels.filter { channel in
                guard !Set((channel.genres ?? []).map { $0.lowercased() }).isDisjoint(with: kind.tags) else { return false }
                return seen.insert(channel.id).inserted
            }
            return shelf.count >= Self.fewest ? Row(kind: kind, channels: shelf) : nil
        }
    }
}

/// The channels the account liked, newest first, the last shelf on Home (owner, 2026-11-21: "put
/// liked video at the botton of the page"; it was the first under the map until then) (owner, 2026-11-08: "add liked channels on
/// homepage for an account so they are easily accessible"). The likes are the account's
/// `passport_saves`, the same the website's heart and the player's Like write, so a like made on
/// any device is here. Signed out, or with nothing liked, there is no shelf. Up and down in the
/// player surf the liked channels.
private struct LikedShelf: View {
    private struct Pick: Identifiable {
        let channel: Channel
        let list: [Channel]
        var id: String { channel.id }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Every ref a channel answers to, mapped to it, for the channels found so far.
    @State private var found: [String: Channel] = [:]
    /// Liked refs a full walk of the receiver did not find (off air, or gone), with when, kept on
    /// this device so a stale like does not cost a walk of every list at each launch. Looked for
    /// again after `missingFor`.
    @AppStorage("kj.likedMissing.v1") private var missingStore = ""
    /// The refs the last walk was asked for: a ref not among them is a new like, looked for at once.
    /// Nil until the first walk of a launch, whose refs are the account's, not new likes.
    @State private var lastRefs: Set<String>?
    private static let missingFor: TimeInterval = 6 * 3600

    private var missing: Set<String> {
        let now = Date().timeIntervalSince1970
        return Set(missingStore.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let at = TimeInterval(parts[0]), now - at < Self.missingFor else { return nil }
            return String(parts[1])
        })
    }

    private func unmarkMissing(_ refs: Set<String>) {
        missingStore = missingStore.split(separator: "\n").filter { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            return parts.count == 2 && !refs.contains(String(parts[1]))
        }.joined(separator: "\n")
    }

    private func markMissing(_ refs: Set<String>) {
        let now = Date().timeIntervalSince1970
        let kept = missingStore.split(separator: "\n").filter { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let at = TimeInterval(parts[0]) else { return false }
            return now - at < Self.missingFor && !refs.contains(String(parts[1]))
        }.map(String.init)
        missingStore = (kept + refs.map { "\(Int(now)) \($0)" }).joined(separator: "\n")
    }
    @State private var playing: Pick?

    /// The account's likes, newest first. A Debug build takes `-kjlikedrefs channel:a,channel:b`
    /// in their place, so the shelf can be seen and tested with no account signed in.
    private var refs: [String] {
        #if DEBUG
        if let given = UserDefaults.standard.string(forKey: "kjlikedrefs") {
            return given.split(separator: ",").map(String.init)
        }
        #endif
        return model.saves.likedChannelRefs
    }

    /// The liked channels the region lists still carry, newest like first, each once. A like of a
    /// channel taken off the receiver is not drawn.
    private var channels: [Channel] {
        var seen = Set<String>()
        return refs.compactMap { found[$0] }.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let list = channels
        // A stack, not a Group: a Group hands its modifiers to its children, and with no likes yet
        // there is no child, so the task that reads the likes would never run.
        VStack(alignment: .leading, spacing: 0) {
            if !list.isEmpty {
                // Names only, as the Themes row is (owner, 2026-11-21: "the liked channels should
                // also be text only like themes"): a plate a channel, its name and its place, no
                // picture. No heart: the row's name already says they are liked.
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Liked").kjName(38)
                    Text("\(list.count) live").kjSmall(faint: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("shelf-liked")
                .padding(.top, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(list) { channel in
                            Button {
                                playing = Pick(channel: channel, list: list)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.name).kjName(30).lineLimit(1)
                                    if !channel.place.isEmpty {
                                        Text(channel.place).kjSmall(faint: true).lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(HouseButtonStyle())
                            // Play/Pause plays it too, as on Apple's TV app.
                            .onPlayPauseCommand { playing = Pick(channel: channel, list: list) }
                            .accessibilityLabel(channel.cardLabel(still: false, liked: false))
                            .accessibilityIdentifier("liked-\(channel.id)")
                        }
                    }
                    // Room over and under the row for a focused plate's lift.
                    .padding(.vertical, 14)
                }
                .scrollClipDisabled()
                // The first plate's padding is pulled back so its text sits on the page margin.
                .padding(.leading, -26)
                .focusSection()
            }
        }
        // Again each time the app comes forward: a read that failed at launch (an Apple TV waking
        // before its network) is retried, and a read that worked is not repeated (SavesStore).
        .task(id: "\(model.auth.session?.userId ?? "")|\(scenePhase)") { await model.saves.load() }
        // Again when the app comes forward: a list that failed to load at launch is read again
        // (the store caches the ones that loaded, so a walk that found everything costs nothing).
        .task(id: "\(refs.joined(separator: ","))|\(scenePhase)") { await resolve() }
        .kjFullScreenCover(item: $playing) { pick in
            ReceiverPlayerView(channel: pick.channel, list: pick.list, listTitle: "Liked")
        }
    }

    /// Finds each liked channel in the region lists: the atlas, then the cameras, then the wider
    /// regions (fewest lists first; the wider ones are not cached with *Beyond the atlas* off),
    /// each tier read at once (the store caches every list), and stops after the first tier that
    /// leaves nothing unfound. A like no list carries is remembered as missing on this
    /// device for `missingFor`, so the receiver is not walked for it on every launch or change.
    private func resolve() async {
        guard let index = model.receiver.index else { return }
        let main = index.listedRegions.filter { ShuffleScope.main.includes(tier: $0.tier) }
        let wide = index.listedRegions.filter { !ShuffleScope.main.includes(tier: $0.tier) }
        // Every region, as the cameras shelf reads them: one may carry cameras and no list.
        let cameras = index.regions.filter { index.cameraFiles?[$0.id] != nil }
        let tiers: [([ReceiverIndex.Region], Bool)] = [(main, false), (cameras, true), (wide, false)]
        let wanted = Set(refs)
        // Nothing to find (signed out, or the likes not read yet): no walk, and the account's likes
        // that arrive next are not taken for new ones.
        // An account that unliked everything has no likes: its next like is new, so it is fresh.
        guard !wanted.isEmpty else { if lastRefs != nil { lastRefs = [] }; return }
        // A like just made is worth a walk, even of a channel off air a moment ago.
        let fresh = lastRefs.map { wanted.subtracting($0) } ?? []
        lastRefs = wanted
        if !fresh.isEmpty, !fresh.isDisjoint(with: missing) { unmarkMissing(fresh) }
        var unfound: Set<String> { wanted.subtracting(found.keys).subtracting(missing) }
        // Missing is written only after every list has loaded: a like is not given up on a failed read.
        var complete = true
        for (regions, camerasOnly) in tiers {
            if unfound.isEmpty { break }
            // Nil for a list that did not load, so a failed read is never taken for "not there".
            let lists = await withTaskGroup(of: [Channel]?.self) { group in
                for region in regions {
                    group.addTask { @MainActor in
                        try? await model.receiver.channels(regionId: region.id, cameras: camerasOnly)
                    }
                }
                var all: [[Channel]?] = []
                for await list in group { all.append(list) }
                return all
            }
            guard !Task.isCancelled else { return }
            if lists.contains(where: { $0 == nil }) { complete = false }
            for channel in lists.compactMap({ $0 }).joined() {
                for ref in PassportSaves.channelRefs(slug: channel.slug, id: channel.id, legacyIds: channel.legacyIds)
                where wanted.contains(ref) && found[ref] == nil { found[ref] = channel }
            }
        }
        if complete, !unfound.isEmpty { markMissing(unfound) }
    }

}

/// Every region with public cameras, main atlas first, each opening its page on its cameras
/// (owner, 2026-10-07: "make cctv show up in the reciever"). Names only, at the foot of the page
/// (owner, 2026-11-19: "cctv should go at the bottom of the main page" and "need no cards just
/// names is wnough that can be clicked"), set as the Themes row is: focus comes in on the first
/// name, then on the one last focused, and Back from a region returns to the name pressed.
private struct CCTVRow: View {
    static let anchor = "shelf-cameras"
    let index: ReceiverIndex
    /// Scrolls the page so the row is on screen.
    let keepVisible: () -> Void
    @Environment(AppModel.self) private var model
    @FocusState private var focused: String?
    @State private var lastFocused: String?
    /// The name whose region page is open, focused again when the page comes back.
    @State private var pressed: String?
    /// Where the row last sat on screen, to tell a push down from a scroll.
    @State private var lastY: CGFloat?

    var body: some View {
        let regions = CameraRegions.ordered(index)
        if !regions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CCTV").kjName(38)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(regions) { region in
                            let count = index.regionCounts[region.id]?.byMedium["camera"] ?? 0
                            Button {
                                pressed = region.id
                                model.camerasFirst = region.id
                                model.receiverPath.append(region)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(region.label).kjName(30).lineLimit(1)
                                    // A count the index does not carry is left out, never "0 live".
                                    if count > 0 {
                                        Text("\(count.formatted()) live").kjSmall(faint: true).monospacedDigit()
                                    }
                                }
                            }
                            .buttonStyle(HouseButtonStyle())
                            .focused($focused, equals: region.id)
                            .accessibilityLabel(count > 0
                                ? "\(region.label) cameras, \(count.formatted()) live"
                                : "\(region.label) cameras")
                            .accessibilityIdentifier("cameras-\(region.id)")
                        }
                    }
                    // Room over and under the row for a focused plate's lift.
                    .padding(.vertical, 14)
                }
                .scrollClipDisabled()
                // The first plate's padding is pulled back so its text sits on the page margin.
                .padding(.leading, -26)
            }
            .focusSection()
            // Entering the row, focus goes to the first name, then to the one last focused. tvOS
            // gives the name under the card it came from and does not honour defaultFocus here
            // (UI test, 2026-11-19), so the row moves it itself.
            .onChange(of: focused) { old, now in
                guard let now else { return }
                let home = regions.contains { $0.id == lastFocused } ? lastFocused : regions.first?.id
                if old == nil, let home, now != home {
                    focused = home
                } else {
                    lastFocused = now
                }
            }
            // Shelves loading above push the row down; a focused name stays on screen. Only a push
            // down acts: the focus engine's scroll and this one move the row up. Not reproduced
            // on the simulator, where the shelves land before a walk reaches the foot; aimed at
            // the slower Apple TV HD.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                defer { lastY = y }
                if focused != nil, let lastY, y > lastY + 1 { keepVisible() }
            }
            // Back from the region page: the name pressed takes focus again, and a later visit to
            // the same region from the list opens on its television, not its cameras.
            .onAppear {
                guard let id = pressed else { return }
                pressed = nil
                // Back from the region leaves camerasFirst set; a link that opened the front
                // cleared it, and then the front opens at its top.
                guard model.camerasFirst == id else { return }
                model.camerasFirst = nil
                Task { @MainActor in
                    focused = id
                    keepVisible()
                }
            }
            .id(Self.anchor)
            .accessibilityIdentifier(Self.anchor)
        }
    }
}

/// The front's All · TV · Radio row, with its own focus, so a step along it is the row's business
/// and only entering or leaving it reaches the front (`onFocus`).
private struct ChipRow: View {
    let items: [(String, String)]
    let current: String
    let id: String
    let set: (String) -> Void
    let onFocus: (Bool) -> Void
    @FocusState private var focused: String?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button {
                    set(item.0)
                } label: { Text(item.1).kjKicker() }
                    .buttonStyle(HouseTabStyle(isCurrent: item.0 == current))
                    .focused($focused, equals: item.0)
                    .accessibilityIdentifier("\(id)-\(item.0)")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        .onChange(of: focused != nil) { _, on in onFocus(on) }
    }
}
