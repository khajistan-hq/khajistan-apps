import SwiftUI

/// The live channel the Receiver is playing, full screen, chosen from the docked screen's
/// full-screen control (ported from the Apple TV app). It reads the tab's one tuner, so closing it
/// leaves the channel playing in the docked screen. A swipe up tunes the next channel in the list
/// the reader came from and a swipe down the one before, behind the pigeon. A picture that does
/// not fill the screen sits on black (owner, 2026-10-05); radio keeps the skin's ground.
struct ReceiverPlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var overlay = OverlayClock()

    private var tuner: ReceiverTuner { model.tuner }
    private var controller: PlayerController { tuner.controller }
    private var current: Channel? { tuner.channel }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: controller.player).ignoresSafeArea()
            if let current, current.mediaType == "radio" && controller.state == .playing {
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
        .onChange(of: controller.state) { _, new in overlay.wake(settled: new == .playing) }
        // The receiver was turned off, or switched to Transmission, while this was up.
        .onChange(of: tuner.channel == nil) { _, off in if off { dismiss() } }
        .onAppear { overlay.wake(settled: controller.state == .playing) }
        .onDisappear { overlay.stop() }
        .accessibilityAction(named: "Next channel") { step(1) }
        .accessibilityAction(named: "Previous channel") { step(-1) }
    }

    private func step(_ delta: Int) {
        overlay.wake(settled: false)
        tuner.step(delta)
    }

    // MARK: - Overlay

    private func chrome(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            PlayerTopBar(leading: bandLeading, trailing: ["\u{25CF} \(liveLabel)"]) { dismiss() }
            Spacer(minLength: 0)
            panel.background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(stateText).accessibilityIdentifier("playerState").accessibilityValue(current?.id ?? "")
            if let current {
                if !(current.mediaType == "radio" && controller.state == .playing) {
                    Text(current.name).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
                }
                if !current.place.isEmpty { Text(current.place).kjBody() }
                if let attribution = current.attributionText, !attribution.isEmpty {
                    Text(attribution).kjSmall(faint: true).lineLimit(3)
                }
            }
            TransportRow(isPlaying: controller.state == .playing || controller.state == .tuning, toggle: tuner.playPause)
            if tuner.canStep {
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
        if let country = current?.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            items.append("Broadcasting from \(country)")
        }
        return items
    }

    private var liveLabel: String {
        switch current?.mediaType.lowercased() {
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
        current?.mediaType != "radio" && (controller.state == .playing || controller.state == .paused)
    }
}

/// The screen docked at the top of the Receiver tab: what the tuner is playing, with the picture
/// for television and cameras, and its controls. It stays above the list while the reader browses
/// (owner, 2026-10-08: "i need reciever to work like a reciever"). Radio, and a Transmission channel
/// that is off air or sound only, has no picture box: the row says what is on.
struct ReceiverScreen: View {
    @Binding var fullScreen: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var tuner: ReceiverTuner { model.tuner }
    private var player: PlayerController { tuner.player }
    private var store: TransmissionStore { model.transmission }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .center, spacing: 24) {
                    if hasPicture { picture.frame(width: 480) }
                    controls
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if hasPicture { picture }
                    controls
                        .padding(.horizontal, KJLayout.inset)
                        .padding(.vertical, 8)
                }
            }
        }
        .kjColumn(KJLayout.wideWidth)
        .background(palette.ground)
        .onChange(of: player.state) { old, new in tuner.playerStateChanged(from: old, to: new) }
        .onChange(of: store.phase) { tuner.transmissionPhaseChanged() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receiverScreen")
    }

    // MARK: Picture

    private var hasPicture: Bool {
        switch tuner.source {
        case .live(let channel): return channel.mediaType != "radio"
        case .transmission:
            if case .onAir(let air) = store.phase { return air.programme?.audio_only != true }
            return false
        case nil: return false
        }
    }

    private var showsPicture: Bool { player.state == .playing || player.state == .paused }

    private var picture: some View {
        ZStack {
            (showsPicture ? Color.black : palette.ground)
            PlayerLayerView(player: player.player)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay { StationClipLayer(clips: model.clips) }
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(stateLine).lineLimit(2)
                    .accessibilityIdentifier("screenState")
                    .accessibilityValue(sourceId)
                Text(title).kjName().lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if tuner.canStep { control("backward.end.fill", "Previous channel", "previousChannel") { tuner.step(-1) } }
            control(isPlaying ? "pause.fill" : "play.fill", isPlaying ? "Pause" : "Play", "screenPlayPause") { tuner.playPause() }
            if tuner.canStep { control("forward.end.fill", "Next channel", "nextChannel") { tuner.step(1) } }
            control("arrow.up.left.and.arrow.down.right", "Full screen", "fullScreen") { fullScreen = true }
            control("xmark", "Turn the receiver off", "receiverOff") { tuner.stop() }
        }
    }

    private func control(_ symbol: String, _ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.bold)).frame(width: 40, height: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var isPlaying: Bool { player.state == .playing || player.state == .tuning }

    private var sourceId: String {
        switch tuner.source {
        case .live(let channel): return channel.id
        case .transmission(let number): return "transmission-\(number)"
        case nil: return ""
        }
    }

    private var title: String {
        switch tuner.source {
        case .live(let channel): return channel.name
        case .transmission:
            if case .onAir(let air) = store.phase,
               let name = [air.programme?.title, air.show?.name].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                return name
            }
            return store.channelName(store.channelNumber)
        case nil: return ""
        }
    }

    private var stateLine: String {
        if case .transmission = tuner.source {
            switch store.phase {
            case .idle, .tuning: return "Channel \(store.channelNumber) \u{00B7} Connecting\u{2026}"
            case .needsSignIn: return "Sign in under Account to watch"
            case .offAir(_, let returns):
                return returns.map { "Off air \u{00B7} returns at \($0) \(StationClock.tzLabel)" } ?? "Off air"
            case .failed(let message): return message
            case .onAir: return "Channel \(store.channelNumber) \u{00B7} \(playerText)"
            }
        }
        return playerText
    }

    private var playerText: String {
        switch player.state {
        case .idle: return " "
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }
}
