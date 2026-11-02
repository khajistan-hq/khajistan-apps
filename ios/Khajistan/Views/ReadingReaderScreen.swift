import SwiftUI
import UIKit

/// One issue, read the way Kindle and Apple Books read a book: the page as large as the screen
/// allows, on the house ground, with the controls out of the way until a tap in the middle brings
/// them. A tap at the left or right edge turns the page, and so does a sideways drag, which carries
/// the page under the finger; the turn follows the issue's own direction (RRDirection, the
/// website's rule), so in a right-to-left issue the next page lies to the left. A wide screen shows
/// two facing pages, the cover alone. Pinch or double-tap zooms to 6x (the website's ceiling) and
/// pans the page as stored; while zoomed a drag pans and does not turn.
///
/// The controls: close, the title and issue, the pages grid and a bookmark for the page at the top;
/// at the bottom the page number, a scrubber that previews the page it will land on, and after a
/// jump a way back. The last page leads on to the next issue of the title.
///
/// The page server decides what this viewer may read and its answer is what is shown: a page, a
/// sign-in for a free title, the membership note for a paid one, the rights-held note, or the
/// page's absence. A page the site holds behind a content warning stays behind its sentence until
/// the reader asks to see it. Where reading stopped, and the pages marked, are kept on this device
/// by title and issue.
struct ReadingReaderScreen: View {
    let title: RRTitle
    let startPage: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var issue: RRIssue
    @State private var pages: Int
    @State private var map: [Int]?
    /// The page being read; on a spread, the first of the two in reading order.
    @State private var position = 1
    @State private var shown: UIImage?
    /// The facing page on a spread, once the server has allowed it.
    @State private var companion: UIImage?
    /// The facing page could not join the spread (refused, curtained): the next turn goes to it.
    @State private var companionRefused = false
    @State private var companionTask: Task<Void, Never>?
    /// A facing page shown on its own because it would not join its spread; the next turn pairs again.
    @State private var single = false
    @State private var phase: Phase = .loading
    @State private var zoomed = false
    @State private var flags: [String: [String]] = [:]
    @State private var revealed = false
    /// The first page this viewer was refused for want of an account or a pass.
    @State private var blockedFrom: Int?
    @State private var showSignIn = false
    @State private var sliderPage: Double = 1
    @State private var loadTask: Task<Void, Never>?
    /// The controls over the page. Hidden while reading; a tap in the middle brings them.
    @State private var chrome = false
    @State private var showGrid = false
    @State private var scrubbing = false
    /// Where reading was before a jump by the scrubber or the grid (Kindle's "Back to page").
    @State private var jumpedFrom: Int?
    /// Two facing pages: the screen is wider than it is tall.
    @State private var wide = false
    @State private var width: CGFloat = 390
    /// The page under the finger, while a sideways drag carries it.
    @State private var dragX: CGFloat = 0
    @State private var turnedForward = true

    private enum Phase: Equatable {
        case loading, page, end
        case gate(RRPageOutcome)
        case curtain([String])
    }

    init(title: RRTitle, issue: RRIssue, startPage: Int = 1) {
        self.title = title
        self.startPage = startPage
        _issue = State(initialValue: issue)
        _pages = State(initialValue: max(issue.pages, 1))
    }

    private var store: ReadingStore { model.reading }
    private var rightToLeft: Bool { RRDirection.isRightToLeft(title, issue) }
    /// The controls stay over a refusal, a curtain and the end, which are what there is to read.
    private var chromeShown: Bool {
        switch phase {
        case .loading, .page: return chrome || scrubbing
        default: return true
        }
    }
    private var marks: [Int] { model.library.pageMarks(title: title.slug, issue: issue.key) }
    private var marked: Bool { marks.contains(position) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    palette.ground
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            let x = value.location.x / max(geometry.size.width, 1)
                            tapped(x < 0.25 ? .leftEdge : x > 0.75 ? .rightEdge : .middle)
                        })
                    pageView
                    if phase == .loading && shown == nil { Kicker("Loading\u{2026}") }
                    stateOverlay
                    if chromeShown { controls.transition(.opacity) }
                }
                .onChange(of: geometry.size, initial: true) { _, size in
                    width = size.width
                    let now = size.width > size.height
                    guard now != wide else { return }
                    wide = now
                    if phase == .page { show(position) }
                }
            }
            // A channel left on in the Receiver plays on while reading; its controls stay to hand.
            if model.tuner.source != nil { NowPlayingBar() }
        }
        .background(palette.ground.ignoresSafeArea())
        .background(keys)
        .foregroundStyle(palette.ink)
        .statusBarHidden(!chromeShown)
        .persistentSystemOverlays(chromeShown ? .automatic : .hidden)
        .task { await open(at: startPage) }
        .onDisappear {
            loadTask?.cancel()
            companionTask?.cancel()
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { retryAfterSignIn() })
        }
        .sheet(isPresented: $showGrid) {
            PagesGrid(issue: issue, pages: pages, map: map, current: position, marks: marks, rightToLeft: rightToLeft,
                      curtained: { isFlagged($0) }) { page in
                showGrid = false
                jump(to: page)
            }
            .environment(model)
            .environment(\.palette, palette)
            .presentationBackground(palette.ground)
        }
    }

    // MARK: - The page

    @ViewBuilder
    private var pageView: some View {
        if let shown, phase == .page || phase == .loading {
            let pair = companion.map { rightToLeft ? [$0, shown] : [shown, $0] } ?? [shown]
            ZoomablePage(images: pair, zoomed: $zoomed, tapped: tapped, dragged: { dragX = $0 }, released: released)
                .offset(x: dragX)
                .id(issue.key + "#\(position)")
                .transition(pageTurn)
                .accessibilityElement()
                .accessibilityLabel(pageWords)
                .accessibilityAddTraits(.isImage)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(forward: true)
                    case .decrement: step(forward: false)
                    @unknown default: break
                    }
                }
                .accessibilityAction { toggleChrome() }
                .accessibilityAction(named: zoomed ? "Zoom out" : "Zoom in") { zoomed.toggle() }
                .accessibilityAction(named: "Pages") { showGrid = true }
                #if DEBUG
                // Where the reader stands, for the UI tests: "3/76|page|rtl|spread|zoom".
                .accessibilityValue(debugState)
                #endif
                .accessibilityIdentifier("rrReaderPage")
        }
    }

    /// The new page slides in from the side the issue turns towards, like a book's leaf.
    private var pageTurn: AnyTransition {
        let fromRight = turnedForward != rightToLeft
        return .asymmetric(insertion: .move(edge: fromRight ? .trailing : .leading),
                           removal: .move(edge: fromRight ? .leading : .trailing))
    }

    /// "Page 3 of 76", or "Pages 2 and 3 of 76" on a spread.
    private var pageWords: String {
        companion != nil ? "Pages \(position) and \(position + 1) of \(pages)" : "Page \(position) of \(pages)"
    }

    #if DEBUG
    private var debugState: String {
        let name: String
        switch phase {
        case .loading: name = "loading"
        case .page: name = "page"
        case .end: name = "end"
        case .gate: name = "gate"
        case .curtain: name = "curtain"
        }
        return "\(position)/\(pages)|\(name)" + (rightToLeft ? "|rtl" : "|ltr") + (companion != nil ? "|spread" : "") + (zoomed ? "|zoom" : "")
    }
    #endif

    // MARK: - Touch

    private func tapped(_ place: ReaderTap) {
        switch place {
        case .middle:
            toggleChrome()
        case .leftEdge, .rightEdge:
            // Turning by the edge puts the controls away, as Kindle does.
            if chrome { withAnimation(.kj) { chrome = false } }
            turn(towardsLeft: place == .leftEdge)
        }
    }

    private func toggleChrome() {
        withAnimation(.kj) { chrome.toggle() }
    }

    /// A drag that ends a fifth of the screen across, or flicked, turns; anything less settles back.
    private func released(_ dx: CGFloat, _ velocity: CGFloat) {
        if abs(dx) > width / 5 || (abs(velocity) > 500 && abs(dx) > 30) {
            turn(towardsLeft: dx > 0, settle: true)
        } else {
            withAnimation(.kj) { dragX = 0 }
        }
    }

    /// The page on the left is the next one in a right-to-left issue and the one before in a
    /// left-to-right one. A finger moving right brings in the left page.
    private func turn(towardsLeft: Bool, settle: Bool = false) {
        step(forward: towardsLeft == rightToLeft, settle: settle)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            topBar.background(palette.ground)
            Spacer(minLength: 0)
            if scrubbing { scrubPreview }
            if hasBottomBar { bottomBar.background(palette.ground) }
        }
    }

    private var hasBottomBar: Bool {
        switch phase {
        case .curtain: return false
        default: return true
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 4) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
            .accessibilityLabel("Close")
            .accessibilityIdentifier("rrReaderClose")
            VStack(alignment: .leading, spacing: 2) {
                Text(title.name).kjName().lineLimit(1)
                if title.issues.count > 1, !issue.label.isEmpty { Text(issue.label).kjSmall(faint: true).lineLimit(1) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rrReaderTitle")
            Spacer(minLength: 0)
            if pages > 1 {
                Button { showGrid = true } label: {
                    Image(systemName: "square.grid.2x2").font(.body).frame(width: 44, height: 44)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
                .accessibilityLabel("Pages")
                .accessibilityIdentifier("rrPagesButton")
            }
            if phase == .page {
                Button { model.togglePageMark(title: title.slug, issue: issue.key, page: position) } label: {
                    Image(systemName: marked ? "bookmark.fill" : "bookmark").font(.body).frame(width: 44, height: 44)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
                .accessibilityLabel("Bookmark page \(position)")
                .accessibilityValue(marked ? "On" : "Off")
                .accessibilityAddTraits(marked ? .isSelected : [])
                .accessibilityIdentifier("rrBookmark")
            }
        }
        .padding(.horizontal, KJLayout.inset - 12)
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if phase != .end, let back = jumpedFrom, back != position {
                Button(kicker: "Back to page \(back)") {
                    jumpedFrom = nil
                    show(back)
                }
                .accessibilityIdentifier("rrBackToPage")
            }
            if pages > 1 {
                PageScrubber(page: $sliderPage, pages: pages, rightToLeft: rightToLeft, scrubbing: scrub) { jump(to: Int(sliderPage)) }
                    .accessibilityIdentifier("rrPageSlider")
            }
            HStack {
                turnButton(left: true)
                Spacer()
                Text(pageLabel).kjSmall().monospacedDigit().accessibilityIdentifier("rrPageLabel")
                Spacer()
                turnButton(left: false)
            }
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 6)
    }

    /// While the scrubber is held its page is previewed; the server is asked about the issue's
    /// small pages once, in runs, when it is first held.
    private func scrub(_ now: Bool) {
        withAnimation(.kj) { scrubbing = now }
        guard now else { return }
        let all = (1...pages).map { RRPageMap.stored($0, map: map) }
        let issue = issue
        Task { await store.signThumbnails(issue, stored: all) }
    }

    /// The page the scrubber will land on, as the server allows it to this viewer.
    private var scrubPreview: some View {
        let target = Int(sliderPage)
        return VStack(spacing: 6) {
            PageThumb(issue: issue, stored: RRPageMap.stored(target, map: map), curtained: isFlagged(target)).frame(height: 180)
            Text("Page \(target)").kjSmall().monospacedDigit()
        }
        .padding(.bottom, 8)
        .accessibilityIdentifier("rrScrubPreview")
    }

    /// The button on the left turns back in a left-to-right issue and forward in a right-to-left
    /// one, so the arrow always points where the page goes.
    private func turnButton(left: Bool) -> some View {
        let forward = left == rightToLeft
        return Button {
            turn(towardsLeft: left)
        } label: {
            Image(systemName: left ? "chevron.left" : "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .disabled(forward ? !canAdvance : (position <= 1 && phase != .end))
        .accessibilityLabel(forward ? "Next page" : "Previous page")
        .accessibilityIdentifier(forward ? "rrNext" : "rrPrevious")
    }

    /// The arrow keys turn as the arrows on screen do, and Escape closes, with the controls hidden too.
    private var keys: some View {
        ZStack {
            Button("") { turn(towardsLeft: true) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { turn(towardsLeft: false) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { close() }.keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var canAdvance: Bool {
        if phase == .end { return false }
        if let blocked = blockedFrom, position >= blocked { return false }
        return true
    }

    /// "Page 3 of 76", "Pages 2–3 of 76" on a spread, or the website's "Preview — 2 of 76 pages" at a gate.
    private var pageLabel: String {
        if let blocked = blockedFrom, position >= blocked {
            return "Preview \u{2014} \(max(blocked - 1, 0)) of \(pages) pages"
        }
        if phase == .end { return "End of the issue \u{00B7} \(pages) pages" }
        return companion != nil ? "Pages \(position)\u{2013}\(position + 1) of \(pages)" : "Page \(position) of \(pages)"
    }

    // MARK: - States over the page

    @ViewBuilder
    private var stateOverlay: some View {
        switch phase {
        case .loading, .page:
            EmptyView()
        case .end:
            endOfIssue
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

    private var nextIssue: RRIssue? {
        let next = issue.index + 1
        return title.issues.indices.contains(next) ? title.issues[next] : nil
    }

    /// The last page turned: the next issue of the title where there is one, and the way back.
    private var endOfIssue: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("End of the issue")
            Text(issue.label.isEmpty || title.issues.count < 2 ? title.name : "\(title.name) \u{00B7} \(issue.label)")
                .kjName(KJType.title)
            if let next = nextIssue {
                Button(kicker: "Next issue \u{00B7} \(next.label)") { Task { await openIssue(next) } }
                    .buttonStyle(HouseButtonStyle(solid: true))
                    .accessibilityIdentifier("rrNextIssue")
            }
            Button(kicker: "Back to the title") { close() }.accessibilityIdentifier("rrEndClose")
        }
        .padding(KJLayout.inset)
        .frame(maxWidth: KJLayout.readingWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rrEnd")
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

    private func open(at page: Int) async {
        async let numbers = store.pageMap(issue)
        async let own = store.warnings(for: issue.slug)
        async let card = title.slug == issue.slug ? [:] : store.warnings(for: title.slug)
        let resolved = await numbers
        pages = max(resolved.pages, 1)
        map = resolved.map
        flags = await own.merging(await card) { first, _ in first }
        show(page)
    }

    /// The next issue of the title, from its first page, in the same reader.
    private func openIssue(_ next: RRIssue) async {
        loadTask?.cancel()
        companionTask?.cancel()
        issue = next
        pages = max(next.pages, 1)
        map = nil
        shown = nil
        companion = nil
        blockedFrom = nil
        revealed = false
        jumpedFrom = nil
        phase = .loading
        await open(at: 1)
    }

    /// The first page of the spread a page sits on: the cover alone, then two and three, four and five.
    private func spreadStart(_ page: Int) -> Int {
        guard wide, page > 1 else { return page }
        return page.isMultiple(of: 2) ? page : page - 1
    }

    private func isFlagged(_ page: Int) -> Bool {
        !revealed && flags[store.endpoint(issue, page: RRPageMap.stored(page, map: map))] != nil
    }

    /// Shows a page, or the spread it sits on. `alone` keeps a facing page that could not join its
    /// spread on its own, so its refusal or curtain is what is read.
    private func show(_ target: Int, alone: Bool = false) {
        loadTask?.cancel()
        companionTask?.cancel()
        let clamped = min(max(1, target), pages)
        position = alone ? clamped : spreadStart(clamped)
        single = alone
        sliderPage = Double(position)
        zoomed = false
        companion = nil
        companionRefused = false
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
            if !alone { showCompanion(of: at) }
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
                if !alone { showCompanion(of: at) }
            case .outcome(let outcome):
                shown = nil
                phase = .gate(outcome)
                if outcome == .members || outcome == .signIn || outcome == .closed {
                    blockedFrom = min(blockedFrom ?? at, at)
                }
            }
        }
    }

    /// The facing page of a spread. Asked of the page server as any page is, and never past a
    /// gate already met or behind a curtain: a page that will not join is read on its own instead.
    private func showCompanion(of at: Int) {
        let facing = at + 1
        guard wide, at > 1, facing <= pages else { return }
        if blockedFrom.map({ facing >= $0 }) ?? false || isFlagged(facing) {
            companionRefused = true
            return
        }
        let stored = RRPageMap.stored(facing, map: map)
        if let held = store.heldPage(issue, stored: stored) {
            companion = held
            return
        }
        companionTask = Task {
            let result = await store.page(issue, stored: stored)
            guard !Task.isCancelled, position == at else { return }
            switch result {
            case .image(let image):
                companion = image
            case .outcome(let outcome):
                companionRefused = true
                if outcome == .members || outcome == .signIn || outcome == .closed {
                    blockedFrom = min(blockedFrom ?? facing, facing)
                }
            }
        }
    }

    /// The server is asked about the next sixteen pages in one call, and the pages ahead and the
    /// one behind are fetched while this one is read; not past a gate, not behind a curtain.
    private func prefetchAround(_ at: Int) {
        let ahead = Array((at + 1)...max(at + 1, min(at + 16, pages))).filter { $0 <= pages }
        let storedAhead = ahead.map { RRPageMap.stored($0, map: map) }
        let reach = wide ? [at + 2, at + 3, at - 1, at - 2] : [at + 1, at + 2, at - 1]
        let near = reach.filter { p in
            p >= 1 && p <= pages && (blockedFrom.map { p < $0 } ?? true) && !isFlagged(p)
        }
        let issue = issue
        Task {
            await store.signAhead(issue, stored: storedAhead)
            for p in near { await store.prefetch(issue, stored: RRPageMap.stored(p, map: map)) }
        }
    }

    /// One turn, a page or a spread. Forward from the last page is the end of the issue; nothing
    /// past a gate already met is asked for.
    private func step(forward: Bool, settle: Bool = false) {
        turnedForward = forward
        if forward {
            guard canAdvance else { return settleBack(settle) }
            let next: Int
            var alone = false
            if !wide || position == 1 || single {
                next = position + 1
            } else if companionRefused {
                // The facing page would not join: it is read on its own, as itself.
                next = position + 1
                alone = true
            } else if companion == nil, phase == .page, position < pages {
                // The facing page is still on its way; the turn waits for it so pairs stay aligned.
                return settleBack(settle)
            } else if companion == nil, phase != .page {
                // This page is a refusal, a curtain or missing, so its facing page was never drawn:
                // it comes next, on its own, rather than being skipped. The pairs line up again after.
                next = position + 1
                alone = true
            } else {
                next = position + 2
            }
            if next > pages {
                withAnimation(.kjPush) {
                    dragX = 0
                    loadTask?.cancel()
                    companionTask?.cancel()
                    shown = nil
                    companion = nil
                    phase = .end
                }
                return
            }
            withAnimation(.kjPush) {
                dragX = 0
                show(next, alone: alone)
            }
        } else {
            if phase == .end {
                withAnimation(.kjPush) {
                    dragX = 0
                    show(position)
                }
                return
            }
            guard position > 1 else { return settleBack(settle) }
            withAnimation(.kjPush) {
                dragX = 0
                show(position - 1)
            }
        }
    }

    private func settleBack(_ settle: Bool) {
        if settle { withAnimation(.kj) { dragX = 0 } }
    }

    /// A jump by the scrubber or the grid; the place left is offered back.
    private func jump(to page: Int) {
        if page != position { jumpedFrom = position }
        show(page)
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
        companionTask?.cancel()
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
