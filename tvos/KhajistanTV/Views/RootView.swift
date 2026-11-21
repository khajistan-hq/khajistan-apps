import SwiftUI

/// The top bar over one of the root screens. There is no TabView: tvOS paints a focused tab
/// as a white pill, and the house allows no white.
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// The radio from the small player, opened full screen again.
    @State private var reopened: RadioAway?
    /// The sections visited before this one, so Back goes one step back (owner, 2026-11-04).
    @State private var visited: [Section] = []
    /// Set while Back changes the section, so the change is not recorded as a visit.
    @State private var goingBack = false
    /// The sections are laid out for the radio bar under them (`underRadioBar`). Set as the bar
    /// comes; once it has gone, cleared only when the viewer moves to another page.
    @State private var underBar = false

    var body: some View {
        let palette = Palette(model.skin)
        #if DEBUG
        if let check = SoundCheckView.requested {
            check
                .environment(\.palette, palette)
                .foregroundStyle(palette.ink)
        } else {
            screens(palette)
        }
        #else
        screens(palette)
        #endif
    }

    /// The welcome is seen: it does not come again on this device.
    private func closeWelcome() {
        UserDefaults.standard.set(true, forKey: Welcome.key)
        model.welcoming = false
    }

    /// A new page with no bar under it is laid out in full.
    private func leavePage() {
        if !model.radioBarUp { underBar = false }
    }

    private func screens(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            TopBar(current: model.section, select: { model.section = $0 })
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
                .environment(\.underRadioBar, underBar)
            // The radio left playing, under every section (owner gap: "while browsing other tabs"),
            // until it is turned off. A full-screen page over a section covers it; Menu brings it back.
            if model.radioBarUp, let away = model.radioAway {
                RadioBar(away: away) {
                    model.silenceRadio()
                    reopened = away
                }
            }
        }
        // The page keeps the bar's shape after the bar goes (Off, or a film or channel opened from
        // a shelf, which stops the radio behind its page) and takes its full shape on the next page.
        // Grown back in place it moved the card focus was on: behind a page, focus was lost when
        // the page closed; on screen, the card was pushed off the bottom (2026-11-20).
        // Set whenever the bar shows, even for a moment (a restore from picture-in-picture shows
        // it until the player opens): if that player cannot open, the bar stays and needs room.
        .onChange(of: model.radioBarUp, initial: true) { _, up in
            if up { underBar = true }
        }
        .onChange(of: model.section) { leavePage() }
        .onChange(of: model.receiverPath.map(\.id)) { leavePage() }
        // A new dial rebuilds the Receiver's front: a new page too. Only there: the dial also turns
        // when a player closes, over whatever section opened it.
        .onChange(of: model.receiver.dialID) { if model.section == .receiver { leavePage() } }
        // Full screen from the picture-in-picture window: the channel opens again, tuned afresh,
        // as a radio from the small player does.
        .onChange(of: model.restoring?.id) {
            guard let away = model.restoring else { return }
            model.restoring = nil
            // Not silenced here: the player that opens silences it as it starts. If a page's cover
            // is open and the screen cannot open over it, the channel plays on in the small bar
            // rather than stopping with nothing on screen.
            var bar = away
            bar.pip = nil
            model.radioAway = bar
            reopened = away
        }
        .fullScreenCover(isPresented: Binding(get: { model.welcoming }, set: { if !$0 { closeWelcome() } })) {
            WelcomeView(done: closeWelcome)
        }
        // A launch from the Top Shelf (khajistan://…) goes where it points: the welcome steps
        // aside for it rather than covering the channel it opens.
        // Not marked seen: a viewer whose first launch is a link still meets it on the next.
        .onChange(of: model.link == nil, initial: true) { _, none in if !none, model.welcoming { model.welcoming = false } }
        .fullScreenCover(item: $reopened) { away in
            ReceiverPlayerView(channel: away.channel, list: away.list, surfChoice: away.surfChoice,
                               regionId: away.listRegion, listTitle: away.listTitle)
        }
        .background(palette.ground.ignoresSafeArea())
        #if DEBUG
        .overlay(alignment: .topLeading) { KeepAwakeReadout() }
        .overlay(alignment: .bottomTrailing) {
            if UserDefaults.standard.bool(forKey: "kjframemeter") { FrameMeterLabel() }
        }
        // A loader held on screen, for the UI test that photographs the grooming pigeon.
        .overlay {
            if UserDefaults.standard.bool(forKey: "kjloaderpreview") {
                TuningLoader("Loading the receiver\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.ground.ignoresSafeArea())
            }
        }
        #endif
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        // The colour scheme steers what tvOS draws itself, the text fields and the keyboard. It
        // is set once on the window, which every cover inherits. `.preferredColorScheme` here was
        // handed down through each cover's hosting controller, and in Day (the light one) a cover
        // three deep that tvOS closed on Menu sent SwiftUI's layout round for ever under
        // accessibility, and the remote stopped answering.
        .onChange(of: model.skin, initial: true) { _, skin in
            let style: UIUserInterfaceStyle = skin == .day ? .light : .dark
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
            }
        }
        // Back (Menu) goes one step back (owner, 2026-11-04: "Back click goes one step back"): a
        // region pops back to the map, another section returns to the section visited before it,
        // and with nothing visited to the atlas (owner, 2026-10-05). The map with nothing behind it
        // leaves the app, as tvOS does. The pop is done here as well, because Back pressed in the
        // top bar never reaches the Receiver's stack.
        .onChange(of: model.section) { old, new in
            // The atlas is the root: reaching it, by Back or the top bar, ends the history.
            if new == .receiver { visited = [] } else if !goingBack { visited.append(old) }
            goingBack = false
        }
        // Play/Pause pauses or resumes the radio left playing under the screens, wherever focus
        // is, as Apple TV does with the audio playing. A focused card's own Play comes first.
        .onPlayPauseCommand(perform: model.radioAway == nil || model.radioAway?.pip != nil ? nil : {
            guard let away = model.radioAway else { return }
            if away.controller.state == .playing || away.controller.state == .tuning {
                away.controller.pause()
            } else {
                // Play tunes the station afresh, full screen, as the bar's own Play does.
                model.silenceRadio()
                reopened = away
            }
        })
        .modifier(BackToAtlas(active: model.section != .receiver || !model.receiverPath.isEmpty) {
            if model.section == .receiver, !model.receiverPath.isEmpty {
                model.receiverPath.removeLast()
            } else {
                goingBack = true
                model.section = visited.popLast() ?? .receiver
            }
        })
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        // Drawn afresh when the dial changes kind, so no shelf keeps the other dial's channels.
        case .receiver: ReceiverView().id(model.receiver.dialID)
        case .transmission: TransmissionView()
        case .reading: ReadingView()
        case .picsvids: PicsVidsView()
        case .rooms:
            if StoreBuild.roomsAreScreeningOnly { TVScreeningRoom() } else { RoomsTVView() }
        case .chat: ChatView()
        case .account: AccountView()
        }
    }
}

private struct BackToAtlas: ViewModifier {
    let active: Bool
    let back: () -> Void

    // Always attached, handing Back to tvOS (nil) when there is nothing to go back to. An if/else
    // here rebuilt the whole screen on every move to or from the Receiver, and the rebuild lost
    // the section change it happened on, so the history never recorded leaving the atlas.
    func body(content: Content) -> some View {
        content.onExitCommand(perform: active ? back : nil)
    }
}

#if DEBUG
/// For the UI tests: whether the app is holding the Apple TV awake (KeepAwake), read once a second.
struct KeepAwakeReadout: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(UIApplication.shared.isIdleTimerDisabled ? "on" : "off")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("keepAwake")
        }
        .allowsHitTesting(false)
    }
}
#endif
