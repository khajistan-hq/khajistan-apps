import SwiftUI

/// ROOMS on the Apple TV: the Screening Room, the Bazaar, the Madrassa and the research databases,
/// grouped under one door so the top bar stays legible from the couch. The door is laid out as the
/// Apple TV app lays its own and Apple Books its Home: a row of large tiles (Chat among them), then
/// Continue, Up Next and Opened lately from this device. Each room opens full screen; Menu comes
/// back here. A payment is never a form on the remote: checkout opens on the phone from a code.
struct RoomsTVView: View {
    enum Room: String, CaseIterable, Identifiable {
        case screening, bazaar, madrassa, databases
        var id: String { rawValue }
        var title: String {
            switch self {
            case .screening: return "Screening Room"
            case .bazaar: return "Bazaar"
            case .madrassa: return "Madrassa"
            case .databases: return "Databases"
            }
        }
        var line: String {
            switch self {
            case .screening: return "Films Khajistan holds and distributes"
            case .bazaar: return "Prints, objects, apparel and stickers"
            case .madrassa: return "The reference wing \u{2014} street dictionary, indices and writings"
            case .databases: return "Eight research systems"
            }
        }
        /// One of the archive's own pictures, bundled (owner, 2026-10-28: "picture first … like how
        /// apple tv has photos or images for section"), so the door starts no download for it.
        var picture: String {
            switch self {
            case .screening: return "RoomScreening"
            case .bazaar: return "RoomBazaar"
            case .madrassa: return "RoomMadrassa"
            case .databases: return "RoomDatabases"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var open: Room?
    @State private var reopened: OpenedLately.Item?
    /// This device's places and history as last drawn: a page read or a room opened redraws them.
    @State private var places = ReadingPlaces.all
    @State private var opened = OpenedLately.all

    /// Chat is a section of its own in the top bar; the door names it beside the rooms, as the
    /// phone's Home does, wherever this build carries it.
    private var hasChat: Bool { StoreBuild.includes(.chat) }
    /// Five tiles fit the row at this width; four keep the wider one.
    private var tileWidth: CGFloat { hasChat ? 310 : 365 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rooms").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                Text("Films, objects, writings and research, beside the Receiver and the Reading Room.").kjBody()
                HStack(spacing: 40) {
                    ForEach(Room.allCases) { room in
                        Button { open = room } label: {
                            RoomTile(picture: room.picture, title: room.title, line: room.line, figure: figure(room), width: tileWidth)
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("tvroom-\(room.rawValue)")
                    }
                    if hasChat {
                        Button { model.section = .chat } label: {
                            RoomTile(picture: "RoomChat", title: "Chat",
                                     line: "The website's rooms, live", figure: nil, width: tileWidth)
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("tvroom-chat")
                    }
                }
                // Room over and under the tiles for the lift and its shadow.
                .padding(.vertical, 40)
                .focusSection()
                continueRow
                // Only this device's places, and only once the catalogue is already loaded: the
                // door starts no download of its own.
                let stopped = model.films.state == .ready ? FilmPlaces.stopped(model.films.films) : []
                if !stopped.isEmpty {
                    FilmShelf(title: "Up Next", count: stopped.count.formatted(), films: stopped, opensPage: true, showsPlaces: true)
                }
                openedRow
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kjTopFade()
        .fullScreenCover(item: $open) { room in
            TVRoomScreen(room: room)
        }
        .fullScreenCover(item: $reopened) { item in
            TVOpenedScreen(item: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let now = ReadingPlaces.all, lately = OpenedLately.all
            if now != places { places = now }
            if lately != opened { opened = lately }
        }
        #if DEBUG
        // `-kjroom screening` opens a room at launch, as on the phone, for a look at it.
        .task {
            if let name = UserDefaults.standard.string(forKey: "kjroom") { open = Room(rawValue: name) }
        }
        #endif
    }

    /// Continue, as Apple Books heads Home: the titles read on this device, newest first. Covers
    /// when the Reading Room's shelf is already in hand; otherwise the names this device kept, so
    /// the door never starts the catalogue download. Either opens the reader at its page.
    @ViewBuilder
    private var continueRow: some View {
        let reading = model.reading
        if reading.phase == .ready {
            let openings = ReadingPlaces.openings(places, in: reading.titles).filter { !reading.isRights($0.title) }
            if !openings.isEmpty {
                Shelf("Continue", count: openings.count.formatted()) {
                    ForEach(openings) { place in
                        Button { continueReading(place.title.slug) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                RRCover(state: reading.card(for: place.title))
                                    .frame(width: ReadingMetrics.coverWidth, height: ReadingMetrics.coverHeight)
                                    .kjCardArt()
                                Text(place.title.name).kjName(26).lineLimit(2).frame(height: 70, alignment: .topLeading)
                                Text(place.line).kjKicker().lineLimit(2)
                            }
                            .frame(width: ReadingMetrics.coverWidth, alignment: .leading)
                        }
                        .buttonStyle(HouseCardStyle())
                        .onAppear { reading.want(place.title) }
                        .accessibilityIdentifier("home-continue-\(place.title.slug)")
                    }
                }
            }
        } else {
            let named = ReadingPlaces.named(places)
            if !named.isEmpty {
                Shelf("Continue", count: named.count.formatted()) {
                    ForEach(named, id: \.slug) { place in
                        Button { continueReading(place.slug) } label: {
                            CardPlate(width: 420, height: 190) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Kicker("Reading Room").lineLimit(1)
                                    Text(place.name).kjName(30).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Text("p. \(place.page)").kjSmall(faint: true)
                                }
                            }
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("home-continue-\(place.slug)")
                    }
                }
            }
        }
    }

    /// The last things opened on this device, newest first: its own history, never a pick.
    @ViewBuilder
    private var openedRow: some View {
        let shown = Array(opened.prefix(8))
        if !shown.isEmpty {
            Shelf("Opened lately") {
                ForEach(shown) { item in
                    Button { reopen(item) } label: {
                        CardPlate(width: 420, height: 190) {
                            VStack(alignment: .leading, spacing: 8) {
                                Kicker(item.kind.place).lineLimit(1)
                                Text(item.title).kjName(30).lineLimit(3)
                            }
                        }
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("opened-\(item.id)")
                }
            }
        }
    }

    private func continueReading(_ slug: String) {
        model.readingLink = ReadingLink(slug: slug, resume: true)
        model.section = .reading
    }

    private func reopen(_ item: OpenedLately.Item) {
        switch item.kind {
        case .reading:
            model.readingLink = ReadingLink(slug: item.ref, resume: false)
            model.section = .reading
        default:
            reopened = item
        }
    }

    /// A count, when the room's list is already on the device; nothing is fetched for it.
    private func figure(_ room: Room) -> String? {
        switch room {
        case .screening: return model.films.state == .ready ? "\(model.films.films.count.formatted()) films" : nil
        case .bazaar: return model.bazaar.value.map { "\($0.count.formatted()) objects" }
        case .madrassa: return model.madrassaPosts.value.map { "\($0.count.formatted()) writings" }
        case .databases: return nil
        }
    }
}

/// A room's tile, picture first, as the Apple TV app's sections: one of the archive's own
/// pictures fitted whole on the lift plate, which lifts and casts the shadow as a picture card
/// does; under it a count where the room's list is on the device, the name and the room's line,
/// whole, in the ground's ink.
struct RoomTile: View {
    let picture: String
    let title: String
    let line: String
    let figure: String?
    let width: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                palette.lift
                Image(picture).resizable().aspectRatio(contentMode: .fit).padding(16)
            }
            .frame(width: width, height: width * 1.2)
            .kjCardArt()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).kjName(34).lineLimit(1)
                Kicker(figure ?? " ").lineLimit(1)
                Text(line).kjSmall(faint: true).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, height: 190, alignment: .topLeading)
        }
    }
}

struct TVRoomScreen: View {
    let room: RoomsTVView.Room
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            switch room {
            case .screening: TVScreeningRoom()
            case .bazaar: TVBazaar()
            case .madrassa: TVMadrassa()
            case .databases: TVDatabases()
            }
        }
        .foregroundStyle(palette.ink)
    }
}

/// What was opened on this device, newest first, for Opened lately on the door: a title, a film,
/// a writing, an object or a database. Only the name and where it lives are kept, never an address
/// that carries access; reopening asks again. The newest twelve are kept.
enum OpenedLately {
    enum Kind: String, Codable {
        case reading, film, writing, object, database
        /// The room it was opened in, as the card's kicker.
        var place: String {
            switch self {
            case .reading: return "Reading Room"
            case .film: return "Screening Room"
            case .writing: return "Madrassa"
            case .object: return "Bazaar"
            case .database: return "Databases"
            }
        }
    }

    struct Item: Codable, Equatable, Identifiable {
        let kind: Kind
        let ref: String
        let title: String
        let date: Date
        var id: String { kind.rawValue + "|" + ref }
    }

    private static let key = "kj.openedLately"
    private static let kept = 12

    static var all: [Item] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items
    }

    /// Already the newest, it is left as it is: a write wakes every screen that reads the
    /// device's history, and a screen that appears again must not keep writing.
    static func record(_ kind: Kind, ref: String, title: String, at date: Date = .now) {
        let item = Item(kind: kind, ref: ref, title: title, date: date)
        let current = all
        if let newest = current.first, newest.id == item.id, newest.title == title { return }
        let items = [item] + current.filter { $0.id != item.id }
        if let data = try? JSONEncoder().encode(Array(items.prefix(kept))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Something from Opened lately, opened again full screen: the room's own page for it, once the
/// room's list is in hand (asked for here, because the viewer asked for the thing).
private struct TVOpenedScreen: View {
    let item: OpenedLately.Item
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            content
        }
        .foregroundStyle(palette.ink)
        .task(id: model.auth.previewPassword) {
            switch item.kind {
            case .film: await model.films.load()
            case .object: await model.bazaar.load(); await model.bazaarSwap.load()
            case .writing: await model.madrassaPosts.load()
            case .reading, .database: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .film:
            if let film = model.films.films.first(where: { $0.handle == item.ref }) {
                TVFilmPage(film: film)
            } else if model.films.state == .ready {
                gone
            } else {
                TuningLoader("Loading\u{2026}")
            }
        case .object:
            if let found = model.bazaar.value?.first(where: { $0.product.h == item.ref }) {
                TVProductScreen(item: found)
            } else if model.bazaar.value != nil {
                gone
            } else {
                TVFeedNote(feed: model.bazaar, subject: "The Bazaar's catalogue")
            }
        case .writing:
            if let post = model.madrassaPosts.value?.first(where: { $0.handle == item.ref }) {
                TVMadrassa.reading(post, model: model)
            } else if model.madrassaPosts.value != nil {
                gone
            } else {
                TVFeedNote(feed: model.madrassaPosts, subject: "The Madrassa")
            }
        case .database:
            if let db = ArchiveDatabase(rawValue: item.ref) { TVDatabaseScreen(db: db) } else { gone }
        case .reading:
            gone
        }
    }

    private var gone: some View {
        Text("\(item.title) is not in the \(item.kind.place) now.").kjBody().padding(KJLayout.inset)
    }
}

/// A room's state when it has nothing to show yet: loading, behind the site password, failed.
struct TVFeedNote<Value: Sendable>: View {
    let feed: SiteFeed<Value>
    let subject: String

    var body: some View {
        switch feed.state {
        case .idle, .loading: TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity)
        case .locked:
            Text("\(subject) is behind the site password while the archive is in preview. Set it under Account.").kjBody()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 20) {
                Text(message).kjBody()
                Button { Task { await feed.load(force: true) } } label: { Text("Try again").kjKicker() }
                    .buttonStyle(HouseButtonStyle())
            }
        case .ready: EmptyView()
        }
    }
}

/// A room's page: its title large, its line, then its shelves.
struct TVPage<Content: View>: View {
    let title: String
    let line: String?
    let content: Content

    init(_ title: String, line: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.line = line
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                    if let line { Text(line).kjBody() }
                }
                content
            }
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kjTopFade()
    }
}

/// A picture from the site, fitted whole in the space it is given and faded in; nothing until it
/// arrives. The preview password goes only to the site's own host.
struct TVPicture: View {
    let url: URL
    let maxPixel: Int
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                FadeIn(shown: image != nil) {
                    Image(uiImage: image ?? UIImage()).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
            .task(id: url) {
                image = await PnvImages.shared.image([url], maxPixel: maxPixel, authorization: model.siteAuthorization(for: url))
            }
    }
}

/// A rule between rows, as a table draws one: across, never around (owner ruling 2026-09-10).
struct Hairline: View {
    @Environment(\.palette) private var palette
    var body: some View { Rectangle().fill(palette.ink.opacity(0.2)).frame(height: 1) }
}

// MARK: - Databases

/// The research systems as tiles; a system opens as a table, a record as its properties, the way
/// Notion lays a database. Long queries stay on the phone, the Mac and the website.
private struct TVDatabases: View {
    @State private var open: ArchiveDatabase?

    private static let columns = Array(repeating: GridItem(.fixed(480), spacing: 40, alignment: .top), count: 3)

    var body: some View {
        TVPage("Databases", line: "Eight research systems. Record previews here; searching in depth is on the phone, the Mac and the website.") {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 50) {
                ForEach(DatabaseShelf.allCases) { shelf in
                    ForEach(shelf.databases) { db in
                        Button { open = db } label: {
                            CardPlate(width: 480, height: 250) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Kicker(shelf.kicker).lineLimit(1)
                                    Text(db.title).kjName(32).lineLimit(2)
                                    Text(shelf.line).kjSmall(faint: true).lineLimit(3)
                                }
                            }
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("tvdb-\(db.rawValue)")
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .fullScreenCover(item: $open) { db in TVDatabaseScreen(db: db) }
    }
}

/// A database on the TV, as Notion's toolbar: a search bar, then Filter and Sort, each opening a
/// panel of choices, the filters in force as pills that take themselves off when pressed, and the
/// records as a table, hairlines between rows, the title and two properties in columns. Select
/// opens the record. The search reads what the phone's does: every word must be in the title, the
/// title in its own script, or any property (artist, album, label, year…), accents and case aside.
private struct TVDatabaseScreen: View {
    let db: ArchiveDatabase
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var facets: [String: String] = [:]
    @State private var sort: DBSort = .listed
    @State private var record: DBRecord?
    @State private var panel: Panel?
    /// What is typed; the table follows once typing pauses, searched off the main actor, so the
    /// largest index (45,568 records) is neither searched nor counted again on every key.
    @State private var query = ""
    @State private var shown: Shown?
    /// Each property's values with their counts, worked out once per load rather than on every
    /// draw; only properties with a choice to make are kept.
    @State private var facetValues: [(name: String, values: [(value: String, count: Int)])] = []
    /// Whether any record carries a year, so the year orders are offered only where they mean something.
    @State private var hasYears = false

    private enum Panel: String, Identifiable {
        case filter, sort
        var id: String { rawValue }
    }

    private struct Shown {
        let query: String
        let records: [DBRecord]
    }

    private struct Ask: Equatable {
        let query: String
        let facets: [String: String]
        let sort: DBSort
        let loaded: Int
    }

    private static let shown = 300
    private static let titleWidth: CGFloat = 760
    private static let columnWidth: CGFloat = 340

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            TVPage(db.title, line: db.isMetadataOnly ? "Metadata only; no playable audio." : nil) {
                if let records = model.database(db).value {
                    table(records)
                } else {
                    TVFeedNote(feed: model.database(db), subject: "This database")
                }
            }
        }
        .foregroundStyle(palette.ink)
        .onAppear { OpenedLately.record(.database, ref: db.rawValue, title: db.title) }
        .task(id: model.auth.previewPassword) { await model.database(db).load() }
        .task(id: model.database(db).value?.count ?? 0) {
            guard let records = model.database(db).value else { return }
            let names = db.facetNames
            let (values, years) = await Task.detached {
                (names.map { (name: $0, values: Array(DBQuery.values($0, in: records).prefix(200))) }.filter { $0.values.count > 1 },
                 records.contains { DBQuery.year($0) != nil })
            }.value
            facetValues = values
            hasYears = years
        }
        .task(id: Ask(query: query, facets: facets, sort: sort, loaded: model.database(db).value?.count ?? 0)) {
            guard let records = model.database(db).value else { return }
            let typed = query, chosen = facets, order = sort
            if shown != nil && !typed.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let found = await Task.detached { DBQuery.sort(DBQuery.filter(records, text: typed, facets: chosen), by: order) }.value
            if !Task.isCancelled { shown = Shown(query: typed, records: found) }
        }
        .fullScreenCover(item: $record) { item in TVRecordScreen(db: db, record: item) }
        .fullScreenCover(item: $panel) { which in
            switch which {
            case .filter:
                TVFilterPanel(properties: facetValues, chosen: facets) { name, value in facets[name] = value }
            case .sort:
                TVSortPanel(orders: DBSort.allCases.filter { $0 == .listed || $0 == .title || hasYears }, chosen: sort) { sort = $0 }
            }
        }
    }

    @ViewBuilder
    private func table(_ records: [DBRecord]) -> some View {
        HouseInputField("Search", text: query, hint: db.isMetadataOnly ? "Song, artist, album, label, year" : "Title, name, place, year") {
            TextField("", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        toolbar
        let found = shown?.records ?? []
        // Said once the first answer is in, so it never reads "0 of" while the table is being found.
        if shown != nil {
            Text("\(found.count.formatted()) of \(records.count.formatted()) records" + (found.count > Self.shown ? " \u{00B7} the first \(Self.shown) here" : ""))
                .kjSmall(faint: true)
                .accessibilityIdentifier("tvdbCount")
        }
        if let applied = shown, found.isEmpty, !applied.query.isEmpty || !facets.isEmpty {
            Text(applied.query.isEmpty ? "No record matches the filters." : "No record\(facets.isEmpty ? "" : " under these filters") has every word of \u{201C}\(applied.query)\u{201D}.").kjBody()
        }
        // The table's columns are the first record's first two properties.
        let columns = Array((records.first?.fields ?? []).prefix(2).map(\.label))
        HStack(spacing: 24) {
            Text("Record").frame(width: Self.titleWidth, alignment: .leading)
            ForEach(columns, id: \.self) { Text($0).frame(width: Self.columnWidth, alignment: .leading) }
        }
        .kjKicker(palette.faint)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .accessibilityHidden(true)
        // Lazy: up to 300 rows, and only those on screen are built.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(found.prefix(Self.shown)) { item in
                Button { record = item } label: { row(item, columns: columns) }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
                    .accessibilityIdentifier("tvrecord-\(item.id)")
                Hairline()
            }
        }
    }

    /// Filter and Sort, as Notion's toolbar has them, then a pill for each filter in force: Select
    /// on a pill takes it off.
    private var toolbar: some View {
        HStack(spacing: 12) {
            if !facetValues.isEmpty {
                Button { panel = .filter } label: {
                    Label(facets.isEmpty ? "Filter" : "Filter \u{00B7} \(facets.count)", systemImage: "line.3.horizontal.decrease").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("tvdbFilter")
            }
            Button { panel = .sort } label: {
                Label(sort == .listed ? "Sort" : "Sort \u{00B7} \(sort.title)", systemImage: "arrow.up.arrow.down").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .accessibilityIdentifier("tvdbSort")
            ForEach(facets.keys.sorted(), id: \.self) { name in
                Button { facets[name] = nil } label: {
                    Label("\(name): \(facets[name] ?? "")", systemImage: "xmark").kjKicker().lineLimit(1)
                }
                // Not solid: the screen's one solid action is none of these.
                .buttonStyle(HouseButtonStyle())
                .accessibilityLabel("Remove the filter \(name), \(facets[name] ?? "")")
                .accessibilityIdentifier("tvdbPill-\(name)")
            }
        }
        // The plates' padding is pulled back so their text sits on the page margin.
        .padding(.leading, -26)
        .focusSection()
    }

    private func row(_ item: DBRecord, columns: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).kjName(30).lineLimit(2)
                if !item.subtitle.isEmpty { Text(item.subtitle).kjSmall(faint: true).lineLimit(1) }
            }
            .frame(width: Self.titleWidth, alignment: .leading)
            ForEach(columns, id: \.self) { label in
                Text(item.fields.first { $0.label == label }?.value ?? "")
                    .kjSmall()
                    .lineLimit(2)
                    .frame(width: Self.columnWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Notion's Filter menu on the remote: the properties down the left, the chosen one's values with
/// their counts beside them. Select on a value applies it and closes the panel; All lifts that
/// property's filter. Menu closes it with nothing changed.
private struct TVFilterPanel: View {
    let properties: [(name: String, values: [(value: String, count: Int)])]
    let chosen: [String: String]
    let apply: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var property: String?

    var body: some View {
        let current = properties.first { $0.name == property } ?? properties.first
        ZStack {
            palette.ground.ignoresSafeArea()
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                    ForEach(properties, id: \.name) { item in
                        Button { property = item.name } label: {
                            Text(item.name + (chosen[item.name].map { " \u{00B7} \($0)" } ?? "")).kjKicker().lineLimit(1)
                        }
                        .buttonStyle(HouseTabStyle(isCurrent: item.name == current?.name))
                        .accessibilityIdentifier("tvdbProperty-\(item.name)")
                    }
                }
                .frame(width: 520, alignment: .leading)
                .focusSection()
                if let current {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            choice("All", on: chosen[current.name] == nil) { apply(current.name, nil) }
                            ForEach(current.values, id: \.value) { value in
                                choice("\(value.value) \u{00B7} \(value.count.formatted())", on: chosen[current.name] == value.value) {
                                    apply(current.name, value.value)
                                }
                                .accessibilityIdentifier("tvdbValue-\(value.value)")
                            }
                        }
                    }
                    .focusSection()
                }
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
    }

    private func choice(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button { action(); dismiss() } label: {
                HStack {
                    Text(title).kjBody().lineLimit(1)
                    Spacer(minLength: 0)
                    if on { Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).accessibilityHidden(true) }
                }
                .frame(maxWidth: 900, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
            .accessibilityAddTraits(on ? .isSelected : [])
            Hairline()
        }
    }
}

/// Notion's Sort menu on the remote: the orders this database can take, the one in force ticked.
private struct TVSortPanel: View {
    let orders: [DBSort]
    let chosen: DBSort
    let apply: (DBSort) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("Sort").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader).padding(.bottom, 20)
                ForEach(orders) { order in
                    Button { apply(order); dismiss() } label: {
                        HStack {
                            Text(order.title).kjBody()
                            Spacer(minLength: 0)
                            if order == chosen { Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).accessibilityHidden(true) }
                        }
                        .frame(maxWidth: 700, alignment: .leading)
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
                    .accessibilityAddTraits(order == chosen ? .isSelected : [])
                    .accessibilityIdentifier("tvdbOrder-\(order.rawValue)")
                    Hairline().frame(maxWidth: 732)
                }
                Spacer(minLength: 0)
            }
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.ink)
    }
}

/// A record as a property page: the label column beside the value, a hairline between, and the
/// record's picture where it has one. Each property is a focus stop, so the remote walks down a
/// long record and the screen follows.
private struct TVRecordScreen: View {
    let db: ArchiveDatabase
    let record: DBRecord
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Kicker(db.title).padding(.bottom, 12)
                    Text(record.title).kjName(56).accessibilityAddTraits(.isHeader)
                    if let native = record.native {
                        // Native script is never letter-spaced.
                        Text(native).font(.system(size: 40, weight: .bold)).foregroundStyle(palette.faint).padding(.top, 6)
                    }
                    if !record.subtitle.isEmpty { Text(record.subtitle).kjBody().padding(.top, 8) }
                    if let image = record.image {
                        TVPicture(url: image, maxPixel: 900).frame(maxWidth: 520, minHeight: 300, maxHeight: 300, alignment: .leading)
                            .padding(.top, 24)
                    }
                    Spacer().frame(height: 32)
                    ForEach(Array(record.fields.enumerated()), id: \.offset) { _, field in
                        Button { } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 32) {
                                // The accent, which the focus plate re-skins; a colour named here would not follow it.
                                Text(field.label).kjKicker().frame(width: 380, alignment: .leading)
                                Text(field.value).kjBody().frame(maxWidth: 1100, alignment: .leading)
                            }
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)))
                        .accessibilityLabel("\(field.label): \(field.value)")
                        Hairline()
                    }
                    if let link = record.link {
                        Text("\(record.linkLabel ?? "Source"): " + (link.host ?? "") + link.path)
                            .kjSmall(faint: true).padding(.top, 24)
                    }
                    Text("Searching and comparing records is on the phone, the Mac and the website.")
                        .kjSmall(faint: true).padding(.top, 8)
                }
                .padding(KJLayout.inset)
            }
        }
        .foregroundStyle(palette.ink)
    }
}
