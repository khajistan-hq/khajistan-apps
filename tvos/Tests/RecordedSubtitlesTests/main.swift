import Foundation

// RecordedSubtitles with stored files only (no AVPlayerItem): several languages, the opener, the
// control stepping through them, cues read against the clock, and files that do not parse.
//   sh tvos/scripts/test-recorded-subtitles.sh

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ ok: Bool, _ note: String, line: Int = #line) throws { if !ok { throw Failure(description: "line \(line): \(note)") } }
/// Waits for the 100 ms ticker rather than a fixed sleep: a busy CI runner can miss a single 250 ms window.
@MainActor func eventually(_ ok: @MainActor () -> Bool, _ note: String, line: Int = #line) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !ok() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    try expect(ok(), note, line: line)
}

let en = "WEBVTT\n\n00:00:01.000 --> 00:00:05.000\nEnglish line\n"
let ur = "WEBVTT\n\nNOTE machine subtitles\n\n00:00:01.000 --> 00:00:05.000\nاردو سطر\n"

@main
struct Main {
    @MainActor static func main() async {
        var failed = 0
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("several files: opener, cues, step through and off", {
                let subs = RecordedSubtitles()
                subs.load(files: [(.init(code: "en", label: "English"), en), (.init(code: "ur", label: "Urdu"), ur)], first: "ur") { 2.0 }
                try expect(subs.tracks.map(\.code) == ["en", "ur"], "tracks \(subs.tracks)")
                try expect(subs.current == "ur", "opener \(String(describing: subs.current))")
                try await eventually({ subs.text == "اردو سطر" }, "text \(String(describing: subs.text))")
                subs.cycle()
                try expect(subs.current == nil, "off after the last")
                try await eventually({ subs.text == nil }, "no text when off")
                subs.cycle()
                try await eventually({ subs.current == "en" && subs.text == "English line" }, "back to the first")
            }),
            ("an opener not offered falls to the first file; a repeat language and a bad file are skipped", {
                let subs = RecordedSubtitles()
                subs.load(files: [(.init(code: "en", label: "English"), en), (.init(code: "en", label: "English 2"), ur),
                                  (.init(code: "fa", label: "Persian"), "<html>")], first: "he") { 2.0 }
                try expect(subs.tracks.map(\.code) == ["en"], "tracks \(subs.tracks)")
                try expect(subs.current == "en", "opener")
            }),
            ("nothing that parses offers no control", {
                let subs = RecordedSubtitles()
                subs.load(files: [(.init(code: "ur", label: "Urdu"), "not vtt")], first: "ur") { 2.0 }
                try expect(subs.tracks.isEmpty && subs.current == nil, "empty")
            }),
        ]
        for (name, body) in cases {
            do { try await body(); print("PASS \(name)") } catch { failed += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count) tests: \(cases.count - failed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
