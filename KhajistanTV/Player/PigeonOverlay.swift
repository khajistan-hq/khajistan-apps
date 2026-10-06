import AVFoundation
import Metal
import QuartzCore
import Observation
import SwiftUI
import UIKit

/// The pigeon flying over the live picture while the channel hard-cuts behind it (owner,
/// 2026-10-06: "hard cut is ok from one channel to next ... and the pigeon transition on it",
/// using the flights they starred in Higgsfield; "use the longer one only for channels that take
/// longer than 8-10 secs to load").
///
/// Each flight is the bird alone, HEVC with alpha, with a sidecar saying its length and `cut`:
/// the last moment the bird covers the most of the screen, which is where the channel changes
/// if the new one is ready (tvos/scripts/flights/, KJ_OVERLAY=1).
@MainActor @Observable
final class PigeonOverlay {
    struct Flight: Equatable {
        let name: String
        let colour: URL
        let matte: URL
        let length: Double
        let cut: Double
        /// How much of the screen the bird covers at `cut`. Under half, there is nothing to hide the
        /// cut behind, so the channel cuts the moment it is ready.
        let cutCover: Double
        var waitsForCover: Bool { cutCover >= 0.5 }
    }

    /// Short flights carry an ordinary change; the long ones only a channel that took 8 s or
    /// more to tune here before.
    static let short = ["across", "swerve", "hover", "lift"]
    static let long = ["loop", "twirl"]
    static let slowChannel = 8.0

    /// A flight is on screen.
    private(set) var showing = false
    /// The flight on screen, or the last one.
    private(set) var current: Flight?

    /// The bird's picture and its matte, two ordinary H.264 videos the Apple TV decodes in
    /// hardware, played in step and drawn together by `PigeonRenderer`.
    let colourPlayer = AVPlayer()
    let mattePlayer = AVPlayer()
    let renderer = PigeonRenderer()

    @ObservationIgnored private var flights: [String: Flight] = [:]
    @ObservationIgnored private var turn = 0
    @ObservationIgnored private var last: String?
    @ObservationIgnored private var armed: Flight?
    @ObservationIgnored private var ended: Signal?

    init() {
        for player in [colourPlayer, mattePlayer] {
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
        }
        for name in Self.short + Self.long { if let flight = Self.load(name) { flights[name] = flight } }
    }

    /// The flight for a channel expected to take `expected` seconds, turning through its pool and
    /// never the one that flew last.
    func pick(expected: Double) -> Flight? {
        let pool = (expected >= Self.slowChannel ? Self.long : Self.short).compactMap { flights[$0] }
        let options = pool.filter { $0.name != last }
        let list = options.isEmpty ? pool : options
        guard !list.isEmpty else { return nil }
        turn += 1
        return list[turn % list.count]
    }

    /// Loads a flight's two videos at their first frame, decoders warmed.
    func arm(_ flight: Flight) async {
        if armed == flight { return }
        armed = nil
        let colour = AVPlayerItem(url: flight.colour), matte = AVPlayerItem(url: flight.matte)
        renderer.attach(colour: colour, matte: matte)
        colourPlayer.replaceCurrentItem(with: colour)
        mattePlayer.replaceCurrentItem(with: matte)
        while colour.status == .unknown || matte.status == .unknown { try? await Task.sleep(for: .milliseconds(20)) }
        guard colour.status == .readyToPlay, matte.status == .readyToPlay else { return }
        async let a: Bool = colourPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        async let b: Bool = mattePlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await (a, b)
        async let c: Bool = colourPlayer.preroll(atRate: 1)
        async let d: Bool = mattePlayer.preroll(atRate: 1)
        _ = await (c, d)
        if colourPlayer.currentItem === colour { armed = flight }
    }

    /// Plays the armed flight over the picture, both videos started on the same host time.
    /// Returns at once; `waitForEnd` returns when the bird has gone.
    func start() {
        guard let flight = armed, let item = colourPlayer.currentItem else { return }
        last = flight.name
        current = flight
        armed = nil
        let done = Signal()
        ended = done
        var tokens: [NSObjectProtocol] = []
        for name in [AVPlayerItem.didPlayToEndTimeNotification, .AVPlayerItemFailedToPlayToEndTime] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { _ in
                Task { @MainActor in done.fire() }
            })
        }
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(flight.length + 1))
            done.fire()
        }
        Task { @MainActor [weak self] in
            await done.wait()
            timeout.cancel()
            tokens.forEach(NotificationCenter.default.removeObserver)
            guard let self, self.ended === done else { return }
            self.renderer.stop()
            self.showing = false
            self.colourPlayer.pause()
            self.mattePlayer.pause()
        }
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
        colourPlayer.setRate(1, time: .zero, atHostTime: host)
        mattePlayer.setRate(1, time: .zero, atHostTime: host)
        renderer.start()
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { showing = true }
        #if DEBUG
        let began = ContinuousClock.now
        Task { @MainActor in
            await done.wait()
            print("KJFLIGHT \(flight.name) len=\(String(format: "%.2f", flight.length)) wall=\(ContinuousClock.now - began) \(self.renderer.report())")
        }
        #endif
    }

    /// Seconds into the flight on screen.
    var elapsed: Double {
        let t = colourPlayer.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var isFlying: Bool { showing }

    func waitForEnd() async {
        await ended?.wait()
    }

    /// Takes the bird off at once.
    func clear() {
        ended?.fire()
        ended = nil
        renderer.stop()
        showing = false
        colourPlayer.pause()
        mattePlayer.pause()
    }

    private static func load(_ name: String) -> Flight? {
        guard let colour = Bundle.main.url(forResource: "flight-\(name)-rgb-1080", withExtension: "mp4"),
              let matte = Bundle.main.url(forResource: "flight-\(name)-matte-540", withExtension: "mp4"),
              let meta = Bundle.main.url(forResource: "flight-\(name)", withExtension: "json"),
              let data = try? Data(contentsOf: meta),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let length = json["length"], let cut = json["cut"] else { return nil }
        return Flight(name: name, colour: colour, matte: matte, length: length, cut: cut, cutCover: json["cutCover"] ?? 0)
    }
}

/// How long each channel took to tune here, from asking to playing. Kept on the device, a running
/// average per channel, so a channel known to be slow gets a long flight.
enum TuneTimes {
    private static let key = "kj.tuneTimes.v4"

    static func expected(_ channel: String, fallback: Double) -> Double {
        (UserDefaults.standard.dictionary(forKey: key)?[channel] as? Double) ?? fallback
    }

    static func record(_ channel: String, seconds: Double) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        let before = all[channel] as? Double
        all[channel] = before.map { $0 * 0.5 + seconds * 0.5 } ?? seconds
        // ponytail: unbounded per-channel dictionary; a few thousand doubles at most.
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// A one-shot signal any number of waiters can await; `wait()` returns at once once fired.
@MainActor
final class Signal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// The pigeon over everything beneath it, while a flight is on screen.
struct PigeonOverlayLayer: UIViewRepresentable {
    let overlay: PigeonOverlay

    func makeUIView(context: Context) -> UIView {
        let view = overlay.renderer.view
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isHidden = !overlay.showing
    }
}

/// Draws the flight: on every display refresh, on a thread of its own (the main thread runs at
/// about 30 Hz on the Apple TV HD), it takes the colour frame due on screen and the matte frame
/// for the same time from the two players' outputs and composites them, premultiplied, into a
/// transparent Metal layer over the live picture.
final class PigeonRenderer: NSObject, @unchecked Sendable {
    let view: UIView
    private let layer = CAMetalLayer()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var cache: CVMetalTextureCache?
    private let lock = NSLock()
    private var colourOut: AVPlayerItemVideoOutput?
    private var matteOut: AVPlayerItemVideoOutput?
    private var colourItem: AVPlayerItem?, matteItem: AVPlayerItem?
    private var colourTex: CVMetalTexture?, matteTex: CVMetalTexture?
    private var link: CADisplayLink?
    private var thread: Thread?
    private var running = false
    private var lastPTS = -1.0, frames = 0, skipped = 0

    override init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        view = MetalHostView(layer: layer)
        super.init()
        guard let device else { return }
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.contentsScale = 1
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 p [[position]]; float2 uv; };
        vertex V v(uint id [[vertex_id]]) {
            float2 xy = float2((id << 1) & 2, id & 2);
            V o; o.p = float4(xy * 2.0 - 1.0, 0, 1); o.uv = float2(xy.x, 1.0 - xy.y); return o;
        }
        fragment float4 f(V in [[stage_in]], texture2d<float> colour [[texture(0)]], texture2d<float> matte [[texture(1)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float a = matte.sample(s, in.uv).r;
            return float4(colour.sample(s, in.uv).rgb * a, a);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "v")
        desc.fragmentFunction = library.makeFunction(name: "f")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// New items for the next flight; their outputs are read from the render thread.
    func attach(colour: AVPlayerItem, matte: AVPlayerItem) {
        let c = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true])
        let m = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelBufferMetalCompatibilityKey as String: true])
        colour.add(c)
        matte.add(m)
        lock.withLock {
            colourOut = c; matteOut = m; colourItem = colour; matteItem = matte
            colourTex = nil; matteTex = nil
        }
    }

    func start() {
        lock.withLock { lastPTS = -1; frames = 0; skipped = 0; running = true }
        guard thread == nil else { return }
        let thread = Thread { [weak self] in
            guard let self else { return }
            let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
            self.lock.withLock { self.link = link }
            link.add(to: .current, forMode: .default)
            while !Thread.current.isCancelled { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Stops drawing and leaves the layer clear.
    func stop() {
        lock.withLock { running = false }
        clear()
    }

    func report() -> String {
        lock.withLock { "frames=\(frames) skipped=\(skipped)" }
    }

    @objc private func tick(_ link: CADisplayLink) {
        lock.lock()
        defer { lock.unlock() }
        guard running, let colourOut, let matteOut else { return }
        let t = colourOut.itemTime(forHostTime: link.targetTimestamp)
        guard colourOut.hasNewPixelBuffer(forItemTime: t),
              let colour = colourOut.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return }
        if let matte = matteOut.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
            matteTex = texture(matte, plane: 0, format: .r8Unorm)
        }
        colourTex = texture(colour, plane: -1, format: .bgra8Unorm)
        let pts = t.seconds
        if lastPTS >= 0, pts - lastPTS > 1.5 / 24 { skipped += Int(((pts - lastPTS) * 24).rounded()) - 1 }
        frames += 1
        lastPTS = pts
        draw()
    }

    private func texture(_ buffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> CVMetalTexture? {
        guard let cache else { return nil }
        let w = plane < 0 ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetWidthOfPlane(buffer, plane)
        let h = plane < 0 ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetHeightOfPlane(buffer, plane)
        var out: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, format, w, h, max(plane, 0), &out)
        return out
    }

    private func draw() {
        guard let pipeline, let queue, let colourTex, let matteTex,
              let c = CVMetalTextureGetTexture(colourTex), let m = CVMetalTextureGetTexture(matteTex),
              let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(c, index: 0)
        enc.setFragmentTexture(m, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func clear() {
        guard let queue, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// A view whose layer is the renderer's Metal layer, kept the size of the screen.
private final class MetalHostView: UIView {
    private let metal: CAMetalLayer

    init(layer metal: CAMetalLayer) {
        self.metal = metal
        super.init(frame: .zero)
        backgroundColor = .clear
        layer.addSublayer(metal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        let scale = window?.screen.nativeScale ?? 1
        metal.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}
