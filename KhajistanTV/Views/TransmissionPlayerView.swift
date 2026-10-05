import SwiftUI

/// One channel of Khajistan Transmission, full screen. The first time in a launch the station signs
/// on (the wing, the ident, the wing), then the channel is joined where the clock has reached.
/// Up and down switch channel through the wing wipe. There is no list of programmes and no
/// scrub bar: a channel is tuned, a programme is not chosen.
///
/// A programme that carries a prepared subtitle file (`subtitle_url`) shows it, on by default as on
/// the website, and the strip ends in the Subtitles control: right moves to it, left comes back.
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
    @State private var subtitles = RecordedSubtitles()
    @State private var captionArmed = false
    @State private var stripHeight: CGFloat = 0
    @FocusState private var focus: PlayerFocus?

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            content
            // On air the focus target sits inside the picture's layers, under the strip, so the
            // Subtitles control in the strip can take focus; a view covered by the picture cannot.
            if holdsFocus && !isOnAir {
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
        .task(id: subtitleKey) { await loadSubtitles() }
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
            focusTarget
            overlay(air)
            CaptionLayer(text: subtitles.text, skin: model.skin, lift: stripShown ? stripHeight : 0)
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
                    upNext: next.map { ($0.startLabel, $0.show?.name ?? "") },
                    accessory: subtitles.tracks.isEmpty ? nil : AnyView(subtitlesControl)
                )
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
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
        // A schedule file (DEBUG, UI tests) plays no picture; its strip shows as a playing one does.
        if store.isScheduleFile { return true }
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
        .focused($focus, equals: .surface)
        .accessibilityLabel("Show details")
    }

    /// A button only once the viewer has moved to it, and focused as it appears.
    @ViewBuilder
    private var subtitlesControl: some View {
        if captionArmed {
            Button {
                subtitles.cycle()
            } label: {
                Text(subtitles.label)
            }
            .buttonStyle(StripChipStyle(isOn: subtitles.current != nil))
            .focused($focus, equals: .captions)
            .onAppear { focus = .captions }
            .accessibilityIdentifier("subtitlesControl")
        } else {
            StripChipStyle.face(Text(subtitles.label), isOn: subtitles.current != nil)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("subtitlesControl")
        }
    }

    // MARK: - Subtitles

    /// The programme on air, so a handover loads the next programme's file.
    private var subtitleKey: String? {
        guard case .onAir(let air) = store.phase else { return nil }
        return "\(air.date) \(air.slot.start) \(air.programmeId)"
    }

    /// The programme's prepared file, read through the site's gate like the schedule: without the
    /// preview password first, then with it. A programme without one shows no control.
    private func loadSubtitles() async {
        subtitles.clear()
        guard case .onAir(let air) = store.phase, let source = await subtitleSource(air) else { return }
        let opened = Date()
        let store = store
        subtitles.load(vtt: source, language: .init(code: "en", label: "English")) {
            let player = store.player.player
            if player.currentItem != nil {
                let time = player.currentTime().seconds
                return time.isFinite ? time : nil
            }
            #if DEBUG
            // A schedule file plays no picture; the slot's own position stands in for the file's.
            if store.isScheduleFile { return air.seekTo + Date().timeIntervalSince(opened) }
            #endif
            return nil
        }
    }

    private func subtitleSource(_ air: OnAir) async -> String? {
        #if DEBUG
        // `-kjsubtitlefile <path>`: a UI test's WebVTT file for whatever is on air.
        if let path = UserDefaults.standard.string(forKey: "kjsubtitlefile") {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        #endif
        guard let path = air.programme?.subtitle_url, let url = KJURL.sitePath(path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard var (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if (response as? HTTPURLResponse)?.statusCode == 401, let password = model.auth.previewPassword {
            request.setValue(Transmission.basicAuthorization(user: KJConfig.previewUser, password: password), forHTTPHeaderField: "Authorization")
            guard let again = try? await URLSession.shared.data(for: request) else { return nil }
            (data, response) = again
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private var isOnAir: Bool {
        if case .onAir = store.phase { return true }
        return false
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
        if direction == .right, !subtitles.tracks.isEmpty, stripShown {
            hideTask?.cancel()
            captionArmed = true
            return
        }
        if direction == .left, captionArmed {
            captionArmed = false
            focus = .surface
            wake()
            return
        }
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
            if !left { await model.clips.holdUntil { await store.player.settled() } }
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
            if !gone { await model.clips.holdUntil { await store.player.settled() } }
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
        subtitles.clear()
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
            // The strip stays while the viewer is on its Subtitles control.
            if !Task.isCancelled, focus != .captions {
                overlayVisible = false
                captionArmed = false
            }
        }
    }
}
