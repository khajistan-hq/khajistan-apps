import SwiftUI

/// Chat: the website's rooms, live. The rooms at left in the site's order, the room's lines at
/// right, newest at the foot. Reading needs no account; writing needs one, a handle and the 16+
/// acknowledgement, the same three things the website asks for. The Apple TV keyboard takes
/// dictation: hold the remote's microphone button while it is up and speak.
/// Hold Select on a line to report it, ignore its author on this device, or delete your own.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var room: ChatRoom?
    @State private var feed: ChatFeed?
    @State private var lines: [ChatMessage] = []
    @State private var draft = ""
    @State private var wantHandle = ""
    @State private var note: String?
    @State private var ignored = ChatRules.ignored()
    @State private var sending = false

    private var store: ChatStore { model.chat }

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            roomList
                .frame(width: 520)
                .focusSection()
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 32)
        .kjBody()
        .task { await store.start() }
        .task(id: model.auth.session?.userId) { await store.loadAccount() }
        .task(id: room?.slug) { await follow(room) }
    }

    // MARK: - Rooms

    private var roomList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Chat")
                    .kjDisplay(KJType.headline, tracking: -0.055)
                    .accessibilityAddTraits(.isHeader)
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the rooms\u{2026}")
                case .failed(let line):
                    Text(line).kjBody()
                    Button("Try again") { Task { await store.start() } }
                        .buttonStyle(HouseButtonStyle())
                        .padding(.leading, -26)
                case .ready:
                    ForEach(store.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker(group.title).padding(.leading, 22)
                            ForEach(group.rooms) { item in
                                Button {
                                    room = item
                                } label: {
                                    Text(item.label).kjKicker()
                                }
                                .buttonStyle(HouseTabStyle(isCurrent: item.slug == room?.slug))
                                .accessibilityIdentifier("chat-room-\(item.slug)")
                            }
                        }
                        .padding(.leading, -22)
                    }
                }
            }
            .padding(.bottom, KJLayout.inset)
        }
        .kjTopFade()
    }

    // MARK: - The room

    @ViewBuilder
    private var panel: some View {
        if let room {
            VStack(alignment: .leading, spacing: 18) {
                Text(room.label).kjName(44).accessibilityIdentifier("chatRoomName")
                if let description = room.description, !description.isEmpty {
                    Text(description).kjSmall(faint: true).lineLimit(2)
                }
                lineList
                composer
                if let note {
                    Text(note).kjSmall(faint: true).accessibilityIdentifier("chatNote")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Kicker("House rules")
                ForEach(ChatRules.houseRules, id: \.self) { rule in
                    Text(rule).kjBody().fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var shown: [ChatMessage] {
        lines.filter { !ignored.contains($0.author_handle ?? "") }
    }

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if shown.isEmpty {
                        Text("No lines in the last 48 hours.").kjSmall(faint: true)
                    }
                    ForEach(shown) { line in
                        Button {} label: {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(Self.time(line.created_at)).kjSmall(faint: true)
                                Text(line.who).kjKicker()
                                Text(line.body).kjBody().fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)))
                        .contextMenu { actions(for: line) }
                        .id(line.id)
                        .accessibilityIdentifier("chat-line-\(line.id)")
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: shown.last?.id) { _, last in
                if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func actions(for line: ChatMessage) -> some View {
        Button("Report") {
            Task { note = await feed?.report(line) }
        }
        if let handle = line.author_handle, handle != store.handle {
            Button("Ignore \(handle)") {
                ChatRules.setIgnored(handle, true)
                ignored = ChatRules.ignored()
                note = "\(handle) is ignored on this Apple TV."
            }
        }
        if line.kind == "text", let mine = model.auth.session?.userId, line.author_id == mine {
            Button("Delete") {
                Task { note = (await feed?.delete(line) ?? false) ? nil : "That did not delete." }
            }
        }
    }

    // MARK: - Writing

    @ViewBuilder
    private var composer: some View {
        if !model.auth.isSignedIn {
            Text("Sign in under Account to write in a room.").kjSmall(faint: true)
        } else if store.handle == "" {
            HouseInputField("Choose a handle", text: wantHandle) {
                TextField("", text: $wantHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { note = await store.claim(wantHandle) } }
            }
            .accessibilityIdentifier("chatHandle")
        } else if store.handle != nil, !store.ageAcknowledged {
            HStack(spacing: 24) {
                Text("You need to be 16 or older to write.").kjBody()
                Button("I am 16 or older") {
                    Task { if !(await store.acknowledgeAge()) { note = "That did not save. Try again." } }
                }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("chatAgeAck")
            }
        } else if let handle = store.handle {
            VStack(alignment: .leading, spacing: 8) {
                HouseInputField("Write as \(handle)", text: draft) {
                    TextField("", text: $draft)
                        .onSubmit { send(as: handle) }
                }
                .disabled(sending)
                .accessibilityIdentifier("chatWrite")
                Text("Hold the microphone button on the remote to speak instead of typing.")
                    .kjSmall(faint: true)
            }
        }
    }

    private func send(as handle: String) {
        guard let feed, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        let text = draft
        Task {
            let refusal = await feed.send(text, handle: handle)
            note = refusal
            if refusal == nil { draft = "" }
            sending = false
        }
    }

    /// Opens a room's feed and follows it until the room changes or the screen goes.
    private func follow(_ room: ChatRoom?) async {
        feed?.stop()
        lines = []
        note = nil
        guard let room else { feed = nil; return }
        let store = store
        let opened = ChatFeed(room: room, account: { await store.account() })
        feed = opened
        opened.start()
        for await batch in opened.lines {
            if Task.isCancelled { break }
            lines = batch
        }
        opened.stop()
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
