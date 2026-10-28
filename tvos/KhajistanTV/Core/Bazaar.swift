import Foundation

// The Bazaar: data/catalog.json, read as bazaar.html and scripts/kj-typetag.js read it (fromCatalog,
// kjCatalogMerchCategory, kjRetiredShelf, kjMerchShelf, printKind, kjPriceGate). The catalogue says
// what is on the shelf; the live product (variants, stock, price) is always asked of the shop's
// Storefront API, and the cart and checkout are the shop's own.

/// One record of catalog.json, under its short keys (catalog.json `_meta.fields`).
struct BazaarProduct: Decodable, Identifiable, Hashable, Sendable {
    /// Shopify handle.
    let h: String
    /// Title.
    let t: String?
    /// Image URL.
    let i: String?
    /// Featured price and currency.
    let p: Double?
    let c: String?
    /// Shopify productType.
    let pt: String?
    /// Region and language, as the store files them.
    let r: String?
    let l: String?
    let tags: [String]?
    /// Cheapest in-stock physical price, and digital price.
    let pp: Double?
    let pd: Double?
    /// 1 when nothing is in stock; 1 for an original holding (not sold on the Bazaar).
    let so: Int?
    let o: Int?

    var id: String { h }
    var title: String { t ?? h }
}

struct BazaarCatalogue: Decodable, Sendable {
    let products: [BazaarProduct]
}

/// A product the Bazaar sells, and the shelf it stands on.
struct BazaarItem: Identifiable, Hashable, Sendable {
    let product: BazaarProduct
    let shelf: BazaarShelf
    var id: String { product.h }
}

enum BazaarShelf: String, CaseIterable, Sendable {
    case prints, apparel, objects, stickers

    var title: String {
        switch self {
        case .prints: return "Prints"
        case .apparel: return "Apparel"
        case .objects: return "Objects"
        case .stickers: return "Stickers"
        }
    }
}

enum Bazaar {
    static let cataloguePath = "data/catalog.json"

    /// MERCH_TYPES in kj-typetag.js: the productTypes the Bazaar sells, and their shelf. Printed
    /// matter, patches, canvas prints, ephemera and downloads are deliberately absent.
    static let merchTypes: [String: BazaarShelf] = [
        "Stickers": .stickers,
        "Matte Print": .prints, "Poster": .prints, "All Over Prints": .prints,
        "T-Shirt": .apparel, "Sweatshirt": .apparel, "Sweatshirts": .apparel, "Hoodie": .apparel, "Tank Top": .apparel,
        "Hats": .apparel, "Hat": .apparel, "Bags": .apparel, "Apparel & Accessories": .apparel, "Shirt and Tops": .apparel,
        "Home Decor": .objects, "Accessories": .objects, "Paper products": .objects, "Wall Decal": .objects,
        "Lunch Box": .objects, "Shower Curtain": .objects, "Silk Cushions": .objects, "Rugs": .objects,
        "Stationery": .objects, "Journals": .objects,
    ]

    /// RETIRED_PT and RETIRED_TITLE: patches and canvas prints are off the Bazaar (owner 2026-08-04).
    static let retiredTypes: Set<String> = ["patch", "canvas print"]
    static let retiredTitles = [#"\bcanvas\s+print\b"#, #"\bembroidered\s+patch(es)?\b"#, #"\biron-?on\b[\s\S]*\bpatch(es)?\b"#]

    /// Above this a price is not shown (kj-pricegate.js, owner rule).
    static let priceOnRequestAbove: Double = 2800

    static func isRetired(type: String?, title: String?) -> Bool {
        let type = (type ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if retiredTypes.contains(type) { return true }
        let title = title ?? ""
        return retiredTitles.contains { title.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// printKind(): the material a title states, even where productType is generic.
    static func printKind(type: String?, title: String?) -> String? {
        let type = (type ?? "").lowercased()
        let title = (title ?? "").lowercased()
        func has(_ pattern: String) -> Bool { title.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\bmetal\b"#) {
            if has(#"metal\s*sign"#) { return "Metal Sign" }
            if has(#"metal\s*art"#) { return "Metal Art" }
            return "Metal Panel"
        }
        if has(#"\bframed\b"#) { return "Framed" }
        if type.contains("canvas") || has(#"\bcanvas\b"#) { return "Canvas Print" }
        if type.contains("matte") || has(#"\bmatte print\b"#) { return "Matte Print" }
        if type.contains("poster") || has(#"\bposter\b"#) { return "Poster" }
        if type.contains("wall decal") || has(#"\bwall decal\b"#) { return "Wall Decal" }
        if type.contains("print") || has(#"\bprint\b"#) { return "Print" }
        return nil
    }

    /// kjMerchShelf(): only what productType called an object is reshelved, a sticker by its
    /// `type:sticker` tag or title, a paper print by the material its title states.
    static func merchShelf(_ shelf: BazaarShelf, _ product: BazaarProduct) -> BazaarShelf {
        guard shelf == .objects else { return shelf }
        if (product.tags ?? []).contains(where: { $0.lowercased() == "type:sticker" }) { return .stickers }
        if (product.t ?? "").range(of: #"\bsticker(s)?\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return .stickers }
        let paper: Set<String> = ["Matte Print", "Poster", "Print", "Framed"]
        if let kind = printKind(type: product.pt, title: product.t), paper.contains(kind) { return .prints }
        return .objects
    }

    /// kjCatalogMerchCategory() plus fromCatalog()'s image test (`p.i` present): the shelf a record stands on, or
    /// nil when the Bazaar does not sell it.
    static func shelf(_ product: BazaarProduct) -> BazaarShelf? {
        // fromCatalog() keeps any record with an image value; one that fails the image allowlist
        // stands on the shelf with no picture rather than leaving it.
        guard let image = product.i, !image.isEmpty else { return nil }
        guard product.o != 1, let type = product.pt, let shelf = merchTypes[type],
              !isRetired(type: product.pt, title: product.t) else { return nil }
        if product.pd != nil && product.pp == nil { return nil }
        return merchShelf(shelf, product)
    }

    static func offered(_ products: [BazaarProduct]) -> [BazaarItem] {
        products.compactMap { product in shelf(product).map { BazaarItem(product: product, shelf: $0) } }
    }

    /// The price line a card shows: sold out, a price, or "Price on request" above the gate.
    static func priceLine(_ product: BazaarProduct) -> String? {
        if product.so == 1 { return "Sold out" }
        guard let price = product.pp ?? product.p else { return nil }
        return priceText(price, currency: product.c)
    }

    static func priceText(_ amount: Double, currency: String?) -> String {
        guard amount <= priceOnRequestAbove else { return "Price on request" }
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency ?? "USD", locale: Locale(identifier: "en_US"))
        return amount.formatted(style.precision(.fractionLength(amount == amount.rounded() ? 0 : 2)))
    }

    static let swapPath = "data/transparent-images.json"

    /// fileKey() in bazaar.html: the URL's last path component, lower-cased, without query.
    static func fileKey(_ url: String) -> String {
        (url.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? url)
            .split(separator: "/").last.map { $0.lowercased() } ?? ""
    }

    /// transparent-images.json keyed as the page keys it, so a white-background mockup is shown
    /// as the clean local scan the site shows instead.
    static func swapMap(_ data: Data) throws -> [String: String] {
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        return Dictionary(raw.map { (fileKey($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The picture a card shows: the swap if there is one, else the record's own image.
    static func picture(_ product: BazaarProduct, swap: [String: String], width: Int) -> URL? {
        guard let raw = product.i else { return nil }
        return imageURL(swap[fileKey(raw)] ?? raw, width: width)
    }

    /// bazaar.html's image allowlist: the site's own product assets and Shopify's CDN, nothing
    /// else. A Shopify image is asked for at a width.
    static func imageURL(_ raw: String, width: Int? = nil, origin: URL = KJConfig.site) -> URL? {
        let raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.range(of: #"^assets/products/[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil {
            return URL(string: raw, relativeTo: origin)?.absoluteURL
        }
        guard var parts = URLComponents(string: raw), parts.scheme == "https", parts.host == "cdn.shopify.com",
              parts.path.hasPrefix("/s/files/") else { return nil }
        if let width {
            var items = (parts.queryItems ?? []).filter { $0.name != "width" }
            items.append(URLQueryItem(name: "width", value: String(width)))
            parts.queryItems = items
        }
        return parts.url
    }
}

// MARK: - The shop's Storefront API

/// A variant as the Storefront API answers for it: its id, its options' title, whether it can be
/// bought now, and its price.
struct StorefrontVariant: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let availableForSale: Bool
    let price: StorefrontMoney
}

struct StorefrontMoney: Decodable, Hashable, Sendable {
    let amount: String
    let currencyCode: String
    var value: Double? { Double(amount) }
}

struct StorefrontProduct: Decodable, Hashable, Sendable {
    let title: String
    let descriptionHtml: String?
    let images: [URL]
    let variants: [StorefrontVariant]
}

enum ShopStorefront {
    static let endpoint = URL(string: "https://\(KJConfig.storefrontDomain)/api/2024-07/graphql.json")!
    /// The hosts a checkout may live on (khaji-cart.js): the shop's own.
    static let checkoutHosts: Set<String> = [KJConfig.storefrontDomain, "khajistan.com", "www.khajistan.com", "checkout.shopify.com"]

    static func request(query: String, variables: [String: Any]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.storefrontToken, forHTTPHeaderField: "X-Shopify-Storefront-Access-Token")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return request
    }

    /// product.html's query: the product's variants, prices and stock, live.
    static func productRequest(handle: String) -> URLRequest {
        request(query: """
        query($h:String!){product(handle:$h){title descriptionHtml images(first:12){nodes{url}}\
         variants(first:50){nodes{id title availableForSale price{amount currencyCode}}}}}
        """, variables: ["h": handle])
    }

    /// The shop's answer for a handle: the product, or that the shop does not sell it online now
    /// (a record the catalogue lists but the shop's channel does not publish), or an unreadable reply.
    enum ProductAnswer: Equatable {
        case found(StorefrontProduct)
        case notForSale
        case unreadable
    }

    static func productAnswer(from data: Data) -> ProductAnswer {
        if let product = product(from: data) { return .found(product) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let box = root["data"] as? [String: Any], box.keys.contains("product"), box["product"] is NSNull else { return .unreadable }
        return .notForSale
    }

    static func product(from data: Data) -> StorefrontProduct? {
        struct Reply: Decodable {
            struct DataBox: Decodable { let product: Raw? }
            struct Raw: Decodable {
                struct Images: Decodable { struct Node: Decodable { let url: URL }; let nodes: [Node] }
                struct Variants: Decodable { let nodes: [StorefrontVariant] }
                let title: String
                let descriptionHtml: String?
                let images: Images
                let variants: Variants
            }
            let data: DataBox?
        }
        guard let raw = (try? JSONDecoder().decode(Reply.self, from: data))?.data?.product else { return nil }
        return StorefrontProduct(title: raw.title, descriptionHtml: raw.descriptionHtml,
                                 images: raw.images.nodes.map(\.url), variants: raw.variants.nodes)
    }

    /// khaji-cart.js cartCreate: a cart of these lines, and the shop's checkout for it.
    static func cartCreateRequest(lines: [(variantID: String, quantity: Int)]) -> URLRequest {
        request(query: "mutation($l:[CartLineInput!]){cartCreate(input:{lines:$l}){cart{checkoutUrl}userErrors{message}}}",
                variables: ["l": lines.map { ["merchandiseId": $0.variantID, "quantity": $0.quantity] }])
    }

    /// The checkout URL the shop answered, accepted only on the shop's own hosts, with Shop Pay's
    /// sign-in skipped as the site does. A user error is returned as its message.
    static func checkout(from data: Data) -> Result<URL, CheckoutError> {
        struct Reply: Decodable {
            struct DataBox: Decodable { let cartCreate: Create? }
            struct Create: Decodable {
                struct Cart: Decodable { let checkoutUrl: String }
                struct UserError: Decodable { let message: String }
                let cart: Cart?
                let userErrors: [UserError]
            }
            let data: DataBox?
        }
        guard let create = (try? JSONDecoder().decode(Reply.self, from: data))?.data?.cartCreate else { return .failure(.unreadable) }
        if let first = create.userErrors.first { return .failure(.refused(first.message)) }
        guard let text = create.cart?.checkoutUrl, let url = safeCheckout(text) else { return .failure(.unreadable) }
        return .success(url)
    }

    static func safeCheckout(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text), parts.scheme == "https",
              let host = parts.host?.lowercased(), checkoutHosts.contains(host), parts.user == nil, parts.password == nil else { return nil }
        var items = (parts.queryItems ?? []).filter { $0.name != "skip_shop_pay" }
        items.append(URLQueryItem(name: "skip_shop_pay", value: "true"))
        parts.queryItems = items
        return parts.url
    }

    enum CheckoutError: Error, Equatable {
        case unreadable
        case refused(String)
    }
}
