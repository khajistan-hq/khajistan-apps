import SwiftUI

/// One issue, a page at a time, full screen on the house ground. Right turns to the next page and left
/// to the one before; Select zooms to 2x and the remote moves the page under the screen; Select again
/// zooms out, and Menu zooms out first and leaves second. The next page is fetched while this one is read.
///
/// The page server decides what a viewer may read, and what it answers is what is shown: a page, a
/// sign-in for a free title, the membership gate for a paid one, the rights-held note (451), or the
/// page's absence. A page the site puts behind a content warning is held behind the same sentence.
struct ReadingReaderView: View {
    let title: RRTitle
    let issue: RRIssue

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var pages: Int
    @State private var map: [Int]?
    @State private var position = 1
    @State private var shown: UIImage?
    @State private var phase: Phase = .loading
    @State private var zoomed = false
    @State private var pan: CGSize = .zero
    @State private var screen: CGSize = CGSize(width: 1920, height: 1080)
    @State private var flags: [String: [String]] = [:]
    @State private var revealed = false
    /// The first page this viewer was refused for want of an account or the pass.
    @State private var blockedFrom: Int?
    @State private var overlayVisible = true
    @State private var showSignIn = false
    @State private var loadTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case loading
        case page
        case gate(RRPageOutcome)
        case curtain([String])
    }

    private static let zoomFactor: CGFloat = 2
    private static let panStep: CGFloat = 240

    init(title: RRTitle, issue: RRIssue) {
        self.title = title
        self.issue = issue
        _pages = State(initialValue: max(issue.pages, 1))
    }

    private var store: ReadingStore { model.reading }

    var body: some View {
        ZStack {
            // The page runs to the screen's edges; everything that is read stays inside the safe area,
            // where a control's plate cannot run off the glass.
            GeometryReader { geometry in
                ZStack {
                    palette.ground
                    if let shown, phase == .page || phase == .loading {
                        Image(uiImage: shown)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(zoomed ? Self.zoomFactor : 1)
                            .offset(pan)
                            .animation(.easeOut(duration: 0.2), value: zoomed)
                            .animation(.easeOut(duration: 0.15), value: pan)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear { screen = geometry.size }
                .onChange(of: geometry.size) { screen = geometry.size }
            }
            .ignoresSafeArea()
            if phase == .loading && shown == nil {
                Kicker("Loading\u{2026}")
            }
            content
            overlay
            if usesSurface {
                // The focus target: it draws nothing and holds focus so the remote's presses land.
                Button {
                    select()
                } label: {
                    Color.clear
                }
                .buttonStyle(SurfaceButtonStyle())
                .accessibilityIdentifier("rrReaderSurface")
                .accessibilityValue(stateValue)
            }
        }
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            if zoomed {
                panBy(direction)
                return
            }
            switch direction {
            case .left: step(by: -1)
            case .right: step(by: 1)
            default: break
            }
        }
        .onExitCommand {
            if zoomed {
                zoomOut()
            } else {
                loadTask?.cancel()
                hideTask?.cancel()
                dismiss()
            }
        }
        .onChange(of: phase) { wake() }
        .task { await open() }
        .onDisappear {
            loadTask?.cancel()
            hideTask?.cancel()
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: { retryAfterSignIn() })
        }
    }

    // MARK: - What stands on the page

    /// Gates that carry their own buttons take focus themselves; every other state has the surface.
    private var usesSurface: Bool {
        switch phase {
        case .loading, .page: return true
        case .curtain: return false
        case .gate(let outcome):
            switch outcome {
            case .signIn, .members, .unavailable: return false
            default: return true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading, .page:
            EmptyView()
        case .curtain(let found):
            curtain(found)
        case .gate(let outcome):
            gate(outcome)
        }
    }

    private func panel<Stack: View>(@ViewBuilder _ body: () -> Stack) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            body()
        }
        .kjBody()
        .frame(maxWidth: 1200, alignment: .leading)
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 150)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.ground)
    }

    /// The website's curtain (rrSensitiveGate): what the page shows, in plain words, and the page on request.
    private func curtain(_ found: [String]) -> some View {
        panel {
            Text(RRSensitive.sentence(found)).kjName(44).accessibilityIdentifier("rrCurtain")
            Button {
                revealed = true
                show(position)
            } label: {
                Text("Show the page").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .padding(.leading, -26)
            .accessibilityIdentifier("rrReveal")
        }
    }

    @ViewBuilder
    private func gate(_ outcome: RRPageOutcome) -> some View {
        switch outcome {
        case .signIn:
            let words = RRWords.accountGate(titleName: title.name, issueLabel: issue.label, pages: pages)
            panel {
                Text(words.heading).kjName(44).accessibilityIdentifier("rrGateTitle")
                Text(words.text).accessibilityIdentifier("rrGateText")
                Button {
                    showSignIn = true
                } label: {
                    Text(RRWords.signInDoor).kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
                .accessibilityIdentifier("rrGateSignIn")
                backToPreview
            }
        case .members:
            let words = RRWords.membersGate(titleName: title.name, issueLabel: issue.label, pages: pages)
            panel {
                Text(words.heading).kjName(44).accessibilityIdentifier("rrGateTitle")
                Text(words.text).accessibilityIdentifier("rrGateText")
                HStack(alignment: .top, spacing: 60) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !model.auth.isSignedIn {
                            Button {
                                showSignIn = true
                            } label: {
                                Text("Already a member? Sign in").kjKicker()
                            }
                            .buttonStyle(HouseButtonStyle())
                            .padding(.leading, -26)
                            .accessibilityIdentifier("rrGateSignIn")
                        }
                        backToPreview
                    }
                    siteLine
                }
            }
        case .closed:
            panel {
                Text(RRWords.residencyHeading).kjName(44)
                Text(RRWords.residencyText)
            }
        case .rights:
            panel {
                Text(RRWords.rightsHeading).kjName(44)
                Text(RRWords.rightsBody(issueCount: title.issues.count, khajistanScanned: store.isKhajistanScanned(title)))
            }
        case .missing:
            panel {
                Text(RRWords.missingPage(position)).kjName(44).accessibilityIdentifier("rrMissing")
            }
        case .unavailable:
            panel {
                Text("This page could not load.").kjName(44)
                Button {
                    show(position)
                } label: {
                    Text("Try again").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
                .accessibilityIdentifier("rrTryAgain")
            }
        case .page:
            EmptyView()
        }
    }

    private var backToPreview: some View {
        Button {
            show(max(1, (blockedFrom ?? 2) - 1))
        } label: {
            Text("\u{2190} Back to free preview").kjKicker()
        }
        .buttonStyle(HouseButtonStyle())
        .padding(.leading, -26)
        .accessibilityIdentifier("rrBackToPreview")
    }

    /// Where membership is taken, named in plain text. No code and no link: on the TV a reader
    /// app may not send a viewer out to buy (owner, 2026-10-06).
    private var siteLine: some View {
        Kicker("khajistan.com").accessibilityIdentifier("rrSiteLine")
    }

    /// Where the reader stands, for the UI test that turns pages: "3/76|page", with "|zoom" while zoomed.
    private var stateValue: String {
        let name: String
        switch phase {
        case .loading: name = "loading"
        case .page: name = "page"
        case .gate: name = "gate"
        case .curtain: name = "curtain"
        }
        return "\(position)/\(pages)|\(name)" + (zoomed ? "|zoom" : "")
    }

    // MARK: - The band

    private var overlay: some View {
        VStack(spacing: 0) {
            StatusBand(leading: bandLeading, trailing: [pageLabel])
            Spacer(minLength: 0)
        }
        .opacity(overlayVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: overlayVisible)
        .allowsHitTesting(false)
    }

    private var bandLeading: [String] {
        var items = ["Khajistan Reading Room", title.name]
        if title.issues.count > 1, !issue.label.isEmpty { items.append(issue.label) }
        return items
    }

    /// "p. 3 / 76", or the website's "Preview — 2 of 76 pages" at a gate.
    private var pageLabel: String {
        if let blocked = blockedFrom, position >= blocked {
            return "Preview \u{2014} \(max(blocked - 1, 0)) of \(pages) pages"
        }
        return (zoomed ? "2\u{00D7} \u{00B7} " : "") + "p. \(position) / \(pages)"
    }

    // MARK: - Opening and turning

    private func open() async {
        async let numbers = store.pageMap(issue)
        async let own = store.warnings(for: issue.slug)
        async let card = title.slug == issue.slug ? [:] : store.warnings(for: title.slug)
        let resolved = await numbers
        pages = max(resolved.pages, 1)
        map = resolved.map
        flags = await own.merging(await card) { first, _ in first }
        show(1)
    }

    private func show(_ target: Int) {
        loadTask?.cancel()
        position = min(max(1, target), pages)
        zoomed = false
        pan = .zero
        let at = position
        let stored = RRPageMap.stored(at, map: map)
        if let warned = flags[store.endpoint(issue, page: stored)], !revealed {
            shown = nil
            phase = .curtain(warned)
            return
        }
        phase = .loading
        loadTask = Task {
            let result = await store.page(issue, stored: stored)
            guard !Task.isCancelled, position == at else { return }
            switch result {
            case .image(let image):
                shown = image
                phase = .page
                if let blocked = blockedFrom, at >= blocked { blockedFrom = nil }
                prefetchNext(after: at)
            case .outcome(let outcome):
                shown = nil
                phase = .gate(outcome)
                if outcome == .members || outcome == .signIn || outcome == .closed {
                    blockedFrom = min(blockedFrom ?? at, at)
                }
            }
        }
    }

    /// The next page is signed and fetched while this one is read, unless it is behind a gate or a curtain.
    private func prefetchNext(after at: Int) {
        let next = at + 1
        guard next <= pages, blockedFrom.map({ next < $0 }) ?? true else { return }
        let stored = RRPageMap.stored(next, map: map)
        if flags[store.endpoint(issue, page: stored)] != nil && !revealed { return }
        Task { await store.prefetch(issue, stored: stored) }
    }

    private func step(by delta: Int) {
        let target = position + delta
        guard target >= 1, target <= pages else { return }
        // A page past the gate is not asked for: the website walks a viewer to the gate and no further.
        if delta > 0, let blocked = blockedFrom, position >= blocked { return }
        show(target)
    }

    private func retryAfterSignIn() {
        blockedFrom = nil
        show(position)
    }

    // MARK: - Zoom

    private func select() {
        wake()
        guard phase == .page else { return }
        if zoomed {
            zoomOut()
        } else {
            zoomed = true
            pan = .zero
        }
    }

    private func zoomOut() {
        zoomed = false
        pan = .zero
    }

    /// The remote moves the page under the screen: right shows what lies to the right, and the page stops at its edge.
    private func panBy(_ direction: MoveCommandDirection) {
        var next = pan
        switch direction {
        case .left: next.width += Self.panStep
        case .right: next.width -= Self.panStep
        case .up: next.height += Self.panStep
        case .down: next.height -= Self.panStep
        @unknown default: return
        }
        let limit = panLimit
        pan = CGSize(width: min(max(next.width, -limit.width), limit.width),
                     height: min(max(next.height, -limit.height), limit.height))
    }

    /// How far the zoomed page may move: half of what its fitted size, doubled, leaves outside the screen.
    private var panLimit: CGSize {
        guard let image = shown, image.size.width > 0, image.size.height > 0 else { return .zero }
        let fit = min(screen.width / image.size.width, screen.height / image.size.height)
        let width = image.size.width * fit * Self.zoomFactor
        let height = image.size.height * fit * Self.zoomFactor
        return CGSize(width: max(0, (width - screen.width) / 2), height: max(0, (height - screen.height) / 2))
    }

    // MARK: - The band's hours

    /// Shows the band. Once a page is showing it hides again after 2.6 seconds without a press; at a gate
    /// or a curtain it stays, because that is what there is to read.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        guard phase == .page else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { overlayVisible = false }
        }
    }
}
