import SwiftUI

/// What a sound channel shows in place of a picture: the dancer, a Khajistan visualizer, or the
/// channel's name alone, as the viewer has chosen (Core/Visualizer.swift). The visualizer is an
/// After Hours picture on a muted AVPlayer of its own (Player/VisualizerPlayer.swift), under the
/// channel's sound, so it never touches the signal: a failure only means the dancer (in Dancer's
/// place) or the plain ground.
///
/// `eligible` false draws exactly what was here before the visualizers: the DancerLayer.
struct SoundStage<Behind: View>: View {
    let controller: PlayerController
    /// Sound with no picture, where the dancer could be: radio, or a sound-only programme.
    let eligible: Bool
    let reverent: Bool
    @ViewBuilder let behind: () -> Behind

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VisualizerMode.key) private var stored = VisualizerMode.dancer.rawValue
    @AppStorage(VisualizerMode.natureKey) private var storedNature = VisualizerMode.off.rawValue
    @State private var picture = VisualizerPlayer()

    private struct Want: Equatable { let play: Bool; let reverent: Bool; let signedIn: Bool }

    var body: some View {
        let mode = VisualizerMode.current(reverent: reverent, stored: stored, storedNature: storedNature)
        let play = eligible && !reduceMotion && mode.playsPicture && controller.state == .playing
        ZStack {
            if !eligible || (mode != .off && !(play && picture.ready) && !reverent) {
                // The dancer as before; in Khajistan mode he stands in until the picture is up.
                DancerLayer(controller: controller, behind: behind)
            } else if play && picture.ready {
                PlayerLayerView(player: picture.player, gravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                // The name moves to the top right, as it does for the dancer.
                behind()
                    .scaleEffect(0.45, anchor: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 64)
                    .padding(.trailing, KJLayout.inset)
            } else {
                behind().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: Want(play: play, reverent: reverent, signedIn: model.auth.isSignedIn)) {
            guard play else { return picture.stop() }
            await picture.run(reverent: reverent, auth: model.auth)
        }
        .onDisappear { picture.stop() }
    }
}
