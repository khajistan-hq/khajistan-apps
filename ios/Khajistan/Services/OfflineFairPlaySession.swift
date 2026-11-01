import AVFoundation
import Foundation

/// Implement only after an approved provider/KSM is provisioned. The backend verifies the
/// authenticated account and FPS device, and puts expiry/dual-expiry policy INSIDE the CKC.
/// Never implement this with vod-token or a downloaded raw AES key.
@MainActor
protocol OfflineFairPlayLicenseService {
    func contentKeyContext(spc: Data, grant: OfflineFilmGrant, keyIdentifier: String) async throws -> Data
}

/// Native FairPlay key acquisition and replay, with the real AVFoundation delegate flow.
/// Not connected to a production endpoint or exposed as a customer feature until RELEASE_GATES
/// pass. This type never accepts a raw video file or a streaming-only key as a persistent key.
@MainActor
final class OfflineFairPlaySession: NSObject, @preconcurrency AVContentKeySessionDelegate {
    private let grant: OfflineFilmGrant
    private let keyIdentifier: String
    private let certificate: Data
    private let service: any OfflineFairPlayLicenseService
    private let scope: OfflineFilmAccountScope
    private let generation: UUID
    private let session = AVContentKeySession(keySystem: .fairPlayStreaming)
    private let owner = UUID()
    private var issuance: Task<Void, Never>?
    private var waiting: [AVPersistableContentKeyRequest] = []
    private var stopped = false
    private let onFailure: (Error) -> Void
    private let onKeyPersisted: () -> Void

    convenience init(grant: OfflineFilmGrant, asset: OfflineFilmAsset, approvedHosts: Set<String>,
         deviceID: UUID, certificate: Data, service: any OfflineFairPlayLicenseService,
         scope: OfflineFilmAccountScope, onFailure: @escaping (Error) -> Void,
         onKeyPersisted: @escaping () -> Void) throws {
        try asset.validate(allowedHosts: approvedHosts)
        try self.init(grant: grant, keyIdentifier: asset.keyIdentifier, deviceID: deviceID,
                      certificate: certificate, service: service, scope: scope,
                      onFailure: onFailure, onKeyPersisted: onKeyPersisted)
    }

    /// Local replay needs no stored signed manifest. The adapter checks the private package
    /// and existing device key before attaching this session, with a replay-only key service.
    init(grant: OfflineFilmGrant, keyIdentifier: String, deviceID: UUID, certificate: Data,
         service: any OfflineFairPlayLicenseService, scope: OfflineFilmAccountScope,
         onFailure: @escaping (Error) -> Void, onKeyPersisted: @escaping () -> Void) throws {
        guard let url = URL(string: keyIdentifier), url.scheme == "skd",
              (2...200).contains(keyIdentifier.utf8.count), !keyIdentifier.contains(where: { $0.isWhitespace }) else {
            throw OfflineFilmError.invalidAsset
        }
        try grant.validate(account: scope.accountID ?? "", device: deviceID,
                           film: grant.filmHandle, version: grant.assetVersion)
        guard !certificate.isEmpty, scope.usable else { throw OfflineFilmError.unavailable }
        self.grant = grant; self.keyIdentifier = keyIdentifier; self.certificate = certificate
        self.service = service; self.scope = scope; generation = scope.generation
        self.onFailure = onFailure; self.onKeyPersisted = onKeyPersisted
        super.init()
        // AVFoundation invokes the delegate on this queue; @preconcurrency preserves that
        // runtime main-actor contract for the Objective-C delegate protocol in Swift 5 builds.
        session.setDelegate(self, queue: .main)
        scope.claim(entitlement: grant.entitlementID, owner: owner) { [weak self] in self?.stop() }
    }

    func attach(to asset: AVURLAsset) throws {
        try checkScope()
        session.addContentKeyRecipient(asset)
    }

    /// Prefetching the persistent key must not start the rental. First playback causes FPS to
    /// supply the updated dual-expiry blob through didUpdatePersistableContentKey below.
    func prepareKey() throws {
        try checkScope()
        session.processContentKeyRequest(withIdentifier: keyIdentifier, initializationData: nil, options: nil)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        issuance?.cancel(); issuance = nil
        let abandoned = waiting; waiting.removeAll()
        abandoned.forEach { $0.processContentKeyResponseError(CancellationError()) }
        session.expire()
        scope.release(entitlement: grant.entitlementID, owner: owner)
    }

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        do {
            try checkScope()
            guard matches(keyRequest.identifier) else { throw OfflineFilmError.invalidAsset }
            if let stored = try OfflineFilmKeys.read(grant.entitlementID) {
                try validate(stored)
                var updated = stored
                updated.owner = owner
                updated.lastObservedAt = Date()
                try OfflineFilmKeys.write(updated)
                keyRequest.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: updated.key))
                onKeyPersisted()
            } else {
                try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
            }
        } catch { reject(keyRequest, error) }
    }

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVPersistableContentKeyRequest) {
        do {
            try checkScope()
            guard matches(keyRequest.identifier) else { throw OfflineFilmError.invalidAsset }
            waiting.append(keyRequest)
            guard issuance == nil else { return }
            issuance = Task { [weak self] in
                guard let self else { return }
                defer { issuance = nil }
                do {
                    try checkScope()
                    let spc = try await keyRequest.makeStreamingContentKeyRequestData(
                        forApp: certificate, contentIdentifier: Data(keyIdentifier.utf8), options: nil)
                    try checkScope(); try Task.checkCancellation()
                    let ckc = try await service.contentKeyContext(spc: spc, grant: grant, keyIdentifier: keyIdentifier)
                    try checkScope(); try Task.checkCancellation()
                    guard !ckc.isEmpty, ckc.count <= 256 * 1024 else { throw OfflineFilmError.missingKey }
                    let persistent = try keyRequest.persistableContentKey(fromKeyVendorResponse: ckc, options: nil)
                    // A same-version key updated while the request was in flight wins. Never
                    // restore a pre-play key over its dual-expiry replacement or reset activation.
                    var record: OfflineFilmKeys.Record
                    if let existing = try OfflineFilmKeys.read(grant.entitlementID) {
                        try validate(existing)
                        record = existing
                        record.owner = owner
                    } else {
                        record = OfflineFilmKeys.Record(grant: grant, keyIdentifier: keyIdentifier,
                            owner: owner, key: persistent, firstPlayedAt: nil, lastObservedAt: Date())
                    }
                    try validate(record)
                    try OfflineFilmKeys.write(record)
                    let requests = waiting; waiting.removeAll()
                    for request in requests {
                        request.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: record.key))
                    }
                    onKeyPersisted()
                } catch {
                    guard !stopped else { return }
                    let requests = waiting; waiting.removeAll()
                    requests.forEach { $0.processContentKeyResponseError(error) }
                    stop(); onFailure(error)
                }
            }
        } catch { reject(keyRequest, error) }
    }

    func contentKeySession(_ session: AVContentKeySession, didUpdatePersistableContentKey persistableContentKey: Data,
                           forContentKeyIdentifier keyIdentifier: Any) {
        guard !stopped, scope.accepts(account: grant.accountID, generation: generation),
              scope.owns(entitlement: grant.entitlementID, owner: owner) else { return }
        do {
            try checkScope()
            guard matches(keyIdentifier), var record = try OfflineFilmKeys.read(grant.entitlementID) else {
                throw OfflineFilmError.missingKey
            }
            try validate(record)
            record.key = persistableContentKey
            // Key update does not prove playback began (it may be renewal). The player calls
            // didBeginPlayback only after actual playback; FPS supplies the authoritative clock.
            record.lastObservedAt = Date()
            try OfflineFilmKeys.write(record)
        } catch {
            // An old dual-expiry key must never survive a failed replacement.
            // A callback from a logged-out generation cannot delete a newly issued key.
            if scope.accepts(account: grant.accountID, generation: generation),
               let stored = try? OfflineFilmKeys.read(grant.entitlementID), stored.grant == grant,
               stored.keyIdentifier == self.keyIdentifier, stored.owner == owner {
                try? OfflineFilmKeys.delete(grant.entitlementID)
            }
            stop(); onFailure(error)
        }
    }

    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest,
                           didFailWithError err: Error) {
        guard !stopped, scope.owns(entitlement: grant.entitlementID, owner: owner) else { return }
        stop(); onFailure(OfflineFilmError.invalidGrant)
    }

    func didBeginPlayback() throws {
        try checkScope()
        guard var record = try OfflineFilmKeys.read(grant.entitlementID), record.owner == owner else {
            throw OfflineFilmError.missingKey
        }
        try validate(record)
        if grant.kind == .rental && record.firstPlayedAt == nil { record.firstPlayedAt = Date() }
        record.lastObservedAt = Date()
        try OfflineFilmKeys.write(record)
    }

    private func matches(_ identifier: Any?) -> Bool {
        (identifier as? String) == keyIdentifier || (identifier as? URL)?.absoluteString == keyIdentifier
    }

    private func checkScope() throws {
        guard !stopped, scope.accepts(account: grant.accountID, generation: generation),
              scope.owns(entitlement: grant.entitlementID, owner: owner) else {
            throw OfflineFilmError.wrongAccount
        }
    }

    private func validate(_ record: OfflineFilmKeys.Record) throws {
        guard record.grant == grant, record.keyIdentifier == keyIdentifier, record.revoked != true else { throw OfflineFilmError.invalidGrant }
        switch grant.access(at: Date(), firstPlayedAt: record.firstPlayedAt, lastObservedAt: record.lastObservedAt) {
        case .allowed: break
        case .reconnect: throw OfflineFilmError.needsConnection
        case .expired: throw OfflineFilmError.expired
        }
    }

    private func reject(_ request: AVContentKeyRequest, _ error: Error) {
        request.processContentKeyResponseError(error)
        guard !stopped, scope.owns(entitlement: grant.entitlementID, owner: owner) else { return }
        stop(); onFailure(error)
    }
}
