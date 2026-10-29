import SwiftUI

/// The Reading Room on a phone, tablet or Mac: the shelf the website draws at /reading-room.html
/// (the same feed, grouping and shelves as the Apple TV app, Core/ReadingRoom.swift). A tab per
/// language and a row per shelf when the module index is there, else one row per region; a field
/// narrows the shelf by name. Each cover is the real scanned first page, and each card says what
/// the page server told this viewer about it.
struct ReadingShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tabID: String?
    @State private var query = ""

    private var store: ReadingStore { model.reading }
    private var tab: RRTab? { store.tabs.first { $0.id == tabID } ?? store.tabs.first }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                LargeTitle(title: RRWords.heading,
                           line: store.phase == .ready && store.tabs.count > 1 ? RRShelves.depthLine(store.titles, rights: store.rights) : RRWords.lede)
                    .accessibilityIdentifier("rrTotal")
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the Reading Room\u{2026}")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await store.retry() } }
                case .ready:
                    SearchField(prompt: "Titles, in any script", text: $query, id: "rrSearch")
                    if !trimmed.isEmpty {
                        results
                    } else {
                        ContinueShelf()
                        if store.tabs.count > 1 {
                            ChipRow(chips: store.tabs.map { Chip(id: $0.id, title: $0.name, identifier: "rr-tab-\($0.id)") },
                                    selected: tab?.id ?? "") { tabID = $0 }
                        }
                        if let tab { shelf(tab) }
                    }
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await store.start() }
    }

    // MARK: - Search

    /// Titles whose name, native name or region matches, in shelf order. Reads the shelf already
    /// held; nothing is fetched.
    private var matches: [RRTitle] {
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return store.titles.filter { title in
            [title.name, title.native, title.byline].contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let found = matches
        Text(found.isEmpty ? "No title on the shelf matches \u{201C}\(trimmed)\u{201D}." : "\(found.count.formatted()) title\(found.count == 1 ? "" : "s")")
            .kjSmall(faint: true)
            .accessibilityIdentifier("rrSearchCount")
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(found) { title in
                NavigationLink(value: RoomRoute.readingTitle(title.slug)) {
                    HStack(alignment: .center, spacing: 14) {
                        RRCover(state: store.card(for: title)).frame(width: 64, height: 88)
                        ReadingCardText(title: title, access: store.access(for: title))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(palette.faint).accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { store.want(title) }
                .accessibilityIdentifier("rr-title-\(title.slug)")
            }
        }
    }

    // MARK: - Shelves

    @ViewBuilder
    private func shelf(_ tab: RRTab) -> some View {
        if store.tabs.count > 1 {
            Text(tab.depth).kjSmall(faint: true).accessibilityIdentifier("rrDepth")
        }
        ForEach(tab.rows) { row in
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(title: row.name, count: row.titles.count, route: .readingShelf(tab: tab.id, row: row.id))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(row.titles) { ReadingCard(title: $0, width: coverWidth) }
                    }
                }
                .scrollClipDisabled()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rr-row-\(row.id)")
        }
    }

    private var coverWidth: CGFloat { sizeClass == .regular ? 150 : 124 }
}

/// A title on a shelf, as Apple Books sets a book: the cover at its own shape, then the name and a
/// faint line, and what the page server said about access.
struct ReadingCard: View {
    let title: RRTitle
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.reading
        NavigationLink(value: RoomRoute.readingTitle(title.slug)) {
            VStack(alignment: .leading, spacing: 8) {
                RRCover(state: store.card(for: title)).frame(width: width, height: width * 1.38)
                ReadingCardText(title: title, access: store.access(for: title))
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { store.want(title) }
        .accessibilityIdentifier("rr-title-\(title.slug)")
    }
}

/// Where reading stopped on this device, as Apple Books' Continue: the issue's own cover, the page,
/// and how far into the issue that is. Nothing shows until something has been read here.
struct ContinueShelf: View {
    /// True on Home, which is not on the room's stack: a card then opens the room at the title.
    var fromHome = false
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var places: [(Resume, RRTitle, RRIssue)] {
        model.library.resume.filter { $0.kind == .reading }.compactMap { place in
            guard let title = model.reading.titles.first(where: { $0.slug == place.ref }),
                  !model.reading.isRights(title),
                  let issue = title.issues.first(where: { $0.key == place.part }) else { return nil }
            return (place, title, issue)
        }
    }

    var body: some View {
        let found = places
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(title: "Continue")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(found, id: \.0.id) { place, title, issue in card(place, title, issue) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var width: CGFloat { sizeClass == .regular ? 190 : 164 }

    private func card(_ place: Resume, _ title: RRTitle, _ issue: RRIssue) -> some View {
        let page = Int(place.position)
        let route = RoomRoute.readingTitle(title.slug, resume: true)
        return RoomLink(route: route, in: fromHome ? .reading : nil) {
            VStack(alignment: .leading, spacing: 8) {
                RRCover(state: model.reading.issueCard(title, issue)).frame(width: width, height: width * 1.38)
                ProgressLine(value: Double(page) / Double(max(issue.pages, 1))).frame(width: width)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.name).kjName().lineLimit(2).multilineTextAlignment(.leading)
                    Text([issue.label, "p. \(page) of \(issue.pages)"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                        .kjSmall(faint: true).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { model.reading.want(title, issue: issue) }
        .accessibilityIdentifier("rr-continue-\(title.slug)")
    }
}

/// One shelf whole, as Apple Books opens a collection: its covers in a grid.
struct ReadingRowScreen: View {
    let tabID: String
    let rowID: String
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let row = model.reading.tabs.first { $0.id == tabID }?.rows.first { $0.id == rowID }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LargeTitle(title: row?.name ?? RRWords.heading,
                           line: row.map { "\($0.titles.count.formatted()) title\($0.titles.count == 1 ? "" : "s")" })
                if let row {
                    let width: CGFloat = sizeClass == .regular ? 150 : 104
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
                        ForEach(row.titles) { ReadingCard(title: $0, width: width) }
                    }
                } else {
                    Text("This shelf is not in the Reading Room now.").kjBody()
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await model.reading.start() }
    }
}

/// A title's name, its run and what the page server said about access.
private struct ReadingCardText: View {
    let title: RRTitle
    let access: RRAccess?

    var body: some View {
        let meta = [title.byline, "\(title.issues.count) issue\(title.issues.count == 1 ? "" : "s")"]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: 2) {
            Text(title.name).font(.system(.subheadline, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !title.native.isEmpty { Text(title.native).kjSmall().lineLimit(1) }
            Text(meta).kjSmall(faint: true).lineLimit(1)
            if let tag = access?.tag { Text(tag).font(.system(.caption, weight: .semibold)).lineLimit(2) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A cover at its own shape, never cropped, standing on the shelf's line as a book does. A plate
/// on the lift colour holds the space until the page arrives; a cover that cannot be had leaves it.
struct RRCover: View {
    let state: RRCardState
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let image = state.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(palette.lift)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityHidden(true)
        // The store keeps the pictures of covers on screen and lets go of the rest past its budget.
        .onAppear { state.shown(true) }
        .onDisappear { state.shown(false) }
    }
}

struct ReadingProblem: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message).kjBody()
            Button(kicker: "Try again", action: retry).accessibilityIdentifier("rrRetry")
        }
    }
}

// MARK: - One title

/// One title: its issues as covers, each the real first page, with the run's figures. A
/// rights-held title shows its covers, opens nothing, and says why. `resume` opens the reader
/// where this device last stopped in this title.
struct ReadingTitleScreen: View {
    let slug: String
    var resume = false
    /// An issue to open at once, by the id the website's `issue=` names, and its page.
    var openIssue: String?
    var openPage = 1

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var reading: ReaderTarget?
    @State private var showProvenance = false
    @State private var saveNote: String?
    @State private var showSignIn = false
    @State private var resumed = false

    private var store: ReadingStore { model.reading }
    private var title: RRTitle? { store.titles.first { $0.slug == slug } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the Reading Room\u{2026}").frame(maxWidth: .infinity).padding(.top, 40)
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await store.retry() } }
                case .ready:
                    if let title { content(title) } else {
                        Text("This title is not on the shelf now.").kjBody().accessibilityIdentifier("rrTitleMissing")
                    }
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await store.start() }
        .task(id: store.phase == .ready) { openResumeIfAsked() }
        .fullScreenCover(item: $reading) { target in
            ReadingReaderScreen(title: target.title, issue: target.issue, startPage: target.page)
                .environment(model)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showSignIn) { SignInView(onSignedIn: {}) }
    }

    private var held: Bool { title.map(store.isRights) ?? false }

    @ViewBuilder
    private func content(_ title: RRTitle) -> some View {
        header(title)
        if held { rightsBanner(title) }
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: "Issues", count: title.issues.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
                ForEach(title.issues) { issueCard(title, $0) }
            }
        }
    }

    /// Where this device stopped in the title, when that issue is still on it.
    private func place(_ title: RRTitle) -> (Resume, RRIssue)? {
        guard !held, let place = model.library.place(.reading, title.slug),
              let issue = title.issues.first(where: { $0.key == place.part }) else { return nil }
        return (place, issue)
    }

    /// Apple Books' book page: the cover, the name, one action, and the smaller ones under it.
    private func header(_ title: RRTitle) -> some View {
        let stopped = place(title)
        let lead = stopped?.1 ?? title.issues.first
        return VStack(spacing: 14) {
            if let lead {
                RRCover(state: store.issueCard(title, lead))
                    .frame(width: 190, height: 262)
                    .onAppear { store.want(title, issue: lead) }
            }
            VStack(spacing: 4) {
                Text(title.name).font(.system(.title2, weight: .bold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if !title.native.isEmpty { Text(title.native).kjName(KJType.title).multilineTextAlignment(.center) }
                Text(summary(title)).kjSmall(faint: true).multilineTextAlignment(.center).accessibilityIdentifier("rrTitleSummary")
            }
            if !held {
                if let stopped {
                    Button {
                        reading = ReaderTarget(title: title, issue: stopped.1, page: Int(stopped.0.position))
                    } label: {
                        Label("Continue \u{00B7} \(stopped.1.label), p. \(Int(stopped.0.position))", systemImage: "book.fill")
                    }
                    .buttonStyle(SolidActionStyle())
                    .accessibilityIdentifier("rrContinue")
                } else if let first = title.issues.first {
                    Button {
                        reading = ReaderTarget(title: title, issue: first, page: 1)
                    } label: { Label("Read", systemImage: "book.fill") }
                    .buttonStyle(SolidActionStyle())
                    .accessibilityIdentifier("rrRead")
                }
            }
            HStack(spacing: 8) {
                saveButton(title)
                if !store.provenanceLines(for: title).isEmpty {
                    IconAction(title: "Provenance", symbol: showProvenance ? "info.circle.fill" : "info.circle") { showProvenance.toggle() }
                        .accessibilityIdentifier("rrProvenance")
                }
                IconAction(title: "Website", symbol: "safari") { model.openWebsite(ReadingLinks.title(title)) }
                    .accessibilityIdentifier("rrOnWebsite")
            }
            if let saveNote { Text(saveNote).kjSmall(faint: true).accessibilityIdentifier("rrSaveNote") }
            if showProvenance {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.provenanceLines(for: title), id: \.self) { Text($0).kjSmall(faint: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    /// Save, as the website's Save control: on the account, so the title is on the dashboard and
    /// on every device signed in to it.
    private func saveButton(_ title: RRTitle) -> some View {
        let saved = model.saves.isSaved(title)
        return IconAction(title: saved ? "Saved" : "Save", symbol: saved ? "bookmark.fill" : "bookmark") {
            guard model.saves.canSave else {
                saveNote = "Sign in to save titles to your account."
                showSignIn = true
                return
            }
            Task {
                await model.saves.load()
                saveNote = await model.saves.toggle(title) ? nil : "That did not save. Try again."
            }
        }
        .accessibilityIdentifier("rrSave")
        .accessibilityValue(saved ? "On" : "Off")
        .task { await model.saves.load() }
    }

    private func summary(_ title: RRTitle) -> String {
        let depth = RRWords.depth(issues: title.issues.count, pages: title.pageTotal, held: held)
        return title.byline.isEmpty ? depth : title.byline + " \u{00B7} " + depth
    }

    private func rightsBanner(_ title: RRTitle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(RRWords.rightsHeading)
            Text(RRWords.rightsBody(issueCount: title.issues.count, khajistanScanned: store.isKhajistanScanned(title)))
                .kjBody()
                .accessibilityIdentifier("rrRightsNote")
            Text(RRWords.researchersAsk).kjSmall(faint: true)
        }
    }

    private func issueCard(_ title: RRTitle, _ issue: RRIssue) -> some View {
        let spot = place(title).flatMap { $0.1.key == issue.key ? $0.0 : nil }
        return Button {
            // A rights-held issue is not opened: the website's card is inert, and the page server answers 451.
            if !held { reading = ReaderTarget(title: title, issue: issue, page: 1) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RRCover(state: store.issueCard(title, issue)).aspectRatio(0.74, contentMode: .fit)
                if let spot { ProgressLine(value: spot.position / Double(max(issue.pages, 1))) }
                Text(issue.label).font(.system(.subheadline, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(issue.pages) pages").kjSmall(faint: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { store.want(title, issue: issue) }
        .accessibilityIdentifier("rr-issue-\(issue.index)")
        .accessibilityLabel(held ? "\(issue.label), cover only, pages held pending rights clearance" : "Open \(issue.label), \(issue.pages) pages")
    }

    private func openResumeIfAsked() {
        if let openIssue, !resumed, store.phase == .ready, let title, !held,
           let issue = title.issues.first(where: { $0.id == openIssue }) {
            resumed = true
            reading = ReaderTarget(title: title, issue: issue, page: max(openPage, 1))
            return
        }
        guard resume, !resumed, store.phase == .ready, let title, !held,
              let place = model.library.place(.reading, title.slug),
              let issue = title.issues.first(where: { $0.key == place.part }) else { return }
        resumed = true
        reading = ReaderTarget(title: title, issue: issue, page: Int(place.position))
    }
}

struct ReaderTarget: Identifiable {
    let title: RRTitle
    let issue: RRIssue
    let page: Int
    var id: String { issue.key }
}

/// The website's own addresses for a title and a page (reading-room-app.js reads `m`, `issue`, `p`).
enum ReadingLinks {
    static func title(_ title: RRTitle) -> URL { url(["m": title.slug]) }

    static func page(_ title: RRTitle, _ issue: RRIssue, page: Int) -> URL {
        url(["m": title.slug, "issue": issue.id, "p": String(page)])
    }

    /// The room route for a website Reading Room address, nil for any other page.
    static func route(_ url: URL) -> RoomRoute? {
        let path = url.path.lowercased()
        guard path == "/reading-room" || path == "/reading-room.html",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let slug = items.first(where: { $0.name == "m" })?.value, !slug.isEmpty else { return nil }
        if let issue = items.first(where: { $0.name == "issue" })?.value, !issue.isEmpty {
            let page = items.first(where: { $0.name == "p" })?.value.flatMap(Int.init) ?? 1
            return .readingPage(slug, issue: issue, page: page)
        }
        return .readingTitle(slug)
    }

    private static func url(_ items: [String: String]) -> URL {
        var parts = URLComponents(url: ArchiveURL.base.appendingPathComponent("reading-room.html"), resolvingAgainstBaseURL: false)!
        parts.queryItems = items.keys.sorted().map { URLQueryItem(name: $0, value: items[$0]) }
        return parts.url!
    }
}
