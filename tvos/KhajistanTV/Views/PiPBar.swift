import SwiftUI

/// The picture in the corner window, as a band along the foot of the screen while the viewer
/// browses: what is playing, Full screen, Play/Pause, its subtitles or captions, and Close. The
/// window itself cannot take the remote's focus (only tvOS's own menu, behind the TV button, reaches
/// it), so the bar is how the window is worked from inside the app (owner, 2026-11-17: "hard to
/// navigate into small pip window and click it back up to full screen"). Full screen is lit as the
/// window opens, so one press of Select brings the picture back; Down reaches the bar from any page
/// after that, the root's and every cover's alike (PiPBarHost).
///
/// It stops short of the right-hand 40% of the screen, where tvOS puts the window by default.
struct PiPBar: View {
    let pip: PictureInPicture
    var focus: FocusState<Bool>.Binding
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pip.title).kjName(30).lineLimit(1)
                Text("Picture in picture \u{00B7} " + (pip.isPlaying ? "Playing" : "Paused")).kjSmall().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { pip.restore() } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right").kjBarLabel()
            }
            .buttonStyle(OnBandStyle())
            .focused(focus)
            .accessibilityIdentifier("pipBarFullScreen")
            Button { pip.setPlaying(!pip.isPlaying) } label: {
                Image(systemName: pip.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .bold)).frame(width: 52)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel(pip.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("pipBarToggle")
            if let label = pip.captionLabel?() {
                Button { pip.onCaptionToggle?() } label: { Text(label).kjBarLabel() }
                    .buttonStyle(OnBandStyle())
                    .accessibilityIdentifier("pipBarCaptions")
            }
            Button { pip.close() } label: {
                Label("Close", systemImage: "xmark").kjBarLabel()
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel("Close picture in picture")
            .accessibilityIdentifier("pipBarClose")
        }
        .foregroundStyle(palette.onBand)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(palette.band)
        .frame(maxWidth: 1080, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KJLayout.inset)
        .padding(.bottom, 24)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pipBar")
    }
}

private extension View {
    func kjBarLabel() -> some View {
        font(.system(size: KJType.kicker, weight: .black)).textCase(.uppercase).lineLimit(1).fixedSize()
    }
}

/// Puts the PiP bar on a screen while the corner window is up, lights its Full screen as the window
/// opens, and gives the remote's Play/Pause to the window. On the root and on every cover
/// (`kjFullScreenCover`), because a window opened from a film page lands the viewer on that page,
/// which is a cover over the root.
struct PiPBarHost: ViewModifier {
    /// The root has its own Play/Pause (the radio bar) and passes false.
    var handlesPlayPause = true
    @Environment(AppModel.self) private var model
    @FocusState private var focus: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            // An inset, not an overlay: the page moves up for it, so nothing at the foot is
            // hidden under the bar. Only the screen on top carries it: a screen under a cover is
            // still drawn, and a second bar there would be a second Full screen for VoiceOver.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pip = model.activePiP, PiPBarStack.shared.top == id { PiPBar(pip: pip, focus: $focus) }
            }
            .onAppear { PiPBarStack.shared.push(id) }
            .onDisappear { PiPBarStack.shared.remove(id) }
            // tvOS hands focus back to the card that opened the player when its cover finishes
            // closing, which can land after a first try: Full screen is asked for until it has held
            // twice running, for a second and a half at most.
            .onChange(of: model.activePiP != nil) { _, up in
                guard up else { return }
                Task {
                    var held = 0
                    for _ in 0..<6 where held < 2 {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard model.activePiP != nil else { return }
                        if focus { held += 1 } else { held = 0; focus = true }
                    }
                }
            }
            .onPlayPauseCommand(perform: handlesPlayPause ? model.activePiP.map { pip in { pip.setPlaying(!pip.isPlaying) } } : nil)
    }
}

/// The screens that can carry the PiP bar, in the order they came up: the root, then each cover
/// over it. A cover's host appears after the screen it covers and goes when it closes, so the last
/// one is the screen on top.
@MainActor @Observable
final class PiPBarStack {
    static let shared = PiPBarStack()
    private(set) var ids: [UUID] = []
    var top: UUID? { ids.last }
    func push(_ id: UUID) { if !ids.contains(id) { ids.append(id) } }
    func remove(_ id: UUID) { ids.removeAll { $0 == id } }
}

extension View {
    func pipBarHost(handlesPlayPause: Bool = true) -> some View { modifier(PiPBarHost(handlesPlayPause: handlesPlayPause)) }

    /// A full-screen cover that carries the PiP bar.
    func kjFullScreenCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                            @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { content($0).pipBarHost() }
    }

    /// A full-screen cover that carries the PiP bar.
    func kjFullScreenCover<Cover: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Cover) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { content().pipBarHost() }
    }
}

/// Opens a screen over whatever is on top, as Full screen from the picture-in-picture window must:
/// SwiftUI cannot present from the root while a page or a room is a cover over it, and the window
/// has already closed by then, so the picture would play on as sound with nothing on screen
/// (Fable round 2: a Receiver channel restored over the Screening Room did exactly that).
/// `otherwise` runs when there is no window to present on, or a closing screen refuses it.
@MainActor
enum TopScreen {
    static func present<Screen: View>(model: AppModel, otherwise: @escaping () -> Void,
                                      _ make: @escaping (_ close: @escaping () -> Void) -> Screen) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        // The key window, else the app's one window: on a restore from another app the window may
        // not be key yet when AVKit asks.
        guard var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else { return otherwise() }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        // A screen still closing above `top` refuses a present: wait for it to finish.
        if let closing = top.presentedViewController {
            if let coordinator = closing.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in present(model: model, otherwise: otherwise, make) }
            } else {
                otherwise()
            }
            return
        }
        weak var host: UIViewController?
        // The root's environment does not reach a UIKit-presented screen: the model and the skin go with it.
        let palette = Palette(model.skin)
        let screen = make({ host?.dismiss(animated: true) })
            .environment(model)
            .environment(\.palette, palette)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
        let controller = UIHostingController(rootView: screen)
        controller.modalPresentationStyle = .fullScreen
        host = controller
        top.present(controller, animated: true)
    }
}
