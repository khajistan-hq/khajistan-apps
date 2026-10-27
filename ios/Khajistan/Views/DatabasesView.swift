import SwiftUI

/// The eight research systems as databases.html lists them; Cinema of the Middle World opens on its
/// four indexes. A record shows every field its database gives, named in that database's terms.
struct DatabaseShelves: View {
    var body: some View {
        ForEach(DatabaseShelf.allCases) { shelf in
            VStack(alignment: .leading, spacing: 4) {
                Kicker("DB \(String(format: "%02d", shelf.rawValue)) \u{00B7} \(shelf.kicker)")
                Text(shelf.title).kjName(KJType.title).accessibilityAddTraits(.isHeader)
                Text(shelf.line).kjSmall(faint: true)
                ForEach(shelf.databases) { db in
                    NavigationLink(value: RoomRoute.database(db.rawValue)) {
                        HStack {
                            Text(shelf.databases.count > 1 ? db.title : "Open the index").kjKicker()
                            Text("\u{2192}").kjKicker().accessibilityHidden(true)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(db.title)
                    .accessibilityIdentifier("db-\(db.rawValue)")
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// One database: a search field, its facets, the result count, and the records. In a wide window
/// the chosen record stands beside the list.
struct DatabaseScreen: View {
    let db: ArchiveDatabase

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    @State private var facets: [String: String] = [:]
    @State private var sort: DBSort = .listed
    @State private var results: [DBRecord] = []
    @State private var limit = Self.page
    @State private var selected: DBRecord?

    private static let page = 120
    private var feed: SiteFeed<[DBRecord]> { model.database(db) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PageHead(kicker: "Databases", db.title, line: db.isMetadataOnly ? "Metadata only; no playable audio." : nil)
                    if let records = feed.value {
                        controls(records)
                        list
                    } else {
                        FeedState(feed: feed, subject: "This database")
                    }
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: sizeClass == .regular ? 460 : .infinity)
            if sizeClass == .regular {
                Rectangle().fill(palette.ink.opacity(0.18)).frame(width: 1).accessibilityHidden(true)
                ScrollView {
                    if let selected { RecordDetail(db: db, record: selected) } else {
                        Text("Choose a record.").kjBody().foregroundStyle(palette.faint).padding(KJLayout.inset)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: model.auth.previewPassword) { await feed.load() }
        // Filtering runs a moment after the last keystroke, and a newer query replaces an older one.
        .task(id: "\(query)|\(facets)|\(sort.rawValue)|\(feed.value?.count ?? -1)") {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let records = feed.value else { return }
            let text = query, chosen = facets, order = sort
            let found = await Task.detached(priority: .userInitiated) {
                DBQuery.sort(DBQuery.filter(records, text: text, facets: chosen), by: order)
            }.value
            guard !Task.isCancelled else { return }
            results = found
            limit = Self.page
        }
    }

    @ViewBuilder
    private func controls(_ records: [DBRecord]) -> some View {
        HouseInputField("Search \(db.title)") {
            TextField("", text: $query, prompt: Text("Every word must match").foregroundStyle(palette.faint))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("dbSearch")
        }
        ForEach(db.facetNames, id: \.self) { name in
            let values = DBQuery.values(name, in: records)
            if values.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Text(name).kjSmall(faint: true).padding(.trailing, 4)
                        facetChip(name, nil, title: "All")
                        ForEach(values.prefix(40), id: \.value) { facetChip(name, $0.value, title: "\($0.value) \u{00B7} \($0.count.formatted())") }
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, -12)
            }
        }
        // Year orders are offered only where the records carry a year.
        let orders = DBSort.allCases.filter { $0 == .listed || $0 == .title || records.contains { DBQuery.year($0) != nil } }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text("Sort").kjSmall(faint: true).padding(.trailing, 4)
                ForEach(orders) { order in
                    Button { sort = order } label: { Text(order.title).kjKicker() }
                        .buttonStyle(HouseTabStyle(isCurrent: sort == order))
                        .accessibilityIdentifier("dbSort-\(order.rawValue)")
                }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, -12)
        HStack {
            Text("\(results.count.formatted()) of \(records.count.formatted()) records").kjSmall(faint: true)
                .accessibilityIdentifier("dbCount")
            if !facets.isEmpty || !query.isEmpty {
                Button(kicker: "Clear") { query = ""; facets = [:] }.accessibilityIdentifier("dbClear")
            }
        }
    }

    private func facetChip(_ name: String, _ value: String?, title: String) -> some View {
        Button { facets[name] = value } label: { Text(title).kjKicker().lineLimit(1) }
            .buttonStyle(HouseTabStyle(isCurrent: facets[name] == value))
            .accessibilityIdentifier("dbFacet-\(name)-\(value ?? "all")")
    }

    @ViewBuilder
    private var list: some View {
        if results.isEmpty, feed.value != nil {
            Text("No record matches.").kjBody().accessibilityIdentifier("dbNone")
        }
        ForEach(results.prefix(limit)) { record in
            if sizeClass == .regular {
                Button { selected = record } label: { RecordRow(record: record, isSelected: selected?.id == record.id) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-\(record.id)")
            } else {
                NavigationLink(value: RoomRoute.record(db.rawValue, record.id)) { RecordRow(record: record, isSelected: false) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-\(record.id)")
            }
        }
        if results.count > limit {
            Button(kicker: "Show \(min(Self.page, results.count - limit)) more") { limit += Self.page }
                .accessibilityIdentifier("dbMore")
        }
    }
}

private struct RecordRow: View {
    let record: DBRecord
    let isSelected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = record.image { RecordPicture(url: image).frame(width: 64, height: 48) }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).kjName().foregroundStyle(isSelected ? palette.accent : palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(3)
                if let native = record.native { Text(native).kjSmall() }
                if !record.subtitle.isEmpty { Text(record.subtitle).kjSmall(faint: true).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct RecordPicture: View {
    let url: URL
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay { if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } }
            .accessibilityHidden(true)
            .task(id: url) { image = await PnvImages.shared.image([url], maxPixel: 480, authorization: model.siteAuthorization(for: url)) }
    }
}

/// A record, every field its database gives, and the source it cites.
struct RecordDetail: View {
    let db: ArchiveDatabase
    let record: DBRecord
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(db.title)
            Text(record.title).kjDisplay(KJType.headline, tracking: -0.04).accessibilityAddTraits(.isHeader)
            if let native = record.native { Text(native).kjName(KJType.title) }
            if let image = record.image { RecordPicture(url: image).frame(maxWidth: 400, maxHeight: 240) }
            ForEach(record.fields, id: \.self) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label).kjSmall(faint: true)
                    Text(field.value).kjBody().fixedSize(horizontal: false, vertical: true)
                }
            }
            if db.isMetadataOnly { Text("Metadata only; no playable audio.").kjSmall(faint: true) }
            if let link = record.link {
                Button(kicker: "\(record.linkLabel ?? "Source") \u{2197}") {
                    // A page of the archive opens in the house browser; any other source in Safari.
                    if ArchiveURL.isArchive(link) { model.open(link) } else { openURL(link) }
                }
                .accessibilityIdentifier("recordLink")
            }
            Button(kicker: "This database on the website \u{2197}") {
                model.open(ArchiveURL.base.appendingPathComponent(db.page))
            }
        }
        .padding(KJLayout.inset)
        .textSelection(.enabled)
        .frame(maxWidth: KJLayout.readingWidth, alignment: .leading)
    }
}

/// A record pushed on a phone's stack.
struct RecordScreen: View {
    let db: ArchiveDatabase
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let record = model.database(db).value?.first(where: { $0.id == id }) {
                RecordDetail(db: db, record: record)
            } else {
                FeedState(feed: model.database(db), subject: "This database").padding(KJLayout.inset)
            }
        }
        .task { await model.database(db).load() }
    }
}
