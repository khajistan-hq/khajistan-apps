import SwiftUI

/// The receiver's front, and the front is the map. At left, what the receiver is and how much is
/// on air; at right, the regions to open. The switch under the figures widens the map beyond the
/// atlas.
struct ReceiverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var path: [ReceiverIndex.Region] = []
    @State private var composed: ComposedMap?
    @State private var mapError: String?
    @State private var showMixes = false
    @FocusState private var focusedRegion: String?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.ground.ignoresSafeArea())
                .foregroundStyle(palette.ink)
                .navigationDestination(for: ReceiverIndex.Region.self) { region in
                    ChannelsView(region: region)
                }
                .navigationDestination(isPresented: $showMixes) {
                    MixesView()
                }
        }
        // The id restarts the load when the switch moves, so the map follows it.
        .task(id: model.extendedAtlas) { await load() }
        .task { await model.mixes.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let index = model.receiver.index {
            HStack(alignment: .top, spacing: 60) {
                sidebar(index)
                mapArea
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 20)
            .defaultFocus($focusedRegion, "indus")
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
        Group {
            if let mapError {
                failure(mapError)
            } else if let composed {
                VStack(alignment: .leading, spacing: 24) {
                    RegionMapView(map: composed, highlighted: focusedRegion)
                    regionStrip(composed)
                    mixesEntry
                }
            } else {
                TuningLoader("Loading the receiver\u{2026}")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
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
        .frame(height: 96)
    }

    /// The Khajistan Radio mixes. The website's receiver took them in as one of its media (owner,
    /// 2026-08-16: television, radio and the mixes are one door), so they open from here, on a row
    /// of their own under the regions. The row spans the map's width so that a press down from any
    /// region lands on it. Offered only once the register has loaded and holds a mix that plays.
    @ViewBuilder
    private var mixesEntry: some View {
        let count = model.mixes.mixes.count
        if count > 0 {
            Button {
                showMixes = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Kicker("Khajistan Radio")
                    Text("\(count) \(count == 1 ? "mix" : "mixes")").kjSmall(faint: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)))
            .accessibilityIdentifier("khajistanRadioMixes")
            // The plate's padding is pulled back so the label sits on the map's margin.
            .padding(.horizontal, -22)
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
        path.append(region)
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
