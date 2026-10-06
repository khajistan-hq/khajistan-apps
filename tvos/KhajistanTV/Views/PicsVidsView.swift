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

    private enum Focus: Hashable { case firstTab }

    /// An object chosen, and the shelf it was chosen from.
    private struct Viewing: Identifiable {
        let row: PnvRow
        let region: String
        var id: String { row.id }
    }

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
        .task { await store.start() }
        .fullScreenCover(item: $viewing) { choice in
            PnvViewerView(row: choice.row, region: choice.region)
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
            kindTab("Everything", kind: nil)
                .focused($focus, equals: .firstTab)
            ForEach(PnvKind.allCases, id: \.self) { kind in
                kindTab(kind.label, kind: kind)
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        .focusSection()
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
                ForEach(store.regions, id: \.self) { region in
                    PnvRegionShelf(region: region) { row in
                        viewing = Viewing(row: row, region: region)
                    }
                }
            }
        }
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

/// One region's shelf. It asks for its own first page when it comes on screen, and for the next
/// when focus is within a few cards of its end. A region with nothing under the filter has no shelf.
private struct PnvRegionShelf: View {
    let region: String
    let open: (PnvRow) -> Void
    @Environment(AppModel.self) private var model

    static let tileHeight: CGFloat = 300
    static let captionHeight: CGFloat = 72

    private var store: PicsVidsStore { model.pnv }

    var body: some View {
        let feed = store.feed(region)
        if feed.isDone && feed.items.isEmpty {
            EmptyView()
        } else {
            let nearEnd = Set(feed.items.suffix(8).map(\.id))
            Shelf(PnvRegions.label(region), count: feed.total.map { $0.formatted() }) {
                if feed.items.isEmpty {
                    placeholder(feed)
                } else {
                    ForEach(feed.items) { row in
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
                            .frame(width: 160, height: Self.tileHeight)
                    }
                }
            }
            // The count of objects drawn so far, for the UI test that walks the paging.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pnv-shelf-\(region)")
            .accessibilityValue(String(feed.items.count))
            // The first page, again whenever the filter starts the shelves over.
            .task(id: store.kind) { await store.loadMore(region: region) }
        }
    }

    /// Holds the shelf's height until its first page lands, so nothing below it moves.
    @ViewBuilder
    private func placeholder(_ feed: PnvFeed) -> some View {
        Group {
            if let error = feed.error {
                retry(error)
            } else {
                TuningLoader("Loading\u{2026}")
            }
        }
        .frame(width: 600, height: Self.tileHeight + 12 + Self.captionHeight, alignment: .leading)
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
        .frame(width: 600, height: Self.tileHeight, alignment: .leading)
    }

    private func tile(_ row: PnvRow) -> some View {
        Button {
            open(row)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect, height: Self.tileHeight, maxPixel: 900)
                    .kjCardArt()
                // The caption takes the picture's width and is cut to it.
                Color.clear
                    .frame(height: Self.captionHeight)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if row.isVideo { Kicker("\u{25B6} Video").lineLimit(1) }
                            Text("@" + store.accountHandle(for: row))
                                .kjSmall(faint: true)
                                .lineLimit(1)
                        }
                    }
            }
        }
        .buttonStyle(HouseCardStyle())
        .accessibilityIdentifier("tile-\(row.media_key)")
        .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(store.accountHandle(for: row))")
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
