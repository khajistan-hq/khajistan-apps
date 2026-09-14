import SwiftUI
import QuickLook

struct LibraryView: View {
    let model: AppModel
    @State private var selection = 0
    @State private var query = ""
    @State private var files: [URL] = []
    @State private var preview: URL?
    @State private var clearConfirmation = false
    private var pages: [SavedPage] {
        (selection == 0 ? model.library.bookmarks : model.library.history).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }
    private var visibleFiles: [URL] { files.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionBand(title: "Your library / On this device")
                Picker("Library section", selection: $selection) {
                    Text("Saved").tag(0); Text("Recent").tag(1); Text("Files").tag(2)
                }.pickerStyle(.segmented).padding(16)
                if selection < 2 {
                    List {
                        ForEach(pages) { page in
                            Button { model.open(page.url) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(page.title).font(.headline).foregroundStyle(.black)
                                    Text(page.url.path == "/" ? "The archive" : page.url.path).font(.caption).foregroundStyle(Brand.green).lineLimit(1)
                                }.padding(.vertical, 8)
                            }
                            .swipeActions { if selection == 0 { Button("Remove", role: .destructive) { model.removeSaved(page.id) } } }
                            .listRowBackground(Brand.yellow).listRowSeparatorTint(.black)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .overlay { if pages.isEmpty { ContentUnavailableView(selection == 0 ? "Keep a page" : "No recent pages", systemImage: selection == 0 ? "bookmark" : "clock", description: Text(selection == 0 ? "Tap the bookmark while browsing to keep a link here. Reading the page requires a connection." : "Archive pages you visit appear here. Account and sign-in pages are excluded.")) } }
                } else {
                    List {
                        ForEach(visibleFiles, id: \.self) { file in
                            HStack {
                                Button { preview = file } label: {
                                    Label(file.lastPathComponent, systemImage: "doc").foregroundStyle(.black).padding(.vertical, 8)
                                }.buttonStyle(.plain)
                                Spacer()
                                ShareLink(item: file) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Share \(file.lastPathComponent)")
                            }
                            .swipeActions { Button("Delete", role: .destructive) { remove(file) } }
                            .listRowBackground(Brand.yellow).listRowSeparatorTint(.black)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .overlay { if visibleFiles.isEmpty { ContentUnavailableView("No downloaded files", systemImage: "arrow.down.doc", description: Text("Files you explicitly download from the archive appear here. Subscription reading pages are not saved for offline access.")) } }
                        .refreshable { readFiles() }
                }
            }
            .background(Brand.yellow).foregroundStyle(.black)
            .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.yellow, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $query, prompt: selection == 2 ? "Find a file" : "Find a page")
            .toolbar { if selection == 1 && !model.library.history.isEmpty { ToolbarItem(placement: .topBarTrailing) { Button("Clear") { clearConfirmation = true } } } }
            .confirmationDialog("Clear recent pages on this device?", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("Clear recent pages", role: .destructive) { model.clearHistory() }
            }
            .quickLookPreview($preview)
            .onAppear(perform: readFiles)
            .onChange(of: selection) { if selection == 2 { readFiles() } }
            .onChange(of: model.isShowingBrowser) { if !model.isShowingBrowser { readFiles() } }
        }
    }
    private func readFiles() {
        let directory = ArchiveBrowser.downloadDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { files = []; return }
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { model.message = "Could not read downloaded files: \(error.localizedDescription)" }
    }
    private func remove(_ file: URL) {
        do { try FileManager.default.removeItem(at: file); readFiles() }
        catch { model.message = "Could not delete file: \(error.localizedDescription)" }
    }
}
