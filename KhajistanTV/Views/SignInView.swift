import SwiftUI

/// Email and password, for Khajistan TV. `onSignedIn` runs after the session is stored and
/// before the sheet closes.
struct SignInView: View {
    let onSignedIn: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorLine: String?

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 32) {
                Text("Khajistan account")
                    .font(KJFont.title())
                Text("The email and password you use on the website.")
                    .font(KJFont.body())
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button("Sign in") {
                    Task { await submit() }
                }
                .buttonStyle(PlateButtonStyle(palette: palette))
                .frame(maxWidth: 500, alignment: .leading)
                .disabled(email.isEmpty || password.isEmpty || busy)
                if let line = errorLine {
                    Text(line)
                        .font(KJFont.body())
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(80)
        }
        .foregroundStyle(palette.ink)
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
        case .anonymous: return "This account cannot watch Khajistan TV."
        default: return "Sign-in failed."
        }
    }
}
