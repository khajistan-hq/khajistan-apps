import CryptoKit
import Foundation

/// Local storage format, not a server protocol or permission to read offline. Only an approved
/// future provider may authenticate this manifest. A hash supplied alongside bytes proves no rights.
struct RRPackageManifest: Codable, Equatable, Sendable {
    struct Page: Codable, Equatable, Sendable {
        let identifier: String
        let byteCount: Int
        let sha256: Data
    }
    let issue: String
    let version: String
    /// Reading order is explicit; array positions are the only on-disk page names.
    let pages: [Page]
}

struct RRPackageLimits: Sendable {
    var pageBytes = 20 * 1024 * 1024
    var packageBytes = 500 * 1024 * 1024
    var totalDiskBytes = 1024 * 1024 * 1024
    var pages = 5000
    var metadataBytes = 4 * 1024 * 1024
    var filesystemEntries = 20000
}

enum RRPackageError: Error, Equatable { case invalidManifest, storage, staleOperation, inactiveSession, incomplete, immutable }

/// Every object for one account generation must share this fence. Logout waits for an in-flight
/// transaction and then prevents further work; no key or plaintext is returned by this component.
final class RRPackageSession: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var active = true
    func invalidate() { lock.lock(); defer { lock.unlock() }; active = false }
}

private enum RRPackageLocks {
    static let lock = NSLock()
    private static var values: [String: NSLock] = [:]
    static func get(_ path: String) -> NSLock {
        lock.lock(); defer { lock.unlock() }
        if let value = values[path] { return value }
        let value = NSLock(); values[path] = value; return value
    }
}

/// Resumable encrypted staging only. Deliberately has NO page-read/export API, URL fetcher,
/// entitlement implementation or connection to ReadingStore. A complete package is not a licence.
/// One app process owns the directory; extensions/multiple processes are unsupported.
final class RROfflinePackageStore: @unchecked Sendable {
    enum Checkpoint { case beforeInitialManifest, afterRemovalMarker, afterPageDirectoryRemoval }
    struct Handle: Equatable, Sendable {
        let id: UUID
        let operation: UUID
    }
    struct Status: Equatable, Sendable {
        let handle: Handle
        let manifest: RRPackageManifest
        let complete: Bool
        let missingPages: [Int]
    }
    private struct Header: Codable {
        let operation: UUID
        let manifest: RRPackageManifest
        var complete: Bool
        var removing: Bool
    }
    private struct Context: Codable {
        let format: Int
        let account: String
        let device: UUID
        let package: UUID
        let operation: UUID?
        let manifest: Data?
        let page: Int?
    }
    private let root: URL
    private let account: String
    private let device: UUID
    private let key: SymmetricKey
    private let session: RRPackageSession
    private let limits: RRPackageLimits
    private let lock: NSLock
    // Controlled crash/storage fixtures only; no default behavior or production implementation.
    private let interrupt: ((Checkpoint) throws -> Void)?

    /// Caller supplies an app-private, backup-excluded Library location and device-only key.
    /// There is no default runtime/key source until licensed delivery has an approved contract.
    init(root: URL, account: String, device: UUID, key: SymmetricKey,
         session: RRPackageSession, limits: RRPackageLimits = RRPackageLimits(),
         interrupt: ((Checkpoint) throws -> Void)? = nil) throws {
        guard root.isFileURL, !account.isEmpty, account.utf8.count <= 1024, key.bitCount == 256,
              limits.pageBytes > 0, limits.pageBytes <= 100 * 1024 * 1024,
              limits.packageBytes > 0, limits.totalDiskBytes > limits.metadataBytes,
              limits.pages > 0, limits.pages <= 10000,
              limits.metadataBytes > 0, limits.metadataBytes <= 8 * 1024 * 1024,
              limits.filesystemEntries > 0 else { throw RRPackageError.storage }
        let path = root.standardizedFileURL
        guard path.resolvingSymlinksInPath().path == path.path else { throw RRPackageError.storage }
        self.root = path; self.account = account; self.device = device; self.key = key
        self.session = session; self.limits = limits; self.interrupt = interrupt
        lock = RRPackageLocks.get(path.path)
    }

    /// Repeated requests with the same local ID and manifest resume the existing operation.
    /// A removed ID receives a fresh operation, fencing every callback from the old attempt.
    func begin(id: UUID, manifest: RRPackageManifest) throws -> Handle {
        try transaction {
            try validate(manifest)
            if FileManager.default.fileExists(atPath: index(id).path) {
                let held = try header(id)
                guard held.manifest == manifest, !held.removing else { throw RRPackageError.staleOperation }
                return Handle(id: id, operation: held.operation)
            }
            // The root manifest is committed BEFORE any page folder exists. A failed first
            // write can retry; an unexplained folder without its manifest is never adopted.
            guard !FileManager.default.fileExists(atPath: folder(id).path) else { throw RRPackageError.storage }
            let held = Header(operation: UUID(), manifest: manifest, complete: false, removing: false)
            try saveHeader(held, id: id)
            return Handle(id: id, operation: held.operation)
        }
    }

    /// Untrusted bytes are checked BEFORE encryption/write. Pages from a completed version are
    /// immutable; changing a version requires a separate ID. No raw JPEG/PDF ever goes to disk.
    func stage(_ bytes: Data, page: Int, in handle: Handle) throws {
        try transaction {
            let held = try current(handle)
            guard !held.complete else { throw RRPackageError.immutable }
            guard held.manifest.pages.indices.contains(page), matches(bytes, held.manifest.pages[page]) else {
                throw RRPackageError.invalidManifest
            }
            let context = try pageContext(handle, digest: Data(SHA256.hash(data: encode(held.manifest))), page: page)
            let sealed = try seal(bytes, context: context)
            try write(sealed, to: pageFile(handle.id, page))
        }
    }

    /// Reopens after restart and checks actual files, including after an interrupted atomic write.
    /// Corrupt/missing pages are reported for an explicit retry; no automatic network/spend occurs.
    func status(id: UUID) throws -> Status {
        try transaction {
            let held = try header(id)
            guard !held.removing else { throw RRPackageError.staleOperation }
            let handle = Handle(id: id, operation: held.operation)
            let missing = missingPages(handle, header: held)
            return Status(handle: handle, manifest: held.manifest,
                          complete: held.complete && missing.isEmpty, missingPages: missing)
        }
    }

    /// Publish completeness last, only after every ordered page authenticates and matches its
    /// expected digest. This flag never represents access, ownership, validity or legal clearance.
    func finish(_ handle: Handle) throws {
        try transaction {
            var held = try current(handle)
            guard missingPages(handle, header: held).isEmpty else { throw RRPackageError.incomplete }
            if held.complete { return }
            held.complete = true
            try saveHeader(held, id: handle.id)
        }
    }

    /// Persist the tombstone first. A partial deletion remains nonresumable, and cleanup can be
    /// retried with this operation without deleting any replacement. Nothing outside our ID folder.
    func remove(_ handle: Handle) throws {
        try transaction {
            var held = try header(handle.id)
            guard held.operation == handle.operation else { throw RRPackageError.staleOperation }
            if !held.removing { held.removing = true; try saveHeader(held, id: handle.id, reserve: false) }
            try interrupt?(.afterRemovalMarker)
            try safe(folder(handle.id))
            if FileManager.default.fileExists(atPath: folder(handle.id).path) {
                try FileManager.default.removeItem(at: folder(handle.id))
            }
            try interrupt?(.afterPageDirectoryRemoval)
            // Deletion intent lives OUTSIDE the page folder and is removed last. If recursive
            // cleanup stops halfway, the same operation can safely retry after app restart.
            try FileManager.default.removeItem(at: index(handle.id))
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        session.lock.lock(); defer { session.lock.unlock() }
        guard session.active else { throw RRPackageError.inactiveSession }
        lock.lock(); defer { lock.unlock() }
        try safe(root)
        return try body()
    }
    private func current(_ handle: Handle) throws -> Header {
        let held = try header(handle.id)
        guard held.operation == handle.operation, !held.removing else { throw RRPackageError.staleOperation }
        return held
    }
    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func index(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".sealed") }
    private func pageFile(_ id: UUID, _ page: Int) -> URL { folder(id).appendingPathComponent("\(page).sealed") }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        // JSON sorted keys is deterministic for AAD; separate fields prevent delimiter ambiguity.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func manifestContext(_ id: UUID) throws -> Data {
        try encode(Context(format: 1, account: account, device: device, package: id,
                           operation: nil, manifest: nil, page: nil))
    }
    private func pageContext(_ handle: Handle, digest: Data, page: Int) throws -> Data {
        try encode(Context(format: 1, account: account, device: device, package: handle.id,
                           operation: handle.operation, manifest: digest, page: page))
    }
    private func seal(_ data: Data, context: Data) throws -> Data {
        guard let bytes = try AES.GCM.seal(data, using: key, authenticating: context).combined else {
            throw RRPackageError.storage
        }
        return bytes
    }
    private func header(_ id: UUID) throws -> Header {
        do {
            let data = try read(index(id), maximum: limits.metadataBytes)
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: manifestContext(id))
            let held = try JSONDecoder().decode(Header.self, from: clear)
            try validate(held.manifest)
            return held
        } catch { throw RRPackageError.storage }
    }
    private func saveHeader(_ header: Header, id: UUID, reserve: Bool = true) throws {
        let bytes = try seal(encode(header), context: manifestContext(id))
        guard bytes.count <= limits.metadataBytes else { throw RRPackageError.invalidManifest }
        let initial = !FileManager.default.fileExists(atPath: index(id).path)
        try write(bytes, to: index(id), reserve: reserve, beforeWrite: {
            if initial { try self.interrupt?(.beforeInitialManifest) }
        })
    }
    private func validate(_ manifest: RRPackageManifest) throws {
        guard [manifest.issue, manifest.version].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
              !manifest.pages.isEmpty, manifest.pages.count <= limits.pages,
              Set(manifest.pages.map(\.identifier)).count == manifest.pages.count else { throw RRPackageError.invalidManifest }
        var total = 0
        for page in manifest.pages {
            guard !page.identifier.isEmpty, page.identifier.utf8.count <= 512,
                  page.sha256.count == 32, page.byteCount > 0, page.byteCount <= limits.pageBytes,
                  page.byteCount <= limits.packageBytes - total else { throw RRPackageError.invalidManifest }
            total += page.byteCount
        }
    }
    private func matches(_ bytes: Data, _ page: RRPackageManifest.Page) -> Bool {
        bytes.count == page.byteCount && Data(SHA256.hash(data: bytes)) == page.sha256
    }
    private func missingPages(_ handle: Handle, header: Header) -> [Int] {
        guard let manifest = try? encode(header.manifest) else { return Array(header.manifest.pages.indices) }
        let digest = Data(SHA256.hash(data: manifest))
        return header.manifest.pages.indices.filter { page in
            do {
                let data = try read(pageFile(handle.id, page), maximum: header.manifest.pages[page].byteCount + 28)
                let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                                            authenticating: pageContext(handle, digest: digest, page: page))
                return !matches(clear, header.manifest.pages[page])
            } catch { return true }
        }
    }
    private func safe(_ url: URL) throws {
        let path = url.standardizedFileURL
        guard (path.path == root.path || path.path.hasPrefix(root.path + "/")),
              path.resolvingSymlinksInPath().path == path.path else { throw RRPackageError.storage }
    }
    private func read(_ url: URL, maximum: Int) throws -> Data {
        try safe(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 28, size <= maximum else { throw RRPackageError.storage }
        return try Data(contentsOf: url)
    }
    private func diskUsage() throws -> (bytes: Int, entries: Int) {
        guard FileManager.default.fileExists(atPath: root.path) else { return (0, 0) }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var failed = false
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            errorHandler: { _, _ in failed = true; return false }) else { throw RRPackageError.storage }
        var bytes = 0, entries = 0
        for case let url as URL in walker {
            entries += 1
            guard entries <= limits.filesystemEntries else { throw RRPackageError.storage }
            try safe(url)
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw RRPackageError.storage }
            if values.isRegularFile == true {
                guard let size = values.fileSize, size >= 0, size <= limits.totalDiskBytes - bytes else { throw RRPackageError.storage }
                bytes += size
            } else if values.isDirectory != true { throw RRPackageError.storage }
        }
        guard !failed else { throw RRPackageError.storage }
        return (bytes, entries)
    }
    private func write(_ bytes: Data, to url: URL, reserve: Bool = true,
                       beforeWrite: (() throws -> Void)? = nil) throws {
        try safe(url)
        // Includes all packages/partials plus atomic replacement headroom. Never evict a package
        // silently to make space, and never delete unrelated user data to satisfy a storage limit.
        let usage = try diskUsage()
        let parent = url.deletingLastPathComponent()
        let newFolder = parent.path == root.path || FileManager.default.fileExists(atPath: parent.path) ? 0 : 1
        let newFile = FileManager.default.fileExists(atPath: url.path) ? 0 : 1
        // Keep room for one tombstone even when the storage budget is otherwise exhausted.
        let spare = reserve ? limits.metadataBytes : 0
        guard usage.bytes <= limits.totalDiskBytes - spare,
              bytes.count <= limits.totalDiskBytes - spare - usage.bytes,
              usage.entries + newFolder + newFile + 1 <= limits.filesystemEntries else { throw RRPackageError.storage }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(tvOS)
        options.insert(.completeFileProtection)
        #endif
        try beforeWrite?()
        try bytes.write(to: url, options: options)
    }
}
