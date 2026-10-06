import SwiftUI
import WebKit
import Observation

@MainActor @Observable
final class ArchiveBrowser: NSObject {
    let webView: WKWebView
    var title = "Khajistan"
    var url: URL?
    var isLoading = false
    var progress = 0.0
    var canGoBack = false
    var canGoForward = false
    var error: String?
    var downloadMessage: String?
    var activeDownloads = 0
    var onVisit: ((URL, String) -> Void)?
    /// The page on screen is the last one opened, not the one asked for: drawn as the ground
    /// until the new page commits, so the old page never flashes up.
    var isStale = false
    /// A JavaScript alert, confirm or prompt from the page, drawn in the house style.
    var dialog: WebDialog?
    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var requestedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.applicationNameForUserAgent = "Khajistan-iOS/1.0"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.refreshControl = UIRefreshControl()
        webView.scrollView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.sync() } }
        ]
    }

    func load(_ url: URL) {
        requestedURL = url
        error = nil
        if webView.url != url { isStale = true }
        webView.load(URLRequest(url: url))
    }

    /// Starts WebKit's page process at launch, so the first page opened does not wait for it.
    func warm() {
        webView.loadHTMLString("", baseURL: nil)
    }

    /// The website's skin keys, written before any of its scripts run, on every page.
    func applySkin(script: String) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    @objc func refresh() {
        error = nil
        if webView.url != nil { webView.reload() }
        else if let requestedURL { load(requestedURL) }
    }
    private func sync() {
        title = webView.title?.isEmpty == false ? webView.title! : "Khajistan"
        url = webView.url; isLoading = webView.isLoading; progress = webView.estimatedProgress
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
        if !isLoading { webView.scrollView.refreshControl?.endRefreshing() }
    }
    private func fail(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        error = failure.localizedDescription
        isStale = false
        webView.scrollView.refreshControl?.endRefreshing()
        sync()
    }
    private func external(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            if !opened { Task { @MainActor in self?.error = "This device could not open that link." } }
        }
    }
}

extension ArchiveBrowser: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { isStale = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        if let url = webView.url { onVisit?(url, title) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "This page stopped responding. Reload to continue." }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if action.shouldPerformDownload, ["https", "blob"].contains(scheme) { decisionHandler(.download); return }
        // Subframes belong to the site's CSP. Top-level custom schemes never execute in WebKit.
        if action.targetFrame?.isMainFrame == false, ["https", "http", "about", "blob"].contains(scheme) {
            decisionHandler(.allow); return
        }
        if ArchiveURL.isArchive(url) || scheme == "blob" || url.absoluteString == "about:blank" {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if ["https", "http", "mailto", "tel"].contains(scheme) { external(url) }
        else { error = "This type of link cannot be opened here." }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            error = "The archive returned an error (\(http.statusCode)). Try reloading this page."
        }
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
}

extension ArchiveBrowser: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url else { return nil }
        if ArchiveURL.isArchive(url) || url.scheme == "blob" { webView.load(action.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialog?.cancel()
        dialog = WebDialog(message: message, kind: .alert, answer: { _ in completionHandler() })
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialog?.cancel()
        dialog = WebDialog(message: message, kind: .confirm, answer: { completionHandler($0 != nil) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        dialog?.cancel()
        dialog = WebDialog(message: prompt, kind: .prompt(defaultText ?? ""), answer: completionHandler)
    }
}

/// A page's alert, confirm or prompt. WebKit waits for exactly one answer: `answer` gives it, and
/// a dialog replaced or abandoned is answered as cancelled.
@MainActor
final class WebDialog: Identifiable {
    enum Kind { case alert, confirm, prompt(String) }
    let id = UUID()
    let message: String
    let kind: Kind
    private var reply: ((String?) -> Void)?

    init(message: String, kind: Kind, answer: @escaping (String?) -> Void) {
        self.message = message
        self.kind = kind
        reply = answer
    }

    /// OK carries the entered text (or "" where there is none); nil is Cancel.
    func answer(_ value: String?) {
        reply?(value)
        reply = nil
    }

    func cancel() { answer(nil) }
}

extension ArchiveBrowser: WKDownloadDelegate {
    static var downloadDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do {
            // Keep a partial file outside the visible library until WebKit reports completion.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KhajistanDownloads/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(DownloadName.safe(suggestedFilename))
            downloads[ObjectIdentifier(download)] = target
            activeDownloads = downloads.count
            completionHandler(target)
        } catch { downloadMessage = "Could not start download: \(error.localizedDescription)"; completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let temporary = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        activeDownloads = downloads.count
        do {
            try FileManager.default.createDirectory(at: Self.downloadDirectory, withIntermediateDirectories: true)
            var target = Self.downloadDirectory.appendingPathComponent(temporary.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                target = Self.downloadDirectory.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(temporary.lastPathComponent)")
            }
            try FileManager.default.moveItem(at: temporary, to: target)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try target.setResourceValues(values)
            downloadMessage = "Saved \(target.lastPathComponent) to Library → Files."
        } catch { downloadMessage = "Could not save download: \(error.localizedDescription)" }
        try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let temporary = downloads.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
        }
        activeDownloads = downloads.count
        downloadMessage = "Download failed: \(error.localizedDescription). Return to the page to try again."
    }
}
