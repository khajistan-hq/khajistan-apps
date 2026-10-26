import Foundation
import Security

/// Generic-password items under one service name. Values are small blobs the app owns:
/// the signed-in session and the preview password.
///
/// The phone and the Apple TV compile this one file. The phone has no keychain-access-groups
/// entitlement and no `KJKeychainGroup`, so its queries omit the access group: that is where
/// every item already on a phone was stored. The Apple TV preview password is stored in the
/// group the Top Shelf entitlement names, team id included, and a read uses that same group.
///
/// The Top Shelf process is an `.appex`. Its only keychain entitlement is the shared group,
/// so that group is also what an omitted-group query finds. This file therefore does not
/// search or delete the omitted-group slot from the extension, and it does not insert the
/// team-id probe there. Migration of an older copy runs in the app.
///
/// A write adds the shared item and reads it back before any old slot is deleted. Nothing
/// in here is written to a log. `Failure` carries the status code only.
enum Keychain {
    struct Failure: Error, LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "The keychain refused the change (status \(status))."
        }
    }

    private static let gate = NSLock()
    /// Cached only after a real group is known. A failed probe is not remembered, so a later
    /// call in the same process can try again. Nil means "not resolved yet", not "no group".
    private static var sharedGroup: String?
    private static var lastStatus: OSStatus = errSecSuccess

    /// True inside Top Shelf. The extension bundle is an `.appex`; the app bundle is not.
    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// The group in the tvOS entitlements, with the team id prefix. Nil on iOS, and nil on a
    /// tvOS build whose signing did not yield a team prefix: queries then omit the group,
    /// which is the only place those builds can keep an item.
    private static func resolvedSharedGroup() -> String? {
        gate.lock()
        let cached = sharedGroup
        gate.unlock()
        if let cached { return cached }
        guard let value = computeSharedGroup() else { return nil }
        gate.lock()
        if sharedGroup == nil { sharedGroup = value }
        let result = sharedGroup
        gate.unlock()
        return result
    }

    private static func computeSharedGroup() -> String? {
        let plist = Bundle.main.object(forInfoDictionaryKey: "KJKeychainGroup") as? String
        if let ready = KeychainAccess.group(fromPlistValue: plist) { return ready }
        // No key in the phone's Info.plist: do not probe, and do not invent the tvOS group.
        guard let plist, !plist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return KeychainAccess.resolvedSharedGroup(plistValue: plist, probedGroup: probedDefaultAccessGroup())
    }

    /// The access group the system assigns when a query sets none. That string begins with
    /// the Team ID. The marker stored here is not a password and not a session. It is removed
    /// before this function returns, and it is never inserted from the extension.
    private static func probedDefaultAccessGroup() -> String? {
        guard !isAppExtension else { return nil }
        let probe = KeychainAccess.Name(service: KJConfig.keychainService, account: KeychainAccess.probeAccount, accessGroup: nil)
        defer { remove(probe) }
        if copy(probe) == nil {
            let status = SecItemAdd(adding(Data([1]), probe) as CFDictionary, nil)
            if status != errSecSuccess && status != errSecDuplicateItem { return nil }
        }
        var query = dictionary(probe)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess, let attrs = found as? [String: Any] else { return nil }
        return attrs[kSecAttrAccessGroup as String] as? String
    }

    /// `shared` selects the group the Top Shelf extension is entitled to. Migration runs only
    /// in the app: the extension's omitted-group query is the shared item itself.
    private static func placement(shared: Bool) -> (group: String?, migrate: Bool) {
        let migrate = shared && !isAppExtension
        let group = shared ? resolvedSharedGroup() : nil
        return (group, migrate)
    }

    /// `shared` reads the group the Top Shelf extension is entitled to. The phone never passes
    /// it. On Apple TV the app moves a newer copy out of an older slot only after the shared
    /// item reads back. The extension reads the shared item and does not touch the other slot.
    static func read(_ account: String, shared: Bool = false) -> Data? {
        let place = placement(shared: shared)
        return KeychainAccess.readItem(
            service: KJConfig.keychainService,
            account: account,
            accessGroup: place.group,
            migrate: place.migrate,
            store: SecSlots())
    }

    /// Replaces the account. The shared item is added and read back before any older slot is
    /// deleted. A refused add leaves the previous shared item in place unless the private
    /// fallback reads back.
    static func write(_ data: Data, account: String, shared: Bool = false) throws {
        let place = placement(shared: shared)
        guard KeychainAccess.writeItem(
            data: data,
            service: KJConfig.keychainService,
            account: account,
            accessGroup: place.group,
            migrate: place.migrate,
            store: SecSlots()) else {
            throw Failure(status: lastStatus)
        }
    }

    static func delete(_ account: String, shared: Bool = false) {
        let place = placement(shared: shared)
        KeychainAccess.deleteItem(
            service: KJConfig.keychainService,
            account: account,
            accessGroup: place.group,
            migrate: place.migrate,
            store: SecSlots())
    }

    private struct SecSlots: KeychainAccess.SlotStore {
        func copy(_ name: KeychainAccess.Name) -> Data? { Keychain.copy(name) }
        func modified(_ name: KeychainAccess.Name) -> Date? { Keychain.modified(name) }
        func store(_ data: Data, as name: KeychainAccess.Name) -> Bool { Keychain.store(data, as: name) }
        func remove(_ name: KeychainAccess.Name) { Keychain.remove(name) }
    }

    /// Inserts or replaces. True only when the item then reads back as `data`. A refused add
    /// or update leaves the previous item in place.
    private static func store(_ data: Data, as name: KeychainAccess.Name) -> Bool {
        let added = SecItemAdd(adding(data, name) as CFDictionary, nil)
        if added == errSecDuplicateItem {
            let changes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            lastStatus = SecItemUpdate(dictionary(name) as CFDictionary, changes as CFDictionary)
            guard lastStatus == errSecSuccess else { return false }
        } else {
            lastStatus = added
            guard added == errSecSuccess else { return false }
        }
        return copy(name) == data
    }

    private static func modified(_ name: KeychainAccess.Name) -> Date? {
        var query = dictionary(name)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let attrs = found as? [String: Any] else { return nil }
        return attrs[kSecAttrModificationDate as String] as? Date
    }

    private static func dictionary(_ name: KeychainAccess.Name) -> [String: Any] {
        assert((kSecAttrService as String) == "svce")
        assert((kSecAttrAccount as String) == "acct")
        assert((kSecAttrAccessGroup as String) == "agrp")
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name.service,
            kSecAttrAccount as String: name.account
        ]
        if let group = name.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func adding(_ data: Data, _ name: KeychainAccess.Name) -> [String: Any] {
        var item = dictionary(name)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return item
    }

    private static func copy(_ name: KeychainAccess.Name) -> Data? {
        var query = dictionary(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess else { return nil }
        return found as? Data
    }

    private static func remove(_ name: KeychainAccess.Name) {
        _ = SecItemDelete(dictionary(name) as CFDictionary)
    }
}
