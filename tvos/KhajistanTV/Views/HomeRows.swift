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

    /// A shelf shows this many, then the card to the whole section.
    private static let shelfLength = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A section this build leaves out (StoreBuild: Pics/Vids, Chat, the Reading Room and
            // every room but the Screening Room in the App Store build) has no shelf on Home either.
            if StoreBuild.includes(.reading) { readingRow }
            if !StoreBuild.roomsAreScreeningOnly {
                madrassaRow
                bazaarRow
            }
            if StoreBuild.includes(.chat) { chatRow }
        }
        // The channel the app opens on comes first: the shelves load a moment after the front.
        // Keyed on the shelf revision: a Clear or a new password empties the shelf, and this reloads it.
        .task(id: model.reading.loadRevision) {
            try? await Task.sleep(for: .seconds(2))
            await model.transmission.loadSchedule()
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
