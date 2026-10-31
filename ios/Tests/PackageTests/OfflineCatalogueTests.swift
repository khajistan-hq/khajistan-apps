import CryptoKit
import Foundation
import XCTest
@testable import KhajistanCore

final class OfflineCatalogueTests: XCTestCase {
    private var folder: URL!
    private let device = UUID()
    private let key = SymmetricKey(size: .bits256)
    private var session = OfflineFilmLibrarySession()

    override func setUpWithError() throws {
        session = OfflineFilmLibrarySession()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("kj-catalogue-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folder = folder.resolvingSymlinksInPath()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func catalogue(account: String = "account-a", device: UUID? = nil,
                           key: SymmetricKey? = nil, entries: Int = 512, bytes: Int = 4 * 1024 * 1024) throws -> OfflineFilmCatalogue {
        try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: account,
                                 device: device ?? self.device, key: key ?? self.key, session: session,
                                 maximumEntries: entries, maximumBytes: bytes)
    }
    private func record(entitlement: UUID = UUID(), id: UUID = UUID()) -> OfflineFilmLibraryRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let grant = OfflineFilmGrant(entitlementID: entitlement, accountID: "account-a", deviceID: device,
            filmHandle: "private-title", assetVersion: "version-1", kind: .purchase, issuedAt: now,
            refreshBy: now.addingTimeInterval(86_400), startBy: nil, playbackEndsAt: nil, playbackDuration: nil)
        return OfflineFilmLibraryRecord(id: id, grant: grant, keyIdentifier: "skd://private-content",
            title: "A private film title", phase: .downloading, taskIdentifier: 7, packagePath: nil)
    }

    func testEncryptedReopenAndAccountDeviceKeyBinding() throws {
        let store = try catalogue()
        XCTAssertEqual(try store.all(), [])
        let row = try store.insert(record())
        let sealed = try Data(contentsOf: store.indexURL)
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains(row.title))
        XCTAssertEqual(try catalogue().all(), [row])
        XCTAssertThrowsError(try catalogue(account: "account-b").all())
        XCTAssertThrowsError(try catalogue(device: UUID()).all())
        XCTAssertThrowsError(try catalogue(key: SymmetricKey(size: .bits256)).all())
    }

    func testCorruptionCannotBecomeAnEmptyOverwrite() throws {
        let store = try catalogue()
        try store.insert(record())
        var sealed = try Data(contentsOf: store.indexURL)
        sealed[sealed.count - 1] ^= 1
        try sealed.write(to: store.indexURL)
        XCTAssertThrowsError(try store.all())
        XCTAssertThrowsError(try store.insert(record()))
        XCTAssertEqual(try Data(contentsOf: store.indexURL), sealed)
        try sealed.prefix(12).write(to: store.indexURL)
        XCTAssertThrowsError(try store.all())
    }

    func testRemovedOperationCannotBeResurrectedByLateCompletion() throws {
        let store = try catalogue()
        let old = try store.insert(record())
        try store.remove(old)
        let replacement = try store.insert(record(entitlement: old.grant.entitlementID, id: old.id))
        XCTAssertNotEqual(old.operation, replacement.operation)
        XCTAssertNil(try store.update(old) { $0.phase = .failed })
        try store.remove(old)
        XCTAssertEqual(try store.all(), [replacement])
        XCTAssertThrowsError(try store.insert(record(entitlement: replacement.grant.entitlementID)))
    }

    func testCapacityAndInvalidUpdatePreserveThePriorIndex() throws {
        let store = try catalogue(entries: 1)
        let row = try store.insert(record())
        let before = try Data(contentsOf: store.indexURL)
        XCTAssertThrowsError(try store.insert(record()))
        XCTAssertThrowsError(try store.update(row) { $0.phase = .ready })
        XCTAssertThrowsError(try store.update(row) { _ in throw OfflineFilmError.storage })
        XCTAssertEqual(try Data(contentsOf: store.indexURL), before)
        XCTAssertThrowsError(try catalogue(bytes: 10).all())
        XCTAssertEqual(try store.all(), [row])
    }

    func testConcurrentInstancesDoNotLoseRecords() throws {
        let stores = [try catalogue(), try catalogue()]
        let inputs = (0..<32).map { _ in record() }
        DispatchQueue.concurrentPerform(iterations: inputs.count) { i in
            do { try stores[i % 2].insert(inputs[i]) } catch { XCTFail("Insert failed: \(error)") }
        }
        let rows = try stores[0].all()
        XCTAssertEqual(Set(rows.map(\.id)), Set(inputs.map(\.id)))
        DispatchQueue.concurrentPerform(iterations: rows.count) { i in
            do { _ = try stores[i % 2].update(rows[i]) { $0.phase = .paused } } catch { XCTFail("Update failed: \(error)") }
        }
        XCTAssertTrue(try stores[1].all().allSatisfy { $0.phase == .paused })
        let old = try XCTUnwrap(stores[0].all().first)
        try stores[1].remove(old)
        XCTAssertNil(try stores[0].update(old) { $0.phase = .failed })
        XCTAssertEqual(try stores[0].all().count, 31)
    }

    func testStaleRevisionCannotOverwritePauseOrFailure() throws {
        let store = try catalogue()
        let row = try store.insert(record())
        let paused = try XCTUnwrap(store.update(row) { $0.phase = .paused })
        XCTAssertNil(try store.update(row) { $0.phase = .failed })
        let failed = try XCTUnwrap(store.update(paused) { $0.phase = .failed })
        XCTAssertThrowsError(try store.update(failed) {
            $0.phase = .ready; $0.packagePath = "Library/Assets/test.movpkg"
            $0.mediaVerified = true; $0.keyPersisted = true; $0.taskIdentifier = nil
        })
        XCTAssertEqual(try store.all(), [failed])
    }

    func testSessionInvalidationFencesAllInstancesAndSameAccountRelogin() throws {
        let oldStore = try catalogue(), another = try catalogue()
        let row = try oldStore.insert(record())
        session.invalidate()
        XCTAssertThrowsError(try oldStore.all())
        XCTAssertThrowsError(try another.remove(row))
        XCTAssertThrowsError(try oldStore.update(row) { $0.phase = .failed })
        session = OfflineFilmLibrarySession()
        let newStore = try catalogue()
        XCTAssertEqual(try newStore.all(), [row])
        try newStore.remove(row)
        let replacement = try newStore.insert(record(entitlement: row.grant.entitlementID, id: row.id))
        XCTAssertThrowsError(try another.update(row) { $0.phase = .paused })
        XCTAssertEqual(try newStore.all(), [replacement])
    }

    func testPrivatePackageContainmentAndEviction() throws {
        let path = "Library/ManagedAssets/test.movpkg"
        let package = folder.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        XCTAssertEqual(try OfflineFilmPackageLocation.relative(package, container: folder), path)
        XCTAssertEqual(try OfflineFilmPackageLocation.resolve(path, container: folder), package)
        for bad in ["Documents/test.movpkg", "Library/../Documents/test.movpkg", "/Library/Assets/test.movpkg",
                    "Library//test.movpkg", "Library/Assets/movie.mp4", "Library/Assets/./test.movpkg"] {
            XCTAssertThrowsError(try OfflineFilmPackageLocation.resolve(bad, container: folder))
        }
        try FileManager.default.removeItem(at: package)
        XCTAssertThrowsError(try OfflineFilmPackageLocation.resolve(path, container: folder))
        XCTAssertNoThrow(try OfflineFilmPackageLocation.resolve(path, container: folder, mustExist: false))
        let outside = folder.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: package, withDestinationURL: outside)
        XCTAssertThrowsError(try OfflineFilmPackageLocation.resolve(path, container: folder))
        XCTAssertThrowsError(try OfflineFilmPackageLocation.relative(package, container: folder))
    }

    func testIndexSymlinkDoesNotReadOrOverwriteUnrelatedFile() throws {
        let store = try catalogue()
        try store.insert(record())
        let other = folder.appendingPathComponent("unrelated")
        let data = Data("leave this alone".utf8)
        try data.write(to: other)
        try FileManager.default.removeItem(at: store.indexURL)
        try FileManager.default.createSymbolicLink(at: store.indexURL, withDestinationURL: other)
        XCTAssertThrowsError(try store.all())
        XCTAssertThrowsError(try store.insert(record()))
        XCTAssertEqual(try Data(contentsOf: other), data)
    }
}
