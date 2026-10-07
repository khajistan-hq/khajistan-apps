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

    /// Replaces whatever is stored under the account: delete first, then add.
    static func write(_ data: Data, account: String) throws {
        delete(account)
        var item = identity(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete(_ account: String) {
        _ = SecItemDelete(identity(account) as CFDictionary)
    }
}
