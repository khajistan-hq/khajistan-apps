import SwiftUI

/// A receiver channel, full screen. Up and down tune the neighbouring channel in the list the
/// viewer came from; play/pause pauses, and pressing it again tunes the channel afresh, because
/// a live signal paused for a minute is not the live signal any more.
struct ReceiverPlayerView: View {
    let list: [Channel]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    @State private var current: Channel
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var tuneTask: Task<Void, Never>?

    init(channel: Channel, list: [Channel]) {
        self.list = list
        _current = State(initialValue: channel)
    }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            PlayerLayerView(player: controller.player)
                .ignoresSafeArea()
            if current.mediaType == "radio" {
                Text(current.name)
                    .font(KJFont.title())
                    .multilineTextAlignment(.center)
                    .padding(120)
            }
            VStack {
                Spacer()
                infoPlate(palette)
            }
            .opacity(overlayVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: overlayVisible)
            // The focus target. It draws nothing; its job is to hold focus so the remote's
            // presses reach the handlers below, and a click on it wakes the overlay.
            Button {
                wake()
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
        }
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
            tuneTask?.cancel()
            controller.stop()
            dismiss()
        }
        .onChange(of: controller.state) { wake() }
        .task { tune(current) }
        .onDisappear {
            tuneTask?.cancel()
            hideTask?.cancel()
            controller.stop()
        }
    }

    private func infoPlate(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.name)
                .font(KJFont.bodyBold())
            if !current.place.isEmpty {
                Text(current.place)
                    .font(KJFont.caption())
            }
            Text(stateText)
                .font(KJFont.caption())
                .accessibilityIdentifier("playerState")
            if let attribution = current.attributionText, !attribution.isEmpty {
                Text(attribution)
                    .font(KJFont.caption())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .background(palette.ground)
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return ""
        case .tuning: return "Tuning\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

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

    /// The neighbour of the current channel in the list, wrapping at either end.
    private func step(by delta: Int) {
        guard list.count > 1, let position = list.firstIndex(where: { $0.id == current.id }) else { return }
        tune(list[(position + delta + list.count) % list.count])
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
