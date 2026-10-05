import SwiftUI

/// Who is signed in, the preview password, and what this app is.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showSignIn = false
    @State private var editingPassword = false
    @State private var draft = ""

    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                Text("Account")
                    .kjDisplay()
                    .accessibilityAddTraits(.isHeader)
                signInBlock
                previewBlock
                footer
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: {})
        }
    }

    @ViewBuilder
    private var signInBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.auth.isSignedIn {
                let email = model.auth.email ?? ""
                Kicker(email.isEmpty ? "Signed in" : "Signed in as")
                if !email.isEmpty {
                    Text(email).kjName()
                }
                Button("Sign out") {
                    Task { await model.auth.signOut() }
                }
                .buttonStyle(HouseButtonStyle())
            } else {
                Kicker("Not signed in")
                Text("Khajistan Transmission needs an account.").kjBody()
                Button("Sign in") {
                    showSignIn = true
                }
                .buttonStyle(HouseButtonStyle())
            }
        }
    }

    private var previewBlock: some View {
        let isSet = model.auth.previewPassword != nil
        return VStack(alignment: .leading, spacing: 20) {
            Kicker("Preview password")
            Text(isSet ? "Set" : "Not set").kjBody()
            if editingPassword {
                HouseInputField("Password") {
                    SecureField("", text: $draft)
                }
                HStack(spacing: 24) {
                    Button("Save") {
                        model.auth.setPreviewPassword(draft)
                        draft = ""
                        editingPassword = false
                    }
                    Button("Cancel") {
                        draft = ""
                        editingPassword = false
                    }
                }
                .buttonStyle(HouseButtonStyle())
            } else {
                HStack(spacing: 24) {
                    Button("Change") {
                        editingPassword = true
                    }
                    if isSet {
                        Button("Clear") {
                            model.auth.clearPreviewPassword()
                        }
                    }
                }
                .buttonStyle(HouseButtonStyle())
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let version, !version.isEmpty {
                Text("Version \(version)").kjSmall(faint: true)
            }
            Text("Khajistan carries each broadcaster's own signal and keeps no copy of it.")
                .kjSmall(faint: true)
        }
    }
}
