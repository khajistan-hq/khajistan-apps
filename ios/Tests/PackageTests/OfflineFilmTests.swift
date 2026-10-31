import XCTest
@testable import KhajistanCore

final class OfflineFilmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let device = UUID()

    private func grant(kind: OfflineFilmGrant.Kind = .rental, end: Date? = nil) -> OfflineFilmGrant {
        OfflineFilmGrant(entitlementID: UUID(), accountID: "account-a", deviceID: device,
            filmHandle: "filmfarsi-volume-1", assetVersion: "v1", kind: kind, issuedAt: now,
            refreshBy: now.addingTimeInterval(40 * 86400),
            startBy: kind == .rental ? now.addingTimeInterval(30 * 86400) : nil,
            playbackEndsAt: end, playbackDuration: kind == .rental ? 48 * 3600 : nil)
    }

    func testAccountDeviceFilmAndVersionAreAllRequired() throws {
        let g = grant()
        try g.validate(account: "account-a", device: device, film: g.filmHandle, version: "v1")
        for (account, id, film, version) in [
            ("account-b", device, g.filmHandle, "v1"),
            ("account-a", UUID(), g.filmHandle, "v1"),
            ("account-a", device, "filmfarsi-volume-2", "v1"),
            ("account-a", device, g.filmHandle, "v2")
        ] { XCTAssertThrowsError(try g.validate(account: account, device: id, film: film, version: version)) }
    }

    func testDownloadingDoesNotStartRentalAndDeadlineIsExclusive() {
        let g = grant()
        XCTAssertEqual(g.access(at: now.addingTimeInterval(29 * 86400), firstPlayedAt: nil, lastObservedAt: now), .allowed)
        XCTAssertEqual(g.access(at: g.startBy!, firstPlayedAt: nil, lastObservedAt: now), .expired)
    }

    func testRentalStartedJustBeforeDay30HasFull48Hours() {
        let g = grant(), first = now.addingTimeInterval(30 * 86400 - 1)
        XCTAssertEqual(g.access(at: first.addingTimeInterval(48 * 3600 - 1), firstPlayedAt: first, lastObservedAt: first), .allowed)
        XCTAssertEqual(g.access(at: first.addingTimeInterval(48 * 3600), firstPlayedAt: first, lastObservedAt: first), .expired)
    }

    func testServerActivatedRentalCannotRestartLocally() {
        let g = grant(end: now.addingTimeInterval(60))
        XCTAssertEqual(g.access(at: now.addingTimeInterval(60), firstPlayedAt: nil, lastObservedAt: now), .expired)
        XCTAssertEqual(g.access(at: now.addingTimeInterval(60), firstPlayedAt: now.addingTimeInterval(59), lastObservedAt: now), .expired)
    }

    func testRenewalPreservesActivationFromBeforeKeyIssue() {
        let g = grant()
        let first = now.addingTimeInterval(-47 * 3600)
        XCTAssertEqual(g.access(at: now, firstPlayedAt: first, lastObservedAt: now), .allowed)
        XCTAssertEqual(g.access(at: now.addingTimeInterval(3600), firstPlayedAt: first, lastObservedAt: now), .expired)
    }

    func testOfflineLeaseExpiryDoesNotConvertPurchaseToExpiredOwnership() {
        let g = grant(kind: .purchase)
        XCTAssertEqual(g.access(at: now.addingTimeInterval(31 * 86400), firstPlayedAt: nil, lastObservedAt: now), .allowed)
        XCTAssertEqual(g.access(at: g.refreshBy, firstPlayedAt: nil, lastObservedAt: now), .reconnect)
    }

    func testClockRollbackAndFutureActivationRequireReconnection() {
        let g = grant()
        XCTAssertEqual(g.access(at: now.addingTimeInterval(-1), firstPlayedAt: nil, lastObservedAt: now), .reconnect)
        XCTAssertEqual(g.access(at: now, firstPlayedAt: now.addingTimeInterval(1), lastObservedAt: now), .reconnect)
    }

    func testReadyNeedsMediaAndPersistedKeyInEitherOrder() {
        var a = OfflineFilmTransfer(id: UUID(), accountID: "a")
        a.mediaFinished(); XCTAssertEqual(a.state, .verifying)
        a.keyPersisted(); XCTAssertEqual(a.state, .ready)
        var b = OfflineFilmTransfer(id: UUID(), accountID: "a")
        b.keyPersisted(); XCTAssertEqual(b.state, .downloading)
        b.mediaFinished(); XCTAssertEqual(b.state, .ready)
    }

    func testCancelOrFailureCannotBeResurrectedByLateCompletion() {
        var a = OfflineFilmTransfer(id: UUID(), accountID: "a")
        a.remove(); a.mediaFinished(); a.keyPersisted(); a.resume()
        XCTAssertEqual(a.state, .removed)
        var b = OfflineFilmTransfer(id: UUID(), accountID: "a")
        b.fail(); b.keyPersisted(); b.mediaFinished()
        XCTAssertEqual(b.state, .failed)
    }

    func testRestartAndStorageEvictionRequireActualPackageAndKey() {
        for (package, key) in [(false, true), (true, false), (false, false)] {
            var a = OfflineFilmTransfer(id: UUID(), accountID: "a")
            a.mediaFinished(); a.keyPersisted()
            a.restore(packageExists: package, keyExists: key, taskExists: false)
            XCTAssertEqual(a.state, .failed)
        }
        var interrupted = OfflineFilmTransfer(id: UUID(), accountID: "a")
        interrupted.restore(packageExists: false, keyExists: true, taskExists: true)
        XCTAssertEqual(interrupted.state, .downloading)
        interrupted.restore(packageExists: false, keyExists: true, taskExists: false)
        XCTAssertEqual(interrupted.state, .failed)
    }

    func testPauseResumeRepeatedEventsAreIdempotent() {
        var a = OfflineFilmTransfer(id: UUID(), accountID: "a")
        a.pause(); a.pause(); XCTAssertEqual(a.state, .paused)
        a.resume(); a.resume(); XCTAssertEqual(a.state, .downloading)
        a.mediaFinished(); a.mediaFinished(); a.keyPersisted(); a.keyPersisted()
        XCTAssertEqual(a.state, .ready)
    }

    func testStoppedSessionCannotReleaseReplacementInSameGeneration() {
        var owners = OfflineKeyOwners()
        let entitlement = UUID(), old = UUID(), replacement = UUID()
        XCTAssertNil(owners.claim(entitlement: entitlement, owner: old))
        XCTAssertEqual(owners.claim(entitlement: entitlement, owner: replacement), old)
        owners.release(entitlement: entitlement, owner: old)
        XCTAssertFalse(owners.owns(entitlement: entitlement, owner: old))
        XCTAssertTrue(owners.owns(entitlement: entitlement, owner: replacement))
        owners.release(entitlement: entitlement, owner: replacement)
        XCTAssertFalse(owners.owns(entitlement: entitlement, owner: replacement))
    }

    func testRawFilesAndUnapprovedOriginsCannotEnterOfflineDriver() throws {
        let hosts: Set<String> = ["media.example.test"]
        try OfflineFilmAsset(manifest: URL(string: "https://media.example.test/film/master.m3u8")!,
                             keyIdentifier: "skd://film-v1").validate(allowedHosts: hosts)
        for url in ["http://media.example.test/master.m3u8", "https://media.example.test/video.mp4",
                    "https://media.example.test.evil/master.m3u8", "file:///tmp/master.m3u8",
                    "https://user:password@media.example.test/master.m3u8", "https://media.example.test:8443/master.m3u8"] {
            XCTAssertThrowsError(try OfflineFilmAsset(manifest: URL(string: url)!, keyIdentifier: "skd://film-v1").validate(allowedHosts: hosts))
        }
        XCTAssertThrowsError(try OfflineFilmAsset(manifest: URL(string: "https://media.example.test/master.m3u8")!,
                                                  keyIdentifier: "https://key.example/key").validate(allowedHosts: hosts))
    }
}
