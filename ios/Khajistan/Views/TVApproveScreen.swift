import SwiftUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// "Sign in on a TV": this phone approves the code the Apple TV shows, so the TV is signed in to
/// this account without typing on the remote (owner, 2026-10-27). Scan the TV's QR, or type the
/// code; the screen says what asked for the code and when before anything is approved.
struct TVApproveScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var typed = ""
    @State private var phase: Phase = .entering
    @State private var note: String?
    @State private var busy = false
    @State private var scanning = false

    private enum Phase: Equatable {
        case entering
        case confirming(code: String, label: String, asked: String, elsewhere: Bool)
        case done(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LargeTitle(title: "Sign in on a TV", line: nil)
                switch phase {
                case .entering: entering
                case .confirming(let code, let label, let asked, let elsewhere): confirming(code, label: label, asked: asked, elsewhere: elsewhere)
                case .done(let line):
                    Text(line).kjBody().accessibilityIdentifier("tvApproveDone")
                    Text("You can put your phone away.").kjSmall(faint: true)
                    Button(kicker: "Done") { dismiss() }.accessibilityIdentifier("tvApproveClose")
                }
                if let note { Text(note).kjSmall(faint: true).accessibilityIdentifier("tvApproveNote") }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $scanning) {
            QRScanner { text in
                scanning = false
                if let code = TVSignIn.code(fromScanned: text) {
                    typed = TVSignIn.display(code)
                    Task { await peek() }
                } else {
                    note = "That is not a Khajistan TV code."
                }
            } cancel: { scanning = false }
            .ignoresSafeArea()
        }
        #endif
    }

    @ViewBuilder
    private var entering: some View {
        Text("On the TV, choose Sign in. It shows a QR and a code: scan it, or type the code.").kjBody()
        if Self.canScan {
            Button { scanning = true } label: { Label("Scan the TV's code", systemImage: "qrcode.viewfinder") }
                .buttonStyle(SolidActionStyle())
                .accessibilityIdentifier("tvApproveScan")
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Code").kjKicker()
            TextField("XXXX-XXXX", text: $typed)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.continue)
                .onSubmit { Task { await peek() } }
                .accessibilityIdentifier("tvApproveCode")
            Rectangle().fill(palette.ink).frame(height: 2)
        }
        .padding(.top, 8)
        Button(kicker: busy ? "Looking\u{2026}" : "Continue") { Task { await peek() } }
            .disabled(busy)
            .accessibilityIdentifier("tvApproveContinue")
    }

    @ViewBuilder
    private func confirming(_ code: String, label: String, asked: String, elsewhere: Bool) -> some View {
        Text("\(label) asked for code \(TVSignIn.display(code)) \(asked).").kjBody().accessibilityIdentifier("tvApproveWhat")
        if elsewhere {
            Text("This TV is on a different network from your phone. If you did not just ask for this code on a TV in front of you, stop here.")
                .font(.system(.body, weight: .bold))
                .accessibilityIdentifier("tvApproveElsewhere")
        }
        Text("Only continue if this code is on your own screen right now. Anyone you approve can use your account on that TV.")
            .kjSmall(faint: true)
        Button { Task { await approve(code) } } label: { Label(busy ? "Signing in\u{2026}" : "Sign in the TV", systemImage: "tv") }
            .buttonStyle(SolidActionStyle())
            .disabled(busy)
            .accessibilityIdentifier("tvApproveConfirm")
        Button(kicker: "Not my TV") { phase = .entering; note = nil }
            .accessibilityIdentifier("tvApproveCancel")
    }

    // MARK: Asking

    private func peek() async {
        note = nil
        guard let code = TVSignIn.normalise(typed) else {
            note = "A code is eight letters and numbers, as the TV shows it."
            return
        }
        busy = true
        defer { busy = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtvapprovefixture") {
            phase = .confirming(code: code, label: "Apple TV", asked: "just now", elsewhere: false)
            return
        }
        #endif
        guard let token = try? await model.auth.validAccessToken(),
              let request = TVSignIn.peekRequest(code: code, accessToken: token) else {
            note = "Sign in on this phone first."
            return
        }
        let (data, status) = await send(request)
        guard status == 200, let pending = try? JSONDecoder().decode(TVSignIn.Pending.self, from: data) else {
            note = Self.refusal(status, data)
            return
        }
        phase = .confirming(code: code, label: pending.device_label ?? "A TV", asked: Self.ago(pending.created_at),
                            elsewhere: pending.same_network == false)
    }

    private func approve(_ code: String) async {
        note = nil
        busy = true
        defer { busy = false }
        let email = model.auth.email ?? "your account"
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "kjtvapprovefixture") {
            phase = .done("Apple TV is signing in as \(email).")
            return
        }
        #endif
        guard let token = try? await model.auth.validAccessToken(),
              let request = TVSignIn.approveRequest(code: code, accessToken: token) else {
            note = "Sign in on this phone first."
            return
        }
        let (data, status) = await send(request)
        guard status == 200 else {
            note = Self.refusal(status, data)
            phase = .entering
            return
        }
        let label = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["device_label"] as? String
        phase = .done("\(label ?? "The TV") is signing in as \(email).")
    }

    private func send(_ request: URLRequest) async -> (Data, Int) {
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return (Data(), 0) }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The function's refusals in plain words. A 404 from the platform itself (the function not
    /// deployed) is told apart from a code that is not waiting.
    static func refusal(_ status: Int, _ data: Data) -> String {
        let body = String(decoding: data, as: UTF8.self)
        switch status {
        case 404 where body.contains("Requested function"): return "Signing in on a TV is not available yet."
        case 404: return "That code is not waiting for a sign-in. Codes last ten minutes: check the TV, or ask it for a new one."
        case 401: return "Sign in on this phone again first."
        case 429: return "Too many tries. Wait a few minutes and try again."
        case 0: return "No connection. Try again."
        default: return "Something went wrong on our side. Try again."
        }
    }

    static func ago(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "a moment ago" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "just now" : "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    static var canScan: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }
}

#if !targetEnvironment(macCatalyst)
/// The camera, reading QR codes only, until it reads one.
private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void
    let cancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in cancel() })
        try? scanner.startScanning()
        return UINavigationController(rootViewController: scanner)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    found(text)
                    return
                }
            }
        }
    }
}
#endif
