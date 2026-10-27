import SwiftUI

/// ROOMS on the Apple TV: the Screening Room, the Bazaar, the Madrassa and the research databases,
/// grouped under one door so the top bar stays legible from the couch. Each opens full screen;
/// Menu comes back here. What needs a keyboard or a payment (a checkout, a long query) is named as
/// a place on the website, never a form on the remote.
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
    }

    @State private var open: Room?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Shelf("Rooms") {
                    ForEach(Room.allCases) { room in
                        Button { open = room } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(room.title).kjName(40)
                                Text(room.line).kjSmall(faint: true).lineLimit(2)
                            }
                            .frame(width: 420, height: 180, alignment: .topLeading)
                            .padding(24)
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("tvroom-\(room.rawValue)")
                    }
                }
            }
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fullScreenCover(item: $open) { room in
            TVRoomScreen(room: room)
        }
    }
}

private struct TVRoomScreen: View {
    let room: RoomsTVView.Room
    @Environment(AppModel.self) private var model
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
private struct TVFeedNote<Value: Sendable>: View {
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

private struct TVPage<Content: View>: View {
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
    }
}

// MARK: - Screening Room

private struct TVScreeningRoom: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TVPage("Screening Room", line: "Films Khajistan holds and distributes, and institutional licensing.") {
            switch model.films.state {
            case .idle, .loading: TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity)
            case .locked: Text("The Screening Room's catalogue is behind the site password while the archive is in preview. Set it under Account.").kjBody()
            case .failed(let message): Text(message).kjBody()
            case .ready:
                let films = model.films.films
                let countries = Dictionary(grouping: films) { $0.country ?? "Elsewhere" }
                ForEach(countries.keys.sorted { (countries[$0]!.count, $1) > (countries[$1]!.count, $0) }, id: \.self) { country in
                    FilmShelf(title: country, count: countries[country]!.count.formatted(), films: countries[country]!)
                }
            }
        }
        .task(id: model.auth.previewPassword) { await model.films.load() }
    }
}

// MARK: - Bazaar

private struct TVBazaar: View {
    @Environment(AppModel.self) private var model
    @State private var showing: BazaarItem?

    var body: some View {
        TVPage("Bazaar", line: "Prints, objects, apparel and stickers. Buying is on khajistan.com.") {
            if let items = model.bazaar.value {
                ForEach([BazaarShelf.apparel, .prints, .stickers, .objects], id: \.self) { shelf in
                    let row = items.filter { $0.shelf == shelf }
                    if !row.isEmpty {
                        Shelf(shelf.title, count: row.count.formatted()) {
                            ForEach(row) { item in
                                Button { showing = item } label: { TVProductCard(item: item) }
                                    .buttonStyle(HouseCardStyle())
                                    .accessibilityIdentifier("tvproduct-\(item.product.h)")
                            }
                        }
                    }
                }
            } else {
                TVFeedNote(feed: model.bazaar, subject: "The Bazaar's catalogue")
            }
        }
        .task(id: model.auth.previewPassword) {
            await model.bazaar.load()
            await model.bazaarSwap.load()
        }
        .fullScreenCover(item: $showing) { item in TVProductScreen(item: item) }
    }
}

private struct TVProductCard: View {
    let item: BazaarItem
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(width: 320, height: 320)
                .overlay { if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } }
            Text(item.product.title).kjName(26).lineLimit(2).frame(width: 320, height: 70, alignment: .topLeading)
            Text(Bazaar.priceLine(item.product) ?? " ").kjSmall()
        }
        .task(id: item.id) {
            guard let url = Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 400) else { return }
            image = await PnvImages.shared.image([url], maxPixel: 640)
        }
    }
}

/// A product, with what the shop answers about it now, and where to buy it. No form on the TV.
private struct TVProductScreen: View {
    let item: BazaarItem
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var live: ShopStorefront.ProductAnswer?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                Color.clear.frame(width: 700, height: 700)
                    .overlay { if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 24) {
                    Kicker(item.shelf.title)
                    Text(item.product.title).kjName(64)
                    switch live {
                    case .found(let product):
                        let available = product.variants.filter(\.availableForSale)
                        if available.isEmpty {
                            Text("Sold out").kjName(40)
                        } else if let price = Bazaar.priceLine(item.product) {
                            Text(price).kjName(40)
                            if product.variants.count > 1 {
                                Text(available.map(\.title).joined(separator: " \u{00B7} ")).kjSmall(faint: true).lineLimit(4)
                            }
                        }
                    case .notForSale: Text("Not for sale online now.").kjBody()
                    case .unreadable: Text("The shop did not answer.").kjBody()
                    case nil: Kicker("Asking the shop\u{2026}")
                    }
                    Text("Buy it on your phone or computer:").kjBody()
                    Text("khajistan.com/products/\(item.product.h)").kjName(30).lineLimit(2).minimumScaleFactor(0.6)
                    // A focus target, so Menu and the remote have somewhere to land.
                    Button { } label: { Text("Back with Menu").kjKicker() }
                        .buttonStyle(HouseButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
        .task {
            if let url = Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 800) {
                image = await PnvImages.shared.image([url], maxPixel: 1200)
            }
            if let (data, response) = try? await URLSession.shared.data(for: ShopStorefront.productRequest(handle: item.product.h)),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                live = ShopStorefront.productAnswer(from: data)
            } else {
                live = .unreadable
            }
        }
    }
}

// MARK: - Madrassa

private struct TVMadrassa: View {
    @Environment(AppModel.self) private var model
    @State private var entry: MadrassaEntry?
    @State private var post: MadrassaPost?
    @State private var dictionary = false

    var body: some View {
        TVPage("Madrassa", line: "The reference wing \u{2014} street dictionary, indices and writings") {
            if let entries = model.madrassaEntries.value {
                Shelf("Reference", count: entries.count.formatted()) {
                    ForEach(entries) { item in
                        Button { entry = item } label: { textCard(item.cat, item.title, item.sub) }
                            .buttonStyle(HouseCardStyle())
                            .accessibilityIdentifier("tventry-\(item.id)")
                    }
                }
            } else {
                TVFeedNote(feed: model.madrassaEntries, subject: "The Madrassa")
            }
            if let posts = model.madrassaPosts.value {
                ForEach([false, true], id: \.self) { forensics in
                    let row = posts.filter { MadrassaWritings.isForensics($0) == forensics }
                    Shelf(forensics ? "Forensics" : "Writings", count: row.count.formatted()) {
                        ForEach(row) { item in
                            Button { post = item } label: { textCard(item.publishedAt ?? "", MadrassaWritings.listTitle(item), nil) }
                                .buttonStyle(HouseCardStyle())
                                .accessibilityIdentifier("tvpost-\(item.handle)")
                        }
                    }
                }
            }
            Shelf("Street Dictionary") {
                Button { dictionary = true } label: { textCard("lughat", "The Street Dictionary", model.lughat.value.map { "\($0.count.formatted()) entries" }) }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("tvdictionary")
            }
        }
        .task(id: model.auth.previewPassword) {
            await model.madrassaEntries.load()
            await model.madrassaPosts.load()
            await model.lughat.load()
        }
        .fullScreenCover(item: $entry) { item in
            TVReading(kicker: item.cat, title: item.title, blocks: [item.sub, item.desc].compactMap { $0 }.map { .paragraph(AttributedString($0)) },
                      website: item.href.map { "The full entry on the website: khajistan-archive.pages.dev/\($0)" })
        }
        .fullScreenCover(item: $post) { item in
            TVReading(kicker: MadrassaWritings.label(item), title: item.title, blocks: ArticleHTML.blocks(item.body ?? ""),
                      website: "Also on the website: khajistan-archive.pages.dev/\(MadrassaWritings.pagePath(item))")
        }
        .fullScreenCover(isPresented: $dictionary) { TVDictionary() }
    }

    private func textCard(_ kicker: String, _ title: String, _ line: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kicker).lineLimit(1)
            Text(title).kjName(32).lineLimit(3)
            if let line { Text(line).kjSmall(faint: true).lineLimit(2) }
        }
        .frame(width: 460, height: 220, alignment: .topLeading)
        .padding(22)
    }
}

/// A piece read whole on the TV: each block is a focus stop, so the remote moves down the text a
/// block at a time and the screen follows.
private struct TVReading: View {
    let kicker: String
    let title: String
    let blocks: [ArticleBlock]
    let website: String?
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Kicker(kicker)
                    Text(title).kjName(64).accessibilityAddTraits(.isHeader)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        Button { } label: { blockView(block).frame(maxWidth: 1300, alignment: .leading) }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                    }
                    if let website { Text(website).kjSmall(faint: true) }
                }
                .padding(KJLayout.inset)
            }
        }
        .foregroundStyle(palette.ink)
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .heading(let text): Text(text).kjName(40)
        case .paragraph(let text), .quote(let text), .item(let text): Text(String(text.characters)).kjBody()
        case .row(let cells): Text(cells.joined(separator: "    ")).kjBody()
        case .image: Text("A picture from the source.").kjSmall(faint: true)
        case .embed: Text("A player is embedded here; it plays on the website.").kjSmall(faint: true)
        case .rule: Rectangle().fill(palette.ink.opacity(0.2)).frame(height: 1)
        }
    }
}

private struct TVDictionary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var language: String?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            TVPage("Street Dictionary") {
                if let entries = model.lughat.value {
                    HStack(spacing: 8) {
                        ForEach([nil] + Lughat.languages(entries).prefix(6).map(Optional.some), id: \.self) { lang in
                            Button { language = lang } label: { Text(lang ?? "All").kjKicker() }
                                .buttonStyle(HouseTabStyle(isCurrent: language == lang))
                        }
                    }
                    .focusSection()
                    let shown = entries.filter { language == nil || $0.lang == language }
                    ForEach(shown.filter { !Lughat.isSetApart($0) }.prefix(300)) { row($0) }
                    let apart = shown.filter(Lughat.isSetApart)
                    if !apart.isEmpty {
                        Text(Lughat.setApartHeading).kjKicker()
                        Text(Lughat.setApartNote).kjBody()
                        ForEach(apart.prefix(300)) { row($0) }
                    }
                } else {
                    TVFeedNote(feed: model.lughat, subject: "The Street Dictionary")
                }
            }
        }
        .foregroundStyle(palette.ink)
    }

    private func row(_ entry: LughatEntry) -> some View {
        Button { } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text([entry.word, entry.translit].compactMap { $0 }.joined(separator: "  \u{00B7}  ")).kjName(32)
                if let meaning = entry.meaning ?? entry.gloss { Text(meaning).kjBody() }
                Text([entry.lang, entry.region, entry.sensitivity.map { "Sensitivity: \($0)" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .kjSmall(faint: true)
            }
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)))
    }
}

// MARK: - Databases

private struct TVDatabases: View {
    @State private var open: ArchiveDatabase?

    var body: some View {
        TVPage("Databases", line: "Eight research systems.") {
            ForEach(DatabaseShelf.allCases) { shelf in
                Shelf(shelf.title) {
                    ForEach(shelf.databases) { db in
                        Button { open = db } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Kicker(shelf.kicker)
                                Text(db.title).kjName(32).lineLimit(2)
                                Text(shelf.line).kjSmall(faint: true).lineLimit(3)
                            }
                            .frame(width: 520, height: 230, alignment: .topLeading)
                            .padding(22)
                        }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("tvdb-\(db.rawValue)")
                    }
                }
            }
        }
        .fullScreenCover(item: $open) { db in TVDatabaseScreen(db: db) }
    }
}

/// A database on the TV: its first facet as tabs, the records as rows, a record's every field.
/// Long queries belong on a keyboard; the rows here are for browsing.
private struct TVDatabaseScreen: View {
    let db: ArchiveDatabase
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var facet: String?
    @State private var record: DBRecord?

    private static let shown = 300

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            TVPage(db.title, line: db.isMetadataOnly ? "Metadata only; no playable audio." : nil) {
                if let records = model.database(db).value {
                    let name = db.facetNames.first ?? ""
                    let values = DBQuery.values(name, in: records).prefix(8)
                    if values.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                tab("All", nil)
                                ForEach(Array(values), id: \.value) { tab("\($0.value) \u{00B7} \($0.count.formatted())", $0.value) }
                            }
                        }
                        .focusSection()
                    }
                    let found = DBQuery.filter(records, text: "", facets: facet.map { [name: $0] } ?? [:])
                    Text("\(found.count.formatted()) of \(records.count.formatted()) records" + (found.count > Self.shown ? " \u{00B7} the first \(Self.shown) here" : ""))
                        .kjSmall(faint: true)
                    ForEach(found.prefix(Self.shown)) { item in
                        Button { record = item } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).kjName(30).lineLimit(2)
                                if !item.subtitle.isEmpty { Text(item.subtitle).kjSmall(faint: true).lineLimit(1) }
                            }
                            .frame(maxWidth: 1400, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)))
                        .accessibilityIdentifier("tvrecord-\(item.id)")
                    }
                } else {
                    TVFeedNote(feed: model.database(db), subject: "This database")
                }
            }
        }
        .foregroundStyle(palette.ink)
        .task(id: model.auth.previewPassword) { await model.database(db).load() }
        .fullScreenCover(item: $record) { item in
            TVReading(kicker: db.title, title: item.title,
                      blocks: ([item.native].compactMap { $0 } + item.fields.map { "\($0.label): \($0.value)" }).map { .paragraph(AttributedString($0)) },
                      website: item.link.map { "\(item.linkLabel ?? "Source"): " + ($0.host ?? "") + $0.path })
        }
    }

    private func tab(_ title: String, _ value: String?) -> some View {
        Button { facet = value } label: { Text(title).kjKicker().lineLimit(1) }
            .buttonStyle(HouseTabStyle(isCurrent: facet == value))
    }
}
