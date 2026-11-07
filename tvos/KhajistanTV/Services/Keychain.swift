import Foundation
import Security

/// Generic-password items under one service name. Values are small blobs the app owns:
/// the signed-in session and the preview password.
enum Keychain {
    struct Failure: Error, LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "The keychain refused the change (status \(status))."
        }
    }

    private static func identity(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KJConfig.keychainService,
            kSecAttrAccount as String: account
        ]
    }

    static func read(_ account: String) -> Data? {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess else { return nil }
        return found as? Data
    }

    /// The access group the app shares with its Top Shelf extension, from Info.plist
    /// (`$(AppIdentifierPrefix)com.khajistan.tv.shared`). Nil when the build left it unexpanded.
    static var sharedGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KJKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        return group
    }

    /// Replaces whatever is stored under the account. `shared` puts the item in the group the Top
    /// Shelf extension can read; a build signed without that entitlement (the simulator under
    /// CODE_SIGNING_ALLOWED=NO) keeps it in the app's own. An item already where it belongs is
    /// updated in place, in one call, so a failed write leaves the previous value. An item that is
    /// not there yet (new, or stored before the shared group existed) is deleted wherever it is
    /// and added in the right group, which is how the launch migration moves the preview password.
    static func write(_ data: Data, account: String, shared: Bool = false) throws {
        var query = identity(account)
        if shared, let group = sharedGroup { query[kSecAttrAccessGroup as String] = group }
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updated = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if updated == errSecSuccess { return }
        // A signed build whose profile lacks the shared group answers -34018 for the grouped query;
        // fall through so the add path below can keep the item in the app's own group.
        guard updated == errSecItemNotFound || (shared && updated == errSecMissingEntitlement) else {
            throw Failure(status: updated)
        }
        delete(account)
        var item = identity(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if shared, let group = sharedGroup {
            var grouped = item
            grouped[kSecAttrAccessGroup as String] = group
            if SecItemAdd(grouped as CFDictionary, nil) == errSecSuccess { return }
        }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete(_ account: String) {
        _ = SecItemDelete(identity(account) as CFDictionary)
    }
}
