import SwiftUI
import WebKit

struct ArchiveWebView: UIViewRepresentable {
    let browser: ArchiveBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var browser = model.browser
        NavigationStack {
            VStack(spacing: 0) {
                if browser.isLoading { ProgressView(value: browser.progress).tint(Brand.green).accessibilityLabel("Page loading") }
                if let error = browser.error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text("Page unavailable").font(.title2.bold())
                        Text(error).multilineTextAlignment(.center)
                        Button("Try again") { browser.refresh() }.buttonStyle(ArchiveButtonStyle())
                    }.padding(24)
                }
                ArchiveWebView(browser: browser).accessibilityIdentifier("archiveWebView")
                HStack {
                    Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(!browser.canGoBack).accessibilityLabel("Back")
                    Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(!browser.canGoForward).accessibilityLabel("Forward")
                    Spacer()
                    if browser.activeDownloads > 0 { ProgressView().accessibilityLabel("Downloading \(browser.activeDownloads) files") }
                    Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload")
                    if let url = browser.url, ArchiveURL.isSaveable(url) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Share page")
                    }
                }.padding(.horizontal, 12).background(Brand.yellow).overlay(alignment: .top) { Rectangle().fill(.black).frame(height: 1) }
            }
            .background(Brand.yellow).foregroundStyle(.black)
            .navigationTitle(browser.title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.yellow, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() }.accessibilityIdentifier("closeBrowser") }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = browser.url, ArchiveURL.isSaveable(url) {
                        let saved = model.library.bookmarks.contains { $0.url == url }
                        Button { model.toggleSaved(url, title: browser.title) } label: { Image(systemName: saved ? "bookmark.fill" : "bookmark") }
                            .accessibilityLabel(saved ? "Remove saved page" : "Save page")
                    }
                }
            }
            .alert("Download", isPresented: Binding(get: { browser.downloadMessage != nil }, set: { if !$0 { browser.downloadMessage = nil } })) {
                Button("OK") { browser.downloadMessage = nil }
            } message: { Text(browser.downloadMessage ?? "") }
            .onAppear { browser.webView.setAllMediaPlaybackSuspended(false) }
            .onDisappear { browser.webView.setAllMediaPlaybackSuspended(true) }
        }
    }
}
