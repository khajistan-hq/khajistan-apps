import SwiftUI

/// The Khajistan Radio mixes: the public register of recordings Khajistan made and hosts itself,
/// as a grid in the register's own order. A mix is a finished recording, not a live signal.
struct MixesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var playing: Mix?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 28), count: 4)

    private var store: MixesStore { model.mixes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 12) {
                    Kicker("Receiver \u{2192} Khajistan Radio")
                    Text("Khajistan Radio")
                        .kjDisplay()
                        .accessibilityAddTraits(.isHeader)
                    if !store.mixes.isEmpty {
                        Text("\(store.mixes.count) \(store.mixes.count == 1 ? "mix" : "mixes")")
                            .kjBody()
                    }
                }
                results
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 40)
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await store.load() }
        .fullScreenCover(item: $playing) { mix in
            MixPlayerView(mix: mix, list: store.mixes)
        }
    }

    @ViewBuilder
    private var results: some View {
        if let message = store.loadError, store.mixes.isEmpty {
            VStack(alignment: .leading, spacing: 28) {
                Text(message).kjBody()
                Button {
                    Task { await store.load() }
                } label: {
                    Text("Try again").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
            }
        } else if store.mixes.isEmpty {
            TuningLoader("Loading\u{2026}")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                ForEach(store.mixes) { mix in
                    Button {
                        playing = mix
                    } label: {
                        card(mix)
                    }
                    .buttonStyle(HouseButtonStyle())
                    .accessibilityIdentifier("mix-\(mix.id)")
                }
            }
            // The cards' plate padding is pulled back so their text sits on the page margin.
            .padding(.horizontal, -26)
        }
    }

    /// The mix's name, the programme block it aired in, and where it is from and in what language.
    private func card(_ mix: Mix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mix.name)
                .kjName()
                .lineLimit(2)
            Kicker(mix.program_block ?? "Mixtape")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            let detail = [mix.place, mix.language].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !detail.isEmpty {
                Text(detail)
                    .kjSmall(faint: true)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }
}
