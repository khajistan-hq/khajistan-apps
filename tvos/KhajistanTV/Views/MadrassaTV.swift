import SwiftUI

/// The Madrassa on the TV, as Wikipedia lists entries and The Atlantic sets an essay: serif titles,
/// a short description on each card, a picture where the piece has one. A piece reads whole here,
/// one block at a time; the long reading is meant for the phone, and the end of each says so.
struct TVMadrassa: View {
    @Environment(AppModel.self) private var model
    @State private var entry: MadrassaEntry?
    @State private var post: MadrassaPost?
    @State private var dictionary = false

    var body: some View {
        TVPage("Madrassa", line: "The reference wing \u{2014} street dictionary, indices and writings") {
            if let entries = model.madrassaEntries.value {
                Shelf("Reference", count: entries.count.formatted()) {
                    ForEach(entries) { item in
                        Button { entry = item } label: { EntryCard(entry: item, picture: picture(item.img)) }
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
                    if !row.isEmpty {
                        Shelf(forensics ? "Forensics" : "Writings", count: row.count.formatted()) {
                            ForEach(row) { item in
                                Button { post = item } label: { PostCard(post: item, picture: picture(item.image)) }
                                    .buttonStyle(HouseCardStyle())
                                    .accessibilityIdentifier("tvpost-\(item.handle)")
                            }
                        }
                    }
                }
            }
            Shelf("Street Dictionary") {
                Button { dictionary = true } label: {
                    CardPlate(width: 520, height: 200) {
                        VStack(alignment: .leading, spacing: 10) {
                            Kicker("Lughat").lineLimit(1)
                            Text("The Street Dictionary").font(MadrassaType.title(34))
                            if let count = model.lughat.value?.count { Text("\(count.formatted()) entries").kjSmall(faint: true) }
                        }
                    }
                }
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
            TVReading(kicker: item.cat, title: item.title, picture: picture(item.img),
                      blocks: [item.sub, item.desc].compactMap { $0 }.map { .paragraph(AttributedString($0)) },
                      website: item.href.map { "khajistan-archive.pages.dev/\($0)" })
        }
        .fullScreenCover(item: $post) { item in Self.reading(item, model: model) }
        .fullScreenCover(isPresented: $dictionary) { TVDictionary() }
    }

    private func picture(_ raw: String?) -> URL? { Self.picture(raw, model: model) }

    /// A picture named by the page or the feed: an https address as it is, a site path on the
    /// site's own origin.
    static func picture(_ raw: String?, model: AppModel) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw, relativeTo: model.madrassaEntries.origin)?.absoluteURL,
              url.scheme == "https" || url.host == model.madrassaEntries.origin.host else { return nil }
        return url
    }

    /// A writing read whole, with its date and Save beside it, as The Atlantic heads an essay.
    static func reading(_ post: MadrassaPost, model: AppModel) -> TVReading {
        TVReading(kicker: MadrassaWritings.label(post), title: post.title, picture: picture(post.image, model: model),
                  blocks: ArticleHTML.blocks(post.body ?? ""),
                  website: "khajistan-archive.pages.dev/\(MadrassaWritings.pagePath(post))",
                  date: post.publishedAt.map { String($0.prefix(10)) },
                  saving: TVReading.Saving(pageID: (post.blog ?? "announcements") + "/" + post.handle,
                                           href: "/" + MadrassaWritings.pagePath(post)),
                  opened: post.handle)
    }
}

/// The serif the phone's Madrassa sets its titles and text in.
enum MadrassaType {
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func body(_ size: CGFloat = KJType.body) -> Font { .system(size: size, design: .serif) }
}

/// A reference entry: its category, the title in a serif, its short description, and its picture
/// beside them where it has one, as Wikipedia lists a result.
private struct EntryCard: View {
    let entry: MadrassaEntry
    let picture: URL?

    var body: some View {
        CardPlate(width: 560, height: 280) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(entry.cat).lineLimit(1)
                    Text(entry.title).font(MadrassaType.title(32)).lineLimit(2)
                    if let line = entry.sub ?? entry.desc {
                        Text(line).font(MadrassaType.body(24)).lineLimit(3).opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                if let picture { TVPicture(url: picture, maxPixel: 240).frame(width: 110, height: 110) }
            }
        }
    }
}

/// A writing: its picture fitted on the soft plate, the date, the title in a serif and its summary.
struct PostCard: View {
    static let width: CGFloat = 520

    let post: MadrassaPost
    let picture: URL?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                palette.lift
                if let picture { TVPicture(url: picture, maxPixel: 800) }
            }
            .frame(width: Self.width, height: 290)
            .kjCardArt()
            VStack(alignment: .leading, spacing: 6) {
                if let date = post.publishedAt?.prefix(10) { Text(String(date)).kjSmall(faint: true) }
                Text(MadrassaWritings.listTitle(post)).font(MadrassaType.title(30)).lineLimit(2)
                if let summary = post.summary.map(ArticleHTML.text), !summary.isEmpty {
                    Text(summary).font(MadrassaType.body(24)).foregroundStyle(palette.faint).lineLimit(2)
                }
            }
            .frame(width: Self.width, height: 170, alignment: .topLeading)
        }
    }
}

/// A piece read whole on the TV, set as The Atlantic sets an essay: the section, the headline in a
/// serif, the date with Save beside it, the contents where the piece has three headings or more,
/// the lead picture, then the text. Each block is a focus stop, so the remote moves down the text
/// a block at a time and the screen follows; a line of the contents jumps to its heading. It ends
/// by sending the reader to the phone.
struct TVReading: View {
    /// Where a writing is kept on the account, with the other saves the website's profile lists.
    struct Saving {
        let pageID: String
        let href: String
    }

    let kicker: String
    let title: String
    var picture: URL? = nil
    let blocks: [ArticleBlock]
    let website: String?
    var date: String? = nil
    var saving: Saving? = nil
    /// The writing's handle, for Opened lately on the Rooms door.
    var opened: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var saveNote: String?
    @State private var showSignIn = false
    /// The block the remote is on; a line of the contents moves it to its heading, and the
    /// screen follows focus there.
    @FocusState private var focusedBlock: Int?

    private var headings: [(index: Int, text: String)] {
        blocks.enumerated().compactMap { index, block in
            if case .heading(let text) = block { return (index, text) } else { return nil }
        }
    }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Kicker(kicker)
                    Text(title).font(MadrassaType.title(60)).frame(maxWidth: 1400, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    if date != nil || saving != nil {
                        HStack(alignment: .center, spacing: 32) {
                            if let date { Text(date).kjSmall(faint: true) }
                            if let saving { saveButton(saving) }
                            if let saveNote { Text(saveNote).kjSmall(faint: true) }
                        }
                        .focusSection()
                    }
                    if headings.count >= 3 { contents(reader) }
                    if let picture { TVPicture(url: picture, maxPixel: 1600).frame(maxWidth: 1300, minHeight: 560, maxHeight: 560) }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        Button { } label: { blockView(block).frame(maxWidth: 1300, alignment: .leading) }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                            .focused($focusedBlock, equals: index)
                            .id(index)
                    }
                    if let website {
                        Text("Continue on your phone, or on the website: \(website)").kjSmall(faint: true).padding(.top, 12)
                    }
                }
                .padding(KJLayout.inset)
            }
            }
        }
        .foregroundStyle(palette.ink)
        .onAppear { if let opened { OpenedLately.record(.writing, ref: opened, title: title) } }
        .task { if saving != nil { await model.saves.load() } }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: {}).environment(\.palette, palette)
        }
    }

    /// The piece's own headings, each a jump to its place, as Wikipedia's contents box.
    private func contents(_ reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker("Contents")
            ForEach(headings, id: \.index) { heading in
                Button { jump(to: heading.index, reader) } label: {
                    Text(heading.text).font(MadrassaType.body(28)).lineLimit(1).frame(maxWidth: 1100, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)))
                .accessibilityIdentifier("tvcontents-\(heading.index)")
            }
        }
        .padding(.vertical, 8)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tvpostContents")
    }

    /// The heading is built first (the text is a lazy stack), then the remote is put on it, and
    /// the screen follows focus there.
    private func jump(to index: Int, _ reader: ScrollViewProxy) {
        reader.scrollTo(index, anchor: .top)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            focusedBlock = index
        }
    }

    private func saveButton(_ saving: Saving) -> some View {
        let saved = model.saves.isSaved(page: saving.pageID)
        return Button {
            guard model.saves.canSave else { showSignIn = true; return }
            Task {
                await model.saves.load()
                saveNote = await model.saves.toggle(page: saving.pageID, title: title, href: saving.href) ? nil : "That did not save. Try again."
            }
        } label: {
            Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark").kjKicker()
        }
        .buttonStyle(HouseButtonStyle())
        .disabled(PassportSaves.pageRef(saving.pageID) == nil)
        .accessibilityIdentifier("tvpostSave")
        .accessibilityValue(saved ? "On" : "Off")
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .heading(let text): Text(text).font(MadrassaType.title(40))
        case .paragraph(let text), .item(let text): Text(String(text.characters)).font(MadrassaType.body()).lineSpacing(6)
        case .quote(let text): Text(String(text.characters)).font(MadrassaType.body(32)).italic().padding(.leading, 24)
        case .row(let cells): Text(cells.joined(separator: "    ")).kjBody()
        case .image(let url, let alt):
            VStack(alignment: .leading, spacing: 8) {
                TVPicture(url: url, maxPixel: 1600).frame(maxWidth: 1300, minHeight: 520, maxHeight: 520)
                if let alt, !alt.isEmpty { Text(alt).kjSmall(faint: true) }
            }
        case .embed: Text("A player is embedded here; it plays on the website.").kjSmall(faint: true)
        case .rule: Hairline()
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
        VStack(spacing: 0) {
            Button { } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text([entry.word, entry.translit].compactMap { $0 }.joined(separator: "  \u{00B7}  ")).font(MadrassaType.title(32))
                    if let meaning = entry.meaning ?? entry.gloss { Text(meaning).font(MadrassaType.body()) }
                    Text([entry.lang, entry.region, entry.sensitivity.map { "Sensitivity: \($0)" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .kjSmall(faint: true)
                }
                .frame(maxWidth: 1400, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)))
            Hairline()
        }
    }
}
