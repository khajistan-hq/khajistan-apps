import SwiftUI

/// Chat: the website's rooms, live. The rooms at left in the site's order, the room's lines at
/// right, newest at the foot. Reading needs no account; writing needs one, a handle and the 16+
/// acknowledgement, the same three things the website asks for. The Apple TV keyboard takes
/// dictation: hold the remote's microphone button while it is up and speak.
/// Select on a line opens its actions under it: report it, ignore its author on this device, or
/// delete your own.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var room: ChatRoom?
    @State private var feed: ChatFeed?
    @State private var draft = ""
    @State private var wantHandle = ""
    @State private var note: String?
    @State private var ignored = ChatRules.ignored()
    @State private var sending = false
    /// The line whose actions are open under it. tvOS draws a context menu's focused item white,
    /// so the actions are a row of house buttons instead, opened by Select on the line.
    @State private var actionsFor: Int64?
    @FocusState private var actionFocus: ActionFocus?
    private enum ActionFocus: Hashable { case open, report }
    /// A Pics/Vids object opened from a line, in the Pics/Vids viewer.
    @State private var viewing: PnvRow?

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
        .fullScreenCover(item: $viewing) { row in
            PnvViewerView(row: row, region: PicsVidsStore.allRegions)
        }
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
                                    actionsFor = nil
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
                if !ignored.isEmpty {
                    Button("Show the \(ignored.count) ignored again") {
                        for handle in ignored { ChatRules.setIgnored(handle, false) }
                        ignored = ChatRules.ignored()
                    }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                    .accessibilityIdentifier("chatUnignore")
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
        (feed?.lines ?? []).filter { !ignored.contains($0.author_handle ?? "") }
    }

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let error = feed?.error {
                        Text(error).kjSmall(faint: true)
                    } else if shown.isEmpty, feed?.isLoadingOlder == true || feed?.hasLoaded == false {
                        TuningLoader("Loading the room\u{2026}")
                    } else if shown.isEmpty {
                        Text("No lines in the last 48 hours.").kjSmall(faint: true)
                    }
                    ForEach(shown) { line in
                        Button {
                            actionsFor = actionsFor == line.id ? nil : line.id
                            actionFocus = actionsFor == nil ? nil : (Self.archiveKey(ChatMedia.of(line)) == nil ? .report : .open)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(Self.time(line.created_at)).kjSmall(faint: true)
                                Text(line.who).kjKicker()
                                // A GIF line's body is the GIF's file name ("10190"); the picture says it.
                                if !Self.isGif(ChatMedia.of(line)) {
                                    Text(line.body).kjBody().fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)))
                        .id(line.id)
                        .accessibilityIdentifier("chat-line-\(line.id)")
                        // Under the button, not in it: on tvOS 26 the UIKit view that draws the
                        // picture kept Select from reaching a button it sat inside (CI run
                        // 37630234504; tvOS 27 was unaffected).
                        if let media = ChatMedia.of(line) {
                            ChatMediaView(media: media, height: 220).padding(.leading, 16)
                        }
                        if actionsFor == line.id { actions(for: line) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: shown.last?.id) { _, last in
                if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
    }

    private func actions(for line: ChatMessage) -> some View {
        let archiveKey = Self.archiveKey(ChatMedia.of(line))
        return HStack(spacing: 12) {
            if let archiveKey {
                Button("Open") {
                    actionsFor = nil
                    Task {
                        if let row = await ChatMediaCache.shared.row(archiveKey) { viewing = row }
                        else { note = "That is not in Pics/Vids any more." }
                    }
                }
                .focused($actionFocus, equals: .open)
            }
            Button("Report") {
                actionsFor = nil
                Task { note = await feed?.report(line) }
            }
            .focused($actionFocus, equals: .report)
            if let handle = line.author_handle, handle != store.handle {
                Button("Ignore \(handle)") {
                    actionsFor = nil
                    ChatRules.setIgnored(handle, true)
                    ignored = ChatRules.ignored()
                    note = "\(handle) is ignored on this Apple TV."
                }
            }
            if line.kind == "text", let mine = model.auth.session?.userId, line.author_id == mine {
                Button("Delete") {
                    actionsFor = nil
                    Task { note = (await feed?.delete(line) ?? false) ? nil : "That did not delete." }
                }
            }
            Button("Cancel") { actionsFor = nil }
        }
        .buttonStyle(HouseTabStyle(isCurrent: false))
        .padding(.leading, 16)
        .onExitCommand { actionsFor = nil }
        .accessibilityIdentifier("chat-actions")
    }

    private static func archiveKey(_ media: ChatMedia?) -> String? {
        if case .archive(let key) = media { return key }
        return nil
    }

    private static func isGif(_ media: ChatMedia?) -> Bool {
        if case .gif = media { return true }
        return false
    }

    // MARK: - Writing

    @ViewBuilder
    private var composer: some View {
        if !model.auth.isSignedIn {
            Text("Sign in under Account to write in a room.").kjSmall(faint: true)
        } else if store.accountUnread {
            HStack(spacing: 24) {
                Text("Your account could not be read.").kjBody()
                Button("Try again") { Task { await store.loadAccount() } }
                    .buttonStyle(HouseButtonStyle())
            }
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
        let text = draft, slug = feed.room.slug
        Task {
            let refusal = await feed.send(text, handle: handle)
            sending = false
            // Only the line that was sent is cleared, and only in the room it was sent from.
            guard room?.slug == slug else { return }
            note = refusal
            if refusal == nil, draft == text { draft = "" }
        }
    }

    /// Opens a room's feed and keeps it polling until the room changes or the screen goes.
    private func follow(_ room: ChatRoom?) async {
        feed?.stop()
        note = nil
        // A draft belongs to the room it was written in.
        draft = ""
        guard let room else { feed = nil; return }
        let store = store
        let opened = feed?.room == room ? feed! : ChatFeed(room: room, account: { await store.account() })
        feed = opened
        opened.start()
        // Held until the task is cancelled: a new room, or the section closing.
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
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
