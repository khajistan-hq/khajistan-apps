import SwiftUI

/// The Bazaar on the TV: a showcase, laid out as Etsy lays a listing. Each shelf is a category; a
/// card is the object fitted whole on a soft plate with the price first; the object's page has
/// the price, the options the shop sells now, and the address where it is bought. No bag and no
/// checkout on the remote (DECISIONS 12).
struct TVBazaar: View {
    @Environment(AppModel.self) private var model
    @State private var showing: BazaarItem?

    var body: some View {
        TVPage("Bazaar", line: "Prints, objects, apparel and stickers. Buying is on khajistan.com.") {
            if let items = model.bazaar.value {
                ForEach([BazaarShelf.apparel, .prints, .stickers, .objects], id: \.self) { shelf in
                    let row = items.filter { $0.shelf == shelf }
                    if !row.isEmpty {
                        Shelf(shelf.title, count: row.count.formatted()) {
                            ForEach(row) { item in
                                Button { showing = item } label: { TVProductCard(item: item) }
                                    .buttonStyle(HouseCardStyle())
                                    .accessibilityIdentifier("tvproduct-\(item.product.h)")
                                    .accessibilityLabel([Bazaar.priceLine(item.product), item.product.title].compactMap { $0 }.joined(separator: ", "))
                            }
                        }
                    }
                }
            } else {
                TVFeedNote(feed: model.bazaar, subject: "The Bazaar's catalogue")
            }
        }
        .task(id: model.auth.previewPassword) {
            await model.bazaar.load()
            await model.bazaarSwap.load()
        }
        .fullScreenCover(item: $showing) { item in TVProductScreen(item: item) }
    }
}

/// An object on its soft plate, fitted whole, then the price and the name under it.
private struct TVProductCard: View {
    static let side: CGFloat = 340

    let item: BazaarItem
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                palette.lift
                if let url = Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 400) {
                    TVPicture(url: url, maxPixel: 640).padding(24)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .kjCardArt()
            VStack(alignment: .leading, spacing: 4) {
                Text(Bazaar.priceLine(item.product) ?? " ").kjName(30)
                Text(item.product.title).kjSmall().lineLimit(2)
            }
            .frame(width: Self.side, height: 100, alignment: .topLeading)
        }
    }
}

/// A product, with what the shop answers about it now, and where to buy it. No form on the TV.
private struct TVProductScreen: View {
    let item: BazaarItem
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var live: ShopStorefront.ProductAnswer?
    @State private var option: String?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                ZStack {
                    palette.lift
                    if let url = Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 800) {
                        TVPicture(url: url, maxPixel: 1200).padding(40)
                    }
                }
                .frame(width: 760, height: 760)
                VStack(alignment: .leading, spacing: 20) {
                    Kicker(item.shelf.title)
                    shop
                    Text(item.product.title).kjName(48).lineLimit(3).accessibilityAddTraits(.isHeader)
                    if case .found(let product) = live, let text = product.descriptionHtml.map(ArticleHTML.text), !text.isEmpty {
                        Text(text).kjBody().lineLimit(4)
                    }
                    Spacer().frame(height: 12)
                    Text("Buy it on your phone or computer at").kjSmall(faint: true)
                    Text("khajistan.com/products/\(item.product.h)").kjName(30).lineLimit(2).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
        .task {
            if let (data, response) = try? await URLSession.shared.data(for: ShopStorefront.productRequest(handle: item.product.h)),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                live = ShopStorefront.productAnswer(from: data)
            } else {
                live = .unreadable
            }
        }
    }

    /// The price first, as Etsy sets it, then the options as chips; the chosen one's price shows.
    /// The shop's live answer, not the catalogue's note of it.
    @ViewBuilder
    private var shop: some View {
        switch live {
        case .found(let product):
            let chosen = product.variants.first { $0.id == option } ?? product.variants.first { $0.availableForSale }
            if let chosen, chosen.availableForSale, let amount = chosen.price.value {
                Text(Bazaar.priceText(amount, currency: chosen.price.currencyCode)).kjStat()
            } else {
                Text("Sold out").kjStat()
            }
            if product.variants.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(product.variants) { variant in
                            Button { option = variant.id } label: {
                                Text(variant.title + (variant.availableForSale ? "" : " \u{00B7} sold out")).kjKicker().lineLimit(1)
                            }
                            .buttonStyle(HouseTabStyle(isCurrent: variant.id == chosen?.id))
                            .accessibilityIdentifier("tvoption-\(variant.title)")
                        }
                    }
                }
                .focusSection()
            } else {
                backStop
            }
        case .notForSale:
            Text("Not for sale online now.").kjBody()
            backStop
        case .unreadable:
            Text("The shop did not answer.").kjBody()
            backStop
        case nil:
            Kicker("Asking the shop\u{2026}")
        }
    }

    /// A focus target where there are no options, so Menu and the remote have somewhere to land.
    private var backStop: some View {
        Button { } label: { Text("Back with Menu").kjKicker() }
            .buttonStyle(HouseButtonStyle())
    }
}
