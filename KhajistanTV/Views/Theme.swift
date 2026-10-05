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
    static let kicker: CGFloat = 22
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

/// A navigation or medium switch: a kicker that is plain ink, the current one in the accent with a
/// 3pt rule under it. Focused, it takes the band plate like any other control.
struct HouseTabStyle: ButtonStyle {
    let isCurrent: Bool

    init(isCurrent: Bool) {
        self.isCurrent = isCurrent
    }

    func makeBody(configuration: Configuration) -> some View {
        HouseControl(
            label: configuration.label, isPressed: configuration.isPressed,
            padding: EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22), kind: .tab(isCurrent: isCurrent)
        )
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
                    Text(detail).kjSmall(faint: true)
                }
            }
        }
    }
}

// MARK: - The pigeon

/// An animated GIF or WebP from the app bundle, played by ImageIO. Reduce Motion, or a file
/// ImageIO will not animate, shows the first frame; a file that is not there draws nothing.
struct AnimatedImage: View {
    let resource: String
    let ext: String
    @State private var currentFrame: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(resource: String, withExtension ext: String) {
        self.resource = resource
        self.ext = ext
    }

    var body: some View {
        content
            // The id restarts the task when Reduce Motion changes while the image is on screen.
            .task(id: "\(resource).\(ext).\(reduceMotion)") { await run() }
    }

    @ViewBuilder
    private var content: some View {
        if let currentFrame {
            Image(decorative: currentFrame, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }

    private func run() async {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            currentFrame = nil
            return
        }
        if reduceMotion || UIAccessibility.isReduceMotionEnabled {
            currentFrame = Self.firstFrame(of: url)
            return
        }
        let stopper = Stopper()
        // Runs when the task ends: the view left the screen, or this function returned early.
        defer { stopper.stop() }
        let status = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { _, image, stop in
            if stopper.isStopped {
                stop.pointee = true
                return
            }
            DispatchQueue.main.async {
                if !stopper.isStopped { currentFrame = image }
            }
        }
        if status != noErr {
            currentFrame = Self.firstFrame(of: url)
            return
        }
        // ImageIO keeps animating until the block says stop, so this task waits for its own
        // cancellation and the `defer` above tells the block.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    private static func firstFrame(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// The flag the animation block reads. It is written from the task and read from ImageIO's
/// callback, so it is behind a lock.
private final class Stopper: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

/// The Khajistan pigeon, the 1080px master, still when Reduce Motion is on.
struct PigeonMark: View {
    let size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        AnimatedImage(resource: "pigeon", withExtension: "gif")
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// What a screen says while it waits. The grooming pigeon that stood here was retired in the
/// apps on 2026-10-05 (owner: one pigeon, the flying one, which carries the channel change).
struct TuningLoader: View {
    let label: String?

    /// nil draws nothing, for a screen that already says what it is waiting for.
    init(_ label: String? = "Connecting\u{2026}") {
        self.label = label
    }

    var body: some View {
        if let label, !label.isEmpty {
            Kicker(label)
        }
    }
}

// MARK: - Sections and the top bar

/// The three root screens. This name shadows SwiftUI's `Section` inside this module; a list
/// section is written `SwiftUI.Section`.
enum Section: String, CaseIterable, Identifiable {
    case receiver
    case transmission
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receiver: return "Receiver"
        case .transmission: return "Transmission"
        case .account: return "Account"
        }
    }
}

/// On every root screen: the pigeon and the name at left, the three sections at right. There is
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
                    Text("Media of the Middle World").kjSmall(faint: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Khajistan")
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ForEach(Section.allCases) { section in
                    Button {
                        select(section)
                    } label: {
                        // The tab style sets this kicker's colour: accent for the current
                        // section, ink for the others, onBand under focus.
                        Text(section.title).kjKicker()
                    }
                    .buttonStyle(HouseTabStyle(isCurrent: section == current))
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
