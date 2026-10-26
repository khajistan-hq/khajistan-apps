import Foundation
import Security

/// Generic-password items under one service name. Values are small blobs the app owns:
/// the signed-in session and the preview password.
///
/// The phone and the Apple TV compile this one file. The phone has no keychain-access-groups
/// entitlement and no `KJKeychainGroup`, so its queries omit the access group: that is where
/// every item already on a phone was stored. The Apple TV preview password is stored in the
/// group the Top Shelf entitlement names, team id included, and a read uses that same group.
/// Nothing in here is written to a log. `Failure` carries the status code only.
enum Keychain {
    struct Failure: Error, LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "The keychain refused the change (status \(status))."
        }
    }

    private static let gate = NSLock()
    private static var didResolveSharedGroup = false
    private static var sharedGroup: String?

    /// The group in the tvOS entitlements, with the team id prefix. Nil on iOS, and nil on a
    /// tvOS build whose signing did not yield a team prefix: queries then omit the group,
    /// which is the only place those builds can keep an item.
    private static func resolvedSharedGroup() -> String? {
        gate.lock()
        let done = didResolveSharedGroup
        let cached = sharedGroup
        gate.unlock()
        if done { return cached }
        let value = computeSharedGroup()
        gate.lock()
        if !didResolveSharedGroup {
            sharedGroup = value
            didResolveSharedGroup = true
        }
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
    /// the Team ID. The marker stored here is not a password and not a session.
    private static func probedDefaultAccessGroup() -> String? {
        let name = KeychainAccess.Name(service: KJConfig.keychainService, account: KeychainAccess.probeAccount, accessGroup: nil)
        if copy(name) == nil {
            let status = SecItemAdd(adding(Data([1]), name) as CFDictionary, nil)
            if status != errSecSuccess && status != errSecDuplicateItem { return nil }
        }
        var query = dictionary(name)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess, let attrs = found as? [String: Any] else { return nil }
        return attrs[kSecAttrAccessGroup as String] as? String
    }

    private static func names(account: String, shared: Bool) -> (preferred: KeychainAccess.Name, legacy: [KeychainAccess.Name]) {
        let group = shared ? resolvedSharedGroup() : nil
        return KeychainAccess.lookup(service: KJConfig.keychainService, account: account, accessGroup: group)
    }

    /// `shared` reads the group the Top Shelf extension is entitled to. The phone never passes
    /// it, and its query has no legacy slots, so an item already stored is read and left where
    /// it is. On Apple TV a copy in an older slot is kept when it is the later write, and it is
    /// removed only after the grouped item reads back.
    static func read(_ account: String, shared: Bool = false) -> Data? {
        let found = names(account: account, shared: shared)
        // Slots a previous build may have used. The phone's query sets no group, so this
        // list stays empty and the item already on the device is what `preferred` reads.
        var legacyNames = found.legacy
        if shared, found.preferred.accessGroup == nil {
            let bare = KeychainAccess.Name(service: KJConfig.keychainService, account: account, accessGroup: KeychainAccess.tvSharedSuffix)
            if !legacyNames.contains(bare) { legacyNames.append(bare) }
        }

        let preferredData = copy(found.preferred)
        // The phone's query names no old slot, so the item already stored is what this returns.
        guard !legacyNames.isEmpty else { return preferredData }

        var bestLegacy: (data: Data, modified: Date?)?
        for old in legacyNames {
            guard let data = copy(old) else { continue }
            let stamp = modified(old)
            if bestLegacy == nil || KeychainAccess.legacyIsNewer(preferred: bestLegacy?.modified, legacy: stamp) {
                bestLegacy = (data, stamp)
            }
        }
        let decision = KeychainAccess.keep(
            hasPreferred: preferredData != nil,
            preferredModified: preferredData == nil ? nil : modified(found.preferred),
            hasLegacy: bestLegacy != nil,
            legacyModified: bestLegacy?.modified)
        switch decision {
        case .legacy:
            if let data = bestLegacy?.data, adopted(data, as: found.preferred) {
                for old in legacyNames { remove(old) }
            }
            return bestLegacy?.data
        case .preferred:
            // An older copy was actually stored. Drop it now that the grouped item is the later one.
            if bestLegacy != nil {
                for old in legacyNames { remove(old) }
            }
            return preferredData
        case nil:
            return nil
        }
    }

    /// Replaces whatever is stored under the account. Every previous slot is removed first,
    /// so a stale copy in the old group cannot outlive the value just saved.
    static func write(_ data: Data, account: String, shared: Bool = false) throws {
        let found = names(account: account, shared: shared)
        remove(found.preferred)
        for legacy in found.legacy { remove(legacy) }
        if shared, found.preferred.accessGroup == nil {
            remove(KeychainAccess.Name(service: found.preferred.service, account: account, accessGroup: KeychainAccess.tvSharedSuffix))
        }
        if found.preferred.accessGroup != nil {
            let status = SecItemAdd(adding(data, found.preferred) as CFDictionary, nil)
            if status == errSecSuccess { return }
            if status == errSecDuplicateItem {
                remove(found.preferred)
                if SecItemAdd(adding(data, found.preferred) as CFDictionary, nil) == errSecSuccess { return }
            }
            // The group was refused (a simulator signed with CODE_SIGNING_ALLOWED=NO).
            // Keep the value in the default group so this app can still read it back.
        }
        let plain = KeychainAccess.Name(service: found.preferred.service, account: found.preferred.account, accessGroup: nil)
        let status = SecItemAdd(adding(data, plain) as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete(_ account: String, shared: Bool = false) {
        let found = names(account: account, shared: shared)
        remove(found.preferred)
        for legacy in found.legacy { remove(legacy) }
        if shared {
            remove(KeychainAccess.Name(service: KJConfig.keychainService, account: account, accessGroup: KeychainAccess.tvSharedSuffix))
        }
    }

    /// Stores `data` in the group reads use, replacing whatever was there. True only after
    /// that item reads back as `data`. The bytes are compared in memory and never logged.
    private static func adopted(_ data: Data, as preferred: KeychainAccess.Name) -> Bool {
        guard preferred.accessGroup != nil else { return false }
        remove(preferred)
        guard SecItemAdd(adding(data, preferred) as CFDictionary, nil) == errSecSuccess else { return false }
        return copy(preferred) == data
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
