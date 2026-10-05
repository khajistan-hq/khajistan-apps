import SwiftUI

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

/// The three colours of the current skin. Text is always `ink`; a focused plate is `lift`.
struct Palette {
    let ground: Color
    let ink: Color
    let lift: Color

    init(_ skin: Skin) {
        ground = Color(hex: skin.groundHex)
        ink = Color(hex: skin.inkHex)
        lift = Color(hex: skin.liftHex)
    }
}

/// Television sizes. A namespace of its own so nothing here can be mistaken for SwiftUI's
/// own `Font.title` and `Font.body`.
enum KJFont {
    static func title() -> Font { .system(size: 56, weight: .bold) }
    static func heading() -> Font { .system(size: 40, weight: .semibold) }
    static func body() -> Font { .system(size: 31) }
    static func bodyBold() -> Font { .system(size: 31, weight: .bold) }
    static func caption() -> Font { .system(size: 25) }
}

/// A plate that sits on the ground and rises to the lift colour, one step larger, under focus.
/// No stroke, no frame, no outline: the colour change and the scale are the whole effect.
struct PlateButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PlateBody(palette: palette, configuration: configuration)
    }
}

/// ButtonStyleConfiguration carries no focus flag on tvOS, so the look lives in a view that
/// can read the focus environment of the button it sits inside.
private struct PlateBody: View {
    let palette: Palette
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.ink)
            .background(isFocused ? palette.lift : palette.ground)
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A switch drawn as a plate, so it takes the same focus look as every other control.
struct PlateToggleStyle: ToggleStyle {
    let palette: Palette

    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Text(configuration.isOn ? "On" : "Off")
            }
        }
        .buttonStyle(PlateButtonStyle(palette: palette))
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A button that draws nothing and shows no focus effect. It is the focus target of a
/// full-screen player surface, so the remote's presses have somewhere to land.
struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
    }
}
