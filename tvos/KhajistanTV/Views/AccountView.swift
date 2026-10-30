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
                Button(kicker: "Sign in") {
                    showSignIn = true
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
            }
        }
    }

    /// One button, as on the website: it shows the skin on now and moves to the next,
    /// Day, Grove, Smut. Until it is pressed the skin follows the sun.
    private var skinBlock: some View {
        HStack(spacing: 20) {
            Kicker("Skin")
                .accessibilityIdentifier("skinState")
                .accessibilityValue(model.skin.rawValue)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    model.skinChoice = model.skin.next
                }
            } label: {
                SkinGlyph(skin: model.skin).frame(width: 44, height: 44)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)))
            .accessibilityIdentifier("skin-toggle")
            .accessibilityLabel("\(model.skin.label) skin. Switch to \(model.skin.next.label).")
        }
    }

    private var previewBlock: some View {
        let isSet = model.auth.previewPassword != nil
        return VStack(alignment: .leading, spacing: 20) {
            Kicker("Preview password")
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
        }
    }
}
/// The website's skin icons (kj-theme.js ICONS), drawn on the same 24-point grid: the sun with
/// rays for Day, the bare disc for Grove, the sun on the horizon for Smut.
struct SkinGlyph: View {
    let skin: Skin

    var body: some View {
        GlyphShape(skin: skin)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct GlyphShape: Shape {
    let skin: Skin

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
        }
        switch skin {
        case .day:
            p.addEllipse(in: CGRect(x: 12 - 4.6, y: 12 - 4.6, width: 9.2, height: 9.2))
            line(12, 1.6, 12, 4.6); line(12, 19.4, 12, 22.4); line(22.4, 12, 19.4, 12); line(4.6, 12, 1.6, 12)
            line(19.35, 4.65, 17.23, 6.77); line(6.77, 17.23, 4.65, 19.35)
            line(19.35, 19.35, 17.23, 17.23); line(6.77, 6.77, 4.65, 4.65)
        case .grove:
            p.addEllipse(in: CGRect(x: 12 - 7.2, y: 12 - 7.2, width: 14.4, height: 14.4))
        case .smut:
            p.addArc(center: CGPoint(x: 12, y: 18), radius: 5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            line(2, 18, 22, 18)
            line(12, 3, 12, 6); line(4.9, 9.9, 6.4, 11.4); line(19.1, 9.9, 17.6, 11.4)
        }
        let k = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(scaleX: k, y: k).translatedBy(x: rect.minX / k, y: rect.minY / k))
    }
}
