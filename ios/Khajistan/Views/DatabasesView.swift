import SwiftUI

/// The eight research systems as databases.html lists them; Cinema of the Middle World opens on its
/// four indexes. A record shows every field its database gives, named in that database's terms.
struct DatabaseShelves: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ForEach(DatabaseShelf.allCases) { shelf in
            VStack(alignment: .leading, spacing: 2) {
                Text("DB \(String(format: "%02d", shelf.rawValue)) \u{00B7} \(shelf.kicker)").kjSmall(faint: true)
                Text(shelf.title).font(.system(.title3, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(shelf.line).kjSmall(faint: true).padding(.bottom, 4)
                ForEach(shelf.databases) { db in
                    NavigationLink(value: RoomRoute.database(db.rawValue)) {
                        HStack(spacing: 10) {
                            Image(systemName: "tablecells").foregroundStyle(palette.accent).accessibilityHidden(true)
                            Text(shelf.databases.count > 1 ? db.title : "Open the index").font(.system(.body, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(.subheadline, weight: .bold))
                                .foregroundStyle(palette.faint).accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(db.title)
                    .accessibilityIdentifier("db-\(db.rawValue)")
                }
            }
            .padding(.vertical, 8)
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
    /// Whether any record carries a year, worked out once when the records arrive.
    @State private var hasYears = false
    /// Each facet with more than one value and its first 60 values, worked out once when the
    /// records arrive rather than on every keystroke in the search field.
    @State private var facetValues: [(name: String, values: [(value: String, count: Int)])] = []
    @State private var results: [DBRecord] = []
    /// False until the first filter has run, so an empty list never reads as "no match" while it fills.
    @State private var filtered = false
    @State private var limit = Self.page
    @State private var selected: DBRecord?

    private static let page = 120
    private var feed: SiteFeed<[DBRecord]> { model.database(db) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    LargeTitle(title: db.title, line: db.isMetadataOnly ? "Metadata only; no playable audio." : nil)
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
        // Worked out when the records arrive, however they arrive (a retry included), as tvOS does.
        .task(id: feed.value?.count ?? 0) {
            guard let records = feed.value else { return }
            let names = db.facetNames
            (facetValues, hasYears) = await Task.detached(priority: .utility) {
                (names.map { (name: $0, values: Array(DBQuery.values($0, in: records).prefix(60))) }.filter { $0.values.count > 1 },
                 records.contains { DBQuery.year($0) != nil })
            }.value
        }
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
            filtered = true
            limit = Self.page
        }
    }

    /// Notion's database toolbar: search, then Filter and Sort as menus, the filters in force as
    /// pills that take themselves off, and the count.
    @ViewBuilder
    private func controls(_ records: [DBRecord]) -> some View {
        SearchField(prompt: "Every word must match", text: $query, id: "dbSearch")
            .textInputAutocapitalization(.never)
        // Year orders are offered only where the records carry a year.
        let orders = DBSort.allCases.filter { $0 == .listed || $0 == .title || hasYears }
        HStack(spacing: 8) {
            if !facetValues.isEmpty {
                Menu {
                    ForEach(facetValues, id: \.name) { facet in
                        let name = facet.name
                        Menu(name) {
                            Button("All") { facets[name] = nil }
                            ForEach(facet.values, id: \.value) { value in
                                Button { facets[name] = value.value } label: {
                                    if facets[name] == value.value { Label("\(value.value) \u{00B7} \(value.count.formatted())", systemImage: "checkmark") }
                                    else { Text("\(value.value) \u{00B7} \(value.count.formatted())") }
                                }
                                .accessibilityIdentifier("dbFacet-\(name)-\(value.value)")
                            }
                        }
                    }
                } label: { toolbarPill("Filter", symbol: "line.3.horizontal.decrease", on: !facets.isEmpty) }
                .accessibilityIdentifier("dbFilterMenu")
            }
            Menu {
                ForEach(orders) { order in
                    Button { sort = order } label: {
                        if sort == order { Label(order.title, systemImage: "checkmark") } else { Text(order.title) }
                    }
                    .accessibilityIdentifier("dbSort-\(order.rawValue)")
                }
            } label: { toolbarPill(sort == .listed ? "Sort" : sort.title, symbol: "arrow.up.arrow.down", on: sort != .listed) }
            .accessibilityIdentifier("dbSortMenu")
            Spacer(minLength: 0)
        }
        if !facets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(facets.keys.sorted(), id: \.self) { name in
                        Button { facets[name] = nil } label: {
                            HStack(spacing: 6) {
                                Text("\(name): \(facets[name] ?? "")").font(.system(.subheadline, weight: .semibold)).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(palette.ground)
                            .background(palette.ink, in: Capsule())
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove the filter \(name), \(facets[name] ?? "")")
                    }
                }
            }
            .scrollClipDisabled()
        }
        if filtered { HStack {
            Text("\(results.count.formatted()) of \(records.count.formatted()) records").kjSmall(faint: true)
                .accessibilityIdentifier("dbCount")
            Spacer()
            if !facets.isEmpty || !query.isEmpty {
                Button(kicker: "Clear") { query = ""; facets = [:] }.accessibilityIdentifier("dbClear")
            }
        } }
    }

    private func toolbarPill(_ title: String, symbol: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(.subheadline, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(minHeight: 34)
        .foregroundStyle(on ? palette.ground : palette.ink)
        .background(on ? palette.ink : palette.lift, in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var list: some View {
        if filtered, results.isEmpty {
            Text("No record matches.").kjBody().accessibilityIdentifier("dbNone")
        }
        LazyVStack(spacing: 0) { ForEach(results.prefix(limit)) { record in
            if sizeClass == .regular {
                Button { selected = record } label: { RecordRow(record: record, isSelected: selected?.id == record.id) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-\(record.id)")
            } else {
                NavigationLink(value: RoomRoute.record(db.rawValue, record.id)) { RecordRow(record: record, isSelected: false) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record-\(record.id)")
            }
        } }
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
        // A table row, as Notion draws one: the title, its other columns faint beside it, a hairline under.
        HStack(alignment: .center, spacing: 12) {
            if let image = record.image { RecordPicture(url: image).frame(width: 56, height: 42) }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).font(.system(.body, weight: .semibold)).foregroundStyle(isSelected ? palette.accent : palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(3)
                if let native = record.native { Text(native).kjSmall() }
                if !record.subtitle.isEmpty { Text(record.subtitle).kjSmall(faint: true).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.faint).accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.ink.opacity(0.12)).frame(height: 1) }
        .background(isSelected ? palette.lift : Color.clear)
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
        // A Notion page: the title large, then each property as a label column and its value.
        VStack(alignment: .leading, spacing: 12) {
            Text(db.title).kjSmall(faint: true)
            Text(record.title).font(.system(.largeTitle, weight: .bold)).accessibilityAddTraits(.isHeader)
            if let native = record.native { Text(native).kjName(KJType.title) }
            if let image = record.image { RecordPicture(url: image).frame(maxWidth: 400, maxHeight: 240) }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(record.fields, id: \.self) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(field.label).kjSmall(faint: true).frame(width: 112, alignment: .leading)
                        Text(field.value).kjBody().fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if db.isMetadataOnly { Text("Metadata only; no playable audio.").kjSmall(faint: true) }
            if let link = record.link {
                Button {
                    // A page of the archive opens in the house browser; any other source in Safari.
                    if ArchiveURL.isArchive(link) { model.open(link) } else { openURL(link) }
                } label: { Label(record.linkLabel ?? "Source", systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(SolidActionStyle())
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
