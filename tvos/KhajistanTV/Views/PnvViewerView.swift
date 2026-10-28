import SwiftUI

/// One Pics/Vids object, full screen. A picture is fitted whole, never cropped. A video plays in
/// AVPlayer; a Khajistan TV row goes through tv-play and needs the viewer's account, which the
/// sign-in sheet takes in place. Left and right move through the shelf the viewer came from
/// (loading its next page at its end); play/pause pauses a video; menu goes back. Down lights Save,
/// as the website's heart, and Right from it Collection, as Cosmos files a block; Select works the
/// one lit, Up or Menu lets go. Lit by the remote, never focused, as the Receiver's strip is.
struct PnvViewerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: PnvRow
    @State private var controller = PlayerController()
    @State private var picture: UIImage?
    @State private var phase: Phase = .loading
    @State private var caption: String?
    @State private var overlayVisible = true
    @State private var showSignIn = false
    @State private var hideTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var stepTask: Task<Void, Never>?
    @State private var armed: Control?
    @State private var saveNote: String?
    @State private var showCollections = false

    private enum Control { case save, collection }

    private enum Phase: Equatable {
        case loading, ready, needsSignIn
        case failed(String)
    }

    /// The shelf the object was chosen from: left and right step through its region's stream, or
    /// through the saved list it was opened from.
    private let region: String
    private let list: [PnvRow]?

    init(row: PnvRow, region: String) {
        _current = State(initialValue: row)
        self.region = region
        self.list = nil
    }

    init(row: PnvRow, list: [PnvRow]) {
        _current = State(initialValue: row)
        self.region = ""
        self.list = list
    }

    private var store: PicsVidsStore { model.pnv }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            // Moving pictures letterbox on black (owner, 2026-10-05); a still keeps the ground.
            (current.isVideo ? Color.black : palette.ground).ignoresSafeArea()
            // The poster stands in until the video is playing, then gives way to it: the two
            // frames need not have the same edges.
            if let picture, !(current.isVideo && controller.state == .playing) {
                Image(uiImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }
            if current.isVideo {
                PlayerLayerView(player: controller.player)
                    .ignoresSafeArea()
            }
            if isWaiting {
                TuningLoader(nil)
            }
            overlay(palette)
            // The focus target: it draws nothing and holds focus so the remote's presses land.
            Button {
                switch armed {
                case .save: wake(); toggleSave()
                case .collection: wake(); openCollections()
                case nil: if phase == .needsSignIn { showSignIn = true } else { wake() }
                }
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
            .accessibilityIdentifier("pnvViewerSurface")
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            if let lit = armed {
                switch direction {
                case .right where lit == .save: armed = .collection
                case .left where lit == .collection: armed = .save
                case .up: armed = nil
                default: break
                }
                return
            }
            switch direction {
            case .left: step(by: -1)
            case .right: step(by: 1)
            case .down: armed = .save
            default: break
            }
        }
        .onPlayPauseCommand {
            wake()
            if current.isVideo && phase == .ready { controller.toggle() }
        }
        .onExitCommand {
            if armed != nil {
                armed = nil
                wake()
                return
            }
            stopEverything()
            dismiss()
        }
        .onChange(of: phase) { wake() }
        .onChange(of: controller.state) { wake() }
        .task { show(current) }
        .onDisappear { stopEverything() }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: { show(current) })
        }
        .fullScreenCover(isPresented: $showCollections) {
            PnvCollectionsPanel(key: current.media_key).environment(\.palette, palette)
        }
        .task(id: model.auth.email) { await model.saves.load() }
    }

    /// A picture still on its way, or a video connecting.
    private var isWaiting: Bool {
        switch phase {
        case .loading: return true
        case .ready: return current.isVideo && controller.state == .tuning
        case .needsSignIn, .failed: return false
        }
    }

    // MARK: - Overlay

    private func overlay(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            StatusBand(leading: ["Khajistan Pics/Vids", "@" + store.accountHandle(for: current)],
                       trailing: [current.isVideo ? "Video" : "Picture"])
            Spacer(minLength: 0)
            panel
                .background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
        }
        .opacity(overlayVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: overlayVisible)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let state = stateText {
                Kicker(state).accessibilityIdentifier("pnvViewerState")
            }
            Text(PnvAPI.metaLine(for: current, regionToken: store.regionToken(for: current), date: Self.dateText))
                .kjBody()
            if let caption {
                Text(caption)
                    .kjSmall(faint: true)
                    .lineLimit(3)
            }
            if phase == .needsSignIn {
                // Select opens the sign-in sheet; the line says so.
                Kicker("Select to sign in")
            }
            saveControls
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Save and Collection, lit by the remote: Down lights Save, Right Collection. Said once in
    /// place while nothing is lit, as the Receiver's strip cues its controls.
    private var saveControls: some View {
        let saved = model.saves.isSaved(pnvKey: current.media_key)
        return HStack(spacing: 14) {
            StripChipStyle.face(Text((armed == nil ? "\u{2193} " : "") + (saved ? "Saved" : "Save")), isOn: saved, selected: armed == .save)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(armed == .save ? .isSelected : [])
                .accessibilityLabel(saved ? "Saved" : "Save")
                .accessibilityValue(saved ? "On" : "Off")
                .accessibilityIdentifier("pnvSave")
                .accessibilityAction { toggleSave() }
            StripChipStyle.face(Text("Collection"), isOn: false, selected: armed == .collection)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(armed == .collection ? .isSelected : [])
                .accessibilityIdentifier("pnvCollection")
                .accessibilityAction { openCollections() }
            if let saveNote { Text(saveNote).kjSmall(faint: true).accessibilityIdentifier("pnvSaveNote") }
        }
        // The strip's chips are drawn for a band; here they stand on one.
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Palette(model.skin).band)
        .padding(.top, 8)
    }

    /// Save, as the website's heart: on the account, with no title or picture kept, so an object
    /// taken off the shelf leaves nothing of itself in a library.
    private func toggleSave() {
        guard model.saves.canSave else { saveNote = "Sign in under Account to save to your account."; return }
        guard PassportSaves.pnvRef(current.media_key) != nil else { saveNote = "This object cannot be saved yet."; return }
        let key = current.media_key
        Task {
            await model.saves.load()
            saveNote = await model.saves.toggle(pnvKey: key) ? nil : "That did not save. Try again."
        }
    }

    private func openCollections() {
        guard model.saves.canSave else { saveNote = "Sign in under Account to keep collections."; return }
        showCollections = true
    }

    private var stateText: String? {
        switch phase {
        case .loading: return "Loading\u{2026}"
        case .needsSignIn: return PnvPlaybackError.needsSignIn.errorDescription
        case .failed(let message): return message
        case .ready:
            switch controller.state {
            case .paused: return "Paused"
            case .failed(let message): return message
            default: return nil
            }
        }
    }

    private static func dateText(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    // MARK: - Showing a row

    private func show(_ row: PnvRow) {
        loadTask?.cancel()
        controller.stop()
        current = row
        picture = nil
        caption = nil
        phase = .loading
        wake()
        let key = row.id
        loadTask = Task {
            Task { @MainActor in
                let text = await store.caption(for: row)
                if current.id == key { caption = text }
            }
            if row.isVideo {
                model.silenceRadio()
                await playVideo(row)
            } else {
                let image = await PnvImages.shared.image(PnvMedia.pictureCandidates(row), maxPixel: 2400)
                guard !Task.isCancelled, current.id == key else { return }
                if let image {
                    picture = image
                    phase = .ready
                } else {
                    phase = .failed("This picture could not load.")
                }
            }
        }
    }

    /// The poster shows at once; the file is resolved and played behind it.
    private func playVideo(_ row: PnvRow) async {
        let key = row.id
        Task { @MainActor in
            let still = await PnvImages.shared.image([PnvMedia.poster(row), PnvMedia.thumb(row)].compactMap { $0 }, maxPixel: 2400)
            if current.id == key, picture == nil { picture = still }
        }
        do {
            let url = try await store.playableURL(for: row)
            try Task.checkCancellation()
            guard current.id == key else { return }
            // A clip loops, as a reel does; a Khajistan TV programme plays once.
            controller.onEnded = { [controller] in
                guard !row.isKtv else { return }
                controller.player.seek(to: .zero)
                controller.resume()
            }
            controller.attach(url: url, seekTo: nil, title: "@" + store.accountHandle(for: row), subtitle: "Khajistan", isLive: false)
            phase = .ready
        } catch PnvPlaybackError.needsSignIn {
            guard !Task.isCancelled, current.id == key else { return }
            phase = .needsSignIn
        } catch {
            guard !Task.isCancelled, current.id == key else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// The neighbour in the stream. At the end of what is loaded the next page is asked for first.
    private func step(by delta: Int) {
        stepTask?.cancel()
        stepTask = Task {
            if let list {
                guard let index = list.firstIndex(where: { $0.id == current.id }), list.indices.contains(index + delta) else { return }
                saveNote = nil
                show(list[index + delta])
                return
            }
            saveNote = nil
            guard var index = store.feed(region).items.firstIndex(where: { $0.id == current.id }) else { return }
            index += delta
            if index >= store.feed(region).items.count { await store.loadMore(region: region) }
            let items = store.feed(region).items
            guard !Task.isCancelled, items.indices.contains(index) else { return }
            show(items[index])
        }
    }

    private func stopEverything() {
        loadTask?.cancel()
        stepTask?.cancel()
        hideTask?.cancel()
        controller.stop()
    }

    /// Shows the overlay. Once the object is showing (a picture, or a video that is playing) it
    /// hides again after 2.6 seconds without a press; otherwise it stays, because that is what
    /// there is to read.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        let settled = phase == .ready && (!current.isVideo || controller.state == .playing)
        guard settled else { return }
        guard OverlayTiming.hidesItself else { return }
        hideTask = Task {
            try? await Task.sleep(for: OverlayTiming.idle)
            // A lit control keeps the overlay up, so Select never works one that cannot be seen.
            if !Task.isCancelled, armed == nil { overlayVisible = false }
        }
    }
}

/// The account's collections, as Cosmos files a block: each ticked where this object is in it,
/// Select puts it in or takes it out; a new one is named and made with this object in it. The same
/// rows the website's Pics/Vids collections are. Menu comes back to the object.
private struct PnvCollectionsPanel: View {
    let key: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var name = ""
    @State private var note: String?

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Collections").kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 20)
                    ForEach(model.saves.collections) { collection in
                        let holds = collection.media_keys.contains(key)
                        Button {
                            Task { note = await model.saves.toggle(pnvKey: key, in: collection.id) ? nil : "That did not save. Try again." }
                        } label: {
                            HStack {
                                Text(collection.name).kjBody().lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(collection.media_keys.count)").kjSmall(faint: true)
                                if holds { Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).accessibilityHidden(true) }
                            }
                            .frame(maxWidth: 900, alignment: .leading)
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
                        .accessibilityAddTraits(holds ? .isSelected : [])
                        .accessibilityIdentifier("pnvcollection-\(collection.id)")
                        Hairline().frame(maxWidth: 932)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        HouseInputField("New collection", text: name, hint: "A name for it") {
                            TextField("", text: $name)
                        }
                        .frame(width: 700)
                        Button {
                            let made = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !made.isEmpty else { return }
                            Task {
                                if await model.saves.createCollection(name: made, keys: [key]) == nil {
                                    note = "That did not save. A name of 1 to 120 characters is needed."
                                } else {
                                    name = ""
                                    note = nil
                                }
                            }
                        } label: { Label("Make", systemImage: "plus").kjKicker() }
                        .buttonStyle(HouseButtonStyle())
                        .accessibilityIdentifier("pnvNewCollection")
                    }
                    .padding(.top, 28)
                    .focusSection()
                    if let note { Text(note).kjSmall(faint: true).padding(.top, 12) }
                }
                .padding(KJLayout.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(palette.ink)
        .task { await model.saves.load() }
    }
}
