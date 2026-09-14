import SwiftUI

@main
struct KhajistanApp: App {
    @State private var model = AppModel()
    init() {
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(Brand.yellow)
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.iconColor = UIColor(Brand.green)
            layout.normal.titleTextAttributes = [.foregroundColor: UIColor(Brand.green)]
            layout.selected.iconColor = .black
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor.black]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().isTranslucent = false
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Brand.green)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(Brand.yellow)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .normal)
    }

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
