import Foundation
import XCTest
@testable import KhajistanCore

#if DEBUG
final class FixtureRoutingTests: XCTestCase {
    func testExplicitRecordedRoutingAndMediaFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("rest/v1"), withIntermediateDirectories: true)
        try Data("[{\"id\":\"fixture-room\"}]".utf8).write(to: directory.appendingPathComponent("rest/v1/chat_rooms"))
        UserDefaults.standard.set(directory.path, forKey: "kjfixtures")
        UserDefaults.standard.set(false, forKey: "kjfixturemedia")
        defer {
            UserDefaults.standard.removeObject(forKey: "kjfixtures")
            UserDefaults.standard.removeObject(forKey: "kjfixturemedia")
            try? FileManager.default.removeItem(at: directory)
        }

        let direct = URLRequest(url: SupabaseRoute.base(for: .direct).appendingPathComponent("rest/v1/chat_rooms"))
        XCTAssertNotNil(KJFixtureProtocol.file(for: direct))
        let proxy = URLRequest(url: KJConfig.site.appendingPathComponent("sb/rest/v1/chat_rooms"))
        XCTAssertEqual(KJFixtureProtocol.file(for: direct), KJFixtureProtocol.file(for: proxy))
        var post = direct
        post.httpMethod = "POST"
        XCTAssertNil(KJFixtureProtocol.file(for: post), "mutations must never be intercepted")
        XCTAssertNil(KJFixtureProtocol.file(for: URLRequest(url: KJConfig.site.appendingPathComponent("not-recorded"))))
        XCTAssertNil(try KJFixtureProtocol.mediaURL(for: "tv"), "media stays live unless explicitly enabled")
        UserDefaults.standard.set(true, forKey: "kjfixturemedia")
        XCTAssertThrowsError(try KJFixtureProtocol.mediaURL(for: "tv"), "missing fixtures must fail, never silently reach a live stream")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("media"), withIntermediateDirectories: true)
        try Data([0]).write(to: directory.appendingPathComponent("media/picture.mp4"))
        XCTAssertEqual(try KJFixtureProtocol.mediaURL(for: "tv"), directory.appendingPathComponent("media/picture.mp4"))
        XCTAssertThrowsError(try KJFixtureProtocol.mediaURL(for: "radio"))

        let session = URLSession(configuration: URLSessionConfiguration.ephemeral.answeringFromFixtures())
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: proxy)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[{\"id\":\"fixture-room\"}]")
    }
}

#endif
