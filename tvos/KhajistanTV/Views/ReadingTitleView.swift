import SwiftUI

/// One title: its issues as covers, each the real first page, with the figures the website states for
/// the run (rrShowIssuesGrid). A rights-held title shows its covers and opens nothing, and says why.
/// Menu goes back to the shelf.
struct ReadingTitleView: View {
    let title: RRTitle

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var reading: RRIssue?
    @State private var showProvenance = false

    private var store: ReadingStore { model.reading }
    private var held: Bool { store.isRights(title) }
    private let columns = [GridItem(.adaptive(minimum: ReadingMetrics.coverWidth + 20), spacing: 24, alignment: .top)]

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if held { rightsBanner }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(title.issues) { issue in
                            issueCard(issue)
                        }
                    }
                    // The cards' plate padding is pulled back so the covers sit on the page margin.
                    .padding(.leading, -10)
                }
                .kjBody()
                .padding(KJLayout.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(palette.ink)
        .onExitCommand { dismiss() }
        .fullScreenCover(item: $reading) { issue in
            ReadingReaderView(title: title, issue: issue)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(RRWords.heading)
            Text(title.name)
                .kjDisplay(KJType.headline, tracking: -0.055)
                .accessibilityAddTraits(.isHeader)
            if !title.native.isEmpty {
                Text(title.native).kjName()
            }
            Text(summary)
                .kjBody()
                .accessibilityIdentifier("rrTitleSummary")
            let lines = store.provenanceLines(for: title)
            if !lines.isEmpty {
                Button {
                    showProvenance.toggle()
                } label: {
                    Text("Provenance").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .padding(.leading, -26)
                .accessibilityIdentifier("rrProvenance")
                if showProvenance {
                    ForEach(lines, id: \.self) { line in
                        Text(line).kjSmall(faint: true)
                    }
                }
            }
        }
    }

    /// "Mashriq · 12 issues · 1,480 pages": the byline, then the run's own figures, totalled from the issues drawn below.
    private var summary: String {
        let depth = RRWords.depth(issues: title.issues.count, pages: title.pageTotal, held: held)
        return title.byline.isEmpty ? depth : title.byline + " \u{00B7} " + depth
    }

    private var rightsBanner: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 12) {
                Kicker(RRWords.rightsHeading)
                Text(RRWords.rightsBody(issueCount: title.issues.count, khajistanScanned: store.isKhajistanScanned(title)))
                    .kjBody()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rrRightsNote")
            }
            .frame(maxWidth: 1000, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text(RRWords.researchersAsk)
                    .kjSmall(faint: true)
                    .frame(width: 280, alignment: .leading)
            }
        }
    }

    // MARK: - Issues

    private func issueCard(_ issue: RRIssue) -> some View {
        let state = store.issueCard(title, issue)
        let label = VStack(alignment: .leading, spacing: 10) {
            RRCover(state: state)
                .frame(width: ReadingMetrics.coverWidth, height: ReadingMetrics.coverHeight)
            Text(issue.label)
                .kjName(24)
                .lineLimit(2)
                .frame(height: 64, alignment: .topLeading)
            Text("\(issue.pages) pages").kjSmall(faint: true)
        }
        .frame(width: ReadingMetrics.coverWidth, alignment: .leading)
        return Button {
            // A rights-held issue is not opened: the website's card is inert, and the page server answers 451.
            if !held { reading = issue }
        } label: {
            label
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)))
        .onAppear { store.want(title, issue: issue) }
        .accessibilityIdentifier("rr-issue-\(issue.index)")
        .accessibilityLabel(held ? "\(issue.label), cover only, pages held pending rights clearance" : "Open \(issue.label), \(issue.pages) pages")
    }
}
