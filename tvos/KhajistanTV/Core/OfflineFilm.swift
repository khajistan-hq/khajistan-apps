import Foundation

/// Advisory app checks, in addition to the expiry enforced inside FairPlay's persistent key.
/// These records are NEVER sufficient authority to issue a key. The KSM checks the account,
/// entitlement, title rights and FPS device identity on every issue/renewal.
struct OfflineFilmGrant: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case rental, purchase }
    let entitlementID: UUID
    let accountID: String
    let deviceID: UUID
    let filmHandle: String
    let assetVersion: String
    let kind: Kind
    let issuedAt: Date
    let refreshBy: Date
    /// Absolute deadline from the existing order; never reset by downloading again.
    let startBy: Date?
    /// Present when already started elsewhere. Offline first-play expiry is enforced by FPS.
    let playbackEndsAt: Date?
    let playbackDuration: TimeInterval?

    func validate(account: String, device: UUID, film: String, version: String) throws {
        guard !account.isEmpty, accountID == account, deviceID == device,
              !film.isEmpty, filmHandle == film, !version.isEmpty, assetVersion == version,
              refreshBy > issuedAt else { throw OfflineFilmError.invalidGrant }
        switch kind {
        case .purchase:
            guard startBy == nil, playbackEndsAt == nil, playbackDuration == nil else {
                throw OfflineFilmError.invalidGrant
            }
        case .rental:
            // An API cannot quietly replace the existing 48-hour promise with a shorter one.
            guard let startBy, startBy > issuedAt || playbackEndsAt != nil,
                  playbackDuration == 48 * 3600,
                  playbackEndsAt.map({ $0 > issuedAt }) ?? true else {
                throw OfflineFilmError.invalidGrant
            }
        }
    }

    func access(at now: Date, firstPlayedAt: Date?, lastObservedAt: Date) -> OfflineFilmAccess {
        // Clock rollback is an online recovery, never grounds for extending a local lease.
        guard now >= lastObservedAt, now >= issuedAt else { return .reconnect }
        if kind == .rental {
            if let end = playbackEndsAt, now >= end { return .expired }
            if let firstPlayedAt {
                // Renewal must retain the original activation even when it predates issuedAt.
                guard firstPlayedAt <= now else { return .reconnect }
                if now >= firstPlayedAt.addingTimeInterval(48 * 3600) { return .expired }
            } else if playbackEndsAt == nil, let startBy, now >= startBy { return .expired }
        }
        return now < refreshBy ? .allowed : .reconnect
    }
}

enum OfflineFilmAccess: Equatable { case allowed, reconnect, expired }

enum OfflineFilmError: Error, LocalizedError {
    case unavailable, invalidGrant, wrongAccount, needsConnection, expired, missingKey, invalidAsset, storage, deviceLocked

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Offline films are not available yet. You can still stream this film."
        case .wrongAccount: return "Sign in to the account that saved this film."
        case .needsConnection: return "Connect to the internet to check this film's offline access."
        case .expired: return "This film's rental has ended."
        case .missingKey, .invalidAsset: return "This offline copy is incomplete. Connect to download it again."
        case .storage: return "This device could not save the protected film. Check available storage and try again."
        case .deviceLocked: return "Unlock this device to check its protected films."
        case .invalidGrant: return "Offline access could not be verified. Connect and try again."
        }
    }
}

/// The lifecycle reducer is deliberately independent of AVFoundation so race/failure cases can
/// be tested. Only the driver can mark media AND a persistent key complete. URLs never enter UI.
struct OfflineFilmTransfer: Equatable {
    enum State: Equatable { case downloading, paused, verifying, ready, failed, removed }
    let id: UUID
    let accountID: String
    private(set) var state: State = .downloading
    private(set) var mediaComplete = false
    private(set) var keyComplete = false

    mutating func mediaFinished() {
        guard state == .downloading || state == .paused else { return }
        mediaComplete = true
        state = keyComplete ? .ready : .verifying
    }

    mutating func keyPersisted() {
        guard state == .downloading || state == .paused || state == .verifying else { return }
        keyComplete = true
        if mediaComplete { state = .ready }
    }

    mutating func pause() { if state == .downloading { state = .paused } }
    mutating func resume() { if state == .paused { state = .downloading } }
    mutating func fail() { if state != .removed { state = .failed; keyComplete = false } }
    mutating func remove() { state = .removed; keyComplete = false; mediaComplete = false }

    /// A completed record is revalidated against the actual on-disk package and key on launch.
    mutating func restore(packageExists: Bool, keyExists: Bool, taskExists: Bool) {
        guard state != .removed else { return }
        if state == .ready && (!packageExists || !keyExists) { fail() }
        else if state != .ready && !taskExists { fail() }
    }
}

/// Rejects ordinary signed streaming URLs at the offline boundary. Only an approved HTTPS
/// manifest and an explicit FairPlay content key identifier can be used by the native driver.
struct OfflineFilmAsset {
    let manifest: URL
    let keyIdentifier: String

    func validate(allowedHosts: Set<String>) throws {
        guard manifest.scheme == "https", manifest.user == nil, manifest.password == nil,
              manifest.port == nil || manifest.port == 443,
              let host = manifest.host?.lowercased(), allowedHosts.contains(host),
              manifest.pathExtension.lowercased() == "m3u8",
              let key = URL(string: keyIdentifier), key.scheme == "skd",
              (2...200).contains(keyIdentifier.utf8.count),
              !keyIdentifier.contains(where: { $0.isWhitespace }) else { throw OfflineFilmError.invalidAsset }
    }
}

/// Only one native key operation owns an entitlement at a time, including retries within the
/// same account session. An obsolete operation cannot release or delete a replacement's key.
struct OfflineKeyOwners {
    private var owners: [UUID: UUID] = [:]
    mutating func claim(entitlement: UUID, owner: UUID) -> UUID? {
        owners.updateValue(owner, forKey: entitlement)
    }
    func owns(entitlement: UUID, owner: UUID) -> Bool { owners[entitlement] == owner }
    mutating func release(entitlement: UUID, owner: UUID) {
        if owns(entitlement: entitlement, owner: owner) { owners[entitlement] = nil }
    }
}
