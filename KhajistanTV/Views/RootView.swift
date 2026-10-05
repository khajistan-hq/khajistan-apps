import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Tab = .receiver
    @State private var startApplied = false

    var body: some View {
        let palette = Palette(model.skin)
        TabView(selection: $selected) {
            ReceiverView()
                .tabItem { Text("Receiver") }
                .tag(Tab.receiver)
            TransmissionView()
                .tabItem { Text("Khajistan TV") }
                .tag(Tab.transmission)
            AccountView()
                .tabItem { Text("Account") }
                .tag(Tab.account)
        }
        .tint(palette.ink)
        .foregroundStyle(palette.ink)
        .background(palette.ground.ignoresSafeArea())
        .preferredColorScheme(model.skin == .day ? .light : .dark)
        .task {
            // The start tab is applied once; later changes belong to the viewer.
            guard !startApplied else { return }
            startApplied = true
            selected = model.startTab
        }
    }
}
