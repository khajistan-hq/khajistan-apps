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
                // The website's name for the page, as on the phone: ACCOUNT over YOUR KHAJISTAN.
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Account")
                    Text("Your Khajistan")
                        .kjDisplay()
                        .accessibilityAddTraits(.isHeader)
                }
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
            Kicker("Your account")
            if model.auth.isSignedIn {
                let email = model.auth.email ?? ""
                Text(email.isEmpty ? "Signed in" : email).kjName()
                Button(kicker: "Sign out") {
                    Task { await model.auth.signOut() }
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
            } else {
                Text("Khajistan Transmission plays under your website account.").kjBody()
                Button(kicker: "Sign in") {
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
            return "Following the sun where you are: \(model.skin.label) now. Day in daylight, Smut at dawn and dusk, Grove at night."
        case .day, .grove, .smut:
            return "\(model.skinChoice.label), whatever the sun is doing."
        }
    }

    private var previewBlock: some View {
        let isSet = model.auth.previewPassword != nil
        return VStack(alignment: .leading, spacing: 20) {
            Kicker("Preview password")
            Text(isSet ? "Set on this device, for the Transmission schedule until launch." : "Not set. Khajistan Transmission asks for it until launch.")
                .kjSmall(faint: true)
            if editingPassword {
                HouseInputField("Password", text: draft, secure: true) {
                    SecureField("", text: $draft)
                }
                HStack(spacing: 24) {
                    Button(kicker: "Save") {
                        model.auth.setPreviewPassword(draft)
                        draft = ""
                        editingPassword = false
                    }
                    Button(kicker: "Cancel") {
                        draft = ""
                        editingPassword = false
                    }
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
            } else {
                HStack(spacing: 24) {
                    Button(kicker: isSet ? "Change" : "Set") {
                        editingPassword = true
                    }
                    if isSet {
                        Button(kicker: "Clear") {
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
                Text("Khajistan for Apple TV \(version)").kjSmall(faint: true)
            }
            Text("Khajistan carries each broadcaster's own signal and keeps no copy of it.")
                .kjSmall(faint: true)
        }
    }
}
