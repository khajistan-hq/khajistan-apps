import Foundation

// RecordedSubtitles with stored files only (no AVPlayerItem): several languages, the opener, the
// control stepping through them, cues read against the clock, and files that do not parse.
//   sh tvos/scripts/test-recorded-subtitles.sh

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ ok: Bool, _ note: String, line: Int = #line) throws { if !ok { throw Failure(description: "line \(line): \(note)") } }

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
                try await Task.sleep(for: .milliseconds(250))
                try expect(subs.text == "اردو سطر", "text \(String(describing: subs.text))")
                subs.cycle()
                try expect(subs.current == nil, "off after the last")
                try await Task.sleep(for: .milliseconds(250))
                try expect(subs.text == nil, "no text when off")
                subs.cycle()
                try await Task.sleep(for: .milliseconds(250))
                try expect(subs.current == "en" && subs.text == "English line", "back to the first")
            }),
            ("an opener not offered falls to the first file; a repeat language and a bad file are skipped", {
                let subs = RecordedSubtitles()
                subs.load(files: [(.init(code: "en", label: "English"), en), (.init(code: "en", label: "English 2"), ur),
                                  (.init(code: "fa", label: "Persian"), "<html>")], first: "he") { 2.0 }
                try expect(subs.tracks.map(\.code) == ["en"], "tracks \(subs.tracks)")
                try expect(subs.current == "en", "opener")
            }),
            ("handed to the window, the control steps through manifest languages only", {
                let codes = ["en", "fa", "ur"]   // the manifest's English and Persian, a stored Urdu
                try expect(RecordedSubtitles.windowCodes(codes, manifest: ["en", "fa"], handedOff: true) == ["en", "fa"],
                           "the stored Urdu is not offered in the window")
                try expect(RecordedSubtitles.windowCodes(codes, manifest: ["en", "fa"], handedOff: false) == codes,
                           "full screen the house view draws it, so it stays")
                try expect(RecordedSubtitles.windowCodes(["ur"], manifest: [], handedOff: false) == ["ur"],
                           "a file programme's files, never handed off, all stay")
            }),
            ("a file-only programme cannot be handed off, so its files stay on for the compositor", {
                let subs = RecordedSubtitles()
                subs.load(files: [(.init(code: "ur", label: "Urdu"), ur)], first: "ur") { 2.0 }
                try expect(!subs.handOff() && !subs.isHandedOff && subs.current == "ur", "no group: nothing handed off")
                subs.cycle()
                try expect(subs.current == nil, "off after the one file")
            }),
            ("revision moves once per load, so a load can tell when another took over", {
                let subs = RecordedSubtitles()
                let before = subs.revision
                subs.load(files: [(.init(code: "ur", label: "Urdu"), ur)], first: "ur") { 2.0 }
                try expect(subs.revision == before + 1, "its own load: one step")
                subs.clear()
                try expect(subs.revision == before + 2, "another load's clear: a second step")
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
