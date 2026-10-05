import SwiftUI

/// The top bar over one of the three root screens. There is no TabView: tvOS paints a focused tab
/// as a white pill, and the house allows no white.
struct RootView: View {
    @Environment(AppModel.self) private var model

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
        }
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        // The colour scheme steers what tvOS draws itself, the text fields and the keyboard.
        .preferredColorScheme(model.skin == .day ? .light : .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .receiver: ReceiverView()
        case .transmission: TransmissionView()
        case .account: AccountView()
        }
    }
}
