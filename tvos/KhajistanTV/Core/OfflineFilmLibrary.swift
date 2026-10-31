import Foundation

struct OfflineFilmAuthorization {
    let grant: OfflineFilmGrant
    let asset: OfflineFilmAsset
    let title: String
}

/// An authenticated provider must explicitly authorize offline FPS. Streaming tokens are not
/// this contract. No implementation or endpoint is installed until provider setup is approved.
@MainActor
protocol OfflineFilmAuthorizing {
    func authorizeDownload(film: String) async throws -> OfflineFilmAuthorization
    /// A complete answer for every requested entitlement is required; absence is not approval.
    func checkEntitlements(_ grants: [OfflineFilmGrant]) async throws -> [UUID: Bool]
}

struct OfflineFilmDownloadEvent {
    enum Kind { case destination(URL), keyPersisted, completed, failed, protectedDataUnavailable }
    let operation: UUID
    let taskIdentifier: Int
    let kind: Kind
}

@MainActor
protocol OfflineFilmDownloadTransport: AnyObject {
    var onEvent: ((OfflineFilmDownloadEvent) -> Void)? { get set }
    /// Create suspended. The catalogue must durably bind the task before it may start.
    func makeDownload(_ record: OfflineFilmLibraryRecord, asset: OfflineFilmAsset) async throws -> Int
    func resume(_ operation: UUID) throws
    func pause(_ operation: UUID)
    /// True only after the task is terminal (or was never created). Otherwise a terminal
    /// delegate event must follow; keep the cleanup tombstone and accept its late destination.
    @discardableResult func cancel(_ operation: UUID) -> Bool
    /// Rebind only exact persisted operation/task identities; cancel unrecognized tasks.
    func restore(_ records: [OfflineFilmLibraryRecord]) async throws -> Set<UUID>
    func verifyPackage(_ record: OfflineFilmLibraryRecord, at url: URL) async throws
    func hasUsableKey(_ record: OfflineFilmLibraryRecord) throws -> Bool
    /// Durable device-key tombstone, independent of the catalogue's file system. Prevents
    /// known revocations becoming usable after restart when the index cannot be updated.
    func markRevoked(_ record: OfflineFilmLibraryRecord) throws
    func deleteKey(_ record: OfflineFilmLibraryRecord) throws
    func shutDown()
}

/// Account-scoped download/library orchestration. No public URL, file export or sales control.
/// The native adapter owns AVFoundation; controlled transports exercise these same lifecycle
/// decisions without network, clear media, provider credentials or paid sessions.
@MainActor
final class OfflineFilmLibrary {
    private let catalogue: OfflineFilmCatalogue
    private let session: OfflineFilmLibrarySession
    private let provider: any OfflineFilmAuthorizing
    private let transport: any OfflineFilmDownloadTransport
    private let account: String
    private let device: UUID
    private let container: URL
    private let approvedHosts: Set<String>
    private let isCurrent: () -> Bool
    private var stopped = false
    private var restoring = false
    private var restored = false
    private var pending: Set<String> = []
    private var creations: [UUID: Task<Int, Error>] = [:]
    private var revoked: Set<UUID> = []
    private var verifications: [UUID: Task<Void, Never>] = [:]
    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(catalogue: OfflineFilmCatalogue, session: OfflineFilmLibrarySession,
         provider: any OfflineFilmAuthorizing, transport: any OfflineFilmDownloadTransport,
         account: String, device: UUID, container: URL, approvedHosts: Set<String>,
         isCurrent: @escaping () -> Bool) {
        self.catalogue = catalogue; self.session = session; self.provider = provider
        self.transport = transport; self.account = account; self.device = device
        self.container = container; self.approvedHosts = approvedHosts; self.isCurrent = isCurrent
        transport.onEvent = { [weak self] event in self?.receive(event) }
    }

    func records() throws -> [OfflineFilmLibraryRecord] {
        try check()
        return try catalogue.all().map { value in
            var row = value
            // A successful revocation response stops access before fallible disk cleanup.
            if revoked.contains(row.grant.entitlementID) { row.phase = .removing }
            return row
        }
    }

    /// Recreating the stable background session is required before any new download. Ready
    /// metadata is checked against storage and device keys, never trusted by itself.
    func restore() async throws {
        try check()
        guard !restoring else { throw OfflineFilmError.unavailable }
        guard !restored else { return }
        restoring = true; defer { restoring = false }
        let saved = try catalogue.all()
        let active = try await transport.restore(saved)
        try check()
        for row in try catalogue.all() {
            if row.phase == .removing {
                if !active.contains(row.operation) { _ = try catalogue.update(row) { $0.taskIdentifier = nil } }
                try remove(row.id)
            } else if row.phase == .ready {
                do {
                    guard try transport.hasUsableKey(row), let path = row.packagePath else { throw OfflineFilmError.missingKey }
                    let url = try OfflineFilmPackageLocation.resolve(path, container: container)
                    try await transport.verifyPackage(row, at: url)
                    try check()
                } catch OfflineFilmError.deviceLocked { throw OfflineFilmError.deviceLocked }
                catch { try check(); fail(row.operation) }
            } else if row.phase == .verifying, row.packagePath != nil {
                verify(row.operation)
            } else if (row.phase == .downloading || row.phase == .paused), row.packagePath != nil,
                      !active.contains(row.operation) {
                // A locked-device relaunch can miss the terminal callback. Trust only a new
                // protected/offline-playable package check and an existing valid device key.
                if try transport.hasUsableKey(row) {
                    _ = try catalogue.update(row) { $0.phase = .verifying; $0.taskIdentifier = nil; $0.keyPersisted = true }
                    verify(row.operation)
                } else { fail(row.operation) }
            } else if row.phase != .failed, !active.contains(row.operation) {
                fail(row.operation)
            }
        }
        restored = true; onChange?()
    }

    @discardableResult
    func download(film: String) async throws -> UUID {
        try check()
        guard restored, !pending.contains(film) else { throw OfflineFilmError.unavailable }
        if let row = try catalogue.all().first(where: { $0.grant.filmHandle == film }) { return row.id }
        pending.insert(film); defer { pending.remove(film) }
        let authorization = try await provider.authorizeDownload(film: film)
        try check(); try Task.checkCancellation()
        let grant = authorization.grant
        try grant.validate(account: account, device: device, film: film, version: grant.assetVersion)
        guard !revoked.contains(grant.entitlementID) else { throw OfflineFilmError.invalidGrant }
        guard grant.access(at: Date(), firstPlayedAt: nil, lastObservedAt: grant.issuedAt) == .allowed else {
            throw OfflineFilmError.needsConnection
        }
        try authorization.asset.validate(allowedHosts: approvedHosts)
        var row = try catalogue.insert(OfflineFilmLibraryRecord(id: UUID(), grant: grant,
            keyIdentifier: authorization.asset.keyIdentifier, title: authorization.title,
            phase: .downloading, taskIdentifier: nil, packagePath: nil))
        do {
            let input = row
            let creation = Task { try await transport.makeDownload(input, asset: authorization.asset) }
            creations[row.operation] = creation
            let task = try await creation.value
            creations[row.operation] = nil
            try check(); try Task.checkCancellation()
            guard let latest = try current(row.operation), latest.phase == .downloading || latest.phase == .paused else {
                throw CancellationError()
            }
            guard let bound = try catalogue.update(latest, { $0.taskIdentifier = task }) else { throw OfflineFilmError.storage }
            row = bound
            if row.phase == .downloading { try transport.resume(row.operation) }
            onChange?(); return row.id
        } catch OfflineFilmError.deviceLocked {
            creations[row.operation] = nil; transport.pause(row.operation); restored = false
            throw OfflineFilmError.deviceLocked
        } catch {
            creations[row.operation] = nil; transport.cancel(row.operation)
            if let latest = try? current(row.operation), latest.phase == .removing { try? remove(latest.id) }
            else { fail(row.operation) }
            throw error
        }
    }

    func pause(_ id: UUID) throws {
        try check()
        guard let row = try catalogue.all().first(where: { $0.id == id }), row.phase == .downloading else { return }
        if try catalogue.update(row, { $0.phase = .paused }) != nil { transport.pause(row.operation); onChange?() }
    }

    func resume(_ id: UUID) throws {
        try check()
        guard let row = try catalogue.all().first(where: { $0.id == id }), row.phase == .paused else { return }
        guard !revoked.contains(row.grant.entitlementID) else { throw OfflineFilmError.invalidGrant }
        guard row.grant.access(at: Date(), firstPlayedAt: nil, lastObservedAt: row.grant.issuedAt) == .allowed else {
            throw OfflineFilmError.needsConnection
        }
        if try catalogue.update(row, { $0.phase = .downloading }) != nil {
            if creations[row.operation] != nil { onChange?(); return }
            do { try transport.resume(row.operation) }
            catch OfflineFilmError.deviceLocked { restored = false; transport.pause(row.operation); throw OfflineFilmError.deviceLocked }
            catch { fail(row.operation); throw error }
            onChange?()
        }
    }

    func remove(_ id: UUID) throws {
        try check()
        guard var row = try catalogue.all().first(where: { $0.id == id }) else { return }
        // A durable tombstone blocks callbacks/playback and survives failed cleanup/restart.
        if row.phase != .removing {
            guard let retired = try catalogue.update(row, { $0.phase = .removing }) else {
                throw OfflineFilmError.storage
            }
            row = retired
        }
        // Stop active playback before any fallible key/package cleanup, including revocation.
        onChange?()
        creations[row.operation]?.cancel()
        let terminal = transport.cancel(row.operation)
        verifications.removeValue(forKey: row.operation)?.cancel()
        // Revoke key use immediately, but retain the row until the last system callback.
        try transport.deleteKey(row)
        if creations[row.operation] != nil || (!terminal && row.taskIdentifier != nil) { onChange?(); return }
        if row.taskIdentifier != nil {
            guard let retired = try catalogue.update(row, { $0.taskIdentifier = nil }) else { throw OfflineFilmError.storage }
            row = retired
        }
        if let path = row.packagePath {
            let url = try OfflineFilmPackageLocation.resolve(path, container: container, mustExist: false)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try catalogue.remove(row)
        onChange?()
    }

    /// Invoke on a verified reconnection. Transient errors retain records but never extend the
    /// device license; an explicit revocation removes access and the saved package/key.
    func reconcile() async throws {
        try check()
        let before = try catalogue.all()
        let answer = try await provider.checkEntitlements(before.map(\.grant))
        try check()
        guard before.allSatisfy({ answer[$0.grant.entitlementID] != nil }) else { throw OfflineFilmError.invalidGrant }
        revoked.formUnion(before.filter { answer[$0.grant.entitlementID] == false }.map { $0.grant.entitlementID })
        onChange?()
        var cleanupError: Error?
        for old in before where answer[old.grant.entitlementID] == false {
            do { try transport.markRevoked(old) } catch { cleanupError = cleanupError ?? error }
            do {
                if let current = try catalogue.all().first(where: { $0.id == old.id && $0.operation == old.operation }) {
                    try remove(current.id)
                }
            } catch { cleanupError = cleanupError ?? error }
        }
        if let cleanupError { throw cleanupError }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true; transport.onEvent = nil
        creations.values.forEach { $0.cancel() }; creations.removeAll()
        verifications.values.forEach { $0.cancel() }; verifications.removeAll()
        transport.shutDown(); session.invalidate(); onChange?()
    }

    private func check() throws {
        guard !stopped, isCurrent() else { throw OfflineFilmError.wrongAccount }
    }

    private func current(_ operation: UUID) throws -> OfflineFilmLibraryRecord? {
        try check(); return try catalogue.all().first { $0.operation == operation }
    }

    private func receive(_ event: OfflineFilmDownloadEvent) {
        do {
            guard let row = try current(event.operation),
                  row.taskIdentifier == event.taskIdentifier ||
                    (row.taskIdentifier == nil && (row.phase == .downloading || row.phase == .failed || row.phase == .removing)) else { return }
            if row.phase == .removing || row.phase == .failed {
                switch event.kind {
                case .destination(let url):
                    let path = try OfflineFilmPackageLocation.relative(url, container: container)
                    guard row.packagePath == nil || row.packagePath == path else { throw OfflineFilmError.invalidAsset }
                    _ = try catalogue.update(row) { $0.packagePath = path; $0.taskIdentifier = event.taskIdentifier }
                case .completed, .failed:
                    _ = try catalogue.update(row) { $0.taskIdentifier = nil }
                    if row.phase == .removing { try remove(row.id) }
                case .keyPersisted, .protectedDataUnavailable: break
                }
                return
            }
            guard row.phase != .ready else { return }
            switch event.kind {
            case .protectedDataUnavailable:
                restored = false; transport.pause(event.operation); onError?(OfflineFilmError.deviceLocked)
            case .destination(let url):
                let path = try OfflineFilmPackageLocation.relative(url, container: container)
                guard row.packagePath == nil || row.packagePath == path else { throw OfflineFilmError.invalidAsset }
                _ = try catalogue.update(row) { $0.packagePath = path; $0.taskIdentifier = event.taskIdentifier }
            case .keyPersisted:
                guard try transport.hasUsableKey(row) else { throw OfflineFilmError.missingKey }
                _ = try catalogue.update(row) { $0.keyPersisted = true }
                finishIfReady(event.operation)
            case .completed:
                guard row.packagePath != nil else { throw OfflineFilmError.invalidAsset }
                _ = try catalogue.update(row) { $0.phase = .verifying }
                verify(event.operation)
            case .failed: fail(event.operation)
            }
            onChange?()
        } catch OfflineFilmError.deviceLocked {
            restored = false; transport.pause(event.operation); onError?(OfflineFilmError.deviceLocked)
        } catch {
            if !stopped && isCurrent() { fail(event.operation); onError?(error) }
        }
    }

    private func verify(_ operation: UUID) {
        guard verifications[operation] == nil else { return }
        verifications[operation] = Task { [weak self] in
            guard let self else { return }
            defer { verifications[operation] = nil }
            do {
                guard let row = try current(operation), row.phase == .verifying, let path = row.packagePath else { return }
                let url = try OfflineFilmPackageLocation.resolve(path, container: container)
                try await transport.verifyPackage(row, at: url)
                try check(); try Task.checkCancellation()
                guard let latest = try current(operation), latest.phase == .verifying, latest.packagePath == path else { return }
                _ = try catalogue.update(latest) { $0.mediaVerified = true }
                finishIfReady(operation)
            } catch OfflineFilmError.deviceLocked {
                restored = false; onError?(OfflineFilmError.deviceLocked)
            } catch {
                if !stopped && isCurrent() { fail(operation); onError?(error) }
            }
        }
    }

    private func finishIfReady(_ operation: UUID) {
        do {
            guard let row = try current(operation), row.phase == .verifying,
                  row.mediaVerified, row.keyPersisted else { return }
            guard try transport.hasUsableKey(row) else { throw OfflineFilmError.missingKey }
            _ = try catalogue.update(row) { $0.phase = .ready; $0.taskIdentifier = nil }
            onChange?()
        } catch OfflineFilmError.deviceLocked { restored = false; onError?(OfflineFilmError.deviceLocked) }
        catch { fail(operation); onError?(error) }
    }

    private func fail(_ operation: UUID) {
        guard !stopped, isCurrent() else { return }
        do {
            if let row = try current(operation), row.phase != .removing {
                _ = try catalogue.update(row) { $0.phase = .failed; $0.keyPersisted = false }
                if transport.cancel(operation), let failed = try current(operation) {
                    _ = try catalogue.update(failed) { $0.taskIdentifier = nil }
                }
            }
        } catch { onError?(error) }
        onChange?()
    }
}
