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
    /// The feed under the region filter.
    private var feed: PnvFeed { store.feed(model.pnvRegion) }
    private var columnCount: Int { sizeClass == .regular ? 4 : 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.noticeVisible { notice }
                HStack(alignment: .top) {
                    LargeTitle(title: "Pics/Vids", line: store.summary ?? "Born Digital Media")
                    if model.auth.isSignedIn {
                        // Cosmos keeps what you collected one tap away, top right.
                        NavigationLink(value: RoomRoute.pnvSaved) {
                            Image(systemName: "bookmark").font(.system(.title2, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Saved")
                        .accessibilityIdentifier("pnvSavedLink")
                    }
                }
                if store.phase == .ready { filters }
                stream
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .animation(.kj, value: store.noticeVisible)
        }
        .task { await store.start() }
        // The store pages each feed only when asked; ask for the first page whenever the region,
        // the kind or the store's readiness changes and that feed has none yet.
        .task(id: "\(model.pnvRegion)|\(store.kind?.rawValue ?? "all")|\(store.phase == .ready)") {
            if store.phase == .ready, feed.isUntouched { await store.loadMore(region: model.pnvRegion) }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            ChipRow(chips: [Chip(id: "", title: "Everything", identifier: "pnvkind-all")]
                        + PnvKind.allCases.map { Chip(id: $0.rawValue, title: $0.label, identifier: "pnvkind-\($0.rawValue)") },
                    selected: store.kind?.rawValue ?? "") { id in store.select(kind: PnvKind.allCases.first { $0.rawValue == id }) }
            if !store.regions.isEmpty {
                ChipRow(chips: [Chip(id: PicsVidsStore.allRegions, title: "All regions", identifier: "pnvregion-all")]
                            + store.regions.map { Chip(id: $0, title: PnvRegions.label($0), identifier: "pnvregion-\($0)") },
                        selected: model.pnvRegion) { model.pnvRegion = $0 }
            }
            Text(feed.total.map { "\($0.formatted()) \($0 == 1 ? "object" : "objects")" } ?? " ")
                .kjSmall(faint: true)
                .padding(.top, 2)
                .accessibilityIdentifier("pnvCount")
        }
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
            if feed.items.isEmpty {
                if let error = feed.error {
                    problem(error)
                } else if feed.isDone {
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
        let layout = PnvLayout.columns(feed.items, count: columnCount)
        let nearEnd = Set(feed.items.suffix(12).map(\.id))
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(layout.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(column) { row in
                        tile(row)
                            .onAppear {
                                if nearEnd.contains(row.id) { Task { await store.loadMore(region: model.pnvRegion) } }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pnvStream")
        .accessibilityValue(String(feed.items.count))
    }

    private func tile(_ row: PnvRow) -> some View {
        Button {
            viewing = row
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect, maxPixel: 700)
                    .overlay(alignment: .topTrailing) { if row.isVideo { VideoBadge().padding(6) } }
                Text("@" + store.accountHandle(for: row)).kjSmall(faint: true).lineLimit(1)
            }
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .accessibilityIdentifier("tile-\(row.media_key)")
        .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(store.accountHandle(for: row))")
    }

    @ViewBuilder
    private var footer: some View {
        if let error = feed.error {
            problem(error)
        } else if feed.isDone {
            Text("\(feed.items.count.formatted()) \(feed.items.count == 1 ? "object" : "objects") \u{00B7} that is all of it")
                .kjSmall(faint: true)
        } else {
            TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func problem(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).kjBody()
            Button {
                Task {
                    if case .failed = store.phase { await store.retry() } else { await store.retry(region: model.pnvRegion) }
                }
            } label: { Text("Try again").kjKicker() }
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: urls) {
                let loaded = await PnvImages.shared.image(urls, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.22)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}


// MARK: - Saved

/// What this account saved from Pics/Vids, and its named collections, read through the gated
/// public view: an object taken off the shelf since it was saved is not drawn. Saved on the
/// account, so the same on the website and every device signed in.
struct PnvSavedScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var collection: String?
    @State private var rows: [PnvRow] = []
    @State private var phase: Phase = .loading
    @State private var viewing: PnvRow?

    private enum Phase: Equatable { case loading, ready, failed }

    private var keys: [String] {
        if let collection, let found = model.saves.collections.first(where: { $0.id == collection }) { return found.media_keys }
        return model.saves.savedPnvKeys
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LargeTitle(title: "Saved", line: "Pics/Vids saved to your account")
                if !model.auth.isSignedIn {
                    Text("Sign in to see what you saved.").kjBody()
                } else {
                    if !model.saves.collections.isEmpty {
                        ChipRow(chips: [Chip(id: "", title: "All saved", identifier: "pnvcollection-all")]
                                    + model.saves.collections.map { Chip(id: $0.id, title: $0.name, identifier: "pnvcollection-\($0.id)") },
                                selected: collection ?? "") { collection = $0.isEmpty ? nil : $0 }
                    }
                    switch phase {
                    case .loading: TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity)
                    case .failed:
                        ReadingProblem(message: "The archive did not answer.") { Task { await hydrate() } }
                    case .ready:
                        if rows.isEmpty {
                            Text(keys.isEmpty ? "Nothing saved yet. Save an object from its viewer." : "None of these objects is on the shelf now.")
                                .kjBody().accessibilityIdentifier("pnvSavedEmpty")
                        } else {
                            Text("\(rows.count.formatted()) object\(rows.count == 1 ? "" : "s")" + (keys.count > 500 ? " \u{00B7} the newest 500" : "")).kjSmall(faint: true)
                                .accessibilityIdentifier("pnvSavedCount")
                            // The same shape-true columns as the stream, as Cosmos lays out a collection.
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(Array(PnvLayout.columns(rows, count: sizeClass == .regular ? 4 : 2).enumerated()), id: \.offset) { _, column in
                                    LazyVStack(spacing: 8) {
                                        ForEach(column) { row in
                                            Button { viewing = row } label: {
                                                PnvPicture(urls: PnvMedia.pictureCandidates(row), aspect: row.aspect, maxPixel: 500)
                                                    .overlay(alignment: .topTrailing) { if row.isVideo { VideoBadge().padding(6) } }
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(row.isVideo ? "Saved video" : "Saved picture")
                                            .accessibilityIdentifier("saved-\(row.media_key)")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
        }
        .task(id: "\(model.auth.email ?? "")|\(collection ?? "")|\(model.saves.savedPnvKeys.count)") { await hydrate() }
        .fullScreenCover(item: $viewing) { row in PnvViewerView(row: row, steps: false).environment(model) }
    }

    /// Keys to rows, in the saved order, a hundred at a time.
    private func hydrate() async {
        await model.saves.load()
        let wanted = keys
        guard !wanted.isEmpty else { rows = []; phase = .ready; return }
        phase = .loading
        var found: [String: PnvRow] = [:]
        for start in stride(from: 0, to: min(wanted.count, 500), by: 100) {
            let chunk = Array(wanted[start..<min(start + 100, wanted.count)])
            guard let (data, response) = try? await URLSession.shared.data(for: PnvAPI.rowsRequest(mediaKeys: chunk)),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let page = try? JSONDecoder().decode([PnvRow].self, from: data) else {
                // A fetch cancelled by a newer one says nothing; the newer one answers.
                if !Task.isCancelled { phase = .failed }
                return
            }
            for row in page { found[row.media_key] = row }
        }
        guard !Task.isCancelled else { return }
        rows = wanted.compactMap { found[$0] }
        phase = .ready
    }
}

/// A video's mark on its tile: a play glyph on a small ink plate.
struct VideoBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(palette.ground)
            .frame(width: 24, height: 24)
            .background(palette.ink.opacity(0.85), in: Circle())
            .accessibilityHidden(true)
    }
}
