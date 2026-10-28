import SwiftUI

/// The five doors and the house bar under them. There is no system tab bar: its tint, its glass
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
            // What the Receiver is playing, under every other door: it keeps playing while you browse.
            if model.tab != .receiver, model.tuner.source != nil {
                NowPlayingBar()
            }
            HouseTabBar(current: model.tab) { tab in
                // At once, as the system tab bar switches: no fade between pages (owner, 2026-10-07).
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { model.tab = tab }
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
        .onChange(of: model.tab, initial: true) {
            mounted.insert(model.tab)
            // A field left focused behind another door would keep the keyboard over this one.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .fullScreenCover(isPresented: $model.isShowingBrowser) {
            BrowserView(model: model)
        }
        .fullScreenCover(isPresented: $model.isShowingChat) {
            ChatScreen()
                .environment(model)
                .environment(\.palette, palette)
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .preferredColorScheme(model.skin == .day ? .light : .dark)
        }
    }

    @ViewBuilder
    private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .rooms: RoomsView()
        case .receiver: ReceiverView()
        case .library: YoursView()
        case .search: SearchView()
        }
    }
}

/// The Receiver's signal, small, while another door is open: what is on, play or pause, off, and
/// a tap on the name goes back to the Receiver. One source plays at a time, so there is one bar.
struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    private var state: PlayerController.State {
        if case .transmission = model.tuner.source { return model.transmission.player.state }
        return model.tuner.controller.state
    }

    private var name: (title: String, detail: String) {
        switch model.tuner.source {
        case .live(let channel): return (channel.name, channel.mediaType.lowercased() == "radio" ? "Radio" : "Television")
        case .transmission(let number): return (model.transmission.channelName(number), "Khajistan Transmission")
        case nil: return ("", "")
        }
    }

    private var stateWord: String {
        switch state {
        case .playing: return "On air"
        case .tuning: return "Tuning\u{2026}"
        case .paused: return "Paused"
        case .failed: return "The signal stopped"
        case .idle: return "Standing by"
        }
    }

    private var symbol: String {
        switch model.tuner.source {
        case .live(let channel): return ChannelRow.symbol(channel.mediaType)
        case .transmission: return "dot.radiowaves.left.and.right"
        case nil: return "tv"
        }
    }

    /// Sonos's small player while you browse: a floating plate in the band's colour, the source's
    /// mark, what is on and its state, and play/pause and off as icons.
    var body: some View {
        let playing = state == .playing || state == .tuning
        HStack(spacing: 12) {
            Button {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { model.tab = .receiver }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.onBand.opacity(0.16))
                        .frame(width: 44, height: 44)
                        .overlay { Image(systemName: symbol).font(.system(size: 18, weight: .semibold)) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name.title).font(.system(.subheadline, weight: .bold)).lineLimit(1)
                        Text("\(name.detail) \u{00B7} \(stateWord)").font(.caption).opacity(0.85).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Receiver")
            .accessibilityIdentifier("nowPlayingName")
            Button { model.tuner.playPause() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 20, weight: .bold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
            .accessibilityIdentifier("nowPlayingToggle")
            Button { model.tuner.stop() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Turn the Receiver off")
            .accessibilityIdentifier("nowPlayingOff")
        }
        .foregroundStyle(palette.onBand)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(palette.band, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(palette.ground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nowPlaying")
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
                        // An icon over its name, as the system's tab bars are; the current one in the accent.
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol).font(.system(size: 21, weight: tab == current ? .bold : .regular))
                                .frame(height: 26)
                            Text(tab.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(tab == current ? palette.accent : palette.faint)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, minHeight: 49)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
