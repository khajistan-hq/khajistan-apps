import SwiftUI

/// Pics/Vids as reels (owner, 2026-11-08: "they need to be like reels and grid to make the
/// interaction better"). One object a screen, a swipe up for the next and down for the one
/// before, as a phone's short-video feed moves. A video plays when its page settles and loops; a
/// tap pauses it. Save and Collection stay on the right rail, the account and the caption at the
/// bottom left, so nothing waits behind a tap. A picture is fitted whole, never cropped.
///
/// The stream's reel never ends: when its feed has given every object, the reel deals the same
/// objects again in a new order and carries on. The region and Shuffle sit at the top, over the
/// reel, and change it in place (owner, 2026-11-14: "an infinite reel option wired to the region
/// with shuffle button and all regions or specific region options").
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
    /// The extra rounds dealt once the feed ran out, each the feed again in a new order.
    @State private var laps: [[PnvRow]] = []

    let start: PnvRow
    let source: Source

    init(start: PnvRow, source: Source = .feed) {
        self.start = start
        self.source = source
        // Seeded before the first paint, so a deep tile never shows the first reel for a frame;
        // the scrollTo on arrival corrects a lazy stack that lands a page off.
        _position = State(initialValue: ReelItem.id(lap: 0, start.id))
        if case .rows(let rows) = source { _fixed = State(initialValue: rows) } else { _fixed = State(initialValue: []) }
    }

    private var store: PicsVidsStore { model.pnv }

    private var items: [PnvRow] {
        switch source {
        case .feed: return store.feed(model.pnvRegion).items
        case .rows: return fixed
        }
    }

    /// The pages: the feed, then each lap after it. A page's id carries its lap, so the same
    /// object dealt twice is two pages.
    private var reel: [ReelItem] {
        ([items] + laps).enumerated().flatMap { lap, rows in rows.map { ReelItem(lap: lap, row: $0) } }
    }

    private var isStream: Bool { if case .feed = source { return true } else { return false } }
    private var currentId: String { position ?? ReelItem.id(lap: 0, start.id) }
    private var current: PnvRow? { reel.first { $0.id == currentId }?.row }

    var body: some View {
        let palette = Palette(model.skin)
        // Read outside the full-bleed pager: inside it the safe area is zero, and the rail would sit
        // on the home indicator.
        GeometryReader { outer in
        let insets = outer.safeAreaInsets
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(reel) { item in
                    let row = item.row
                    PnvReelPage(row: row, isCurrent: item.id == currentId, ownsPlayer: owner == item.id,
                                controller: controller, phase: phase, insets: insets,
                                signIn: { showSignIn = true })
                        .containerRelativeFrame([.horizontal, .vertical])
                        // Only the reel on screen is read: a built neighbour's Save is not reachable
                        // off screen. Set here, where the current page is always known.
                        .accessibilityHidden(item.id != currentId)
                        .id(item.id)
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
        .onAppear { proxy.scrollTo(ReelItem.id(lap: 0, start.id), anchor: .top) }
        // On the pager itself, not the screen: on the screen it also renamed the Close button.
        .accessibilityIdentifier("pnvReels")
        // The account, which VoiceOver reads; the page's own identifier carries the key for tests.
        .accessibilityValue(current.map { "@" + store.accountHandle(for: $0) } ?? "")
        .accessibilityActions {
            Button("Next") { step(1) }
            Button("Previous") { step(-1) }
        }
        .overlay(alignment: .top) { topBar }
        .overlay { if items.isEmpty { emptyState } }
        }
        }
        .background(palette.ground.ignoresSafeArea())
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .statusBarHidden()
        .onAppear { activate() }
        .task { await model.saves.load() }
        .onChange(of: position) { activate() }
        // A new region or a new deal empties the feed: the reel waits, then opens on its first page.
        .task(id: "\(model.pnvRegion)|\(store.deal)") {
            guard isStream else { return }
            if store.feed(model.pnvRegion).isUntouched { await store.loadMore(region: model.pnvRegion) }
        }
        .onChange(of: items.first?.id) { reopenIfLost() }
        .onDisappear { loadTask?.cancel(); controller.stop() }
        .sheet(isPresented: $showSignIn) { SignInView(model: model, onSignedIn: { activate(force: true) }) }
        // A keyboard or a trackpad pages too: a drag does not page a scroll view on the Mac.
        .focusable()
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
    }

    /// Close on the left; on a stream, the region and Shuffle on the right. Plates in the ground
    /// colour, as the rail's are, so they read over any picture.
    private var topBar: some View {
        HStack(spacing: 10) {
            Button { controller.stop(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(.body, weight: .bold)).frame(width: 44, height: 44)
            }
            .buttonStyle(ReelRailStyle())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("closePlayer")
            Spacer(minLength: 0)
            if isStream {
                regionMenu
                Button { deal(shuffled: !store.shuffled) } label: {
                    Image(systemName: "shuffle").font(.system(.body, weight: .bold)).frame(width: 44, height: 44)
                }
                .buttonStyle(ReelRailStyle(isOn: store.shuffled))
                .accessibilityLabel("Shuffle")
                .accessibilityValue(store.shuffled ? "On" : "Off")
                .accessibilityHint(store.shuffled ? "Deals the reel again. Hold for the stream's own order." : "")
                .accessibilityIdentifier("pnvReelShuffle")
                .contextMenu {
                    if store.shuffled {
                        Button("Deal again", systemImage: "shuffle") { deal(shuffled: true) }
                        Button("Stream order", systemImage: "list.bullet") { deal(shuffled: false) }
                    }
                }
            }
        }
        .padding(.horizontal, KJLayout.inset - 6)
        .padding(.top, 6)
    }

    /// All regions, or one: the same filter as the grid's chips, so the grid follows the reel.
    private var regionMenu: some View {
        Menu {
            Picker("Region", selection: Binding(get: { model.pnvRegion }, set: { change(region: $0) })) {
                Text("All regions").tag(PicsVidsStore.allRegions)
                ForEach(store.regions, id: \.self) { Text(PnvRegions.label($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                // The grid's chip type, so the one filter reads the same in both places.
                Text(model.pnvRegion.isEmpty ? "All regions" : PnvRegions.label(model.pnvRegion))
                    .font(.system(.subheadline, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(.caption, weight: .bold))
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .buttonStyle(ReelRailStyle(shape: .capsule))
        .accessibilityLabel("Region")
        .accessibilityValue(model.pnvRegion.isEmpty ? "All regions" : PnvRegions.label(model.pnvRegion))
        .accessibilityIdentifier("pnvReelRegion")
    }

    /// While a new region or deal has nothing yet: the loader, or what went wrong.
    @ViewBuilder
    private var emptyState: some View {
        let feed = store.feed(model.pnvRegion)
        if let error = feed.error {
            VStack(spacing: 12) {
                Text(error).kjBody()
                Button(kicker: "Try again") { Task { await store.retry(region: model.pnvRegion) } }
                    .buttonStyle(HouseButtonStyle(solid: true))
            }
        } else if feed.isDone {
            Text("Nothing filed under this yet.").kjBody()
        } else {
            TuningLoader("Loading\u{2026}")
        }
    }

    private func change(region: String) {
        guard region != model.pnvRegion else { return }
        restart { model.pnvRegion = region }
    }

    private func deal(shuffled: Bool) {
        restart { store.setShuffled(shuffled) }
    }

    /// Stops what is playing and empties the reel; it reopens on the new feed's first page.
    private func restart(_ change: () -> Void) {
        loadTask?.cancel()
        controller.stop()
        owner = nil
        activatedId = nil
        laps = []
        change()
        // No page is current until the new feed has one: reopenIfLost() then opens on it, here
        // if the feed is already loaded, or when its first page arrives.
        position = ""
        reopenIfLost()
    }

    /// The page on screen left the reel (a new region, a new deal): open on the first page.
    private func reopenIfLost() {
        guard isStream, let first = items.first, current == nil else { return }
        position = ReelItem.id(lap: 0, first.id)
        activate()
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
        let pages = reel
        if isStream, let index = pages.firstIndex(where: { $0.id == currentId }), index >= pages.count - 4 {
            if store.feed(model.pnvRegion).isDone {
                // The feed has given everything: deal it again, so the reel never ends.
                if !items.isEmpty { laps.append(items.shuffled()) }
            } else {
                Task { await store.loadMore(region: model.pnvRegion) }
            }
        }
        guard row.isVideo else { phase = .ready; return }
        phase = .loading
        let key = currentId
        loadTask = Task { [controller] in
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
        let pages = reel
        guard let index = pages.firstIndex(where: { $0.id == currentId }) else { return }
        let next = index + delta
        guard pages.indices.contains(next) else { return }
        withAnimation(.kj) { position = pages[next].id }
    }
}

/// One page of the reel: an object, and the round it was dealt in.
private struct ReelItem: Identifiable {
    let lap: Int
    let row: PnvRow
    var id: String { Self.id(lap: lap, row.id) }
    static func id(lap: Int, _ key: String) -> String { "\(lap)|\(key)" }
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
            // The rail and the caption belong to the reel on screen only. A neighbour the lazy
            // stack has built carries no controls, so VoiceOver, a test, or a stray tap can never
            // reach a Save that is off screen (hiding them was not enough: they stayed in the tree).
            if isCurrent {
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
                .transition(.opacity)
            }
        }
        .animation(.kj, value: isCurrent)
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
/// `isOn` holds it on the band, as a switch that is on: Shuffle while the reel is shuffled.
private struct ReelRailStyle: ButtonStyle {
    enum Shape { case circle, capsule }
    var isOn = false
    var shape: Shape = .circle
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let lit = isOn || configuration.isPressed
        let fill = lit ? palette.band : palette.ground.opacity(0.9)
        return configuration.label
            .foregroundStyle(lit ? palette.onBand : palette.ink)
            .environment(\.palette, lit ? palette.onBandPlate : palette)
            .background { if shape == .circle { Circle().fill(fill) } else { Capsule().fill(fill) } }
            .contentShape(shape == .circle ? AnyShape(Circle()) : AnyShape(Capsule()))
            .animation(.kj, value: isOn)
    }
}
