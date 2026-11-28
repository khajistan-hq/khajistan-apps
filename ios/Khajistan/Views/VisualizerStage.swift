import SwiftUI

/// What a full-screen sound channel shows on the iPhone: the channel's name alone, as before, or a
/// Khajistan visualizer behind it, as the viewer has chosen (Core/Visualizer.swift, shared with
/// the Apple TV app; owner, 2026-11-25: "create these multiple visualizers that on demand can play
/// just like how the dancer shows up in all of the audio"). The phone has no dancer, so its sound
/// channels cycle Off and Khajistan, and a reverent channel Off and Nature; Khajistan and Nature are
/// the defaults (owner, 2026-11-26: "for all audio channels make the khajistan viusalizer the default
/// option"), and the name stands on the ground until the picture is up. The picture is an After
/// Hours piece on a muted player of its own (Player/VisualizerPlayer.swift, shared), under the
/// channel's sound: a failure, or a viewer not signed in, only leaves the name on the ground.
/// Reduce Motion: no picture. The caller draws this only where there is no picture of its own.
struct VisualizerStage<Name: View>: View {
    let controller: PlayerController
    let reverent: Bool
    @ViewBuilder let name: () -> Name

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VisualizerMode.key) private var stored = VisualizerMode.khajistan.rawValue
    @AppStorage(VisualizerMode.natureKey) private var storedNature = VisualizerMode.nature.rawValue
    @State private var picture = VisualizerPlayer()

    private struct Want: Equatable { let play: Bool; let reverent: Bool; let signedIn: Bool }

    var body: some View {
        let mode = VisualizerMode.current(reverent: reverent, stored: stored, storedNature: storedNature, dancer: false)
        let play = !reduceMotion && mode.playsPicture && controller.state == .playing
        let shown = play && picture.ready
        ZStack {
            if play {
                // Attached from the start, invisible until ready: an AVPlayer with no layer and no play()
                // can sit at "unknown" for good (measured 2026-11-26 on the owner's Apple TV HD).
                // Two players, as on the TV: the next piece fades in over the one it replaces.
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        PlayerLayerView(player: picture.players[i], gravity: .resizeAspectFill)
                            .opacity(shown && (picture.front == i || picture.outgoing == i) ? 1 : 0)
                            .zIndex(picture.front == i ? 1 : 0)
                    }
                }
                .animation(.linear(duration: VisualizerPlayer.fade), value: picture.front)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // The name moves to the top right while the picture plays, as it does on the TV.
            name()
                .scaleEffect(shown ? 0.45 : 1, anchor: .topTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shown ? .topTrailing : .center)
                .padding(.top, shown ? 64 : 0)
                .padding(.trailing, shown ? KJLayout.inset : 0)
            // When the picture fails, one line says why, as on the TV; only a failure, never the loading steps
            // (owner, 2026-11-27, on the TV's line: "sticky visualizer message on every tv channel"). At the top
            // here, because the phone's controls sit over the bottom of the screen.
            if play, !picture.ready, let problem = picture.problem {
                Text("Khajistan visualizer: \(problem)")
                    .kjSmall(faint: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, KJLayout.inset)
                    .padding(.top, 64)
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

/// The player panel's control, beside CC: "Visualizer · Off", "· Khajistan"; "· Nature" on a
/// reverent channel. A tap moves to the next.
struct VisualizerButton: View {
    let reverent: Bool
    var wake: () -> Void = {}
    @AppStorage(VisualizerMode.key) private var stored = VisualizerMode.khajistan.rawValue
    @AppStorage(VisualizerMode.natureKey) private var storedNature = VisualizerMode.nature.rawValue

    var body: some View {
        let mode = VisualizerMode.current(reverent: reverent, stored: stored, storedNature: storedNature, dancer: false)
        Button {
            wake()
            let next = mode.next(reverent: reverent, dancer: false).rawValue
            if reverent { storedNature = next } else { stored = next }
        } label: {
            Text(mode.label).kjKicker().padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
        .accessibilityLabel(mode.label)
        .accessibilityHint("Changes the visualizer")
        .accessibilityIdentifier("visualizerControl")
    }
}
