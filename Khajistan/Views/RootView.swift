import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            ExploreView(model: model)
                .tabItem { Label("Explore", systemImage: "globe.asia.australia") }.tag(AppTab.explore)
            RadioView(model: model)
                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }.tag(AppTab.radio)
            LibraryView(model: model)
                .tabItem { Label("Library", systemImage: "bookmark") }.tag(AppTab.library)
            PassportView(model: model)
                .tabItem { Label("Passport", systemImage: "person.crop.rectangle") }.tag(AppTab.passport)
        }
        .toolbarBackground(Brand.yellow, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: $model.isShowingBrowser) { BrowserView(model: model) }
        .alert("Khajistan", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

struct ExploreView: View {
    let model: AppModel
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("KHAJISTAN").font(.system(.largeTitle, design: .default, weight: .black)).tracking(-1.5).minimumScaleFactor(0.65).lineLimit(1)
                            Text("MEDIA OF THE\nMIDDLE WORLD").font(.caption.weight(.bold)).tracking(2)
                        }
                        Spacer(minLength: 4)
                        Image("Pigeon").resizable().scaledToFit().frame(width: 90, height: 110).accessibilityHidden(true)
                    }.padding(20)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        TextField("Search the archive", text: $query, prompt: Text("Search the archive").foregroundStyle(Brand.green)).submitLabel(.search)
                            .onSubmit(search).accessibilityIdentifier("archiveSearch")
                        Button(action: search) { Image(systemName: "arrow.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("Search archive").disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.leading, 12).overlay { Rectangle().stroke(.black) }.padding(.horizontal, 20).padding(.bottom, 22)
                    ForEach(ArchiveDestination.doors, id: \.door) { group in
                        SectionBand(title: group.door)
                        LazyVStack(spacing: 0) {
                            ForEach(group.rooms) { destination in
                                Button { model.open(destination.url) } label: {
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(destination.title).font(.title3.weight(.bold))
                                            Text(destination.subtitle).font(.subheadline).foregroundStyle(Brand.green)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.body.weight(.medium))
                                    }.padding(.horizontal, 20).padding(.vertical, 17).frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("destination-\(destination.id)")
                                if destination != group.rooms.last { Divider().overlay(.black) }
                            }
                        }
                    }
                }
            }
            .background(Brand.yellow).foregroundStyle(.black)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    private func search() { if let url = ArchiveURL.search(query) { model.open(url) } }
}

struct PassportView: View {
    let model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "person.crop.rectangle").font(.system(size: 64, weight: .thin)).padding(.top, 20)
                    Text("Your Passport").font(.largeTitle.weight(.black))
                    Text("Sign in to your Khajistan account to open your library and manage your membership.").font(.title3)
                    Button("Open Passport") { model.open(ArchiveURL.base.appendingPathComponent("dashboard.html")) }
                        .buttonStyle(ArchiveButtonStyle())
                    Button("My downloads") { model.open(ArchiveURL.base.appendingPathComponent("downloads.html")) }
                        .buttonStyle(ArchiveButtonStyle())
                    Divider().overlay(.black)
                    Text("ON THIS DEVICE").font(.caption.weight(.bold)).tracking(1.5)
                    Text("Saved page links and recent visits stay on this device. Files you choose to download are available in Library. Account access is managed by the archive website.").font(.body)
                    Button("About Khajistan") { model.open(ArchiveURL.base.appendingPathComponent("about.html")) }
                        .buttonStyle(ArchiveButtonStyle())
                    Text("Khajistan for iOS · 1.0").font(.caption.monospaced()).foregroundStyle(Brand.green)
                }.padding(24)
            }.background(Brand.yellow).foregroundStyle(.black).toolbar(.hidden, for: .navigationBar)
        }
    }
}
