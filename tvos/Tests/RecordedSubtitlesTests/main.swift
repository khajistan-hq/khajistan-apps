import AVFoundation
import Foundation

// RecordedSubtitles with stored files only (no AVPlayerItem): several languages, the opener, the
// control stepping through them, cues read against the clock, and files that do not parse.
//   sh tvos/scripts/test-recorded-subtitles.sh

struct Failure: Error, CustomStringConvertible { let description: String }
struct Skip: Error { let reason: String }
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
            ("PiP hand-off: a stored-only language gives way to the manifest's, and comes back after", {
                // A master playlist carrying English and Persian subtitle groups, read from disk:
                // enough for AVFoundation's legible selection group; nothing plays.
                // AVFoundation reads HLS over HTTP: the script serves KJ_HLS_DIR at KJ_HLS_BASE.
                let env = ProcessInfo.processInfo.environment
                guard let dirPath = env["KJ_HLS_DIR"], let base = env["KJ_HLS_BASE"].flatMap(URL.init(string:)) else {
                    throw Skip(reason: "run through scripts/test-recorded-subtitles.sh, which serves the playlist")
                }
                let dir = URL(fileURLWithPath: dirPath)
                let sub = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:10,\ns.vtt\n#EXT-X-ENDLIST\n"
                try sub.write(to: dir.appendingPathComponent("subs.m3u8"), atomically: true, encoding: .utf8)
                try en.write(to: dir.appendingPathComponent("s.vtt"), atomically: true, encoding: .utf8)
                let master = """
                #EXTM3U
                #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",NAME="English",LANGUAGE="en",AUTOSELECT=YES,URI="subs.m3u8"
                #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",NAME="Persian",LANGUAGE="fa",AUTOSELECT=YES,URI="subs.m3u8"
                #EXT-X-STREAM-INF:BANDWIDTH=500000,SUBTITLES="s"
                subs.m3u8

                """
                try master.write(to: dir.appendingPathComponent("master.m3u8"), atomically: true, encoding: .utf8)
                let url = base.appendingPathComponent("master.m3u8")
                UserDefaults.standard.removeObject(forKey: SubtitleChoice.storeKey)
                let item = AVPlayerItem(asset: AVURLAsset(url: url))
                let subs = RecordedSubtitles()
                await subs.attach(item, film: nil, listed: SubtitleChoice.house, skin: .day)
                guard !subs.tracks.isEmpty else { throw Failure(description: "no legible group read from the served master playlist") }
                // The playlist's two first; macOS may add a system-made translated option after them.
                try expect(Array(subs.tracks.map(\.code).prefix(2)) == ["en", "fa"], "manifest tracks \(subs.tracks)")
                subs.addFiles([(.init(code: "ur", label: "Urdu"), ur)], first: nil) { 2.0 }
                try expect(subs.tracks.last?.code == "ur" && subs.tracks.filter { $0.code == "ur" }.count == 1, "Urdu added beside them")
                while subs.current != "ur" { subs.cycle() }
                try expect(subs.handOff(), "handed to AVPlayer")
                try expect(subs.isHandedOff, "AVPlayer draws now")
                try expect(subs.current != nil && subs.current != "ur", "a manifest language it can draw, not the Urdu file: \(String(describing: subs.current))")
                try expect(UserDefaults.standard.string(forKey: SubtitleChoice.storeKey) == "ur", "the viewer's own choice is not overwritten")
                var seen: [String?] = []
                for _ in 0..<(subs.tracks.count + 1) { subs.cycle(); seen.append(subs.current) }
                try expect(!seen.contains("ur"), "while handed off, the control skips the file: \(seen)")
                subs.reclaim()
                let group = try await item.asset.loadMediaSelectionGroup(for: .legible)
                try expect(group.map { item.currentMediaSelection.selectedMediaOption(in: $0) == nil } ?? false,
                           "reclaim switches the track off, so tvOS draws nothing before the screen's load")
                // The screen that reopens attaches its own object to the same item, and the window can
                // open again on it: nothing the first object left may still suppress the track.
                let again = RecordedSubtitles()
                await again.attach(item, film: nil, listed: SubtitleChoice.house, skin: .day)
                try expect(!again.tracks.isEmpty && again.current != nil, "the reopened screen offers and selects a track")
                try expect(again.handOff(), "handed to AVPlayer a second time")
                try expect(!item.outputs.contains { $0 is AVPlayerItemLegibleOutput },
                           "no suppressing output left on the item: \(item.outputs)")
                try expect(group.map { item.currentMediaSelection.selectedMediaOption(in: $0) != nil } ?? false,
                           "a track is selected for tvOS to draw in the window")
                var back: [String?] = []
                for _ in 0..<(again.tracks.count + 1) { again.cycle(); back.append(again.current) }
                try expect(!back.contains("ur"), "the reopened window still steps only through what it can draw: \(back)")
                // A stream with no stored file hands off as before; a load with no manifest never does.
                let files = RecordedSubtitles()
                files.load(files: [(.init(code: "en", label: "English"), en)], first: "en") { 2.0 }
                try expect(!files.handOff(), "a file programme has no track to hand over")
            }),
        ]
        for (name, body) in cases {
            do { try await body(); print("PASS \(name)") }
            catch let skip as Skip { print("SKIP \(name): \(skip.reason)") }
            catch { failed += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count) tests: \(cases.count - failed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
