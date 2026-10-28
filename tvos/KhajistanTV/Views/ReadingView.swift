import Combine
import SwiftUI

/// The Reading Room: the shelf the website draws at /reading-room.html, as rows of covers. A tab per
/// language and a row per shelf in it when the module index is there (data/rr-modules.json, behind the
/// site password); otherwise one tab of every title in a row per region. Each cover is the real scanned
/// first page; each card says what the page server told an anonymous visitor about it.
struct ReadingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var tabID: String?
    @State private var opened: RRTitle?
    @State private var continuing: ReadingPlaces.Opening?
    /// A shelf opened whole, as Apple Books opens "Name ›" into a grid.
    @State private var wholeRow: RRRow?
    /// What is typed in the search bar: titles in any script, from the shelf already held.
    @State private var query = ""
    /// The places as last drawn: a page read in the reader redraws Continue.
    @State private var places = ReadingPlaces.all
    @FocusState private var focusedTab: String?

    private var store: ReadingStore { model.reading }

    private var tab: RRTab? {
        store.tabs.first { $0.id == tabID } ?? store.tabs.first
    }

    var body: some View {
        ScrollView {
            // The head of the page (Continue and the tabs with it) is always built, so Up from a
            // shelf reaches Continue even when it arrived while the page was scrolled away from
            // it; only the shelves are lazy.
            VStack(alignment: .leading, spacing: 32) {
                header
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the Reading Room\u{2026}")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed(let message):
                    problem(message)
                case .ready:
                    searchBar
                    if !trimmed.isEmpty {
                        results
                    } else {
                        continueRow
                        if store.tabs.count > 1 { tabRow }
                        if let tab {
                            LazyVStack(alignment: .leading, spacing: 32) { shelf(tab) }
                        }
                    }
                }
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Down from the top bar lands on the tab on show, not on the one under the bar item.
        .defaultFocus($focusedTab, tab?.id, priority: .userInitiated)
        .task { await store.start() }
        // A title the Rooms door asked for, opened once the shelf is in hand.
        .task(id: store.phase == .ready && model.readingLink != nil) { follow() }
        // A shelf that did not load drops the request, so it never opens a title later unasked.
        .onChange(of: store.phase) { if case .failed = store.phase { model.readingLink = nil } }
        .fullScreenCover(item: $opened) { title in
            ReadingTitleView(title: title)
        }
        .fullScreenCover(item: $continuing) { place in
            ReadingReaderView(title: place.title, issue: place.issue, startPage: place.page)
        }
        .fullScreenCover(item: $wholeRow) { row in
            ReadingRowGrid(row: row)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let now = ReadingPlaces.all
            if now != places { places = now }
        }
    }

    /// Continue, as Apple Books heads its shelf: the titles read on this device, newest first, each
    /// opening the reader at the page it was left on. Only this device's places; never a pick.
    @ViewBuilder
    private var continueRow: some View {
        let openings = ReadingPlaces.openings(places, in: store.titles).filter { !store.isRights($0.title) }
        if !openings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Continue").kjName(KJType.name)
                    Text(openings.count.formatted()).kjSmall(faint: true)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 24) {
                        ForEach(openings) { place in
                            Button { continuing = place } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    RRCover(state: store.card(for: place.title))
                                        .frame(width: ReadingMetrics.coverWidth, height: ReadingMetrics.coverHeight)
                                    Text(place.title.name).kjName(26).lineLimit(2).frame(height: 70, alignment: .topLeading)
                                    Text(place.line).kjKicker().lineLimit(2)
                                }
                                .frame(width: ReadingMetrics.coverWidth, alignment: .leading)
                            }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)))
                            .onAppear { store.want(place.title) }
                            .accessibilityIdentifier("rr-continue-\(place.title.slug)")
                            .accessibilityLabel("Continue \(place.title.name), \(place.line)")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
                .padding(.leading, -10)
            }
            .focusSection()
        }
    }

    private func follow() {
        guard store.phase == .ready, let link = model.readingLink else { return }
        model.readingLink = nil
        guard let title = store.titles.first(where: { $0.slug == link.slug }) else { return }
        if link.resume, let place = ReadingPlaces.openings(places, in: [title]).first, !store.isRights(title) {
            continuing = place
        } else {
            opened = title
        }
    }

    // MARK: - Search

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The search bar Apple Books puts over its shelf, in the house field.
    private var searchBar: some View {
        HouseInputField("Search", text: query, hint: "Titles, in any script") {
            TextField("", text: $query)
                .autocorrectionDisabled()
        }
        .frame(maxWidth: 900, alignment: .leading)
        .accessibilityIdentifier("rrSearch")
    }

    /// Titles whose name, native name or byline holds what is typed, in shelf order. Reads the
    /// shelf already held; nothing is fetched.
    @ViewBuilder
    private var results: some View {
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let found = store.titles.filter { title in
            [title.name, title.native, title.byline].contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle)
            }
        }
        Text(found.isEmpty ? "No title on the shelf matches \u{201C}\(trimmed)\u{201D}." : "\(found.count.formatted()) title\(found.count == 1 ? "" : "s")")
            .kjSmall(faint: true)
            .accessibilityIdentifier("rrSearchCount")
        LazyVGrid(columns: ReadingMetrics.gridColumns, alignment: .leading, spacing: 28) {
            ForEach(found) { title in RRTitleCard(title: title) { opened = title } }
        }
        .padding(.leading, -10)
        .focusSection()
    }

    // MARK: - Header and tabs

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RRWords.heading)
                .kjDisplay(KJType.headline, tracking: -0.055)
                .accessibilityAddTraits(.isHeader)
            Text(RRWords.lede).kjBody()
            // The whole room's figures, as the site's head gives them (owner, 2026-10-07); each
            // tab's own line stays on its shelf. One tab is the whole room, so it is not repeated.
            if case .ready = store.phase, store.tabs.count > 1 {
                Text(RRShelves.depthLine(store.titles, rights: store.rights))
                    .kjSmall(faint: true)
                    .accessibilityIdentifier("rrTotal")
            }
        }
    }

    private var tabRow: some View {
        HStack(spacing: 12) {
            ForEach(store.tabs) { item in
                Button {
                    tabID = item.id
                } label: {
                    Text(item.name).kjKicker()
                }
                .buttonStyle(HouseTabStyle(isCurrent: item.id == tab?.id))
                .focused($focusedTab, equals: item.id)
                .accessibilityIdentifier("rr-tab-\(item.id)")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        .focusSection()
    }

    // MARK: - The shelf

    @ViewBuilder
    private func shelf(_ tab: RRTab) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(tab.name).kjName(KJType.name)
                if let native = tab.native, !native.isEmpty {
                    Text(native).kjName(KJType.name).foregroundStyle(palette.faint)
                }
            }
            Text(tab.depth)
                .kjSmall(faint: true)
                .accessibilityIdentifier("rrDepth")
        }
        ForEach(tab.rows) { row in
            rowView(row)
        }
    }

    private func rowView(_ row: RRRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // "Name ›", as Apple Books heads a shelf: it opens the whole shelf as a grid.
            Button { wholeRow = row } label: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.name + " \u{203A}").kjKicker()
                    Text(row.titles.count.formatted()).kjSmall(faint: true)
                }
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)))
            .padding(.leading, -14)
            .accessibilityLabel("\(row.name), \(row.titles.count) titles")
            .accessibilityHint("Opens the whole shelf")
            .accessibilityIdentifier("rr-shelf-\(row.id)")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(row.titles) { title in
                        RRTitleCard(title: title) { opened = title }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            // The cards' plate padding is pulled back so the covers sit on the page margin.
            .padding(.leading, -10)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rr-row-\(row.id)")
    }

    private func problem(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(message).kjBody()
            Button {
                Task { await store.retry() }
            } label: {
                Text("Try again").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .accessibilityIdentifier("rrRetry")
        }
    }
}

/// A title the Rooms door sends the Reading Room to: its page, or the reader at this device's place.
struct ReadingLink: Equatable {
    let slug: String
    let resume: Bool
}

/// Where reading stopped, on this device: per title, the issue (its position in the title) and the
/// page. Never a page address, which carries access; the page server is asked again on Continue.
enum ReadingPlaces {
    private static let key = "kj.readingPlaces"

    struct Place: Codable, Equatable {
        /// The issue's position in its title when it was read.
        let issue: Int
        let page: Int
        let date: Date
        /// The issue's own slug and id, so a catalogue that inserts an issue ahead of it does not
        /// send Continue to its neighbour. Absent in a place kept before it was added.
        var ref: String? = nil
        /// The title's name, so the Rooms door can say what to continue without the shelf.
        /// Absent in a place kept before it was added.
        var name: String? = nil
    }

    /// A place made openable: the title and issue as the shelf has them now.
    struct Opening: Identifiable {
        let title: RRTitle
        let issue: RRIssue
        let page: Int
        var id: String { title.slug }
        var line: String { (title.issues.count > 1 ? issue.label + " \u{00B7} " : "") + "p. \(page)" }
    }

    private static func ref(_ issue: RRIssue) -> String { issue.slug + "|" + issue.id }

    /// The issue a place names: by its slug and id (the position breaks a tie between issues that
    /// share them, as one ingested whole does), else, for an old place, by position. An issue no
    /// longer on the shelf has no place.
    static func issue(_ place: Place, in title: RRTitle) -> RRIssue? {
        guard let wanted = place.ref else { return title.issues.first { $0.index == place.issue } }
        let same = title.issues.filter { ref($0) == wanted }
        return same.first { $0.index == place.issue } ?? same.first
    }

    static var all: [String: Place] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let places = try? JSONDecoder().decode([String: Place].self, from: data) else { return [:] }
        return places
    }

    /// Page 1 of the first issue is no place to continue from; the newest forty are kept.
    static func record(title slug: String, name: String? = nil, issue: RRIssue, page: Int, at date: Date = .now) {
        var places = all
        places[slug] = page > 1 || issue.index > 0 ? Place(issue: issue.index, page: page, date: date, ref: ref(issue), name: name) : nil
        let kept = places.sorted { $0.value.date > $1.value.date }.prefix(40)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// The places that know their title's name, newest first: what the Rooms door can offer
    /// without the shelf.
    static func named(_ places: [String: Place]) -> [(slug: String, name: String, page: Int)] {
        places.sorted { $0.value.date > $1.value.date }.compactMap { slug, place in
            place.name.map { (slug, $0, place.page) }
        }
    }

    /// The places whose title and issue are still on the shelf, newest first.
    static func openings(_ places: [String: Place], in titles: [RRTitle]) -> [Opening] {
        let bySlug = Dictionary(titles.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        return places.sorted { $0.value.date > $1.value.date }.compactMap { slug, place in
            guard let title = bySlug[slug], let issue = Self.issue(place, in: title) else { return nil }
            return Opening(title: title, issue: issue, page: min(max(place.page, 1), max(issue.pages, 1)))
        }
    }
}

enum ReadingMetrics {
    static let coverWidth: CGFloat = 250
    static let coverHeight: CGFloat = 340
    static let gridColumns = [GridItem(.adaptive(minimum: coverWidth + 20), spacing: 24, alignment: .top)]
}

/// A title on a shelf: the real cover at its own shape, the name, its run, and the access line in
/// the shelf's words.
struct RRTitleCard: View {
    let title: RRTitle
    let open: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.reading
        let meta = [title.byline, "\(title.issues.count) issue\(title.issues.count == 1 ? "" : "s")"]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                RRCover(state: store.card(for: title))
                    .frame(width: ReadingMetrics.coverWidth, height: ReadingMetrics.coverHeight)
                Text(title.name)
                    .kjName(26)
                    .lineLimit(2)
                    .frame(height: 70, alignment: .topLeading)
                Text(meta)
                    .kjSmall(faint: true)
                    .lineLimit(1)
                Text(store.access(for: title)?.tag ?? " ")
                    .kjKicker()
                    .lineLimit(2)
                    .frame(height: 56, alignment: .topLeading)
            }
            .frame(width: ReadingMetrics.coverWidth, alignment: .leading)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)))
        .onAppear { store.want(title) }
        .accessibilityIdentifier("rr-title-\(title.slug)")
        .accessibilityLabel([title.name, meta, store.access(for: title)?.tag].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A shelf opened whole, as Apple Books opens one: its name large, the count, every title as a
/// grid of covers. A title opens its page; Menu comes back to the shelf.
struct ReadingRowGrid: View {
    let row: RRRow
    @Environment(\.palette) private var palette
    @State private var opened: RRTitle?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.name).kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                        Text("\(row.titles.count.formatted()) title\(row.titles.count == 1 ? "" : "s")").kjBody()
                    }
                    LazyVGrid(columns: ReadingMetrics.gridColumns, alignment: .leading, spacing: 28) {
                        ForEach(row.titles) { title in RRTitleCard(title: title) { opened = title } }
                    }
                    .padding(.leading, -10)
                }
                .padding(KJLayout.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(palette.ink)
        .fullScreenCover(item: $opened) { title in ReadingTitleView(title: title) }
    }
}

/// A cover at its own shape on the house lift colour, fitted whole and never cropped. The plate holds
/// the space until the page arrives; a cover that cannot be had leaves the plate and nothing else.
struct RRCover: View {
    let state: RRCardState
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.lift)
            .overlay {
                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
    }
}
