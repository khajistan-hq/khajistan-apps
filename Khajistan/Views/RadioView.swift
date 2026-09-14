import SwiftUI
import AVKit

struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.tintColor = .black; view.activeTintColor = UIColor(Brand.green)
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct RadioView: View {
    let model: AppModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var country = "All places"
    private var countries: [String] { ["All places"] + Set(model.radio.channels.compactMap(\.country)).sorted() }
    private var filtered: [RadioChannel] {
        model.radio.channels.filter { channel in
            (country == "All places" || channel.country == country) &&
            (query.isEmpty || "\(channel.name) \(channel.location)".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionBand(title: "Khajistan Receiver / Radio")
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Find a station or language", text: $query, prompt: Text("Find a station or language").foregroundStyle(Brand.green))
                        .autocorrectionDisabled().accessibilityIdentifier("stationSearch").focused($searchFocused)
                        .submitLabel(.search).onSubmit { searchFocused = false }
                    Menu {
                        Picker("Place", selection: $country) { ForEach(countries, id: \.self) { Text($0).tag($0) } }
                    } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }
                        .accessibilityLabel("Filter by place: \(country)")
                }.padding(.horizontal, 20)
                if let error = model.radio.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.callout)
                        Button("Retry station list") { Task { await model.radio.load() } }.font(.callout.bold())
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
                if model.radio.isLoadingCatalogue && model.radio.channels.isEmpty {
                    Spacer(); ProgressView("Tuning the directory…"); Spacer()
                } else {
                    List {
                        ForEach(filtered) { channel in
                            Button { searchFocused = false; model.radio.play(channel) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: model.radio.selected?.id == channel.id && model.radio.isPlaying ? "waveform" : "play.circle")
                                        .font(.title2).foregroundStyle(Brand.green).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(channel.name).font(.headline).foregroundStyle(.black)
                                        Text(channel.location).font(.caption).foregroundStyle(Brand.green)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 8)
                            }.accessibilityIdentifier("radio-\(channel.id)").listRowBackground(Brand.yellow).listRowSeparatorTint(.black)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .overlay { if filtered.isEmpty && !model.radio.isLoadingCatalogue { ContentUnavailableView("No stations", systemImage: "radio", description: Text("Try a different place or search, or refresh the directory.")) } }
                        .refreshable { await model.radio.load() }
                }
                if let selected = model.radio.selected {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selected.name).font(.headline)
                                Text(model.radio.isTuning ? "Connecting…" : model.radio.isPlaying ? "Playing" : "Paused").font(.caption)
                            }
                            Spacer()
                            if model.radio.isTuning { ProgressView() }
                            Button { model.radio.toggle() } label: {
                                Image(systemName: model.radio.isPlaying || model.radio.isTuning ? "pause.fill" : "play.fill").frame(width: 48, height: 48)
                            }.accessibilityLabel(model.radio.isPlaying || model.radio.isTuning ? "Pause radio" : "Play radio")
                            AirPlayPicker().frame(width: 44, height: 44).accessibilityLabel("Audio output")
                        }
                        if let attribution = selected.attributionText { Text(attribution).font(.caption2).lineLimit(4) }
                    }.padding(16).overlay(alignment: .top) { Rectangle().fill(.black).frame(height: 1) }
                }
            }.background(Brand.yellow).foregroundStyle(.black)
                .navigationTitle("Radio").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Brand.yellow, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Full receiver") { model.open(ArchiveURL.base.appendingPathComponent("open-frequencies")) } } }
                .task { if model.radio.channels.isEmpty { await model.radio.load() } }
        }
    }
}
