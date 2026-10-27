import SwiftUI

/// HOME: the masthead, what was opened last on this device, and the rooms the app draws itself.
/// Nothing on it is picked by hand or ranked; the website's whole menu is ROOMS. Membership is
/// offered in the Reading Room itself, on the website's own page, and nowhere else in the app
/// (owner, 2026-10-07: the Home card was too aggressive).
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.bottom, 28)
                if !places.isEmpty { continueBlock.padding(.bottom, 28) }
                if !recent.isEmpty { recentBlock.padding(.bottom, 28) }
                if !Self.nativeRooms.isEmpty {
                    RoomDoor(name: "In the app", rooms: Self.nativeRooms)
                }
                Button(kicker: "Every room \u{2192}") { model.tab = .rooms }
                    .accessibilityIdentifier("homeAllRooms")
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    /// The menu's rooms the app draws inside ROOMS, in the menu's order.
    static var nativeRooms: [ArchiveDestination] {
        ArchiveDestination.doorsInThisBuild.flatMap(\.rooms).filter { $0.nativeRoom?.opensInRooms == true }
    }

    /// Where reading stopped on this device, newest first, for the rooms this build carries.
    private var places: [Resume] {
        Array(model.library.resume.filter { $0.kind == .reading && StoreBuild.includes(.reading) }.prefix(3))
    }

    private var continueBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseRule()
            Kicker("Continue").padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            ForEach(places) { place in
                Button {
                    model.open(.reading, at: [.readingTitle(place.ref, resume: true)])
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.title).kjName().lineLimit(2)
                            Text([place.detail, "p. \(Int(place.position))"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .kjSmall(faint: true)
                        }
                        Spacer(minLength: 0)
                        Text("\u{2192}").kjName().accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
                .accessibilityIdentifier("continue-\(place.ref)")
            }
        }
    }

    /// The last pages opened here, newest first: the device's own history, never a pick.
    private var recent: [SavedPage] { Array(model.library.history.prefix(3)) }

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

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseRule()
            Kicker("Opened lately").padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            ForEach(recent) { page in
                Button { model.open(page.url) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(page.title.isEmpty ? page.url.path : page.title).kjName().lineLimit(2)
                        Spacer(minLength: 0)
                        Text("\u{2197}").kjName().accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
            }
        }
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
