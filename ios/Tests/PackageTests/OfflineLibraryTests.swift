import CryptoKit
import Foundation
import XCTest
@testable import KhajistanCore

@MainActor
private final class FixtureProvider: OfflineFilmAuthorizing {
    var authorization: OfflineFilmAuthorization!
    var failure = false
    var answer: [UUID: Bool] = [:]
    var deferred: CheckedContinuation<OfflineFilmAuthorization, Error>?
    var holdAuthorization = false
    var requests = 0
    var beforeAnswer: (() throws -> Void)?
    func authorizeDownload(film: String) async throws -> OfflineFilmAuthorization {
        requests += 1
        if holdAuthorization { return try await withCheckedThrowingContinuation { deferred = $0 } }
        if failure { throw OfflineFilmError.needsConnection }
        return authorization
    }
    func checkEntitlements(_ grants: [OfflineFilmGrant]) async throws -> [UUID: Bool] {
        if failure { throw OfflineFilmError.needsConnection }
        try beforeAnswer?()
        return answer
    }
}

@MainActor
private final class FixtureTransport: OfflineFilmDownloadTransport {
    var onEvent: ((OfflineFilmDownloadEvent) -> Void)?
    var tasks: [UUID: Int] = [:]
    var resumed: Set<UUID> = []
    var paused: Set<UUID> = []
    var cancelled: Set<UUID> = []
    var keyAvailable = true
    var locked = false
    var protectedPackage = true
    var deleteFails = false
    var cancellationTerminal = true
    var activeOnRestore: Set<UUID> = []
    var verification: CheckedContinuation<Void, Error>?
    var holdVerification = false
    var stopped = false
    var sequence = 0
    var onMake: (() throws -> Void)?
    var heldCreation: CheckedContinuation<Void, Error>?
    var holdCreation = false
    var deleteAttempts: Set<UUID> = []
    var revokedKeys: Set<UUID> = []
    func makeDownload(_ record: OfflineFilmLibraryRecord, asset: OfflineFilmAsset) async throws -> Int {
        if holdCreation { try await withCheckedThrowingContinuation { heldCreation = $0 } }
        try Task.checkCancellation()
        sequence += 1; tasks[record.operation] = sequence; try onMake?(); return sequence
    }
    func resume(_ operation: UUID) throws { resumed.insert(operation); paused.remove(operation) }
    func pause(_ operation: UUID) { paused.insert(operation) }
    func cancel(_ operation: UUID) -> Bool { cancelled.insert(operation); return cancellationTerminal }
    func restore(_ records: [OfflineFilmLibraryRecord]) async throws -> Set<UUID> { activeOnRestore }
    func verifyPackage(_ record: OfflineFilmLibraryRecord, at url: URL) async throws {
        if holdVerification { try await withCheckedThrowingContinuation { verification = $0 } }
        if !protectedPackage { throw OfflineFilmError.invalidAsset }
    }
    func hasUsableKey(_ record: OfflineFilmLibraryRecord) throws -> Bool {
        if locked { throw OfflineFilmError.deviceLocked }
        return keyAvailable && !revokedKeys.contains(record.grant.entitlementID)
    }
    func markRevoked(_ record: OfflineFilmLibraryRecord) throws { revokedKeys.insert(record.grant.entitlementID) }
    func deleteKey(_ record: OfflineFilmLibraryRecord) throws {
        deleteAttempts.insert(record.grant.entitlementID)
        if deleteFails { throw OfflineFilmError.storage }
    }
    func shutDown() { stopped = true }
    func emit(_ row: OfflineFilmLibraryRecord, _ kind: OfflineFilmDownloadEvent.Kind) {
        onEvent?(OfflineFilmDownloadEvent(operation: row.operation, taskIdentifier: row.taskIdentifier!, kind: kind))
    }
}

@MainActor
final class OfflineLibraryTests: XCTestCase {
    private var folder: URL!
    private var session: OfflineFilmLibrarySession!
    private var store: OfflineFilmCatalogue!
    private var provider: FixtureProvider!
    private var transport: FixtureTransport!
    private var library: OfflineFilmLibrary!
    private var current = true
    private let device = UUID()
    private let key = SymmetricKey(size: .bits256)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("kj-library-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folder = folder.resolvingSymlinksInPath()
        session = OfflineFilmLibrarySession(); provider = FixtureProvider(); transport = FixtureTransport()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        let now = Date()
        provider.authorization = OfflineFilmAuthorization(grant: OfflineFilmGrant(entitlementID: UUID(),
            accountID: "account-a", deviceID: device, filmHandle: "film", assetVersion: "v1", kind: .purchase,
            issuedAt: now.addingTimeInterval(-1), refreshBy: now.addingTimeInterval(3600),
            startBy: nil, playbackEndsAt: nil, playbackDuration: nil),
            asset: OfflineFilmAsset(manifest: URL(string: "https://fixture.invalid/master.m3u8?token=not-persisted")!,
                                    keyIdentifier: "skd://fixture-key"), title: "Fixture film")
        makeLibrary()
        try await library.restore()
    }

    override func tearDown() async throws {
        library.stop()
        try FileManager.default.removeItem(at: folder)
    }

    private func makeLibrary() {
        library = OfflineFilmLibrary(catalogue: store, session: session, provider: provider, transport: transport,
            account: "account-a", device: device, container: folder, approvedHosts: ["fixture.invalid"],
            isCurrent: { [weak self] in self?.current == true })
    }

    private func row() throws -> OfflineFilmLibraryRecord { try XCTUnwrap(library.records().first) }
    private func package() throws -> URL {
        let url = folder.appendingPathComponent("Library/Assets/fixture.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<100 { if condition() { return }; await Task.yield() }
        XCTAssertTrue(condition(), "Asynchronous lifecycle did not reach expected state")
    }
    private func ready() async throws -> OfflineFilmLibraryRecord {
        _ = try await library.download(film: "film")
        let row = try row()
        transport.emit(row, .destination(try package())); transport.emit(row, .keyPersisted)
        transport.emit(row, .completed)
        await settle { (try? self.row().phase) == .ready }
        return try self.row()
    }

    func testReadyRequiresBothVerifiedProtectedPackageAndKey() async throws {
        _ = try await library.download(film: "film")
        let saved = try row()
        transport.emit(saved, .destination(try package())); transport.emit(saved, .completed)
        await settle { (try? self.row().mediaVerified) == true }
        XCTAssertEqual(try row().phase, .verifying)
        transport.emit(saved, .keyPersisted)
        XCTAssertEqual(try row().phase, .ready)
        XCTAssertNil(try row().taskIdentifier)
        let same = try await library.download(film: "film")
        XCTAssertEqual(same, saved.id); XCTAssertEqual(provider.requests, 1)
    }

    func testClearOrIncompletePackageNeverBecomesReady() async throws {
        transport.protectedPackage = false
        _ = try await library.download(film: "film")
        let saved = try row()
        transport.emit(saved, .destination(try package())); transport.emit(saved, .keyPersisted)
        transport.emit(saved, .completed)
        await settle { (try? self.row().phase) == .failed }
        XCTAssertTrue(transport.cancelled.contains(saved.operation))
    }

    func testPauseResumeFailureAndLateSuccess() async throws {
        _ = try await library.download(film: "film")
        let saved = try row()
        try library.pause(saved.id); XCTAssertEqual(try row().phase, .paused)
        try library.resume(saved.id); XCTAssertEqual(try row().phase, .downloading)
        transport.emit(saved, .failed)
        transport.emit(saved, .destination(try package())); transport.emit(saved, .keyPersisted)
        transport.emit(saved, .completed)
        XCTAssertEqual(try row().phase, .failed)
    }

    func testRemoveBeforeDestinationKeepsTombstoneUntilTerminalCallback() async throws {
        transport.cancellationTerminal = false
        _ = try await library.download(film: "film")
        let saved = try row()
        try library.remove(saved.id)
        XCTAssertEqual(try row().phase, .removing)
        let url = try package()
        transport.emit(saved, .destination(url)); transport.emit(saved, .failed)
        XCTAssertEqual(try library.records(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailedKeyDeletionSurvivesRestartAndRetries() async throws {
        let saved = try await ready(), url = try package()
        transport.deleteFails = true
        XCTAssertThrowsError(try library.remove(saved.id))
        XCTAssertEqual(try row().phase, .removing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); makeLibrary()
        try await library.restore()
        XCTAssertEqual(try library.records(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStorageSubstitutionCannotDeleteUnrelatedDirectoryAndCleanupRetries() async throws {
        let saved = try await ready(), url = try package()
        try FileManager.default.removeItem(at: url)
        let outside = folder.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        XCTAssertThrowsError(try library.remove(saved.id))
        XCTAssertEqual(try row().phase, .removing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try FileManager.default.removeItem(at: url)
        try library.remove(saved.id)
        XCTAssertEqual(try library.records(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testLogoutWhileAuthorizingCannotCreateOrStartTask() async throws {
        provider.holdAuthorization = true
        let request = Task { try await library.download(film: "film") }
        await settle { self.provider.deferred != nil }
        current = false; library.stop()
        provider.deferred?.resume(returning: provider.authorization)
        do { _ = try await request.value; XCTFail("Logged-out grant was accepted") } catch {}
        XCTAssertEqual(transport.tasks.count, 0); XCTAssertTrue(transport.stopped)
    }

    func testRemovalDuringVerificationCannotResurrectRecord() async throws {
        transport.holdVerification = true
        _ = try await library.download(film: "film")
        let saved = try row()
        transport.emit(saved, .destination(try package())); transport.emit(saved, .keyPersisted)
        transport.emit(saved, .completed)
        await settle { self.transport.verification != nil }
        try library.remove(saved.id)
        transport.verification?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(try library.records(), [])
    }

    func testRestartDetectsEvictedPackageAndInterruptedTask() async throws {
        let saved = try await ready()
        try FileManager.default.removeItem(at: try OfflineFilmPackageLocation.resolve(saved.packagePath!, container: folder))
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); makeLibrary(); try await library.restore()
        XCTAssertEqual(try row().phase, .failed)
        try library.remove(saved.id)
        _ = try await library.download(film: "film")
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); makeLibrary(); try await library.restore()
        XCTAssertEqual(try row().phase, .failed)
    }

    func testReconnectionRevocationAndNetworkFailure() async throws {
        let saved = try await ready()
        provider.failure = true
        do { try await library.reconcile(); XCTFail("Network failure ignored") } catch {}
        XCTAssertEqual(try row().phase, .ready)
        provider.failure = false
        do { try await library.reconcile(); XCTFail("Missing answer accepted") } catch {}
        XCTAssertEqual(try row().phase, .ready)
        provider.answer = [saved.grant.entitlementID: false]
        try await library.reconcile()
        XCTAssertEqual(try library.records(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(saved.packagePath!).path))
    }

    func testRevocationStopsPlaybackBeforeFailingKeyDeletion() async throws {
        let saved = try await ready()
        var stoppedPlayback = false
        library.onChange = { if (try? self.library.records().first?.phase) == .removing { stoppedPlayback = true } }
        provider.answer = [saved.grant.entitlementID: false]; transport.deleteFails = true
        do { try await library.reconcile(); XCTFail("Expected cleanup error") } catch {}
        XCTAssertTrue(stoppedPlayback)
        XCTAssertEqual(try row().phase, .removing)
    }

    func testTaskBindingWriteFailureCannotStartAndLateDestinationIsRetained() async throws {
        var original: Data!
        transport.onMake = {
            original = try Data(contentsOf: self.store.indexURL)
            // Controlled storage failure after suspended task creation but before task binding.
            try FileManager.default.removeItem(at: self.store.indexURL)
            try FileManager.default.createDirectory(at: self.store.indexURL, withIntermediateDirectories: false)
        }
        do { _ = try await library.download(film: "film"); XCTFail("Expected storage failure") } catch {}
        XCTAssertTrue(transport.resumed.isEmpty)
        try FileManager.default.removeItem(at: store.indexURL); try original.write(to: store.indexURL)
        let saved = try row(), url = try package()
        let task = try XCTUnwrap(transport.tasks[saved.operation])
        transport.onEvent?(OfflineFilmDownloadEvent(operation: saved.operation, taskIdentifier: task, kind: .destination(url)))
        XCTAssertEqual(try row().packagePath, "Library/Assets/fixture.movpkg")
        transport.onEvent?(OfflineFilmDownloadEvent(operation: saved.operation, taskIdentifier: task, kind: .failed))
        XCTAssertEqual(try row().phase, .failed)
        try library.remove(saved.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPauseDuringAssetInspectionRemainsPausedAndCanResume() async throws {
        transport.holdCreation = true
        let download = Task { try await library.download(film: "film") }
        await settle { self.transport.heldCreation != nil }
        let saved = try row()
        try library.pause(saved.id)
        transport.heldCreation?.resume()
        _ = try await download.value
        XCTAssertEqual(try row().phase, .paused)
        XCTAssertTrue(transport.resumed.isEmpty)
        try library.resume(saved.id)
        XCTAssertEqual(try row().phase, .downloading)
        XCTAssertTrue(transport.resumed.contains(saved.operation))
    }

    func testRemovalDuringAssetInspectionCancelsBeforeCreatingTask() async throws {
        transport.holdCreation = true
        let download = Task { try await library.download(film: "film") }
        await settle { self.transport.heldCreation != nil }
        let saved = try row()
        try library.remove(saved.id)
        XCTAssertEqual(try row().phase, .removing)
        transport.heldCreation?.resume()
        do { _ = try await download.value; XCTFail("Cancelled creation succeeded") } catch {}
        XCTAssertTrue(transport.tasks.isEmpty)
        XCTAssertEqual(try library.records(), [])
    }

    func testAllRevocationsStopAccessEvenWhenFirstCleanupFails() async throws {
        let first = try await ready()
        let old = provider.authorization!
        let next = OfflineFilmGrant(entitlementID: UUID(), accountID: old.grant.accountID, deviceID: device,
            filmHandle: "second", assetVersion: "v1", kind: .purchase, issuedAt: old.grant.issuedAt,
            refreshBy: old.grant.refreshBy, startBy: nil, playbackEndsAt: nil, playbackDuration: nil)
        provider.authorization = OfflineFilmAuthorization(grant: next, asset: old.asset, title: "Second fixture")
        _ = try await library.download(film: "second")
        let second = try XCTUnwrap(library.records().first { $0.grant.filmHandle == "second" })
        provider.answer = [first.grant.entitlementID: false, second.grant.entitlementID: false]
        transport.deleteFails = true
        var allRevokedBeforeCleanup = false
        library.onChange = {
            if self.transport.deleteAttempts.isEmpty,
               (try? self.library.records().allSatisfy { $0.phase == .removing }) == true {
                allRevokedBeforeCleanup = true
            }
        }
        do { try await library.reconcile(); XCTFail("Expected cleanup error") } catch {}
        XCTAssertTrue(allRevokedBeforeCleanup)
        XCTAssertEqual(transport.deleteAttempts, [first.grant.entitlementID, second.grant.entitlementID])
        XCTAssertTrue(try library.records().allSatisfy { $0.phase == .removing })
    }

    func testRevocationSurvivesCatalogueWriteFailureAndRestart() async throws {
        let saved = try await ready()
        let readyBytes = try Data(contentsOf: store.indexURL)
        provider.answer = [saved.grant.entitlementID: false]
        // Start from a readable snapshot; fail index writes after the complete provider answer.
        provider.beforeAnswer = {
            try FileManager.default.removeItem(at: self.store.indexURL)
            try FileManager.default.createDirectory(at: self.store.indexURL, withIntermediateDirectories: false)
        }
        do { try await library.reconcile(); XCTFail("Expected storage failure") } catch {}
        XCTAssertTrue(transport.revokedKeys.contains(saved.grant.entitlementID))
        let durableKeys = transport.revokedKeys
        try FileManager.default.removeItem(at: store.indexURL); try readyBytes.write(to: store.indexURL)
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); transport.revokedKeys = durableKeys
        makeLibrary(); try await library.restore()
        XCTAssertEqual(try row().phase, .failed)
    }

    func testRestartRevalidatesPackageWhenTerminalCallbackWasMissed() async throws {
        _ = try await library.download(film: "film")
        let saved = try row()
        transport.emit(saved, .destination(try package())); transport.emit(saved, .keyPersisted)
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); makeLibrary(); try await library.restore()
        await settle { (try? self.library.records().first?.phase) == .ready }
        XCTAssertEqual(try row().phase, .ready)
    }

    func testLockedKeychainDefersReadyAndMissedCompletionUntilUnlock() async throws {
        _ = try await library.download(film: "film")
        let saved = try row()
        transport.emit(saved, .destination(try package())); transport.emit(saved, .keyPersisted)
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); transport.locked = true
        makeLibrary()
        do { try await library.restore(); XCTFail("Locked data accepted") } catch OfflineFilmError.deviceLocked {} catch { XCTFail("Wrong error") }
        XCTAssertEqual(try row().phase, .downloading)
        transport.locked = false; try await library.restore()
        await settle { (try? self.library.records().first?.phase) == .ready }
        library.stop(); session = OfflineFilmLibrarySession()
        store = try OfflineFilmCatalogue(folder: folder.appendingPathComponent("index"), account: "account-a",
                                         device: device, key: key, session: session)
        transport = FixtureTransport(); transport.locked = true; makeLibrary()
        do { try await library.restore(); XCTFail("Locked data accepted") } catch OfflineFilmError.deviceLocked {} catch { XCTFail("Wrong error") }
        XCTAssertEqual(try row().phase, .ready)
        transport.locked = false; try await library.restore()
        XCTAssertEqual(try row().phase, .ready)
    }
}
