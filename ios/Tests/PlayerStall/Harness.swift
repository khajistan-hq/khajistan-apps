import AVFoundation
import Foundation

// Drives the app's own PlayerController against server.py's carrier that stops sending (run.sh).
// Prints one PASS or FAIL line per case and exits non-zero on any FAIL.

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
        // The stall limit is 20 s, and a dead carrier is retuned once (a second's grace, ten
        // seconds of tone again on the first case) before the second stall is shown: 80 s.
        let limit = 80.0

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
        // A recording, so its retune comes back at 100 s, past the cut, and stalls again.
        paused.attach(url: URL(string: base + "/tone.mp3?cut=720000")!, seekTo: nil, title: "seek", subtitle: nil, isLive: false)
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

        // A carrier that stops sending for a while and then comes back: the stall is the
        // network's, and one retune plays on from where it stopped instead of showing a failure.
        let healing = PlayerController()
        healing.attach(url: URL(string: base + "/tone.mp3?cut=80000&heal=\(UUID().uuidString)")!, seekTo: nil,
                       title: "heal", subtitle: nil, isLive: false)
        if await wait(20, { healing.state == .playing }) {
            let since = Date()
            var sawFailure = false
            let recovered = await wait(limit, {
                if isFailed(healing.state) { sawFailure = true }
                // 80 000 bytes at 64 kb/s is 10 s of tone: past 13 s, it is playing past the cut.
                return sawFailure || (healing.state == .playing && healing.player.currentTime().seconds > 13)
            }) && !sawFailure
            print((recovered ? "PASS" : "FAIL") + " a carrier that comes back is retuned once and plays on after \(Int(Date().timeIntervalSince(since))) s (state: \(healing.state))")
            if !recovered { failures += 1 }
        } else {
            print("ERROR heal carrier never played (state: \(healing.state))")
            exit(2)
        }
        healing.stop()
        exit(failures == 0 ? 0 : 1)
    }
}
