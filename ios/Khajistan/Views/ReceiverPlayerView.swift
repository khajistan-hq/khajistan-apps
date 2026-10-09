import SwiftUI
import UIKit

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
            Kicker(stateText).accessibilityIdentifier("playerState")
                #if DEBUG
                .accessibilityValue(current?.id ?? "")
                #endif
            if let current {
                if !(current.mediaType == "radio" && controller.state == .playing) {
                    Text(current.name).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2)
                }
                if !current.place.isEmpty { Text(current.place).kjBody() }
                if let attribution = current.sourceLine {
                    Text(attribution).kjSmall(faint: true).lineLimit(3)
                }
            }
            TransportRow(isPlaying: controller.state == .playing || controller.state == .tuning, toggle: tuner.playPause,
                         previousChannel: tuner.canStep ? { step(-1) } : nil,
                         nextChannel: tuner.canStep ? { step(1) } : nil)
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

/// The Khajistan Receiver as one set, as the website draws it (open-frequencies.html `.receiver`):
/// its tabs in the bar on top, the screen, and the remote under the screen (owner, 2026-10-08:
/// "the reciever is like a device/tv/radio type"; "it should go fullscreen only if fullscreen is
/// chosen"). Off, the screen carries the Khajistan Receiver mark and Surf finds a channel; on, it
/// carries the picture, or the station's name for radio.
struct ReceiverDevice: View {
    @Binding var part: ReceiverView.Part
    @Binding var fullScreen: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalClass

    private var tuner: ReceiverTuner { model.tuner }
    private var player: PlayerController { tuner.player }
    private var store: TransmissionStore { model.transmission }

    var body: some View {
        Group {
            if sizeClass == .regular || verticalClass == .compact {
                // A phone on its side is as short as it is wide: the set sits beside its words,
                // small enough to leave the page room under it.
                HStack(alignment: .top, spacing: 28) {
                    set.frame(width: verticalClass == .compact ? 300 : 560)
                    copy.padding(.top, 52)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    set
                    copy
                }
            }
        }
        .onChange(of: player.state) { old, new in
            tuner.playerStateChanged(from: old, to: new)
            // The screen is hidden from VoiceOver; say what came on.
            if new == .playing, old != .paused, !title.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: title)
            }
        }
        .onChange(of: store.phase) { tuner.transmissionPhaseChanged() }
    }

    /// The set itself: bar, screen and remote, one body.
    private var set: some View {
        // The set's body runs round the screen, as a bezel does, so off it still reads as one
        // object and not a strip of the page between two bars.
        VStack(spacing: 0) {
            bar
            screen.padding(.horizontal, 6)
            remote
        }
        .background(palette.band)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receiverScreen")
    }

    // MARK: Bar

    private var bar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ReceiverView.Part.allCases) { item in
                    Button { part = item } label: {
                        Text(item.title).kjKicker(item == part ? palette.band : palette.onBand)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(item == part ? palette.onBand : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item == part ? .isSelected : [])
                    .accessibilityIdentifier("part-\(item.rawValue)")
                }
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.band)
    }

    // MARK: Screen

    private var hasPicture: Bool {
        switch tuner.source {
        case .live(let channel): return channel.mediaType != "radio"
        case .transmission:
            if case .onAir(let air) = store.phase { return air.programme?.audio_only != true }
            return false
        case nil: return false
        }
    }

    private var showsPicture: Bool { hasPicture && (player.state == .playing || player.state == .paused) }

    private var screen: some View {
        ZStack {
            (showsPicture ? Color.black : palette.ground)
            if hasPicture {
                PlayerLayerView(player: player.player).accessibilityHidden(true)
            } else if tuner.source == nil {
                idleMark.accessibilityHidden(true)
            } else {
                Text(title)
                    .kjDisplay(KJType.headline, tracking: -0.04)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay { StationClipLayer(clips: model.clips) }
        .clipped()
        // Only a radio station's name is read here: it is said nowhere else on the page.
    }

    /// The website's idle mark: the name large, RECEIVER on a band plate under it.
    private var idleMark: some View {
        VStack(spacing: 4) {
            Text("Khajistan").kjDisplay(tracking: -0.075).lineLimit(1).minimumScaleFactor(0.5)
            Text("Receiver").kjKicker(palette.onBand)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(palette.band)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Remote

    private var remote: some View {
        // Off, the set has one key, Surf; the others come with a channel rather than sitting
        // there dimmed.
        HStack(spacing: 0) {
            if tuner.source != nil {
                key("backward.end.fill", "Previous channel", "previousChannel", enabled: tuner.canStep) { tuner.step(-1) }
            }
            key("shuffle", tuner.surfing ? "Surfing" : "Surf", "surf", enabled: !tuner.surfing) { Task { await tuner.surf() } }
            if tuner.source != nil {
                key("forward.end.fill", "Next channel", "nextChannel", enabled: tuner.canStep) { tuner.step(1) }
                Spacer(minLength: 0)
                key(isPlaying ? "pause.fill" : "play.fill", isPlaying ? "Pause" : "Play", "screenPlayPause", enabled: true) {
                    tuner.playPause()
                }
                key("arrow.up.left.and.arrow.down.right", "Full screen", "fullScreen", enabled: true) { fullScreen = true }
                key("power", "Turn the receiver off", "receiverOff", enabled: true) { tuner.stop() }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .background(palette.band)
        .environment(\.palette, palette.onBandPlate)
    }

    private func key(_ symbol: String, _ label: String, _ id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.bold)).frame(width: 46, height: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: What is on

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            // "Playing" and "Standing by" say what the screen and the keys already show, so only a
            // state worth reading is printed. The full state stays for VoiceOver and the UI tests.
            if let shown = visibleState { Kicker(shown).lineLimit(2) }
            if tuner.source == nil {
                Text(part == .transmission ? "Choose a channel below." : "Choose a channel, or press Surf.").kjName().lineLimit(2)
            } else if hasPicture {
                Text(title).kjName().lineLimit(2)
            }
            if let place, !place.isEmpty { Text(place).kjSmall(faint: true).lineLimit(1) }
            if let note = tuner.surfNote { Text(note).kjSmall(faint: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Text(stateLine)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("screenState")
                #if DEBUG
                .accessibilityValue(sourceId)
                #endif
        }
    }

    private var visibleState: String? {
        let line = stateLine.trimmingCharacters(in: .whitespaces)
        return line.isEmpty || line == "Playing" || line == "Standing by" ? nil : line
    }

    private var isPlaying: Bool { player.state == .playing || player.state == .tuning }

    private var sourceId: String {
        switch tuner.source {
        case .live(let channel): return channel.id
        case .transmission(let number): return "transmission-\(number)"
        case nil: return ""
        }
    }

    private var place: String? {
        if case .live(let channel) = tuner.source { return channel.place }
        return nil
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
        switch tuner.source {
        case nil: return tuner.surfing ? "Surfing\u{2026}" : "Standing by"
        case .transmission:
            switch store.phase {
            case .idle, .tuning: return "Channel \(store.channelNumber) \u{00B7} Connecting\u{2026}"
            case .needsSignIn: return "Sign in to watch"
            case .offAir(_, let returns):
                return returns.map { "Off air \u{00B7} returns at \($0) \(StationClock.tzLabel)" } ?? "Off air"
            case .failed(let message): return message
            case .onAir: return "Channel \(store.channelNumber) \u{00B7} \(playerText)"
            }
        case .live: return playerText
        }
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
