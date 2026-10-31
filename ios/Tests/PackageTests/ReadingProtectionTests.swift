import CryptoKit
import Foundation
import XCTest
@testable import KhajistanCore

final class ReadingProtectionTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rr-protection-tests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testCacheSurvivesReopenButContainsNoRawPage() throws {
        let root = try folder(), key = SymmetricKey(size: .bits256)
        let cache = RRProtectedPageCache(folder: root, key: key)
        let page = Data("private scan bytes must never be a raw JPEG file".utf8)
        XCTAssertTrue(cache.write(page, "volume/issue-p003"))
        let disk = try Data(contentsOf: cache.file("volume/issue-p003"))
        XCTAssertNil(disk.range(of: page))
        XCTAssertEqual(cache.file("volume/issue-p003").pathExtension, "sealed")
        let reopened = RRProtectedPageCache(folder: root, key: key)
        XCTAssertEqual(reopened.read("volume/issue-p003"), page)
        XCTAssertNil(RRProtectedPageCache(folder: root, key: SymmetricKey(size: .bits256)).read("volume/issue-p003"))
    }

    func testTamperingTruncationAndPageSubstitutionFailClosed() throws {
        let cache = RRProtectedPageCache(folder: try folder(), key: SymmetricKey(size: .bits256))
        XCTAssertTrue(cache.write(Data("page A".utf8), "A"))
        let sealed = try Data(contentsOf: cache.file("A"))
        try sealed.write(to: cache.file("B"))
        XCTAssertNil(cache.read("B"), "associated data binds the ciphertext to this page")
        var changed = sealed; changed[changed.count / 2] ^= 1
        try changed.write(to: cache.file("A"))
        XCTAssertNil(cache.read("A"))
        try sealed.prefix(10).write(to: cache.file("A"))
        XCTAssertNil(cache.read("A"), "interrupted data never becomes a partial page")
    }

    func testExpiryUsesEncryptedTimestampAndRejectsClockRollback() throws {
        let cache = RRProtectedPageCache(folder: try folder(), key: SymmetricKey(size: .bits256), lifetime: 60)
        let at = Date()
        XCTAssertTrue(cache.write(Data("scan".utf8), "page", now: at))
        XCTAssertNotNil(cache.read("page", now: at.addingTimeInterval(59)))
        XCTAssertNil(cache.read("page", now: at.addingTimeInterval(60)))
        XCTAssertNil(cache.read("page", now: at.addingTimeInterval(-1)))
        try FileManager.default.setAttributes([.modificationDate: at.addingTimeInterval(100)], ofItemAtPath: cache.file("page").path)
        XCTAssertNil(cache.read("page", now: at.addingTimeInterval(61)), "touching a file cannot refresh its content lifetime")
    }

    func testBudgetIsEnforcedDuringWritesNotOnlyNextLaunch() throws {
        let root = try folder()
        let budget = 1800
        let cache = RRProtectedPageCache(folder: root, key: SymmetricKey(size: .bits256), budget: budget)
        for index in 0..<12 { _ = cache.write(Data(repeating: UInt8(index), count: 500), "page-\(index)") }
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try urls.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(bytes, budget)
        XCTAssertNil(cache.read("page-0"))
        XCTAssertNotNil(cache.read("page-11"))
        XCTAssertFalse(cache.write(Data(repeating: 1, count: budget + 1), "too-large"))
    }

    func testStorageFailureDoesNotCreatePlaintextFallback() throws {
        let root = try folder().appendingPathComponent("a-file-not-a-directory")
        try Data("sentinel".utf8).write(to: root)
        let cache = RRProtectedPageCache(folder: root, key: SymmetricKey(size: .bits256))
        XCTAssertFalse(cache.write(Data("scan".utf8), "page"))
        XCTAssertNil(cache.read("page"))
        XCTAssertEqual(try Data(contentsOf: root), Data("sentinel".utf8))
    }

    func testConcurrentWritesRemainAuthenticatedAndWithinBudget() throws {
        let root = try folder()
        let cache = RRProtectedPageCache(folder: root, key: SymmetricKey(size: .bits256), budget: 8000)
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = cache.write(Data(repeating: UInt8(index), count: 250), "page-\(index)")
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(bytes, 8000)
        for index in 0..<20 {
            if let read = cache.read("page-\(index)") { XCTAssertEqual(read, Data(repeating: UInt8(index), count: 250)) }
        }
    }

    func testCachedPixelsDoNotAuthorizeExpiredOrOtherSession() {
        let now = Date(), generation = UUID()
        let clock = ContinuousClock.now
        let permit = RRPagePermission(generation: generation, until: now.addingTimeInterval(60), now: now, clockNow: clock)
        XCTAssertTrue(permit.permits(generation: generation, now: now, clockNow: clock))
        XCTAssertFalse(permit.permits(generation: generation, now: now.addingTimeInterval(60), clockNow: clock))
        XCTAssertFalse(permit.permits(generation: UUID(), now: now, clockNow: clock), "logout and same-account sign-in get a fresh generation too")
        XCTAssertFalse(permit.permits(generation: generation, now: now.addingTimeInterval(-1), clockNow: clock))
        XCTAssertFalse(permit.permits(generation: generation, now: now.addingTimeInterval(10), clockNow: clock.advanced(by: .seconds(60))),
                       "rolling the wall clock back within the answer lifetime cannot extend the monotonic deadline")
    }
}
