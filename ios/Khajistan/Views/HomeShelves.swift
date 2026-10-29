import SwiftUI

/// A shelf on Home for each part of Khajistan (owner, 2026-10-29: "all nav carousels should show
/// up in home ... we need all branches/sections of khajistan"), each the part's own covers and
/// pictures in a row that scrolls sideways, its heading leading to the whole room. A part whose
/// catalogue has not come draws nothing, so no shelf stands empty.
///
/// The Reading Room's catalogue is read for this shelf; the store keeps its copy for six hours,
/// so Home costs at most that one download in that time.
struct HomeShelves: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewing: PnvRow?

    private static let shelfLength = 16
    private var cardWidth: CGFloat { sizeClass == .regular ? 170 : 132 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            receiver
            if StoreBuild.includes(.reading) { reading }
            if StoreBuild.includes(.screening) { films }
            if StoreBuild.includes(.picsVids) { picsVids }
            madrassa
            bazaar
            if StoreBuild.includes(ArchiveDestination.all.first { $0.id == "chat" }!) { chat }
        }
        // The channel the app opens on comes first: the shelves load a moment after Home.
        .task {
            try? await Task.sleep(for: .seconds(2))
            if StoreBuild.includes(.picsVids) {
                await model.pnv.start()
                if model.pnv.phase == .ready, model.pnv.feed(model.pnvRegion).isUntouched {
                    await model.pnv.loadMore(region: model.pnvRegion)
                }
            }
            if StoreBuild.includes(.reading) { await model.reading.start() }
            await model.chat.start()
        }
        .task(id: model.auth.previewPassword) {
            try? await Task.sleep(for: .seconds(2))
            await model.films.load()
            await model.bazaar.load()
            await model.bazaarSwap.load()
            await model.madrassaPosts.load()
        }
        .fullScreenCover(item: $viewing) { PnvViewerView(row: $0) }
    }

    // MARK: - Receiver

    private var receiver: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Receiver") { model.tab = .receiver }
            Button {
                model.tab = .receiver
                Task { await model.tuner.surf() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Surf").font(.system(.title2, weight: .bold))
                    Text("A live channel at random, as set under the Receiver's Surf").kjSmall(faint: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)))
            .accessibilityIdentifier("home-surf")
        }
    }

    // MARK: - Reading Room

    @ViewBuilder
    private var reading: some View {
        let titles = model.reading.titles
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Reading Room", count: titles.count) { model.open(.reading) }
                row {
                    ForEach(titles.prefix(Self.shelfLength)) { title in
                        RoomLink(route: .readingTitle(title.slug), in: .reading) {
                            VStack(alignment: .leading, spacing: 6) {
                                RRCover(state: model.reading.card(for: title))
                                    .frame(width: cardWidth, height: cardWidth * 1.38)
                                Text(title.name).font(.system(.subheadline, weight: .semibold)).lineLimit(2)
                                    .frame(width: cardWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .onAppear { model.reading.want(title) }
                        .accessibilityIdentifier("home-rr-\(title.slug)")
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-reading")
        }
    }

    // MARK: - Screening Room

    @ViewBuilder
    private var films: some View {
        let films = model.films.films
        if !films.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Screening Room", count: films.count) { model.open(.screening) }
                row {
                    ForEach(films.prefix(Self.shelfLength)) { film in
                        FilmCard(film: film, width: cardWidth, fromHome: true)
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-films")
        }
    }

    // MARK: - Pics/Vids

    /// Until the reader has answered the adult material notice in the room, the shelf is one line
    /// that takes them there to read it: no picture is shown before the notice is.
    @ViewBuilder
    private var picsVids: some View {
        let store = model.pnv
        let rows = Array(store.feed(model.pnvRegion).items.prefix(Self.shelfLength))
        if store.noticeVisible {
            VStack(alignment: .leading, spacing: 4) {
                heading("Pics/Vids") { model.open(.picsVids) }
                Text("Born Digital Media. The room opens on a note about adult material.").kjSmall(faint: true)
            }
            .accessibilityIdentifier("home-shelf-picsvids")
        } else if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Pics/Vids") { model.open(.picsVids) }
                row {
                    ForEach(rows) { item in
                        Button { viewing = item } label: {
                            PnvPicture(urls: PnvMedia.pictureCandidates(item), aspect: item.aspect, maxPixel: 480)
                                .frame(height: cardWidth * 1.2)
                                .overlay(alignment: .topTrailing) { if item.isVideo { VideoBadge().padding(6) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isVideo ? "Video" : "Picture")
                        .accessibilityIdentifier("home-pnv-\(item.media_key)")
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-picsvids")
        }
    }

    // MARK: - Madrassa

    @ViewBuilder
    private var madrassa: some View {
        if let posts = model.madrassaPosts.value, !posts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Madrassa", count: posts.count) { model.open(.madrassa) }
                row {
                    ForEach(posts.prefix(Self.shelfLength)) { post in
                        RoomLink(route: .post(post.id), in: .madrassa) {
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if let image = post.image, let url = URL(string: image), url.scheme == "https" {
                                        ProductPicture(url: url)
                                    } else {
                                        RoomPicture(room: .madrassa).aspectRatio(1, contentMode: .fit)
                                    }
                                }
                                .frame(width: cardWidth * 1.4)
                                Text(MadrassaWritings.listTitle(post)).font(.system(.subheadline, design: .serif, weight: .semibold))
                                    .lineLimit(3).multilineTextAlignment(.leading)
                                    .frame(width: cardWidth * 1.4, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-post-\(post.id)")
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-madrassa")
        }
    }

    // MARK: - Bazaar

    @ViewBuilder
    private var bazaar: some View {
        if let items = model.bazaar.value, !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Bazaar", count: items.count) { model.open(.bazaar) }
                row {
                    ForEach(items.prefix(Self.shelfLength)) { item in
                        RoomLink(route: .product(item.product.h), in: .bazaar) {
                            VStack(alignment: .leading, spacing: 6) {
                                ProductPicture(url: Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 400))
                                Text(item.product.title).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                                if let price = Bazaar.priceLine(item.product) {
                                    Text(price).font(.system(.subheadline, weight: .bold))
                                }
                            }
                            .frame(width: cardWidth, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-product-\(item.product.h)")
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-bazaar")
        }
    }

    // MARK: - Chat

    @ViewBuilder
    private var chat: some View {
        let rooms = model.chat.groups.flatMap(\.rooms)
        if !rooms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Chat", count: rooms.count) { model.open(.chat) }
                row {
                    ForEach(rooms.prefix(Self.shelfLength)) { room in
                        Button { model.open(.chat) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if let place = room.country ?? room.region { Kicker(place).lineLimit(1) }
                                Text(room.label).font(.system(.headline, weight: .bold)).lineLimit(2)
                            }
                            .frame(width: cardWidth * 1.3, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)))
                        .accessibilityIdentifier("home-chat-\(room.slug)")
                    }
                }
            }
            .accessibilityIdentifier("home-shelf-chat")
        }
    }

    // MARK: - Parts

    private func heading(_ title: String, count: Int? = nil, open: @escaping () -> Void) -> some View {
        ShelfHeader(title: title, count: count, action: open)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) { content() }
        }
        .scrollClipDisabled()
    }
}
