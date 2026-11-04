import AVFoundation
import CoreImage
import Network
import Observation
import UIKit

/// The Receiver's picture cards: a still frame of each television channel, taken on the viewer's
/// own device from the channel's live stream, the same carrier the player tunes (the receiver's
/// `resolve`, the player's User-Agent, nothing else sent). A still is held in memory only, small
/// (at most 480x270), under a bound (`StillCache`), and is dropped on a memory warning. Nothing is
/// written to disk and nothing leaves the device, so "keeps no copy" stays true.
///
/// A page opens a visit, says which channels it wants (nearest the viewer first), and closes the
/// visit when it goes. One still is taken at a time, spaced and capped by `StillPlan`. On an
/// expensive or constrained connection (cellular, Low Data Mode) none is taken.
@MainActor @Observable
final class LiveStills {
    nonisolated static let maxSize = CGSize(width: 480, height: 270)
    /// About 36 stills at 480x270, 19 MB of pixels: a still for every region and camera card.
    private static let costLimit = 480 * 270 * 4 * 36
    /// A still older than this is taken again when its card is next wanted.
    private static let maxAge: TimeInterval = 600
    /// How long a still may take to arrive before the channel is given up for this visit.
    private static let grabLimit: Duration = .seconds(10)

    private(set) var cache = StillCache<UIImage>(costLimit: costLimit, maxAge: maxAge)

    @ObservationIgnored private let receiver: ReceiverStore
    @ObservationIgnored private var plan = StillPlan()
    @ObservationIgnored private var wanted: [Channel] = []
    /// A second list, wanted after the first: the Receiver's camera cards, beside its regions.
    @ObservationIgnored private var wantedToo: [Channel] = []
    @ObservationIgnored private var onScreen: [Channel] = []
    @ObservationIgnored private var visit = 0
    @ObservationIgnored private var driver: Task<Void, Never>?
    /// Set by a page whose own live picture is starting up (the Apple TV hero), so a still's
    /// decode never starts alongside it.
    @ObservationIgnored var heldBack = false
    @ObservationIgnored private var costly = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var memoryObserver: NSObjectProtocol?

    init(receiver: ReceiverStore) {
        self.receiver = receiver
        monitor.pathUpdateHandler = { [weak self] path in
            let costly = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.costly = costly }
        }
        monitor.start(queue: DispatchQueue(label: "com.khajistan.stills.path"))
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cache.removeAll() }
        }
    }

    /// The still for a channel, when one is on hand.
    func image(for id: String) -> UIImage? {
        cache.value(for: id, now: Date().timeIntervalSince1970)
    }

    /// Starts a visit: a fresh share of stills. What is already wanted (rows that came on screen
    /// first) is kept.
    func beginVisit() {
        driver?.cancel()
        driver = nil
        visit += 1
        plan = StillPlan()
        drive()
    }

    /// Ends the visit: the still under way is abandoned and no more are taken. A later `want`
    /// carries on with the visit's share; only `beginVisit` renews it.
    func endVisit() {
        driver?.cancel()
        driver = nil
        wanted = []
        wantedToo = []
        onScreen = []
        visit += 1
        plan.finished()
    }

    /// The channels the page wants stills of, nearest the viewer first. Radio has no picture and is
    /// skipped here, so a page may pass its whole list.
    func want(_ channels: [Channel]) {
        wanted = channels.filter { $0.mediaType != "radio" }
        drive()
    }

    /// Wanted after `want`'s list, and kept when that list changes.
    func wantToo(_ channels: [Channel]) {
        wantedToo = channels.filter { $0.mediaType != "radio" }
        drive()
    }

    /// For a list: a row came on screen, or went. The rows on screen are what is wanted, in the
    /// order they came.
    func appeared(_ channel: Channel) {
        guard !onScreen.contains(where: { $0.id == channel.id }) else { return }
        onScreen.append(channel)
        want(onScreen)
    }

    func disappeared(_ id: String) {
        onScreen.removeAll { $0.id == id }
        wanted.removeAll { $0.id == id }
    }

    /// A frame the page already has on screen (the hero's), kept as the channel's still.
    func keep(_ buffer: CVPixelBuffer, for id: String) {
        guard let image = Self.image(from: buffer) else { return }
        store(image, for: id)
    }

    private func store(_ image: UIImage, for id: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        cache.insert(image, for: id, cost: pixels * 4, now: Date().timeIntervalSince1970)
    }

    /// One loop per visit: takes the next wanted still once the spacing allows, and stops when the
    /// visit ends, has had its share, or has nothing left it may take. `want` starts it again.
    private func drive() {
        guard driver == nil, !plan.exhausted else { return }
        let current = visit
        driver = Task { [weak self] in
            while let self, !Task.isCancelled, current == self.visit, !self.plan.exhausted {
                // A grab plays a muted player, and playing can take the audio session from another
                // app's music: no still while something else is sounding.
                if self.costly || self.heldBack || AVAudioSession.sharedInstance().isOtherAudioPlaying {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                let now = Date().timeIntervalSince1970
                let all = self.wanted + self.wantedToo
                guard let id = self.plan.next(wanted: all.map(\.id), has: { self.image(for: $0) != nil }, now: now) else {
                    let wait = self.plan.wait(now: now)
                    if wait == 0 { break }
                    try? await Task.sleep(for: .seconds(wait))
                    continue
                }
                if let channel = all.first(where: { $0.id == id }), let image = await self.grab(channel),
                   !Task.isCancelled, current == self.visit {
                    self.store(image, for: id)
                }
                self.plan.finished()
            }
            if let self, current == self.visit { self.driver = nil }
        }
    }

    /// Plays the channel muted on a player of its own, at the stream's lowest picture, until one
    /// frame arrives, then lets go of it.
    private func grab(_ channel: Channel) async -> UIImage? {
        guard let url = try? await receiver.resolve(channel), !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": KJConfig.userAgent]])
        let item = AVPlayerItem(asset: asset)
        item.preferredMaximumResolution = Self.maxSize
        item.preferredPeakBitRate = 800_000
        item.preferredForwardBufferDuration = 1
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        player.play()
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        let deadline = ContinuousClock.now + Self.grabLimit
        while ContinuousClock.now < deadline, !Task.isCancelled, item.status != .failed {
            try? await Task.sleep(for: .milliseconds(200))
            let time = item.currentTime()
            guard time.isNumeric, output.hasNewPixelBuffer(forItemTime: time),
                  let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { continue }
            return Self.image(from: buffer)
        }
        return nil
    }

    nonisolated private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Below this mean brightness (0–1) a frame is a black or fade-out frame, not a picture.
    nonisolated static let darkFrame: CGFloat = 0.06

    /// A frame scaled to fit `maxSize`, keeping its shape, or nil for a frame that is nearly black:
    /// a card keeps its name plate rather than show a black box (2026-10-29, the Receiver's front).
    nonisolated static func image(from buffer: CVPixelBuffer) -> UIImage? {
        let frame = CIImage(cvPixelBuffer: buffer)
        let extent = frame.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        if brightness(frame) < darkFrame { return nil }
        let scale = min(1, maxSize.width / extent.width, maxSize.height / extent.height)
        let scaled = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent.integral) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The frame's mean brightness, 0–1, from CIAreaAverage over the whole frame.
    nonisolated static func brightness(_ frame: CIImage) -> CGFloat {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: frame, kCIInputExtentKey: CIVector(cgRect: frame.extent),
        ]), let average = filter.outputImage else { return 1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }
}
