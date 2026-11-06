import AVFoundation
import Foundation

// Drives the app's own PlayerController against server.py's carrier that stops sending (run.sh).
// Prints one PASS or FAIL line per case and exits non-zero on any FAIL.

#if os(iOS)
import MediaPlayer
/// The line under the title on the system's Now Playing card (lock screen, Control Centre).
@MainActor func cardLine() -> String? { MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] as? String }
#endif

@MainActor func isFailed(_ state: PlayerController.State) -> Bool {
    if case .failed = state { return true }
    return false
}

@MainActor func wait(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(200))
    }
    return condition()
}

@main
struct StallHarness {
    @MainActor static func main() async {
        let base = CommandLine.arguments[1]
        var failures = 0
        // The stall limit is 20 s. 35 s leaves room for it and still ends before the system's own
        // 60 s network timeout, so a pass here is the controller's doing.
        let limit = 35.0

        let stalled = PlayerController()
        stalled.attach(url: URL(string: base + "/tone.mp3?cut=80000")!, seekTo: nil, title: "stall", subtitle: nil)
        if await wait(20, { stalled.state == .playing }) {
            let since = Date()
            let ended = await wait(limit, { isFailed(stalled.state) })
            print((ended ? "PASS" : "FAIL") + " a stall mid-play ends in a failure after \(Int(Date().timeIntervalSince(since))) s (state: \(stalled.state))")
            if !ended { failures += 1 }
        } else {
            print("ERROR stall carrier never played (state: \(stalled.state))")
            exit(2)
        }
        stalled.stop()

        let paused = PlayerController()
        paused.attach(url: URL(string: base + "/tone.mp3?cut=720000")!, seekTo: nil, title: "seek", subtitle: nil)
        if await wait(20, { paused.state == .playing }) {
            paused.pause()
            paused.player.seek(to: CMTime(seconds: 100, preferredTimescale: 600)) { _ in }
            try? await Task.sleep(for: .seconds(1))
            paused.resume()
            let since = Date()
            let ended = await wait(limit, { isFailed(paused.state) })
            print((ended ? "PASS" : "FAIL") + " resuming a paused dead stream ends in a failure after \(Int(Date().timeIntervalSince(since))) s (state: \(paused.state))")
            if !ended { failures += 1 }
        } else {
            print("ERROR seek carrier never played (state: \(paused.state))")
            exit(2)
        }
        paused.stop()

        #if os(iOS)
        // The song on the lock screen: shown, put back after attach() resets it, cleared to the
        // place, and never written by a player that is not the active one.
        let song = PlayerController()
        song.attach(url: URL(string: base + "/tone.mp3?cut=720000")!, seekTo: nil, title: "Barış FM", subtitle: "Türkiye")
        song.showSong("BLOK3 – Sevmeyi Denemedin")
        let shown = cardLine() == "BLOK3 – Sevmeyi Denemedin"
        song.attach(url: URL(string: base + "/tone.mp3?cut=720000")!, seekTo: nil, title: "Barış FM", subtitle: "Türkiye")
        let reset = cardLine() == "Türkiye"
        song.showSong("BLOK3 – Sevmeyi Denemedin")
        let back = cardLine() == "BLOK3 – Sevmeyi Denemedin"
        song.showSong("")
        let cleared = cardLine() == "Türkiye"
        let other = PlayerController()
        other.showSong("Somebody Else – Not This")
        let untouched = cardLine() == "Türkiye"
        for (ok, what) in [(shown, "the song shows on the lock screen"), (reset && back, "attach resets the card to the place and showSong puts the song back"),
                           (cleared, "no song puts the place back"), (untouched, "a player that is not active writes nothing")] {
            print((ok ? "PASS " : "FAIL ") + what)
            if !ok { failures += 1 }
        }
        song.stop()
        #endif
        exit(failures == 0 ? 0 : 1)
    }
}
