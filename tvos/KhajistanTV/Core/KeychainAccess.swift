import Foundation

/// Names a generic-password keychain item so a read asks for the same service, account and
/// access group a write stored.
///
/// The Apple TV app and its Top Shelf extension share one entitlement,
/// `$(AppIdentifierPrefix)com.khajistan.tv.shared`. The system records that as
/// `<TeamID>.com.khajistan.tv.shared`. A query that leaves the group off, or that uses the
/// suffix with no team id, does not find the item on the next launch: the preview password
/// is still in the keychain and the viewer is asked to type it again.
///
/// The extension's default group is that shared group, because it is the extension's only
/// entitlement. An omitted-group query there names the same item. The extension therefore
/// reads the explicit group and does not search or delete the omitted-group slot. Migration
/// of an older copy stays in the app, whose default group is a different entitlement.
///
/// The iPhone app has no keychain-access-groups entitlement. Its items were stored with the
/// group omitted, and that is still the query a phone read and write share. When a query does
/// name a group and the item is not there, the ungrouped item is the old copy to read once.
enum KeychainAccess {
    /// Entitlement suffix in `KhajistanTV.entitlements` and `TopShelf.entitlements`, without
    /// the team-id prefix. The app's own group (`com.khajistan.tv`) is the default when a
    /// query sets no group; the session stays there.
    static let tvSharedSuffix = "com.khajistan.tv.shared"
    static let tvAppSuffix = "com.khajistan.tv"

    /// Account of the non-secret marker used to learn the team id. It is neither the preview
    /// password nor the signed-in session.
    static let probeAccount = "kj.access-group"

    struct Name: Equatable {
        var service: String
        var account: String
        /// Full access group, team id included. Nil means the query must not set one.
        var accessGroup: String?

        /// SecItem attribute names (`kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessGroup`).
        /// Literals, so this file does not import Security and the core tests can build it.
        /// The password is not an attribute of the name: it never appears here.
        var attributes: [String: String] {
            var attrs = [
                "svce": service,
                "acct": account
            ]
            if let accessGroup {
                attrs["agrp"] = accessGroup
            }
            return attrs
        }
    }

    /// One stored secret and the date the keychain recorded for it, if any. The bytes are
    /// compared in memory. Nothing here is logged.
    struct Held: Equatable {
        var data: Data
        var modified: Date?
    }

    /// A stand-in or the real keychain. `store` inserts or replaces and returns true only
    /// when a following copy equals `data`. On false the previous value is still there.
    /// `store` does not delete first.
    protocol SlotStore {
        func copy(_ name: Name) -> Data?
        func modified(_ name: Name) -> Date?
        func store(_ data: Data, as name: Name) -> Bool
        func remove(_ name: Name)
    }

    /// A team-id prefix is the ten-character Team ID and a trailing dot, as in `A1B2C3D4E5.`.
    /// An unexpanded `$(AppIdentifierPrefix)`, an empty expansion, or the bare entitlement
    /// suffix is not a prefix. Using one of those as the group is how the item was lost.
    static func isTeamPrefix(_ prefix: String) -> Bool {
        guard prefix.count == 11, prefix.last == "." else { return false }
        return prefix.dropLast().unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        }
    }

    /// `<teamPrefix><suffix>` when `teamPrefix` is a real Team ID prefix. Otherwise nil:
    /// the caller omits the group rather than store an item the entitlement will not match.
    static func entitledGroup(teamPrefix: String?, suffix: String = tvSharedSuffix) -> String? {
        guard let teamPrefix, isTeamPrefix(teamPrefix), !suffix.isEmpty, !suffix.hasPrefix(".") else { return nil }
        return teamPrefix + suffix
    }

    /// The Team ID prefix inside a group the system already assigned, such as
    /// `A1B2C3D4E5.com.khajistan.tv` or `A1B2C3D4E5.com.khajistan.tv.shared`. A bundle id with
    /// no team id, including the phone's, returns nil.
    static func teamPrefix(inAccessGroup group: String) -> String? {
        let suffixes = [tvSharedSuffix, tvAppSuffix].sorted { $0.count > $1.count }
        for suffix in suffixes {
            guard group.hasSuffix(suffix), group.count > suffix.count else { continue }
            let prefix = String(group.dropLast(suffix.count))
            if isTeamPrefix(prefix) { return prefix }
        }
        return nil
    }

    /// `KJKeychainGroup` from Info.plist, when it has already been expanded to the entitled
    /// group. `$(AppIdentifierPrefix)` is substituted in the entitlements file; in Info.plist
    /// it is sometimes left as written or replaced with nothing, and neither of those is a group.
    /// `$(DEVELOPMENT_TEAM)` is a build setting, so a signed build can bake
    /// `<TeamID>.com.khajistan.tv.shared`. An empty team expands to a leading dot and is rejected.
    static func group(fromPlistValue raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.contains("$(") else { return nil }
        if text.hasSuffix(tvSharedSuffix), let prefix = teamPrefix(inAccessGroup: text) {
            return prefix + tvSharedSuffix
        }
        if isTeamPrefix(text) { return entitledGroup(teamPrefix: text) }
        return nil
    }

    /// The access group a new shared item should use.
    ///
    /// A plist value that is already `<TeamID>.com.khajistan.tv.shared` wins. When the plist
    /// names the group but the team id did not expand, `probedGroup` is the access group on an
    /// item stored with no group of its own (the app's default group, the first entitlement).
    /// A bundle with no plist value is the iPhone app: it must not take the tvOS group.
    static func resolvedSharedGroup(plistValue: String?, probedGroup: String?) -> String? {
        if let ready = group(fromPlistValue: plistValue) { return ready }
        guard let plistValue, !plistValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let probedGroup, let prefix = teamPrefix(inAccessGroup: probedGroup) else { return nil }
        return entitledGroup(teamPrefix: prefix)
    }

    enum KeptCopy: Equatable {
        case preferred
        case legacy
    }

    /// True when both dates are known and `legacy` is strictly later. A missing date is
    /// unknown, not newer. Equal dates are not later.
    static func legacyIsNewer(preferred: Date?, legacy: Date?) -> Bool {
        guard let preferred, let legacy else { return false }
        return legacy > preferred
    }

    /// Which copy to keep when both the grouped item and an older slot may exist.
    ///
    /// A later legacy date wins only when both dates are known. A missing date is unknown:
    /// the shared item stays when it exists, because that is the only copy the last successful
    /// shared write could have stored. The legacy item is kept when it is the only copy.
    static func keep(hasPreferred: Bool, preferredModified: Date?, hasLegacy: Bool, legacyModified: Date?) -> KeptCopy? {
        if !hasPreferred && !hasLegacy { return nil }
        if hasPreferred && !hasLegacy { return .preferred }
        if !hasPreferred && hasLegacy { return .legacy }
        if let preferredModified, let legacyModified, legacyModified > preferredModified {
            return .legacy
        }
        return .preferred
    }

    /// The omitted-group private item is the app's old default slot. It wins over the bare
    /// entitlement suffix even when the private item has no date and the suffix does. The bare
    /// suffix is only a candidate when the private slot is empty.
    static func chooseLegacy(omitted: Held?, bare: Held?) -> Held? {
        if let omitted { return omitted }
        return bare
    }

    /// `preferred` is the query read and write both use. `legacy` is where a copy saved before
    /// the group was corrected may still sit: the default group (no access group), then the
    /// entitlement suffix with no team id.
    ///
    /// When `accessGroup` is nil, `legacy` is empty. That is the iPhone query, and the Apple TV
    /// query for the session: the item already stored is the one this read finds, and nothing
    /// is moved. When `migrate` is false, `legacy` is empty as well: the Top Shelf extension
    /// passes that, because its omitted-group slot is the shared item and must not be deleted.
    static func lookup(service: String, account: String, accessGroup: String?, migrate: Bool = true) -> (preferred: Name, legacy: [Name]) {
        let preferred = Name(service: service, account: account, accessGroup: accessGroup)
        guard migrate, accessGroup != nil else { return (preferred, []) }
        var legacy = [Name(service: service, account: account, accessGroup: nil)]
        if let accessGroup, accessGroup.hasSuffix(tvSharedSuffix), accessGroup != tvSharedSuffix {
            legacy.append(Name(service: service, account: account, accessGroup: tvSharedSuffix))
        }
        return (preferred, legacy.filter { $0 != preferred })
    }

    /// Reads the preferred slot. With `migrate` false, that is the only query: nothing is
    /// searched or deleted. With `migrate` true (the app), an older copy is adopted into the
    /// preferred slot only after that store reads back, and only then are the old slots removed.
    static func readItem<S: SlotStore>(service: String, account: String, accessGroup: String?, migrate: Bool, store: S) -> Data? {
        let found = lookup(service: service, account: account, accessGroup: accessGroup, migrate: migrate)
        let preferredData = store.copy(found.preferred)
        guard migrate, !found.legacy.isEmpty else { return preferredData }

        var omitted: Held?
        var bare: Held?
        for old in found.legacy {
            guard let data = store.copy(old) else { continue }
            let held = Held(data: data, modified: store.modified(old))
            if old.accessGroup == nil {
                omitted = held
            } else if bare == nil {
                bare = held
            }
        }
        let chosen = chooseLegacy(omitted: omitted, bare: bare)
        let decision = keep(
            hasPreferred: preferredData != nil,
            preferredModified: preferredData == nil ? nil : store.modified(found.preferred),
            hasLegacy: chosen != nil,
            legacyModified: chosen?.modified)
        switch decision {
        case .legacy:
            guard let chosen else { return nil }
            if store.store(chosen.data, as: found.preferred) {
                for old in found.legacy { store.remove(old) }
            }
            return chosen.data
        case .preferred:
            for old in found.legacy where store.copy(old) != nil {
                store.remove(old)
            }
            return preferredData
        case nil:
            return nil
        }
    }

    /// Stores into the preferred slot first and reads it back. Old slots are removed only after
    /// that succeeds. If the preferred add is refused, the previous preferred item stays unless
    /// a private (omitted-group) fallback reads back; only then is the old preferred item removed.
    /// `migrate` false never writes or deletes the omitted-group slot.
    static func writeItem<S: SlotStore>(data: Data, service: String, account: String, accessGroup: String?, migrate: Bool, store: S) -> Bool {
        let found = lookup(service: service, account: account, accessGroup: accessGroup, migrate: migrate)
        if found.preferred.accessGroup != nil {
            if store.store(data, as: found.preferred) {
                if migrate {
                    for old in found.legacy { store.remove(old) }
                }
                return true
            }
            // The add was refused. If the bytes are already there, the previous item is the
            // value we wanted; leave it and drop the old slots.
            if store.copy(found.preferred) == data {
                if migrate {
                    for old in found.legacy { store.remove(old) }
                }
                return true
            }
            guard migrate else { return false }
            let plain = Name(service: service, account: account, accessGroup: nil)
            guard store.store(data, as: plain), store.copy(plain) == data else { return false }
            store.remove(found.preferred)
            for old in found.legacy where old.accessGroup != nil {
                store.remove(old)
            }
            return true
        }
        return store.store(data, as: found.preferred)
    }

    /// Removes the preferred item. Old slots are removed only when `migrate` is true, so an
    /// extension delete cannot hit the omitted-group name of the same shared item.
    static func deleteItem<S: SlotStore>(service: String, account: String, accessGroup: String?, migrate: Bool, store: S) {
        let found = lookup(service: service, account: account, accessGroup: accessGroup, migrate: migrate)
        store.remove(found.preferred)
        guard migrate else { return }
        for old in found.legacy { store.remove(old) }
    }
}
