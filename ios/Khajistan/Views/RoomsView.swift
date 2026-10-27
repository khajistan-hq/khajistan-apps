import SwiftUI

/// A screen pushed inside a room. It names the object by its own stable identity (a slug, a
/// handle, a record id), never by a URL that expires, so a kept route still means the same thing.
enum RoomRoute: Hashable, Sendable {
    case room(NativeRoom)
    /// A Reading Room title by slug; `resume` opens the reader where this device stopped.
    case readingTitle(String, resume: Bool = false)
    /// A Reading Room page: title slug, issue id (as the website's `issue=`) and page number.
    case readingPage(String, issue: String, page: Int)
    /// A Screening Room film by handle.
    case film(String)
    /// A Bazaar product by handle, and the bag.
    case product(String)
    case bag
    /// The Madrassa: a reference entry, a writing (blog/handle), a database and one of its records.
    case madrassaEntry(String)
    case post(String)
    case database(String)
    case record(String, String)
}

/// ROOMS: every room of the website's menu, door by door (ArchiveDestination, read off
/// kj-chrome.js). A room the app draws itself opens here; every other room is the live website in
/// the house browser. A phone pushes the room over the list; a wide window keeps the list beside it.
struct RoomsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            WideRooms()
        } else {
            NarrowRooms()
        }
    }
}

/// One stack: the list, then the room, then what the room pushes.
private struct NarrowRooms: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: pathBinding) {
            RoomList(selected: nil)
                .navigationDestination(for: RoomRoute.self) { RouteScreen(route: $0) }
                .stackScreen()
        }
    }

    /// The open room and its own stack, as one path. Back to the list leaves the room's stack
    /// kept, so opening the room again finds it where it was.
    private var pathBinding: Binding<[RoomRoute]> {
        Binding {
            guard let room = model.room else { return [] }
            return [.room(room)] + model.roomPaths[room, default: []]
        } set: { path in
            guard case .room(let room)? = path.first else { model.room = nil; return }
            model.room = room
            model.roomPaths[room] = Array(path.dropFirst())
        }
    }
}

/// The list as a sidebar and the room beside it. Each room opened is kept mounted, so moving
/// between rooms keeps each one's scroll, filters and stack.
private struct WideRooms: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var mounted: [NativeRoom] = []

    var body: some View {
        HStack(spacing: 0) {
            RoomList(selected: model.room)
                .frame(width: 320)
            Rectangle().fill(palette.ink.opacity(0.18)).frame(width: 1)
                .accessibilityHidden(true)
            ZStack {
                if model.room == nil {
                    Text("Choose a room.").kjBody().foregroundStyle(palette.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(mounted, id: \.self) { room in
                    RoomStack(room: room)
                        .opacity(room == model.room ? 1 : 0)
                        .allowsHitTesting(room == model.room)
                        .accessibilityHidden(room != model.room)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.room, initial: true) {
            if let room = model.room, !mounted.contains(room) { mounted.append(room) }
        }
    }
}

/// A room's own stack in the wide layout.
private struct RoomStack: View {
    let room: NativeRoom
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: Binding { model.roomPaths[room, default: []] } set: { model.roomPaths[room] = $0 }) {
            RoomScreen(room: room)
                .navigationDestination(for: RoomRoute.self) { RouteScreen(route: $0) }
                .stackScreen()
        }
    }
}

/// The website's menu, door by door, without the rooms the bar already holds (one control once).
struct RoomList: View {
    let selected: NativeRoom?

    static var doors: [(door: String, rooms: [ArchiveDestination])] {
        ArchiveDestination.doorsInThisBuild
            .map { ($0.door, $0.rooms.filter { room in room.id != "home" && room.nativeRoom.flatMap(AppTab.init) == nil }) }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHead(kicker: "Rooms", "The archive", line: nil)
                    .padding(.bottom, 20)
                ForEach(Self.doors, id: \.door) { group in
                    RoomDoor(name: group.door, rooms: group.rooms, selected: selected)
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .kjColumn()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }
}

/// One door of the menu and its rooms.
struct RoomDoor: View {
    let name: String
    let rooms: [ArchiveDestination]
    var selected: NativeRoom?
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HouseRule()
            // A door with one room of its own name is named once, by the room.
            if !(rooms.count == 1 && rooms[0].title.caseInsensitiveCompare(name) == .orderedSame) {
                Kicker(name)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(rooms) { room in
                let isCurrent = room.nativeRoom != nil && room.nativeRoom == selected
                Button {
                    model.open(room)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.title).kjName(KJType.title)
                                .foregroundStyle(isCurrent ? palette.accent : palette.ink)
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
                .accessibilityHint(room.nativeRoom == nil ? "Opens the website" : "Opens in the app")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(.bottom, 18)
    }
}

/// The room's own first screen.
struct RoomScreen: View {
    let room: NativeRoom

    var body: some View {
        switch room {
        case .picsVids: PicsVidsView()
        case .reading: ReadingShelfView()
        case .screening: ScreeningRoomView()
        case .bazaar: BazaarView()
        case .madrassa: MadrassaView()
        // Rooms with a bar door or a cover of their own never open here (NativeRoom.opensInRooms).
        case .receiver, .yours, .chat: EmptyView()
        }
    }
}

/// A pushed screen.
struct RouteScreen: View {
    let route: RoomRoute

    var body: some View {
        Group {
            switch route {
            case .room(let room): RoomScreen(room: room)
            case .readingTitle(let slug, let resume): ReadingTitleScreen(slug: slug, resume: resume)
            case .readingPage(let slug, let issue, let page): ReadingTitleScreen(slug: slug, openIssue: issue, openPage: page)
            case .film(let handle): FilmScreen(handle: handle)
            case .product(let handle): ProductScreen(handle: handle)
            case .bag: BagScreen()
            case .madrassaEntry(let id): MadrassaEntryScreen(id: id)
            case .post(let id): PostScreen(id: id)
            case .database(let raw):
                if let db = ArchiveDatabase(rawValue: raw) { DatabaseScreen(db: db) }
            case .record(let raw, let id):
                if let db = ArchiveDatabase(rawValue: raw) { RecordScreen(db: db, id: id) }
            }
        }
        .stackScreen(back: true)
    }
}

extension View {
    /// A screen on a navigation stack: the skin's own ground under it (a stack paints the
    /// system's white otherwise, and the house allows no white) and no system bar over it. Back
    /// is the edge swipe, and each room draws its own way back.
    /// A pushed screen (`back`) carries a visible way back as well as the edge swipe.
    func stackScreen(back: Bool = false) -> some View { modifier(StackScreen(back: back)) }
}

private struct StackScreen: ViewModifier {
    let back: Bool
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if back {
                Button { dismiss() } label: { Text("\u{2190} Back").kjKicker() }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: KJLayout.inset, bottom: 6, trailing: 16)))
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityIdentifier("stackBack")
                    .accessibilityLabel("Back")
            }
            content
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }
}
