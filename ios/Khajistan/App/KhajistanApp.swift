import SwiftUI

@main
struct KhajistanApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { url in
                    if let destination = ArchiveURL.deepLink(url) { model.open(destination) }
                    else { model.message = "This link is not a Khajistan archive page." }
                }
                // Back from the lock screen or another app: the sky may have moved.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { withAnimation(.easeInOut(duration: 0.4)) { model.refreshSkin() } }
                }
        }
    }
}
