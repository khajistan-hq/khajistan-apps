import Foundation
import Security

/// Persistent FPS blobs are opaque, device-bound DRM material, never clear content keys.
/// One atomic Keychain item holds the key plus its advisory access record. No Documents path,
/// iCloud sync, file sharing, backup, user-picked destination, or app-group access is used.
enum OfflineFilmKeys {
    struct Record: Codable {
        let grant: OfflineFilmGrant
        let keyIdentifier: String
        var owner: UUID
        var key: Data
        var firstPlayedAt: Date?
        var lastObservedAt: Date
    }

    private static let service = KJConfig.keychainService + ".offline-films.v1"

    private static func identity(_ entitlement: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: entitlement.uuidString]
    }

    static func read(_ entitlement: UUID) throws -> Record? {
        var query = identity(entitlement)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw OfflineFilmError.storage }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    static func write(_ record: Record) throws {
        guard !record.key.isEmpty, record.key.count <= 256 * 1024 else { throw OfflineFilmError.missingKey }
        let data = try JSONEncoder().encode(record)
        let query = identity(record.grant.entitlementID)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw OfflineFilmError.storage }
        var item = query.merging(attributes) { _, new in new }
        item[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw OfflineFilmError.storage }
    }

    static func delete(_ entitlement: UUID) throws {
        let status = SecItemDelete(identity(entitlement) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OfflineFilmError.storage }
    }

    static func purge() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OfflineFilmError.storage }
    }
}

/// Account-scoped generation prevents an old key request completing after logout or a switch,
/// including sign-out followed by signing back into the same account.
@MainActor
final class OfflineFilmAccountScope {
    static let shared = OfflineFilmAccountScope()
    private(set) var generation = UUID()
    private(set) var accountID: String?
    private(set) var usable = true
    private var stops: [UUID: () -> Void] = [:]
    private var owners = OfflineKeyOwners()

    func change(to account: String?) {
        // Every explicit sign-in is a new session, even with the same account identifier.
        generation = UUID()
        accountID = account
        let callbacks = Array(stops.values)
        stops.removeAll()
        owners = OfflineKeyOwners()
        callbacks.forEach { $0() }
        do { try OfflineFilmKeys.purge(); usable = true }
        catch { usable = false }
    }

    /// Restore a Keychain-authenticated account at launch without purging its device keys.
    func restore(_ account: String?) {
        guard accountID == nil, stops.isEmpty else { return }
        accountID = account
        if account == nil { do { try OfflineFilmKeys.purge() } catch { usable = false } }
    }

    func accepts(account: String, generation: UUID) -> Bool {
        usable && !account.isEmpty && account == accountID && generation == self.generation
    }

    func claim(entitlement: UUID, owner: UUID, stop: @escaping () -> Void) {
        let previous = owners.claim(entitlement: entitlement, owner: owner)
        if let previous { stops.removeValue(forKey: previous)?() }
        stops[owner] = stop
    }
    func owns(entitlement: UUID, owner: UUID) -> Bool { owners.owns(entitlement: entitlement, owner: owner) }
    func release(entitlement: UUID, owner: UUID) {
        owners.release(entitlement: entitlement, owner: owner)
        stops.removeValue(forKey: owner)
    }
}
