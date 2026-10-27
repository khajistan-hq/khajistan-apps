import SwiftUI

/// SEARCH: one field. The rooms the app reads itself answer here, each under its own name; a
/// room whose data this device cannot read (behind the site password until launch) is named as
/// not searched, never shown as having no results. The website's own index (/search.html) is
/// always one control away for everything else.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var settled = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static let perRoom = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHead(kicker: "Search", "Search the archive", line: nil)
                field
                if settled.count >= 2 { results }
                websiteRow
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        // The rooms' data is read once, when Search is first opened.
        .task(id: model.auth.previewPassword) {
            async let reading: Void = model.reading.start()
            async let films: Void = model.films.load()
            async let bazaar: Void = model.bazaar.load()
            async let entries: Void = model.madrassaEntries.load()
            async let posts: Void = model.madrassaPosts.load()
            async let words: Void = model.lughat.load()
            _ = await (reading, films, bazaar, entries, posts, words)
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { settled = trimmed }
        }
    }

    private var field: some View {
        HouseInputField("Titles, places, people") {
            TextField("", text: $query, prompt: Text("Titles, places, people").foregroundStyle(palette.faint))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { settled = trimmed }
                .accessibilityIdentifier("archiveSearch")
        }
    }

    // MARK: - Results by room

    @ViewBuilder
    private var results: some View {
        let needle = DBQuery.fold(settled)
        let titles = model.reading.titles.filter { [$0.name, $0.native, $0.byline].contains { DBQuery.fold($0).contains(needle) } }
        section("Reading Room", count: titles.count, ready: model.reading.phase == .ready) {
            ForEach(titles.prefix(Self.perRoom)) { title in
                row(title.name, detail: title.byline) { model.open(.reading, at: [.readingTitle(title.slug)]) }
            }
        }
        let films = model.films.films.filter { [$0.title, $0.country, $0.publisher].compactMap { $0 }.contains { DBQuery.fold($0).contains(needle) } }
        section("Screening Room", count: films.count, ready: model.films.state == .ready) {
            ForEach(films.prefix(Self.perRoom)) { film in
                row(Films.displayTitle(film), detail: film.country ?? "") { model.open(.screening, at: [.film(film.handle)]) }
            }
        }
        if StoreBuild.includes(.bazaar) {
            let products = (model.bazaar.value ?? []).filter { DBQuery.fold($0.product.title).contains(needle) }
            section("Bazaar", count: products.count, ready: model.bazaar.state == .ready) {
                ForEach(products.prefix(Self.perRoom)) { item in
                    row(item.product.title, detail: [item.shelf.title, Bazaar.priceLine(item.product)].compactMap { $0 }.joined(separator: " \u{00B7} ")) {
                        model.open(.bazaar, at: [.product(item.product.h)])
                    }
                }
            }
        }
        let entries = (model.madrassaEntries.value ?? []).filter { [$0.title, $0.sub ?? "", $0.cat].contains { DBQuery.fold($0).contains(needle) } }
        let posts = (model.madrassaPosts.value ?? []).filter { DBQuery.fold($0.title + " " + ($0.tags ?? []).joined(separator: " ")).contains(needle) }
        section("Madrassa", count: entries.count + posts.count, ready: model.madrassaPosts.state == .ready || model.madrassaEntries.state == .ready) {
            ForEach(entries.prefix(Self.perRoom)) { entry in
                row(entry.title, detail: entry.cat) { model.open(.madrassa, at: [.madrassaEntry(entry.id)]) }
            }
            ForEach(posts.prefix(Self.perRoom)) { post in
                row(MadrassaWritings.listTitle(post), detail: MadrassaWritings.label(post)) { model.open(.madrassa, at: [.post(post.id)]) }
            }
        }
        let words = (model.lughat.value ?? []).filter { Lughat.matches($0, settled) }
        section("Street Dictionary", count: words.count, ready: model.lughat.state == .ready) {
            ForEach(words.prefix(Self.perRoom)) { entry in
                row(entry.word ?? entry.id, detail: [entry.lang, entry.meaning].compactMap { $0 }.joined(separator: " \u{00B7} ")) {
                    model.open(.madrassa)
                }
            }
        }
        if !notSearched.isEmpty {
            Text("Not searched here: \(notSearched.joined(separator: ", ")) \u{2014} behind the site password on this device, or not yet loaded.")
                .kjSmall(faint: true)
                .accessibilityIdentifier("searchNotSearched")
        }
        Text("The research databases are searched inside each one, under Madrassa \u{2192} Databases.").kjSmall(faint: true)
    }

    private var notSearched: [String] {
        var out: [String] = []
        if model.reading.phase != .ready { out.append("Reading Room") }
        if model.films.state != .ready { out.append("Screening Room") }
        if StoreBuild.includes(.bazaar), model.bazaar.state != .ready { out.append("Bazaar") }
        if model.madrassaPosts.state != .ready { out.append("Madrassa") }
        if model.lughat.state != .ready { out.append("Street Dictionary") }
        return out
    }

    /// A room's answers. A room this device could not read is left out here and named below.
    @ViewBuilder
    private func section<Rows: View>(_ name: String, count: Int, ready: Bool, @ViewBuilder rows: () -> Rows) -> some View {
        if ready {
            VStack(alignment: .leading, spacing: 0) {
                HouseRule()
                HStack(alignment: .firstTextBaseline) {
                    Kicker(name).accessibilityAddTraits(.isHeader)
                    Text(count == 0 ? "nothing" : count.formatted()).kjSmall(faint: true)
                }
                .padding(.top, 10)
                rows()
                if count > Self.perRoom { Text("First \(Self.perRoom) of \(count.formatted())").kjSmall(faint: true).padding(.top, 4) }
            }
            .accessibilityIdentifier("searchRoom-\(name)")
        }
    }

    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).kjName().lineLimit(2).multilineTextAlignment(.leading)
                    if !detail.isEmpty { Text(detail).kjSmall(faint: true).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Text("\u{2192}").kjName().accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)))
    }

    private var websiteRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HouseRule()
            Button(action: searchWebsite) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trimmed.isEmpty ? "The website's index" : "\u{201C}\(trimmed)\u{201D} on the website").kjName()
                        Text("Every room, in the website's own search").kjSmall(faint: true)
                    }
                    Spacer(minLength: 0)
                    Text("\u{2197}").kjName().accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
            .disabled(trimmed.isEmpty)
            .accessibilityIdentifier("archiveSearchGo")
        }
    }

    private func searchWebsite() {
        guard let url = ArchiveURL.search(query) else { return }
        focused = false
        model.openWebsite(url)
    }
}
