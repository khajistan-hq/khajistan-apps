import SwiftUI

@main
struct KhajistanApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Brand.green)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    if let destination = ArchiveURL.deepLink(url) { model.open(destination) }
                    else { model.message = "This link is not a Khajistan archive page." }
                }
        }
    }
}
