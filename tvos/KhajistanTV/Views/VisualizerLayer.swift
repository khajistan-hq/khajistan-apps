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
    @AppStorage(VisualizerMode.key) private var stored = VisualizerMode.khajistan.rawValue
    @AppStorage(VisualizerMode.natureKey) private var storedNature = VisualizerMode.nature.rawValue
    @State private var picture = VisualizerPlayer()

    private struct Want: Equatable { let play: Bool; let reverent: Bool; let signedIn: Bool }

    var body: some View {
        let mode = VisualizerMode.current(reverent: reverent, stored: stored, storedNature: storedNature)
        let play = eligible && !reduceMotion && mode.playsPicture && controller.state == .playing
        let dancer = !eligible || (mode != .off && !(play && picture.ready) && !reverent)
        ZStack {
            if dancer {
                // The dancer as before; in Khajistan mode he stands in until the picture is up.
                DancerLayer(controller: controller, behind: behind)
            }
            if play {
                // Attached from the start, invisible until ready: on Apple TV an AVPlayer with no layer and
                // no play() can sit at "unknown" for good (measured 2026-11-26 on the owner's Apple TV HD:
                // stuck at "opening the picture" on a plain 960x540 H.264 file Channel 1 plays fine).
                PlayerLayerView(player: picture.player, gravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .opacity(picture.ready ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if play && picture.ready {
                // The name moves to the top right, as it does for the dancer.
                behind()
                    .scaleEffect(0.45, anchor: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 64)
                    .padding(.trailing, KJLayout.inset)
            } else if !dancer {
                behind().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // When the picture cannot come, one line says why (owner, 2026-11-26: "khajistan visualizer
            // isnt showing on my apple tv"); the dancer stands in meanwhile.
            if mode.playsPicture, !picture.ready {
                // Until the picture is up, the step it is on, so a hang shows as clearly as a failure.
                let step = !play ? (controller.state == .playing ? "off for this channel" : "waiting for the channel to play")
                    : (picture.problem ?? picture.step)
                Text("Khajistan visualizer: \(step)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, KJLayout.inset)
                    .padding(.bottom, 40)
                    .allowsHitTesting(false)
            }
        }
        .task(id: Want(play: play, reverent: reverent, signedIn: model.auth.isSignedIn)) {
            guard play else { return picture.stop() }
            await picture.run(reverent: reverent, auth: model.auth)
        }
        .onDisappear { picture.stop() }
    }
}
