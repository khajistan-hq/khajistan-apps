import SwiftUI

/// A receiver channel, full screen (ported from the Apple TV app). A swipe up tunes the next
/// channel in the list the reader came from and a swipe down the one before, behind the pigeon:
/// the old sound fades as the skin's ground comes up, the wing covers the screen, the new channel
/// tunes behind it, and the ground lifts as the new sound fades in. A picture that does not fill
/// the screen sits on black (owner, 2026-10-05); radio keeps the skin's ground.
struct ReceiverPlayerView: View {
    let list: [Channel]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    @State private var overlay = OverlayClock()
    @State private var current: Channel
    /// The channel the last swipe asked for, until the wipe has tuned it.
    @State private var destination: Channel?
    @State private var tuneTask: Task<Void, Never>?
    @State private var changeTask: Task<Void, Never>?
    /// True while the screen opens or a channel changes: those flows cover and uncover the
    /// picture themselves, and the player passes through tuning and playing more than once.
    @State private var changing = false
    /// When the last change or opening settled. A stream often stalls once just after it starts;
    /// covering that would flash the ground up and down over a picture that is about to play.
    @State private var settledAt = Date.distantPast

    init(channel: Channel, list: [Channel]) {
        self.list = list
        _current = State(initialValue: channel)
    }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: controller.player).ignoresSafeArea()
            if current.mediaType == "radio" && controller.state == .playing {
                Text(current.name)
                    .kjDisplay()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KJLayout.inset)
            }
            Color.clear.channelGestures(step: step, tap: { overlay.toggle(settled: controller.state == .playing) })
            chrome(palette)
                .opacity(overlay.visible ? 1 : 0)
                .allowsHitTesting(overlay.visible)
        }
        // An overlay, not the last child of the ZStack: as a child the layer composited under the
        // chrome while it showed, and the bird read green-washed through the panel's ground.
        .overlay { StationClipLayer(clips: model.clips) }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .statusBarHidden(!overlay.visible)
        .onChange(of: controller.state) { old, new in
            overlay.wake(settled: new == .playing)
            // The site's rule: the pigeon covers every wait, a buffer mid-broadcast included. Only
            // outside a change, and only for a stall that lasts: a blip must not flash the bird.
            guard !changing else { return }
            if old == .playing && new == .tuning, Date().timeIntervalSince(settledAt) > 3 {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !changing, controller.state == .tuning { model.clips.cover(caption: current.name) }
                }
            } else if new == .playing, model.clips.coverage > 0 {
                model.clips.uncover()
            }
        }
        .task { await open() }
        .onDisappear { stopEverything() }
        .accessibilityAction(named: "Next channel") { step(1) }
        .accessibilityAction(named: "Previous channel") { step(-1) }
    }

    // MARK: - Overlay

    private func chrome(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            PlayerTopBar(leading: bandLeading, trailing: ["\u{25CF} \(liveLabel)"]) {
                stopEverything()
                dismiss()
            }
            Spacer(minLength: 0)
            panel.background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(stateText).accessibilityIdentifier("playerState").accessibilityValue(current.id)
            if !(current.mediaType == "radio" && controller.state == .playing) {
                Text(current.name).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
            }
            if !current.place.isEmpty { Text(current.place).kjBody() }
            if let attribution = current.attributionText, !attribution.isEmpty {
                Text(attribution).kjSmall(faint: true).lineLimit(3)
            }
            TransportRow(isPlaying: controller.state == .playing || controller.state == .tuning, toggle: playPause)
            if list.count > 1 {
                Text("Swipe up or down for the next channel.").kjSmall(faint: true)
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 14)
        .padding(.bottom, 8)
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
        case .idle: return " "
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    private var showsPicture: Bool {
        current.mediaType != "radio" && (controller.state == .playing || controller.state == .paused)
    }

    /// A live signal paused is not the live signal any more: play tunes it afresh.
    private func playPause() {
        if controller.state == .playing || controller.state == .tuning {
            controller.pause()
        } else {
            tune(current)
        }
    }

    // MARK: - Tuning

    private func tune(_ target: Channel) {
        tuneTask?.cancel()
        controller.stop()
        controller.state = .tuning
        current = target
        tuneTask = Task {
            do {
                let url = try await model.receiver.resolve(target)
                try Task.checkCancellation()
                controller.attach(url: url, seekTo: nil, title: target.name, subtitle: target.place.isEmpty ? nil : target.place)
            } catch {
                if Task.isCancelled { return }
                controller.state = .failed(error.localizedDescription)
            }
        }
    }

    private func step(_ delta: Int) {
        let from = destination ?? current
        guard list.count > 1, let position = list.firstIndex(where: { $0.id == from.id }) else { return }
        let target = list[(position + delta + list.count) % list.count]
        destination = target
        overlay.wake(settled: false)
        model.clips.skip()
        changeTask?.cancel()
        changeTask = Task { await change(to: target) }
    }

    /// The screen opens on the ground with the channel's name, which fades off as the picture arrives.
    private func open() async {
        changing = true
        defer { changing = false }
        model.clips.cover(caption: current.name, animated: false)
        tune(current)
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
        settledAt = Date()
    }

    private func change(to target: Channel) async {
        changing = true
        defer { if destination == nil || destination?.id == target.id { changing = false } }
        async let quiet: Void = controller.fadeOut()
        await model.clips.flyThrough(caption: target.name) {
            guard destination?.id == target.id else { return }
            tune(target)
            destination = nil
        }
        await quiet
        guard !Task.isCancelled else { return }
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
        settledAt = Date()
    }

    private func stopEverything() {
        tuneTask?.cancel()
        changeTask?.cancel()
        overlay.stop()
        controller.stop()
        model.clips.clear()
    }
}
