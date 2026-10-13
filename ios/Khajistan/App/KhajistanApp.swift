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
                Button("Home") { model.tab = .home }.keyboardShortcut("1")
                Button("Receiver") { model.tab = .receiver }.keyboardShortcut("2")
                if AppTab.available.contains(.picsVids) {
                    Button("Pics/Vids") { model.tab = .picsVids }.keyboardShortcut("3")
                }
                Button("Account") { model.tab = .yours }.keyboardShortcut("4")
            }
        }
        #endif
    }
}
