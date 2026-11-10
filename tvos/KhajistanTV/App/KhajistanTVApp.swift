import SwiftUI

@main
struct KhajistanTVApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.open($0) }
                // Back on the screen: the device clock may have been set right while away.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.transmission.resyncClock() } }
                }
        }
    }
}
