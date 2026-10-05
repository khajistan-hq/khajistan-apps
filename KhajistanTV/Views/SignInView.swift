import SwiftUI

/// Email and password, for Khajistan Transmission. `onSignedIn` runs after the session is stored
/// and before the sheet closes.
struct SignInView: View {
    let onSignedIn: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorLine: String?

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 32) {
                Text("Khajistan account")
                    .kjDisplay(KJType.headline, tracking: -0.055)
                Text("The email and password you use on the website.")
                    .kjBody()
                HouseInputField("Email") {
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                }
                HouseInputField("Password") {
                    SecureField("", text: $password)
                }
                Button("Sign in") {
                    Task { await submit() }
                }
                .buttonStyle(HouseButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
                if let line = errorLine {
                    Text(line).kjBody()
                }
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(palette.ink)
        // The colour scheme steers what tvOS draws itself: the keyboard this sheet brings up.
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
        default: return "Sign-in failed."
        }
    }
}

/// The house text field, used wherever the app asks for text: the label as a kicker, the entry in
/// body type, and one 2pt rule under it. The rule is the only border the house allows, because a
/// viewer must see where to aim. Focus is the band plate, as on a button.
struct HouseInputField<Entry: View>: View {
    let label: String
    private let entry: Entry
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    /// `entry` is the TextField or SecureField itself, with its own title left empty: the kicker is
    /// the label, and a title would print as a second one inside the field.
    init(_ label: String, @ViewBuilder entry: () -> Entry) {
        self.label = label
        self.entry = entry()
    }

    var body: some View {
        let ink = isFocused ? palette.onBand : palette.ink
        VStack(alignment: .leading, spacing: 10) {
            Kicker(label, color: isFocused ? palette.onBand : nil)
                .accessibilityHidden(true)
            entry
                .textFieldStyle(.plain)
                .kjBody()
                .foregroundStyle(ink)
                .padding(.vertical, 12)
                .focused($isFocused)
                .accessibilityLabel(label)
            Rectangle()
                .fill(ink)
                .frame(height: 2)
        }
        .padding(EdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 26))
        .frame(maxWidth: 900, alignment: .leading)
        .background(isFocused ? palette.band : Color.clear)
    }
}
