import SwiftUI
import UIKit

/// Email and password, for Khajistan Transmission. `onSignedIn` runs after the session is stored
/// and before the screen closes. Menu goes back without signing in.
struct SignInView: View {
    let onSignedIn: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorLine: String?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 32) {
                Text("Khajistan account")
                    .kjDisplay(KJType.headline, tracking: -0.055)
                Text("The email and password you use on the website.")
                    .kjBody()
                HouseInputField("Email", text: email) {
                    // username + password is the pair AutoFill looks for: an iPhone offering
                    // the Apple TV keyboard can then fill the saved Khajistan login.
                    TextField("", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HouseInputField("Password", text: password, secure: true) {
                    SecureField("", text: $password)
                        .textContentType(.password)
                }
                // Always focusable: a dimmed button that focus skipped gave no reason. A press with
                // a field empty says which.
                Button("Sign in") {
                    if email.isEmpty || password.isEmpty {
                        errorLine = email.isEmpty ? "Type the email first." : "Type the password first."
                    } else {
                        Task { await submit() }
                    }
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
                .disabled(busy)
                if let line = errorLine {
                    Text(line).kjBody()
                }
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(palette.ink)
        .onChange(of: errorLine) { _, line in
            if let line { UIAccessibility.post(notification: .announcement, argument: line) }
        }
        .onExitCommand { dismiss() }
        // The colour scheme steers what tvOS draws itself: the keyboard this screen brings up.
        .preferredColorScheme(model.skin == .day ? .light : .dark)
    }

    private func submit() async {
        busy = true
        errorLine = nil
        do {
            try await model.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            await onSignedIn()
            dismiss()
        } catch {
            errorLine = message(for: error)
        }
        busy = false
    }

    private func message(for error: Error) -> String {
        guard let failure = error as? AuthError else { return error.localizedDescription }
        switch failure {
        case .server(let text): return text
        case .anonymous: return "This account cannot watch Khajistan Transmission."
        default: return "Sign-in failed. Check the email and password and try again."
        }
    }
}

/// The house text field, used wherever the app asks for text: the label as a kicker, the entry in
/// body type, and one 2pt rule under it. The rule is the only border the house allows, because a
/// viewer must see where to aim. Focus is the band plate, as on a button.
struct HouseInputField<Entry: View>: View {
    let label: String
    private let shown: String
    private let entry: Entry
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    /// `entry` is the TextField or SecureField itself, with its own title left empty: the kicker is
    /// the label, and a title would print as a second one inside the field. `text` is what it
    /// holds, drawn by this view; `secure` draws it as bullets.
    init(_ label: String, text: String, secure: Bool = false, @ViewBuilder entry: () -> Entry) {
        self.label = label
        self.shown = secure ? String(repeating: "\u{2022}", count: text.count) : text
        self.entry = entry()
    }

    var body: some View {
        let ink = isFocused ? palette.onFocus : palette.ink
        VStack(alignment: .leading, spacing: 10) {
            Kicker(label, color: isFocused ? palette.onFocus : nil)
                .accessibilityHidden(true)
            // tvOS draws the field as a pill that turns white under focus, and neither the focus
            // effect nor UITextField's appearance takes it away. So the field is kept, focusable
            // and selectable, nearly transparent (UIKit stops focusing a view below 0.01) and
            // covered, and its text is drawn over it in the house ink.
            entry
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .kjBody()
                .opacity(0.02)
                .focused($isFocused)
                .accessibilityLabel(label)
                .overlay(alignment: .leading) {
                    // Opaque, in the colour under it, so what is left of the pill does not show.
                    Text(shown)
                        .kjBody()
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(isFocused ? palette.focusPlate : palette.ground)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
            Rectangle()
                .fill(ink)
                .frame(height: 2)
        }
        .padding(EdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 26))
        .frame(maxWidth: 900, alignment: .leading)
        .background(isFocused ? palette.focusPlate : Color.clear)
        // The plate's padding is pulled back so the label and the entry sit on the page margin.
        .padding(.leading, -26)
    }
}
