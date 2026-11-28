import AVFoundation
import Foundation

// Which tap an audio file gets (SignalTap.tapsBeforeEffects): an mp3 is known by its codec, read from
// the file's own track, so an mp3 behind an address that does not end in ".mp3" is tapped before
// effects too. After effects, an mp3 played silent on the Apple TV (PR 141). This runs on the Mac and
// proves the rule and the codec read; the silence itself is the Apple TV's and is checked on the device.
//   sh tvos/scripts/test-signal-tap.sh

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ ok: Bool, _ note: String, line: Int = #line) throws { if !ok { throw Failure(description: "line \(line): \(note)") } }

func track(_ path: String) async throws -> AVAssetTrack {
    let tracks = try await AVURLAsset(url: URL(fileURLWithPath: path)).loadTracks(withMediaType: .audio)
    guard let track = tracks.first else { throw Failure(description: "\(path): no audio track") }
    return track
}

@main
struct SignalTapTests {
    static func main() async {
        var failed = 0
        func run(_ name: String, _ body: () async throws -> Void) async {
            do { try await body(); print("PASS \(name)") } catch { failed += 1; print("FAIL \(name): \(error)") }
        }
        let aac = ProcessInfo.processInfo.environment["KJ_TAP_AAC"]
        let mp3 = ProcessInfo.processInfo.environment["KJ_TAP_MP3"]

        await run("the rule: an mp3 by codec or by address, nothing else") {
            try expect(SignalTap.tapsBeforeEffects(formatIDs: [kAudioFormatMPEGLayer3], pathExtension: ""), "an mp3 with no extension")
            try expect(SignalTap.tapsBeforeEffects(formatIDs: [kAudioFormatMPEGLayer3], pathExtension: "bin"), "an mp3 behind another extension")
            try expect(SignalTap.tapsBeforeEffects(formatIDs: [], pathExtension: "MP3"), "the address alone, as before")
            try expect(!SignalTap.tapsBeforeEffects(formatIDs: [kAudioFormatMPEG4AAC], pathExtension: "m4a"), "an m4a keeps the after-effects tap")
            try expect(!SignalTap.tapsBeforeEffects(formatIDs: [kAudioFormatMPEG4AAC], pathExtension: ""), "an AAC file with no extension")
            try expect(!SignalTap.tapsBeforeEffects(formatIDs: [], pathExtension: ""), "nothing known")
        }
        await run("a real AAC file reads as AAC and keeps the after-effects tap") {
            guard let aac else { throw Failure(description: "KJ_TAP_AAC not set") }
            let ids = await SignalTap.formatIDs(of: try await track(aac))
            try expect(ids == [kAudioFormatMPEG4AAC], "read \(ids)")
            try expect(!SignalTap.tapsBeforeEffects(formatIDs: ids, pathExtension: ""), "an AAC file was tapped before effects")
        }
        if let mp3 {
            await run("a real mp3 reads as an mp3, whatever its address says") {
                let ids = await SignalTap.formatIDs(of: try await track(mp3))
                try expect(ids == [kAudioFormatMPEGLayer3], "read \(ids)")
                try expect(SignalTap.tapsBeforeEffects(formatIDs: ids, pathExtension: ""), "an mp3 with no extension kept the after-effects tap")
                // The tap itself is made with the flag the rule gives.
                try expect(SignalTap().audioMix(for: try await track(mp3), preEffects: true) != nil, "no before-effects tap could be made")
            }
        } else {
            print("SKIP a real mp3 reads as an mp3 (no ffmpeg to make one)")
        }
        exit(failed == 0 ? 0 : 1)
    }
}
