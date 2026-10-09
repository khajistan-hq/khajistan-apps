import SwiftUI

/// One Pics/Vids object, full screen (ported from the Apple TV app). A picture is fitted whole,
/// never cropped; a video plays and loops as a reel does; a Khajistan TV row needs the account
/// tv-play asks for, and the sign-in sheet takes it in place. A swipe left or right moves through
/// the stream, loading the next page at its end; a tap wakes the overlay.
struct PnvViewerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: PnvRow
    @State private var controller = PlayerController()
    @State private var overlay = OverlayClock()
    @State private var picture: UIImage?
    @State private var phase: Phase = .loading
    @State private var caption: String?
    @State private var showSignIn = false
    @State private var loadTask: Task<Void, Never>?
    @State private var stepTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case loading, ready, needsSignIn
        case failed(String)
    }

    /// False when opened from a chat line: the object is not in a feed, so there is no next.
    private let steps: Bool

    init(row: PnvRow, steps: Bool = true) {
        _current = State(initialValue: row)
        self.steps = steps
    }

    private var store: PicsVidsStore { model.pnv }

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            (current.isVideo && controller.state == .playing ? Color.black : palette.ground).ignoresSafeArea()
            if let picture, !(current.isVideo && controller.state == .playing) {
                Image(uiImage: picture).resizable().aspectRatio(contentMode: .fit).transition(.opacity)
            }
            if current.isVideo { PlayerLayerView(player: controller.player) }
            if isWaiting { TuningLoader("Loading\u{2026}") }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { overlay.toggle(settled: settled) }
                .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                    step(by: dx < 0 ? 1 : -1)
                })
            chrome(palette)
                .opacity(overlay.visible ? 1 : 0)
                .allowsHitTesting(overlay.visible)
        }
        .animation(.easeOut(duration: 0.22), value: picture)
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .statusBarHidden(!overlay.visible)
        .onChange(of: phase) { overlay.wake(settled: settled) }
        .onChange(of: controller.state) { overlay.wake(settled: settled) }
        .task { show(current) }
        .onDisappear { stopEverything() }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { show(current) })
        }
        .accessibilityActions {
            if steps {
                Button("Next") { step(by: 1) }
                Button("Previous") { step(by: -1) }
            }
        }
    }

    private var isWaiting: Bool {
        switch phase {
        case .loading: return picture == nil
        case .ready: return current.isVideo && controller.state == .tuning && picture == nil
        case .needsSignIn, .failed: return false
        }
    }

    private var settled: Bool {
        phase == .ready && (!current.isVideo || controller.state == .playing)
    }

    // MARK: - Overlay

    private func chrome(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            PlayerTopBar(leading: ["Khajistan Pics/Vids", "@" + store.accountHandle(for: current)],
                         trailing: [current.isVideo ? "Video" : "Picture"]) {
                stopEverything()
                dismiss()
            }
            Spacer(minLength: 0)
            panel.background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let state = stateText { Kicker(state).accessibilityIdentifier("pnvViewerState") }
            Text(PnvAPI.metaLine(for: current, regionToken: store.regionToken(for: current), date: Self.dateText)).kjSmall()
            if let caption { Text(caption).kjSmall(faint: true).lineLimit(4) }
            if phase == .needsSignIn {
                Button(kicker: "Sign in") { showSignIn = true }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .accessibilityIdentifier("pnvSignIn")
            } else if current.isVideo && phase == .ready {
                TransportRow(isPlaying: controller.state == .playing, toggle: { controller.toggle() })
            }
            // Buttons as well as the swipe, for a viewer who cannot swipe (WCAG 2.5.1).
            if steps {
                HStack(spacing: 4) {
                    Button { step(by: -1) } label: { Text("Previous").kjKicker() }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 18)))
                        .accessibilityIdentifier("pnvPrevious")
                    Button { step(by: 1) } label: { Text("Next").kjKicker() }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 18)))
                        .accessibilityIdentifier("pnvNext")
                }
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let key = row.id
        loadTask = Task {
            Task { @MainActor in
                let text = await store.caption(for: row)
                if current.id == key { caption = text }
            }
            if row.isVideo {
                await playVideo(row)
            } else {
                let image = await PnvImages.shared.image(PnvMedia.pictureCandidates(row), maxPixel: 2000)
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

    private func playVideo(_ row: PnvRow) async {
        let key = row.id
        Task { @MainActor in
            let still = await PnvImages.shared.image([PnvMedia.poster(row), PnvMedia.thumb(row)].compactMap { $0 }, maxPixel: 2000)
            if current.id == key, picture == nil { picture = still }
        }
        do {
            let url = try await store.playableURL(for: row)
            try Task.checkCancellation()
            guard current.id == key else { return }
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

    private func step(by delta: Int) {
        guard steps else { return }
        stepTask?.cancel()
        stepTask = Task {
            let region = model.pnvRegion
            guard var index = store.feed(region).items.firstIndex(where: { $0.id == current.id }) else { return }
            index += delta
            if index >= store.feed(region).items.count && !store.feed(region).isDone { await store.loadMore(region: region) }
            let items = store.feed(region).items
            guard !Task.isCancelled, items.indices.contains(index) else { return }
            show(items[index])
        }
    }

    private func stopEverything() {
        loadTask?.cancel()
        stepTask?.cancel()
        overlay.stop()
        controller.stop()
    }
}
