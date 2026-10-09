import SwiftUI

/// A receiver channel, full screen. Up and down tune the neighbouring channel in the list the
/// viewer came from, behind the pigeon (StationClips); play/pause pauses, and pressing it again tunes the
/// channel afresh, because a live signal paused for a minute is not the live signal any more.
///
/// Live captions: where the channel offers them the strip ends in the Captions control. Right moves
/// to it and left comes back; Select on it turns captions on or off. Play/Pause, Select on the
/// picture and up/down are already the player's, and a control the viewer can see in the strip says
/// what it does, which a hidden gesture would not.
struct ReceiverPlayerView: View {
    let list: [Channel]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Two signals: the one on screen, and the next one tuning out of sight and out of hearing
    /// until the cut. Each keeps its own layer, so the cut is a change of which layer shows.
    @State private var playerA = PlayerController()
    @State private var playerB = PlayerController()
    @State private var aIsFront = true
    @State private var current: Channel
    /// The channel the last up or down press asked for, until the wipe has tuned it. A second
    /// press steps on from here, not from the channel still on screen.
    @State private var destination: Channel?
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var tuneTask: Task<Void, Never>?
    @State private var changeTask: Task<Void, Never>?
    /// The Captions control takes focus only when the viewer moves right to it, so the focus engine
    /// never lands on it from an up or down press, which change channel.
    /// The strip control the remote has lit: Right lights Captions (when offered) then Like, Left
    /// lets go, Select works it. Focus never leaves the surface (see below).
    @State private var armed: Chip?
    @State private var likeNote: String?
    private enum Chip { case captions, like }
    private var captionArmed: Bool { armed == .captions }
    @State private var stripHeight: CGFloat = 0
    @FocusState private var focus: PlayerFocus?

    /// The signal on screen, which everything on the screen reads.
    private var controller: PlayerController { aIsFront ? playerA : playerB }
    /// The signal a channel change tunes, behind the one on screen.
    private var incoming: PlayerController { aIsFront ? playerB : playerA }

    init(channel: Channel, list: [Channel]) {
        self.list = list
        _current = State(initialValue: channel)
    }

    var body: some View {
        // Taken from the skin and handed down, so the clip layer and the kickers read it even in
        // the full-screen cover, which is a hosting controller of its own.
        let palette = Palette(model.skin)
        ZStack {
            // A picture that does not fill the screen sits on black, whatever the skin (owner,
            // 2026-10-05). Radio, which has no picture, keeps the skin's ground.
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: playerA.player)
                .ignoresSafeArea()
                .opacity(aIsFront ? 1 : 0)
            PlayerLayerView(player: playerB.player)
                .ignoresSafeArea()
                .opacity(aIsFront ? 0 : 1)
            // Radio: the dancer, when the carrier can be read and the stream carries a beat, in
            // front of the channel's name. The band says live radio; the centre carries the name.
            DancerLayer(controller: controller) {
                if current.mediaType == "radio" && controller.state == .playing {
                    Text(current.name)
                        .kjDisplay()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, KJLayout.inset)
                }
            }
            // The focus target. It draws nothing; its job is to hold focus so the remote's
            // presses reach the handlers below. A click works the Captions control when the viewer
            // has moved to it, and otherwise wakes the overlay. Focus never leaves it: moving
            // focus onto a control as it appears did not take on a real Apple TV, so Select fell
            // through to here and captions could not be turned on (owner, 2026-10-06).
            Button {
                switch armed {
                case .captions: model.captions.toggle()
                case .like: like()
                case nil: wake()
                }
            } label: {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
            .focused($focus, equals: .surface)
            overlay(palette)
            CaptionLayer(text: model.captions.text, skin: model.skin, lift: stripShown ? stripHeight : 0)
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            wake()
            switch direction {
            case .up: armed = nil; step(by: -1)
            case .down: armed = nil; step(by: 1)
            case .right: moveRight()
            case .left: moveLeft()
            default: break
            }
        }
        .onPlayPauseCommand {
            wake()
            // During a change the channel coming in is the one that matters; retuning the one
            // going out would cancel it and leave the new channel on "Connecting" for good.
            guard destination == nil else { return }
            if controller.state == .playing {
                controller.pause()
            } else {
                tune(current)
            }
        }
        .onExitCommand {
            stopEverything()
            dismiss()
        }
        .onChange(of: controller.state) { wake() }
        .task {
            await open()
            #if DEBUG
            // `-kjautochange 6` steps to the next channel that many times, ten seconds apart, so
            // the flights can be measured on a device with no one at the remote.
            let n = UserDefaults.standard.integer(forKey: "kjautochange")
            for _ in 0..<n {
                try? await Task.sleep(for: .seconds(10))
                print("KJCLOCK \(current.id) \(controller.clockReport)")
                if Task.isCancelled { return }
                step(by: 1)
            }
            #endif
        }
        .task { await model.saves.load() }
        .onDisappear { stopEverything() }
    }

    // MARK: - Overlay

    /// The status band across the top and the panel on the ground below. Both go together.
    private func overlay(_ palette: Palette) -> some View {
        // During a change the strip names where the viewer is going, not the channel being left.
        let shown = destination ?? current
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlayerStrip(
                // Radio carries its name in display type on the ground; the strip leaves it out.
                name: destination == nil && current.mediaType == "radio" && controller.state == .playing ? nil : shown.name,
                detail: stripDetail,
                attribution: shown.sourceLine,
                trailing: stripTrailing,
                accessory: controller.state.isFailed ? nil : AnyView(stripControls)
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
            .offset(y: stripShown ? 0 : 40)
            .opacity(stripShown ? 1 : 0)
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: stripShown)
        .overlay(alignment: .bottomLeading) {
            // The state, for tests and VoiceOver; the strip shows only a reason, never "Playing".
            Text(stateText)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("playerState")
                .overlay {
                    // Which channel is on screen, for the UI tests.
                    Text(current.id)
                        .font(.system(size: 1))
                        .opacity(0.01)
                        .accessibilityIdentifier("currentChannel")
                }
        }
    }

    /// While a signal tunes the ground already says so; the strip waits for the picture.
    private var stripShown: Bool {
        guard overlayVisible else { return false }
        switch controller.state {
        case .playing, .paused, .failed: return true
        case .idle, .tuning: return false
        }
    }

    /// What follows the name: a failure's reason, Paused, the captions' note, or the place.
    private var stripDetail: String? {
        if let destination { return destination.place.isEmpty ? nil : destination.place }
        switch controller.state {
        case .failed(let message): return message + " Press Down for the next channel."
        case .paused: return "Paused"
        default:
            if let likeNote { return likeNote }
            if !model.captions.note.isEmpty { return model.captions.note }
            return current.place.isEmpty ? nil : current.place
        }
    }

    /// The site's Captions button: its label says what is on and what is left. Right lights it,
    /// Select works it, left lets it go; no up or down press can land on it.
    private var captionsControl: some View {
        StripChipStyle.face(Text(model.captions.label), isOn: model.captions.isOn, selected: captionArmed)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("captionsControl")
            // Lit by the remote rather than focused: tests and VoiceOver read it as selected.
            .accessibilityAddTraits(captionArmed ? .isSelected : [])
            .accessibilityValue(model.captions.isOn ? "On" : "Off")
    }

    private var stripControls: some View {
        HStack(spacing: 14) {
            if model.captions.offered { captionsControl }
            likeControl
        }
    }

    /// Like: saved on the account, so it is on the dashboard and every device signed in to it.
    private var likeControl: some View {
        let liked = model.saves.isSaved(current)
        return StripChipStyle.face(Text(liked ? "Liked" : "Like"), isOn: liked, selected: armed == .like)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("likeControl")
            .accessibilityAddTraits(armed == .like ? .isSelected : [])
            .accessibilityValue(liked ? "On" : "Off")
    }

    private func moveRight() {
        // A failed channel's strip carries no controls, so there is nothing to the right.
        guard stripShown, !controller.state.isFailed else { return }
        hideTask?.cancel()
        switch armed {
        case nil: armed = model.captions.offered ? .captions : .like
        case .captions: armed = .like
        case .like: break
        }
    }

    private func moveLeft() {
        switch armed {
        case .like: armed = model.captions.offered ? .captions : nil
        case .captions: armed = nil
        case nil: return
        }
        if armed == nil { wake() }
    }

    private func like() {
        guard model.saves.canSave else {
            say("Sign in under Account to like channels.")
            return
        }
        let channel = current
        Task {
            await model.saves.load()
            if !(await model.saves.toggle(channel)) { say("That did not save. Try again.") }
        }
    }

    private func say(_ line: String) {
        likeNote = line
        Task {
            try? await Task.sleep(for: .seconds(4))
            if likeNote == line { likeNote = nil }
        }
    }

    /// The medium only: the place is already beside the name, and one thing is said once.
    private var stripTrailing: [String] {
        controller.state.isFailed ? ["Off the air"] : ["\u{25CF} \(liveLabel)"]
    }

    private var liveLabel: String {
        switch current.mediaType.lowercased() {
        case "tv": return "Live television"
        case "radio": return "Live radio"
        case "camera": return "Camera"
        default: return "Live"
        }
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return ""
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"   // the band already names the medium
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    /// The signal on screen has a picture: television or a camera, playing or paused.
    private var showsPicture: Bool {
        current.mediaType != "radio" && (controller.state == .playing || controller.state == .paused)
    }

    // MARK: - Tuning

    /// Resolves the channel's carrier and plays it on the signal on screen, or, for a channel
    /// change, on the one behind it, silent until the cut. A tuning the viewer has already moved
    /// on from is cancelled and says nothing.
    private func tune(_ target: Channel, behind: Bool = false) {
        tuneTask?.cancel()
        let player = behind ? incoming : controller
        player.stop()
        player.holdsSound = behind
        player.state = .tuning
        if !behind { current = target }
        wake()
        tuneTask = Task {
            do {
                let url = try await model.receiver.resolve(target)
                try Task.checkCancellation()
                player.attach(
                    url: url,
                    seekTo: nil,
                    title: target.name,
                    subtitle: target.place.isEmpty ? nil : target.place,
                    // Radio only: television and cameras carry a picture (owner, 2026-07-21).
                    listen: dancerMayListen(target),
                    // A live mount the app plays itself, so its samples can be read; HLS stays
                    // on AVPlayer and has no dancer.
                    live: target.activeStream?.format != "hls" && !url.path.lowercased().hasSuffix(".m3u8")
                )
                if !behind { model.captions.attach(target, player: player) }
            } catch {
                if Task.isCancelled { return }
                PlayerController.log.error("resolve \(target.id, privacy: .public): \(String(describing: error), privacy: .public)")
                player.state = .failed(PlayerController.unreachable)
            }
        }
    }

    /// The dancer: radio, not reverent, and not for a viewer who has asked for less motion (who
    /// then gets AVPlayer, as before).
    private func dancerMayListen(_ channel: Channel) -> Bool {
        channel.mediaType == "radio" && !channel.isReverent && !reduceMotion
    }

    /// The neighbour of the channel last asked for, wrapping at either end, reached behind the
    /// pigeon. A press while a flight is on screen ends that flight and takes over from it.
    private func step(by delta: Int) {
        let from = destination ?? current
        guard list.count > 1, let position = list.firstIndex(where: { $0.id == from.id }) else { return }
        let target = list[(position + delta + list.count) % list.count]
        destination = target
        changeTask?.cancel()
        changeTask = Task { await change(to: target) }
    }

    /// The screen opens on the ground with the channel's name, which fades off the picture as it
    /// arrives.
    private func open() async {
        model.clips.cover(caption: current.name, animated: false)
        tune(current)
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
    }

    /// The pigeon flies over the picture while the next channel tunes behind it, out of sight and
    /// silent; the channel hard-cuts the moment the new one plays, with the bird flying on over
    /// it, and only the sound fades (owner, 2026-10-06; cut on readiness 2026-10-07).
    /// A channel known to take 8 s or more gets a long flight; one that outlasts its flight gets
    /// another. A press during a change retunes behind the bird already flying.
    private func change(to target: Channel) async {
        let outgoing = controller, next = incoming, pigeon = model.pigeon
        // The tune starts first and the bird is armed while it runs: arming took up to 2 s on the
        // Apple TV HD, and the signal used to wait for it (roast, 2026-10-07).
        async let quiet: Void = outgoing.fadeOut()
        let started = ContinuousClock.now
        tune(target, behind: true)
        if !pigeon.isFlying, !reduceMotion,
           let pick = pigeon.pick(expected: TuneTimes.expected(target.id, fallback: target.mediaType == "radio" ? 1.5 : 2.5)) {
            await pigeon.arm(pick)
            guard !Task.isCancelled else { await quiet; return }
            pigeon.start()
        }
        // The channel's own tune time, from now to its first frame; never the wait for the bird.
        // Read live (State storage), so a press on to another channel stops the timing.
        TuneTimes.recordWhenPlaying(target.id, player: next, since: started) {
            destination?.id == target.id || current.id == target.id
        }
        // `destination` stays set until the cut: the channel on screen changes only then, and a
        // press before it must step on from the channel asked for, not the one still showing.
        while !Task.isCancelled {
            switch next.state {
            case .playing, .failed:
                // Ready: cut now, with the bird flying on over the new picture (owner,
                // 2026-10-07). Waiting for the wing to cover the cut cost ~4 s a press.
                cut(to: target, from: outgoing, into: next, tookSince: started)
                await quiet
                return
            default:
                // Still tuning and the bird has gone: cut now. One press is one flight, never a
                // loop (owner, 2026-10-06: "the pigeons keep playing/looping"); the new channel
                // shows its own tuning state and the remote is free again.
                if !pigeon.isFlying {
                    cut(to: target, from: outgoing, into: next, tookSince: started)
                    await quiet
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// The hard cut: the new signal's layer shows in the same frame the old one goes, the old
    /// stops, and the new one's sound comes up.
    private func cut(to target: Channel, from outgoing: PlayerController, into next: PlayerController, tookSince started: ContinuousClock.Instant) {
        #if DEBUG
        NSLog("KJCUT %@", "\(target.id) state=\(next.state) after=\(ContinuousClock.now - started) bird=\(model.pigeon.current?.name ?? "-") at=\(String(format: "%.2f", model.pigeon.elapsed))")
        #endif
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            aIsFront.toggle()
            current = target
        }
        if destination?.id == target.id { destination = nil }
        outgoing.stop()
        next.releaseSound()
        model.captions.attach(target, player: next)
        wake()
    }

    /// Everything this screen started: the tuning, the wipe, the timer, the signal and the clip.
    private func stopEverything() {
        tuneTask?.cancel()
        changeTask?.cancel()
        hideTask?.cancel()
        model.captions.detach()
        playerA.stop()
        playerB.stop()
        model.clips.clear()
        model.pigeon.clear()
    }

    /// Shows the overlay. Once the signal is playing it hides again after 2.6 seconds without
    /// a press; while tuning, paused or failed it stays, because that is what there is to read.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        guard controller.state == .playing else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            // The strip stays while the viewer is on its Captions control.
            if !Task.isCancelled, armed == nil {
                overlayVisible = false
            }
        }
    }
}

/// What holds focus on a player: the picture, or the caption control in its strip.
enum PlayerFocus: Hashable {
    case surface, captions
}
