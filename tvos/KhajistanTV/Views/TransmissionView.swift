import SwiftUI

/// Khajistan Transmission. Selecting the tab plays a channel at once, full screen: the guide in the
/// player is how a viewer picks another (owner, 2026-11-28: "transmission should start the stream
/// of channels not showing the page, the guide will do that work"). The first channel is the last
/// one watched, else the lowest-numbered channel on air with a picture. What is left here is the
/// screen under the player: loading, the preview password, a schedule not published or not loaded,
/// sign-in, and a Watch button for a viewer who came back from the player.
struct TransmissionView: View {
    @Environment(AppModel.self) private var model
    @State private var showSignIn = false
    /// The channel the viewer chose while signed out, and the one to open once the sign-in screen
    /// has closed. A cover cannot open over one that is still on its way down.
    @State private var chosen: Int?
    @State private var openAfterSignIn: Int?
    @State private var playing: ChannelChoice?
    /// This visit to the tab has started a channel already: Back from the player stays here.
    @State private var started = false
    /// The last channel watched, kept on the device.
    static let lastChannelKey = "kj.transmission.lastChannel"

    private struct ChannelChoice: Identifiable {
        let number: Int
        var id: Int { number }
    }

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text("Khajistan Transmission")
                .kjDisplay()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("transmissionTitle")
            scheduleBlock
        }
        // Buttons take the platform's text style unless told otherwise; the house scale decides.
        .kjBody()
        .padding(KJLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await store.loadSchedule()
            startOnce()
            // A page left open as the month turns takes the new month's schedule. A schedule
            // held for the current month answers at once, so this costs nothing most of the time.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if store.schedule == .ready { await store.loadSchedule() }
            }
        }
        .onChange(of: store.schedule == .ready) { _, ready in if ready { startOnce() } }
        // The channel the viewer leaves the player on is the one the tab opens next time.
        .onChange(of: playing == nil) { _, closed in
            if closed { UserDefaults.standard.set(store.channelNumber, forKey: Self.lastChannelKey) }
        }
        // Full screen on the ground, as in Account: a sheet is a shadowed card.
        .kjFullScreenCover(isPresented: $showSignIn, onDismiss: { openChosen() }) {
            SignInView(onSignedIn: { openAfterSignIn = chosen })
        }
        .kjFullScreenCover(item: $playing) { choice in
            TransmissionPlayerView(channel: choice.number)
        }
        // A Top Shelf link: the station page, or one channel tuned from it. Held while the welcome
        // is still going, so the player's cover is not presented under it and dropped.
        .task(id: HeldLink(link: model.link, held: model.welcomeOnScreen)) {
            guard !model.welcomeOnScreen else { return }
            switch model.link {
            case .transmission:
                model.link = nil
                // The station link plays, even after Back on this visit.
                started = false
                startOnce()
            case .channel(let number):
                started = true
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
                // The welcome has gone: the tab plays, as a press on it does.
                startOnce()
            }
        }
    }

    // MARK: - The page

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
            // Under the player: the counts and the channels are in the player's guide now. One
            // Watch, which Back from the player does not light: focus goes back to the top bar.
            VStack(alignment: .leading, spacing: 24) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isStaticText)
                    .transmissionState("Ready")
                if !model.auth.isSignedIn && !store.isScheduleFile {
                    Text("Sign in to watch Khajistan Transmission.")
                        .kjBody()
                    Button("Sign in") {
                        chosen = nil
                        showSignIn = true
                    }
                    .buttonStyle(HouseButtonStyle())
                    .padding(.leading, -26)
                } else {
                    Button("Watch") {
                        if let number = firstChannel() { choose(number) }
                    }
                    .buttonStyle(HouseButtonStyle())
                    .padding(.leading, -26)
                    .accessibilityIdentifier("transmissionWatch")
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

    static func shortName(_ name: String, number: Int) -> String {
        let prefix = "Channel \(number) \u{00B7} "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    // MARK: - Choosing

    /// The tab's first press plays a channel, once a visit, when nothing else is opening one.
    private func startOnce() {
        // Signed out, the screen's Sign in is the way on; a sign-in sheet is not thrown up unasked.
        guard !started, case .ready = store.schedule, playing == nil, !showSignIn,
              model.auth.isSignedIn || store.isScheduleFile,
              !model.welcomeOnScreen, model.link == nil, let number = firstChannel() else { return }
        started = true
        choose(number)
    }

    /// The last channel watched, if the schedule still has it; else the lowest-numbered channel on
    /// air now that has a picture (Channel 1, After Hours, is sound only); else the first channel.
    private func firstChannel() -> Int? {
        // In number order: the schedule lists its channels in lineup order, not by number.
        let numbers = store.channelNumbers.sorted()
        let last = UserDefaults.standard.integer(forKey: Self.lastChannelKey)
        if numbers.contains(last) { return last }
        let now = TransmissionStore.now(Date())
        return numbers.first { number in
            guard let air = store.nowOn(channel: number, at: now) else { return false }
            return air.programme?.audio_only != true
        } ?? numbers.first
    }

    /// A signed-in viewer opens the channel. A signed-out one signs in first, and the channel
    /// opens when the sign-in screen has closed.
    private func choose(_ number: Int) {
        // Any way in (the tab, Watch, a link) counts as this visit's start.
        started = true
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

private extension View {
    /// The page's state, as the accessibility value of its state line. The UI tests read it and it
    /// is never drawn.
    func transmissionState(_ marker: String) -> some View {
        accessibilityIdentifier("transmissionState")
            .accessibilityValue(marker)
    }
}

/// A link and whether it must wait (the welcome still on screen), so the link's task runs again
/// when the welcome has gone.
private struct HeldLink: Equatable {
    let link: DeepLink?
    let held: Bool
}
