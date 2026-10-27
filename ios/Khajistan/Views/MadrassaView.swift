import SwiftUI

/// The Madrassa, the reference wing (madrassa.html): its reference entries, its writings and
/// forensics read whole, the Street Dictionary, and the research databases. Each section reads the
/// page's own source (Core/Madrassa.swift, Core/Databases.swift).
struct MadrassaView: View {
    enum Section: String, CaseIterable, Identifiable {
        case reference, writings, forensics, dictionary, databases
        var id: String { rawValue }
        var title: String {
            switch self {
            case .reference: return "Reference"
            case .writings: return "Writings"
            case .forensics: return "Forensics"
            case .dictionary: return "Street Dictionary"
            case .databases: return "Databases"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var section: Section = .reference

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHead("Madrassa", line: "The reference wing \u{2014} street dictionary, indices and writings")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Section.allCases) { item in
                            Button { section = item } label: { Text(item.title).kjKicker() }
                                .buttonStyle(HouseTabStyle(isCurrent: section == item))
                                .accessibilityIdentifier("madrassa-\(item.rawValue)")
                        }
                    }
                }
                .padding(.horizontal, -12)
                switch section {
                case .reference: ReferenceList()
                case .writings: WritingsList(forensics: false)
                case .forensics: WritingsList(forensics: true)
                case .dictionary: DictionaryList()
                case .databases: DatabaseShelves()
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// The state of a feed that is not ready, in one place: loading, behind the password, failed.
struct FeedState<Value: Sendable>: View {
    let feed: SiteFeed<Value>
    let subject: String

    var body: some View {
        switch feed.state {
        case .idle, .loading:
            TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity).padding(.top, 30)
        case .locked:
            LockedNote(subject: subject)
        case .failed(let message):
            ReadingProblem(message: message) { Task { await feed.load(force: true) } }
        case .ready:
            EmptyView()
        }
    }
}

// MARK: - Reference

private struct ReferenceList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.madrassaEntries
        Group {
            if let entries = feed.value {
                ForEach(entries) { entry in
                    NavigationLink(value: RoomRoute.madrassaEntry(entry.id)) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Kicker(entry.cat)
                                Text(entry.title).kjName(KJType.title)
                                if let sub = entry.sub { Text(sub).kjSmall(faint: true) }
                            }
                            Spacer(minLength: 0)
                            Text("\u{2192}").kjName().accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("entry-\(entry.id)")
                }
            } else {
                FeedState(feed: feed, subject: "The Madrassa")
            }
        }
        .task(id: model.auth.previewPassword) { await feed.load() }
    }
}

struct MadrassaEntryScreen: View {
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entry = model.madrassaEntries.value?.first(where: { $0.id == id }) {
                    Kicker(entry.cat)
                    Text(entry.title).kjDisplay(KJType.headline, tracking: -0.05).accessibilityAddTraits(.isHeader)
                    if let sub = entry.sub { Text(sub).kjName() }
                    // A site path ("assets/…") is the archive's own picture, as the page resolves it.
                    if let img = entry.img, let url = siteURL(img), url.scheme == "https" {
                        ArticleImage(url: url, alt: entry.alt)
                    }
                    if let desc = entry.desc { Text(desc).kjBody().fixedSize(horizontal: false, vertical: true) }
                    if let href = entry.href {
                        Button(kicker: "The full entry \u{2197}") { if let url = siteURL(href) { model.open(url) } }
                            .accessibilityIdentifier("entryFull")
                    }
                    if let press = entry.press, !press.isEmpty {
                        HouseRule()
                        Kicker("Press")
                        ForEach(press, id: \.u) { item in
                            if let url = URL(string: item.u), url.scheme == "https" {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.h).kjName().multilineTextAlignment(.leading)
                                        if let s = item.s { Text(s).kjSmall(faint: true) }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    FeedState(feed: model.madrassaEntries, subject: "The Madrassa")
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .kjColumn()
        }
        .task { await model.madrassaEntries.load() }
    }

    /// An entry's own page: a site path opens in the house browser, an outside address in Safari.
    private func siteURL(_ href: String) -> URL? {
        if let url = URL(string: href), url.scheme == "https" { return url }
        return URL(string: href, relativeTo: ArchiveURL.base)?.absoluteURL
    }
}

// MARK: - Writings and forensics

private struct WritingsList: View {
    let forensics: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.madrassaPosts
        Group {
            if let posts = feed.value?.filter({ MadrassaWritings.isForensics($0) == forensics }) {
                if posts.isEmpty { Text("Nothing here yet.").kjBody() }
                ForEach(posts) { post in
                    NavigationLink(value: RoomRoute.post(post.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Kicker([MadrassaWritings.label(post), post.publishedAt].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            Text(MadrassaWritings.listTitle(post)).kjName(KJType.title).multilineTextAlignment(.leading)
                            if let summary = post.summary.map(ArticleHTML.text), !summary.isEmpty {
                                Text(summary).kjSmall(faint: true).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("post-\(post.handle)")
                }
            } else {
                FeedState(feed: feed, subject: "The Madrassa's writings")
            }
        }
        .task(id: model.auth.previewPassword) { await feed.load() }
    }
}

/// An essay, whole, from the body the feed carries: headings, paragraphs with their links,
/// quotations, a transcript's rows, pictures, and a note where the source embeds a player.
struct PostScreen: View {
    let id: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var saveNote: String?
    @State private var showSignIn = false

    private var post: MadrassaPost? { model.madrassaPosts.value?.first { $0.id == id } }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let post {
                    let blocks = ArticleHTML.blocks(post.body ?? "")
                    Kicker([MadrassaWritings.label(post), post.publishedAt].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    Text(post.title).kjDisplay(KJType.headline, tracking: -0.05).accessibilityAddTraits(.isHeader)
                    saveRow(post)
                    contents(blocks, reader: reader)
                    if let image = post.image, let url = URL(string: image), url.scheme == "https" {
                        ArticleImage(url: url, alt: post.imageAlt)
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        blockView(block, post: post).id(index)
                    }
                    HouseRule()
                    Button(kicker: "This piece on the website \u{2197}") {
                        model.open(URL(string: MadrassaWritings.pagePath(post), relativeTo: ArchiveURL.base)!.absoluteURL)
                    }
                    .accessibilityIdentifier("postOnWebsite")
                } else {
                    FeedState(feed: model.madrassaPosts, subject: "The Madrassa's writings")
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .kjColumn()
            .textSelection(.enabled)
        }
        }
        .sheet(isPresented: $showSignIn) { SignInView(onSignedIn: {}) }
        // A link in the text to an archive page opens in the app; any other in Safari.
        .environment(\.openURL, OpenURLAction { url in
            guard ArchiveURL.isArchive(url) else { return .systemAction }
            model.open(url)
            return .handled
        })
        .task { await model.madrassaPosts.load() }
    }

    /// The piece's own headings, each a jump to its place. Only where there are three or more.
    @ViewBuilder
    private func contents(_ blocks: [ArticleBlock], reader: ScrollViewProxy) -> some View {
        let headings = blocks.enumerated().compactMap { index, block -> (Int, String)? in
            if case .heading(let text) = block { return (index, text) } else { return nil }
        }
        if headings.count >= 3 {
            VStack(alignment: .leading, spacing: 2) {
                Kicker("Contents").accessibilityAddTraits(.isHeader)
                ForEach(headings, id: \.0) { index, text in
                    Button { withAnimation(.kjPush) { reader.scrollTo(index, anchor: .top) } } label: {
                        Text(text).kjSmall().multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)))
                }
            }
            .accessibilityIdentifier("postContents")
            HouseRule()
        }
    }

    /// Save, on the account with the other saves the website's dashboard lists.
    private func saveRow(_ post: MadrassaPost) -> some View {
        let pageID = (post.blog ?? "announcements") + "/" + post.handle
        let saved = model.saves.isSaved(page: pageID)
        return VStack(alignment: .leading, spacing: 4) {
            Button(kicker: saved ? "Saved" : "Save") {
                guard model.saves.canSave else { showSignIn = true; return }
                Task {
                    await model.saves.load()
                    saveNote = await model.saves.toggle(page: pageID, title: post.title, href: "/" + MadrassaWritings.pagePath(post))
                        ? nil : "That did not save. Try again."
                }
            }
            .disabled(PassportSaves.pageRef(pageID) == nil)
            .accessibilityIdentifier("postSave")
            .accessibilityValue(saved ? "On" : "Off")
            if let saveNote { Text(saveNote).kjSmall(faint: true) }
        }
        .task { await model.saves.load() }
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock, post: MadrassaPost) -> some View {
        switch block {
        case .heading(let text):
            Text(text).kjName(KJType.title).padding(.top, 8).accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(text).kjBody().fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            Text(text).kjBody().italic().padding(.leading, 16).fixedSize(horizontal: false, vertical: true)
        case .item(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\u{2022}").kjBody(); Text(text).kjBody() }
        case .row(let cells):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    // A cell in Arabic script reads from the right, as the page sets it.
                    Text(cell).kjBody()
                        .frame(maxWidth: .infinity, alignment: Self.isRightToLeft(cell) ? .trailing : .leading)
                        .multilineTextAlignment(Self.isRightToLeft(cell) ? .trailing : .leading)
                }
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.ink.opacity(0.2)).frame(height: 1) }
        case .image(let url, let alt):
            ArticleImage(url: url, alt: alt)
        case .embed:
            Button(kicker: "A player is embedded here \u{2014} open the piece on the website \u{2197}") {
                model.open(URL(string: MadrassaWritings.pagePath(post), relativeTo: ArchiveURL.base)!.absoluteURL)
            }
        case .rule:
            HouseRule()
        }
    }

    static func isRightToLeft(_ text: String) -> Bool {
        text.unicodeScalars.first { CharacterSet.letters.contains($0) }.map { (0x0590...0x08FF).contains($0.value) } ?? false
    }
}

/// A picture from the source at its own shape, with its own description for VoiceOver.
struct ArticleImage: View {
    let url: URL
    let alt: String?
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.clear.frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(alt ?? "")
        .accessibilityHidden(alt == nil)
        .task(id: url) { image = await PnvImages.shared.image([url], maxPixel: 1400, authorization: model.siteAuthorization(for: url)) }
    }
}

// MARK: - Street Dictionary

private struct DictionaryList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var language: String?
    @State private var query = ""
    @State private var open: String?

    var body: some View {
        let feed = model.lughat
        Group {
            if let entries = feed.value {
                let shown = entries.filter { (language == nil || $0.lang == language) && Lughat.matches($0, query) }
                HouseInputField("Find a word") {
                    TextField("", text: $query, prompt: Text("Word, meaning, region").foregroundStyle(palette.faint))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("lughatSearch")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        chip("All", nil)
                        ForEach(Lughat.languages(entries), id: \.self) { chip($0, $0) }
                    }
                }
                .padding(.horizontal, -12)
                Text("\(shown.count.formatted()) of \(entries.count.formatted()) entries").kjSmall(faint: true)
                    .accessibilityIdentifier("lughatCount")
                ForEach(shown.filter { !Lughat.isSetApart($0) }) { row($0) }
                let apart = shown.filter(Lughat.isSetApart)
                if !apart.isEmpty {
                    HouseRule()
                    Text(Lughat.setApartHeading).kjKicker().accessibilityAddTraits(.isHeader)
                    Text(Lughat.setApartNote).kjSmall()
                    ForEach(apart) { row($0) }
                }
            } else {
                FeedState(feed: feed, subject: "The Street Dictionary")
            }
        }
        .task(id: model.auth.previewPassword) { await feed.load() }
    }

    private func chip(_ title: String, _ value: String?) -> some View {
        Button { language = value } label: { Text(title).kjKicker() }
            .buttonStyle(HouseTabStyle(isCurrent: language == value))
    }

    /// A word, opened in place: every field its record gives, its review state named.
    private func row(_ entry: LughatEntry) -> some View {
        let isOpen = open == entry.id
        return Button { open = isOpen ? nil : entry.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.word ?? entry.id).kjName(KJType.title)
                    if let translit = entry.translit, translit != entry.word { Text(translit).kjSmall(faint: true) }
                }
                if let meaning = entry.meaning ?? entry.gloss { Text(meaning).kjBody().multilineTextAlignment(.leading) }
                let marks = [entry.lang, entry.sensitivity.map { "Sensitivity: \($0)" }, entry.needsVerifying ? "To be verified" : nil].compactMap { $0 }
                Text(marks.joined(separator: " \u{00B7} ")).kjSmall(faint: true)
                if isOpen {
                    ForEach(Self.fields(entry), id: \.0) { label, value in
                        (Text("\(label): ").bold() + Text(value)).kjSmall()
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Closes the entry" : "Opens the entry")
        .accessibilityIdentifier("lughat-\(entry.id)")
    }

    static func fields(_ entry: LughatEntry) -> [(String, String)] {
        [("Example", entry.example), ("Region", entry.region), ("Register", entry.register?.joined(separator: ", ")),
         ("Part of speech", entry.pos), ("Domain", entry.domain), ("Concept", entry.concept), ("Source", entry.by ?? entry.source),
         ("Access", entry.access), ("Review", entry.verify?.note.flatMap { $0.isEmpty ? nil : $0 })]
            .compactMap { label, value in value.map { (label, $0) } }
    }
}
