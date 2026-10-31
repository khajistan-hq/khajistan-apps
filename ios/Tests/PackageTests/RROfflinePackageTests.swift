import CryptoKit
import Foundation
import XCTest
@testable import KhajistanCore

final class RROfflinePackageTests: XCTestCase {
    let device = UUID()
    let key = SymmetricKey(size: .bits256)
    let pages = [Data("synthetic private scan A".utf8), Data("synthetic private scan B".utf8)]
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("rr-package-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func manifest(version: String = "v1", bytes: [Data]? = nil) -> RRPackageManifest {
        RRPackageManifest(issue: "fixture issue", version: version, pages: (bytes ?? pages).enumerated().map {
            .init(identifier: "page-\($0.offset)", byteCount: $0.element.count, sha256: Data(SHA256.hash(data: $0.element)))
        })
    }
    func store(_ root: URL, session: RRPackageSession = RRPackageSession(), limits: RRPackageLimits = .init()) throws -> RROfflinePackageStore {
        try RROfflinePackageStore(root: root, account: "fixture account", device: device, key: key, session: session, limits: limits)
    }
    func path(_ root: URL, _ handle: RROfflinePackageStore.Handle, _ name: String) -> URL {
        if name == "manifest.sealed" { return root.appendingPathComponent(handle.id.uuidString + ".sealed") }
        return root.appendingPathComponent(handle.id.uuidString).appendingPathComponent(name)
    }
    func testInterruptedDownloadResumesAndCompletesOnlyAfterAllPagesVerify() throws {
        let root = try root(), first = try store(root), id = UUID()
        let handle = try first.begin(id: id, manifest: manifest())
        XCTAssertEqual(try first.begin(id: id, manifest: manifest()), handle)
        try first.stage(pages[0], page: 0, in: handle)
        XCTAssertThrowsError(try first.finish(handle)) { XCTAssertEqual($0 as? RRPackageError, .incomplete) }
        let reopened = try store(root), held = try reopened.status(id: id)
        XCTAssertEqual(held.handle, handle); XCTAssertEqual(held.missingPages, [1]); XCTAssertFalse(held.complete)
        try reopened.stage(pages[1], page: 1, in: handle)
        try reopened.finish(handle); try reopened.finish(handle)
        XCTAssertTrue(try store(root).status(id: id).complete)
    }
    func testDiskContainsOnlySealedBytesAndMetadata() throws {
        let root = try root(), store = try store(root), handle = try store.begin(id: UUID(), manifest: manifest())
        try store.stage(pages[0], page: 0, in: handle)
        let pageFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(handle.id.uuidString), includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(pageFiles.map(\.lastPathComponent)), ["0.sealed"])
        let files = pageFiles + [path(root, handle, "manifest.sealed")]
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertNil(data.range(of: pages[0])); XCTAssertNil(data.range(of: Data("fixture issue".utf8)))
            XCTAssertNil(data.range(of: Data("fixture account".utf8)))
        }
    }
    func testWrongAccountDeviceKeyAndPackageIdentityFailClosed() throws {
        let root = try root(), store = try store(root), handle = try store.begin(id: UUID(), manifest: manifest())
        for (account, device, key) in [("other", device, key), ("fixture account", UUID(), key), ("fixture account", device, SymmetricKey(size: .bits256))] {
            let other = try RROfflinePackageStore(root: root, account: account, device: device, key: key, session: RRPackageSession())
            XCTAssertThrowsError(try other.status(id: handle.id))
        }
        let other = try store.begin(id: UUID(), manifest: manifest())
        let data = try Data(contentsOf: path(root, handle, "manifest.sealed"))
        try data.write(to: path(root, other, "manifest.sealed"))
        XCTAssertThrowsError(try store.status(id: other.id))
    }
    func testCorruptTruncatedAndSwappedPagesCannotBecomeComplete() throws {
        let root = try root(), store = try store(root), handle = try store.begin(id: UUID(), manifest: manifest())
        for index in pages.indices { try store.stage(pages[index], page: index, in: handle) }
        let a = try Data(contentsOf: path(root, handle, "0.sealed")), b = try Data(contentsOf: path(root, handle, "1.sealed"))
        try b.write(to: path(root, handle, "0.sealed")); try a.write(to: path(root, handle, "1.sealed"))
        XCTAssertEqual(try store.status(id: handle.id).missingPages, [0, 1])
        var corrupt = a; corrupt[corrupt.count / 2] ^= 1
        try corrupt.write(to: path(root, handle, "0.sealed")); try b.prefix(10).write(to: path(root, handle, "1.sealed"))
        XCTAssertThrowsError(try store.finish(handle))
        for index in pages.indices { try store.stage(pages[index], page: index, in: handle) }
        try store.finish(handle)
        try a.prefix(10).write(to: path(root, handle, "0.sealed"))
        XCTAssertFalse(try store.status(id: handle.id).complete, "a stored complete flag cannot hide later corruption")
        XCTAssertThrowsError(try store.stage(pages[0], page: 0, in: handle), "complete packages are immutable, use a new attempt")
    }
    func testCrossVersionAndAttemptPageSubstitutionFails() throws {
        let root = try root(), store = try store(root), first = try store.begin(id: UUID(), manifest: manifest())
        try store.stage(pages[0], page: 0, in: first)
        let saved = try Data(contentsOf: path(root, first, "0.sealed"))
        let next = try store.begin(id: UUID(), manifest: manifest(version: "v2"))
        try store.stage(pages[0], page: 0, in: next)
        try saved.write(to: path(root, next, "0.sealed"))
        XCTAssertEqual(try store.status(id: next.id).missingPages, [0, 1])
        try store.remove(first)
        let replacement = try store.begin(id: first.id, manifest: manifest())
        XCTAssertNotEqual(replacement.operation, first.operation)
        try store.stage(pages[0], page: 0, in: replacement)
        try saved.write(to: path(root, replacement, "0.sealed"))
        XCTAssertEqual(try store.status(id: replacement.id).missingPages, [0, 1])
        XCTAssertThrowsError(try store.stage(pages[0], page: 0, in: first))
        XCTAssertThrowsError(try store.finish(first)); XCTAssertThrowsError(try store.remove(first))
        XCTAssertEqual(try store.status(id: replacement.id).handle, replacement)
    }
    func testSessionInvalidationFencesAllInstancesAndOperations() throws {
        let root = try root(), session = RRPackageSession(), first = try store(root, session: session), second = try store(root, session: session)
        let handle = try first.begin(id: UUID(), manifest: manifest())
        session.invalidate()
        XCTAssertThrowsError(try second.stage(pages[0], page: 0, in: handle)) { XCTAssertEqual($0 as? RRPackageError, .inactiveSession) }
        XCTAssertThrowsError(try first.status(id: handle.id)); XCTAssertThrowsError(try first.finish(handle))
        XCTAssertThrowsError(try first.remove(handle)); XCTAssertThrowsError(try second.begin(id: UUID(), manifest: manifest()))
    }
    func testBoundsAndInvalidManifestRejectedBeforeWriting() throws {
        let root = try root()
        var limits = RRPackageLimits(); limits.pageBytes = 30; limits.packageBytes = 40; limits.pages = 2
        let store = try store(root, limits: limits)
        XCTAssertThrowsError(try store.begin(id: UUID(), manifest: manifest())) // total exceeds 40
        let page = manifest().pages[0]
        for invalid in [RRPackageManifest(issue: "", version: "v", pages: [page]),
                        RRPackageManifest(issue: "x", version: "v", pages: []),
                        RRPackageManifest(issue: "x", version: "v", pages: [page, page]),
                        RRPackageManifest(issue: "x", version: "v", pages: [.init(identifier: "x", byteCount: -1, sha256: Data())])] {
            XCTAssertThrowsError(try store.begin(id: UUID(), manifest: invalid))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testBadPageHashSizeAndOrdinalNeverWrite() throws {
        let root = try root(), store = try store(root), handle = try store.begin(id: UUID(), manifest: manifest())
        XCTAssertThrowsError(try store.stage(pages[1], page: 0, in: handle))
        XCTAssertThrowsError(try store.stage(Data(), page: 0, in: handle))
        XCTAssertThrowsError(try store.stage(pages[0], page: -1, in: handle))
        XCTAssertThrowsError(try store.stage(pages[0], page: 2, in: handle))
        XCTAssertEqual(try store.status(id: handle.id).missingPages, [0, 1])
    }
    func testGlobalStorageBudgetIncludesPartialPackagesAndLeavesRemovalHeadroom() throws {
        let root = try root()
        var limits = RRPackageLimits(); limits.metadataBytes = 1024; limits.totalDiskBytes = 2600
        let store = try store(root, limits: limits), data = Data(repeating: 9, count: 1100)
        let first = try store.begin(id: UUID(), manifest: manifest(bytes: [data]))
        try store.stage(data, page: 0, in: first)
        XCTAssertThrowsError(try store.begin(id: UUID(), manifest: manifest(bytes: [data])))
        try store.remove(first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testSymlinkSubstitutionDoesNotWriteOrRemoveExternalFiles() throws {
        let root = try root(), outside = try self.root(), store = try store(root)
        let handle = try store.begin(id: UUID(), manifest: manifest())
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("untouched".utf8).write(to: sentinel)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(handle.id.uuidString), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: path(root, handle, "0.sealed"), withDestinationURL: sentinel)
        XCTAssertThrowsError(try store.stage(pages[0], page: 0, in: handle))
        XCTAssertFalse(try store.status(id: handle.id).complete)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))
        XCTAssertThrowsError(try store.remove(handle), "unknown symlinks fail closed before tombstone write")
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))
    }
    func testConcurrentInstancesKeepBothPagesAndOneOperation() throws {
        let root = try root(), first = try store(root), second = try store(root), id = UUID()
        let handle = try first.begin(id: id, manifest: manifest())
        let errors = NSLock(), failures = NSMutableArray()
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do {
                let instance = index % 2 == 0 ? first : second
                XCTAssertEqual(try instance.begin(id: id, manifest: manifest()), handle)
                try instance.stage(pages[index % 2], page: index % 2, in: handle)
            } catch { errors.lock(); failures.add(error); errors.unlock() }
        }
        XCTAssertEqual(failures.count, 0)
        try first.finish(handle); XCTAssertTrue(try second.status(id: id).complete)
    }
    func testManifestCorruptionAndFilesystemEntryBoundFailClosed() throws {
        let root = try root(), store = try store(root), id = UUID()
        let handle = try store.begin(id: id, manifest: manifest())
        try Data("interrupted".utf8).write(to: path(root, handle, "manifest.sealed"))
        XCTAssertThrowsError(try store.begin(id: id, manifest: manifest()))
        XCTAssertThrowsError(try store.status(id: id))
        var limits = RRPackageLimits(); limits.filesystemEntries = 3
        let limited = try self.store(try self.root(), limits: limits)
        let other = try limited.begin(id: UUID(), manifest: manifest())
        XCTAssertThrowsError(try limited.stage(pages[0], page: 0, in: other))
    }
    func testInterruptedInitialManifestWriteCanRetryWithoutOrphanPackage() throws {
        let root = try root(), id = UUID()
        let broken = try RROfflinePackageStore(root: root, account: "fixture account", device: device,
            key: key, session: RRPackageSession(), interrupt: { step in
                if step == .beforeInitialManifest { throw RRPackageError.storage }
            })
        XCTAssertThrowsError(try broken.begin(id: id, manifest: manifest()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        let reopened = try store(root), handle = try reopened.begin(id: id, manifest: manifest())
        try reopened.stage(pages[0], page: 0, in: handle)
        XCTAssertEqual(try reopened.status(id: id).missingPages, [1])
    }
    func testRemovalRecoversAfterPartialPageDeletionAndAfterDirectoryDeletion() throws {
        for interruption in [RROfflinePackageStore.Checkpoint.afterRemovalMarker, .afterPageDirectoryRemoval] {
            let root = try root(), good = try store(root), id = UUID()
            let handle = try good.begin(id: id, manifest: manifest())
            for index in pages.indices { try good.stage(pages[index], page: index, in: handle) }
            try good.finish(handle)
            let broken = try RROfflinePackageStore(root: root, account: "fixture account", device: device,
                key: key, session: RRPackageSession(), interrupt: { step in
                    if step == interruption { throw RRPackageError.storage }
                })
            XCTAssertThrowsError(try broken.remove(handle))
            if interruption == .afterRemovalMarker {
                // Simulate recursive deletion stopping after its first encrypted child.
                try FileManager.default.removeItem(at: path(root, handle, "0.sealed"))
            }
            let reopened = try store(root)
            XCTAssertThrowsError(try reopened.begin(id: id, manifest: manifest()))
            XCTAssertThrowsError(try reopened.status(id: id))
            XCTAssertThrowsError(try reopened.stage(pages[0], page: 0, in: handle))
            try reopened.remove(handle)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
            let replacement = try reopened.begin(id: id, manifest: manifest())
            XCTAssertNotEqual(replacement.operation, handle.operation)
            XCTAssertThrowsError(try reopened.remove(handle))
        }
    }

}
