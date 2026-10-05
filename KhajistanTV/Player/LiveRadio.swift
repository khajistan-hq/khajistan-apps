import AudioToolbox
import AVFoundation

/// A live radio mount played by the app itself, so the dancer can hear it.
///
/// AVPlayer plays an Icecast or Shoutcast mount, but gives a tap nothing to read: the asset
/// reports no tracks, and a tap installed on the item's own track is never prepared (measured
/// 2026-10-05 on FM 101 Lahore, whmsonic.radio.gov.pk, three ways). The website met the same wall
/// on Safari (FLAG-230) and answered it with its own player (open-frequencies.js
/// startLivePlayer, owner 2026-09-18: "I want the dancer in my Safari"); this is that player:
///
/// - ONE fetch of the mount. A second connection for analysis starts up to a second apart from
///   the one being heard, and nothing says how far (the site measured it and did not ship it).
/// - Packets cut by AudioFileStream (MP3, or AAC in ADTS), decoded by AVAudioConverter, and
///   scheduled back to back on an AVAudioPlayerNode, each buffer at an explicit sample time.
/// - The dancer analyses each buffer as it is scheduled, stamped with that sample time, so what
///   he hears is the sample the listener hears when it is heard.
/// - About three seconds are committed ahead of the speaker and up to six more may wait; older
///   audio is dropped, so a mount that opens with a burst of its ring buffer (FM 101 sends ~14 s)
///   does not leave the listener that far behind live.
/// - Another content type, or no packet in the first 64 KB, or a fetch that fails before any
///   sound: the stream is handed back to AVPlayer and plays plainly, with no dancer.
/// - Twelve seconds with no bytes, or the mount closing, is a dead carrier.
final class LiveRadio: @unchecked Sendable {
    enum Event: Sendable {
        case started
        case failed(String)
        case fallback(String)
    }

    /// The dancer's ears: the same analysis the item tap uses, fed from here.
    let signal = SignalTap()

    private static let preroll = 1.5, lead = 3.0, maxWait = 6.0, stall = 12.0

    private let queue = DispatchQueue(label: "com.khajistan.tv.liveradio")
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let userAgent: String
    private let onEvent: @Sendable (Event) -> Void

    // Everything below is touched only on `queue`.
    private var session: URLSession?
    private var stream: AudioFileStreamID?
    private var inFormat: AVAudioFormat?
    private var outFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var maxPacket: UInt32 = 0
    private var packetBytes = Data()
    private var packetDescs: [AudioStreamPacketDescription] = []
    private var packetFrames = 0.0
    private var waiting: [AVAudioPCMBuffer] = []
    private var waitingSeconds = 0.0
    private var started = false
    private var nextAt: AVAudioFramePosition = 0
    private var bytesSeen = 0
    private var lastBytes = Date()
    private var ended = false
    private var stopped = false
    private var tick: DispatchSourceTimer?
    private(set) var underruns = 0
    private(set) var dropped = 0

    init(userAgent: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.userAgent = userAgent
        self.onEvent = onEvent
        engine.attach(node)
    }

    deinit {
        if let stream { AudioFileStreamClose(stream) }
    }

    // MARK: - Controls (any thread)

    func start(url: URL) {
        queue.async { [self] in
            #if os(tvOS) || os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            #endif
            let operations = OperationQueue()
            operations.underlyingQueue = queue
            operations.maxConcurrentOperationCount = 1
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config, delegate: Receiver(self), delegateQueue: operations)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            session.dataTask(with: request).resume()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
            timer.setEventHandler { [weak self] in self?.onTick() }
            timer.resume()
            tick = timer
        }
    }

    func stop() {
        queue.async { [self] in teardown() }
    }

    func pause() { node.pause() }
    func resume() { node.play() }

    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    var isPlaying: Bool { node.isPlaying }

    /// The node's own clock, in ms: the sample at the speaker, in the time the analysis is stamped in.
    var playTimeMS: Double? {
        guard let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render),
              time.sampleRate > 0 else { return nil }
        return Double(time.sampleTime) / time.sampleRate * 1000
    }

    // MARK: - The network (queue)

    fileprivate func received(_ response: URLResponse) -> Bool {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { fallBack("http-\(status)"); return false }
        let type = (response.mimeType ?? "").lowercased()
        let hint: AudioFileTypeID
        if ["audio/mpeg", "audio/mp3", "audio/mpa", "application/octet-stream"].contains(type) {
            hint = kAudioFileMP3Type
        } else if ["audio/aac", "audio/aacp", "audio/x-aac"].contains(type) {
            hint = kAudioFileAAC_ADTSType
        } else {
            fallBack("type:\(type)")
            return false
        }
        var id: AudioFileStreamID?
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status2 = AudioFileStreamOpen(me, { client, stream, property, _ in
            Unmanaged<LiveRadio>.fromOpaque(client).takeUnretainedValue().property(stream, property)
        }, { client, bytes, packets, data, descriptions in
            Unmanaged<LiveRadio>.fromOpaque(client).takeUnretainedValue()
                .packets(bytes: bytes, count: packets, data: data, descriptions: descriptions)
        }, hint, &id)
        guard status2 == noErr, let id else { fallBack("parser"); return false }
        stream = id
        return true
    }

    fileprivate func received(_ data: Data) {
        guard !stopped, let stream else { return }
        bytesSeen += data.count
        lastBytes = Date()
        data.withUnsafeBytes { raw in
            _ = AudioFileStreamParseBytes(stream, UInt32(raw.count), raw.baseAddress!, [])
        }
        // After the parse, not before it: a mount that opens with a burst hands the first read
        // hundreds of KB, and that is not "no frame in 64 KB".
        if !started && inFormat == nil && bytesSeen > 65536 { fallBack("no-frames") }
    }

    fileprivate func finished(_ error: Error?) {
        guard !stopped else { return }
        if !started && waiting.isEmpty {
            fallBack("fetch-failed")
        } else {
            ended = true
            drain()
        }
    }

    // MARK: - Parsing and decoding (queue)

    private func property(_ stream: AudioFileStreamID, _ property: AudioFileStreamPropertyID) {
        guard property == kAudioFileStreamProperty_ReadyToProducePackets else { return }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr,
              let input = AVAudioFormat(streamDescription: &asbd),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate,
                                         channels: AVAudioChannelCount(min(2, max(1, asbd.mChannelsPerFrame))), interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else {
            fallBack("format")
            return
        }
        var cookieSize: UInt32 = 0
        var writable: DarwinBoolean = false
        if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable) == noErr, cookieSize > 0 {
            var cookie = Data(count: Int(cookieSize))
            let ok = cookie.withUnsafeMutableBytes { AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, $0.baseAddress!) }
            if ok == noErr { converter.magicCookie = cookie }
        }
        var bound: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &bound) == noErr { maxPacket = bound }
        inFormat = input
        outFormat = output
        self.converter = converter
        engine.connect(node, to: engine.mainMixerNode, format: output)
        signal.prepare(for: output)
    }

    private func packets(bytes: UInt32, count: UInt32, data: UnsafeRawPointer, descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let input = inFormat, count > 0 else { return }
        let asbd = input.streamDescription.pointee
        let base = packetBytes.count
        packetBytes.append(data.assumingMemoryBound(to: UInt8.self), count: Int(bytes))
        for i in 0..<Int(count) {
            var d = descriptions?[i] ?? AudioStreamPacketDescription(
                mStartOffset: Int64(i) * Int64(asbd.mBytesPerPacket), mVariableFramesInPacket: 0, mDataByteSize: asbd.mBytesPerPacket)
            d.mStartOffset += Int64(base)
            maxPacket = max(maxPacket, d.mDataByteSize)
            packetDescs.append(d)
        }
        let perPacket = asbd.mFramesPerPacket > 0 ? Double(asbd.mFramesPerPacket) : 1152
        packetFrames += perPacket * Double(count)
        // Decode in half-second chunks.
        if packetFrames / asbd.mSampleRate >= 0.5 { decode() }
    }

    private func decode() {
        guard let input = inFormat, let output = outFormat, let converter, !packetDescs.isEmpty else { return }
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: AVAudioPacketCount(packetDescs.count),
                                                 maximumPacketSize: Int(max(maxPacket, 1)))
        packetBytes.withUnsafeBytes { raw in
            compressed.data.copyMemory(from: raw.baseAddress!, byteCount: min(raw.count, Int(compressed.byteCapacity)))
        }
        for (i, d) in packetDescs.enumerated() { compressed.packetDescriptions?[i] = d }
        compressed.packetCount = AVAudioPacketCount(packetDescs.count)
        compressed.byteLength = UInt32(min(packetBytes.count, Int(compressed.byteCapacity)))
        let capacity = AVAudioFrameCount(packetFrames * output.sampleRate / input.sampleRate + 4096)
        packetBytes.removeAll(keepingCapacity: true)
        packetDescs.removeAll(keepingCapacity: true)
        packetFrames = 0
        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var given = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if given { outStatus.pointee = .noDataNow; return nil }
            given = true
            outStatus.pointee = .haveData
            return compressed
        }
        guard status != .error, pcm.frameLength > 0 else { return }
        waiting.append(pcm)
        waitingSeconds += Double(pcm.frameLength) / output.sampleRate
        schedule()
    }

    // MARK: - Scheduling (queue)

    private func nodeNow(_ rate: Double) -> AVAudioFramePosition {
        guard let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) else { return 0 }
        return time.sampleTime
    }

    private func schedule() {
        guard let output = outFormat, !stopped else { return }
        let rate = output.sampleRate
        // A burst, or what piled up while paused: step past the oldest.
        while waitingSeconds > LiveRadio.maxWait && waiting.count > 1 {
            waitingSeconds -= Double(waiting.removeFirst().frameLength) / rate
            dropped += 1
        }
        if !started {
            guard waitingSeconds >= LiveRadio.preroll || ended else { return }
            do {
                engine.prepare()
                try engine.start()
            } catch {
                fallBack("engine")
                return
            }
            node.play()
            started = true
            nextAt = AVAudioFramePosition(0.05 * rate)
            onEvent(.started)
        }
        while !waiting.isEmpty {
            let now = nodeNow(rate)
            if Double(nextAt - now) / rate > LiveRadio.lead { return }
            let buffer = waiting.removeFirst()
            waitingSeconds -= Double(buffer.frameLength) / rate
            var at = nextAt
            if at < now { underruns += 1; at = now + AVAudioFramePosition(0.02 * rate) }
            node.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: at, atRate: rate))
            signal.consume(buffer, atMS: Double(at) / rate * 1000)
            nextAt = at + AVAudioFramePosition(buffer.frameLength)
        }
    }

    private func onTick() {
        guard !stopped else { return }
        schedule()
        drain()
        if Date().timeIntervalSince(lastBytes) > LiveRadio.stall && !ended {
            dead("The signal stopped.")
        }
    }

    /// The mount closed: whatever is buffered plays out, and then the carrier is dead.
    private func drain() {
        guard ended, started, waiting.isEmpty, let output = outFormat else { return }
        if nodeNow(output.sampleRate) >= nextAt { dead("The signal stopped.") }
    }

    private func dead(_ message: String) {
        guard !stopped else { return }
        teardown()
        onEvent(.failed(message))
    }

    private func fallBack(_ why: String) {
        guard !stopped else { return }
        teardown()
        onEvent(.fallback(why))
    }

    private func teardown() {
        guard !stopped else { return }
        stopped = true
        tick?.cancel()
        tick = nil
        session?.invalidateAndCancel()
        session = nil
        node.stop()
        engine.stop()
        waiting.removeAll()
    }
}

/// The URLSession delegate, held by the session and holding the player weakly.
private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var radio: LiveRadio?
    init(_ radio: LiveRadio) { self.radio = radio }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(radio?.received(response) == true ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        radio?.received(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        radio?.finished(error)
    }
}
