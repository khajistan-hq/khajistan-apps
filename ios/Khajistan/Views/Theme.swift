import ImageIO
import SwiftUI
import UIKit

// The house style, for a phone. Measured from the website and carried over from the Apple TV
// app's Theme (tvos/DESIGN.md): two house colours and their skins, the system font at the
// website's weights, no white, no grey, no frames or boxes. Spacing separates things; the only
// lines are a text field's rule and the owner's one-pixel row rule (frontend.md §1).

extension Color {
    /// 0xRRGGBB in sRGB. The one place a hex value becomes a Color.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Palette

/// Every colour in the app, for one skin (tvos/DESIGN.md's token table). Never white, never grey.
struct Palette: Equatable {
    let ground: Color
    let ink: Color
    let accent: Color
    let faint: Color
    let band: Color
    let onBand: Color
    let lift: Color
    let mapDeep: Color
    let mapTint: Color
    let skin: Skin
    /// True inside a band plate, where a press dims rather than lifting (the lift is a page colour).
    let isBandPlate: Bool

    init(_ skin: Skin) {
        self.skin = skin
        isBandPlate = false
        let ink = Color(hex: skin.inkHex)
        ground = Color(hex: skin.groundHex)
        self.ink = ink
        lift = Color(hex: skin.liftHex)
        onBand = Color(hex: 0xF3FB04)
        mapTint = Color(hex: 0x7E9B45)
        switch skin {
        case .day:
            accent = Color(hex: 0x186409)
            faint = ink.opacity(0.62)
            band = Color(hex: 0x186409)
            mapDeep = Color(hex: 0x006F00)
        case .grove:
            accent = Color(hex: 0xF3FB04)
            faint = ink.opacity(0.85)
            band = Color(hex: 0x002800)
            mapDeep = Color(hex: 0x7E9B45)
        case .smut:
            accent = Color(hex: 0xF3FB04)
            faint = ink.opacity(0.95)
            band = Color(hex: 0x6E003F)
            mapDeep = Color(hex: 0x006F00)
        }
    }

    private init(copy p: Palette, ground: Color, ink: Color, accent: Color, faint: Color, isBandPlate: Bool? = nil) {
        self.isBandPlate = isBandPlate ?? p.isBandPlate
        self.ground = ground
        self.ink = ink
        self.accent = accent
        self.faint = faint
        band = p.band
        onBand = p.onBand
        lift = p.lift
        mapDeep = p.mapDeep
        mapTint = p.mapTint
        skin = p.skin
    }

    /// What a label sees on a band plate: the band is its ground, onBand its ink and accent. On
    /// the day skin the accent and the band are the same green, so a kicker would vanish there.
    var onBandPlate: Palette {
        Palette(copy: self, ground: band, ink: onBand, accent: onBand, faint: onBand.opacity(0.85), isBandPlate: true)
    }

    /// A pressed control: the lift plate under the page's own ink.
    var onLiftPlate: Palette {
        Palette(copy: self, ground: lift, ink: ink, accent: accent, faint: faint)
    }

    /// A tab that is not the current one: its kicker reads as plain ink.
    var plainTab: Palette {
        Palette(copy: self, ground: ground, ink: ink, accent: ink, faint: faint)
    }

    var uiGround: UIColor { UIColor(ground) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(.day)
}

extension EnvironmentValues {
    /// The palette in force here. RootView sets the skin's; a plate sets its own for its label.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Type

/// The website's type on a phone: the system font (the site sets everything in system-ui) at its
/// weights, on Dynamic Type's text styles so every size follows the reader's setting.
enum KJType {
    static let display: Font.TextStyle = .largeTitle
    static let headline: Font.TextStyle = .title
    static let title: Font.TextStyle = .title3
    static let name: Font.TextStyle = .headline
    static let stat: Font.TextStyle = .title2
    static let body: Font.TextStyle = .body
    static let kicker: Font.TextStyle = .caption2
    static let small: Font.TextStyle = .footnote

    /// The point size a style has at the reader's current setting, for tracking given in em.
    static func points(_ style: Font.TextStyle) -> CGFloat {
        let ui: UIFont.TextStyle
        switch style {
        case .largeTitle: ui = .largeTitle
        case .title: ui = .title1
        case .title2: ui = .title2
        case .title3: ui = .title3
        case .headline: ui = .headline
        case .subheadline: ui = .subheadline
        case .callout: ui = .callout
        case .footnote: ui = .footnote
        case .caption: ui = .caption1
        case .caption2: ui = .caption2
        default: ui = .body
        }
        return UIFont.preferredFont(forTextStyle: ui).pointSize
    }
}

enum KJLayout {
    /// The page margin.
    static let inset: CGFloat = 20
    /// The widest a page of rows and text may run. On an iPhone the screen is narrower, so this
    /// never applies there; on an iPad it keeps a row's name and its arrow within one glance.
    static let readingWidth: CGFloat = 720
    /// The Receiver's cap: on an iPad the map and the channel list sit side by side within it,
    /// centred in landscape instead of stretching the page.
    static let wideWidth: CGFloat = 1240
}

extension View {
    /// Holds a page's content to `width` and centres it. Below that width (every iPhone, and an
    /// iPad app in a narrow split) it changes nothing.
    func kjColumn(_ width: CGFloat = KJLayout.readingWidth) -> some View {
        frame(maxWidth: width, alignment: .leading).frame(maxWidth: .infinity)
    }
}

extension View {
    /// Black, upper case, tight: the website's page titles.
    func kjDisplay(_ style: Font.TextStyle = KJType.display, tracking em: CGFloat = -0.06) -> some View {
        modifier(DisplayStyle(style: style, em: em))
    }

    /// A name, as written.
    func kjName(_ style: Font.TextStyle = KJType.name) -> some View {
        modifier(TrackedStyle(style: style, weight: .black, em: -0.02))
    }

    /// A figure.
    func kjStat() -> some View {
        modifier(TrackedStyle(style: KJType.stat, weight: .black, em: -0.04)).monospacedDigit()
    }

    /// A label: black, upper case, spaced out, in `color` or the palette's accent.
    func kjKicker(_ color: Color? = nil) -> some View {
        modifier(KickerStyle(color: color))
    }

    func kjBody() -> some View {
        font(.system(KJType.body))
    }

    /// Small type, in the palette's faint tone when asked.
    func kjSmall(faint: Bool = false) -> some View {
        modifier(SmallStyle(faint: faint))
    }
}

private struct DisplayStyle: ViewModifier {
    let style: Font.TextStyle
    let em: CGFloat
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content
            .font(.system(style, weight: .black))
            .textCase(.uppercase)
            .tracking(KJType.points(style) * em)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
    }
}

private struct TrackedStyle: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight
    let em: CGFloat
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content.font(.system(style, weight: weight)).tracking(KJType.points(style) * em)
    }
}

private struct KickerStyle: ViewModifier {
    let color: Color?
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content
            .font(.system(KJType.kicker, weight: .black))
            .textCase(.uppercase)
            .tracking(KJType.points(KJType.kicker) * 0.13)
            .foregroundStyle(color ?? palette.accent)
    }
}

private struct SmallStyle: ViewModifier {
    let faint: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        if faint {
            content.font(.system(KJType.small)).foregroundStyle(palette.faint)
        } else {
            content.font(.system(KJType.small))
        }
    }
}

// MARK: - Motion

extension Animation {
    /// The house's short ease: quick enough at 120 Hz to feel like a response, not a show.
    static let kj = Animation.easeOut(duration: 0.18)
    /// A drill-in and back, at about the pace of the system's navigation push.
    static let kjPush = Animation.smooth(duration: 0.32)
}

// MARK: - Controls

/// A control on the page. At rest it is text on the ground; pressed, it sits on the lift plate.
/// `solid` is the call to action: a band plate under onBand text, as the website's buttons are.
struct HouseButtonStyle: ButtonStyle {
    var solid = false
    var padding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

    func makeBody(configuration: Configuration) -> some View {
        HousePlate(label: configuration.label, pressed: configuration.isPressed, solid: solid, padding: padding, tab: nil)
    }
}

/// A navigation or filter tab: a kicker in plain ink, the current one in the accent with a 3pt
/// rule under it, the way the website marks the current section.
struct HouseTabStyle: ButtonStyle {
    let isCurrent: Bool
    var padding = EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)

    func makeBody(configuration: Configuration) -> some View {
        HousePlate(label: configuration.label, pressed: configuration.isPressed, solid: false, padding: padding, tab: isCurrent)
    }
}

private struct HousePlate<Face: View>: View {
    let label: Face
    let pressed: Bool
    let solid: Bool
    let padding: EdgeInsets
    let tab: Bool?
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    /// On a band a press dims; on the page it lifts.
    private var lifts: Bool { pressed && !palette.isBandPlate }

    private var inner: Palette {
        if lifts { return palette.onLiftPlate }
        if solid { return palette.onBandPlate }
        if tab == false { return palette.plainTab }
        return palette
    }

    var body: some View {
        let look = inner
        label
            .multilineTextAlignment(.leading)
            // A tab's name never breaks; rows of tabs scroll sideways instead.
            .fixedSize(horizontal: tab != nil, vertical: false)
            .overlay(alignment: .bottom) {
                if tab == true && !pressed {
                    Rectangle().fill(look.accent).frame(height: 3).offset(y: 7)
                }
            }
            .padding(padding)
            .environment(\.palette, look)
            .foregroundStyle(look.ink)
            .background(lifts ? palette.lift : (solid ? palette.band : Color.clear))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (pressed && palette.isBandPlate ? 0.6 : 1) : 0.45)
            .animation(.kj, value: pressed)
    }
}

/// A label in the accent colour, or `color`.
struct Kicker: View {
    let text: String
    let color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).kjKicker(color)
    }
}

/// A labelled number.
struct Figure: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(label)
            Text(value).kjStat()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The owner's one-pixel rule between sections and rows (frontend.md §1, 2026-09-10).
struct HouseRule: View {
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle().fill(palette.ink).frame(height: 1 / max(scale, 1)).accessibilityHidden(true)
    }
}

/// A full-width band of kickers on the band colour. It heads every player, as the website's
/// console bar does.
struct StatusBand: View {
    let leading: [String]
    let trailing: [String]
    @Environment(\.palette) private var palette

    init(leading: [String], trailing: [String] = []) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        // On a phone the band keeps what fits: everything, then the first label and the state,
        // then the first label alone.
        ViewThatFits(in: .horizontal) {
            row(leading, trailing)
            row(Array(leading.prefix(1)), trailing)
            row(Array(leading.prefix(1)), [])
        }
        .lineLimit(1)
        .padding(.vertical, 10)
        .padding(.horizontal, KJLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.band, ignoresSafeAreaEdges: [.horizontal, .top])
    }

    private func row(_ items: [String], _ tail: [String]) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { Kicker($0.element, color: palette.onBand).fixedSize() }
            Spacer(minLength: 14)
            ForEach(Array(tail.enumerated()), id: \.offset) { Kicker($0.element, color: palette.onBand).fixedSize() }
        }
    }
}

/// An on/off control: the track in ink, the knob in the ground, a kicker beside it.
struct HouseSwitch: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            withAnimation(.kj) { isOn.toggle() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Capsule().fill(palette.ink).frame(width: 46, height: 26)
                    Circle().fill(palette.ground).frame(width: 18, height: 18).offset(x: isOn ? 10 : -10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).kjKicker(palette.ink)
                    if let detail { Text(detail).kjSmall(faint: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The house text field: the label as a kicker, the entry in body type, one 2pt rule under it.
/// The rule is the only border the house allows, because a reader must see where to aim.
struct HouseInputField<Entry: View>: View {
    let label: String
    private let entry: Entry
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    init(_ label: String, @ViewBuilder entry: () -> Entry) {
        self.label = label
        self.entry = entry()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(label).accessibilityHidden(true)
            entry
                .textFieldStyle(.plain)
                .kjBody()
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .padding(.vertical, 6)
                .focused($isFocused)
                .accessibilityLabel(label)
            Rectangle().fill(isFocused ? palette.accent : palette.ink).frame(height: 2)
        }
    }
}

/// A sentence the app needs the reader to see, on a band across the top: no system alert.
struct HouseBanner: View {
    let text: String
    let dismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(text).font(.system(KJType.small)).foregroundStyle(palette.onBand)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Text("OK").kjKicker(palette.onBand) }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)))
                .environment(\.palette, palette.onBandPlate)
                .accessibilityIdentifier("bannerOK")
        }
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 10)
        .background(palette.band)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("houseBanner")
    }
}

/// A question that needs an answer, as a band at the bottom of the screen: the question and its
/// actions in onBand. It replaces the system's alert and confirmation panels.
struct HouseDialog: View {
    struct Action: Identifiable {
        let title: String
        let run: () -> Void
        var id: String { title }
    }

    let text: String
    let actions: [Action]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text).kjBody().foregroundStyle(palette.onBand)
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button(action: action.run) { Text(action.title).kjKicker(palette.onBand) }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 18)))
                        .accessibilityIdentifier("dialog-\(action.title)")
                }
            }
        }
        .environment(\.palette, palette.onBandPlate)
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.band, ignoresSafeAreaEdges: [.horizontal, .bottom])
        .transition(.move(edge: .bottom))
    }
}

/// What a screen says while it waits.
struct TuningLoader: View {
    let label: String?

    init(_ label: String? = "Connecting\u{2026}") {
        self.label = label
    }

    var body: some View {
        if let label, !label.isEmpty { Kicker(label) }
    }
}

// MARK: - The pigeon

// PigeonMark lives in Views/PigeonMark.swift, the Apple TV app's file, linked: its frames are
// decoded once at the screen's density and played by a UIImageView, with no main-thread work
// per frame. The old player here pushed every full 1080px frame through SwiftUI state, which
// kept the main thread busy and failed UI automation on a GPU-less CI runner (2026-10-06).

/// A button's words, as the house sets them: a kicker, in the plate's accent.
struct KickerLabel: View {
    let title: String
    var body: some View { Text(title).kjKicker() }
}

extension Button where Label == KickerLabel {
    init(kicker title: String, action: @escaping () -> Void) {
        self.init(action: action) { KickerLabel(title: title) }
    }
}
