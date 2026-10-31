import XCTest
@testable import KhajistanCore

final class OfflineReconciliationTests: XCTestCase {
    func testTransientFailureRetriesWithoutAnotherPathChange() throws {
        var policy = OfflineReconciliationSchedule()
        policy.network(true, at: 0)
        let first = try XCTUnwrap(policy.begin(at: 0))
        policy.finish(first, succeeded: false, at: 1)
        XCTAssertEqual(policy.next, 31); XCTAssertNil(policy.begin(at: 30))
        let retry = try XCTUnwrap(policy.begin(at: 31))
        policy.finish(retry, succeeded: true, at: 32)
        XCTAssertNil(policy.next); XCTAssertNil(policy.inFlight)
    }

    func testReconnectWhilePendingRequiresAnotherCheck() throws {
        var policy = OfflineReconciliationSchedule()
        policy.network(true, at: 0)
        let first = try XCTUnwrap(policy.begin(at: 0))
        policy.network(false, at: 1); policy.network(true, at: 2)
        XCTAssertNil(policy.begin(at: 2))
        policy.finish(first, succeeded: true, at: 3)
        XCTAssertNotNil(policy.begin(at: 3))
    }

    func testFlappingAndForegroundCannotExceedSixRequestsPerHour() throws {
        var policy = OfflineReconciliationSchedule()
        policy.network(true, at: 0)
        for i in 0..<6 {
            policy.request(at: Double(i))
            let token = try XCTUnwrap(policy.begin(at: Double(i)))
            policy.finish(token, succeeded: true, at: Double(i))
        }
        for i in 6..<100 { policy.network(false, at: Double(i)); policy.network(true, at: Double(i)) }
        XCTAssertEqual(policy.next, 3600); XCTAssertNil(policy.begin(at: 3599))
        XCTAssertNotNil(policy.begin(at: 3600))
        policy.stop(); XCTAssertNil(policy.next); XCTAssertNil(policy.inFlight)
    }
}
