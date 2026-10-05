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
        let palette = Palette(model.skin)
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Account")
                        .font(KJFont.title())
                    signInBlock(palette)
                    previewBlock(palette)
                    VStack(alignment: .leading, spacing: 8) {
                        if let version, !version.isEmpty {
                            Text("Version \(version)")
                                .font(KJFont.caption())
                        }
                        Text("Khajistan carries each broadcaster's own signal and keeps no copy of it.")
                            .font(KJFont.caption())
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
        .foregroundStyle(palette.ink)
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: {})
        }
    }

    @ViewBuilder
    private func signInBlock(_ palette: Palette) -> some View {
        if model.auth.isSignedIn {
            if let email = model.auth.email, !email.isEmpty {
                Text(email)
                    .font(KJFont.body())
            }
            Button("Sign out") {
                Task { await model.auth.signOut() }
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
        } else {
            Button("Sign in") {
                showSignIn = true
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
        }
    }

    @ViewBuilder
    private func previewBlock(_ palette: Palette) -> some View {
        let isSet = model.auth.previewPassword != nil
        Text("Preview password")
            .font(KJFont.heading())
        Text(isSet ? "Set" : "Not set")
            .font(KJFont.body())
        if editingPassword {
            SecureField("Password", text: $draft)
            Button("Save") {
                model.auth.setPreviewPassword(draft)
                draft = ""
                editingPassword = false
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
            Button("Cancel") {
                draft = ""
                editingPassword = false
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
        } else {
            Button("Change") {
                editingPassword = true
            }
            .buttonStyle(PlateButtonStyle(palette: palette))
            .frame(maxWidth: 500, alignment: .leading)
            if isSet {
                Button("Clear") {
                    model.auth.clearPreviewPassword()
                }
                .buttonStyle(PlateButtonStyle(palette: palette))
                .frame(maxWidth: 500, alignment: .leading)
            }
        }
    }
}
