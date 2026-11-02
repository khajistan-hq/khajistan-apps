import SwiftUI

/// The Bazaar on the TV: a showcase, laid out as Etsy lays a listing. Each shelf is a category; a
/// card is the object fitted whole on a soft plate with the price first; the object's page has
/// the price, the options the shop sells now and one Add to bag. The bag, as On's: a line per
/// item with a stepper, the summary and one Checkout, which is the shop's own page opened on the
/// phone from a code (owner, 2026-10-28: "Bag + QR checkout"). Nothing is paid on the remote.
struct TVBazaar: View {
    @Environment(AppModel.self) private var model
    @State private var showing: BazaarItem?
    @State private var showBag = false

    var body: some View {
        TVPage("Bazaar", line: "Prints, objects, apparel and stickers. Checkout is on your phone.") {
            Button { showBag = true } label: {
                Label(model.bag.count == 0 ? "Bag" : "Bag \u{00B7} \(model.bag.count)", systemImage: "bag").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .padding(.leading, -26)
            .accessibilityLabel(model.bag.count == 0 ? "Bag, empty" : "Bag, \(model.bag.count) item\(model.bag.count == 1 ? "" : "s")")
            .accessibilityIdentifier("tvbag")
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
        .fullScreenCover(isPresented: $showBag) { TVBagScreen() }
    }
}

/// An object on its soft plate, fitted whole, then the price and the name under it.
struct TVProductCard: View {
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
struct TVProductScreen: View {
    let item: BazaarItem
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var live: ShopStorefront.ProductAnswer?
    @State private var option: String?
    @State private var added = false
    @State private var showBag = false
    @FocusState private var addFocused: Bool

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
                    Text("Or buy it on your phone or computer at").kjSmall(faint: true)
                    Text("khajistan.com/products/\(item.product.h)").kjName(30).lineLimit(2).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
        .defaultFocus($addFocused, true)
        // In place over the object, not one more cover, so Menu closes only the top layer. (A third
        // cover once looped SwiftUI's layout in Day; the cause, `.preferredColorScheme`, is gone:
        // RootView sets the style on the window.)
        .disabled(showBag)
        .accessibilityHidden(showBag)
        .overlay { if showBag { TVBagScreen { showBag = false }.accessibilityAddTraits(.isModal) } }
        .onAppear { OpenedLately.record(.object, ref: item.product.h, title: item.product.title) }
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
                optionChips(product, chosen: chosen)
            }
            addRow(product, chosen: chosen)
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

    /// One Add to bag, the screen's solid action, for the option chosen; the bag beside it once
    /// something is in it.
    @ViewBuilder
    private func addRow(_ product: StorefrontProduct, chosen: StorefrontVariant?) -> some View {
        HStack(spacing: 24) {
            if let chosen, chosen.availableForSale {
                Button {
                    model.bag.add(chosen, handle: item.product.h, title: item.product.title, singleVariant: product.variants.count == 1)
                    added = true
                } label: {
                    Label("Add to bag", systemImage: "bag.badge.plus").kjKicker()
                }
                .buttonStyle(HouseButtonStyle(solid: true))
                .focused($addFocused)
                .accessibilityIdentifier("tvaddToBag")
            } else {
                backStop
            }
            if model.bag.count > 0 {
                Button { showBag = true } label: { Label("Bag \u{00B7} \(model.bag.count)", systemImage: "bag").kjKicker() }
                    .buttonStyle(HouseButtonStyle())
                    .accessibilityIdentifier("tvobjectBag")
            }
        }
        .focusSection()
        if added { Text("In the bag.").kjSmall(faint: true).accessibilityIdentifier("tvadded") }
    }

    private func optionChips(_ product: StorefrontProduct, chosen: StorefrontVariant?) -> some View {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(product.variants) { variant in
                            Button { option = variant.id; added = false } label: {
                                Text(variant.title + (variant.availableForSale ? "" : " \u{00B7} sold out")).kjKicker().lineLimit(1)
                            }
                            .buttonStyle(HouseTabStyle(isCurrent: variant.id == chosen?.id))
                            .accessibilityIdentifier("tvoption-\(variant.title)")
                        }
                    }
                }
                .focusSection()
    }

    /// A focus target where there are no options, so Menu and the remote have somewhere to land.
    private var backStop: some View {
        Button { } label: { Text("Back with Menu").kjKicker() }
            .buttonStyle(HouseButtonStyle())
    }
}

/// The bag, as On lays its own: a line per item with a stepper (− count +), the summary, and one
/// Checkout. Checkout asks the shop for a cart of these lines and shows its checkout page as a
/// code for the phone, where the address, the delivery and the payment are taken. The price here
/// is a note; the shop's checkout prices the cart again.
struct TVBagScreen: View {
    /// Set where the bag is drawn in place over another screen: Menu calls it. A bag in a cover
    /// of its own leaves Menu to the cover.
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var problem: String?
    @State private var checkout: CheckoutPage?

    /// The shop's checkout page for this bag, shown as a code.
    private struct CheckoutPage: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @FocusState private var checkoutFocused: Bool

    var body: some View {
        let bag = model.bag
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bag").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                        if !bag.lines.isEmpty { Text("\(bag.count) item\(bag.count == 1 ? "" : "s")").kjBody() }
                    }
                    if bag.lines.isEmpty {
                        Text("Nothing in the bag.").kjBody().accessibilityIdentifier("tvbagEmpty")
                        Button { if let close { close() } else { dismiss() } } label: { Text("Back").kjKicker() }
                            .buttonStyle(HouseButtonStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(bag.lines) { line in
                                row(line)
                                Hairline()
                            }
                        }
                        .frame(maxWidth: 1300, alignment: .leading)
                        // The summary and Checkout as one section the width of the lines, so Down from
                        // a stepper at the right lands on Checkout at the left.
                        VStack(alignment: .leading, spacing: 24) {
                            summary
                            Button { Task { await startCheckout() } } label: {
                                Label(bag.checkingOut ? "Opening checkout\u{2026}" : "Checkout", systemImage: "lock.fill").kjKicker()
                            }
                            .buttonStyle(HouseButtonStyle(solid: true))
                            .disabled(bag.checkingOut)
                            .focused($checkoutFocused)
                            .accessibilityIdentifier("tvbagCheckout")
                            if let problem { Text(problem).kjBody().accessibilityIdentifier("tvbagProblem") }
                        }
                        .frame(maxWidth: 1300, alignment: .leading)
                        .focusSection()
                    }
                }
                .padding(KJLayout.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(palette.ink)
        .defaultFocus($checkoutFocused, true)
        .modifier(MenuCloses(close: close))
        // In place over the bag, as the film page's Website: never one more cover.
        .disabled(checkout != nil)
        .accessibilityHidden(checkout != nil)
        .overlay {
            if let page = checkout {
                TVOnYourPhone(title: "Checkout", url: page.url,
                              line: "Point your phone's camera at the code to pay on khajistan.com. Nothing is paid on the TV.") { checkout = nil }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subtotal = model.bag.subtotal {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text("Subtotal").kjKicker(palette.faint).frame(width: 300, alignment: .leading)
                    Text(Bazaar.priceText(subtotal.amount, currency: subtotal.currency)).kjName(34).monospacedDigit()
                        .accessibilityIdentifier("tvbagSubtotal")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("Delivery and taxes").kjKicker(palette.faint).frame(width: 300, alignment: .leading)
                Text("At checkout").kjBody()
            }
            Text("The shop sets delivery, taxes and the total at checkout, on khajistan.com.").kjSmall(faint: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// A line: the object, its option and unit price, then − count + as one row of focus stops.
    private func row(_ line: BagLine) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title).kjName(30).lineLimit(2)
                if let option = line.option { Text(option).kjSmall(faint: true) }
                Text(Bazaar.priceText(line.unitPrice, currency: line.currency)).kjSmall()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.bag.setQuantity(line, line.quantity - 1) } label: {
                Image(systemName: line.quantity == 1 ? "trash" : "minus").font(.system(size: 30, weight: .bold)).frame(width: 44)
            }
            .buttonStyle(HouseButtonStyle())
            .accessibilityLabel(line.quantity == 1 ? "Remove \(line.title)" : "One fewer \(line.title)")
            .accessibilityIdentifier("tvbagFewer-\(line.handle)")
            Text("\(line.quantity)").kjName(34).monospacedDigit().frame(minWidth: 50)
                .accessibilityLabel("\(line.quantity) in the bag")
                .accessibilityIdentifier("tvbagCount-\(line.handle)")
            Button { model.bag.setQuantity(line, line.quantity + 1) } label: {
                Image(systemName: "plus").font(.system(size: 30, weight: .bold)).frame(width: 44)
            }
            .buttonStyle(HouseButtonStyle())
            .disabled(line.quantity >= BagStore.maxQuantity)
            .accessibilityLabel("One more \(line.title)")
            .accessibilityIdentifier("tvbagMore-\(line.handle)")
        }
        .padding(.vertical, 12)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tvbagLine-\(line.handle)")
    }

    private func startCheckout() async {
        problem = nil
        switch await model.bag.checkout() {
        case .success(let url): checkout = CheckoutPage(url: url)
        case .failure(.refused(let message)): problem = "The shop said: \(message)"
        case .failure(.unreadable): problem = "The shop did not answer. Nothing was charged. Try again in a moment."
        }
    }
}


/// Menu calls `close` where there is one, and is left to the presentation otherwise.
private struct MenuCloses: ViewModifier {
    let close: (() -> Void)?

    func body(content: Content) -> some View {
        if let close { content.onExitCommand(perform: close) } else { content }
    }
}
