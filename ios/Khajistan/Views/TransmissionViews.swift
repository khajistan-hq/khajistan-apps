import SwiftUI

/// Khajistan Transmission inside the Receiver, as the website carries it: two scheduled channels
/// on Pakistan time, what is on each now and what is up next. A channel is tuned and the clock says
/// what is on it; there is no list of programmes to choose from. Playback needs an account, as
/// tv-play does (ported from the Apple TV app's station page).
struct TransmissionSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var password = ""
    @State private var showSignIn = false
    @State private var chosen: Int?
    @State private var openAfterSignIn: Int?
    @State private var playing: ChannelChoice?

    private struct ChannelChoice: Identifiable {
        let number: Int
        var id: Int { number }
    }

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Khajistan Transmission").kjDisplay(KJType.headline, tracking: -0.04)
                Text(metaText).kjSmall(faint: true)
            }
            scheduleBlock
        }
        .task {
            await store.loadSchedule()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if store.schedule == .ready { await store.loadSchedule() }
            }
        }
        .sheet(isPresented: $showSignIn, onDismiss: openChosen) {
            SignInView(onSignedIn: { openAfterSignIn = chosen })
        }
        .fullScreenCover(item: $playing) { choice in
            TransmissionPlayerView(channel: choice.number)
        }
    }

    private var metaText: String {
        let tail = "two scheduled channels \u{00B7} Pakistan time (UTC+5)"
        guard case .ready = store.schedule, let count = store.programmeCount else { return tail }
        return "\(count.formatted()) \(count == 1 ? "programme" : "programmes") \u{00B7} \(tail)"
    }

    @ViewBuilder
    private var scheduleBlock: some View {
        switch store.schedule {
        case .idle, .loading:
            TuningLoader("Tuning Khajistan Transmission\u{2026}")
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityIdentifier("transmissionLoading")
        case .needsPreviewPassword(let message):
            VStack(alignment: .leading, spacing: 14) {
                Text("The schedule is behind the preview password until launch.").kjBody()
                    .accessibilityIdentifier("transmissionPreview")
                if let message { Text(message).kjBody() }
                HouseInputField("Preview password") {
                    SecureField("", text: $password).onSubmit(submitPassword)
                }
                Button(kicker: "Continue", action: submitPassword)
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .disabled(password.isEmpty)
            }
        case .noSchedule:
            problem("The schedule for this month has not been published.")
        case .failed(let message):
            problem(message)
        case .ready:
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach([1, 2], id: \.self) { number in
                            HouseRule()
                            Button { choose(number) } label: {
                                ChannelCard(number: number, line: store.channelLine(number),
                                            onAir: store.nowOn(channel: number, at: context.date),
                                            returns: store.returnTime(channel: number, at: context.date))
                            }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)))
                            .accessibilityIdentifier("transmission-channel-\(number)")
                        }
                    }
                }
                if !model.auth.isSignedIn {
                    HouseRule()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sign in to watch Khajistan Transmission.").kjBody()
                        Button(kicker: "Sign in") {
                            chosen = nil
                            showSignIn = true
                        }
                        .buttonStyle(HouseButtonStyle(solid: true))
                        .accessibilityIdentifier("transmissionSignIn")
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private func problem(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).kjBody()
            Button(kicker: "Try again") { Task { await store.loadSchedule() } }
                .buttonStyle(HouseButtonStyle(solid: true))
        }
    }

    private func choose(_ number: Int) {
        if model.auth.isSignedIn {
            playing = ChannelChoice(number: number)
        } else {
            chosen = number
            showSignIn = true
        }
    }

    private func openChosen() {
        if let number = openAfterSignIn { playing = ChannelChoice(number: number) }
        openAfterSignIn = nil
        chosen = nil
    }

    private func submitPassword() {
        let entered = password
        password = ""
        Task {
            model.auth.setPreviewPassword(entered)
            await store.loadSchedule()
        }
    }
}

/// One channel: its number, on air or not, its own line, what is on now and what is up next.
private struct ChannelCard: View {
    let number: Int
    let line: String?
    let onAir: OnAir?
    let returns: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Kicker("Channel \(number)")
                Kicker(onAir == nil ? "Off air" : "\u{25CF} On air")
                Spacer(minLength: 0)
                Text("\u{2192}").kjName().accessibilityHidden(true)
            }
            if let line, !line.isEmpty { Text(line).kjSmall(faint: true) }
            if let air = onAir {
                if let show = air.show?.name, !show.isEmpty { Text(show).kjName(KJType.title) }
                if let title = air.programme?.title, !title.isEmpty { Text(title).kjBody().lineLimit(2) }
                Kicker("Now \(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)")
                if let start = air.nextStart {
                    Text("Up next \(start)" + (air.nextShow.map { " \u{00B7} \($0.name)" } ?? "")).kjSmall(faint: true)
                }
            } else if let returns, !returns.isEmpty {
                Text("Returns at \(returns) \(StationClock.tzLabel)").kjBody()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One channel of Khajistan Transmission, full screen. The first time in a launch the pigeon flies
/// through and the programme tunes behind it (the website's sign-on); later it opens on the ground
/// with the channel's name. A swipe up or down switches channel through the wing.
struct TransmissionPlayerView: View {
    let channel: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var overlay = OverlayClock()
    @State private var showSignIn = false
    @State private var switching = false
    @State private var left = false

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            content(palette)
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .statusBarHidden(!overlay.visible)
        .onChange(of: store.phase) { overlay.wake(settled: store.player.state == .playing) }
        .onChange(of: store.player.state) { overlay.wake(settled: store.player.state == .playing) }
        .onChange(of: store.schedule) { _, schedule in
            switch schedule {
            case .needsPreviewPassword, .noSchedule: close()
            default: break
            }
        }
        .task { await start() }
        .onDisappear { leave() }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { await store.tune(channel: store.channelNumber) })
        }
        .accessibilityAction(named: "Switch channel") { switchChannel() }
    }

    @ViewBuilder
    private func content(_ palette: Palette) -> some View {
        switch store.phase {
        case .idle, .tuning:
            VStack(spacing: 0) {
                topBar([])
                Spacer()
                TuningLoader("Connecting\u{2026}")
                Spacer()
            }
        case .needsSignIn:
            message("Sign in to watch Khajistan Transmission.") {
                Button(kicker: "Sign in") { showSignIn = true }.buttonStyle(HouseButtonStyle(solid: true))
            }
        case .offAir(channelName: let name, returns: let returns):
            message(returns.map { "\(name) returns at \($0) \(StationClock.tzLabel)." } ?? "\(name) is off air.", title: "Off air") {
                Text("Swipe up or down to switch channel.").kjSmall(faint: true)
            }
            .channelGestures(step: { _ in switchChannel() }, tap: {})
        case .onAir(let air):
            onAir(air, palette)
        case .failed(let text):
            message(text) {
                Button(kicker: "Try again") { Task { await store.tune(channel: store.channelNumber) } }
                    .buttonStyle(HouseButtonStyle(solid: true))
            }
        }
    }

    private func topBar(_ trailing: [String], air: OnAir? = nil) -> some View {
        var leading = ["Khajistan Transmission", "Channel \(store.channelNumber)"]
        if let air { leading.append("\(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)") }
        return PlayerTopBar(leading: leading, trailing: trailing) { close() }
    }

    private func message<Actions: View>(_ text: String, title: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar([])
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                if let title { Text(title).kjDisplay() }
                Text(text).kjBody()
                actions()
            }
            .padding(.horizontal, KJLayout.inset)
            Spacer()
        }
    }

    private func onAir(_ air: OnAir, _ palette: Palette) -> some View {
        ZStack {
            if air.programme?.audio_only == true {
                VStack(spacing: 12) {
                    Kicker("Channel \(store.channelNumber) \u{00B7} sound only")
                    Text(headline(air)).kjDisplay().multilineTextAlignment(.center)
                }
                .padding(.horizontal, KJLayout.inset)
            } else {
                Color.black.ignoresSafeArea()
                PlayerLayerView(player: store.player.player).ignoresSafeArea()
            }
            if store.player.state == .tuning { palette.ground.ignoresSafeArea() }
            Color.clear.channelGestures(step: { _ in switchChannel() }, tap: { overlay.toggle(settled: store.player.state == .playing) })
            VStack(spacing: 0) {
                topBar(air.nextStart.map { ["Up next \($0)" + (air.nextShow.map { " \($0.name)" } ?? "")] } ?? [], air: air)
                Spacer(minLength: 0)
                panel(air).background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
            }
            .opacity(overlay.visible ? 1 : 0)
            .allowsHitTesting(overlay.visible)
        }
    }

    private func panel(_ air: OnAir) -> some View {
        let soundOnly = air.programme?.audio_only == true
        return VStack(alignment: .leading, spacing: 6) {
            Kicker(stateText).accessibilityIdentifier("playerState")
            if !soundOnly { Text(headline(air)).kjDisplay(KJType.headline, tracking: -0.04).lineLimit(2) }
            if let show = nonEmpty(air.show?.name) { Kicker(show) }
            if let line = nonEmpty(air.show?.line) { Text(line).kjSmall(faint: true).lineLimit(3) }
            let facts = [nonEmpty(air.programme?.work_kind), nonEmpty(air.programme?.country)].compactMap { $0 }
            if !facts.isEmpty { Text(facts.joined(separator: " \u{00B7} ")).kjSmall() }
            if let custodian = nonEmpty(air.programme?.custodian) { Text(custodian).kjSmall(faint: true) }
            if let transfer = nonEmpty(air.programme?.transfer) { Text(transfer).kjSmall(faint: true) }
            TransportRow(isPlaying: store.player.state == .playing, toggle: playPause)
            Text("Swipe up or down to switch channel.").kjSmall(faint: true)
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headline(_ air: OnAir) -> String {
        nonEmpty(air.programme?.title) ?? nonEmpty(air.show?.name) ?? store.channelName(store.channelNumber)
    }

    private var stateText: String {
        switch store.player.state {
        case .idle: return " "
        case .tuning: return "Tuning\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Controls

    private func switchChannel() {
        overlay.wake(settled: false)
        if model.clips.showing { model.clips.skip(); return }
        guard !switching else { return }
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

    /// Pauses a picture that is playing; anything else joins the channel again, live.
    private func playPause() {
        if store.player.state == .playing {
            store.player.pause()
        } else {
            Task { await store.rejoinLive() }
        }
    }

    private func start() async {
        if !model.clips.signOnPlayed {
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
        if !gone { model.clips.uncover() }
    }

    private var gone: Bool { left || Task.isCancelled }

    private func close() {
        leave()
        dismiss()
    }

    private func leave() {
        left = true
        overlay.stop()
        store.stop()
        model.clips.clear()
    }
}
