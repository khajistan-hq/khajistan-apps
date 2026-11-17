import XCTest
@testable import KhajistanCore

final class ReadingLoadContextTests: XCTestCase {
    func testCredentialTransitionRetriesAndRejectsPriorLoads() {
        var context = RRShelfLoadContext()
        XCTAssertTrue(context.update(nil))
        let open = context.generation
        XCTAssertFalse(context.update(nil), "reopening the same shelf keeps its cached load")
        XCTAssertTrue(context.update("test-only-preview"))
        let gated = context.generation
        XCTAssertFalse(context.accepts(open, credential: "test-only-preview"))
        XCTAssertTrue(context.accepts(gated, credential: "test-only-preview"))
        context.invalidate(nil)
        XCTAssertFalse(context.accepts(gated, credential: nil), "a response after Clear cannot publish or write its cache")
        XCTAssertTrue(context.update("test-only-preview"))
        XCTAssertFalse(context.accepts(gated, credential: "test-only-preview"), "returning to a credential cannot revive its older request")
    }

    func testExplicitClearInvalidatesEvenAnAlreadyOpenContext() {
        var context = RRShelfLoadContext()
        XCTAssertTrue(context.update(nil))
        let pending = context.generation
        context.invalidate(nil)
        XCTAssertFalse(context.accepts(pending, credential: nil))
        XCTAssertFalse(context.update(nil))
        XCTAssertTrue(context.accepts(context.generation, credential: nil))
    }
}
