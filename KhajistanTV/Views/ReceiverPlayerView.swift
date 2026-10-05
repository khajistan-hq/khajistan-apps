import SwiftUI

/// A receiver channel, full screen. Up and down tune the neighbouring channel in the list the
/// viewer came from, through the wing wipe; play/pause pauses, and pressing it again tunes the
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
            palette.ground.ignoresSafeArea()
            PlayerLayerView(player: controller.player)
                .ignoresSafeArea()
            if current.mediaType == "radio" && controller.state == .playing {
                // The band says live radio; the centre carries the name alone.
                Text(current.name)
                    .kjDisplay()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KJLayout.inset)
            }
            if controller.state == .tuning {
                TuningLoader(nil)
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
        .task { tune(current) }
        .onDisappear { stopEverything() }
    }

    // MARK: - Overlay

    /// The status band across the top and the panel on the ground below. Both go together.
    private func overlay(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            // The band's text stays inside the safe area; its colour runs up to the screen edge.
            StatusBand(leading: bandLeading, trailing: ["\u{25CF} \(liveLabel)"])
            Spacer(minLength: 0)
            panel
                .background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
        }
        .opacity(overlayVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: overlayVisible)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(stateText)
                .accessibilityIdentifier("playerState")
            if !(current.mediaType == "radio" && controller.state == .playing) {
                Text(current.name)
                    .kjDisplay(KJType.headline, tracking: -0.055)
            }
            if !current.place.isEmpty {
                Text(current.place)
                    .kjBody()
            }
            if let attribution = current.attributionText, !attribution.isEmpty {
                Text(attribution)
                    .kjSmall(faint: true)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bandLeading: [String] {
        var items = ["Khajistan Receiver"]
        if let country = current.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            items.append("Broadcasting from \(country)")
        }
        return items
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

    /// The neighbour of the channel last asked for, wrapping at either end, reached through the
    /// wing wipe. A press while a clip is on screen ends that clip and takes over from it.
    private func step(by delta: Int) {
        let from = destination ?? current
        guard list.count > 1, let position = list.firstIndex(where: { $0.id == from.id }) else { return }
        let target = list[(position + delta + list.count) % list.count]
        destination = target
        model.clips.skip()
        changeTask?.cancel()
        changeTask = Task { await change(to: target) }
    }

    /// The wing crosses and holds, the new channel is tuned behind it, the wing leaves.
    private func change(to target: Channel) async {
        await model.clips.play(.wingIn, holdLastFrame: true)
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
