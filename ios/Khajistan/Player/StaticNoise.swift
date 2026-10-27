import AVFoundation
import CoreAudio

/// The hiss between stations, made here rather than played from a file: white noise through a
/// one-pole low-pass, so it reads as a dial between frequencies rather than a fault. Its level
/// glides towards the level asked for, so it never clicks in or out.
final class StaticNoise {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var wired = false
    /// [0] the level asked for, written on the main thread; [1] the level now, the audio thread's.
    private let levels = UnsafeMutablePointer<Float>.allocate(capacity: 2)

    /// Loud enough to hear under a quiet room, well under a station at full volume.
    static let tuningLevel: Float = 0.22

    init() {
        levels.initialize(repeating: 0, count: 2)
        let levels = self.levels
        var low: Float = 0
        // A glide of about 120 ms at 48 kHz. ponytail: fixed rate; read the sample rate if a
        // device ever runs the engine far from 44.1–48 kHz.
        let glide: Float = 1.0 / (0.12 * 48_000)
        node = AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                levels[1] += (levels[0] - levels[1]) * glide
                low += 0.18 * (Float.random(in: -1...1) - low)
                let sample = low * 2.4 * levels[1]
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
    }

    /// The graph is wired on the first sound, not in `init`: touching `mainMixerNode` opens the
    /// audio device, and SwiftUI builds this object on every rebuild of the view that holds it.
    /// A simulator with no audio device hung there for ten seconds and then aborted (CI, 2026-10-27).
    private func wire() {
        guard !wired, let node else { return }
        wired = true
        engine.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    deinit {
        // An engine never wired never reached the device; leave it untouched.
        if wired { engine.stop() }
        levels.deallocate()
    }

    /// Asks for a level, 0 to silence. The engine starts on the first sound and stops once the
    /// glide to silence has run, so an idle dial costs no audio hardware.
    func set(_ level: Float) {
        levels[0] = level
        if level > 0 {
            wire()
            if !engine.isRunning { try? engine.start() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.levels[0] == 0 else { return }
            self.stop()
        }
    }

    func stop() {
        levels[0] = 0
        levels[1] = 0
        if wired { engine.stop() }
    }
}
