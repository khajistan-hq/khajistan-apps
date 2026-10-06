import SwiftUI

/// The Reading Room: the shelf the website draws at /reading-room.html, as rows of covers. A tab per
/// language and a row per shelf in it when the module index is there (data/rr-modules.json, behind the
/// site password); otherwise one tab of every title in a row per region. Each cover is the real scanned
/// first page; each card says what the page server told an anonymous visitor about it.
struct ReadingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var tabID: String?
    @State private var opened: RRTitle?
    @FocusState private var focusedTab: String?

    private var store: ReadingStore { model.reading }

    private var tab: RRTab? {
        store.tabs.first { $0.id == tabID } ?? store.tabs.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                header
                switch store.phase {
                case .idle, .loading:
                    TuningLoader("Loading the Reading Room\u{2026}")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed(let message):
                    problem(message)
                case .ready:
                    if store.tabs.count > 1 { tabRow }
                    if let tab { shelf(tab) }
                }
            }
            .kjBody()
            .padding(KJLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Down from the top bar lands on the tab on show, not on the one under the bar item.
        .defaultFocus($focusedTab, tab?.id, priority: .userInitiated)
        .task { await store.start() }
        .fullScreenCover(item: $opened) { title in
            ReadingTitleView(title: title)
        }
    }

    // MARK: - Header and tabs

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RRWords.heading)
                .kjDisplay(KJType.headline, tracking: -0.055)
                .accessibilityAddTraits(.isHeader)
            Text(RRWords.lede).kjBody()
        }
    }

    private var tabRow: some View {
        HStack(spacing: 12) {
            ForEach(store.tabs) { item in
                Button {
                    tabID = item.id
                } label: {
                    Text(item.name).kjKicker()
                }
                .buttonStyle(HouseTabStyle(isCurrent: item.id == tab?.id))
                .focused($focusedTab, equals: item.id)
                .accessibilityIdentifier("rr-tab-\(item.id)")
            }
        }
        // The tabs' plate padding is pulled back so their text sits on the page margin.
        .padding(.leading, -22)
        .focusSection()
    }

    // MARK: - The shelf

    @ViewBuilder
    private func shelf(_ tab: RRTab) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(tab.name).kjName(KJType.name)
                if let native = tab.native, !native.isEmpty {
                    Text(native).kjName(KJType.name).foregroundStyle(palette.faint)
                }
            }
            Text(tab.depth)
                .kjSmall(faint: true)
                .accessibilityIdentifier("rrDepth")
        }
        ForEach(tab.rows) { row in
            rowView(row)
        }
    }

    private func rowView(_ row: RRRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Kicker(row.name)
                Text(row.titles.count.formatted()).kjSmall(faint: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(row.titles) { title in
                        card(title)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            // The cards' plate padding is pulled back so the covers sit on the page margin.
            .padding(.leading, -10)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rr-row-\(row.id)")
    }

    private func card(_ title: RRTitle) -> some View {
        let state = store.card(for: title)
        let meta = [title.byline, "\(title.issues.count) issue\(title.issues.count == 1 ? "" : "s")"]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return Button {
            opened = title
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RRCover(state: state)
                    .frame(width: ReadingMetrics.coverWidth, height: ReadingMetrics.coverHeight)
                Text(title.name)
                    .kjName(26)
                    .lineLimit(2)
                    .frame(height: 70, alignment: .topLeading)
                Text(meta)
                    .kjSmall(faint: true)
                    .lineLimit(1)
                Text(store.access(for: title)?.tag ?? " ")
                    .kjKicker()
                    .lineLimit(2)
                    .frame(height: 56, alignment: .topLeading)
            }
            .frame(width: ReadingMetrics.coverWidth, alignment: .leading)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)))
        .onAppear { store.want(title) }
        .accessibilityIdentifier("rr-title-\(title.slug)")
        .accessibilityLabel([title.name, meta, store.access(for: title)?.tag].compactMap { $0 }.joined(separator: ", "))
    }

    private func problem(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(message).kjBody()
            Button {
                Task { await store.retry() }
            } label: {
                Text("Try again").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .accessibilityIdentifier("rrRetry")
        }
    }
}

enum ReadingMetrics {
    static let coverWidth: CGFloat = 250
    static let coverHeight: CGFloat = 340
}

/// A cover at its own shape on the house lift colour, fitted whole and never cropped. The plate holds
/// the space until the page arrives; a cover that cannot be had leaves the plate and nothing else.
struct RRCover: View {
    let state: RRCardState
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.lift)
            .overlay {
                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
    }
}
