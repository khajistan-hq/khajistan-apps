import SwiftUI

/// PICS/VIDS: the Born Digital stream at /browse-archive.html, read as the page reads it
/// (Core/PicsVids.swift, ported from the Apple TV app). Two columns on a phone, more on a wide
/// screen; each tile the object's own shape, never cropped, the shortest column taking the next.
struct PicsVidsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewing: PnvRow?
    @State private var dontAskAgain = false

    private var store: PicsVidsStore { model.pnv }
    private var columnCount: Int { sizeClass == .regular ? 4 : 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.noticeVisible { notice }
                PageHead(kicker: "Pics/Vids", "Born Digital Media", line: nil)
                if let summary = store.summary { Text(summary).kjSmall(faint: true).padding(.top, -8) }
                if store.phase == .ready { filters }
                stream
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .animation(.kj, value: store.noticeVisible)
        }
        .task { await store.start() }
        .fullScreenCover(item: $viewing) { row in
            PnvViewerView(row: row)
        }
    }

    // MARK: - Notice

    /// The site's notice, in its words. It states what the archive holds and blocks nothing.
    private var notice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AdultNotice.heading).kjName().foregroundStyle(palette.onBand)
            Text(AdultNotice.body).kjSmall().foregroundStyle(palette.onBand)
            HStack(spacing: 16) {
                Button {
                    withAnimation(.kj) { store.dismissNotice(dontAskAgain: dontAskAgain) }
                } label: {
                    Text(AdultNotice.ok).kjKicker(palette.band).frame(minWidth: 64)
                }
                .buttonStyle(OnBandButtonStyle())
                .accessibilityIdentifier("adultNoticeOK")
                HouseSwitch(title: AdultNotice.dontAskAgain, detail: nil, isOn: $dontAskAgain)
                    .environment(\.palette, palette.onBandPlate)
                    .accessibilityIdentifier("adultNoticeDontAsk")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.band)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adultNotice")
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    tab("Everything", current: store.kind == nil, id: "pnvkind-all") { await store.select(kind: nil) }
                    ForEach(PnvKind.allCases, id: \.self) { kind in
                        tab(kind.label, current: store.kind == kind, id: "pnvkind-\(kind.rawValue)") { await store.select(kind: kind) }
                    }
                }
            }
            if !store.regions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        tab("All", current: store.region == nil, id: "pnvregion-all") { await store.select(region: nil) }
                        ForEach(store.regions, id: \.self) { token in
                            tab(PnvRegions.label(token), current: store.region == token, id: "pnvregion-\(token)") { await store.select(region: token) }
                        }
                    }
                }
            }
            Text(store.total.map { "\($0.formatted()) \($0 == 1 ? "object" : "objects")" } ?? " ")
                .kjSmall(faint: true)
                .padding(.leading, 12)
                .padding(.top, 6)
                .accessibilityIdentifier("pnvCount")
        }
        .padding(.horizontal, -12)
    }

    private func tab(_ title: String, current: Bool, id: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title).kjKicker()
        }
        .buttonStyle(HouseTabStyle(isCurrent: current))
        .accessibilityIdentifier(id)
    }

    // MARK: - The stream

    @ViewBuilder
    private var stream: some View {
        switch store.phase {
        case .idle, .loading:
            TuningLoader("Loading the archive\u{2026}").frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            problem(message)
        case .ready:
            if store.items.isEmpty {
                if let error = store.pageError {
                    problem(error)
                } else if store.isDone {
                    Text("Nothing filed under this yet.").kjBody()
                } else {
                    TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 200)
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
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(layout.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: 14) {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pnvStream")
        .accessibilityValue(String(store.items.count))
    }

    private func tile(_ row: PnvRow) -> some View {
        Button {
            viewing = row
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect, maxPixel: 700)
                HStack(spacing: 6) {
                    if row.isVideo { Kicker("\u{25B6} Video") }
                    Text("@" + store.accountHandle(for: row)).kjSmall(faint: true).lineLimit(1)
                }
            }
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .accessibilityIdentifier("tile-\(row.media_key)")
        .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(store.accountHandle(for: row))")
    }

    @ViewBuilder
    private var footer: some View {
        if let error = store.pageError {
            problem(error)
        } else if store.isDone {
            Text("\(store.items.count.formatted()) \(store.items.count == 1 ? "object" : "objects") \u{00B7} that is all of it")
                .kjSmall(faint: true)
        } else {
            TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func problem(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).kjBody()
            Button { Task { await store.retry() } } label: { Text("Try again").kjKicker() }
                .buttonStyle(HouseButtonStyle(solid: true))
                .accessibilityIdentifier("pnvRetry")
        }
    }
}

/// A picture at its own shape: a plate in the lift colour holds the space from the first frame,
/// and the image fades in over it, fitted, never cropped. Addresses are tried in order.
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
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).transition(.opacity)
                }
            }
            .task(id: urls) {
                let loaded = await PnvImages.shared.image(urls, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.22)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}
