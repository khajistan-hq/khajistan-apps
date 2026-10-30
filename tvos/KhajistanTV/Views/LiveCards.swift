import AVFoundation
import SwiftUI
import UIKit

// A region page's live cards (owner, 2026-10-29: "photo forward/visual like on netflix"): the
// focused channel plays muted in a hero at the top, television and camera cards carry a still
// their own device took from the stream (Services/LiveStillsStore.swift), and radio cards are the
// name over a moving sound line. Nothing here is stored.

/// The hero's picture: the focused channel's live stream, muted, on a player of its own. It starts
/// once focus has rested on a card for a moment, so walking along a shelf does not start and stop
/// a decode at every press; one channel at a time, and none while the page is covered. Once the
/// picture is up, one frame of it becomes that card's still.
@MainActor @Observable
final class LivePreview {
    let player = AVPlayer()
    private(set) var channelId: String?
    /// The picture is moving.
    private(set) var live = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// What the hero asks of a stream: the screen it fills is under 800 points wide.
    private static let maxSize = CGSize(width: 1280, height: 720)

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
    }

    /// Plays `channel` in the hero, or nothing for nil and for radio, which has no picture.
    func show(_ channel: Channel?, receiver: ReceiverStore, stills: LiveStills) {
        let wanted = channel?.mediaType == "radio" ? nil : channel
        guard wanted?.id != channelId else { return }
        stop(stills: stills)
        guard let channel = wanted else { return }
        channelId = channel.id
        let gen = generation
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            stills.heldBack = true
            defer { if gen == self.generation { stills.heldBack = false } }
            guard let url = try? await receiver.resolve(channel), !Task.isCancelled, gen == self.generation else { return }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": KJConfig.userAgent]])
            let item = AVPlayerItem(asset: asset)
            item.preferredMaximumResolution = Self.maxSize
            item.preferredForwardBufferDuration = 2
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            item.add(output)
            self.player.replaceCurrentItem(with: item)
            self.player.play()
            let deadline = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < deadline, !Task.isCancelled, gen == self.generation, item.status != .failed {
                if self.player.timeControlStatus == .playing, item.status == .readyToPlay { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled, gen == self.generation, self.player.timeControlStatus == .playing else { return }
            self.live = true
            stills.heldBack = false
            // A moment in, so the frame kept is a picture and not the stream's first black.
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, gen == self.generation else { return }
            let time = item.currentTime()
            if time.isNumeric, let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                stills.keep(buffer, for: channel.id)
            }
        }
    }

    func stop(stills: LiveStills) {
        generation += 1
        task?.cancel()
        task = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        channelId = nil
        live = false
        stills.heldBack = false
    }
}

/// The top of a region page: the crumb and the region's name, then the channel focus rests on,
/// with ● LIVE, its place and broadcaster, beside its picture, playing muted. Radio shows its name
/// over a sound line instead.
struct ChannelHero: View {
    static let pictureWidth: CGFloat = 640
    static let pictureHeight: CGFloat = 360

    let region: ReceiverIndex.Region
    let native: String?
    let channel: Channel?
    let preview: LivePreview
    let still: UIImage?
    @Environment(\.palette) private var palette

    private var playing: Bool { preview.live && preview.channelId == channel?.id }

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Receiver \u{2192} \(region.label)")
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(region.label).kjDisplay(KJType.headline, tracking: -0.055).lineLimit(1).layoutPriority(1)
                    // Native script is never letter-spaced: tracking breaks the joins.
                    if let native {
                        Text(native).kjDisplay(KJType.name * 1.4, tracking: 0).foregroundStyle(palette.faint).lineLimit(1)
                    }
                }
                Spacer(minLength: 24)
                if let channel { about(channel) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            picture
                .frame(width: Self.pictureWidth, height: Self.pictureHeight)
                .clipped()
        }
        .frame(height: Self.pictureHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("regionHero")
    }

    private func about(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kicker(channel))
                .accessibilityIdentifier("heroState")
            Text(channel.name)
                .kjName(56)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("heroName")
            if !channel.place.isEmpty { Text(channel.place).kjBody().lineLimit(1) }
            if let broadcaster = channel.broadcaster, !broadcaster.isEmpty, broadcaster != channel.name {
                Text(broadcaster).kjSmall(faint: true).lineLimit(1)
            }
        }
    }

    private func kicker(_ channel: Channel) -> String {
        let medium = ReceiverRules.mediumLabel(channel.mediaType)
        if channel.mediaType == "radio" { return "\u{25CF} Live \u{00B7} \(medium)" }
        return playing ? "\u{25CF} Live \u{00B7} \(medium)" : medium
    }

    @ViewBuilder
    private var picture: some View {
        if let channel, channel.mediaType == "radio" {
            SoundLine(seed: channel.id, lineWidth: 5, period: 5)
                .padding(.vertical, 120)
                .accessibilityIdentifier("heroSound")
        } else {
            ZStack {
                if let still {
                    Color.black
                    Image(uiImage: still).resizable().scaledToFit()
                } else {
                    palette.lift
                    if channel != nil { Kicker("Tuning\u{2026}") }
                }
                // A moving picture sits on black (DESIGN.md, Letterbox).
                PlayerLayerView(player: preview.player)
                    .background(Color.black)
                    .opacity(playing ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: playing)
            }
            .accessibilityElement()
            .accessibilityLabel(playing ? "Live picture" : (still == nil ? "Tuning" : "Still picture"))
            .accessibilityIdentifier("heroPicture")
            .accessibilityValue(playing ? "live" : (still == nil ? "waiting" : "still"))
        }
    }
}

/// A television or camera card: the still the device took, with the name over a scrim of the
/// plate's own colour at its foot. Until a still arrives the name is set large on the lift plate.
/// The plate re-skins under focus as a text card does.
struct PictureCard: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 236

    /// The channel whose place and heart head the card; nil for a card that names a region.
    let channel: Channel?
    let title: String
    let still: UIImage?
    var liked = false
    var width: CGFloat = Self.width
    var height: CGFloat = Self.height

    init(channel: Channel, still: UIImage?, liked: Bool = false) {
        self.channel = channel
        self.title = channel.name
        self.still = still
        self.liked = liked
    }

    /// A region's card on the Receiver's front: its name over a still of one of its channels.
    init(title: String, still: UIImage?, width: CGFloat, height: CGFloat) {
        self.channel = nil
        self.title = title
        self.still = still
        self.width = width
        self.height = height
    }
    @Environment(\.isFocused) private var isFocused
    @Environment(\.palette) private var palette

    var body: some View {
        let look = isFocused ? palette.onFocusPlate : palette
        let plate = isFocused ? palette.focusPlate : (still == nil ? palette.lift : palette.ground)
        ZStack(alignment: .bottomLeading) {
            if let still {
                Color.black
                Image(uiImage: still).resizable().scaledToFit()
                    .frame(width: width, height: height)
                LinearGradient(stops: [
                    .init(color: plate.opacity(0), location: 0.3),
                    .init(color: plate.opacity(0.88), location: 0.72),
                    .init(color: plate.opacity(0.95), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                plate
            }
            VStack(alignment: .leading, spacing: 6) {
                if let channel { CardKicker(channel: channel, liked: liked) }
                Text(title)
                    .kjName(still == nil ? 40 : KJType.name)
                    .lineLimit(2)
            }
            .padding(24)
        }
        .frame(width: width, height: height)
        .environment(\.palette, look)
        .foregroundStyle(look.ink)
        .kjCardArt()
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.35), value: still != nil)
    }
}

/// A radio card: the station's name set large over its sound line, on the lift plate.
struct RadioCard: View {
    let channel: Channel
    var liked = false

    var body: some View {
        CardPlate(width: PictureCard.width, height: PictureCard.height) {
            VStack(alignment: .leading, spacing: 8) {
                CardKicker(channel: channel, liked: liked)
                Text(channel.name)
                    .kjName(36)
                    .lineLimit(2)
                Spacer(minLength: 0)
                SoundLine(seed: channel.id)
                    .frame(height: 40)
            }
        }
    }
}

/// The heart where the channel is liked, then the place.
private struct CardKicker: View {
    let channel: Channel
    let liked: Bool

    var body: some View {
        HStack(spacing: 12) {
            if liked {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .semibold))
            }
            if !channel.place.isEmpty {
                Kicker(channel.place).lineLimit(1)
            }
        }
    }
}

extension Channel {
    /// What a card says to VoiceOver: the name, the place, "live picture" while a still is shown.
    func cardLabel(still: Bool, liked: Bool) -> String {
        [name, place, still ? "live picture" : "", liked ? "Liked" : ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
