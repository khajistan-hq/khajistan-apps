import XCTest
@testable import KhajistanCore

/// `-kjfixtures`: the network first, the recording when the network fails (UI tests on CI).
final class FixtureProtocolTests: XCTestCase {
    private static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kj-fixture-test")
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("data"), withIntermediateDirectories: true)
        try? Data(#"{"recorded":true}"#.utf8).write(to: dir.appendingPathComponent("data/answer.json"))
        return dir
    }()

    private func session() -> URLSession {
        // Read per request, and other tests in this process point it elsewhere: set it every time.
        UserDefaults.standard.set(Self.directory.path, forKey: "kjfixtures")
        UserDefaults.standard.set(false, forKey: "kjfixturesonly")
        return URLSession(configuration: URLSessionConfiguration.ephemeral.answeringFromFixtures())
    }

    /// Nothing listens on port 9 here: the connection fails at once and the recording answers.
    func testAFailedConnectionIsAnsweredFromTheRecording() async throws {
        let (data, response) = try await session().data(from: URL(string: "http://127.0.0.1:9/data/answer.json")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"recorded":true}"#)
    }

    /// No recording for the path: the protocol stays out of the way and the failure stands.
    func testAPathWithNoRecordingStillFails() async {
        do {
            _ = try await session().data(from: URL(string: "http://127.0.0.1:9/data/missing.json")!)
            XCTFail("a dead connection with no recording must fail")
        } catch {}
    }
}
