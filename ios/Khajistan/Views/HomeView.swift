import SwiftUI

/// HOME: the website's own menu, door by door (ArchiveDestination, read off kj-chrome.js), with the
/// site's search at the top. Membership is offered in the Reading Room itself, on the website's
/// own page, and nowhere else in the app (owner, 2026-10-07: the Home card was too aggressive). A room the app draws itself opens
/// in its door; every other room is the live website in the house browser.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.bottom, 24)
                search
                    .padding(.bottom, 32)
                ForEach(Self.doors, id: \.door) { group in
                    door(group.door, rooms: group.rooms)
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The website's menu without the rooms the tab bar already holds (owner, 2026-10-07: one
    /// control once). Receiver, Pics/Vids and Your Khajistan are tabs; the website's own home is
    /// this page. A door left with no rooms is not drawn.
    static var doors: [(door: String, rooms: [ArchiveDestination])] {
        ArchiveDestination.doorsInThisBuild
            .map { ($0.door, $0.rooms.filter { room in room.id != "home" && room.nativeRoom.flatMap(AppTab.init) == nil }) }
            .filter { !$0.1.isEmpty }
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Khajistan").kjDisplay(tracking: -0.075).lineLimit(1)
                Text("Media of the Middle World").kjSmall(faint: true)
            }
            Spacer(minLength: 0)
            PigeonMark(size: 128)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Khajistan, Media of the Middle World")
    }

    private var search: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HouseInputField("Search the archive") {
                TextField("", text: $query, prompt: Text("Titles, places, people").foregroundStyle(palette.faint))
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($searching)
                    .onSubmit(runSearch)
                    .accessibilityIdentifier("archiveSearch")
            }
            Button(action: runSearch) { Text("Search").kjKicker() }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 0)))
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("archiveSearchGo")
        }
    }

    private func door(_ name: String, rooms: [ArchiveDestination]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseRule()
            Kicker(name)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(rooms) { room in
                Button {
                    searching = false
                    model.open(room)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.title).kjName(KJType.title)
                            Text(room.subtitle).kjSmall(faint: true)
                        }
                        Spacer(minLength: 0)
                        // In the app, or the live website.
                        Text(room.nativeRoom == nil ? "\u{2197}" : "\u{2192}").kjName().accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
                .accessibilityIdentifier("destination-\(room.id)")
            }
        }
        .padding(.bottom, 18)
    }

    private func runSearch() {
        guard let url = ArchiveURL.search(query) else { return }
        searching = false
        model.open(url)
    }
}

/// A button standing on a band: a plate of the band's own ink with the band's colour as its text.
struct OnBandButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(palette.onBand)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Rectangle())
            .animation(.kj, value: configuration.isPressed)
    }
}
