import XCTest
@testable import KhajistanCore

final class LibraryStateTests: XCTestCase {
    /// A library written before `resume` existed still opens, with nothing lost.
    func testOlderLibraryFileStillDecodes() throws {
        let old = #"{"bookmarks":[{"id":"6F0C2D2E-6B57-4E0F-9A64-1D2B3C4D5E6F","url":"https://khajistan-archive.pages.dev/about.html","title":"About","date":0}],"history":[]}"#
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(old.utf8))
        XCTAssertEqual(state.bookmarks.count, 1)
        XCTAssertEqual(state.resume, [])
    }

    func testRecordKeepsOnePlacePerObjectNewestFirst() {
        var state = LibraryState()
        let first = Resume(kind: .reading, ref: "kayhan", part: "kayhan|1|0", position: 3, title: "Kayhan", detail: "No. 1", date: Date(timeIntervalSince1970: 1))
        let other = Resume(kind: .film, ref: "zinda-laash", part: nil, position: 120, title: "Zinda Laash", detail: "", date: Date(timeIntervalSince1970: 2))
        var moved = first
        moved.position = 9
        state.record(first)
        state.record(other)
        state.record(moved)
        XCTAssertEqual(state.resume.map(\.id), ["reading|kayhan", "film|zinda-laash"])
        XCTAssertEqual(state.place(.reading, "kayhan")?.position, 9)
        XCTAssertNil(state.place(.reading, "zinda-laash"), "a film handle is not a reading slug")
    }

    func testRecordIsBounded() {
        var state = LibraryState()
        for n in 0..<60 {
            state.record(Resume(kind: .film, ref: "f\(n)", part: nil, position: 0, title: "", detail: "", date: .now))
        }
        XCTAssertEqual(state.resume.count, 40)
        XCTAssertEqual(state.resume.first?.ref, "f59")
    }

    func testPageMarksToggleAndSurviveAnOlderFile() throws {
        var state = try JSONDecoder().decode(LibraryState.self, from: Data(#"{"bookmarks":[],"history":[]}"#.utf8))
        XCTAssertEqual(state.pageMarks, [], "a file from before page marks opens with none")
        state.togglePageMark(title: "kayhan", issue: "kayhan|1|0", page: 12)
        state.togglePageMark(title: "kayhan", issue: "kayhan|1|0", page: 3)
        state.togglePageMark(title: "kayhan", issue: "kayhan|2|1", page: 3)
        XCTAssertEqual(state.pageMarks(title: "kayhan", issue: "kayhan|1|0"), [3, 12])
        state.togglePageMark(title: "kayhan", issue: "kayhan|1|0", page: 12)
        XCTAssertEqual(state.pageMarks(title: "kayhan", issue: "kayhan|1|0"), [3], "a second press takes the mark off")
        let again = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(again.pageMarks(title: "kayhan", issue: "kayhan|2|1"), [3], "marks are written with the library")
    }
}
