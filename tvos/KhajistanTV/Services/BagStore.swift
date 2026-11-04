import Foundation
import Observation

/// One line of the bag: a variant the shop said could be bought, at the price it said then. The
/// price shown is a note; the shop's checkout prices the cart again and is the price paid.
struct BagLine: Codable, Identifiable, Hashable, Sendable {
    let variantID: String
    let handle: String
    let title: String
    /// The variant's options ("Large / Black"), or nil for a product with one variant.
    let option: String?
    let unitPrice: Double
    let currency: String
    var quantity: Int

    var id: String { variantID }
}

/// The Bazaar's bag on this device. Checkout is the shop's own: the lines become a Storefront cart,
/// and the shop's checkout page, on its own host, takes the address, the delivery and the payment.
/// Nothing here is a receipt: a checkout page opening says nothing about an order.
@MainActor @Observable
final class BagStore {
    private(set) var lines: [BagLine]
    private(set) var checkingOut = false

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "kj.bag"
    static let maxQuantity = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lines = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([BagLine].self, from: $0) } ?? []
    }

    var count: Int { lines.reduce(0) { $0 + $1.quantity } }

    /// The bag's note of a total, in one currency; nil when lines disagree on currency.
    var subtotal: (amount: Double, currency: String)? {
        guard let currency = lines.first?.currency, lines.allSatisfy({ $0.currency == currency }) else { return nil }
        return (lines.reduce(0) { $0 + $1.unitPrice * Double($1.quantity) }, currency)
    }

    /// Only a variant the shop answered as available is ever added.
    func add(_ variant: StorefrontVariant, handle: String, title: String, singleVariant: Bool) {
        guard variant.availableForSale, let price = variant.price.value else { return }
        if let index = lines.firstIndex(where: { $0.variantID == variant.id }) {
            lines[index].quantity = min(lines[index].quantity + 1, Self.maxQuantity)
        } else {
            lines.append(BagLine(variantID: variant.id, handle: handle, title: title,
                                 option: singleVariant ? nil : variant.title, unitPrice: price,
                                 currency: variant.price.currencyCode, quantity: 1))
        }
        save()
    }

    func setQuantity(_ line: BagLine, _ quantity: Int) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        if quantity <= 0 { lines.remove(at: index) } else { lines[index].quantity = min(quantity, Self.maxQuantity) }
        save()
    }

    func remove(_ line: BagLine) {
        lines.removeAll { $0.id == line.id }
        save()
    }

    func empty() {
        lines = []
        save()
    }

    /// A Storefront cart of these lines, and the shop's checkout URL for it. The shop's answer is
    /// final: a line it refuses comes back as its own message.
    func checkout(session: URLSession = .shared) async -> Result<URL, ShopStorefront.CheckoutError> {
        guard !lines.isEmpty, !checkingOut else { return .failure(.unreadable) }
        checkingOut = true
        defer { checkingOut = false }
        let request = ShopStorefront.cartCreateRequest(lines: lines.map { ($0.variantID, $0.quantity) })
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .failure(.unreadable) }
        return ShopStorefront.checkout(from: data)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(lines), forKey: Self.key)
    }
}
