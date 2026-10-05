import SwiftUI

/// A receiver channel, full screen. Up and down tune the neighbouring channel in the list the
/// viewer came from, behind the pigeon (StationClips); play/pause pauses, and pressing it again tunes the
/// channel afresh, because a live signal paused for a minute is not the live signal any more.
struct ReceiverPlayerView: View {
    let list: [Channel]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    @State private var current: Channel
    /// The channel the last up or down press asked for, until the wipe has tuned it. A second
    /// press steps on from here, not from the channel still on screen.
    @State private var destination: Channel?
    @State private var overlayVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hideTask: Task<Void, Never>?
    @State private var tuneTask: Task<Void, Never>?
    @State private var changeTask: Task<Void, Never>?

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
            if current.mediaType == "radio" && controller.state == .playing {
                // The band says live radio; the centre carries the name alone.
                Text(current.name)
                    .kjDisplay()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KJLayout.inset)
            }
            overlay(palette)
            // The focus target. It draws nothing; its job is to hold focus so the remote's
            // presses reach the handlers below, and a click on it wakes the overlay.
            Button {
                wake()
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            switch direction {
            case .up: step(by: -1)
            case .down: step(by: 1)
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
        .task { await open() }
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
                trailing: stripTrailing
            )
            .accessibilityElement(children: .combine)
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

    /// What follows the name: a failure's reason, Paused, or the place.
    private var stripDetail: String? {
        switch controller.state {
        case .failed(let message): return message
        case .paused: return "Paused"
        default: return current.place.isEmpty ? nil : current.place
        }
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
                    subtitle: target.place.isEmpty ? nil : target.place
                )
            } catch {
                if Task.isCancelled { return }
                controller.state = .failed(error.localizedDescription)
            }
        }
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
        model.clips.uncover(fade: true)
    }

    /// The old sound fades as the pigeon flies in over the skin's ground; the new channel starts
    /// tuning the moment the wing covers the screen, while the bird flies on out; the ground holds
    /// with the channel's name until the picture plays, and fades off it as its sound fades in.
    private func change(to target: Channel) async {
        async let quiet: Void = controller.fadeOut()
        await model.clips.flyThrough(caption: target.name) {
            // A newer press has moved on: that press tunes its own channel.
            guard destination?.id == target.id else { return }
            tune(target)
            destination = nil
        }
        await quiet
        guard !Task.isCancelled else { return }
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
    }

    /// Everything this screen started: the tuning, the wipe, the timer, the signal and the clip.
    private func stopEverything() {
        tuneTask?.cancel()
        changeTask?.cancel()
        hideTask?.cancel()
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
            if !Task.isCancelled { overlayVisible = false }
        }
    }
}
