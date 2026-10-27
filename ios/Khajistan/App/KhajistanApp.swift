import SwiftUI

@main
struct KhajistanApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                #if targetEnvironment(macCatalyst)
                .onAppear { DesktopSupport.configureWindows() }
                #endif
                .onOpenURL { url in
                    if let destination = ArchiveURL.deepLink(url) { model.open(destination) }
                    else { model.message = "This link is not a Khajistan archive page." }
                }
                // Back from the lock screen or another app: the sky may have moved.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { withAnimation(.easeInOut(duration: 0.4)) { model.refreshSkin() } }
                }
        }
        #if targetEnvironment(macCatalyst)
        .commands {
            CommandMenu("Khajistan") {
                ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.title) { model.tab = tab }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { model.tab = .search }.keyboardShortcut("f")
            }
        }
        #endif
    }
}
