import SwiftUI

/// The Bazaar: the shelves bazaar.html draws from data/catalog.json (Core/Bazaar.swift, held to the
/// site's own kj-typetag.js by a core test). A product opens on its live record from the shop
/// (variants, stock, price); a bag on this device goes to the shop's own checkout.
struct BazaarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var shelf: BazaarShelf?
    @State private var query = ""

    private var feed: SiteFeed<[BazaarItem]> { model.bazaar }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    PageHead("Bazaar", line: "Prints, objects, apparel and stickers")
                    BagLink()
                }
                switch feed.state {
                case .idle, .loading:
                    TuningLoader("Loading the Bazaar\u{2026}").frame(maxWidth: .infinity).padding(.top, 40)
                case .locked:
                    LockedNote(subject: "The Bazaar's catalogue")
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await feed.load(force: true) } }
                case .ready:
                    filters
                    grid
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: model.auth.previewPassword) {
            await feed.load()
            await model.bazaarSwap.load()
        }
    }

    private var items: [BazaarItem] { feed.value ?? [] }

    private var shown: [BazaarItem] {
        let needle = DBQuery.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return items.filter { item in
            (shelf == nil || item.shelf == shelf)
                && (needle.isEmpty || DBQuery.fold(item.product.title).contains(needle)
                    || DBQuery.fold(item.product.r ?? "").contains(needle))
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HouseInputField("Find in the Bazaar") {
                TextField("", text: $query, prompt: Text("Title or region").foregroundStyle(palette.faint))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("bazaarSearch")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    chip("All", nil)
                    // The shelves the catalogue fills, in the page's order (CAT_LABELS).
                    ForEach([BazaarShelf.apparel, .prints, .stickers, .objects].filter { s in items.contains { $0.shelf == s } }, id: \.self) {
                        chip($0.title, $0)
                    }
                }
            }
            .padding(.horizontal, -12)
            Text("\(shown.count.formatted()) of \(items.count.formatted())").kjSmall(faint: true)
                .accessibilityIdentifier("bazaarCount")
        }
    }

    private func chip(_ title: String, _ value: BazaarShelf?) -> some View {
        Button { shelf = value } label: { Text(title).kjKicker() }
            .buttonStyle(HouseTabStyle(isCurrent: shelf == value))
            .accessibilityIdentifier("bazaarShelf-\(value?.rawValue ?? "all")")
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 180 : 150), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 22) {
            ForEach(shown) { item in
                NavigationLink(value: RoomRoute.product(item.product.h)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProductPicture(url: Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 400))
                        Text(item.product.title).kjName().lineLimit(3).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let price = Bazaar.priceLine(item.product) { Text(price).kjSmall() }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("product-\(item.product.h)")
            }
        }
    }
}

/// A product picture at its own shape, square plate held while it loads, never cropped.
struct ProductPicture: View {
    let url: URL?
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
            }
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url else { return }
                image = await PnvImages.shared.image([url], maxPixel: 800, authorization: model.siteAuthorization(for: url))
            }
    }
}

/// "Bag · 2", where the bag holds anything.
private struct BagLink: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.bag.count > 0 {
            NavigationLink(value: RoomRoute.bag) {
                Text("Bag \u{00B7} \(model.bag.count)").kjKicker()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bagLink")
        }
    }
}

// MARK: - One product

struct ProductScreen: View {
    let handle: String

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL
    @State private var live: StorefrontProduct?
    @State private var failed = false
    @State private var notForSale = false
    @State private var chosen: String?
    @State private var note: String?

    private var item: BazaarItem? { model.bazaar.value?.first { $0.product.h == handle } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let wide = sizeClass == .regular
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                layout {
                    ProductPicture(url: picture).frame(maxWidth: wide ? 420 : .infinity)
                    details
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await load() }
    }

    private var picture: URL? {
        if let item { return Bazaar.picture(item.product, swap: model.bazaarSwap.value ?? [:], width: 800) }
        return live?.images.first
    }

    private var variants: [StorefrontVariant] { live?.variants ?? [] }
    private var selected: StorefrontVariant? {
        variants.first { $0.id == chosen } ?? (variants.count == 1 ? variants.first : nil)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Kicker(item?.shelf.title ?? "Bazaar"); Spacer(); BagLink() }
            Text(live?.title ?? item?.product.title ?? "").kjDisplay(KJType.headline, tracking: -0.05).accessibilityAddTraits(.isHeader)
            if let region = item?.product.r, !region.isEmpty { Text(region).kjSmall(faint: true) }
            if notForSale {
                Text("Not for sale online now.").kjName().accessibilityIdentifier("productNotForSale")
            } else if live == nil && !failed {
                Kicker("Asking the shop\u{2026}")
            } else if failed {
                Text("The shop did not answer, so nothing can be added now.").kjBody().accessibilityIdentifier("productFailed")
                Button(kicker: "Try again") { Task { await load() } }
            } else if let note, variants.isEmpty {
                Text(note).kjName().accessibilityIdentifier("productOnRequest")
            } else if variants.isEmpty || !variants.contains(where: \.availableForSale) {
                Text("Sold out").kjName().accessibilityIdentifier("productSoldOut")
            } else {
                if variants.count > 1 { variantPicker }
                price
                Button(kicker: "Add to bag") {
                    guard let selected, let live else { return }
                    model.bag.add(selected, handle: handle, title: live.title, singleVariant: variants.count == 1)
                    note = "In your bag."
                }
                .buttonStyle(HouseButtonStyle(solid: true))
                .disabled(selected?.availableForSale != true)
                .accessibilityIdentifier("addToBag")
                if let note { Text(note).kjSmall(faint: true).accessibilityIdentifier("bagNote") }
            }
            if let body = live?.descriptionHtml, !body.isEmpty {
                Text(ArticleHTML.text(body)).kjBody().fixedSize(horizontal: false, vertical: true)
            }
            Button(kicker: "On khajistan.com \u{2197}") {
                if let url = URL(string: "https://khajistan.com/products/\(KJURL.encodeQueryValue(handle))") { openURL(url) }
            }
            .accessibilityIdentifier("productOnShop")
        }
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker("Choose")
            FlowRow(spacing: 0) {
                ForEach(variants) { variant in
                    Button { chosen = variant.id } label: {
                        Text(variant.title).kjKicker().strikethrough(!variant.availableForSale)
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: selected?.id == variant.id))
                    .disabled(!variant.availableForSale)
                    .accessibilityLabel(variant.availableForSale ? variant.title : "\(variant.title), sold out")
                    .accessibilityIdentifier("variant-\(variant.title)")
                }
            }
            .padding(.horizontal, -12)
        }
    }

    @ViewBuilder
    private var price: some View {
        if let selected, let amount = selected.price.value {
            Text(Bazaar.priceText(amount, currency: selected.price.currencyCode)).kjStat().accessibilityIdentifier("productPrice")
        } else {
            Text("Choose an option to see its price.").kjSmall(faint: true)
        }
    }

    private func load() async {
        failed = false
        var request = ShopStorefront.productRequest(handle: handle)
        request.timeoutInterval = 25
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            failed = true
            return
        }
        let product: StorefrontProduct
        switch ShopStorefront.productAnswer(from: data) {
        case .found(let found): product = found
        case .notForSale: notForSale = true; return
        case .unreadable: failed = true; return
        }
        // Over the gate, a price is never shown or sold here: the record says Price on request.
        if let highest = product.variants.compactMap(\.price.value).max(), highest > Bazaar.priceOnRequestAbove {
            live = StorefrontProduct(title: product.title, descriptionHtml: product.descriptionHtml, images: product.images, variants: [])
            note = "Price on request"
        } else {
            live = product
        }
    }
}

// MARK: - The bag

struct BagScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHead(kicker: "Bazaar", "Your bag", line: nil)
                if model.bag.lines.isEmpty {
                    Text("Nothing in the bag.").kjBody().accessibilityIdentifier("bagEmpty")
                } else {
                    ForEach(model.bag.lines) { line in row(line) }
                    HouseRule()
                    if let subtotal = model.bag.subtotal {
                        Text("Subtotal \(Bazaar.priceText(subtotal.amount, currency: subtotal.currency))").kjName()
                            .accessibilityIdentifier("bagSubtotal")
                    }
                    Text("Delivery, taxes and the total are set by the shop at checkout, on khajistan.com.").kjSmall(faint: true)
                    Button(kicker: model.bag.checkingOut ? "Opening checkout\u{2026}" : "Checkout on khajistan.com \u{2197}") {
                        Task { await checkout() }
                    }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .disabled(model.bag.checkingOut)
                    .accessibilityIdentifier("bagCheckout")
                    if let problem { Text(problem).kjBody().accessibilityIdentifier("bagProblem") }
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .kjColumn()
        }
    }

    private func row(_ line: BagLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.title).kjName()
                if let option = line.option { Text(option).kjSmall(faint: true) }
                Text(Bazaar.priceText(line.unitPrice, currency: line.currency)).kjSmall()
            }
            Spacer()
            Button(kicker: "\u{2212}") { model.bag.setQuantity(line, line.quantity - 1) }
                .accessibilityLabel("One fewer \(line.title)")
            Text("\(line.quantity)").kjName().monospacedDigit().accessibilityLabel("\(line.quantity) in the bag")
            Button(kicker: "+") { model.bag.setQuantity(line, line.quantity + 1) }
                .disabled(line.quantity >= BagStore.maxQuantity)
                .accessibilityLabel("One more \(line.title)")
        }
        .accessibilityIdentifier("bagLine-\(line.handle)")
    }

    private func checkout() async {
        problem = nil
        switch await model.bag.checkout() {
        case .success(let url): openURL(url)
        case .failure(.refused(let message)): problem = "The shop said: \(message)"
        case .failure(.unreadable): problem = "The shop did not answer. Nothing was charged. Try again in a moment."
        }
    }
}

/// Buttons laid out in rows that wrap.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x)
        }
        return (CGSize(width: widest, height: y + line), points)
    }
}
