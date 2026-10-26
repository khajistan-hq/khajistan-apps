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

    /// True when `legacy` is a strictly later modification than `preferred`. A missing date
    /// is not later. Equal dates are not later. Used to choose among old slots.
    static func legacyIsNewer(preferred: Date?, legacy: Date?) -> Bool {
        switch (preferred, legacy) {
        case (_, nil): return false
        case (nil, .some): return true
        case let (preferredDate?, legacyDate?): return legacyDate > preferredDate
        }
    }

    /// Which copy to keep when both the grouped item and an older slot may exist.
    /// A later date wins. When neither date is known, the old slot wins: that is the item
    /// the previous app was able to read, and the grouped copy may be an earlier save that
    /// a duplicate add could not replace. Equal dates keep the grouped item.
    static func keep(hasPreferred: Bool, preferredModified: Date?, hasLegacy: Bool, legacyModified: Date?) -> KeptCopy? {
        if !hasPreferred && !hasLegacy { return nil }
        if hasPreferred && !hasLegacy { return .preferred }
        if !hasPreferred && hasLegacy { return .legacy }
        switch (preferredModified, legacyModified) {
        case let (preferredDate?, legacyDate?) where legacyDate > preferredDate:
            return .legacy
        case (_?, _?):
            return .preferred
        case (nil, nil):
            return .legacy
        case (_?, nil):
            return .preferred
        case (nil, _?):
            return .legacy
        }
    }

    /// `preferred` is the query read and write both use. `legacy` is where a copy saved before
    /// the group was corrected may still sit: the default group (no access group), then the
    /// entitlement suffix with no team id.
    ///
    /// When `accessGroup` is nil, `legacy` is empty. That is the iPhone query, and the Apple TV
    /// query for the session: the item already stored is the one this read finds, and nothing
    /// is moved.
    static func lookup(service: String, account: String, accessGroup: String?) -> (preferred: Name, legacy: [Name]) {
        let preferred = Name(service: service, account: account, accessGroup: accessGroup)
        guard let accessGroup else { return (preferred, []) }
        var legacy = [Name(service: service, account: account, accessGroup: nil)]
        if accessGroup.hasSuffix(tvSharedSuffix), accessGroup != tvSharedSuffix {
            legacy.append(Name(service: service, account: account, accessGroup: tvSharedSuffix))
        }
        return (preferred, legacy.filter { $0 != preferred })
    }
}
