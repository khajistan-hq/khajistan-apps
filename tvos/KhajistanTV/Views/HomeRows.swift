import SwiftUI

/// The rest of Khajistan under the Receiver's front, a shelf for each part as the Apple TV app
/// lays its rows (owner, 2026-10-29: "all nav carousels should show up in home ... we need all
/// branches/sections of khajistan", and one "should be able to move down a page in home").
/// Each shelf shows the part's own covers and pictures, opens what is chosen where that part
/// opens it, and ends on a card that goes to the whole section. A part whose catalogue has not
/// come yet draws nothing, so no shelf stands empty.
struct HomeRows: View {
    @Environment(AppModel.self) private var model
    @State private var reading: RRTitle?
    @State private var product: BazaarItem?
    @State private var post: MadrassaPost?
    @State private var viewing: PnvRow?

    /// A shelf shows this many, then the card to the whole section.
    private static let shelfLength = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transmissionRow
            // A section this build leaves out (StoreBuild: Pics/Vids, Chat, the Reading Room and
            // every room but the Screening Room in the App Store build) has no shelf on Home either.
            if StoreBuild.includes(.reading) { readingRow }
            if StoreBuild.includes(.picsvids) { picsVidsRow }
            if !StoreBuild.roomsAreScreeningOnly {
                madrassaRow
                bazaarRow
            }
            if StoreBuild.includes(.chat) { chatRow }
        }
        // The channel the app opens on comes first: the shelves load a moment after the front.
        .task {
            try? await Task.sleep(for: .seconds(2))
            await model.transmission.loadSchedule()
            if StoreBuild.includes(.picsvids) {
                await model.pnv.start()
                if let region = model.pnv.regions.first, model.pnv.feed(region).isUntouched {
                    await model.pnv.loadMore(region: region)
                }
            }
            if StoreBuild.includes(.reading) { await model.reading.start() }
            if StoreBuild.includes(.chat) { await model.chat.start() }
        }
        .task(id: model.auth.previewPassword) {
            guard !StoreBuild.roomsAreScreeningOnly else { return }
            try? await Task.sleep(for: .seconds(2))
            await model.bazaar.load()
            await model.bazaarSwap.load()
            await model.madrassaPosts.load()
        }
        .fullScreenCover(item: $reading) { ReadingTitleView(title: $0) }
        .fullScreenCover(item: $product) { TVProductScreen(item: $0) }
        .fullScreenCover(item: $post) { TVMadrassa.reading($0, model: model) }
        .fullScreenCover(item: $viewing) { row in
            PnvViewerView(row: row, list: pnvRows)
        }
    }

    // MARK: - Transmission

    private var transmissionRow: some View {
        let store = model.transmission
        let now = TransmissionStore.now()
        return Shelf("Khajistan Transmission") {
            ForEach([1, 2], id: \.self) { number in
                let onAir = store.nowOn(channel: number, at: now)
                Button {
                    model.open(DeepLink.channel(number).url)
                } label: {
                    CardPlate(width: ChannelCard.width, height: ChannelCard.height) {
                        VStack(alignment: .leading, spacing: 10) {
                            Kicker(onAir == nil ? "Channel \(number)" : "Channel \(number) \u{00B7} On air")
                            if store.programming != nil {
                                Text(onAir?.show?.name ?? store.channelName(number))
                                    .kjName()
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .buttonStyle(HouseCardStyle())
                .accessibilityIdentifier("home-transmission-\(number)")
            }
        }
        .accessibilityIdentifier("home-shelf-transmission")
    }

    // MARK: - Reading Room

    @ViewBuilder
    private var readingRow: some View {
        let titles = model.reading.titles
        if !titles.isEmpty {
            Shelf("Reading Room", count: "\(titles.count.formatted()) titles") {
                ForEach(titles.prefix(Self.shelfLength)) { title in
                    RRTitleCard(title: title) { reading = title }
                }
                SeeAll("the Reading Room", height: ReadingMetrics.coverHeight) { model.section = .reading }
            }
            .accessibilityIdentifier("home-shelf-reading")
        }
    }

    // MARK: - Pics/Vids

    /// The first region's stream, as the room opens on. Until the reader has answered the adult
    /// material notice in the room, the shelf is one card that takes them there to read it: the
    /// pictures are not shown before the notice is.
    private var pnvRows: [PnvRow] {
        guard let region = model.pnv.regions.first else { return [] }
        return Array(model.pnv.feed(region).items.prefix(Self.shelfLength))
    }

    @ViewBuilder
    private var picsVidsRow: some View {
        let store = model.pnv
        if store.noticeVisible {
            Shelf("Pics/Vids", count: store.summary ?? "Born Digital Media") {
                SeeAll("Pics/Vids", line: "Born Digital Media. The room opens on a note about adult material.", height: 300) {
                    model.section = .picsvids
                }
            }
            .accessibilityIdentifier("home-shelf-picsvids")
        } else if !pnvRows.isEmpty {
            Shelf("Pics/Vids", count: store.summary ?? "Born Digital Media") {
                ForEach(pnvRows) { row in
                    Button { viewing = row } label: {
                        PnvPicture(urls: [PnvMedia.tile(row), PnvMedia.thumb(row)].compactMap { $0 }, aspect: row.aspect,
                                   height: 300, maxPixel: 640)
                            .kjCardArt()
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityLabel("\(row.isVideo ? "Video" : "Picture") from @\(store.accountHandle(for: row))")
                    .accessibilityIdentifier("home-pnv-\(row.media_key)")
                }
                SeeAll("Pics/Vids", height: 300) { model.section = .picsvids }
            }
            .accessibilityIdentifier("home-shelf-picsvids")
        }
    }

    // MARK: - Madrassa

    @ViewBuilder
    private var madrassaRow: some View {
        if let posts = model.madrassaPosts.value, !posts.isEmpty {
            Shelf("Madrassa", count: "Writings") {
                ForEach(posts.prefix(Self.shelfLength)) { item in
                    Button { post = item } label: {
                        PostCard(post: item, picture: TVMadrassa.picture(item.image, model: model))
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("home-post-\(item.handle)")
                }
                SeeAll("the Madrassa", height: 460) { model.section = .rooms }
            }
            .accessibilityIdentifier("home-shelf-madrassa")
        }
    }

    // MARK: - Bazaar

    @ViewBuilder
    private var bazaarRow: some View {
        if let items = model.bazaar.value, !items.isEmpty {
            Shelf("Bazaar", count: "\(items.count.formatted()) things") {
                ForEach(items.prefix(Self.shelfLength)) { item in
                    Button { product = item } label: { TVProductCard(item: item) }
                        .buttonStyle(HouseCardStyle())
                        .accessibilityIdentifier("home-product-\(item.product.h)")
                        .accessibilityLabel([Bazaar.priceLine(item.product), item.product.title].compactMap { $0 }.joined(separator: ", "))
                }
                SeeAll("the Bazaar", height: TVProductCard.side) { model.section = .rooms }
            }
            .accessibilityIdentifier("home-shelf-bazaar")
        }
    }

    // MARK: - Chat

    @ViewBuilder
    private var chatRow: some View {
        let rooms = model.chat.groups.flatMap(\.rooms)
        if !rooms.isEmpty {
            Shelf("Chat", count: "\(rooms.count) rooms") {
                ForEach(rooms.prefix(Self.shelfLength)) { room in
                    Button { model.section = .chat } label: {
                        CardPlate(width: ChannelCard.width, height: ChannelCard.height) {
                            VStack(alignment: .leading, spacing: 10) {
                                if let place = room.country ?? room.region { Kicker(place).lineLimit(1) }
                                Text(room.label).kjName().lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(HouseCardStyle())
                    .accessibilityIdentifier("home-chat-\(room.slug)")
                }
            }
            .accessibilityIdentifier("home-shelf-chat")
        }
    }
}

/// The last card on a Home shelf: the whole section, one press away.
private struct SeeAll: View {
    let place: String
    var line: String?
    let height: CGFloat
    let action: () -> Void

    init(_ place: String, line: String? = nil, height: CGFloat, action: @escaping () -> Void) {
        self.place = place
        self.line = line
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CardPlate(width: 360, height: height) {
                VStack(alignment: .leading, spacing: 12) {
                    Spacer(minLength: 0)
                    Text("All of \(place) \u{203A}").kjName().lineLimit(3)
                    if let line { Text(line).kjSmall(faint: true).lineLimit(4) }
                }
            }
        }
        .buttonStyle(HouseCardStyle())
        .accessibilityIdentifier("home-all-\(place)")
    }
}

/// Every part of Khajistan as a picture tile, the first shelf under the Receiver's front (owner,
/// 2026-10-29: "reading room, PixVids, rooms, chat as well on the home page of the apps so that
/// people can just move down and select it instead of going to the navigation"). The same tiles
/// and pictures as the Rooms door; a part this build leaves out (StoreBuild) has no tile.
struct HomeSections: View {
    private enum Door: String, CaseIterable, Identifiable {
        case reading, picsvids, screening, bazaar, madrassa, databases, chat
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var room: RoomsTVView.Room?

    private static let tileWidth: CGFloat = 280

    private var doors: [Door] {
        Door.allCases.filter { door in
            switch door {
            case .picsvids: return StoreBuild.includes(.picsvids)
            case .chat: return StoreBuild.includes(.chat)
            case .reading: return StoreBuild.includes(.reading)
            case .bazaar, .madrassa, .databases: return !StoreBuild.roomsAreScreeningOnly
            case .screening: return true
            }
        }
    }

    var body: some View {
        // One door left (the App Store build) is the top bar's own Screening Room: no shelf.
        if doors.count > 1 { shelf }
    }

    private var shelf: some View {
        Shelf("Khajistan", count: "Every part") {
            ForEach(doors) { door in
                Button { open(door) } label: {
                    RoomTile(picture: picture(door), title: title(door), line: line(door), figure: nil, width: Self.tileWidth)
                }
                .buttonStyle(HouseCardStyle())
                .accessibilityIdentifier("home-door-\(door.rawValue)")
            }
        }
        .accessibilityIdentifier("home-shelf-doors")
        .fullScreenCover(item: $room) { TVRoomScreen(room: $0) }
    }

    private func open(_ door: Door) {
        switch door {
        case .reading: model.section = .reading
        case .picsvids: model.section = .picsvids
        case .chat: model.section = .chat
        case .screening: room = .screening
        case .bazaar: room = .bazaar
        case .madrassa: room = .madrassa
        case .databases: room = .databases
        }
    }

    private func title(_ door: Door) -> String {
        switch door {
        case .reading: return "Reading Room"
        case .picsvids: return "Pics/Vids"
        case .chat: return "Chat"
        case .screening: return RoomsTVView.Room.screening.title
        case .bazaar: return RoomsTVView.Room.bazaar.title
        case .madrassa: return RoomsTVView.Room.madrassa.title
        case .databases: return RoomsTVView.Room.databases.title
        }
    }

    private func line(_ door: Door) -> String {
        switch door {
        case .reading: return "Periodicals, posters and books, page by page"
        case .picsvids: return "Born Digital Media"
        case .chat: return "The website's rooms, live"
        case .screening: return RoomsTVView.Room.screening.line
        case .bazaar: return RoomsTVView.Room.bazaar.line
        case .madrassa: return RoomsTVView.Room.madrassa.line
        case .databases: return RoomsTVView.Room.databases.line
        }
    }

    private func picture(_ door: Door) -> String {
        switch door {
        case .reading: return "RoomReading"
        case .picsvids: return "RoomPicsVids"
        case .chat: return "RoomChat"
        case .screening: return RoomsTVView.Room.screening.picture
        case .bazaar: return RoomsTVView.Room.bazaar.picture
        case .madrassa: return RoomsTVView.Room.madrassa.picture
        case .databases: return RoomsTVView.Room.databases.picture
        }
    }
}
