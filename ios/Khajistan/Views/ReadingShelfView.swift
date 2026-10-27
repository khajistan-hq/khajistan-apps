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
            LazyVStack(alignment: .leading, spacing: 24) {
                PageHead(RRWords.heading, line: RRWords.lede)
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the Reading Room\u{2026}")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await store.retry() } }
                case .ready:
                    if store.tabs.count > 1 {
                        Text(RRShelves.depthLine(store.titles, rights: store.rights))
                            .kjSmall(faint: true)
                            .accessibilityIdentifier("rrTotal")
                    }
                    search
                    if !trimmed.isEmpty {
                        results
                    } else {
                        if store.tabs.count > 1 { tabRow }
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

    private var search: some View {
        HouseInputField("Find a title") {
            TextField("", text: $query, prompt: Text("Name, in any script").foregroundStyle(palette.faint))
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("rrSearch")
        }
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
                    HStack(alignment: .top, spacing: 14) {
                        RRCover(state: store.card(for: title))
                            .frame(width: 64, height: 88)
                        ReadingCardText(title: title, access: store.access(for: title))
                        Spacer(minLength: 0)
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

    // MARK: - Tabs and shelves

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.tabs) { item in
                    Button { tabID = item.id } label: { Text(item.name).kjKicker() }
                        .buttonStyle(HouseTabStyle(isCurrent: item.id == tab?.id))
                        .accessibilityIdentifier("rr-tab-\(item.id)")
                }
            }
        }
        .padding(.horizontal, -12)
    }

    @ViewBuilder
    private func shelf(_ tab: RRTab) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(tab.name).kjName(KJType.title)
                if let native = tab.native, !native.isEmpty {
                    Text(native).kjName(KJType.title).foregroundStyle(palette.faint)
                }
            }
            Text(tab.depth).kjSmall(faint: true).accessibilityIdentifier("rrDepth")
        }
        ForEach(tab.rows) { row in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Kicker(row.name).accessibilityAddTraits(.isHeader)
                    Text(row.titles.count.formatted()).kjSmall(faint: true)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(row.titles) { card($0) }
                    }
                }
                .scrollClipDisabled()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rr-row-\(row.id)")
        }
    }

    private var coverWidth: CGFloat { sizeClass == .regular ? 150 : 116 }

    private func card(_ title: RRTitle) -> some View {
        NavigationLink(value: RoomRoute.readingTitle(title.slug)) {
            VStack(alignment: .leading, spacing: 6) {
                RRCover(state: store.card(for: title))
                    .frame(width: coverWidth, height: coverWidth * 1.36)
                ReadingCardText(title: title, access: store.access(for: title))
            }
            .frame(width: coverWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { store.want(title) }
        .accessibilityIdentifier("rr-title-\(title.slug)")
    }
}

/// A title's name, its run and what the page server said about access.
private struct ReadingCardText: View {
    let title: RRTitle
    let access: RRAccess?

    var body: some View {
        let meta = [title.byline, "\(title.issues.count) issue\(title.issues.count == 1 ? "" : "s")"]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: 3) {
            Text(title.name).kjName().lineLimit(3).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !title.native.isEmpty { Text(title.native).kjSmall().lineLimit(1) }
            Text(meta).kjSmall(faint: true).lineLimit(1)
            if let tag = access?.tag { Text(tag).kjKicker().lineLimit(2) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A cover at its own shape on the lift colour, fitted whole and never cropped. The plate holds
/// the space until the page arrives; a cover that cannot be had leaves the plate.
struct RRCover: View {
    let state: RRCardState
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.lift)
            .overlay {
                if let image = state.image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
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
        if let place = model.library.place(.reading, title.slug), !held,
           let issue = title.issues.first(where: { $0.key == place.part }) {
            Button {
                reading = ReaderTarget(title: title, issue: issue, page: Int(place.position))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue \u{2192}").kjKicker()
                    Text([issue.label, "p. \(Int(place.position))"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")).kjName()
                }
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)))
            .accessibilityIdentifier("rrContinue")
        }
        if held { rightsBanner(title) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
            ForEach(title.issues) { issueCard(title, $0) }
        }
    }

    private func header(_ title: RRTitle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(RRWords.heading)
            Text(title.name).kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
            if !title.native.isEmpty { Text(title.native).kjName(KJType.title) }
            Text(summary(title)).kjBody().accessibilityIdentifier("rrTitleSummary")
            HStack(spacing: 18) {
                saveButton(title)
                if !store.provenanceLines(for: title).isEmpty {
                    Button(kicker: showProvenance ? "Hide provenance" : "Provenance") { showProvenance.toggle() }
                        .accessibilityIdentifier("rrProvenance")
                }
                Button(kicker: "On the website \u{2197}") { model.openWebsite(ReadingLinks.title(title)) }
                    .accessibilityIdentifier("rrOnWebsite")
            }
            if let saveNote { Text(saveNote).kjSmall(faint: true).accessibilityIdentifier("rrSaveNote") }
            if showProvenance {
                ForEach(store.provenanceLines(for: title), id: \.self) { Text($0).kjSmall(faint: true) }
            }
        }
    }

    /// Save, as the website's Save control: on the account, so the title is on the dashboard and
    /// on every device signed in to it.
    private func saveButton(_ title: RRTitle) -> some View {
        let saved = model.saves.isSaved(title)
        return Button(kicker: saved ? "Saved" : "Save") {
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
        Button {
            // A rights-held issue is not opened: the website's card is inert, and the page server answers 451.
            if !held { reading = ReaderTarget(title: title, issue: issue, page: 1) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RRCover(state: store.issueCard(title, issue)).aspectRatio(0.74, contentMode: .fit)
                Text(issue.label).kjName().lineLimit(2).multilineTextAlignment(.leading)
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
