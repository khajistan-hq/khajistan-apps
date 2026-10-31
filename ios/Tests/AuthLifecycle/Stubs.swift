import Foundation

// Synthetic process-local persistence. No real Keychain reads/writes or network requests.
enum Keychain {
    static var values: [String: Data] = [:]
    static func read(_ account: String) -> Data? { values[account] }
    static func write(_ data: Data, account: String, shared: Bool = false) throws { values[account] = data }
    static func delete(_ account: String) { values[account] = nil }
}
@MainActor final class OfflineFilmAccountScope {
    static let shared = OfflineFilmAccountScope()
    func restore(_ account: String?) {}
    func change(to account: String?) {}
}
