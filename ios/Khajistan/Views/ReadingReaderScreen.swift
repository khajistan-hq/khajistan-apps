import SwiftUI
import UIKit

/// One issue, a scanned page at a time, on the house ground. Pinch or double-tap zooms (to 6x, the
/// website's ceiling) and pans the page as stored; a swipe turns it when the page is not zoomed,
/// in the issue's own direction (RRDirection, the website's rule): in a right-to-left issue the
/// next page lies to the left. The arrow keys, the page buttons and the page slider turn it too.
///
/// The page server decides what this viewer may read and its answer is what is shown: a page, a
/// sign-in for a free title, the membership note for a paid one, the rights-held note, or the
/// page's absence. A page the site holds behind a content warning stays behind its sentence until
/// the reader asks to see it. Where reading stopped is kept on this device by title and issue.
struct ReadingReaderScreen: View {
    let title: RRTitle
    let issue: RRIssue
    let startPage: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var pages: Int
    @State private var map: [Int]?
    @State private var position = 1
    @State private var shown: UIImage?
    @State private var phase: Phase = .loading
    @State private var zoomed = false
    @State private var flags: [String: [String]] = [:]
    @State private var revealed = false
    /// The first page this viewer was refused for want of an account or a pass.
    @State private var blockedFrom: Int?
    @State private var showSignIn = false
    @State private var sliderPage: Double = 1
    @State private var loadTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case loading, page
        case gate(RRPageOutcome)
        case curtain([String])
    }

    init(title: RRTitle, issue: RRIssue, startPage: Int = 1) {
        self.title = title
        self.issue = issue
        self.startPage = startPage
        _pages = State(initialValue: max(issue.pages, 1))
    }

    private var store: ReadingStore { model.reading }
    private var rightToLeft: Bool { RRDirection.isRightToLeft(title, issue) }

    var body: some View {
        HStack(spacing: 0) {
            // A wide screen keeps the issue's pages beside the one being read.
            if sizeClass == .regular && pages > 1 {
                PageRail(issue: issue, pages: pages, map: map, current: position) { show($0) }
                    .frame(width: 132)
            }
            reader
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await open() }
        .onDisappear { loadTask?.cancel() }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { retryAfterSignIn() })
        }
    }

    private var reader: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                palette.ground
                if let shown, phase == .page || phase == .loading {
                    ZoomablePage(image: shown, zoomed: $zoomed)
                        .id(position)
                        .accessibilityElement()
                        .accessibilityLabel("Page \(position) of \(pages)")
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: step(by: 1)
                            case .decrement: step(by: -1)
                            @unknown default: break
                            }
                        }
                        .accessibilityIdentifier("rrReaderPage")
                }
                if phase == .loading && shown == nil { Kicker("Loading\u{2026}") }
                stateOverlay
            }
            .contentShape(Rectangle())
            .gesture(turnGesture, including: zoomed ? .subviews : .all)
            bottomBar
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.name).kjName().lineLimit(1)
                if title.issues.count > 1, !issue.label.isEmpty { Text(issue.label).kjSmall(faint: true).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Button(kicker: "Close") { close() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("rrReaderClose")
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if pages > 1 {
                PageScrubber(page: $sliderPage, pages: pages, rightToLeft: rightToLeft) { show(Int(sliderPage)) }
                    .accessibilityIdentifier("rrPageSlider")
            }
            HStack {
                turnButton(towardsLeading: true)
                Spacer()
                Text(pageLabel).kjSmall().monospacedDigit().accessibilityIdentifier("rrPageLabel")
                Spacer()
                turnButton(towardsLeading: false)
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 8)
    }

    /// The button on the left turns back in a left-to-right issue and forward in a right-to-left
    /// one, so the arrow always points where the page goes. The arrow keys follow the same rule.
    private func turnButton(towardsLeading: Bool) -> some View {
        let forward = towardsLeading == rightToLeft
        return Button {
            step(by: forward ? 1 : -1)
        } label: {
            Text(towardsLeading ? "\u{2190}" : "\u{2192}").kjName(KJType.title).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .keyboardShortcut(towardsLeading ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(forward ? !canAdvance : position <= 1)
        .accessibilityLabel(forward ? "Next page" : "Previous page")
        .accessibilityIdentifier(forward ? "rrNext" : "rrPrevious")
    }

    private var canAdvance: Bool {
        guard position < pages else { return false }
        if let blocked = blockedFrom, position >= blocked { return false }
        return true
    }

    /// "p. 3 / 76", or the website's "Preview — 2 of 76 pages" at a gate.
    private var pageLabel: String {
        if let blocked = blockedFrom, position >= blocked {
            return "Preview \u{2014} \(max(blocked - 1, 0)) of \(pages) pages"
        }
        return "p. \(position) / \(pages)"
    }

    /// A horizontal swipe turns the page, in the issue's direction. Only while the page is not
    /// zoomed: a zoomed page pans under the finger instead.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard !zoomed, abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 60 else { return }
                let towardsLeading = value.translation.width > 0  // finger moved right: the left page comes in
                step(by: towardsLeading == rightToLeft ? 1 : -1)
            }
    }

    // MARK: - States over the page

    @ViewBuilder
    private var stateOverlay: some View {
        switch phase {
        case .loading, .page:
            EmptyView()
        case .curtain(let found):
            panel {
                Text(RRSensitive.sentence(found)).kjBody()
                Button(kicker: "Show the page") {
                    revealed = true
                    show(position)
                }
                .accessibilityIdentifier("rrReveal")
            }
        case .gate(let outcome):
            gate(outcome)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(KJLayout.inset)
            .frame(maxWidth: KJLayout.readingWidth, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rrGate")
    }

    @ViewBuilder
    private func gate(_ outcome: RRPageOutcome) -> some View {
        switch outcome {
        case .signIn:
            let words = RRWords.accountGate(titleName: title.name, issueLabel: issue.label, pages: pages)
            panel {
                Text(words.heading).kjName(KJType.title)
                Text(words.text).kjBody()
                Button(kicker: RRWords.signInDoor) { showSignIn = true }.accessibilityIdentifier("rrSignIn")
            }
        case .members:
            let words = RRWords.membersGate(titleName: title.name, issueLabel: issue.label, pages: pages)
            panel {
                Text(words.heading).kjName(KJType.title)
                Text(words.text).kjBody()
                if !model.auth.isSignedIn {
                    Button(kicker: "Sign in") { showSignIn = true }.accessibilityIdentifier("rrSignIn")
                }
                // The website's own page carries its own offer, and is tagged app=1 outside the
                // US storefront so it carries none (JoinOffer).
                Button(kicker: "This page on the website \u{2197}") { openOnWebsite() }
                    .accessibilityIdentifier("rrMembersWebsite")
            }
        case .closed:
            panel {
                Text(RRWords.residencyHeading).kjName(KJType.title)
                Text(RRWords.residencyText).kjBody()
            }
        case .rights:
            panel {
                Text(RRWords.rightsHeading).kjName(KJType.title)
                Text(RRWords.rightsBody(issueCount: title.issues.count, khajistanScanned: store.isKhajistanScanned(title))).kjBody()
            }
        case .missing:
            panel { Text(RRWords.missingPage(position)).kjName(KJType.title).accessibilityIdentifier("rrMissing") }
        case .unavailable:
            panel {
                Text("The page could not be fetched.").kjName(KJType.title)
                Button(kicker: "Try again") { show(position) }.accessibilityIdentifier("rrRetryPage")
            }
        case .page:
            EmptyView()
        }
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
        show(startPage)
    }

    private func show(_ target: Int) {
        loadTask?.cancel()
        position = min(max(1, target), pages)
        sliderPage = Double(position)
        zoomed = false
        let at = position
        let stored = RRPageMap.stored(at, map: map)
        if let warned = flags[store.endpoint(issue, page: stored)], !revealed {
            shown = nil
            phase = .curtain(warned)
            return
        }
        // A page already allowed and in memory is on screen at once; any other turn clears the
        // old page, so a number is never shown over the page before it.
        if let held = store.heldPage(issue, stored: stored) {
            shown = held
            phase = .page
            remember(at)
            prefetchAround(at)
            return
        }
        shown = nil
        phase = .loading
        loadTask = Task {
            let result = await store.page(issue, stored: stored)
            guard !Task.isCancelled, position == at else { return }
            switch result {
            case .image(let image):
                shown = image
                phase = .page
                if let blocked = blockedFrom, at >= blocked { blockedFrom = nil }
                remember(at)
                prefetchAround(at)
            case .outcome(let outcome):
                shown = nil
                phase = .gate(outcome)
                if outcome == .members || outcome == .signIn || outcome == .closed {
                    blockedFrom = min(blockedFrom ?? at, at)
                }
            }
        }
    }

    /// The server is asked about the next sixteen pages in one call, and the two pages ahead and
    /// the one behind are fetched while this one is read; not past a gate, not behind a curtain.
    private func prefetchAround(_ at: Int) {
        let ahead = Array((at + 1)...max(at + 1, min(at + 16, pages))).filter { $0 <= pages }
        let storedAhead = ahead.map { RRPageMap.stored($0, map: map) }
        let near = [at + 1, at + 2, at - 1].filter { p in
            p >= 1 && p <= pages && (blockedFrom.map { p < $0 } ?? true)
                && (flags[store.endpoint(issue, page: RRPageMap.stored(p, map: map))] == nil || revealed)
        }
        Task {
            await store.signAhead(issue, stored: storedAhead)
            for p in near { await store.prefetch(issue, stored: RRPageMap.stored(p, map: map)) }
        }
    }

    private func step(by delta: Int) {
        let next = position + delta
        guard next >= 1, next <= pages else { return }
        if delta > 0, let blocked = blockedFrom, position >= blocked { return }
        show(next)
    }

    /// Only a page the server let this viewer read is remembered as a place to come back to.
    private func remember(_ page: Int) {
        model.record(Resume(kind: .reading, ref: title.slug, part: issue.key, position: Double(page),
                            title: title.name, detail: issue.label, date: .now))
    }

    private func retryAfterSignIn() {
        blockedFrom = nil
        show(position)
    }

    private func close() {
        loadTask?.cancel()
        dismiss()
    }

    /// The reader is a cover over the app, so it closes before the house browser opens.
    private func openOnWebsite() {
        let url = ReadingLinks.page(title, issue, page: position)
        close()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            model.openWebsite(url)
        }
    }
}

/// The issue's pages as a column of small images. The page server is asked about them in runs, at
/// the small size; a page it does not allow this viewer shows its number and no picture.
private struct PageRail: View {
    let issue: RRIssue
    let pages: Int
    let map: [Int]?
    let current: Int
    let choose: (Int) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(1...pages, id: \.self) { page in
                        Button { choose(page) } label: {
                            VStack(spacing: 4) {
                                RailThumb(issue: issue, stored: RRPageMap.stored(page, map: map))
                                    .frame(height: 140)
                                Text("\(page)").kjSmall().monospacedDigit()
                            }
                            .padding(6)
                            .background(page == current ? palette.lift : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(page)
                        .accessibilityLabel("Page \(page)")
                        .accessibilityAddTraits(page == current ? .isSelected : [])
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: current, initial: true) { withAnimation(.kj) { reader.scrollTo(current, anchor: .center) } }
        }
        .task(id: issue.key) {
            // Nearest the page being read first, so a resumed issue's rail fills where you are.
            let order = (1...pages).sorted { abs($0 - current) < abs($1 - current) }
            await model.reading.signThumbnails(issue, stored: order.map { RRPageMap.stored($0, map: map) })
        }
        .accessibilityIdentifier("rrPageRail")
    }
}

private struct RailThumb: View {
    let issue: RRIssue
    let stored: Int
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay { if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } }
            .accessibilityHidden(true)
            .task(id: stored) { image = await model.reading.thumbnail(issue, stored: stored) }
    }
}

/// The page scrubber, drawn in the house's own ink: the system slider's knob is white, and the
/// house has no white. It runs the way the pages do; VoiceOver adjusts it a page at a time.
private struct PageScrubber: View {
    @Binding var page: Double
    let pages: Int
    let rightToLeft: Bool
    let commit: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 22, 1)
            let fraction = pages > 1 ? (page - 1) / Double(pages - 1) : 0
            let x = (rightToLeft ? 1 - fraction : fraction) * width
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.ink.opacity(0.25)).frame(height: 2).padding(.horizontal, 11)
                Rectangle().fill(palette.accent).frame(width: 22, height: 22).offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var f = min(max((value.location.x - 11) / width, 0), 1)
                    if rightToLeft { f = 1 - f }
                    page = (1 + f * Double(pages - 1)).rounded()
                }
                .onEnded { _ in commit() })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue("\(Int(page)) of \(pages)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, Double(pages))
            case .decrement: page = max(page - 1, 1)
            @unknown default: break
            }
            commit()
        }
    }
}

/// The page in a scroll view: pinch and double-tap zoom, pan when zoomed. `zoomed` tells the
/// reader when a swipe should pan rather than turn the page.
private struct ZoomablePage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(zoomed: $zoomed) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = view
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image { context.coordinator.imageView?.image = image }
        if !zoomed, scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: false) }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var zoomed: Bool
        weak var imageView: UIImageView?

        init(zoomed: Binding<Bool>) { _zoomed = zoomed }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let now = scrollView.zoomScale > 1.01
            if now != zoomed { zoomed = now }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
