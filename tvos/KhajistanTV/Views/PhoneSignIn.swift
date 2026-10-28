import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// "Sign in with your phone", the first thing SignInView shows (owner, 2026-10-27: "allow people
/// to sign in with their phone or with a qr code ... so they dont have to write in apple tv
/// everytime"). A QR for the archive's /activate page with the code in it, the code itself in large
/// type for a phone without a camera at hand, and how long it lasts. The TV asks every few seconds
/// whether a phone has approved it; when one has, it signs itself in. Email and password stay one
/// press away. Until the tv-sign-in function is live the panel steps aside for the password form.
struct PhoneSignInPanel: View {
    /// Runs once the session is stored.
    let signedIn: () async -> Void
    /// The viewer chose email and password, or phone sign-in is not available.
    let usePassword: (_ unavailable: Bool) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var phase: Phase = .asking
    @State private var attempt = 0
    @FocusState private var focused: Bool

    private enum Phase: Equatable {
        case asking
        case showing(TVSignIn.Start, until: Date)
        case expired
        case signingIn
        /// Said for a moment before the screen closes, so a TV signed in to an account that is not
        /// the viewer's own (approved from a photographed screen) is noticed.
        case signedIn(String)
        case failed(String)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 90) {
            qrPlate
            VStack(alignment: .leading, spacing: 22) {
                Text("Sign in with your phone")
                    .kjDisplay(KJType.headline, tracking: -0.055)
                    .accessibilityAddTraits(.isHeader)
                words
                HStack(spacing: 12) {
                    if phase == .expired || isFailed {
                        Button(kicker: "Get a new code") { attempt += 1 }
                            .buttonStyle(HouseButtonStyle(solid: true))
                            .accessibilityIdentifier("tvSignInNewCode")
                    }
                    Button(kicker: "Use email and password instead") { usePassword(false) }
                        .buttonStyle(HouseButtonStyle())
                        .focused($focused)
                        .accessibilityIdentifier("tvSignInUsePassword")
                }
                .padding(.leading, -26)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($focused, true)
        .task(id: attempt) { await run() }
    }

    private var isFailed: Bool { if case .failed = phase { return true } else { return false } }

    @ViewBuilder
    private var words: some View {
        switch phase {
        case .asking:
            Kicker("Asking for a code\u{2026}")
        case .showing(let start, let until):
            Text("Point your phone's camera at the code, or go to").kjBody()
            Text(Self.shortAddress(start.verification_uri)).kjName(40)
                .accessibilityIdentifier("tvSignInAddress")
            Text("and type").kjBody()
            Text(start.user_code)
                .font(.system(size: 96, weight: .black, design: .monospaced))
                .tracking(8)
                .accessibilityLabel("Code " + start.user_code.map(String.init).joined(separator: " "))
                .accessibilityIdentifier("tvSignInCode")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(until.timeIntervalSince(context.date)))
                Text("This code works for \(left / 60):\(String(format: "%02d", left % 60))").kjSmall(faint: true)
            }
        case .expired:
            Text("That code ran out. Get a new one, then scan it within ten minutes.").kjBody()
        case .signingIn:
            Kicker("Signing in\u{2026}")
        case .signedIn(let email):
            Text("Signed in as \(email)").kjName(40).accessibilityIdentifier("tvSignInDone")
        case .failed(let message):
            Text(message).kjBody().accessibilityIdentifier("tvSignInProblem")
        }
    }

    /// The QR, dark modules on a light plate in every skin, because phone cameras read an inverted
    /// QR badly: ink on the ground by day, and the ground's colour on an ink plate in Grove and
    /// Smut, where the ink is the light one. No white either way.
    @ViewBuilder
    private var qrPlate: some View {
        let day = model.skin == .day
        let dark = day ? palette.ink : palette.ground
        let light = day ? palette.ground : palette.ink
        ZStack {
            light
            if case .showing(let start, _) = phase, let grid = QRModules.grid(start.verification_uri_complete) {
                QRModulesView(grid: grid, colour: dark).padding(36)
                    .accessibilityLabel("QR code for the sign-in page")
                    .accessibilityIdentifier("tvSignInQR")
            } else {
                TuningLoader(nil, bird: 140)
            }
        }
        .frame(width: 520, height: 520)
    }

    // MARK: Asking

    private func run() async {
        phase = .asking
        #if DEBUG
        // `-kjsigninfixture YES`: a code to show without the tv-sign-in function, for the UI test
        // that photographs this screen. Nothing is asked and nothing can sign in.
        if UserDefaults.standard.bool(forKey: "kjsigninfixture") {
            let address = KJConfig.site.appendingPathComponent("activate").absoluteString
            phase = .showing(TVSignIn.Start(device_code: String(repeating: "x", count: 43), user_code: "QRT4-MXZ7",
                                            verification_uri: address, verification_uri_complete: address + "?code=QRT4-MXZ7",
                                            interval: 5, expires_in: 600),
                             until: Date().addingTimeInterval(600))
            return
        }
        #endif
        guard let (data, response) = try? await URLSession.shared.data(for: TVSignIn.startRequest()),
              (response as? HTTPURLResponse)?.statusCode == 200, let start = TVSignIn.start(from: data) else {
            // The function is not live yet, or the network is down: the password form, saying why.
            if !Task.isCancelled { usePassword(true) }
            return
        }
        let until = Date().addingTimeInterval(TimeInterval(start.expires_in))
        phase = .showing(start, until: until)
        var interval = max(start.interval, 2)
        while !Task.isCancelled, Date() < until {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            // A failed ask (the network, a server fault) is asked again at the next turn.
            guard let (data, response) = try? await URLSession.shared.data(for: TVSignIn.pollRequest(deviceCode: start.device_code)),
                  (response as? HTTPURLResponse)?.statusCode == 200, let answer = TVSignIn.poll(from: data) else { continue }
            switch answer {
            case .pending: continue
            case .slowDown: interval += 5
            case .expired:
                phase = .expired
                return
            case .approved(let tokenHash):
                phase = .signingIn
                do {
                    try await model.auth.signIn(tokenHash: tokenHash)
                    phase = .signedIn(model.auth.email ?? "your account")
                    try? await Task.sleep(for: .seconds(2.5))
                    await signedIn()
                } catch {
                    phase = .failed("The phone approved it, but signing in here did not finish. Get a new code and try again.")
                }
                return
            }
        }
        if !Task.isCancelled { phase = .expired }
    }

    /// "https://khajistan-archive.pages.dev/activate" → "khajistan-archive.pages.dev/activate".
    static func shortAddress(_ uri: String) -> String {
        guard let parts = URLComponents(string: uri), let host = parts.host else { return uri }
        return host + parts.path
    }
}

/// A QR code's modules, from Core Image's generator: row 0 is the top (checked against Apple's own
/// QR reader, 2026-10-27), and the generator's one-module margin is part of the grid.
enum QRModules {
    static func grid(_ text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let width = Int(image.extent.width), height = Int(image.extent.height)
        guard width > 0, width == height else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        CIContext().render(image, toBitmap: &pixels, rowBytes: width, bounds: image.extent, format: .L8, colorSpace: nil)
        return (0..<height).map { y in (0..<width).map { x in pixels[y * width + x] < 128 } }
    }
}

/// The modules drawn as squares in one colour, on whatever is under them.
struct QRModulesView: View {
    let grid: [[Bool]]
    let colour: Color

    var body: some View {
        Canvas { context, size in
            let count = CGFloat(grid.count)
            let side = floor(min(size.width, size.height) / count)
            let origin = CGPoint(x: (size.width - side * count) / 2, y: (size.height - side * count) / 2)
            var path = Path()
            for (y, row) in grid.enumerated() {
                for (x, dark) in row.enumerated() where dark {
                    path.addRect(CGRect(x: origin.x + CGFloat(x) * side, y: origin.y + CGFloat(y) * side, width: side, height: side))
                }
            }
            context.fill(path, with: .color(colour))
        }
    }
}
