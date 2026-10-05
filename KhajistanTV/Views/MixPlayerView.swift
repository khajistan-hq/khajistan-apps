import AVFoundation
import SwiftUI

/// A Khajistan Radio mix, full screen. A mix is a recording, so it has a position and can be
/// scrubbed: left and right move thirty seconds, up and down move to the neighbouring mix, play/
/// pause pauses. A mix that ends rolls on to the next one, and stops when there is none.
struct MixPlayerView: View {
    let list: [Mix]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    @State private var current: Mix
    @State private var overlayVisible = true
    @State private var position: Double = 0
    @State private var duration: Double?
    @State private var hideTask: Task<Void, Never>?

    private static let jump: Double = 30

    init(mix: Mix, list: [Mix]) {
        self.list = list
        _current = State(initialValue: mix)
    }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            if controller.state == .playing || controller.state == .paused {
                // Sound has no picture: the name stands in the centre, as it does for radio.
                Text(current.name)
                    .kjDisplay()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KJLayout.inset)
            }
            if controller.state == .tuning {
                TuningLoader(nil)
            }
            overlay(palette)
            Button {
                wake()
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            switch direction {
            case .left: seek(by: -Self.jump)
            case .right: seek(by: Self.jump)
            case .up: step(by: -1)
            case .down: step(by: 1)
            @unknown default: break
            }
        }
        .onPlayPauseCommand {
            wake()
            if controller.state == .playing || controller.state == .paused { controller.toggle() }
        }
        .onExitCommand {
            stopEverything()
            dismiss()
        }
        .onChange(of: controller.state) { wake() }
        .task { play(current) }
        .task { await trackPosition() }
        .onDisappear { stopEverything() }
    }

    // MARK: - Overlay

    private func overlay(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            StatusBand(leading: ["Khajistan Receiver", current.program_block ?? "Mixtape"], trailing: ["Khajistan Radio mix"])
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
            if controller.state != .playing && controller.state != .paused {
                Text(current.name)
                    .kjDisplay(KJType.headline, tracking: -0.055)
            }
            if let subtitle = current.subtitle, !subtitle.isEmpty {
                Text(subtitle).kjBody()
            }
            let facts = [current.place, current.language, current.decade].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !facts.isEmpty {
                Text(facts).kjBody()
            }
            if controller.state == .playing || controller.state == .paused {
                Text(timeText)
                    .kjSmall()
                    .monospacedDigit()
                    .accessibilityIdentifier("mixTime")
            }
            Text(current.attribution)
                .kjSmall(faint: true)
                .lineLimit(2)
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return ""
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    /// "12:04 / 1:24:13", or the position alone while the length is not known.
    private var timeText: String {
        guard let duration else { return Mixes.clock(position) }
        return "\(Mixes.clock(position)) / \(Mixes.clock(duration))"
    }

    // MARK: - Playing

    private func play(_ mix: Mix) {
        controller.stop()
        current = mix
        position = 0
        duration = nil
        wake()
        guard let url = Mixes.playURL(mix) else {
            controller.state = .failed("This mix could not be played.")
            return
        }
        controller.onEnded = { advance() }
        controller.attach(url: url, seekTo: nil, title: mix.name, subtitle: mix.place ?? "Khajistan Radio", isLive: false)
    }

    /// The mix ended: on to the next, and stop at the last.
    private func advance() {
        guard let index = list.firstIndex(where: { $0.id == current.id }), index + 1 < list.count else {
            controller.pause()
            return
        }
        play(list[index + 1])
    }

    private func step(by delta: Int) {
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        play(list[(index + delta + list.count) % list.count])
    }

    private func seek(by seconds: Double) {
        guard controller.state == .playing || controller.state == .paused else { return }
        var target = position + seconds
        if let duration { target = min(target, max(duration - 1, 0)) }
        target = max(target, 0)
        controller.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
    }

    /// Reads the player twice a second while the screen is up.
    private func trackPosition() async {
        while !Task.isCancelled {
            let now = controller.player.currentTime().seconds
            if now.isFinite { position = now }
            let length = controller.player.currentItem?.duration.seconds
            duration = (length?.isFinite == true && (length ?? 0) > 0) ? length : nil
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func stopEverything() {
        hideTask?.cancel()
        controller.stop()
    }

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
