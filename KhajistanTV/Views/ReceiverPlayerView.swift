import SwiftUI

/// A receiver channel, full screen. Up and down tune the neighbouring channel in the list the
/// viewer came from, behind the pigeon (StationClips); play/pause pauses, and pressing it again tunes the
/// channel afresh, because a live signal paused for a minute is not the live signal any more.
///
/// Live captions: where the channel offers them the strip ends in the Captions control. Right moves
/// to it and left comes back; Select on it turns captions on or off. Play/Pause, Select on the
/// picture and up/down are already the player's, and a control the viewer can see in the strip says
/// what it does, which a hidden gesture would not.
struct ReceiverPlayerView: View {
    let list: [Channel]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller = PlayerController()
    @State private var current: Channel
    /// The channel the last up or down press asked for, until the wipe has tuned it. A second
    /// press steps on from here, not from the channel still on screen.
    @State private var destination: Channel?
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var tuneTask: Task<Void, Never>?
    @State private var changeTask: Task<Void, Never>?
    /// The Captions control takes focus only when the viewer moves right to it, so the focus engine
    /// never lands on it from an up or down press, which change channel.
    @State private var captionArmed = false
    @State private var stripHeight: CGFloat = 0
    @FocusState private var focus: PlayerFocus?

    init(channel: Channel, list: [Channel]) {
        self.list = list
        _current = State(initialValue: channel)
    }

    var body: some View {
        // Taken from the skin and handed down, so the clip layer and the kickers read it even in
        // the full-screen cover, which is a hosting controller of its own.
        let palette = Palette(model.skin)
        ZStack {
            // A picture that does not fill the screen sits on black, whatever the skin (owner,
            // 2026-10-05). Radio, which has no picture, keeps the skin's ground.
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: controller.player)
                .ignoresSafeArea()
            // Radio: the dancer, when the carrier can be read and the stream carries a beat, in
            // front of the channel's name. The band says live radio; the centre carries the name.
            DancerLayer(controller: controller) {
                if current.mediaType == "radio" && controller.state == .playing {
                    Text(current.name)
                        .kjDisplay()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, KJLayout.inset)
                }
            }
            // The focus target. It draws nothing; its job is to hold focus so the remote's
            // presses reach the handlers below. A click works the Captions control when the viewer
            // has moved to it, and otherwise wakes the overlay. Focus never leaves it: moving
            // focus onto a control as it appears did not take on a real Apple TV, so Select fell
            // through to here and captions could not be turned on (owner, 2026-10-06).
            Button {
                if captionArmed {
                    model.captions.toggle()
                } else {
                    wake()
                }
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
            .focused($focus, equals: .surface)
            overlay(palette)
            CaptionLayer(text: model.captions.text, skin: model.skin, lift: stripShown ? stripHeight : 0)
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            switch direction {
            case .up: captionArmed = false; step(by: -1)
            case .down: captionArmed = false; step(by: 1)
            case .right: moveToCaptions()
            case .left: leaveCaptions()
            default: break
            }
        }
        .onPlayPauseCommand {
            wake()
            if controller.state == .playing {
                controller.pause()
            } else {
                tune(current)
            }
        }
        .onExitCommand {
            stopEverything()
            dismiss()
        }
        .onChange(of: controller.state) { wake() }
        .task {
            await open()
            #if DEBUG
            // `-kjautochange 6` steps to the next channel that many times, ten seconds apart, so
            // the flights can be measured on a device with no one at the remote.
            let n = UserDefaults.standard.integer(forKey: "kjautochange")
            for _ in 0..<n {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { return }
                step(by: 1)
            }
            #endif
        }
        .onDisappear { stopEverything() }
    }

    // MARK: - Overlay

    /// The status band across the top and the panel on the ground below. Both go together.
    private func overlay(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlayerStrip(
                // Radio carries its name in display type on the ground; the strip leaves it out.
                name: current.mediaType == "radio" && controller.state == .playing ? nil : current.name,
                detail: stripDetail,
                attribution: current.attributionText,
                trailing: stripTrailing,
                accessory: model.captions.offered ? AnyView(captionsControl) : nil
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
            .offset(y: stripShown ? 0 : 40)
            .opacity(stripShown ? 1 : 0)
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: stripShown)
        .overlay(alignment: .bottomLeading) {
            // The state, for tests and VoiceOver; the strip shows only a reason, never "Playing".
            Text(stateText)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("playerState")
        }
    }

    /// While a signal tunes the ground already says so; the strip waits for the picture.
    private var stripShown: Bool {
        guard overlayVisible else { return false }
        switch controller.state {
        case .playing, .paused, .failed: return true
        case .idle, .tuning: return false
        }
    }

    /// What follows the name: a failure's reason, Paused, the captions' note, or the place.
    private var stripDetail: String? {
        switch controller.state {
        case .failed(let message): return message
        case .paused: return "Paused"
        default:
            if !model.captions.note.isEmpty { return model.captions.note }
            return current.place.isEmpty ? nil : current.place
        }
    }

    /// The site's Captions button: its label says what is on and what is left. Right lights it,
    /// Select works it, left lets it go; no up or down press can land on it.
    private var captionsControl: some View {
        StripChipStyle.face(Text(model.captions.label), isOn: model.captions.isOn, selected: captionArmed)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("captionsControl")
            // Lit by the remote rather than focused: tests and VoiceOver read it as selected.
            .accessibilityAddTraits(captionArmed ? .isSelected : [])
            .accessibilityValue(model.captions.isOn ? "On" : "Off")
    }

    private func moveToCaptions() {
        guard model.captions.offered, stripShown else { return }
        hideTask?.cancel()
        captionArmed = true
    }

    private func leaveCaptions() {
        guard captionArmed else { return }
        captionArmed = false
        wake()
    }

    /// The medium only: the place is already beside the name, and one thing is said once.
    private var stripTrailing: [String] {
        ["\u{25CF} \(liveLabel)"]
    }

    private var liveLabel: String {
        switch current.mediaType.lowercased() {
        case "tv": return "Live television"
        case "radio": return "Live radio"
        case "camera": return "Camera"
        default: return "Live"
        }
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return ""
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"   // the band already names the medium
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    /// The signal on screen has a picture: television or a camera, playing or paused.
    private var showsPicture: Bool {
        current.mediaType != "radio" && (controller.state == .playing || controller.state == .paused)
    }

    // MARK: - Tuning

    /// Stops what is playing, resolves the channel's carrier now and plays it. A tuning the
    /// viewer has already moved on from is cancelled and says nothing.
    private func tune(_ target: Channel) {
        tuneTask?.cancel()
        controller.stop()
        controller.state = .tuning
        current = target
        wake()
        tuneTask = Task {
            do {
                let url = try await model.receiver.resolve(target)
                try Task.checkCancellation()
                controller.attach(
                    url: url,
                    seekTo: nil,
                    title: target.name,
                    subtitle: target.place.isEmpty ? nil : target.place,
                    // Radio only: television and cameras carry a picture (owner, 2026-07-21).
                    listen: dancerMayListen(target),
                    // A live mount the app plays itself, so its samples can be read; HLS stays
                    // on AVPlayer and has no dancer.
                    live: target.activeStream?.format != "hls" && !url.path.lowercased().hasSuffix(".m3u8")
                )
                model.captions.attach(target, player: controller)
            } catch {
                if Task.isCancelled { return }
                controller.state = .failed(error.localizedDescription)
            }
        }
    }

    /// The dancer: radio, not reverent, and not for a viewer who has asked for less motion (who
    /// then gets AVPlayer, as before).
    private func dancerMayListen(_ channel: Channel) -> Bool {
        channel.mediaType == "radio" && !channel.isReverent && !reduceMotion
    }

    /// The neighbour of the channel last asked for, wrapping at either end, reached behind the
    /// pigeon. A press while a flight is on screen ends that flight and takes over from it.
    private func step(by delta: Int) {
        let from = destination ?? current
        guard list.count > 1, let position = list.firstIndex(where: { $0.id == from.id }) else { return }
        let target = list[(position + delta + list.count) % list.count]
        destination = target
        model.clips.skip()
        changeTask?.cancel()
        changeTask = Task { await change(to: target) }
    }

    /// The screen opens on the ground with the channel's name, which fades off the picture as it
    /// arrives.
    private func open() async {
        model.clips.cover(caption: current.name, animated: false)
        tune(current)
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
    }

    /// The wing crosses and holds while the old sound fades, the new channel is tuned behind it,
    /// the wing leaves, and the picture cuts in as its sound fades up. The video never fades.
    private func change(to target: Channel) async {
        async let quiet: Void = controller.fadeOut()
        await model.clips.play(.wingIn, holdLastFrame: true)
        await quiet
        // A newer press, or leaving, cancelled this one while the wing was crossing.
        guard !Task.isCancelled else { return }
        tune(target)
        destination = nil
        await model.clips.play(.wingOut)
    }

    /// Everything this screen started: the tuning, the wipe, the timer, the signal and the clip.
    private func stopEverything() {
        tuneTask?.cancel()
        changeTask?.cancel()
        hideTask?.cancel()
        model.captions.detach()
        controller.stop()
        model.clips.clear()
    }

    /// Shows the overlay. Once the signal is playing it hides again after 2.6 seconds without
    /// a press; while tuning, paused or failed it stays, because that is what there is to read.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        guard controller.state == .playing else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            // The strip stays while the viewer is on its Captions control.
            if !Task.isCancelled, !captionArmed {
                overlayVisible = false
                captionArmed = false
            }
        }
    }
}

/// What holds focus on a player: the picture, or the caption control in its strip.
enum PlayerFocus: Hashable {
    case surface, captions
}
