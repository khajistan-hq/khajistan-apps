import SwiftUI

/// SEARCH: one field. The rooms the app reads itself answer here, each under its own name, and the
/// website's own index (/search.html) is always one control away for everything else. A scope is
/// listed only when the app holds that room's data; nothing is said to have been searched that
/// was not.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHead(kicker: "Search", "Search the archive", line: nil)
                field
                websiteRow
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var field: some View {
        HouseInputField("Titles, places, people") {
            TextField("", text: $query, prompt: Text("Titles, places, people").foregroundStyle(palette.faint))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(searchWebsite)
                .accessibilityIdentifier("archiveSearch")
        }
    }

    private var websiteRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HouseRule()
            Button(action: searchWebsite) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trimmed.isEmpty ? "The website's index" : "\u{201C}\(trimmed)\u{201D} on the website").kjName()
                        Text("Every room, in the website's own search").kjSmall(faint: true)
                    }
                    Spacer(minLength: 0)
                    Text("\u{2197}").kjName().accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
            .disabled(trimmed.isEmpty)
            .accessibilityIdentifier("archiveSearchGo")
        }
    }

    private func searchWebsite() {
        guard let url = ArchiveURL.search(query) else { return }
        focused = false
        model.open(url)
    }
}
