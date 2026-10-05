import SwiftUI
import WebKit

struct ArchiveWebView: UIViewRepresentable {
    let browser: ArchiveBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// The live website, in the house's own chrome: a bar with back, the page's name, share, save and
/// close, the load as a rule of accent across it, and the page's own alerts drawn as house panels.
/// The web view is one for the life of the app (ArchiveBrowser), so it opens warm.
struct BrowserView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var promptText = ""

    var body: some View {
        @Bindable var browser = model.browser
        let palette = Palette(model.skin)
        VStack(spacing: 0) {
            bar(browser, palette)
            ZStack {
                palette.ground
                ArchiveWebView(browser: browser)
                    .opacity(browser.isStale ? 0 : 1)
                    .accessibilityIdentifier("archiveWebView")
                if browser.isStale && browser.error == nil {
                    TuningLoader("Opening the page\u{2026}")
                }
                if let error = browser.error { failure(error, browser) }
            }
            .animation(.easeOut(duration: 0.2), value: browser.isStale)
        }
        .overlay(alignment: .top) {
            if let message = browser.downloadMessage {
                HouseBanner(text: message) { browser.downloadMessage = nil }.padding(.top, 52)
            }
        }
        .overlay(alignment: .bottom) {
            if let dialog = browser.dialog { dialogPanel(dialog, browser) }
        }
        .animation(.kj, value: browser.downloadMessage)
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .preferredColorScheme(model.skin == .day ? .light : .dark)
        .onAppear { browser.webView.setAllMediaPlaybackSuspended(false) }
        .onDisappear {
            browser.webView.setAllMediaPlaybackSuspended(true)
            browser.dialog?.cancel()
            browser.dialog = nil
        }
    }

    // MARK: - The bar

    private func bar(_ browser: ArchiveBrowser, _ palette: Palette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                icon("chevron.left", label: "Back", id: "browserBack") {
                    if browser.canGoBack { browser.webView.goBack() } else { dismiss() }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Kicker(browser.url.flatMap(Self.section) ?? "Khajistan")
                    Text(browser.title).kjName().lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("browserTitle")
                if let url = browser.url, ArchiveURL.isSaveable(url) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up").font(.system(.body, weight: .semibold)).frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Share page")
                    let saved = model.library.bookmarks.contains { $0.url == url }
                    icon(saved ? "bookmark.fill" : "bookmark", label: saved ? "Remove saved page" : "Save page", id: saved ? "Remove saved page" : "Save page") {
                        model.toggleSaved(url, title: browser.title)
                    }
                }
                icon("xmark", label: "Close", id: "closeBrowser") { dismiss() }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 52)
            // The load, as a rule of accent across the bar's foot; at rest the house rule.
            ZStack(alignment: .leading) {
                HouseRule()
                if browser.isLoading {
                    GeometryReader { proxy in
                        Rectangle().fill(palette.accent).frame(width: proxy.size.width * max(0.08, browser.progress), height: 2)
                    }
                    .frame(height: 2)
                    .transition(.opacity)
                }
            }
            .frame(height: 2)
            .animation(.easeOut(duration: 0.2), value: browser.progress)
            .accessibilityLabel(browser.isLoading ? "Page loading" : "")
        }
        .background(palette.ground)
    }

    private func icon(_ name: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(.body, weight: .semibold)).frame(width: 40, height: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// The door a page sits under, from the website's own menu, for the kicker above its name.
    private static func section(_ url: URL) -> String? {
        let path = url.path.lowercased()
        let match = ArchiveDestination.all
            .filter { $0.path != "/" && path.hasPrefix($0.path.lowercased().replacingOccurrences(of: ".html", with: "")) }
            .max { $0.path.count < $1.path.count }
        return match?.door
    }

    // MARK: - States

    private func failure(_ error: String, _ browser: ArchiveBrowser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Page unavailable").kjDisplay(KJType.headline, tracking: -0.04)
            Text(error).kjBody()
            Button(kicker: "Try again") { browser.refresh() }.buttonStyle(HouseButtonStyle(solid: true))
        }
        .padding(KJLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette(model.skin).ground)
    }

    private func dialogPanel(_ dialog: WebDialog, _ browser: ArchiveBrowser) -> some View {
        let finish: (String?) -> Void = { value in
            dialog.answer(value)
            browser.dialog = nil
            promptText = ""
        }
        var actions: [HouseDialog.Action] = []
        switch dialog.kind {
        case .alert:
            actions = [.init(title: "OK") { finish("") }]
        case .confirm:
            actions = [.init(title: "OK") { finish("") }, .init(title: "Cancel") { finish(nil) }]
        case .prompt:
            actions = [.init(title: "OK") { finish(promptText) }, .init(title: "Cancel") { finish(nil) }]
        }
        return VStack(spacing: 0) {
            if case .prompt(let initial) = dialog.kind {
                HouseInputField(dialog.message) { TextField("", text: $promptText) }
                    .padding(KJLayout.inset)
                    .background(Palette(model.skin).ground)
                    .onAppear { promptText = initial }
            }
            HouseDialog(text: dialog.message, actions: actions)
        }
    }
}
