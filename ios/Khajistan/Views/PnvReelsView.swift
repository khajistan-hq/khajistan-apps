import SwiftUI

/// Pics/Vids as reels (owner, 2026-11-08: "they need to be like reels and grid to make the
/// interaction better"). One object a screen, a swipe up for the next and down for the one
/// before, as a phone's short-video feed moves. A video plays when its page settles and loops; a
/// tap pauses it. Save and Collection stay on the right rail, the account and the caption at the
/// bottom left, so nothing waits behind a tap. A picture is fitted whole, never cropped.
struct PnvReelsView: View {
    /// Where the pages come from: the live stream under the region filter, which grows as the
    /// viewer nears its end, or a fixed list (an account's saves).
    enum Source { case feed, rows([PnvRow]) }

    enum Phase: Equatable { case idle, loading, ready, needsSignIn, failed(String) }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var position: String?
    @State private var controller = PlayerController()
    @State private var phase: Phase = .idle
    @State private var loadTask: Task<Void, Never>?
    @State private var showSignIn = false
    /// The page activate() last ran for, so a second call for the same page does not restart it.
    @State private var activatedId: String?
    /// The page whose video is attached to the player now. A page shows the player only when it
    /// owns it, so the frame after a flip never shows the last page's picture on the new one.
    @State private var owner: String?
    /// A saved list is fixed when the reels open: un-saving here must not pull the page away.
    @State private var fixed: [PnvRow]

    let start: PnvRow
    let source: Source

    init(start: PnvRow, source: Source = .feed) {
        self.start = start
        self.source = source
        // Seeded before the first paint, so a deep tile never shows the first reel for a frame;
        // the scrollTo on arrival corrects a lazy stack that lands a page off.
        _position = State(initialValue: start.id)
        if case .rows(let rows) = source { _fixed = State(initialValue: rows) } else { _fixed = State(initialValue: []) }
    }

    private var store: PicsVidsStore { model.pnv }

    private var items: [PnvRow] {
        switch source {
        case .feed: return store.feed(model.pnvRegion).items
        case .rows: return fixed
        }
    }

    private var currentId: String { position ?? start.id }
    private var current: PnvRow? { items.first { $0.id == currentId } }

    var body: some View {
        let palette = Palette(model.skin)
        // Read outside the full-bleed pager: inside it the safe area is zero, and the rail would sit
        // on the home indicator.
        GeometryReader { outer in
        let insets = outer.safeAreaInsets
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { row in
                    PnvReelPage(row: row, isCurrent: row.id == currentId, ownsPlayer: owner == row.id,
                                controller: controller, phase: phase, insets: insets,
                                signIn: { showSignIn = true })
                        .containerRelativeFrame([.horizontal, .vertical])
                        // Only the reel on screen is read: a built neighbour's Save is not reachable
                        // off screen. Set here, where the current page is always known.
                        .accessibilityHidden(row.id != currentId)
                        .id(row.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        // The seeded position can land a page off in a lazy stack that has not built the tapped
        // page yet; scrolling to it once on arrival puts the reel on the object that was tapped.
        .onAppear { proxy.scrollTo(start.id, anchor: .top) }
        // On the pager itself, not the screen: on the screen it also renamed the Close button.
        .accessibilityIdentifier("pnvReels")
        // The account, which VoiceOver reads; the page's own identifier carries the key for tests.
        .accessibilityValue(current.map { "@" + store.accountHandle(for: $0) } ?? "")
        .accessibilityActions {
            Button("Next") { step(1) }
            Button("Previous") { step(-1) }
        }
        .overlay(alignment: .topLeading) { closeButton }
        }
        }
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .statusBarHidden()
        .onAppear { activate() }
        .task { await model.saves.load() }
        .onChange(of: position) { activate() }
        .onDisappear { loadTask?.cancel(); controller.stop() }
        .sheet(isPresented: $showSignIn) { SignInView(model: model, onSignedIn: { activate(force: true) }) }
        // A keyboard or a trackpad pages too: a drag does not page a scroll view on the Mac.
        .focusable()
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
    }

    private var closeButton: some View {
        Button { controller.stop(); dismiss() } label: {
            Image(systemName: "xmark").font(.system(.body, weight: .bold)).frame(width: 44, height: 44)
        }
        .buttonStyle(ReelRailStyle())
        .padding(.leading, KJLayout.inset - 6)
        .padding(.top, 6)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("closePlayer")
    }

    /// The page that settled: its video starts, whatever played before stops; near the end of the
    /// stream the next page of it is asked for.
    private func activate(force: Bool = false) {
        guard force || activatedId != currentId else { return }
        activatedId = currentId
        loadTask?.cancel()
        controller.stop()
        owner = nil
        guard let row = current else { return }
        if case .feed = source, let index = items.firstIndex(where: { $0.id == row.id }),
           index >= items.count - 4, !store.feed(model.pnvRegion).isDone {
            Task { await store.loadMore(region: model.pnvRegion) }
        }
        guard row.isVideo else { phase = .ready; return }
        phase = .loading
        let key = row.id
        loadTask = Task {
            do {
                // A flick past a page is not a visit: only a page still current after a moment
                // asks for its stream (a Khajistan TV row mints a token per ask).
                try await Task.sleep(for: .milliseconds(250))
                let url = try await store.playableURL(for: row)
                try Task.checkCancellation()
                guard currentId == key else { return }
                // Weak: the controller stores this closure, so a strong capture keeps the player.
                controller.onEnded = { [weak controller] in
                    guard let controller else { return }
                    // A Khajistan TV programme ends rather than looping, and says it is stopped.
                    guard !row.isKtv else { controller.pause(); return }
                    // Loops in place: resume() would tune again, flashing the still and fading in.
                    controller.player.seek(to: .zero)
                    controller.player.play()
                }
                controller.attach(url: url, seekTo: nil, title: "@" + store.accountHandle(for: row),
                                  subtitle: "Khajistan", isLive: false, fadeIn: false)
                // A clip loops without its item ending, so the rate never drops and the reel never
                // reads as tuning again (a dip to .tuning flashed the still and the spinner). A
                // Khajistan TV programme ends.
                controller.player.actionAtItemEnd = row.isKtv ? .pause : .none
                // The viewer's own setting for video that starts by itself (Settings > Accessibility
                // > Motion); with it off the reel waits for the rail's Play.
                if !UIAccessibility.isVideoAutoplayEnabled { controller.pause() }
                owner = key
                phase = .ready
            } catch PnvPlaybackError.needsSignIn {
                if !Task.isCancelled { phase = .needsSignIn }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// For VoiceOver and Switch Control, which cannot page by swiping (WCAG 2.5.1).
    private func step(_ delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == currentId }) else { return }
        let next = index + delta
        guard items.indices.contains(next) else { return }
        withAnimation(.kj) { position = items[next].id }
    }
}

/// One reel: the object, and over it the rail and the caption. Only the current page holds the
/// player; the others show their still, so a page scrolled past costs no decoding.
private struct PnvReelPage: View {
    let row: PnvRow
    let isCurrent: Bool
    let ownsPlayer: Bool
    let controller: PlayerController
    let phase: PnvReelsView.Phase
    /// The screen's safe area, which the full-bleed pager cannot read for itself.
    let insets: EdgeInsets
    let signIn: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var caption: String?
    @State private var note: String?
    @State private var naming = false
    @State private var newName = ""
    /// Set once this page's video has shown a frame: from then the reel stays black around the
    /// picture through a pause or a loop, rather than flashing back to the still.
    @State private var hasPlayed = false
    @State private var showLoader = false

    private var store: PicsVidsStore { model.pnv }
    /// Waiting for a first frame. The loader shows only once that wait passes 600 ms: most reels
    /// arrive sooner, and a spinner on every swipe is not how a reel feels.
    private var waiting: Bool {
        isCurrent && row.isVideo && !hasPlayed && (phase == .loading || controller.state == .tuning)
    }

    var body: some View {
        ZStack {
            // The one black in the app is around a moving picture (the Receiver's letterbox rule).
            // Black once played, until the page leaves the screen: the page swiped away keeps its
            // last look while it slides off rather than flashing to the ground and its still.
            (hasPlayed ? Color.black : palette.ground)
            // The still also covers a played page sliding off, whose player has already moved on:
            // its own picture on black rather than an empty black screen.
            if !hasPlayed || !ownsPlayer {
                PnvPicture(urls: row.isVideo ? [PnvMedia.poster(row), PnvMedia.thumb(row)].compactMap { $0 }
                                             : PnvMedia.pictureCandidates(row),
                           aspect: row.aspect, maxPixel: 1600, cornerRadius: 0, releaseOnDisappear: true)
            }
            // Over the still: an AVPlayerLayer with no frame yet is clear, so the still shows
            // through until the first frame lands.
            if ownsPlayer { PlayerLayerView(player: controller.player).allowsHitTesting(false) }
            if showLoader && waiting { TuningLoader("Loading\u{2026}") }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if ownsPlayer { controller.toggle() } }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    details
                    Spacer(minLength: 0)
                    rail
                }
                .padding(.horizontal, KJLayout.inset)
                .padding(.bottom, insets.bottom + 12)
            }
        }
        .onChange(of: controller.state) { if ownsPlayer && controller.state == .playing { hasPlayed = true } }
        .onDisappear { hasPlayed = false }
        .task(id: waiting) {
            showLoader = false
            guard waiting else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { showLoader = true }
        }
        // Only the reel on screen asks for its caption: the stack builds its neighbours too.
        .task(id: isCurrent ? row.id : "") { if isCurrent, caption == nil { caption = await store.caption(for: row) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reel-\(row.media_key)")
    }

    // MARK: - Bottom left

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("@" + store.accountHandle(for: row)).kjName(.headline).lineLimit(1)
            Text(PnvAPI.metaLine(for: row, regionToken: store.regionToken(for: row), date: Self.dateText, showsSize: false))
                .kjSmall().lineLimit(2)
            if let caption, !caption.isEmpty { Text(caption).kjSmall(faint: true).lineLimit(3) }
            if isCurrent { stateLine }
            if let note { Text(note).kjSmall(faint: true).accessibilityIdentifier("pnvSaveNote") }
        }
        .padding(12)
        .background(palette.ground.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private var stateLine: some View {
        switch phase {
        case .needsSignIn:
            Button(kicker: "Sign in to watch") { signIn() }
                .buttonStyle(HouseButtonStyle(solid: true))
                .accessibilityIdentifier("pnvSignIn")
        case .failed(let message):
            Kicker(message).accessibilityIdentifier("pnvViewerState")
        default:
            if row.isVideo, case .failed(let message) = controller.state {
                Kicker(message).accessibilityIdentifier("pnvViewerState")
            }
        }
    }

    // MARK: - Right rail

    private var rail: some View {
        VStack(spacing: 14) {
            if ownsPlayer && phase == .ready {
                railButton(controller.state == .playing ? "pause.fill" : "play.fill",
                           label: controller.state == .playing ? "Pause" : "Play", id: "pnvPlayPause") { controller.toggle() }
            }
            saveButton
            if model.saves.canSave && PassportSaves.pnvRef(row.media_key) != nil { collectionMenu }
        }
    }

    private func railButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(.title3, weight: .semibold)).frame(width: 48, height: 48)
        }
        .buttonStyle(ReelRailStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Save, as the website's heart: on the account, nothing of the object kept beside its key.
    private var saveButton: some View {
        let saved = model.saves.isSaved(pnvKey: row.media_key)
        return railButton(saved ? "bookmark.fill" : "bookmark", label: saved ? "Saved" : "Save", id: "pnvSave") {
            guard model.saves.canSave else { note = "Sign in under \(KJConfig.signInDoor) to save to your account."; return }
            Task {
                await model.saves.load()
                note = await model.saves.toggle(pnvKey: row.media_key) ? nil : "That did not save. Try again."
            }
        }
        .accessibilityValue(saved ? "On" : "Off")
        .disabled(PassportSaves.pnvRef(row.media_key) == nil)
    }

    /// The account's collections, ticked where this object is in one, and a new one made with it.
    private var collectionMenu: some View {
        let key = row.media_key
        return Menu {
            ForEach(model.saves.collections) { collection in
                Button {
                    Task { note = await model.saves.toggle(pnvKey: key, in: collection.id) ? nil : "That did not save. Try again." }
                } label: {
                    if collection.media_keys.contains(key) { Label(collection.name, systemImage: "checkmark") } else { Text(collection.name) }
                }
            }
            if !model.saves.collections.isEmpty { Divider() }
            Button { newName = ""; naming = true } label: { Label("New collection\u{2026}", systemImage: "plus") }
                .accessibilityIdentifier("pnvNewCollection")
        } label: {
            Image(systemName: "folder.badge.plus").font(.system(.title3, weight: .semibold)).frame(width: 48, height: 48)
        }
        .buttonStyle(ReelRailStyle())
        .accessibilityLabel("Collection")
        .accessibilityIdentifier("pnvCollection")
        .alert("New collection", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Make") {
                let name = newName
                Task {
                    note = await model.saves.createCollection(name: name, keys: [key]) == nil
                        ? "That did not save. A name of 1 to 120 characters is needed." : nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It holds this object; add more from their reels.")
        }
    }

    private static func dateText(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

/// A round plate in the ground colour behind a rail icon, so it reads over any picture. A press
/// turns it to the band, as every house control does.
private struct ReelRailStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? palette.onBand : palette.ink)
            .background(configuration.isPressed ? palette.band : palette.ground.opacity(0.9), in: Circle())
            .contentShape(Circle())
    }
}
