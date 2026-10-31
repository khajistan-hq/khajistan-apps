import CryptoKit
import Foundation

/// A bounded performance cache, NOT an offline entitlement. Every read still requires an unexpired
/// page-server authorization in ReadingStore. AES-GCM keeps raw scans out of on-disk files.
/// The device-only key is supplied by the app's Keychain layer. No plaintext fallback exists.
final class RRProtectedPageCache: @unchecked Sendable {
    private struct Entry: Codable { let writtenAt: Date; let bytes: Data }
    let folder: URL
    private let key: SymmetricKey
    private let budget: Int
    private let lifetime: TimeInterval
    private let lock = NSLock()

    init(folder: URL, key: SymmetricKey, budget: Int = 400 * 1024 * 1024,
         lifetime: TimeInterval = 3 * 24 * 3600) {
        self.folder = folder; self.key = key; self.budget = max(0, budget); self.lifetime = lifetime
    }

    func file(_ path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest + ".sealed")
    }

    func read(_ path: String, now: Date = Date()) -> Data? {
        lock.lock(); defer { lock.unlock() }
        let url = file(path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink != true, let count = size.fileSize, count <= 30 * 1024 * 1024,
              let sealed = try? Data(contentsOf: url),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let clear = try? AES.GCM.open(box, using: key, authenticating: Data(path.utf8)),
              let entry = try? PropertyListDecoder().decode(Entry.self, from: clear),
              now >= entry.writtenAt, now.timeIntervalSince(entry.writtenAt) < lifetime else { return nil }
        return entry.bytes
    }

    @discardableResult
    func write(_ data: Data, _ path: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { return false }
        do {
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let clear = try encoder.encode(Entry(writtenAt: now, bytes: data))
            guard let sealed = try AES.GCM.seal(clear, using: key, authenticating: Data(path.utf8)).combined,
                  sealed.count <= budget else { return false }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var directory = folder
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try sealed.write(to: file(path), options: .atomic)
            #if os(iOS) || os(tvOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                 ofItemAtPath: file(path).path)
            #endif
            trimLocked(now: now)
            return FileManager.default.fileExists(atPath: file(path).path)
        } catch { return false }
    }

    func remove(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file(path))
    }

    func trim(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        trimLocked(now: now)
    }

    private func trimLocked(now: Date) {
        let fields: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(fields))) ?? [])
            .filter { $0.pathExtension == "sealed" }
            .compactMap { url -> (URL, Date, Int)? in
                guard let attributes = try? url.resourceValues(forKeys: fields), attributes.isSymbolicLink != true,
                      let date = attributes.contentModificationDate, let size = attributes.fileSize else { return nil }
                return (url, date, size)
            }.sorted { $0.1 > $1.1 }
        var total = 0
        for (url, date, size) in files {
            if now.timeIntervalSince(date) >= lifetime || total + size > budget {
                try? FileManager.default.removeItem(at: url)
            } else { total += size }
        }
    }
}

/// Both the generation and deadline must pass, even when decoded pixels are already in memory.
struct RRPagePermission {
    let generation: UUID
    let until: Date
    private let issuedAt: Date
    let clockUntil: ContinuousClock.Instant

    init(generation: UUID, until: Date, now: Date = Date(), clockNow: ContinuousClock.Instant = .now) {
        self.generation = generation; self.until = until; issuedAt = now
        clockUntil = clockNow.advanced(by: .seconds(max(0, until.timeIntervalSince(now))))
    }

    func permits(generation current: UUID, now: Date = Date(), clockNow: ContinuousClock.Instant = .now) -> Bool {
        generation == current && now >= issuedAt && now < until && clockNow < clockUntil
    }
}
