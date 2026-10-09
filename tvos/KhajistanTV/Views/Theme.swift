import AVFoundation
import ImageIO
import SwiftUI
import UIKit

extension Color {
    /// 0xRRGGBB in sRGB. The one place a hex value becomes a Color.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - Palette

/// Every colour in the app, for one skin: DESIGN.md's token table. Ground, ink and lift are read
/// from `Skin`, which owns them; the rest are set here. Never white, never grey, no third hue.
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

    init(_ skin: Skin) {
        let ink = Color(hex: skin.inkHex)
        ground = Color(hex: skin.groundHex)
        self.ink = ink
        lift = Color(hex: skin.liftHex)
        onBand = Color(hex: Skin.onBandHex)
        mapTint = Color(hex: Skin.mapTintHex)
        accent = Color(hex: skin.accentHex)
        band = Color(hex: skin.bandHex)
        mapDeep = Color(hex: skin.mapDeepHex)
        switch skin {
        case .day: faint = ink.opacity(0.62)
        case .grove: faint = ink.opacity(0.85)
        case .smut: faint = ink.opacity(0.95)
        }
    }

    fileprivate init(ground: Color, ink: Color, accent: Color, faint: Color, band: Color, onBand: Color, lift: Color, mapDeep: Color, mapTint: Color) {
        self.ground = ground
        self.ink = ink
        self.accent = accent
        self.faint = faint
        self.band = band
        self.onBand = onBand
        self.lift = lift
        self.mapDeep = mapDeep
        self.mapTint = mapTint
    }

    private func replacing(ground: Color? = nil, ink: Color? = nil, accent: Color? = nil, faint: Color? = nil) -> Palette {
        Palette(
            ground: ground ?? self.ground, ink: ink ?? self.ink, accent: accent ?? self.accent, faint: faint ?? self.faint,
            band: band, onBand: onBand, lift: lift, mapDeep: mapDeep, mapTint: mapTint
        )
    }

    // What a control's label sees from inside its plate. The plate is the label's ground, so a
    // kicker (accent) or a faint line that is right on the page cannot fall into the plate's own
    // colour: on the day skin the accent and the band are the same green.

    /// A focused control: the band is the ground, `onBand` the ink and the accent.
    fileprivate var onFocusPlate: Palette {
        replacing(ground: band, ink: onBand, accent: onBand, faint: onBand.opacity(0.85))
    }

    /// A pressed control: the lift plate under the page's own ink.
    fileprivate var onPressPlate: Palette {
        replacing(ground: lift)
    }

    /// A navigation tab that is not the current one: its kicker reads as plain ink.
    fileprivate var onPlainTab: Palette {
        replacing(accent: ink)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(.day)
}

extension EnvironmentValues {
    /// The palette in force at this point in the tree. RootView sets the skin's; a control's
    /// plate sets its own for its label.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Type

/// Television sizes, measured from the website (DESIGN.md). The system font is the house font.
enum KJType {
    static let display: CGFloat = 120
    static let headline: CGFloat = 72
    static let name: CGFloat = 34
    static let stat: CGFloat = 56
    static let body: CGFloat = 29
    /// No text on the television is under 24 pt (roast 2026-10-07).
    static let kicker: CGFloat = 24
    static let small: CGFloat = 24
}

/// Layout numbers shared by the root screens.
enum KJLayout {
    /// The side margin of the top bar, the status band and the screens' content. It is laid inside
    /// the safe area tvOS already keeps, so it is added to that margin, not measured from the edge.
    static let inset: CGFloat = 80
}

extension View {
    /// Black, upper case, tight. The headline is `kjDisplay(KJType.headline, tracking: -0.055)`.
    func kjDisplay(_ size: CGFloat = KJType.display, tracking em: CGFloat = -0.075) -> some View {
        font(.system(size: size, weight: .black))
            .textCase(.uppercase)
            .tracking(size * em)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }

    /// A name, as written.
    func kjName(_ size: CGFloat = KJType.name) -> some View {
        font(.system(size: size, weight: .black))
            .tracking(size * -0.03)
    }

    /// A figure.
    func kjStat() -> some View {
        font(.system(size: KJType.stat, weight: .black))
            .tracking(KJType.stat * -0.05)
            .monospacedDigit()
    }

    /// A label: black, upper case, spaced out, in `color` or the palette's accent.
    func kjKicker(_ color: Color? = nil) -> some View {
        modifier(KickerStyle(color: color))
    }

    func kjBody() -> some View {
        font(.system(size: KJType.body))
    }

    /// Small type. `faint` is the palette's secondary tone; otherwise it inherits the ink around it.
    func kjSmall(faint: Bool = false) -> some View {
        modifier(SmallStyle(faint: faint))
    }
}

private struct KickerStyle: ViewModifier {
    let color: Color?
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.system(size: KJType.kicker, weight: .black))
            .textCase(.uppercase)
            .tracking(KJType.kicker * 0.13)
            .foregroundStyle(color ?? palette.accent)
    }
}

private struct SmallStyle: ViewModifier {
    let faint: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        if faint {
            content
                .font(.system(size: KJType.small))
                .foregroundStyle(palette.faint)
        } else {
            content
                .font(.system(size: KJType.small))
        }
    }
}

// MARK: - Controls

/// The website's hover is a band plate under onBand text, and on a television focus is the hover.
/// A pressed control sits on the lift plate. No outline, no shadow: colour and a 1.03 scale.
struct HouseButtonStyle: ButtonStyle {
    let padding: EdgeInsets

    init(padding: EdgeInsets = EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26)) {
        self.padding = padding
    }

    func makeBody(configuration: Configuration) -> some View {
        HouseControl(label: configuration.label, isPressed: configuration.isPressed, padding: padding, kind: .button)
    }
}

/// A card in a shelf, moved as the TV app moves one: focus lifts it to 1.08 on a spring, a soft
/// shadow in the band colour opens under its art or plate, and a press settles it back a little.
/// The style draws no colour of its own. A card with text only sits on a `CardPlate`; one with a
/// picture wears `kjCardArt()` on the picture, so the shadow is the picture's and never the
/// lettering's.
struct HouseCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardControl(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private enum CardMotion {
    static let lift: CGFloat = 1.08
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.74)
}

private struct CardControl<Face: View>: View {
    let label: Face
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .scaleEffect(isPressed ? 1.03 : (isFocused ? CardMotion.lift : 1))
            .animation(CardMotion.spring, value: isFocused)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

/// The soft shadow under a focused card's picture or plate: the band colour, so it stays inside
/// the palette on every skin.
private struct CardShadow: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .shadow(color: palette.band.opacity(isFocused ? 0.55 : 0), radius: isFocused ? 30 : 0, x: 0, y: isFocused ? 20 : 0)
            .animation(CardMotion.spring, value: isFocused)
    }
}

extension View {
    /// For the picture of a card inside a `HouseCardStyle` button.
    func kjCardArt() -> some View {
        modifier(CardShadow())
    }
}

/// The plate of a card that is text alone: the lift plate at rest, the band plate under focus,
/// with the palette its text reads re-skinned for whichever it is on. In a shelf the size is
/// fixed, so the shelf never changes height as its cards arrive. With no width the plate takes
/// the width it is offered and `height` is its least.
struct CardPlate<Content: View>: View {
    let width: CGFloat?
    let height: CGFloat
    let content: Content
    @Environment(\.isFocused) private var isFocused
    @Environment(\.palette) private var palette

    init(width: CGFloat? = nil, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        let look = isFocused ? palette.onFocusPlate : palette
        content
            .multilineTextAlignment(.leading)
            .padding(28)
            .modifier(PlateSize(width: width, height: height))
            .environment(\.palette, look)
            .foregroundStyle(look.ink)
            .background(isFocused ? palette.band : palette.lift)
            .kjCardArt()
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct PlateSize: ViewModifier {
    let width: CGFloat?
    let height: CGFloat

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, height: height, alignment: .topLeading)
        } else {
            content.frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        }
    }
}

/// A picture that arrives by fading in, so a card never pops.
struct FadeIn<Content: View>: View {
    let shown: Bool
    let content: Content

    init(shown: Bool, @ViewBuilder content: () -> Content) {
        self.shown = shown
        self.content = content()
    }

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: shown)
    }
}

/// A navigation or medium switch: a kicker that is plain ink, the current one in the accent with a
/// 3pt rule under it. Focused, it takes the band plate like any other control.
struct HouseTabStyle: ButtonStyle {
    let isCurrent: Bool
    /// The plate's side padding. Tabs on a page pull back by 22 so their text sits on the margin;
    /// the top bar takes 16 so six sections fit at 24 pt.
    let inset: CGFloat

    init(isCurrent: Bool, inset: CGFloat = 22) {
        self.isCurrent = isCurrent
        self.inset = inset
    }

    func makeBody(configuration: Configuration) -> some View {
        HouseControl(
            label: configuration.label, isPressed: configuration.isPressed,
            padding: EdgeInsets(top: 12, leading: inset, bottom: 12, trailing: inset), kind: .tab(isCurrent: isCurrent)
        )
        // The current tab is marked by colour and a rule; VoiceOver is told in words.
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private enum ControlKind {
    case button
    case tab(isCurrent: Bool)
}

/// ButtonStyleConfiguration carries no focus flag on tvOS, so the look is drawn by a view that can
/// read the focus environment of the button it sits inside.
private struct HouseControl<Face: View>: View {
    let label: Face
    let isPressed: Bool
    let padding: EdgeInsets
    let kind: ControlKind
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HousePlate(label: label, isFocused: isFocused, isPressed: isPressed, padding: padding, kind: kind)
    }
}

/// The look, as a function of its inputs and nothing else.
private struct HousePlate<Face: View>: View {
    let label: Face
    let isFocused: Bool
    let isPressed: Bool
    let padding: EdgeInsets
    let kind: ControlKind
    @Environment(\.palette) private var palette

    /// What the label sees from inside the plate.
    private var inner: Palette {
        if isPressed { return palette.onPressPlate }
        if isFocused { return palette.onFocusPlate }
        if case .tab(isCurrent: false) = kind { return palette.onPlainTab }
        return palette
    }

    private var plate: Color {
        if isPressed { return palette.lift }
        return isFocused ? palette.band : .clear
    }

    /// The rule under the current tab, which a plate under it would make redundant.
    private var showsRule: Bool {
        guard case .tab(isCurrent: true) = kind else { return false }
        return !isFocused && !isPressed
    }

    var body: some View {
        let look = inner
        label
            .multilineTextAlignment(.leading)
            .overlay(alignment: .bottom) {
                // An indicator under the text, not a frame: it takes no room in the layout.
                if showsRule {
                    Rectangle()
                        .fill(look.accent)
                        .frame(height: 3)
                        .offset(y: 9)
                }
            }
            .padding(padding)
            .environment(\.palette, look)
            .foregroundStyle(look.ink)
            .background(plate)
            .scaleEffect(isFocused ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
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

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(label)
            Text(value).kjStat()
        }
    }
}

/// A full-width band of kickers on the palette's band colour. It heads every player, as the
/// website's console bar does. The band runs to both edges; its text is inset by `KJLayout.inset`.
struct StatusBand: View {
    let leading: [String]
    let trailing: [String]
    @Environment(\.palette) private var palette

    init(leading: [String], trailing: [String] = []) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(leading.enumerated()), id: \.offset) { item in
                Kicker(item.element, color: palette.onBand)
            }
            Spacer(minLength: 28)
            ForEach(Array(trailing.enumerated()), id: \.offset) { item in
                Kicker(item.element, color: palette.onBand)
            }
        }
        .lineLimit(1)
        .padding(.vertical, 14)
        .padding(.horizontal, KJLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The text stays inside the safe area; the colour runs to the screen's edges, the top
        // included when the band is the first thing on screen.
        .background(palette.band, ignoresSafeAreaEdges: [.horizontal, .top])
    }
}

/// The strip a playing signal wears: one slim band along the bottom in the band colour, the
/// name and its line in the band's text colour, the attribution under them in small type, and
/// the medium and the place at the right. It replaced a top band and a ground panel that
/// covered a third of the picture (owner, 2026-10-05: "too thick and not smooth at all, make
/// it small and better"). It rises and fades in, and sinks and fades out, together.
struct PlayerStrip: View {
    let name: String?
    let detail: String?
    let attribution: String?
    let trailing: [String]
    /// What comes next on a scheduled channel: its start time and its name.
    var upNext: (time: String, name: String)? = nil
    /// The caption control, at the right end, where a press of right reaches it.
    var accessory: AnyView? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    if let name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 30, weight: .black))
                            .tracking(30 * -0.03)
                            .lineLimit(1)
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 24, weight: .semibold))
                            .lineLimit(1)
                            .opacity(0.85)
                    }
                }
                if let attribution, !attribution.isEmpty {
                    Text(attribution)
                        .font(.system(size: 24))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(0.75)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 24)
            ForEach(Array(trailing.enumerated()), id: \.offset) { item in
                Kicker(item.element, color: palette.onBand)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let upNext {
                VStack(alignment: .trailing, spacing: 6) {
                    Kicker("Up next \(upNext.time) \(StationClock.tzLabel)", color: palette.onBand)
                        .lineLimit(1)
                        .fixedSize()
                    Text(upNext.name)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: 520, alignment: .trailing)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("upNext")
            }
            if let accessory {
                accessory
            }
        }
        .foregroundStyle(palette.onBand)
        .padding(.horizontal, KJLayout.inset)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.band, ignoresSafeAreaEdges: [.horizontal, .bottom])
    }
}

/// An on/off control. A button, so it takes focus and the plate like every other one.
struct HouseSwitch: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(title: String, detail: String?, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            SwitchLabel(title: title, detail: detail, isOn: isOn)
        }
        .buttonStyle(HouseButtonStyle())
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A separate view so it reads the palette from inside the button's plate: the track is ink and
/// the knob the ground, which on the focus plate are onBand and the band.
private struct SwitchLabel: View {
    let title: String
    let detail: String?
    let isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Capsule()
                    .fill(palette.ink)
                    .frame(width: 72, height: 40)
                Circle()
                    .fill(palette.ground)
                    .frame(width: 30, height: 30)
                    .offset(x: isOn ? 16 : -16)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).kjKicker(palette.ink)
                if let detail {
                    // One line, run into the gap beside it rather than wrapped or cut: a second line
                    // moved the switch below the region strip, and left off the strip's west end
                    // stopped reaching it.
                    Text(detail).kjSmall(faint: true).fixedSize()
                }
            }
        }
    }
}

/// When a player's or reader's overlay hides itself: after ~2.6 s idle (frontend.md §4), and
/// never while VoiceOver or Switch Control is running, because the overlay is how those viewers
/// reach anything.
enum OverlayTiming {
    static let idle: Duration = .seconds(2.6)
    static var hidesItself: Bool { !UIAccessibility.isVoiceOverRunning && !UIAccessibility.isSwitchControlRunning }
}

/// What a screen says while it waits: the website receiver's grooming pigeon over the words.
/// Retired on 2026-10-05 for one pigeon; brought back on the loaders only (owner, 2026-10-08).
/// The flying pigeon still carries the channel change.
struct TuningLoader: View {
    let label: String?
    let bird: CGFloat

    /// nil draws no words, for a screen that already says what it is waiting for. `bird` is the
    /// pigeon's width: the site's cap of 200 points, smaller in a shelf's placeholder.
    init(_ label: String? = "Connecting\u{2026}", bird: CGFloat = 200) {
        self.label = label
        self.bird = bird
    }

    var body: some View {
        VStack(spacing: 16) {
            GroomingPigeon(width: bird)
            if let label, !label.isEmpty {
                Kicker(label)
            }
        }
    }
}

/// The grooming loop (ios/scripts/make-tuning-pigeon.sh, 300x276 HEVC with alpha). One player
/// for every loader on screen, playing only while one is: the Apple TV HD decodes HEVC in
/// software. Reduce Motion holds it on its first frame.
private struct GroomingPigeon: View {
    let width: CGFloat

    var body: some View {
        PlayerLayerView(player: GroomingLoop.shared.player)
            .frame(width: width, height: width * 276 / 300)
            .onAppear { GroomingLoop.shared.retain() }
            .onDisappear { GroomingLoop.shared.release() }
            .accessibilityHidden(true)
    }
}

@MainActor
private final class GroomingLoop {
    static let shared = GroomingLoop()
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var watchers = 0

    private init() {
        // The bird must never take the audio session from a signal.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        if let url = Bundle.main.url(forResource: "tuning-pigeon", withExtension: "mov") {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }

    func retain() {
        watchers += 1
        if !UIAccessibility.isReduceMotionEnabled { player.play() }
    }

    func release() {
        watchers = max(watchers - 1, 0)
        if watchers == 0 { player.pause() }
    }
}

// MARK: - Sections and the top bar

/// The root screens. This name shadows SwiftUI's `Section` inside this module; a list
/// section is written `SwiftUI.Section`.
enum Section: String, CaseIterable, Identifiable {
    case receiver
    case transmission
    case reading
    case picsvids
    case chat
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receiver: return "Receiver"
        case .transmission: return "Transmission"
        // The website's own nav label (kj-chrome.js, door `read`: READING ROOM).
        case .reading: return "Reading Room"
        // The website's own nav label (kj-chrome.js, door `picsnvids`: PICS/VIDS).
        case .picsvids: return "Pics/Vids"
        case .chat: return "Chat"
        case .account: return "Account"
        }
    }
}

/// On every root screen: the pigeon and the name at left, the sections at right. There is
/// no system tab bar, because tvOS paints its focused tab as a white pill.
struct TopBar: View {
    let current: Section
    let select: (Section) -> Void
    /// Focus enters the bar on the section on screen, so a first press never jumps elsewhere.
    @FocusState private var focused: Section?

    init(current: Section, select: @escaping (Section) -> Void) {
        self.current = current
        self.select = select
    }

    var body: some View {
        HStack(spacing: 40) {
            HStack(spacing: 18) {
                PigeonMark(size: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KHAJISTAN").kjName(40)
                    Text("Media of the Middle World").kjSmall(faint: true).lineLimit(1).fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Khajistan")
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(Section.available) { section in
                    Button {
                        select(section)
                    } label: {
                        // The tab style sets this kicker's colour: accent for the current
                        // section, ink for the others, onBand under focus.
                        // One line always: six sections fill the bar, and a name never wraps.
                        Text(section.title).kjKicker().lineLimit(1).fixedSize()
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: section == current, inset: 16))
                    .focused($focused, equals: section)
                    .accessibilityIdentifier("nav-\(section.rawValue)")
                }
            }
            .defaultFocus($focused, current)
        }
        // The launch focus is the system's first pick, top-left; place it on the current tab.
        .onAppear { focused = current }
        .padding(.horizontal, KJLayout.inset)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .focusSection()
    }
}

// MARK: - The focus target

/// A button that draws nothing and shows no focus effect. It is the focus target of a
/// full-screen player surface, so the remote's presses have somewhere to land.
struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
    }
}
