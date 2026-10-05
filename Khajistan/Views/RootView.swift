import SwiftUI

/// The four doors and the house bar under them. There is no system tab bar: its tint, its glass
/// and its selection pill are not the house's. A door is mounted the first time it is opened and
/// then kept, so going back to it finds it where it was left.
struct RootView: View {
    @Bindable var model: AppModel
    @State private var mounted: Set<AppTab> = []

    var body: some View {
        let palette = Palette(model.skin)
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if mounted.contains(tab) || tab == model.tab {
                        page(tab)
                            .opacity(tab == model.tab ? 1 : 0)
                            .allowsHitTesting(tab == model.tab)
                            .accessibilityHidden(tab != model.tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The ground under the status bar, so a page scrolled up never shows behind the clock.
            .overlay(alignment: .top) {
                Color.clear.frame(height: 0).background(palette.ground, ignoresSafeAreaEdges: .top)
            }
            HouseTabBar(current: model.tab) { tab in
                withAnimation(.kj) { model.tab = tab }
            }
        }
        .overlay(alignment: .top) {
            if let message = model.message {
                HouseBanner(text: message) { withAnimation(.kj) { model.message = nil } }
            }
        }
        .animation(.kj, value: model.message)
        .background(palette.ground.ignoresSafeArea())
        .environment(model)
        .environment(\.palette, palette)
        // The system's grey scroll indicators are not drawn; spacing and the rules do the work.
        .scrollIndicators(.hidden)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        // What iOS draws itself (the status bar, the keyboard) follows the skin's lightness.
        .preferredColorScheme(model.skin == .day ? .light : .dark)
        .onChange(of: model.tab, initial: true) { mounted.insert(model.tab) }
        .fullScreenCover(isPresented: $model.isShowingBrowser) {
            BrowserView(model: model)
        }
    }

    @ViewBuilder
    private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .receiver: ReceiverView()
        case .picsVids: PicsVidsView()
        case .yours: YoursView()
        }
    }
}

/// The house bar: the doors as kickers, the current one in the accent with the rule under it, the
/// way the website marks the section you are in. One pixel of ink separates it from the page.
struct HouseTabBar: View {
    let current: AppTab
    let select: (AppTab) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HouseRule()
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        select(tab)
                    } label: {
                        Text(tab.title).kjKicker().lineLimit(1)
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: tab == current, padding: EdgeInsets(top: 14, leading: 6, bottom: 14, trailing: 6)))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
                    .accessibilityAddTraits(tab == current ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 6)
            // The bar holds its size, as the system's own does; a long press shows the name large.
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityShowsLargeContentViewer()
        }
        .background(palette.ground.ignoresSafeArea(edges: .bottom))
    }
}

/// A page title block: the kicker above (where it sits in the site), the title, and a line.
struct PageHead: View {
    let kicker: String?
    let title: String
    let line: String?

    init(kicker: String? = nil, _ title: String, line: String? = nil) {
        self.kicker = kicker
        self.title = title
        self.line = line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let kicker { Kicker(kicker) }
            Text(title).kjDisplay().accessibilityAddTraits(.isHeader)
            if let line { Text(line).kjBody() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
