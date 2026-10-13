import XCTest
@testable import KhajistanCore

final class ReceiverInteractionTests: XCTestCase {
    func testManualSelectionInvalidatesPendingAutomaticPlayback() throws {
        var opening = ReceiverOpeningPlayback()
        let ticket = try XCTUnwrap(opening.begin(active: true, ready: true, explicitDestination: false))
        opening.manualInteraction()
        XCTAssertFalse(opening.admits(ticket))
        XCTAssertNil(opening.begin(active: true, ready: true, explicitDestination: false))
    }

    func testRenderAndDismissalDoNotRepeatAutomaticPlayback() throws {
        var opening = ReceiverOpeningPlayback()
        let ticket = try XCTUnwrap(opening.begin(active: true, ready: true, explicitDestination: false))
        XCTAssertNil(opening.begin(active: true, ready: true, explicitDestination: false))
        XCTAssertTrue(opening.admits(ticket))
    }

    func testLeavingReceiverCancelsOldWorkAndNextVisitGetsNewTicket() throws {
        var opening = ReceiverOpeningPlayback()
        let old = try XCTUnwrap(opening.begin(active: true, ready: true, explicitDestination: false))
        XCTAssertNil(opening.begin(active: false, ready: true, explicitDestination: false))
        XCTAssertFalse(opening.admits(old))
        let next = try XCTUnwrap(opening.begin(active: true, ready: true, explicitDestination: false))
        XCTAssertNotEqual(old, next)
        XCTAssertTrue(opening.admits(next))
    }

    func testExplicitDeepLinkTakesPrecedenceOverRandomAutomaticChannel() {
        var opening = ReceiverOpeningPlayback()
        XCTAssertNil(opening.begin(active: true, ready: true, explicitDestination: true))
        XCTAssertNil(opening.begin(active: true, ready: true, explicitDestination: false))
    }

    func testActualPayloadRightsRefusalPreventsCaptionsAndExplainsWhy() throws {
        let payload = #"{"id":"pk-test","name":"Test signal","mediaType":"tv","streams":[{"id":"carrier"}],"activeStreamId":"carrier","primaryLanguage":"Urdu","languageCode":"ur","regionIds":["indus"],"captionsDenied":true}"#
        let denied = try JSONDecoder().decode(Channel.self, from: Data(payload.utf8))
        XCTAssertEqual(denied.captionsDenied, true)
        XCTAssertFalse(CaptionRules.eligible(denied, detected: nil, accuracy: nil))
        XCTAssertFalse(CaptionRules.parkedReason(denied, detected: nil, accuracy: nil).isEmpty)
        let permitted = try JSONDecoder().decode(Channel.self, from: Data(payload.replacingOccurrences(of: #""captionsDenied":true"#, with: #""captionsDenied":false"#).utf8))
        XCTAssertTrue(CaptionRules.eligible(permitted, detected: nil, accuracy: nil))
    }
}
