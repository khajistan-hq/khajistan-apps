import SwiftUI
import UIKit

/// CHAT, the website's rooms (kj-chat.js) on a phone: the rooms by region, a room's last 48 hours,
/// and a line written by typing or by the keyboard's own dictation. The rules and the requests are
/// the Apple TV app's (Core/Chat.swift, Services/ChatStore.swift, linked). Partners (18+) rooms are
/// never offered (owner, 2026-10-06). App Store builds leave chat out (StoreBuild).
struct ChatScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var room: ChatRoom?

    var body: some View {
        VStack(spacing: 0) {
            PlayerTopBar(leading: ["Khajistan", "Chat"], trailing: []) {
                model.isShowingChat = false
            }
            ZStack {
                if let room {
                    ChatRoomView(room: room) { withAnimation(.kjPush) { self.room = nil } }
                        .id(room.slug)
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                } else {
                    roomList
                        .transition(.move(edge: .leading))
                }
            }
            .clipped()
        }
        .background(palette.ground.ignoresSafeArea())
        .task {
            await model.chat.start()
            await model.chat.loadAccount()
        }
    }

    // MARK: - The rooms

    private var roomList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHead(kicker: "Chat", "Rooms", line: "Chat rooms by region")
                switch model.chat.phase {
                case .idle, .loading:
                    TuningLoader("Loading the rooms\u{2026}")
                case .failed(let message):
                    Text(message).kjBody()
                case .ready:
                    ForEach(model.chat.groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            HouseRule()
                            Kicker(group.title).padding(.top, 14).padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.rooms) { item in
                                Button {
                                    withAnimation(.kjPush) { room = item }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.label).kjName()
                                        if let description = item.description, !description.isEmpty {
                                            Text(description).kjSmall(faint: true).lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
                                .accessibilityIdentifier("chat-room-\(item.slug)")
                            }
                        }
                    }
                }
                houseRules
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.vertical, 16)
        }
    }

    private var houseRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            HouseRule()
            Kicker("House rules").padding(.top, 14)
            ForEach(ChatRules.houseRules, id: \.self) { rule in
                Text(rule).kjSmall().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One room: its lines, oldest first, polled while the room is on screen, and the writing line.
struct ChatRoomView: View {
    let room: ChatRoom
    let back: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed: ChatFeed?
    @State private var draft = ""
    @State private var wantHandle = ""
    @State private var note: String?
    @State private var sending = false
    @State private var ignored = ChatRules.ignored()
    /// A Pics/Vids object opened from a line, in the Pics/Vids viewer.
    @State private var viewing: PnvRow?
    /// The line whose actions are up, in the house dialog. Apple's context menu drew a grey
    /// platter over the room (ECC roast 2026-10-08).
    @State private var actionsFor: ChatMessage?

    private var store: ChatStore { model.chat }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            lines
            composer
            if let note {
                Text(note).kjSmall(faint: true).accessibilityIdentifier("chatNote")
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.bottom, 12)
        .kjColumn()
        .onAppear {
            let store = store
            let opened = feed ?? ChatFeed(room: room, account: { await store.account() })
            feed = opened
            opened.start()
        }
        .onDisappear { feed?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { feed?.start() } else { feed?.stop() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: back) {
                Text("\u{2190} All rooms").kjKicker()
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 4, trailing: 12)))
            .accessibilityIdentifier("chatBack")
            Text(room.label).kjDisplay(KJType.headline, tracking: -0.04)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("chatRoomName")
            if let description = room.description, !description.isEmpty {
                Text(description).kjSmall(faint: true).lineLimit(2)
            }
        }
    }

    private var shown: [ChatMessage] {
        (feed?.lines ?? []).filter { !ignored.contains($0.author_handle ?? "") }
    }

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let feed, feed.hasOlder, !shown.isEmpty {
                        Button {
                            Task { await feed.loadOlder() }
                        } label: {
                            Text(feed.isLoadingOlder ? "Loading\u{2026}" : "Earlier lines").kjKicker()
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 12)))
                        .disabled(feed.isLoadingOlder)
                        .accessibilityIdentifier("chatOlder")
                    }
                    if let error = feed?.error {
                        Text(error).kjSmall(faint: true)
                    } else if shown.isEmpty {
                        Text("No lines in the last 48 hours.").kjSmall(faint: true)
                    }
                    ForEach(shown) { line in
                        let media = ChatMedia.of(line)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(line.who).kjKicker()
                                Text(Self.time(line.created_at)).kjSmall(faint: true)
                            }
                            // A GIF line's body is the GIF's file name ("10190"); the picture says it.
                            if !Self.isGif(media) {
                                Text(line.body).kjBody().fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            if let media { mediaView(media) }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.kj) { actionsFor = line } }
                        .id(line.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityAction(named: "Line actions") { actionsFor = line }
                        .accessibilityIdentifier("chat-line-\(line.id)")
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .fullScreenCover(item: $viewing) { row in
                PnvViewerView(row: row, steps: false)
            }
            .overlay(alignment: .bottom) {
                if let line = actionsFor {
                    HouseDialog(text: "\(line.who): \(line.body)", actions: actions(for: line) + [
                        .init(title: "Cancel") { withAnimation(.kj) { actionsFor = nil } },
                    ])
                }
            }
            .onChange(of: shown.last?.id) { _, last in
                if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
    }

    /// A GIF plays in the line; a Pics/Vids object opens in the Pics/Vids viewer when tapped.
    @ViewBuilder
    private func mediaView(_ media: ChatMedia) -> some View {
        switch media {
        case .gif:
            ChatMediaView(media: media, height: 160).padding(.top, 4)
        case .archive(let key):
            // A tap layer over the picture: the UIKit view that draws it keeps a Button around it
            // from ever seeing the touch.
            ChatMediaView(media: media, height: 160)
                .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { open(key) } }
                .padding(.top, 4)
        }
    }

    private func open(_ key: String) {
        Task {
            if let row = await ChatMediaCache.shared.row(key) { viewing = row }
            else { note = "That is not in Pics/Vids any more." }
        }
    }

    private static func isGif(_ media: ChatMedia?) -> Bool {
        if case .gif = media { return true }
        return false
    }

    private func actions(for line: ChatMessage) -> [HouseDialog.Action] {
        var list: [HouseDialog.Action] = []
        let close = { withAnimation(.kj) { actionsFor = nil } }
        if case .archive(let key) = ChatMedia.of(line) {
            list.append(.init(title: "Open") { close(); open(key) })
        }
        list.append(.init(title: "Report") { close(); Task { note = await feed?.report(line) } })
        if let handle = line.author_handle, handle != store.handle {
            list.append(.init(title: "Ignore") {
                close()
                ChatRules.setIgnored(handle, true)
                ignored = ChatRules.ignored()
                note = "\(handle) is ignored on this device."
            })
        }
        if line.kind == "text", let mine = model.auth.session?.userId, line.author_id == mine {
            list.append(.init(title: "Delete") {
                close()
                Task { note = (await feed?.delete(line) ?? false) ? nil : "That did not delete." }
            })
        }
        return list
    }

    // MARK: - Writing

    @ViewBuilder
    private var composer: some View {
        if !model.auth.isSignedIn {
            Text("Sign in under Account to write in a room.").kjSmall(faint: true)
        } else if store.handle == "" {
            HouseInputField("Choose a handle") {
                TextField("", text: $wantHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { note = await store.claim(wantHandle) } }
            }
            .accessibilityIdentifier("chatHandle")
        } else if store.handle != nil, !store.ageAcknowledged {
            VStack(alignment: .leading, spacing: 10) {
                Text("You need to be 16 or older to write.").kjBody()
                Button {
                    Task { if !(await store.acknowledgeAge()) { note = "That did not save. Try again." } }
                } label: {
                    Text("I am 16 or older").kjKicker()
                }
                .buttonStyle(HouseButtonStyle(solid: true))
                .accessibilityIdentifier("chatAgeAck")
            }
        } else if let handle = store.handle {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 12) {
                    HouseInputField("Write as \(handle)") {
                        TextField("", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .submitLabel(.send)
                            .onSubmit { send(as: handle) }
                    }
                    .accessibilityIdentifier("chatWrite")
                    Button {
                        send(as: handle)
                    } label: {
                        Text("Send").kjKicker()
                    }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .disabled(sending || ChatRules.cleaned(draft) == nil)
                    .accessibilityIdentifier("chatSend")
                }
                .disabled(sending)
                Text("To speak instead of typing, use the microphone on the keyboard.")
                    .kjSmall(faint: true)
            }
        }
    }

    private func send(as handle: String) {
        guard let feed, ChatRules.cleaned(draft) != nil else { return }
        sending = true
        let text = draft
        Task {
            let refusal = await feed.send(text, handle: handle)
            note = refusal
            if refusal == nil { draft = "" }
            sending = false
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ created: String) -> String {
        ChatClock.date(created).map { clock.string(from: $0) } ?? ""
    }
}
