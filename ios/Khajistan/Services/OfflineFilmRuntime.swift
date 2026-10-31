import AVFoundation
import CryptoKit
import Foundation
import Observation
import Security
import Network
import UIKit

/// Composition boundary for a provisioned provider. There is deliberately no default provider,
/// remote flag, certificate download or production activation. App launch must supply the same
/// approved configuration before routing background events. Catalyst requires separate approval.
@MainActor @Observable
final class OfflineFilmRuntime {
    static private(set) var installed: OfflineFilmRuntime?
    private(set) var rows: [OfflineFilmLibraryRecord] = []
    private(set) var errorMessage: String?
    private(set) var active = true
    let library: OfflineFilmLibrary
    let backgroundIdentifier: String
    private let driver: OfflineHLSDownloadDriver
    private let scope: OfflineFilmAccountScope
    private let owner = UUID()
    private let device: UUID
    private let certificate: Data
    private let container: URL
    private var playback: OfflineProtectedPlayback?
    private var backgroundCompletion: (() -> Void)?
    private var backgroundDrained = false
    private let network = NWPathMonitor()
    private var reconciliationSchedule = OfflineReconciliationSchedule()
    private var restored = false
    private var reconciliation: Task<Void, Never>?
    private var retryWakeup: Task<Void, Never>?
    private var unlockObserver: NSObjectProtocol?

    init(provider: any OfflineFilmAuthorizing, licenses: any OfflineFairPlayLicenseService,
         approvedHosts: Set<String>, certificate: Data, scope: OfflineFilmAccountScope,
         catalystValidated: Bool = false) throws {
        #if targetEnvironment(macCatalyst)
        guard catalystValidated else { throw OfflineFilmError.unavailable }
        #endif
        guard Self.installed?.active != true, !certificate.isEmpty, !approvedHosts.isEmpty else { throw OfflineFilmError.unavailable }
        guard let account = scope.accountID, scope.usable else { throw OfflineFilmError.wrongAccount }
        let identity = try OfflineFilmDeviceStore.load()
        device = identity.device; self.scope = scope; self.certificate = certificate
        container = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
        let name = SHA256.hash(data: Data((account + "|" + device.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
        backgroundIdentifier = "com.khajistan.archive.offline-hls.v1." + name
        let folder = container.appendingPathComponent("Library/Application Support/ProtectedFilms/" + name, isDirectory: true)
        let session = OfflineFilmLibrarySession()
        let catalogue = try OfflineFilmCatalogue(folder: folder, account: account, device: device,
                                                 key: identity.key, session: session)
        let generation = scope.generation
        driver = try OfflineHLSDownloadDriver(identifier: backgroundIdentifier, account: account, device: device,
            certificate: certificate, service: licenses, scope: scope, approvedHosts: approvedHosts, container: container)
        library = OfflineFilmLibrary(catalogue: catalogue, session: session, provider: provider, transport: driver,
            account: account, device: device, container: container, approvedHosts: approvedHosts,
            isCurrent: { scope.accepts(account: account, generation: generation) })
        library.onChange = { [weak self] in self?.refresh() }
        library.onError = { [weak self] error in self?.errorMessage = error.localizedDescription }
        driver.onBackgroundEventsFinished = { [weak self] in
            guard let self else { return }
            backgroundDrained = true; finishBackgroundEvents()
        }
        scope.observeSession(owner: owner) { [weak self] in self?.stop() }
        Self.installed = self
        network.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkChanged(connected) }
        }
        network.start(queue: DispatchQueue(label: "com.khajistan.offline-network"))
        unlockObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, active else { return }
                    do { try await restore() } catch { errorMessage = "Protected films could not be checked. Try again." }
                }
            }
    }

    func restore() async throws { try await library.restore(); restored = true; refresh() }

    func checkAccessAfterReconnection() {
        guard active else { return }
        reconciliationSchedule.request(at: ProcessInfo.processInfo.systemUptime)
        driveReconciliation()
    }

    private func driveReconciliation() {
        guard active, restored, reconciliation == nil else { return }
        guard let rows = try? library.records(), !rows.isEmpty else { return }
        retryWakeup?.cancel(); retryWakeup = nil
        let now = ProcessInfo.processInfo.systemUptime
        guard let token = reconciliationSchedule.begin(at: now) else {
            guard let next = reconciliationSchedule.next else { return }
            retryWakeup = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0.1, next - now))) } catch { return }
                guard let self else { return }; retryWakeup = nil; driveReconciliation()
            }
            return
        }
        reconciliation = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            do { try await library.reconcile(); succeeded = true }
            catch {
                // A transport outage never extends a license or erases a purchase. The
                // playback boundary independently checks the existing device key/expiry.
                if active { errorMessage = "Offline access could not be refreshed. Existing device limits still apply." }
            }
            reconciliationSchedule.finish(token, succeeded: succeeded, at: ProcessInfo.processInfo.systemUptime)
            reconciliation = nil; driveReconciliation()
        }
    }

    private func networkChanged(_ value: Bool) {
        guard active else { return }
        reconciliationSchedule.network(value, at: ProcessInfo.processInfo.systemUptime)
        if !value { retryWakeup?.cancel(); retryWakeup = nil }
        driveReconciliation()
    }

    /// Forward UIApplicationDelegate's matching background-session callback here. Completion
    /// runs only after delegate events have durably updated the index, never on a guessed timer.
    func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) -> Bool {
        guard active, identifier == backgroundIdentifier else { return false }
        backgroundCompletion = completion; finishBackgroundEvents(); return true
    }

    func play(_ id: UUID) async throws -> OfflineProtectedPlayback {
        guard active, let row = try library.records().first(where: { $0.id == id }),
              row.phase == .ready, let path = row.packagePath, try driver.hasUsableKey(row) else {
            throw OfflineFilmError.missingKey
        }
        let url = try OfflineFilmPackageLocation.resolve(path, container: container)
        playback?.stop()
        let pending = try OfflineProtectedPlayback(record: row, url: url, device: device,
            certificate: certificate, scope: scope)
        playback = pending
        do {
            try await pending.prepare()
            guard active, playback === pending,
                  try library.records().contains(where: { $0.id == row.id && $0.operation == row.operation && $0.phase == .ready }) else {
                throw OfflineFilmError.wrongAccount
            }
            return pending
        } catch { pending.stop(); throw error }
    }

    func remove(_ id: UUID) throws {
        if playback?.recordID == id { playback?.stop(); playback = nil }
        try library.remove(id)
    }

    func stop() {
        guard active else { return }; active = false
        network.cancel(); reconciliation?.cancel(); reconciliation = nil
        retryWakeup?.cancel(); retryWakeup = nil; reconciliationSchedule.stop()
        if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver); self.unlockObserver = nil }
        playback?.stop(); playback = nil; library.stop(); rows = []
        scope.removeObserver(owner: owner)
        if Self.installed === self { Self.installed = nil }
        backgroundCompletion?(); backgroundCompletion = nil
    }

    private func refresh() {
        guard active else { return }
        do {
            rows = try library.records()
            if let playback, !rows.contains(where: { $0.id == playback.recordID && $0.phase == .ready }) {
                playback.stop(); self.playback = nil
            }
            driveReconciliation()
        } catch { playback?.stop(); playback = nil; rows = []; errorMessage = error.localizedDescription }
    }

    private func finishBackgroundEvents() {
        guard backgroundDrained, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil; backgroundDrained = false; completion()
    }
}

/// Cold launch still needs the approved provider bootstrap to install/restore its runtime;
/// this delegate routes only an already provisioned account's exact stable session identifier.
final class OfflineFilmBackgroundDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if let runtime = OfflineFilmRuntime.installed,
           runtime.handleBackgroundEvents(identifier: identifier, completion: completionHandler) { return }
        completionHandler()
    }
}

/// Private identity and catalogue encryption material. No iCloud sync, export, app group or
/// external credential is used. A locked/unreadable item fails closed rather than replacing it.
private enum OfflineFilmDeviceStore {
    struct Identity: Codable { let device: UUID; let bytes: Data; var key: SymmetricKey { SymmetricKey(data: bytes) } }
    static func load() throws -> Identity {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KJConfig.keychainService + ".offline-library.v1", kSecAttrAccount as String: "device"]
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &found)
        if status == errSecInteractionNotAllowed || status == errSecNotAvailable { throw OfflineFilmError.deviceLocked }
        if status == errSecSuccess, let data = found as? Data {
            let identity = try PropertyListDecoder().decode(Identity.self, from: data)
            guard identity.bytes.count == 32 else { throw OfflineFilmError.storage }; return identity
        }
        guard status == errSecItemNotFound else { throw OfflineFilmError.storage }
        let key = SymmetricKey(size: .bits256)
        let identity = Identity(device: UUID(), bytes: key.withUnsafeBytes { Data($0) })
        var item = query
        item[kSecValueData as String] = try PropertyListEncoder().encode(identity)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw OfflineFilmError.storage }
        return identity
    }
}

@MainActor
final class OfflineProtectedPlayback: Identifiable {
    private struct ReplayOnly: OfflineFairPlayLicenseService {
        func contentKeyContext(spc: Data, grant: OfflineFilmGrant, keyIdentifier: String) async throws -> Data {
            throw OfflineFilmError.needsConnection
        }
    }
    let recordID: UUID
    let id = UUID()
    let player = AVPlayer()
    private let record: OfflineFilmLibraryRecord
    private let media: AVURLAsset
    private let scope: OfflineFilmAccountScope
    private let generation: UUID
    private let observerID = UUID()
    private var keys: OfflineFairPlaySession!
    private var observation: NSKeyValueObservation?
    private var checkTask: Task<Void, Never>?
    private var stopped = false
    private var lastWallClock = Date()
    var onFailure: ((Error) -> Void)?

    init(record: OfflineFilmLibraryRecord, url: URL, device: UUID, certificate: Data,
         scope: OfflineFilmAccountScope) throws {
        self.record = record; recordID = record.id; self.scope = scope; generation = scope.generation
        player.allowsExternalPlayback = false
        media = AVURLAsset(url: url, options: [AVURLAssetAllowsCellularAccessKey: false,
            AVURLAssetAllowsExpensiveNetworkAccessKey: false, AVURLAssetAllowsConstrainedNetworkAccessKey: false])
        guard media.assetCache?.isPlayableOffline == true else { throw OfflineFilmError.invalidAsset }
        keys = try OfflineFairPlaySession(grant: record.grant, keyIdentifier: record.keyIdentifier,
            deviceID: device, certificate: certificate, service: ReplayOnly(), scope: scope,
            onFailure: { [weak self] error in self?.reject(error) }, onKeyPersisted: {})
        try keys.attach(to: media)
        scope.observeSession(owner: observerID) { [weak self] in self?.stop() }
    }

    func prepare() async throws {
        try check()
        let (protected, playable) = try await media.load(.hasProtectedContent, .isPlayable)
        try check(); try Task.checkCancellation()
        guard protected, playable, media.assetCache?.isPlayableOffline == true else { throw OfflineFilmError.invalidAsset }
        let item = AVPlayerItem(asset: media)
        // Choose only media selections present in the package. Never ask the offline player
        // to fetch a remote language variant simply because it matches the system locale.
        for characteristic in [AVMediaCharacteristic.audible, .legible] {
            if let group = try await media.loadMediaSelectionGroup(for: characteristic) {
                let available = media.assetCache?.mediaSelectionOptions(in: group) ?? []
                if let option = available.first { item.select(option, in: group) }
                else if group.allowsEmptySelection { item.select(nil, in: group) }
                else { throw OfflineFilmError.invalidAsset }
            }
        }
        try check(); player.replaceCurrentItem(with: item)
        observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { try check(); try keys.didBeginPlayback() } catch { reject(error) }
            }
        }
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                do { try check() } catch { reject(error); return }
            }
        }
    }

    func stop() {
        guard !stopped else { return }; stopped = true
        player.pause(); player.replaceCurrentItem(with: nil)
        observation?.invalidate(); observation = nil; checkTask?.cancel(); checkTask = nil
        keys?.stop(); scope.removeObserver(owner: observerID)
    }

    private func check() throws {
        let now = Date()
        guard !stopped, scope.accepts(account: record.grant.accountID, generation: generation) else { throw OfflineFilmError.wrongAccount }
        guard now >= lastWallClock else { throw OfflineFilmError.needsConnection }
        lastWallClock = now
        guard let stored = try OfflineFilmKeys.read(record.grant.entitlementID), stored.grant == record.grant,
              stored.keyIdentifier == record.keyIdentifier, !stored.key.isEmpty, stored.revoked != true else { throw OfflineFilmError.missingKey }
        switch stored.grant.access(at: now, firstPlayedAt: stored.firstPlayedAt, lastObservedAt: stored.lastObservedAt) {
        case .allowed: break
        case .reconnect: throw OfflineFilmError.needsConnection
        case .expired: throw OfflineFilmError.expired
        }
    }

    private func reject(_ error: Error) { stop(); onFailure?(error) }
}
