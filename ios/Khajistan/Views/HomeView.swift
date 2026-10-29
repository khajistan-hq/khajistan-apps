import SwiftUI

/// HOME: the masthead, what was opened last on this device, a shelf for each part of Khajistan,
/// and the rooms the app draws itself.
/// Nothing on it is picked by hand or ranked; the website's whole menu is ROOMS. Membership is
/// offered in the Reading Room itself, on the website's own page, and nowhere else in the app
/// (owner, 2026-10-07: the Home card was too aggressive).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                masthead
                if hasReading {
                    // Covers when the shelf is already in hand; otherwise the places as text, so
                    // Home never starts the catalogue download (every Supabase byte is billed).
                    if model.reading.phase == .ready { ContinueShelf(fromHome: true) } else { continueText }
                }
                upNext
                HomeShelves()
                rooms
                if !recent.isEmpty { recentBlock }
                Button(kicker: "Every room \u{2192}") { model.tab = .rooms }
                    .accessibilityIdentifier("homeAllRooms")
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn(KJLayout.wideWidth)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .task(id: model.auth.previewPassword) { if hasFilm { await model.films.load() } }
    }

    /// The menu's rooms the app draws inside ROOMS, in the menu's order.
    static var nativeRooms: [ArchiveDestination] {
        ArchiveDestination.doorsInThisBuild.flatMap(\.rooms).filter { $0.nativeRoom?.opensInRooms == true }
    }

    /// Every room the app draws itself, Chat included, in the menu's order.
    private var appRooms: [ArchiveDestination] {
        ArchiveDestination.doorsInThisBuild.flatMap(\.rooms).filter {
            guard let room = $0.nativeRoom else { return false }
            return room.opensInRooms || room == .chat
        }
    }

    private var hasReading: Bool {
        StoreBuild.includes(.reading) && model.library.resume.contains { $0.kind == .reading }
    }

    private var hasFilm: Bool {
        StoreBuild.includes(.screening) && model.library.resume.contains { $0.kind == .film && $0.position > 30 }
    }

    /// Where reading stopped, from this device's own record: no catalogue needed.
    private var continueText: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfHeader(title: "Continue")
            ForEach(model.library.resume.filter { $0.kind == .reading }.prefix(3)) { place in
                Button { model.open(.reading, at: [.readingTitle(place.ref, resume: true)]) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title).font(.system(.body, weight: .semibold)).lineLimit(2)
                            Text([place.detail, "p. \(Int(place.position))"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .kjSmall(faint: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(.subheadline, weight: .bold)).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
                .accessibilityIdentifier("continue-\(place.ref)")
            }
        }
    }

    /// Full films stopped on this device, as the Apple TV app's Up Next.
    @ViewBuilder
    private var upNext: some View {
        let stopped: [(Film, Resume)] = hasFilm ? model.library.resume.filter { $0.kind == .film && $0.position > 30 }.compactMap { place in
            model.films.films.first { $0.handle == place.ref }.map { ($0, place) }
        } : []
        if !stopped.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(title: "Up Next")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(stopped, id: \.0.id) { film, place in
                            FilmCard(film: film, width: sizeClass == .regular ? 170 : 140,
                                     progress: film.runtime_minutes.flatMap { $0 > 0 ? place.position / Double($0 * 60) : nil },
                                     line: "Stopped at \(FilmPlayback.clock(place.position))", fromHome: true)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The rooms, as the Apple TV app's sections and Apple Books' categories: a picture first,
    /// then the name and its line, whole.
    private var rooms: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "In the app")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 220 : 150), spacing: 12, alignment: .top)], spacing: 18) {
                ForEach(appRooms) { room in RoomTile(room: room) }
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
            ShelfHeader(title: "Opened lately")
            ForEach(recent) { page in
                Button { model.open(page.url) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(page.title.isEmpty ? page.url.path : page.title).font(.system(.body, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)))
            }
        }
    }
}

/// A room on Home, picture first: one of the archive's own pictures on the lift plate, fitted
/// whole, then the name and the room's line in full.
private struct RoomTile: View {
    let room: ArchiveDestination
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        Button { model.open(room) } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoomPicture(room: room.nativeRoom)
                    .aspectRatio(4 / 5, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.title).font(.system(.headline, weight: .bold)).lineLimit(2)
                    Text(room.subtitle).kjSmall(faint: true).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-room-\(room.id)")
    }
}

/// A room's picture on the lift plate, fitted whole and never cropped; the room's icon where it
/// has no picture.
struct RoomPicture: View {
    let room: NativeRoom?
    var corner: CGFloat = 14
    var inset: CGFloat = 8
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(palette.lift)
            .overlay {
                if let name = room?.picture {
                    Image(name).resizable().aspectRatio(contentMode: .fit).padding(inset)
                } else {
                    Image(systemName: room?.symbol ?? "globe").font(.system(.title2, weight: .semibold)).foregroundStyle(palette.accent)
                }
            }
            .accessibilityHidden(true)
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
