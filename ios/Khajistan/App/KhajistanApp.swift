import SwiftUI

@main
struct KhajistanApp: App {
    @State private var model: AppModel = {
        #if DEBUG && KJ_NAVIGATION_FIXTURE
        // The separately identified UI fixture launches through the native app controller,
        // which cannot supply arguments. Never read real auth or start a signal in this build.
        UserDefaults.standard.register(defaults: ["kjtestsignedout": true, "kjautoplay": false, "kjreceiverautoplay": false, "kjtab": "rooms"])
        #endif
        return AppModel()
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // Supply the model above presentation boundaries, including native sheets.
                .environment(model)
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
                    if phase == .background { model.tuner.appLeftTheScreen() }
                }
        }
        #if targetEnvironment(macCatalyst)
        .commands {
            CommandMenu("Khajistan") {
                ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.title) { model.selectTab(tab) }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                        .disabled(!model.menuNavigationLocks.isEmpty)
                }
                Divider()
                ForEach(ArchiveDestination.doorsInThisBuild.filter { $0.door != "HOME" }, id: \.door) { door in
                    Menu(door.door) {
                        ForEach(door.rooms) { destination in
                            Button(destination.title) { model.open(destination) }
                                .disabled(!model.menuNavigationLocks.isEmpty)
                        }
                    }
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { model.selectTab(.search) }.keyboardShortcut("f")
                    .disabled(!model.menuNavigationLocks.isEmpty)
            }
        }
        #endif
    }
}
