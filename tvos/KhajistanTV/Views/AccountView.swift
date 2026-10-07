import SwiftUI

/// Who is signed in, the preview password, and what this app is.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showSignIn = false
    @State private var editingPassword = false
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                skinBlock
                previewBlock
                footer
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Full screen on the ground, not a sheet: tvOS draws a sheet as a rounded, shadowed
        // card over a dimmed page, and the house has no boxes and no shadows.
        .fullScreenCover(isPresented: $showSignIn) {
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
                .padding(.leading, -26)
            } else {
                Kicker("Not signed in")
                Text("Khajistan Transmission needs an account.").kjBody()
                Button("Sign in") {
                    showSignIn = true
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
            }
        }
    }

    /// The website's three skins, by their names on its switch, and Automatic, which follows
    /// the sun, as the website does. The choice is kept on this Apple TV.
    private var skinBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            Kicker("Skin")
                .accessibilityIdentifier("skinState")
                .accessibilityValue(model.skin.rawValue)
            HStack(spacing: 12) {
                ForEach(SkinChoice.allCases, id: \.self) { choice in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                            model.skinChoice = choice
                        }
                    } label: {
                        Text(choice.label).kjKicker()
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: model.skinChoice == choice))
                    .accessibilityIdentifier("skin-\(choice.rawValue)")
                }
            }
            // The tab's plate padding is pulled back so its text sits on the page margin.
            .padding(.leading, -22)
            Text(skinLine).kjSmall(faint: true)
        }
    }

    private var skinLine: String {
        switch model.skinChoice {
        case .automatic:
            return "Following the sun for this Apple TV\u{2019}s time zone: Day in daylight, Smut at dawn and dusk, Grove at night."
        case .day, .grove, .smut:
            return "\(model.skinChoice.label), whatever the sun is doing."
        }
    }

    private var previewBlock: some View {
        let isSet = model.auth.previewPassword != nil
        return VStack(alignment: .leading, spacing: 20) {
            Kicker("Preview password")
            Text(isSet ? "Set" : "Not set").kjBody()
            if editingPassword {
                HouseInputField("Password", text: draft, secure: true) {
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
                .padding(.leading, -26)
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
                .padding(.leading, -26)
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
