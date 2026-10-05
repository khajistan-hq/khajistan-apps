import SwiftUI

/// One channel of Khajistan Transmission, full screen. The first time in a launch the station signs
/// on (the wing, the ident, the wing), then the channel is joined where the clock has reached.
/// Up and down switch channel through the wing wipe. There is no list of programmes and no
/// scrub bar: a channel is tuned, a programme is not chosen.
struct TransmissionPlayerView: View {
    /// The channel the viewer chose. The store holds the channel now on air, which Up and Down change.
    let channel: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showSignIn = false
    @State private var switching = false
    /// Set when the viewer leaves, so a sequence that is part-way through does not start the next step.
    @State private var left = false

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            content
            if holdsFocus {
                focusTarget
            }
            StationClipLayer(clips: model.clips)
        }
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            move(direction)
        }
        .onPlayPauseCommand {
            playPause()
        }
        .onExitCommand {
            leave()
            dismiss()
        }
        .onChange(of: store.phase) { wake() }
        .onChange(of: store.player.state) { wake() }
        // A schedule that now needs the preview password, or is not published, is answered on
        // the station page, which carries the password step. The player goes back to it.
        .onChange(of: store.schedule) { _, schedule in
            switch schedule {
            case .needsPreviewPassword, .noSchedule:
                leave()
                dismiss()
            default:
                break
            }
        }
        .task { await start() }
        .onDisappear { leave() }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { await store.tune(channel: store.channelNumber) })
        }
    }

    // MARK: - What the phase puts on screen

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .tuning:
            TuningLoader("Connecting\u{2026}")
        case .needsSignIn:
            message("Sign in to watch Khajistan Transmission.") {
                Button("Sign in") {
                    showSignIn = true
                }
                .buttonStyle(HouseButtonStyle())
            }
        case .offAir(channelName: let name, returns: let returns):
            VStack(alignment: .leading, spacing: 28) {
                Text("Off air").kjDisplay()
                Text(returns.map { "\(name) returns at \($0) \(StationClock.tzLabel)." } ?? "\(name) is off air.")
                    .kjBody()
                Text("Up or down switches channel.").kjSmall(faint: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
        case .onAir(let air):
            onAir(air)
        case .failed(let text):
            message(text) {
                Button("Try again") {
                    Task { await store.tune(channel: store.channelNumber) }
                }
                .buttonStyle(HouseButtonStyle())
            }
        }
    }

    private func message<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(text).kjBody()
            actions()
        }
        .kjBody()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, KJLayout.inset)
    }

    private func onAir(_ air: OnAir) -> some View {
        ZStack {
            if air.programme?.audio_only == true {
                DancerLayer(controller: store.player) {
                    soundOnly(air)
                }
            } else {
                // A picture that does not fill the screen sits on black (owner, 2026-10-05).
                Color.black.ignoresSafeArea()
                PlayerLayerView(player: store.player.player)
                    .ignoresSafeArea()
            }
            if store.player.state == .tuning {
                // The ground covers the picture while the signal is on its way; the loader itself
                // sits in the overlay, between the band and the panel.
                palette.ground.ignoresSafeArea()
            }
            overlay(air)
            HandoverNotice(
                air: air,
                next: store.upcoming(channel: store.channelNumber, at: Date(), count: 1).first,
                overlayVisible: overlayVisible
            )
        }
    }

    /// What an audio-only transmission shows in place of a picture. The panel does not repeat the
    /// title or the credits while this is on screen.
    private func soundOnly(_ air: OnAir) -> some View {
        VStack(spacing: 24) {
            Kicker("Channel \(store.channelNumber) \u{00B7} sound only")
            Text(headline(air))
                .kjDisplay()
                .multilineTextAlignment(.center)
            if let custodian = nonEmpty(air.programme?.custodian) {
                Text(custodian).kjSmall(faint: true)
            }
            if let transfer = nonEmpty(air.programme?.transfer) {
                Text(transfer).kjSmall(faint: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, KJLayout.inset)
    }

    // MARK: - The overlay

    /// The slim strip, as the Receiver's (owner, 2026-10-05: the bar was "too thick"): the slot
    /// and the show at left with the show's line under them, the channel and what is up next at
    /// right. It rises and fades with the overlay; while the signal tunes the ground says so.
    private func overlay(_ air: OnAir) -> some View {
        let soundOnly = air.programme?.audio_only == true
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            // Redrawn on the minute, so what is up next moves on at a handover.
            TimelineView(.everyMinute) { context in
                let next = store.upcoming(channel: store.channelNumber, at: context.date, count: 1).first
                PlayerStrip(
                    // A sound programme carries its name on the ground, with the dancer.
                    name: soundOnly ? nil : headline(air),
                    detail: stateText(air),
                    attribution: credit(air),
                    trailing: ["\u{25CF} Channel \(store.channelNumber)"],
                    upNext: next.map { ($0.startLabel, $0.show?.name ?? "") }
                )
            }
            .offset(y: stripShown ? 0 : 40)
            .opacity(stripShown ? 1 : 0)
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: stripShown)
        .overlay(alignment: .bottomLeading) {
            Text(stateText(air))
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("playerState")
        }
    }

    private var stripShown: Bool {
        guard overlayVisible else { return false }
        switch store.player.state {
        case .playing, .paused, .failed: return true
        case .idle, .tuning: return false
        }
    }

    /// One small line under the name: the show's own line, else the custodian and the transfer.
    private func credit(_ air: OnAir) -> String? {
        if let line = nonEmpty(air.show?.line) { return line }
        let parts = [air.programme?.custodian, air.programme?.transfer].compactMap { nonEmpty($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Words

    /// The show, not the programme: programme titles are file names (owner, 2026-09-06, on
    /// the receiver's two channel rows: "just programming block names").
    private func headline(_ air: OnAir) -> String {
        nonEmpty(air.show?.name) ?? nonEmpty(air.programme?.title) ?? store.channelName(store.channelNumber)
    }

    /// While the programme plays, the slot it belongs to, as the station page says it.
    private func stateText(_ air: OnAir) -> String {
        switch store.player.state {
        case .idle, .playing: return "Now \(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)"
        case .tuning: return "Tuning\u{2026}"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - The remote

    /// A full-screen button that draws nothing. It holds focus so the remote's presses reach the
    /// handlers above, and a click skips a clip or wakes the overlay. It is left out while a
    /// button of the screen's own (Sign in, Try again) is the thing to focus.
    private var focusTarget: some View {
        Button {
            if model.clips.showing {
                model.clips.skip()
            } else {
                wake()
            }
        } label: {
            Color.clear
        }
        .buttonStyle(SurfaceButtonStyle())
        .accessibilityLabel("Show details")
    }

    private var holdsFocus: Bool {
        switch store.phase {
        case .needsSignIn, .failed: return false
        default: return true
        }
    }

    /// Up and down switch channel behind the pigeon. While it is flying they skip it.
    private func move(_ direction: MoveCommandDirection) {
        wake()
        guard direction == .up || direction == .down else { return }
        if model.clips.showing {
            model.clips.skip()
            return
        }
        guard holdsFocus, !switching else { return }
        switching = true
        Task {
            let next = store.channelNumber == 1 ? 2 : 1
            async let quiet: Void = store.player.fadeOut()
            var retune: Task<Void, Never>?
            await model.clips.flyThrough(caption: store.channelName(next)) {
                if !left { retune = Task { await store.switchChannel() } }
            }
            await quiet
            await retune?.value
            if !left { await store.player.settled() }
            if !left { model.clips.uncover() }
            switching = false
        }
    }

    /// Pauses a picture that is playing. Anything else joins the channel again, live: a paused
    /// transmission is not the transmission any more.
    private func playPause() {
        wake()
        if model.clips.showing {
            model.clips.skip()
        } else if store.player.state == .playing {
            store.player.pause()
        } else {
            Task { await store.rejoinLive() }
        }
    }

    // MARK: - Coming and going

    /// The sign-on, once per launch: the pigeon flies through and the programme (joined where
    /// the clock has reached) tunes behind it. Later visits open on the ground with the channel's
    /// name. Either way the ground fades off as the picture arrives. Every step checks that the
    /// viewer is still here: a flight must not start after the screen has gone.
    private func start() async {
        // After a flight the picture cuts in; on a screen that opens with nothing flying it fades.
        let flies = !model.clips.signOnPlayed
        if flies {
            model.clips.signOnPlayed = true
            var tuning: Task<Void, Never>?
            await model.clips.flyThrough(caption: store.channelName(channel)) {
                if !gone { tuning = Task { await store.tune(channel: channel) } }
            }
            await tuning?.value
        } else {
            model.clips.cover(caption: store.channelName(channel), animated: false)
            if !gone { await store.tune(channel: channel) }
        }
        if !gone { await store.player.settled() }
        if !gone { model.clips.uncover(fade: !flies) }
    }

    private var gone: Bool {
        left || Task.isCancelled
    }

    private func leave() {
        left = true
        hideTask?.cancel()
        store.stop()
        model.clips.clear()
    }

    /// Shows the overlay. Once the programme is playing it hides again after 2.6 seconds without
    /// a press; while tuning, paused or failed it stays.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        // A schedule file (DEBUG, UI tests) plays no picture; its overlay hides as a playing one does.
        guard store.player.state == .playing || store.isScheduleFile else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { overlayVisible = false }
        }
    }
}
