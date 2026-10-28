import SwiftUI

/// ROOMS on the Apple TV: the Screening Room, the Bazaar, the Madrassa and the research databases,
/// grouped under one door so the top bar stays legible from the couch. The door is laid out as the
/// Apple TV app lays its own: a row of large tiles, then Up Next from this device. Each room opens
/// full screen; Menu comes back here. What needs a keyboard or a payment (a checkout, a long query)
/// is named as a place on the website, never a form on the remote.
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
        var symbol: String {
            switch self {
            case .screening: return "film"
            case .bazaar: return "bag"
            case .madrassa: return "books.vertical"
            case .databases: return "tablecells"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var open: Room?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rooms").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                Text("Films, objects, writings and research, beside the Receiver and the Reading Room.").kjBody()
                HStack(spacing: 40) {
                    ForEach(Room.allCases) { room in
                        Button { open = room } label: { RoomTile(room: room, figure: figure(room)) }
                            .buttonStyle(HouseCardStyle())
                            .accessibilityIdentifier("tvroom-\(room.rawValue)")
                    }
                }
                // Room over and under the tiles for the lift and its shadow.
                .padding(.vertical, 40)
                .focusSection()
                // Only this device's places, and only once the catalogue is already loaded: the
                // door starts no download of its own.
                let stopped = model.films.state == .ready ? FilmPlaces.stopped(model.films.films) : []
                if !stopped.isEmpty {
                    FilmShelf(title: "Up Next", count: stopped.count.formatted(), films: stopped, opensPage: true, showsPlaces: true)
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kjTopFade()
        .fullScreenCover(item: $open) { room in
            TVRoomScreen(room: room)
        }
        #if DEBUG
        // `-kjroom screening` opens a room at launch, as on the phone, for a look at it.
        .task {
            if let name = UserDefaults.standard.string(forKey: "kjroom") { open = Room(rawValue: name) }
        }
        #endif
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

/// A room's tile: its mark large, the name, the room's line. The plate takes focus as every text
/// card does.
private struct RoomTile: View {
    let room: RoomsTVView.Room
    let figure: String?

    var body: some View {
        CardPlate(width: 365, height: 330) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: room.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let figure { Kicker(figure).lineLimit(1) }
                Text(room.title).kjName(36).lineLimit(2)
                Text(room.line).kjSmall(faint: true).lineLimit(3)
            }
        }
    }
}

private struct TVRoomScreen: View {
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

/// A database on the TV: a search bar, its first facet as tabs, then the records as a table,
/// hairlines between rows, the title and two properties in columns. Select opens the record. The
/// search reads what the phone's does: every word must be in the title, the title in its own
/// script, or any property (artist, album, label, year…), accents and case aside.
private struct TVDatabaseScreen: View {
    let db: ArchiveDatabase
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var facet: String?
    @State private var record: DBRecord?
    /// What is typed; the table follows once typing pauses, searched off the main actor, so the
    /// largest index (45,568 records) is neither searched nor counted again on every key.
    @State private var query = ""
    @State private var shown: Shown?
    /// The first facet's values, counted once per load rather than on every draw.
    @State private var facetValues: [(value: String, count: Int)] = []

    private struct Shown {
        let query: String
        let records: [DBRecord]
    }

    private struct Ask: Equatable {
        let query: String
        let facet: String?
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
        .task(id: model.auth.previewPassword) { await model.database(db).load() }
        .task(id: model.database(db).value?.count ?? 0) {
            guard let records = model.database(db).value else { return }
            let name = db.facetNames.first ?? ""
            facetValues = Array(await Task.detached { DBQuery.values(name, in: records) }.value.prefix(8))
        }
        .task(id: Ask(query: query, facet: facet, loaded: model.database(db).value?.count ?? 0)) {
            guard let records = model.database(db).value else { return }
            let typed = query, name = db.facetNames.first ?? "", chosen = facet.map { [name: $0] } ?? [:]
            if shown != nil && !typed.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let found = await Task.detached { DBQuery.filter(records, text: typed, facets: chosen) }.value
            if !Task.isCancelled { shown = Shown(query: typed, records: found) }
        }
        .fullScreenCover(item: $record) { item in TVRecordScreen(db: db, record: item) }
    }

    @ViewBuilder
    private func table(_ records: [DBRecord]) -> some View {
        HouseInputField("Search", text: query, hint: db.isMetadataOnly ? "Song, artist, album, label, year" : "Title, name, place, year") {
            TextField("", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        let values = facetValues
        if values.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tab("All", nil)
                    ForEach(Array(values), id: \.value) { tab("\($0.value) \u{00B7} \($0.count.formatted())", $0.value) }
                }
            }
            .focusSection()
        }
        let found = shown?.records ?? []
        // Said once the first answer is in, so it never reads "0 of" while the table is being found.
        if shown != nil {
            Text("\(found.count.formatted()) of \(records.count.formatted()) records" + (found.count > Self.shown ? " \u{00B7} the first \(Self.shown) here" : ""))
                .kjSmall(faint: true)
                .accessibilityIdentifier("tvdbCount")
        }
        if let applied = shown?.query, found.isEmpty, !applied.isEmpty {
            Text("No record\(facet.map { " under \($0)" } ?? "") has every word of \u{201C}\(applied)\u{201D}.").kjBody()
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(found.prefix(Self.shown)) { item in
                Button { record = item } label: { row(item, columns: columns) }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
                    .accessibilityIdentifier("tvrecord-\(item.id)")
                Hairline()
            }
        }
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

    private func tab(_ title: String, _ value: String?) -> some View {
        Button { facet = value } label: { Text(title).kjKicker().lineLimit(1) }
            .buttonStyle(HouseTabStyle(isCurrent: facet == value))
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
