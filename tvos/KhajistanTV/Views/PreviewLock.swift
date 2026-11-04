import SwiftUI

/// A room that is closed until launch, said plainly where the room would be: what the room is,
/// that it opens to everyone at launch, and the preview password field right there, so the screen
/// is never a dead end. The same words on every locked room.
struct PreviewLock: View {
    /// One sentence on what the room holds.
    let about: String
    /// A refusal from the server for the password last tried, if there was one.
    var message: String?
    /// Runs after the password is kept, to read the room again.
    let reload: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(about).kjBody()
            Text("It opens to everyone when Khajistan launches. Testers: type the preview password, then press Open.")
                .kjBody()
                .fixedSize(horizontal: false, vertical: true)
            if let message { Text(message).kjBody() }
            HouseInputField("Preview password", text: password, secure: true, hint: "Press to type") {
                SecureField("", text: $password)
                    .focused($fieldFocused)
                    .onSubmit(open)
            }
            .frame(maxWidth: 720, alignment: .leading)
            Button("Open", action: open)
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
                .accessibilityIdentifier("previewOpen")
                // Whether a password has been typed, for VoiceOver and the UI test.
                .accessibilityValue(password.isEmpty ? "Nothing typed" : "Password typed")
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func open() {
        // Open pressed before anything was typed: the field is where to start.
        guard !password.isEmpty else { fieldFocused = true; return }
        let entered = password
        password = ""
        Task {
            model.auth.setPreviewPassword(entered)
            await reload()
        }
    }
}
