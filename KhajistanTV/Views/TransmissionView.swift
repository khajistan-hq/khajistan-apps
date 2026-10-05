import SwiftUI

/// Khajistan TV. A channel is tuned and the clock says what is on it; there is no list of
/// programmes to choose from and no scrub bar. Up or down switches between the two channels.
struct TransmissionView: View {
    @Environment(AppModel.self) private var model
    @State private var showSignIn = false
    @State private var passwordDraft = ""
    @State private var hasTuned = false
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            content(palette)
        }
        .foregroundStyle(palette.ink)
        .onChange(of: model.transmission.phase) { wake() }
        .onChange(of: model.transmission.player.state) { wake() }
        .task {
            hasTuned = true
            wake()
            await model.transmission.load()
        }
        .onDisappear {
            // Leaving the tab ends the transmission; coming back tunes it afresh by the clock.
            hasTuned = false
            hideTask?.cancel()
            model.transmission.stop()
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { await model.transmission.load() })
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private func content(_ palette: Palette) -> some View {
        switch model.transmission.phase {
        case .idle:
            if hasTuned {
                statusBlock(marker: "Stopped", line: "Stopped.") {
                    Button("Tune in") {
                        Task { await model.transmission.load() }
                    }
                    .buttonStyle(PlateButtonStyle(palette: palette))
                    .frame(maxWidth: 500, alignment: .leading)
                }
            } else {
                loadingBlock
            }
        case .loading:
            loadingBlock
        case .needsPreviewPassword(let message):
            statusBlock(marker: "Preview password", line: "The schedule is behind the preview password until launch.") {
                if let message {
                    Text(message)
                        .font(KJFont.body())
                }
                SecureField("Password", text: $passwordDraft)
                Button("Continue") {
                    submitPassword()
                }
                .buttonStyle(PlateButtonStyle(palette: palette))
                .frame(maxWidth: 500, alignment: .leading)
                .disabled(passwordDraft.isEmpty)
            }
        case .noSchedule:
            statusBlock(marker: "No schedule", line: "The schedule for this month has not been published.") {
                EmptyView()
            }
        case .needsSignIn:
            statusBlock(marker: "Sign in", line: "Sign in to watch Khajistan TV.") {
                Button("Sign in") {
                    showSignIn = true
                }
                .buttonStyle(PlateButtonStyle(palette: palette))
                .frame(maxWidth: 500, alignment: .leading)
            }
        case .offAir(channelName: let channelName, returns: let returns):
            remote(offAirView(channelName: channelName, returns: returns))
        case .failed(let message):
            statusBlock(marker: "Failed", line: message) {
                Button("Try again") {
                    Task { await model.transmission.load() }
                }
                .buttonStyle(PlateButtonStyle(palette: palette))
                .frame(maxWidth: 500, alignment: .leading)
            }
        case .onAir(let air):
            remote(onAirView(palette, air))
        }
    }

    private var loadingBlock: some View {
        statusBlock(marker: "Loading", line: "Tuning Khajistan TV\u{2026}") {
            EmptyView()
        }
    }

    /// What a phase has to say: its sentence, then whatever it offers. The one-word marker is
    /// the sentence's accessibility value, read by the UI tests and never drawn.
    private func statusBlock<Extra: View>(marker: String, line: String, @ViewBuilder _ extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(line)
                .font(KJFont.body())
                .accessibilityIdentifier("transmissionState")
                .accessibilityValue(marker)
            extra()
        }
        .frame(maxWidth: 1000, alignment: .leading)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func offAirView(channelName: String, returns: String?) -> some View {
        ZStack {
            statusBlock(marker: "Off air", line: offAirLine(channelName: channelName, returns: returns)) {
                Text("Up or down switches channel.")
                    .font(KJFont.caption())
            }
            focusTarget
        }
    }

    private func offAirLine(channelName: String, returns: String?) -> String {
        guard let returns, !returns.isEmpty else { return "Off air." }
        return "Off air. \(channelName) returns at \(returns) \(StationClock.tzLabel)."
    }

    private func onAirView(_ palette: Palette, _ air: OnAir) -> some View {
        let player = model.transmission.player
        let audioOnly = air.programme?.audio_only == true
        return ZStack {
            if audioOnly {
                Text(headline(for: air))
                    .font(KJFont.title())
                    .multilineTextAlignment(.center)
                    .padding(120)
            } else {
                PlayerLayerView(player: player.player)
                    .ignoresSafeArea()
            }
            VStack {
                Spacer()
                infoPlate(palette, air: air, player: player)
            }
            .opacity(overlayVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: overlayVisible)
            focusTarget
        }
    }

    private func infoPlate(_ palette: Palette, air: OnAir, player: PlayerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lineOne(for: air))
                .font(KJFont.body())
                .accessibilityIdentifier("transmissionState")
                .accessibilityValue("On air")
            let title = air.programme?.title ?? ""
            if !title.isEmpty {
                Text(title)
                    .font(KJFont.bodyBold())
            }
            if let custodian = air.programme?.custodian, !custodian.isEmpty {
                Text(custodian)
                    .font(KJFont.caption())
            }
            if let transfer = air.programme?.transfer, !transfer.isEmpty {
                Text(transfer)
                    .font(KJFont.caption())
            }
            Text(stateText(player.state))
                .font(KJFont.caption())
                .accessibilityIdentifier("playerState")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .background(palette.ground)
    }

    // MARK: - Words

    /// The channel, the show and the hours, joined by middle dots. The show is left out when
    /// the schedule names none.
    private func lineOne(for air: OnAir) -> String {
        var parts = [channelLabel(for: air)]
        if let show = air.show?.name, !show.isEmpty { parts.append(show) }
        parts.append("\(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)")
        return parts.joined(separator: " \u{00B7} ")
    }

    private func channelLabel(for air: OnAir) -> String {
        if let info = model.transmission.programming?._meta.channels.first(where: { $0.id == air.channelId }) {
            return info.name
        }
        return model.transmission.channelName(model.transmission.channelNumber)
    }

    /// What an audio-only transmission shows in place of a picture. Five vinyl transfers carry
    /// no title, and for those the show name stands in.
    private func headline(for air: OnAir) -> String {
        let title = air.programme?.title ?? ""
        if !title.isEmpty { return title }
        if let show = air.show?.name, !show.isEmpty { return show }
        return channelLabel(for: air)
    }

    private func stateText(_ state: PlayerController.State) -> String {
        switch state {
        case .idle: return ""
        case .tuning: return "Tuning\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    // MARK: - The remote

    /// Holds focus on a full-screen phase so the remote's presses reach `remote(_:)`, and wakes
    /// the overlay on a click. It draws nothing.
    private var focusTarget: some View {
        Button {
            wake()
        } label: {
            Color.clear
        }
        .buttonStyle(SurfaceButtonStyle())
    }

    /// Up or down switches channel, play/pause pauses (or rejoins the channel live when it is
    /// not playing), and the menu button stops the transmission. The view stays; the tab is
    /// the container.
    private func remote<Surface: View>(_ surface: Surface) -> some View {
        surface
            .onMoveCommand { direction in
                wake()
                if direction == .up || direction == .down {
                    Task { await model.transmission.switchChannel() }
                }
            }
            .onPlayPauseCommand {
                wake()
                if model.transmission.player.state == .playing {
                    model.transmission.player.pause()
                } else {
                    Task { await model.transmission.rejoinLive() }
                }
            }
            .onExitCommand {
                model.transmission.stop()
            }
    }

    private func submitPassword() {
        let entered = passwordDraft
        passwordDraft = ""
        Task {
            model.auth.setPreviewPassword(entered)
            await model.transmission.load()
        }
    }

    /// Shows the overlay. Once the programme is playing it hides again after 2.6 seconds
    /// without a press; while tuning, paused or failed it stays.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        guard model.transmission.player.state == .playing else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { overlayVisible = false }
        }
    }
}
