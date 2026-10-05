import SwiftUI

/// The top bar over one of the root screens. There is no TabView: tvOS paints a focused tab
/// as a white pill, and the house allows no white.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = Palette(model.skin)
        VStack(spacing: 0) {
            TopBar(current: model.section, select: { model.section = $0 })
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
        }
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        // The colour scheme steers what tvOS draws itself, the text fields and the keyboard.
        .preferredColorScheme(model.skin == .day ? .light : .dark)
        // Back (Menu) on any other section returns to the atlas (owner, 2026-10-05: "make sure
        // it's easy to go back to home on Apple TV where the atlas is"). On the Receiver it does
        // what tvOS does: a region pops back to the map, and the map leaves the app.
        .modifier(BackToAtlas(active: model.section != .receiver) { model.section = .receiver })
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .receiver: ReceiverView()
        case .transmission: TransmissionView()
        case .picsvids: PicsVidsView()
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
