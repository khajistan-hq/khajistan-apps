import QuickLook
import SwiftUI

/// ACCOUNT: the website's "Your Khajistan" (account, downloads and saved work) as it
/// stands on this device: the skin, All Access, the account Transmission plays under, the pages
/// kept and visited here, and the files downloaded from the site.
struct YoursView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var shelf = 0
    @State private var files: [URL] = []
    @State private var preview: URL?
    @State private var confirmClear = false
    @State private var showSignIn = false
    @State private var editingPassword = false
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHead(kicker: "Account", "Your Khajistan", line: "Account, downloads and saved work")
                skinBlock
                accountBlock
                libraryBlock
                footer
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.vertical, 16)
        }
        .overlay(alignment: .bottom) {
            if confirmClear {
                HouseDialog(text: "Clear recent pages on this device?", actions: [
                    .init(title: "Clear") { model.clearHistory(); withAnimation(.kj) { confirmClear = false } },
                    .init(title: "Cancel") { withAnimation(.kj) { confirmClear = false } },
                ])
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView(onSignedIn: {}) }
        .quickLookPreview($preview)
        .onAppear(perform: readFiles)
        .onChange(of: model.isShowingBrowser) { if !model.isShowingBrowser { readFiles() } }
    }

    // MARK: - Skin

    private var skinBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HouseRule()
            Kicker("Skin").padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    skinTab("Automatic", pick: nil)
                    ForEach(Skin.allCases, id: \.self) { skin in skinTab(skin.label, pick: skin) }
                }
            }
            .padding(.horizontal, -12)
            Text(model.skinPick == nil
                 ? "Following the sun where you are: \(model.skin.label) now. Day in daylight, Smut at dawn and dusk, Grove at night."
                 : "\(model.skin.label), until the sky moves to its next band. Then Automatic again, as on the website.")
                .kjSmall(faint: true)
                .accessibilityIdentifier("skinLine")
        }
    }

    private func skinTab(_ title: String, pick: Skin?) -> some View {
        Button {
            model.chooseSkin(pick)
        } label: {
            Text(title).kjKicker()
        }
        .buttonStyle(HouseTabStyle(isCurrent: model.skinPick == pick))
        .accessibilityIdentifier("skin-\(pick?.rawValue ?? "auto")")
    }

    // MARK: - Account

    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HouseRule()
            Kicker("Your account").padding(.top, 10)
            if model.auth.isSignedIn {
                let email = model.auth.email ?? ""
                Text(email.isEmpty ? "Signed in" : email).kjName(KJType.title)
                Button(kicker: "Sign out") { Task { await model.auth.signOut() } }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
            } else {
                Text("Khajistan Transmission plays under your website account.").kjBody()
                Button(kicker: "Sign in") { showSignIn = true }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .accessibilityIdentifier("accountSignIn")
            }
            webRow("Your Khajistan on the website", path: "dashboard.html", id: "web-dashboard")
            webRow("Your downloads", path: "downloads.html", id: "web-downloads")
            previewBlock
        }
    }

    private func webRow(_ title: String, path: String, id: String) -> some View {
        Button {
            model.open(ArchiveURL.base.appendingPathComponent(path))
        } label: {
            HStack {
                Text(title).kjName()
                Spacer()
                Text("\u{2197}").kjName().accessibilityHidden(true)
            }
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var previewBlock: some View {
        let isSet = model.auth.previewPassword != nil
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Preview password")
            Text(isSet ? "Set on this device, for the Transmission schedule until launch." : "Not set. Khajistan Transmission asks for it until launch.")
                .kjSmall(faint: true)
            if editingPassword {
                HouseInputField("Password") { SecureField("", text: $draft) }
                HStack(spacing: 16) {
                    Button(kicker: "Save") {
                        model.auth.setPreviewPassword(draft)
                        draft = ""
                        editingPassword = false
                    }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    Button(kicker: "Cancel") { draft = ""; editingPassword = false }
                        .buttonStyle(HouseButtonStyle())
                }
            } else {
                HStack(spacing: 16) {
                    Button(kicker: isSet ? "Change" : "Set") { editingPassword = true }
                    if isSet { Button(kicker: "Clear") { model.auth.clearPreviewPassword() } }
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Saved, recent, files

    private var libraryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HouseRule()
            Kicker("On this device").padding(.top, 10)
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        shelfTab("Saved", 0)
                        shelfTab("Recent", 1)
                        shelfTab("Files", 2)
                    }
                }
                if shelf == 1 && !model.library.history.isEmpty {
                    Button(kicker: "Clear") { withAnimation(.kj) { confirmClear = true } }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 0)))
                        .accessibilityIdentifier("clearRecent")
                }
            }
            .padding(.leading, -12)
            switch shelf {
            case 0: pages(model.library.bookmarks, empty: "Save a page with the bookmark in the browser and it is kept here. Reading it needs a connection.", removable: true)
            case 1: pages(model.library.history, empty: "Archive pages you open appear here. Sign-in and account pages are left out.", removable: false)
            default: fileList
            }
        }
    }

    private func shelfTab(_ title: String, _ value: Int) -> some View {
        Button { shelf = value; if value == 2 { readFiles() } } label: { Text(title).kjKicker() }
            .buttonStyle(HouseTabStyle(isCurrent: shelf == value))
            .accessibilityIdentifier("shelf-\(title.lowercased())")
    }

    @ViewBuilder
    private func pages(_ list: [SavedPage], empty: String, removable: Bool) -> some View {
        if list.isEmpty {
            Text(empty).kjSmall(faint: true).padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(list) { page in
                    HStack(alignment: .firstTextBaseline) {
                        Button { model.open(page.url) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(page.title).kjName().lineLimit(2)
                                Text(page.url.path == "/" ? "The archive" : page.url.path).kjSmall(faint: true).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
                        .accessibilityIdentifier("saved-\(page.url.path)")
                        if removable {
                            Button { model.removeSaved(page.id) } label: { Text("Remove").kjKicker() }
                                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0)))
                        }
                    }
                    if page.id != list.last?.id { HouseRule() }
                }
            }
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if files.isEmpty {
            Text("Files you download from the archive appear here. Reading Room pages are not saved for offline reading.")
                .kjSmall(faint: true).padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.self) { file in
                    HStack {
                        Button { preview = file } label: {
                            Text(file.lastPathComponent).kjName().lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
                        ShareLink(item: file) { Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40) }
                            .accessibilityLabel("Share \(file.lastPathComponent)")
                        Button { remove(file) } label: { Text("Delete").kjKicker() }
                            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 0)))
                    }
                    if file != files.last { HouseRule() }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HouseRule()
            webRow("About Khajistan", path: "about.html", id: "web-about")
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            Text("Khajistan for \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") \(version)").kjSmall(faint: true)
            Text("Khajistan carries each broadcaster's own signal and keeps no copy of it.").kjSmall(faint: true)
        }
    }

    private func readFiles() {
        let directory = ArchiveBrowser.downloadDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { files = []; return }
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { model.message = "Could not read downloaded files: \(error.localizedDescription)" }
    }

    private func remove(_ file: URL) {
        do { try FileManager.default.removeItem(at: file); readFiles() }
        catch { model.message = "Could not delete file: \(error.localizedDescription)" }
    }
}

/// Email and password, for Khajistan Transmission: the account the reader has on the website.
struct SignInView: View {
    let onSignedIn: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorLine: String?

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !busy }

    var body: some View {
        let palette = Palette(model.skin)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Kicker("Khajistan account")
                    Spacer()
                    Button(kicker: "Cancel") { dismiss() }.buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)))
                }
                Text("Sign in").kjDisplay()
                Text("The email and password you use on the website.").kjBody()
                HouseInputField("Email") {
                    TextField("", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("signInEmail")
                }
                HouseInputField("Password") {
                    SecureField("", text: $password).textContentType(.password).onSubmit { Task { await submit() } }
                }
                Button(kicker: busy ? "Signing in\u{2026}" : "Sign in") { Task { await submit() } }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .disabled(!canSubmit)
                if let errorLine { Text(errorLine).kjBody() }
            }
            .padding(KJLayout.inset)
        }
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .presentationBackground(palette.ground)
        .preferredColorScheme(model.skin == .day ? .light : .dark)
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        errorLine = nil
        do {
            try await model.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            await onSignedIn()
            dismiss()
        } catch {
            if let failure = error as? AuthError {
                switch failure {
                case .server(let text): errorLine = text
                case .anonymous: errorLine = "This account cannot watch Khajistan Transmission."
                default: errorLine = "Sign-in failed."
                }
            } else {
                errorLine = error.localizedDescription
            }
        }
        busy = false
    }
}
