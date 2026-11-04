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

    private func screens(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            TopBar(current: model.section, select: { model.section = $0 })
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
            // The radio left playing, under every section (owner gap: "while browsing other tabs"),
            // until it is turned off. A full-screen page over a section covers it; Menu brings it back.
            if let away = model.radioAway {
                RadioBar(away: away) {
                    model.silenceRadio()
                    reopened = away
                }
            }
        }
        .fullScreenCover(item: $reopened) { away in
            ReceiverPlayerView(channel: away.channel, list: away.list, surfChoice: away.surfChoice)
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
        .onChange(of: model.section) { old, _ in
            if goingBack { goingBack = false } else { visited.append(old) }
        }
        .modifier(BackToAtlas(active: model.section != .receiver || !model.receiverPath.isEmpty || !visited.isEmpty) {
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
        case .receiver: ReceiverView()
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

    func body(content: Content) -> some View {
        if active {
            content.onExitCommand(perform: back)
        } else {
            content
        }
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
