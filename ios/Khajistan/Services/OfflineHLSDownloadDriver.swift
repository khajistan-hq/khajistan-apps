import AVFoundation
import Foundation

/// This adapter is constructed only by an explicitly provisioned runtime. It does not read
/// vod-token, create a raw download, move the system HLS package or offer an export URL.
@MainActor
final class OfflineHLSDownloadDriver: NSObject, OfflineFilmDownloadTransport,
    @preconcurrency AVAssetDownloadDelegate {
    private struct Binding {
        let row: OfflineFilmLibraryRecord
        let task: AVAssetDownloadTask
        let keys: OfflineFairPlaySession
    }
    private struct ReplayOnly: OfflineFairPlayLicenseService {
        func contentKeyContext(spc: Data, grant: OfflineFilmGrant, keyIdentifier: String) async throws -> Data {
            throw OfflineFilmError.needsConnection
        }
    }
    private var session: AVAssetDownloadURLSession!
    private var bindings: [UUID: Binding] = [:]
    private var replayKeys: [UUID: OfflineFairPlaySession] = [:]
    private var terminal: Set<UUID> = []
    private var resumeAfterKey: Set<UUID> = []
    private var restored = false
    private var buffered: [(URLSessionTask, OfflineFilmDownloadEvent.Kind)] = []
    private var backgroundFinishedPending = false
    private let account: String
    private let device: UUID
    private let certificate: Data
    private let service: any OfflineFairPlayLicenseService
    private let scope: OfflineFilmAccountScope
    private let generation: UUID
    private let approvedHosts: Set<String>
    private let container: URL
    private var stopped = false
    var onEvent: ((OfflineFilmDownloadEvent) -> Void)?
    var onBackgroundEventsFinished: (() -> Void)?

    init(identifier: String, account: String, device: UUID, certificate: Data,
         service: any OfflineFairPlayLicenseService, scope: OfflineFilmAccountScope,
         approvedHosts: Set<String>, container: URL) throws {
        guard !identifier.isEmpty, !certificate.isEmpty, !approvedHosts.isEmpty,
              scope.accepts(account: account, generation: scope.generation) else { throw OfflineFilmError.unavailable }
        self.account = account; self.device = device; self.certificate = certificate
        self.service = service; self.scope = scope; generation = scope.generation
        self.approvedHosts = approvedHosts; self.container = container
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }

    func makeDownload(_ record: OfflineFilmLibraryRecord, asset: OfflineFilmAsset) async throws -> Int {
        try check(); try validate(record)
        try asset.validate(allowedHosts: approvedHosts)
        guard record.keyIdentifier == asset.keyIdentifier, bindings[record.operation] == nil else { throw OfflineFilmError.invalidAsset }
        let media = AVURLAsset(url: asset.manifest)
        let protected = try await media.load(.hasProtectedContent)
        try check(); try Task.checkCancellation()
        guard protected else { throw OfflineFilmError.invalidAsset }
        let config = AVAssetDownloadConfiguration(asset: media, title: record.title)
        // Keep the primary selection. Additional editions/audio downloads require an explicit
        // product/storage decision; the default auxiliary renditions must not multiply costs.
        config.auxiliaryContentConfigurations = []
        let task = session.makeAssetDownloadTask(downloadConfiguration: config)
        task.taskDescription = record.operation.uuidString
        do {
            let keys = try keySession(record, task: task.taskIdentifier, replayOnly: false)
            try keys.attach(to: media)
            bindings[record.operation] = Binding(row: record, task: task, keys: keys)
            return task.taskIdentifier
        } catch { task.cancel(); throw error }
    }

    func resume(_ operation: UUID) throws {
        try check()
        guard let binding = bindings[operation], !terminal.contains(operation) else { throw OfflineFilmError.invalidAsset }
        try validate(binding.row)
        let stored = try OfflineFilmKeys.read(binding.row.grant.entitlementID)
        if let stored {
            guard stored.grant == binding.row.grant, stored.keyIdentifier == binding.row.keyIdentifier, stored.revoked != true else {
                throw OfflineFilmError.invalidGrant
            }
        }
        guard binding.row.grant.access(at: Date(), firstPlayedAt: stored?.firstPlayedAt,
            lastObservedAt: stored?.lastObservedAt ?? binding.row.grant.issuedAt) == .allowed else {
            throw OfflineFilmError.needsConnection
        }
        resumeAfterKey.insert(operation)
        do { try binding.keys.prepareKey() }
        catch { resumeAfterKey.remove(operation); throw error }
    }

    func pause(_ operation: UUID) { resumeAfterKey.remove(operation); bindings[operation]?.task.suspend() }

    @discardableResult
    func cancel(_ operation: UUID) -> Bool {
        resumeAfterKey.remove(operation)
        replayKeys.removeValue(forKey: operation)?.stop()
        guard let binding = bindings[operation] else { return true }
        binding.keys.stop()
        if terminal.contains(operation) { bindings[operation] = nil; return true }
        binding.task.cancel()
        return false
    }

    func restore(_ records: [OfflineFilmLibraryRecord]) async throws -> Set<UUID> {
        try check()
        let listed = await session.allTasks
        try check()
        // Events can arrive during session recreation, before getAllTasks returns. Completed
        // tasks may no longer be listed; their retained delegate objects still bind to the row.
        var unique: [Int: URLSessionTask] = [:]
        (listed + buffered.map { $0.0 }).forEach { unique[$0.taskIdentifier] = $0 }
        var active: Set<UUID> = []
        for task in unique.values {
            guard let task = task as? AVAssetDownloadTask,
                  let description = task.taskDescription, let operation = UUID(uuidString: description),
                  let row = records.first(where: { $0.operation == operation &&
                      ($0.taskIdentifier == task.taskIdentifier ||
                       ($0.taskIdentifier == nil && $0.phase != .ready && $0.phase != .verifying)) }) else {
                task.cancel(); continue
            }
            do {
                try validate(row)
                try OfflineFilmAsset(manifest: task.urlAsset.url, keyIdentifier: row.keyIdentifier).validate(allowedHosts: approvedHosts)
                let keys = try keySession(row, task: task.taskIdentifier, replayOnly: false)
                try keys.attach(to: task.urlAsset)
                bindings[operation] = Binding(row: row, task: task, keys: keys)
                active.insert(operation)
                if row.phase == .removing || row.phase == .failed || row.taskIdentifier == nil { _ = cancel(operation) }
                else if row.phase == .paused { task.suspend() }
                else if row.phase == .downloading { try resume(operation) }
            } catch OfflineFilmError.deviceLocked { task.suspend(); throw OfflineFilmError.deviceLocked }
            catch { task.cancel() }
        }
        restored = true
        let events = buffered; buffered.removeAll()
        events.forEach { deliver($0.0, $0.1) }
        if backgroundFinishedPending { backgroundFinishedPending = false; onBackgroundEventsFinished?() }
        return active
    }

    func verifyPackage(_ record: OfflineFilmLibraryRecord, at url: URL) async throws {
        try check(); try validate(record)
        guard let path = record.packagePath,
              try OfflineFilmPackageLocation.resolve(path, container: container) == url else { throw OfflineFilmError.invalidAsset }
        let local = AVURLAsset(url: url, options: [AVURLAssetAllowsCellularAccessKey: false,
            AVURLAssetAllowsExpensiveNetworkAccessKey: false, AVURLAssetAllowsConstrainedNetworkAccessKey: false])
        guard local.assetCache?.isPlayableOffline == true else { throw OfflineFilmError.invalidAsset }
        let keys: OfflineFairPlaySession
        if let binding = bindings[record.operation] { keys = binding.keys }
        else {
            guard try hasUsableKey(record) else { throw OfflineFilmError.missingKey }
            keys = try keySession(record, task: record.taskIdentifier ?? -1, replayOnly: true)
            replayKeys[record.operation]?.stop(); replayKeys[record.operation] = keys
        }
        try keys.attach(to: local)
        let (protected, playable) = try await local.load(.hasProtectedContent, .isPlayable)
        try check(); try Task.checkCancellation()
        guard protected, playable, local.assetCache?.isPlayableOffline == true else { throw OfflineFilmError.invalidAsset }
    }

    func hasUsableKey(_ record: OfflineFilmLibraryRecord) throws -> Bool {
        try check(); try validate(record)
        guard let stored = try OfflineFilmKeys.read(record.grant.entitlementID),
              stored.grant == record.grant, stored.keyIdentifier == record.keyIdentifier,
              !stored.key.isEmpty, stored.revoked != true else { return false }
        return stored.grant.access(at: Date(), firstPlayedAt: stored.firstPlayedAt,
                                   lastObservedAt: stored.lastObservedAt) == .allowed
    }

    func deleteKey(_ record: OfflineFilmLibraryRecord) throws {
        try check()
        // Never delete a newer entitlement's key just because an old download was cancelled.
        if let stored = try OfflineFilmKeys.read(record.grant.entitlementID),
           stored.grant == record.grant, stored.keyIdentifier == record.keyIdentifier {
            try OfflineFilmKeys.delete(record.grant.entitlementID)
        }
    }

    func markRevoked(_ record: OfflineFilmLibraryRecord) throws {
        try check()
        bindings[record.operation]?.keys.stop(); replayKeys.removeValue(forKey: record.operation)?.stop()
        try OfflineFilmKeys.markRevoked(grant: record.grant, keyIdentifier: record.keyIdentifier)
    }

    func shutDown() {
        guard !stopped else { return }; stopped = true; onEvent = nil
        bindings.values.forEach { $0.keys.stop(); $0.task.cancel() }
        resumeAfterKey.removeAll()
        replayKeys.values.forEach { $0.stop() }; replayKeys.removeAll()
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        destination(assetDownloadTask, location)
    }

    // iOS 17 fallback. A package location alone is not successful task completion.
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        destination(assetDownloadTask, location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        deliver(task, error == nil ? .completed : .failed)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if !restored { backgroundFinishedPending = true }
        else { onBackgroundEventsFinished?() }
    }

    private func destination(_ task: AVAssetDownloadTask, _ url: URL) {
        deliver(task, .destination(url))
    }

    private func deliver(_ task: URLSessionTask, _ kind: OfflineFilmDownloadEvent.Kind) {
        guard !stopped else { return }
        if !restored { buffered.append((task, kind)); return }
        guard let binding = binding(task) else { return }
        switch kind {
        case .completed, .failed: terminal.insert(binding.row.operation)
        default: break
        }
        emit(binding.row.operation, task: task.taskIdentifier, kind: kind)
    }

    private func binding(_ task: URLSessionTask) -> Binding? {
        guard !stopped, let description = task.taskDescription, let op = UUID(uuidString: description),
              let binding = bindings[op], binding.task.taskIdentifier == task.taskIdentifier else { return nil }
        return binding
    }

    private func emit(_ op: UUID, task: Int, kind: OfflineFilmDownloadEvent.Kind) {
        guard !stopped, scope.accepts(account: account, generation: generation) else { return }
        onEvent?(OfflineFilmDownloadEvent(operation: op, taskIdentifier: task, kind: kind))
    }

    private func keySession(_ row: OfflineFilmLibraryRecord, task: Int, replayOnly: Bool) throws -> OfflineFairPlaySession {
        try OfflineFairPlaySession(grant: row.grant, keyIdentifier: row.keyIdentifier, deviceID: device,
            certificate: certificate, service: replayOnly ? ReplayOnly() : service, scope: scope,
            onFailure: { [weak self] error in
                let unavailable: Bool
                if case OfflineFilmError.deviceLocked = error { unavailable = true } else { unavailable = false }
                self?.emit(row.operation, task: task, kind: unavailable ? .protectedDataUnavailable : .failed)
            },
            onKeyPersisted: { [weak self] in
                guard let self else { return }
                emit(row.operation, task: task, kind: .keyPersisted)
                // The callback can synchronously fail/cancel this operation. Resume only if
                // the library still owns it after recording the key, and pause was not pressed.
                if resumeAfterKey.remove(row.operation) != nil, !stopped,
                   scope.accepts(account: account, generation: generation),
                   let binding = bindings[row.operation], binding.task.taskIdentifier == task,
                   !terminal.contains(row.operation) { binding.task.resume() }
            })
    }

    private func check() throws {
        guard !stopped, scope.accepts(account: account, generation: generation) else { throw OfflineFilmError.wrongAccount }
    }

    private func validate(_ row: OfflineFilmLibraryRecord) throws {
        try row.validate(account: account, device: device)
    }
}
