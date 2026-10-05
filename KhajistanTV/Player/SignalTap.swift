import Accelerate
import AVFoundation
import MediaToolbox
import os

/// Reads the samples of the signal that is actually playing, so the dancer moves to real audio
/// and never to a timer (kj-scope.js: "Nothing here animates to invented audio").
///
/// An MTAudioProcessingTap on the item's audio mix hands over the decoded PCM, which passes
/// through untouched. On AVFoundation's own audio thread it is mixed to mono and, every sixtieth
/// of a second of audio, turned into what the website's AnalyserNode gives kj-scope.js (fftSize
/// 1024, smoothingTimeConstant .72, -85 to -25 dB, a Blackman window): 512 spectrum bytes, plus
/// the RMS of the same 1024 samples. Each spectrum is stamped with the item time of its last
/// sample, so the main actor can read them in step with what is being heard.
///
/// WHICH CARRIERS CAN SHOW HIM. A tap needs an audio track on the asset, and AVFoundation exposes
/// one only for a finite progressive file: a Khajistan Transmission programme on Supabase storage
/// or a Dropbox temporary link. `PlayerController` asks the asset for its audio tracks and
/// installs the tap only when there is one. A live Icecast or Shoutcast mount exposes no track
/// (measured 2026-10-05), so LiveRadio plays those itself and feeds this the buffers it
/// schedules. HLS (Cloudflare Stream, a broadcaster's .m3u8) exposes nothing to either: no
/// samples, no dancer.
final class SignalTap: @unchecked Sendable {
    struct Frame {
        let time: Double       // ms of item time, at the window's last sample
        let rms: Double
        let spectrum: [UInt8]
    }

    static let fftSize = 1024
    static let bins = fftSize / 2
    /// Ten seconds of spectra. LiveRadio stamps them as it schedules, up to three seconds ahead of
    /// the speaker plus the length of one decoded chunk; a ring shorter than that overwrote the
    /// spectra about to be heard (measured: 51 a second falling to 34).
    private static let slots = 600
    private static let smoothing: Float = 0.72
    private static let minDB: Float = -85, maxDB: Float = -25

    /// The sample rate of the audio being read, for the band edges.
    private(set) var sampleRate = 44100.0

    // Analysis state: touched only on the tap's thread, between prepare and unprepare.
    private var ring = [Float](repeating: 0, count: SignalTap.fftSize)
    private var ringPos = 0
    private var filled = 0
    private var sinceHop = 0
    private var hop = 735
    private var floatFormat = false
    private var interleaved = false
    private var channels = 1
    private let window: [Float]
    private var windowed = [Float](repeating: 0, count: SignalTap.fftSize)
    private var real = [Float](repeating: 0, count: SignalTap.bins)
    private var imag = [Float](repeating: 0, count: SignalTap.bins)
    private var smoothed = [Float](repeating: 0, count: SignalTap.bins)
    private let setup: FFTSetup

    // Published spectra: a ring of slots, written on the tap's thread, read on the main actor.
    private let lock = OSAllocatedUnfairLock()
    private var outBytes = [UInt8](repeating: 0, count: SignalTap.slots * SignalTap.bins)
    private var outTime = [Double](repeating: 0, count: SignalTap.slots)
    private var outRMS = [Double](repeating: 0, count: SignalTap.slots)
    private var written = 0

    init() {
        let n = SignalTap.fftSize
        // The Blackman window Web Audio's AnalyserNode applies (alpha .16).
        window = (0..<n).map { i in
            let x = Float(i) / Float(n)
            return 0.42 - 0.5 * cos(2 * .pi * x) + 0.08 * cos(4 * .pi * x)
        }
        setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))!
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// An audio mix that taps `track`, or nil if the tap could not be made.
    func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<SignalTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<SignalTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                var range = CMTimeRange()
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, &range, framesOut) == noErr else { return }
                Unmanaged<SignalTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .consume(buffers, count: Int(framesOut.pointee), start: range.start)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            // The tap never took the retain it was handed.
            Unmanaged.passUnretained(self).release()
            return nil
        }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }

    /// The spectra written since `seq`, oldest first, up to `time` (ms of item time) when one is
    /// given. A spectrum further ahead than that waits for the audio to reach it.
    func take(after seq: inout Int, upTo time: Double?) -> [Frame] {
        let start = seq
        let (out, next): ([Frame], Int) = lock.withLock {
            var out: [Frame] = []
            var cursor = max(start, written - SignalTap.slots)   // fell behind: drop the oldest
            while cursor < written {
                let slot = cursor % SignalTap.slots
                // A stamp more than ten seconds ahead of the clock is not on it; read on.
                if let time, outTime[slot].isFinite, outTime[slot] > time, outTime[slot] < time + 10000 { break }
                let base = slot * SignalTap.bins
                out.append(Frame(time: outTime[slot], rms: outRMS[slot], spectrum: Array(outBytes[base..<base + SignalTap.bins])))
                cursor += 1
            }
            return (out, cursor)
        }
        seq = next
        return out
    }

    // MARK: - Fed by LiveRadio, on its queue

    func prepare(for format: AVAudioFormat) {
        prepare(format.streamDescription.pointee)
    }

    /// A decoded buffer that will be heard at `ms` on the player's clock.
    func consume(_ buffer: AVAudioPCMBuffer, atMS ms: Double) {
        consume(buffer.mutableAudioBufferList, count: Int(buffer.frameLength),
                start: CMTime(seconds: ms / 1000, preferredTimescale: 1_000_000))
    }

    // MARK: - The tap's thread

    private func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100
        hop = max(1, Int((sampleRate / 60).rounded()))
        floatFormat = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
        interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        channels = max(1, Int(format.mChannelsPerFrame))
        filled = 0; ringPos = 0; sinceHop = 0
        for i in 0..<smoothed.count { smoothed[i] = 0 }
    }

    private func consume(_ list: UnsafeMutablePointer<AudioBufferList>, count: Int, start: CMTime) {
        // Anything but 32-bit float PCM is left alone: no spectra, so no dancer, never a guess.
        guard floatFormat, count > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        // Item time when AVFoundation gives it; otherwise the spectra carry no stamp (NaN) and the
        // dancer reads them as they arrive. The first buffers of a seeked file come unstamped.
        let origin = start.isNumeric ? start.seconds : .nan
        let scale = 1 / Float(channels)
        for i in 0..<count {
            var mono: Float = 0
            if interleaved {
                guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
                for c in 0..<channels { mono += data[i * channels + c] }
            } else {
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    mono += data[i]
                }
            }
            ring[ringPos] = mono * scale
            ringPos = (ringPos + 1) % SignalTap.fftSize
            if filled < SignalTap.fftSize { filled += 1 }
            sinceHop += 1
            if sinceHop >= hop && filled == SignalTap.fftSize {
                sinceHop = 0
                analyse(time: (origin + Double(i + 1) / sampleRate) * 1000)
            }
        }
    }

    /// One AnalyserNode reading of the last 1024 samples.
    private func analyse(time: Double) {
        let n = SignalTap.fftSize
        var power: Float = 0
        for i in 0..<n {
            let sample = ring[(ringPos + i) % n]
            power += sample * sample
            windowed[i] = sample * window[i]
        }
        let rms = Double((power / Float(n)).squareRoot())
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))
            }
        }
        // zrip leaves every bin at twice the DFT, with the Nyquist term packed into imag[0].
        // Web Audio scales the magnitude by 1/fftSize, smooths, then maps dB onto a byte.
        let norm = 1 / (2 * Float(n))
        let span = SignalTap.maxDB - SignalTap.minDB
        lock.withLock {
            let base = (written % SignalTap.slots) * SignalTap.bins
            for k in 0..<SignalTap.bins {
                let magnitude = (k == 0 ? abs(real[0]) : (real[k] * real[k] + imag[k] * imag[k]).squareRoot()) * norm
                smoothed[k] = SignalTap.smoothing * smoothed[k] + (1 - SignalTap.smoothing) * magnitude
                let db = smoothed[k] > 0 ? 20 * log10(smoothed[k]) : -1000
                let byte = 255 * (db - SignalTap.minDB) / span
                outBytes[base + k] = UInt8(max(0, min(255, byte)))
            }
            outTime[written % SignalTap.slots] = time
            outRMS[written % SignalTap.slots] = rms
            written += 1
        }
    }
}
