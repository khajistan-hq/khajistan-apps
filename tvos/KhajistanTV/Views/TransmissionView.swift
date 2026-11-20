import SwiftUI

/// Khajistan Transmission, the station page. It names the channels and what is on each, and
/// opens one of them full screen. A channel is tuned and the clock says what is on it: there is
/// no list of programmes to choose from and no scrub bar.
struct TransmissionView: View {
    @Environment(AppModel.self) private var model
    @State private var showSignIn = false
    /// The channel the viewer chose while signed out, and the one to open once the sign-in screen
    /// has closed. A cover cannot open over one that is still on its way down.
    @State private var chosen: Int?
    @State private var openAfterSignIn: Int?
    @State private var playing: ChannelChoice?
    @FocusState private var focusedCard: Int?

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
        // Down from the top bar lands on Channel 1, not on whichever card sits under the bar item.
        .defaultFocus($focusedCard, 1, priority: .userInitiated)
        .task {
            await store.loadSchedule()
            // A page left open as the month turns takes the new month's schedule. A schedule
            // held for the current month answers at once, so this costs nothing most of the time.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if store.schedule == .ready { await store.loadSchedule() }
            }
        }
        // Full screen on the ground, as in Account: a sheet is a shadowed card.
        .kjFullScreenCover(isPresented: $showSignIn, onDismiss: { openChosen() }) {
            SignInView(onSignedIn: { openAfterSignIn = chosen })
        }
        .kjFullScreenCover(item: $playing) { choice in
            TransmissionPlayerView(channel: choice.number)
        }
        // A Top Shelf link: the station page, or one channel tuned from it.
        .task(id: model.link) {
            switch model.link {
            case .transmission:
                model.link = nil
            case .channel(let number):
                // Only a channel the schedule names opens; any other number stays on this page.
                // The link is cleared first, so it cannot replay on a later visit. Clearing it
                // restarts this task, but the fetch runs in the store's own Task, which that
                // cancellation does not reach.
                model.link = nil
                await store.loadSchedule()
                // Full screen from picture in picture that cannot open the player here (not on
                // the schedule, or signed out) stops the channel, rather than leave it sounding
                // under a page with no way to stop it.
                let opens = store.channelNumbers.contains(number) && (model.auth.isSignedIn || store.isScheduleFile)
                if model.transmissionPiP != nil, !opens { model.silenceRadio() }
                if store.channelNumbers.contains(number) {
                    choose(number)
                }
            default:
                break
            }
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
        }
    }

    private var metaText: String {
        let channels = store.channelNumbers.count
        let tail = "\(channels) scheduled \(channels == 1 ? "channel" : "channels") \u{00B7} Pakistan time (UTC+5)"
        guard case .ready = store.schedule, let count = store.programmeCount else { return tail }
        let hours = store.programmeHours.map { "\($0.formatted()) hours \u{00B7} " } ?? ""
        return "\(count.formatted()) \(count == 1 ? "programme" : "programmes") \u{00B7} \(hours)\(tail)"
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
                // The page's state for the UI tests; nothing on screen.
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isStaticText)
                    .transmissionState("Preview password")
                PreviewLock(about: "Khajistan's own TV channels, on the air all day.", message: message) {
                    await store.loadSchedule()
                }
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
                // A TV guide: one row per channel, what is on now and its hours. The rows read the
                // clock; slots start on the minute, so they are drawn again on every minute and
                // "now" is never the slot that has just ended.
                TimelineView(.everyMinute) { context in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.channelNumbers, id: \.self) { number in
                            row(number, at: TransmissionStore.now(context.date))
                        }
                    }
                    // The rows' plates run past the column by their padding, as a list's do.
                    .padding(.horizontal, -ScheduleRow.padding.leading)
                }
                if !model.auth.isSignedIn && !store.isScheduleFile {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Sign in to watch Khajistan Transmission.")
                            .kjBody()
                        Button("Sign in") {
                            chosen = nil
                            showSignIn = true
                        }
                        .buttonStyle(HouseButtonStyle())
                        .padding(.leading, -26)
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
        .padding(.leading, -26)
    }

    private func row(_ number: Int, at date: Date) -> some View {
        Button {
            choose(number)
        } label: {
            ScheduleRow(
                number: number,
                // The schedule names a channel "Channel 1 · Bioscope"; the row prints the number
                // in its own column, so the name is the part after it.
                name: Self.shortName(store.channelName(number), number: number),
                onAir: store.nowOn(channel: number, at: date),
                returns: store.returnLabel(channel: number, at: date),
                back: store.returnStrip(channel: number, at: date)
            )
        }
        .onPlayPauseCommand { choose(number) }
        .buttonStyle(HouseButtonStyle(padding: ScheduleRow.padding))
        .focused($focusedCard, equals: number)
        .accessibilityIdentifier("transmission-channel-\(number)")
    }

    static func shortName(_ name: String, number: Int) -> String {
        let prefix = "Channel \(number) \u{00B7} "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    // MARK: - Choosing

    /// A signed-in viewer opens the channel. A signed-out one signs in first, and the channel
    /// opens when the sign-in screen has closed.
    private func choose(_ number: Int) {
        if model.auth.isSignedIn || store.isScheduleFile {
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

}

/// One channel's row in the guide, read left to right as a printed TV guide: the channel's number
/// and name, the hours of what is on, and the show. Off air, when it is back and with what. Show
/// names only: programme titles are file names (owner, 2026-09-06). Nothing about later: the row
/// is what is on now (owner, 2026-11-19: "removing up next from the cards and making it more like
/// a simple tv guide"). It sits inside a button's plate, so its colours come from the palette the
/// plate sets for it.
private struct ScheduleRow: View {
    static let padding = EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28)

    let number: Int
    let name: String
    let onAir: OnAir?
    /// When an off-air channel is back, the clock's label (StationClock.returnLabel), and the strip
    /// it comes back with.
    let returns: String?
    let back: ScheduleStrip?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 40) {
            Text("\(number)")
                .kjName(48)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            // The channel is a label and the programme the headline, so the two never read as
            // the same kind of thing (owner, 2026-11-19: "there needs to be a distinction between
            // name of channel in transmission and the program playing").
            Kicker(name)
                .lineLimit(1)
                .frame(width: 420, alignment: .leading)
            if let air = onAir {
                Text("\(air.startLabel)\u{2013}\(air.endLabel)")
                    .kjBody()
                    .monospacedDigit()
                    .frame(width: 210, alignment: .leading)
                Text(onNow(air))
                    .kjName()
                    .lineLimit(1)
            } else {
                Text("Off air")
                    .kjBody()
                    .foregroundStyle(palette.faint)
                    .frame(width: 210, alignment: .leading)
                if let returns {
                    Text(backLine(returns))
                        .kjBody()
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// What is on: the programme by its standardized name, as the player's strip heads it, else
    /// the show. Nothing when that is only the channel's own name again (a one-show channel), and
    /// nothing for a slot whose show the schedule has lost; the hours still show.
    private func onNow(_ air: OnAir) -> String {
        // The name with its Roman form after it, as the player's guide writes it (owner,
        // 2026-11-19: "all shows should show names in roman as well").
        let now = air.guideLine
        return now == name ? "" : now
    }

    /// "Channel 1, Bioscope, 18:00 to 18:15 Pakistan time, Ghunghat."
    private var spoken: String {
        var parts = ["Channel \(number)", name]
        if let air = onAir {
            parts.append("\(air.startLabel) to \(air.endLabel) Pakistan time")
            let now = onNow(air)
            if !now.isEmpty { parts.append(now) }
        } else {
            parts.append(returns.map { backLine($0) } ?? "Off air")
        }
        return parts.joined(separator: ", ")
    }

    /// The website's off-air line: "Back at 23:00 PKT with The Feature.", with the day once the
    /// channel is a day or more from coming back.
    private func backLine(_ returns: String) -> String {
        var text = "Back at \(returns)"
        if let show = back?.show?.name, !show.isEmpty { text += " with \(show)" }
        return text + "."
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
