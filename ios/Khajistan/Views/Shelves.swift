import SwiftUI

// The layout the rooms take from the apps chosen for them (Apple Books for the Reading Room,
// Apple TV for the Screening Room; docs/native-rooms/DECISIONS.md 17): a large title as written,
// a search field, filter chips, shelves headed "Name ›", artwork at its own shape, and one solid
// action. The colours stay the skin's, and nothing is outlined.

/// A room's title, as the reference apps set theirs: large, bold, as written, a faint line under it.
struct LargeTitle: View {
    let title: String
    var line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.largeTitle, weight: .bold))
                .tracking(KJType.points(.largeTitle) * -0.02)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let line, !line.isEmpty { Text(line).kjSmall(faint: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A search field on the lift colour, with a clear button once something is typed.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    let id: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.faint).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(palette.faint))
                .textFieldStyle(.plain)
                .kjBody()
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(prompt)
                .accessibilityIdentifier(id)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.faint).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(palette.lift, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Chip: Identifiable {
    let id: String
    let title: String
    let identifier: String
}

/// Filter chips: the chosen one in ink with the ground's colour as its text, the others on lift.
struct ChipRow: View {
    let chips: [Chip]
    let selected: String
    let choose: (String) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.id == selected
                    Button { choose(chip.id) } label: {
                        Text(chip.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .foregroundStyle(on ? palette.ground : palette.ink)
                            .background(on ? palette.ink : palette.lift, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier(chip.identifier)
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// A chip's look for a button that is not in a ChipRow: the chosen one in ink, the others on lift.
struct ChipStyle: ButtonStyle {
    let on: Bool
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(on ? palette.ground : palette.ink)
            .background(on ? palette.ink : palette.lift, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A shelf's heading: its name, how many it holds, and a chevron when it opens to the whole shelf.
struct ShelfHeader: View {
    let title: String
    var count: Int?
    /// Where the chevron goes: the whole shelf. None, and the heading is only a heading.
    var route: RoomRoute?
    /// Or what the chevron does in place (a filter chosen on the same screen).
    var action: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        let face = HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(.title3, weight: .bold)).lineLimit(1)
            if route != nil || action != nil {
                Image(systemName: "chevron.right").font(.system(.subheadline, weight: .bold)).foregroundStyle(palette.faint)
            }
            Spacer(minLength: 8)
            if let count { Text(count.formatted()).kjSmall(faint: true) }
        }
        .foregroundStyle(palette.ink)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if let route {
            NavigationLink(value: route) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                .accessibilityHint("Shows the whole shelf")
        } else if let action {
            Button(action: action) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                .accessibilityHint("Shows the whole shelf")
        } else {
            face.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
    }
}

/// A push on the room's own stack, or, from outside it (Home), opening the room at that place.
struct RoomLink<Label: View>: View {
    let route: RoomRoute
    let room: NativeRoom?
    let label: Label
    @Environment(AppModel.self) private var model

    init(route: RoomRoute, in room: NativeRoom?, @ViewBuilder label: () -> Label) {
        self.route = route
        self.room = room
        self.label = label()
    }

    var body: some View {
        if let room {
            Button { model.open(room, at: [route]) } label: { label }
        } else {
            NavigationLink(value: route) { label }
        }
    }
}

/// How far along something is: a thin accent line over the lift colour.
struct ProgressLine: View {
    let value: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.lift)
                Capsule().fill(palette.accent).frame(width: box.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// The one action a screen is for (Read, Play): full width, the band's colour, its label in onBand.
struct SolidActionStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(palette.onBand)
            .background(palette.band, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : palette.faintAlpha))
            .contentShape(Rectangle())
            .animation(.kj, value: configuration.isPressed)
    }
}

/// A secondary action under the solid one: an icon over a short word, in ink.
struct IconAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(.title3, weight: .semibold)).frame(height: 26)
                Text(title).font(.system(.caption, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(palette.ink)
            .frame(minWidth: 64, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)))
    }
}

/// A label and its value, one to a line, as an information list sets them.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).kjSmall(faint: true)
            Text(value).kjBody()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
