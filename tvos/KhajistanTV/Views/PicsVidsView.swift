import SwiftUI

/// Pics/Vids: the Born Digital archive at /browse-archive.html. Everything the site shows and
/// nothing it does not (Core/PicsVids.swift). The page is one shelf per region the roster carries,
/// west to east, each its own stream, paged on its own as focus nears its end. A card is the
/// object's own shape at a fixed height, never cropped. The one filter, Everything / Pictures /
/// Videos, applies to every shelf.
struct PicsVidsView: View {
    @Environment(AppModel.self) private var model
    @State private var viewing: Viewing?
    @State private var dontAskAgain = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case noticeOK, firstTab }

    /// An object chosen, and the shelf it was chosen from: a region's stream, or a saved list.
    private struct Viewing: Identifiable {
        let row: PnvRow
        var region: String = ""
        var list: [PnvRow]? = nil
        var videosOnly = false
        var id: String { row.id }
    }

    @Environment(\.scenePhase) private var scenePhase
    private var store: PicsVidsStore { model.pnv }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.noticeVisible { notice }
                header
                if store.phase == .ready { filters }
                shelves
            }
            .kjBody()
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 32)
            .padding(.bottom, KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kjTopFade()
        // Down from the top bar lands on the first control, never on the tile under the bar item.
        .defaultFocus($focus, store.noticeVisible ? .noticeOK : .firstTab, priority: .userInitiated)
        // A new hand if the page was left, dealt before the shelves' first loads ask.
        .onAppear { store.dealIfLeft() }
        .task {
            // Held to one kind before the shelves ask, so no photo is ever asked for.
            if let only = StoreBuild.picsVidsKind { store.select(kind: only) }
            await store.start()
        }
        .onDisappear {
            // Left for another section (not for an object opened over the page): the next visit
            // deals again (owner, 2026-11-14: "shuffle everytime").
            if viewing == nil { store.pageLeft() }
        }
        .task(id: model.auth.email) { await model.saves.load() }
        // Back from the background (the app left on this page overnight): a new deal too.
        .onChange(of: scenePhase) { old, new in
            // The page is on screen here, so the deal is made at once.
            if old == .background, new != .background, viewing == nil { store.setShuffled(true) }
        }
        .kjFullScreenCover(item: $viewing) { choice in
            if let list = choice.list {
                PnvViewerView(row: choice.row, list: list)
            } else {
                PnvViewerView(row: choice.row, region: choice.region, videosOnly: choice.videosOnly)
            }
        }
    }

    // MARK: - Notice

    /// The site's entry notice, in its words. It states what the archive holds and gets out of the
    /// way: nothing is blocked, and the stream loads under it.
    private var notice: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(AdultNotice.heading).kjName()
            Text(AdultNotice.body)
                .kjBody()
                .frame(maxWidth: 1200, alignment: .leading)
            HStack(spacing: 28) {
                Button {
                    store.dismissNotice(dontAskAgain: dontAskAgain)
                    focus = .firstTab
                } label: {
                    Text(AdultNotice.ok).kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .focused($focus, equals: .noticeOK)
                .accessibilityIdentifier("adultNoticeOK")
                HouseSwitch(title: AdultNotice.dontAskAgain, detail: nil, isOn: $dontAskAgain)
                    .accessibilityIdentifier("adultNoticeDontAsk")
            }
            .padding(.leading, -26)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adultNotice")
    }

    // MARK: - Header and filters

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The page's own title: the nav says PICS/VIDS, the page says Born Digital Media.
            Text("Born Digital Media")
                .kjDisplay(KJType.headline, tracking: -0.055)
                .accessibilityAddTraits(.isHeader)
            if let summary = store.summary {
                Text(summary).kjSmall(faint: true)
            }
        }
    }

    /// The page's one control. The regions are the shelves under it.
    private var filters: some View {
        HStack(spacing: 12) {
            // Held to one kind (StoreBuild.picsVidsKind): no tabs, and Shuffle takes first focus.
            if StoreBuild.picsVidsKind == nil {
                kindTab("Everything", kind: nil)
                    .focused($focus, equals: .firstTab)
                ForEach(PnvKind.allCases, id: \.self) { kind in
                    kindTab(kind.label, kind: kind)
                }
                shuffleButton.padding(.leading, 28)
            } else {
                shuffleButton.focused($focus, equals: .firstTab)
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        // The section spans the page, so Up from a tile anywhere on the top shelf lands here.
        // Hugging its buttons, it covered only the left: Up from a right-hand tile found nothing
        // above it and went to the top bar, or nowhere (UI test, 2026-11-25).
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// A new deal now, every shelf from a new random place, as the Receiver's Surf.
    private var shuffleButton: some View {
        Button {
            store.setShuffled(true)
        } label: {
            Label("Shuffle", systemImage: "shuffle").kjKicker()
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 26, bottom: 14, trailing: 26)))
        .accessibilityIdentifier("pnvShuffle")
    }

    private func kindTab(_ title: String, kind: PnvKind?) -> some View {
        Button {
            store.select(kind: kind)
        } label: {
            Text(title).kjKicker()
        }
        .buttonStyle(HouseTabStyle(isCurrent: store.kind == kind))
        .accessibilityIdentifier("pnvkind-\(kind?.rawValue ?? "all")")
    }

    // MARK: - The shelves

    @ViewBuilder
    private var shelves: some View {
        switch store.phase {
        case .idle, .loading:
            TuningLoader("Loading the archive\u{2026}")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let message):
            problem(message)
        case .ready:
            LazyVStack(alignment: .leading, spacing: 8) {
                // What this account saved, and its collections, above the regions, as Cosmos
                // keeps them a press away. On the account, so the same on every device.
                if model.auth.isSignedIn {
                    PnvSavedShelf(title: "Saved", id: "saved", keys: model.saves.savedPnvKeys) { row, list in
                        viewing = Viewing(row: row, list: list)
                    }
                    ForEach(model.saves.collections) { collection in
                        PnvSavedShelf(title: collection.name, id: collection.id, keys: collection.media_keys) { row, list in
                            viewing = Viewing(row: row, list: list)
                        }
                    }
                }
                // Every region mixed, large, first: the page opens on pictures, a new hand each
                // visit (owner, 2026-11-14: "the same photos are just there and look boring").
                PnvRegionShelf(region: PicsVidsStore.allRegions, title: "All regions",
                               tileHeight: PnvRegionShelf.largeTileHeight) { row in
                    open(row, region: PicsVidsStore.allRegions)
                }
                ForEach(store.regions, id: \.self) { region in
                    PnvRegionShelf(region: region) { row in
                        open(row, region: region)
                    }
                }
            }
        }
    }

    /// A video opens as the Reel of its shelf's region: it plays first, then that region's videos
    /// follow by themselves, Up and Down between them (owner, 2026-11-20: every region's row works
    /// as the Reel did, and the Reel button goes). A picture opens as before.
    private func open(_ row: PnvRow, region: String) {
        guard row.isVideo else { viewing = Viewing(row: row, region: region); return }
        store.seedReel(with: row, region: region)
        viewing = Viewing(row: row, region: region, videosOnly: true)
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
            .accessibilityIdentifier("pnvRetry")
        }
    }
}

/// Saved objects, or one collection, as a shelf: the keys made rows through the gated public view,
/// so an object taken off the shelf since is not drawn. The newest hundred; the rest are on the
/// phone and the website. Nothing is drawn while there is nothing in it.
private struct PnvSavedShelf: View {
    let title: String
    let id: String
    let keys: [String]
    let open: (PnvRow, [PnvRow]) -> Void
    @Environment(AppModel.self) private var model
    @State private var rows: [PnvRow] = []

    var body: some View {
        Group {
            if !rows.isEmpty {
                Shelf(title, count: rows.count.formatted()) {
                    ForEach(rows) { row in
                        PnvTile(row: row, handle: model.pnv.accountHandle(for: row)) { open(row, rows) }
                            .accessibilityIdentifier("saved-\(id)-\(row.media_key)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("pnv-saved-\(id)")
            }
        }
        .task(id: keys) { await hydrate() }
    }

    private func hydrate() async {
        let wanted = Array(keys.prefix(100))
        guard !wanted.isEmpty else { rows = []; return }
        guard let (data, response) = try? await URLSession.shared.data(for: PnvAPI.rowsRequest(mediaKeys: wanted)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let page = try? JSONDecoder().decode([PnvRow].self, from: data), !Task.isCancelled else { return }
        let found = Dictionary(page.map { ($0.media_key, $0) }, uniquingKeysWith: { first, _ in first })
        rows = PnvKind.shown(wanted.compactMap { found[$0] }, only: StoreBuild.picsVidsKind)
    }
}

/// One region's shelf. It asks for its own first page when it comes on screen, and for the next
/// when focus is within a few cards of its end. A region with nothing under the filter has no shelf.
private struct PnvRegionShelf: View {
    let region: String
    var title: String? = nil
    var tileHeight: CGFloat = PnvRegionShelf.tileHeight
    let open: (PnvRow) -> Void
    @Environment(AppModel.self) private var model

    static let tileHeight: CGFloat = 300
    /// The all-regions shelf at the top of the page.
    static let largeTileHeight: CGFloat = 460
    static let captionHeight: CGFloat = 72

    private var store: PicsVidsStore { model.pnv }

    var body: some View {
        let feed = store.feed(region)
        if feed.isDone && feed.items.isEmpty {
            EmptyView()
        } else {
            let nearEnd = Set(feed.items.suffix(8).map(\.id))
            Shelf(title ?? PnvRegions.label(region), count: feed.total.map { $0.formatted() }) {
                if feed.items.isEmpty {
                    placeholder(feed)
                } else {
                    ForEach(PnvKind.shown(feed.items, only: StoreBuild.picsVidsKind)) { row in
                        tile(row)
                            .onAppear {
                                if nearEnd.contains(row.id) { Task { await store.loadMore(region: region) } }
                            }
                    }
                    if let error = feed.error {
                        retry(error)
                    } else if feed.isLoading {
                        TuningLoader(nil)
                            .scaleEffect(0.5)
                            .frame(width: 160, height: tileHeight)
                    }
                }
            }
            // The count of objects drawn so far, for the UI test that walks the paging.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pnv-shelf-\(region)")
            .accessibilityValue(String(feed.items.count))
            // The first page, again whenever the filter starts the shelves over.
            .task(id: store.deal) { await store.loadMore(region: region) }
        }
    }

    /// Holds the shelf's height until its first page lands, so nothing below it moves.
    @ViewBuilder
    private func placeholder(_ feed: PnvFeed) -> some View {
        Group {
            if let error = feed.error {
                retry(error)
            } else {
                TuningLoader("Loading\u{2026}", bird: 120)
            }
        }
        .frame(width: 600, height: tileHeight + 12 + Self.captionHeight, alignment: .leading)
    }

    private func retry(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(message).kjBody()
            Button {
                Task { await store.retry(region: region) }
            } label: {
                Text("Try again").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .accessibilityIdentifier("pnvRetry")
        }
        .frame(width: 600, height: tileHeight, alignment: .leading)
    }

    private func tile(_ row: PnvRow) -> some View {
        PnvTile(row: row, handle: store.accountHandle(for: row), height: tileHeight) { open(row) }
            .accessibilityIdentifier("tile-\(row.media_key)")
    }
}

/// A card: the object at its own shape at the shelf's height, never cropped, with *▶ Video* and
/// the account under it.
private struct PnvTile: View {
    let row: PnvRow
    let handle: String
    var height: CGFloat = PnvRegionShelf.tileHeight
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect, height: height, maxPixel: 900)
                    .kjCardArt()
                // The caption takes the picture's width and is cut to it.
                Color.clear
                    .frame(height: PnvRegionShelf.captionHeight)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if row.isVideo { Kicker("\u{25B6} Video").lineLimit(1) }
                            Text("@" + handle)
                                .kjSmall(faint: true)
                                .lineLimit(1)
                        }
                    }
            }
        }
        .buttonStyle(HouseCardStyle())
        .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(handle)")
    }
}

/// A picture at its own shape and a fixed height: a plate in the house lift colour holds the
/// space, and the image is fitted inside it, never cropped. Addresses are tried in order.
struct PnvPicture: View {
    let urls: [URL]
    let aspect: Double?
    let height: CGFloat
    let maxPixel: Int
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    private var ratio: CGFloat {
        if let aspect { return CGFloat(aspect) }
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        return 1
    }

    var body: some View {
        Rectangle()
            .fill(palette.lift)
            .frame(width: height * ratio, height: height)
            .overlay {
                // Fades in over the plate that held its space.
                FadeIn(shown: image != nil) {
                    Image(uiImage: image ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .task(id: urls) {
                image = await PnvImages.shared.image(urls, maxPixel: maxPixel)
            }
            .accessibilityHidden(true)
    }
}
