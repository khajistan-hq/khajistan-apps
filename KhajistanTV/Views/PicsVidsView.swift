import SwiftUI

/// Pics/Vids: the Born Digital stream at /browse-archive.html. Everything the site shows and
/// nothing it does not (Core/PicsVids.swift). The stream is four columns, each tile the object's
/// own shape and never cropped, the shortest column taking the next tile as on the site.
struct PicsVidsView: View {
    @Environment(AppModel.self) private var model
    @State private var viewing: PnvRow?
    @State private var dontAskAgain = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case firstTab }

    private var store: PicsVidsStore { model.pnv }
    private let columnCount = 4
    /// The plates' padding is pulled back so tile images sit on the page margin.
    private let tilePadding: CGFloat = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.noticeVisible { notice }
                header
                if store.phase == .ready { filters }
                stream
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await store.start() }
        .fullScreenCover(item: $viewing) { row in
            PnvViewerView(row: row)
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

    private var filters: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                kindTab("Everything", kind: nil)
                    .focused($focus, equals: .firstTab)
                ForEach(PnvKind.allCases, id: \.self) { kind in
                    kindTab(kind.label, kind: kind)
                }
            }
            if !store.regions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        regionTab("All", token: nil)
                        ForEach(store.regions, id: \.self) { token in
                            regionTab(PnvRegions.label(token), token: token)
                        }
                    }
                }
                .scrollClipDisabled()
            }
            if let total = store.total {
                Text("\(total.formatted()) \(total == 1 ? "object" : "objects")")
                    .kjSmall(faint: true)
                    .padding(.top, 12)
                    .padding(.leading, 22)
                    .accessibilityIdentifier("pnvCount")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        .focusSection()
    }

    private func kindTab(_ title: String, kind: PnvKind?) -> some View {
        Button {
            Task { await store.select(kind: kind) }
        } label: {
            Text(title).kjKicker()
        }
        .buttonStyle(HouseTabStyle(isCurrent: store.kind == kind))
        .accessibilityIdentifier("pnvkind-\(kind?.rawValue ?? "all")")
    }

    private func regionTab(_ title: String, token: String?) -> some View {
        Button {
            Task { await store.select(region: token) }
        } label: {
            Text(title).kjKicker()
        }
        .buttonStyle(HouseTabStyle(isCurrent: store.region == token))
        .accessibilityIdentifier("pnvregion-\(token ?? "all")")
    }

    // MARK: - The stream

    @ViewBuilder
    private var stream: some View {
        switch store.phase {
        case .idle, .loading:
            TuningLoader("Loading the archive\u{2026}")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let message):
            problem(message)
        case .ready:
            if store.items.isEmpty {
                if let error = store.pageError {
                    problem(error)
                } else if store.isDone {
                    Text("Nothing filed under this yet.").kjBody()
                } else {
                    TuningLoader("Loading\u{2026}")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            } else {
                columns
                footer
            }
        }
    }

    private var columns: some View {
        let layout = PnvLayout.columns(store.items, count: columnCount)
        let nearEnd = Set(store.items.suffix(12).map(\.id))
        return HStack(alignment: .top, spacing: 12) {
            ForEach(Array(layout.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(column) { row in
                        tile(row)
                            .onAppear {
                                if nearEnd.contains(row.id) { Task { await store.loadMore() } }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, -tilePadding)
        // The count of tiles drawn so far, for the UI test that walks the paging.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pnvStream")
        .accessibilityValue(String(store.items.count))
    }

    private func tile(_ row: PnvRow) -> some View {
        Button {
            viewing = row
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect, maxPixel: 900)
                HStack(spacing: 12) {
                    if row.isVideo { Kicker("\u{25B6} Video") }
                    Text("@" + store.accountHandle(for: row))
                        .kjSmall(faint: true)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: tilePadding, leading: tilePadding, bottom: tilePadding, trailing: tilePadding)))
        .accessibilityIdentifier("tile-\(row.media_key)")
        .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(store.accountHandle(for: row))")
    }

    @ViewBuilder
    private var footer: some View {
        if let error = store.pageError {
            problem(error)
        } else if store.isDone {
            // The site's closing line.
            Text("\(store.items.count.formatted()) \(store.items.count == 1 ? "object" : "objects") \u{00B7} that is all of it")
                .kjSmall(faint: true)
        } else {
            TuningLoader(nil)
                .frame(maxWidth: .infinity)
                .scaleEffect(0.5)
                .frame(height: 160)
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

/// A picture at its own shape: a plate in the house lift colour holds the space, and the image
/// is fitted inside it, never cropped. Addresses are tried in order.
struct PnvPicture: View {
    let urls: [URL]
    let aspect: Double?
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
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
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
