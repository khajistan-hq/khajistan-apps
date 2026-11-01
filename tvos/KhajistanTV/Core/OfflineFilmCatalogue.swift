import CryptoKit
import Foundation

/// Private local metadata, never proof of entitlement. Playback must also validate the
/// device-bound Keychain/FairPlay record. Signed URLs, tokens and key blobs do not belong here.
struct OfflineFilmLibraryRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case downloading, paused, verifying, ready, failed, removing }
    let id: UUID
    // Assigned by the catalogue on insert, even if an id is reused. Callbacks carry both.
    var operation: UUID = UUID()
    var revision: UUID = UUID()
    let grant: OfflineFilmGrant
    let keyIdentifier: String
    let title: String
    var phase: Phase
    var taskIdentifier: Int?
    /// Relative to the app container; the system-owned HLS package is never moved.
    var packagePath: String?
    var mediaVerified = false
    var keyPersisted = false

    func validate(account: String, device: UUID) throws {
        try grant.validate(account: account, device: device, film: grant.filmHandle, version: grant.assetVersion)
        guard !title.isEmpty, title.utf8.count <= 1024,
              let key = URL(string: keyIdentifier), key.scheme == "skd",
              (2...200).contains(keyIdentifier.utf8.count),
              !keyIdentifier.contains(where: { $0.isWhitespace }),
              taskIdentifier.map({ $0 >= 0 }) ?? true,
              packagePath.map(OfflineFilmPackageLocation.isValid) ?? true,
              !mediaVerified || packagePath != nil,
              phase != .ready || (mediaVerified && keyPersisted && taskIdentifier == nil) else {
            throw OfflineFilmError.invalidAsset
        }
    }
}

/// All catalogues owned by one signed-in session share this fence. Invalidation waits for any
/// current transaction, then prevents reads and writes, including same-account late callbacks.
final class OfflineFilmLibrarySession: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var active = true
    func invalidate() { lock.lock(); defer { lock.unlock() }; active = false }
}

/// Background URLSession delegates and the foreground UI run in the app process. No extension
/// or other process may write this index. Distinct catalogue objects share its transaction lock.
private enum OfflineFilmIndexLocks {
    static let registryLock = NSLock()
    private static var locks: [String: NSLock] = [:]
    static func get(_ path: String) -> NSLock {
        registryLock.lock(); defer { registryLock.unlock() }
        if let lock = locks[path] { return lock }
        let lock = NSLock(); locks[path] = lock; return lock
    }
}

/// Only AVFoundation-provided .movpkg directories beneath Library can be recorded. This is
/// containment, not a DRM check. The driver must independently validate protected content.
enum OfflineFilmPackageLocation {
    static func isValid(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.first == "Library" && path.hasSuffix(".movpkg")
            && !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
            && !path.contains("\\") && !path.contains("\0")
    }

    static func relative(_ url: URL, container: URL) throws -> String {
        guard url.isFileURL, container.isFileURL else { throw OfflineFilmError.invalidAsset }
        let root = container.standardizedFileURL.resolvingSymlinksInPath()
        let file = url.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw OfflineFilmError.invalidAsset }
        let path = String(file.path.dropFirst(root.path.count + 1))
        guard isValid(path), file.resolvingSymlinksInPath().path == file.path else {
            throw OfflineFilmError.invalidAsset
        }
        return path
    }

    static func resolve(_ path: String, container: URL, mustExist: Bool = true) throws -> URL {
        guard isValid(path), container.isFileURL else { throw OfflineFilmError.invalidAsset }
        let root = container.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(path, isDirectory: true)
        guard file.resolvingSymlinksInPath().path == file.path else { throw OfflineFilmError.invalidAsset }
        if mustExist {
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw OfflineFilmError.invalidAsset }
        }
        return file
    }
}

/// One encrypted, atomic index per account/device. Corruption or wrong keys fail closed; they
/// never silently overwrite an existing library. Serialized updates prevent lost completions.
final class OfflineFilmCatalogue: @unchecked Sendable {
    private struct Envelope: Codable {
        let version: Int
        let records: [OfflineFilmLibraryRecord]
    }
    private let folder: URL
    private let account: String
    private let device: UUID
    private let key: SymmetricKey
    private let maximumEntries: Int
    private let maximumBytes: Int
    private let lock: NSLock
    private let session: OfflineFilmLibrarySession

    init(folder: URL, account: String, device: UUID, key: SymmetricKey,
         session: OfflineFilmLibrarySession,
         maximumEntries: Int = 512, maximumBytes: Int = 4 * 1024 * 1024) throws {
        guard folder.isFileURL, !account.isEmpty, key.bitCount == 256,
              maximumEntries > 0, maximumBytes > 0 else { throw OfflineFilmError.storage }
        self.folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        self.lock = OfflineFilmIndexLocks.get(self.folder.path)
        self.session = session
        self.account = account; self.device = device; self.key = key
        self.maximumEntries = maximumEntries; self.maximumBytes = maximumBytes
    }

    var indexURL: URL { folder.appendingPathComponent("library-v1.sealed") }
    private var context: Data { Data("khajistan.offline-library.v1|\(account)|\(device.uuidString)".utf8) }

    func all() throws -> [OfflineFilmLibraryRecord] {
        try begin(); defer { end() }
        return try readLocked()
    }

    @discardableResult
    func insert(_ input: OfflineFilmLibraryRecord) throws -> OfflineFilmLibraryRecord {
        try begin(); defer { end() }
        var record = input
        record.operation = UUID(); record.revision = UUID()
        guard record.phase == .downloading, record.packagePath == nil,
              !record.mediaVerified, !record.keyPersisted else { throw OfflineFilmError.invalidGrant }
        var records = try readLocked()
        guard !records.contains(where: { $0.id == record.id || $0.grant.entitlementID == record.grant.entitlementID }) else {
            throw OfflineFilmError.invalidGrant
        }
        records.append(record)
        try writeLocked(records)
        return record
    }

    /// Completion callbacks may update an existing operation, never recreate a removed one.
    @discardableResult
    func update(_ expected: OfflineFilmLibraryRecord,
                _ change: (inout OfflineFilmLibraryRecord) throws -> Void) throws -> OfflineFilmLibraryRecord? {
        try begin(); defer { end() }
        var records = try readLocked()
        guard let index = records.firstIndex(where: { $0.id == expected.id }),
              records[index] == expected else { return nil }
        let original = records[index]
        try change(&records[index])
        guard records[index].id == original.id, records[index].grant == original.grant,
              records[index].keyIdentifier == original.keyIdentifier,
              records[index].operation == original.operation,
              records[index].revision == original.revision,
              Self.permits(original.phase, records[index].phase) else { throw OfflineFilmError.invalidGrant }
        records[index].revision = UUID()
        try writeLocked(records)
        return records[index]
    }

    func remove(_ expected: OfflineFilmLibraryRecord) throws {
        try begin(); defer { end() }
        try writeLocked(readLocked().filter { $0.id != expected.id || $0.operation != expected.operation })
    }

    private func begin() throws {
        session.lock.lock()
        guard session.active else { session.lock.unlock(); throw OfflineFilmError.wrongAccount }
        lock.lock()
    }
    private func end() { lock.unlock(); session.lock.unlock() }

    private static func permits(_ old: OfflineFilmLibraryRecord.Phase, _ new: OfflineFilmLibraryRecord.Phase) -> Bool {
        if old == new { return true }
        if old == .removing { return false }
        switch (old, new) {
        case (.downloading, .paused), (.paused, .downloading),
             (.downloading, .verifying), (.paused, .verifying), (.verifying, .ready): return true
        case (_, .failed), (_, .removing): return true
        default: return false
        }
    }

    private func readLocked() throws -> [OfflineFilmLibraryRecord] {
        do {
            let values = try indexURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= maximumBytes,
                  indexURL.resolvingSymlinksInPath().path == indexURL.path else { throw OfflineFilmError.storage }
            let bytes = try Data(contentsOf: indexURL)
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key, authenticating: context)
            let envelope = try PropertyListDecoder().decode(Envelope.self, from: clear)
            guard envelope.version == 1 else { throw OfflineFilmError.storage }
            try validate(envelope.records)
            return envelope.records
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        } catch { throw OfflineFilmError.storage }
    }

    private func validate(_ records: [OfflineFilmLibraryRecord]) throws {
        guard records.count <= maximumEntries,
              Set(records.map(\.id)).count == records.count,
              Set(records.map { $0.grant.entitlementID }).count == records.count else { throw OfflineFilmError.storage }
        try records.forEach { try $0.validate(account: account, device: device) }
    }

    private func writeLocked(_ records: [OfflineFilmLibraryRecord]) throws {
        try validate(records)
        // Refuse path substitution rather than following a symlink to unrelated user files.
        guard folder.resolvingSymlinksInPath().path == folder.path,
              indexURL.resolvingSymlinksInPath().path == indexURL.path else { throw OfflineFilmError.storage }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let bytes = try encoder.encode(Envelope(version: 1, records: records))
        guard let sealed = try AES.GCM.seal(bytes, using: key, authenticating: context).combined,
              sealed.count <= maximumBytes else { throw OfflineFilmError.storage }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var directory = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(tvOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        // Protection is applied to the temporary file before atomic replacement. No fallible
        // operation follows the commit, so a protection error cannot masquerade as a failed save.
        try sealed.write(to: indexURL, options: options)
    }
}
