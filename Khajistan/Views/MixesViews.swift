import AVFoundation
import SwiftUI

/// The Khajistan Radio mixes: the public register (data/radio/mixtapes.json) in its own order. A
/// mix is a finished recording Khajistan made, not a live signal (ported from the Apple TV app).
struct MixesSection: View {
    @Environment(AppModel.self) private var model
    @State private var playing: Mix?

    private var store: MixesStore { model.mixes }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Khajistan Radio").kjDisplay(KJType.headline, tracking: -0.04)
                if !store.mixes.isEmpty {
                    Text("\(store.mixes.count) \(store.mixes.count == 1 ? "mix" : "mixes")").kjSmall(faint: true)
                }
            }
            if let message = store.loadError, store.mixes.isEmpty {
                Text(message).kjBody()
                Button(kicker: "Try again") { Task { await store.load() } }.buttonStyle(HouseButtonStyle(solid: true))
            } else if store.mixes.isEmpty {
                TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.mixes) { mix in
                        HouseRule()
                        Button { playing = mix } label: { MixRow(mix: mix) }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)))
                            .accessibilityIdentifier("mix-\(mix.id)")
                    }
                }
            }
        }
        .task { await store.load() }
        .fullScreenCover(item: $playing) { mix in
            MixPlayerView(mix: mix, list: store.mixes)
        }
    }
}

private struct MixRow: View {
    let mix: Mix

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mix.name).kjName().lineLimit(2)
            Kicker(mix.program_block ?? "Mixtape").lineLimit(1)
            let detail = [mix.place, mix.language].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !detail.isEmpty { Text(detail).kjSmall(faint: true).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A mix, full screen. A recording has a position, so it can be moved thirty seconds either way;
/// a swipe up or down moves to the neighbouring mix, and a mix that ends rolls on to the next.
struct MixPlayerView: View {
    let list: [Mix]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    @State private var current: Mix
    @State private var position: Double = 0
    @State private var duration: Double?

    init(mix: Mix, list: [Mix]) {
        self.list = list
        _current = State(initialValue: mix)
    }

    var body: some View {
        let palette = Palette(model.skin)
        VStack(spacing: 0) {
            PlayerTopBar(leading: ["Khajistan Receiver", current.program_block ?? "Mixtape"], trailing: ["Khajistan Radio mix"]) {
                controller.stop()
                dismiss()
            }
            Spacer(minLength: 0)
            Text(current.name)
                .kjDisplay()
                .multilineTextAlignment(.center)
                .padding(.horizontal, KJLayout.inset)
                .id(current.id)
                .transition(.opacity)
            Spacer(minLength: 0)
            panel
        }
        .background(palette.ground.ignoresSafeArea())
        .channelGestures(step: step, tap: {})
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .task { play(current) }
        .task { await trackPosition() }
        .onDisappear { controller.stop() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(stateText).accessibilityIdentifier("playerState")
            if let subtitle = current.subtitle, !subtitle.isEmpty { Text(subtitle).kjBody() }
            let facts = [current.place, current.language, current.decade].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !facts.isEmpty { Text(facts).kjSmall() }
            Text(timeText).kjSmall().monospacedDigit().accessibilityIdentifier("mixTime")
            Text(current.attribution).kjSmall(faint: true).lineLimit(2)
            TransportRow(isPlaying: controller.state == .playing, toggle: { controller.toggle() },
                         back: { seek(by: -30) }, forward: { seek(by: 30) })
            Text("Swipe up or down for the next mix.").kjSmall(faint: true)
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return " "
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    private var timeText: String {
        guard let duration else { return Mixes.clock(position) }
        return "\(Mixes.clock(position)) / \(Mixes.clock(duration))"
    }

    private func play(_ mix: Mix) {
        controller.stop()
        withAnimation(.kj) { current = mix }
        position = 0
        duration = nil
        guard let url = Mixes.playURL(mix) else {
            controller.state = .failed("This mix could not be played.")
            return
        }
        controller.onEnded = { advance() }
        controller.attach(url: url, seekTo: nil, title: mix.name, subtitle: mix.place ?? "Khajistan Radio", isLive: false)
    }

    private func advance() {
        guard let index = list.firstIndex(where: { $0.id == current.id }), index + 1 < list.count else {
            controller.pause()
            return
        }
        play(list[index + 1])
    }

    private func step(_ delta: Int) {
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

    private func trackPosition() async {
        while !Task.isCancelled {
            let now = controller.player.currentTime().seconds
            if now.isFinite { position = now }
            let length = controller.player.currentItem?.duration.seconds
            duration = (length?.isFinite == true && (length ?? 0) > 0) ? length : nil
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
