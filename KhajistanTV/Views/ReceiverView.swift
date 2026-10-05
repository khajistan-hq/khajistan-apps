import SwiftUI

/// The receiver's front page: regions by tier, and one switch for the ones beyond the atlas.
struct ReceiverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = Palette(model.skin)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("Receiver")
                        .font(KJFont.title())
                    content(palette)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .background(palette.ground.ignoresSafeArea())
            .navigationDestination(for: ReceiverIndex.Region.self) { region in
                ChannelsView(region: region)
            }
        }
        .foregroundStyle(palette.ink)
        .task { await model.receiver.loadIndex() }
    }

    @ViewBuilder
    private func content(_ palette: Palette) -> some View {
        if let index = model.receiver.index {
            // The heartbeat regions, then the rest of the atlas, each in the index's own order.
            // The tier names are filing vocabulary and are not shown.
            regionLinks(
                index.listedRegions.filter { $0.tier == "heartbeat" }
                    + index.listedRegions.filter { $0.tier != "heartbeat" && ReceiverRules.tiersOnByDefault.contains($0.tier) },
                index: index, palette: palette
            )
            // The website's switch, in the website's words. Its regions follow it when it is on.
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: extendedBinding) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Beyond the atlas")
                            .font(KJFont.bodyBold())
                        Text("The wider Islamicate, Rumelia to Nusantara")
                            .font(KJFont.caption())
                    }
                }
                .toggleStyle(PlateToggleStyle(palette: palette))
                .accessibilityIdentifier("beyondTheAtlas")
                if model.extendedAtlas {
                    regionLinks(index.listedRegions.filter { $0.tier == "islamicate" }, index: index, palette: palette)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        } else if let message = model.receiver.indexError {
            Text(message)
                .font(KJFont.body())
            Button("Try again") {
                Task { await model.receiver.loadIndex() }
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
        } else {
            Text("Loading the receiver\u{2026}")
                .font(KJFont.body())
        }
    }

    @ViewBuilder
    private func regionLinks(_ regions: [ReceiverIndex.Region], index: ReceiverIndex, palette: Palette) -> some View {
        if !regions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(regions) { region in
                    NavigationLink(value: region) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(region.label)
                                .font(KJFont.bodyBold())
                            let line = index.mediumLine(regionId: region.id)
                            if !line.isEmpty {
                                Text(line)
                                    .font(KJFont.caption())
                            }
                        }
                    }
                    .buttonStyle(PlateButtonStyle(palette: palette))
                    .accessibilityIdentifier("region-\(region.id)")
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var extendedBinding: Binding<Bool> {
        Binding(
            get: { model.extendedAtlas },
            set: { model.extendedAtlas = $0 }
        )
    }
}
