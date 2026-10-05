import SwiftUI

/// Khajistan Transmission, the station page. It names the two channels and what is on each, and
/// opens one of them full screen. A channel is tuned and the clock says what is on it: there is
/// no list of programmes to choose from and no scrub bar.
struct TransmissionView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var showSignIn = false
    /// The channel the viewer chose while signed out, and the one to open once the sign-in sheet
    /// has closed. A cover cannot open over a sheet that is still on its way down.
    @State private var chosen: Int?
    @State private var openAfterSignIn: Int?
    @State private var playing: ChannelChoice?

    private struct ChannelChoice: Identifiable {
        let number: Int
        var id: Int { number }
    }

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("Khajistan Transmission")
                    .kjDisplay()
                    .accessibilityAddTraits(.isHeader)
                meta
                scheduleBlock
            }
            // Buttons take the platform's text style unless told otherwise; the house scale decides.
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await store.loadSchedule()
            // A page left open as the month turns takes the new month's schedule. A schedule
            // held for the current month answers at once, so this costs nothing most of the time.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if store.schedule == .ready { await store.loadSchedule() }
            }
        }
        .sheet(isPresented: $showSignIn, onDismiss: { openChosen() }) {
            SignInView(onSignedIn: { openAfterSignIn = chosen })
        }
        .fullScreenCover(item: $playing) { choice in
            TransmissionPlayerView(channel: choice.number)
        }
    }

    // MARK: - The page

    /// The count is known once the schedule is held. In that state this line is the page's state
    /// line, since a Text inside a card's button label is merged into the button and cannot be
    /// found as a static text.
    @ViewBuilder
    private var meta: some View {
        if case .ready = store.schedule {
            Text(metaText)
                .kjBody()
                .transmissionState("Ready")
        } else {
            Text(metaText)
                .kjBody()
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tuning Khajistan Transmission")
                .accessibilityAddTraits(.isStaticText)
                .transmissionState("Loading")
        case .needsPreviewPassword(let message):
            VStack(alignment: .leading, spacing: 28) {
                Text("The schedule is behind the preview password until launch.")
                    .kjBody()
                    .transmissionState("Preview password")
                if let message {
                    Text(message).kjBody()
                }
                HouseInputField("Password") {
                    SecureField("", text: $password)
                }
                Button("Continue") {
                    submitPassword()
                }
                .buttonStyle(HouseButtonStyle())
                .disabled(password.isEmpty)
                .opacity(password.isEmpty ? 0.5 : 1)
            }
        case .noSchedule:
            VStack(alignment: .leading, spacing: 28) {
                Text("The schedule for this month has not been published.")
                    .kjBody()
                    .transmissionState("No schedule")
                tryAgain
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 28) {
                Text(message)
                    .kjBody()
                    .transmissionState("Failed")
                tryAgain
            }
        case .ready:
            VStack(alignment: .leading, spacing: 48) {
                // The cards read the clock, so they are drawn again every half minute.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(alignment: .top, spacing: 40) {
                        ForEach([1, 2], id: \.self) { number in
                            card(number, at: context.date)
                        }
                    }
                }
                if !model.auth.isSignedIn {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Sign in to watch Khajistan Transmission.")
                            .kjBody()
                        Button("Sign in") {
                            chosen = nil
                            showSignIn = true
                        }
                        .buttonStyle(HouseButtonStyle())
                    }
                }
            }
        }
    }

    private var tryAgain: some View {
        Button("Try again") {
            Task { await store.loadSchedule() }
        }
        .buttonStyle(HouseButtonStyle())
    }

    private func card(_ number: Int, at date: Date) -> some View {
        Button {
            choose(number)
        } label: {
            ChannelCardLabel(
                number: number,
                line: store.channelLine(number),
                onAir: store.nowOn(channel: number, at: date),
                returns: store.returnTime(channel: number, at: date)
            )
        }
        .buttonStyle(HouseButtonStyle())
        .accessibilityIdentifier("transmission-channel-\(number)")
    }

    // MARK: - Choosing

    /// A signed-in viewer opens the channel. A signed-out one signs in first, and the channel
    /// opens when the sheet has closed.
    private func choose(_ number: Int) {
        if model.auth.isSignedIn {
            playing = ChannelChoice(number: number)
        } else {
            chosen = number
            showSignIn = true
        }
    }

    private func openChosen() {
        if let number = openAfterSignIn {
            playing = ChannelChoice(number: number)
        }
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

/// One channel's card: its number, whether it is on air, its own line from the schedule, and
/// what is on it now or when it returns. It sits inside a button's plate, so every colour comes
/// from the palette the plate sets for it, through the kicker and the inherited ink.
private struct ChannelCardLabel: View {
    let number: Int
    let line: String?
    let onAir: OnAir?
    let returns: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                Kicker("Channel \(number)")
                Kicker(onAir == nil ? "Off air" : "\u{25CF} On air")
            }
            if let line, !line.isEmpty {
                Text(line).kjBody()
            }
            if let air = onAir {
                if let show = air.show?.name, !show.isEmpty {
                    Text(show).kjName()
                }
                if let title = air.programme?.title, !title.isEmpty {
                    Text(title).kjBody()
                }
                Kicker("\(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)")
            } else if let returns, !returns.isEmpty {
                Text("Returns at \(returns) \(StationClock.tzLabel)").kjBody()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
    }
}

private extension View {
    /// The page's state, as the accessibility value of its state line. The UI tests read it and it
    /// is never drawn.
    func transmissionState(_ marker: String) -> some View {
        accessibilityIdentifier("transmissionState")
            .accessibilityValue(marker)
    }
}
