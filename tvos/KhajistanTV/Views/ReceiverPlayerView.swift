import SwiftUI
import UIKit

/// A receiver channel, full screen. Up or down, a click or a swipe, tunes the neighbouring channel
/// in the list the viewer came from, behind the pigeon (StationClips); left or right opens the guide
/// (owner, 2026-11-04: "bring back the down and top as channel changing, right and left shows
/// guide"); play/pause pauses, and pressing it again tunes the channel afresh, because a live
/// signal paused for a minute is not the live signal any more.
///
/// The strip's controls (Captions, Like, Guide): Select on the picture, with the strip showing,
/// lights the first; left and right then walk them, Select works one, and Back lets go.
struct ReceiverPlayerView: View {
    /// The channels up and down step through: the shelf the viewer came from, or the region last
    /// chosen from in the guide.
    @State private var list: [Channel]
    let surfChoice: SurfChoice?
    /// The region `list` is from: the region page the viewer came from, or the region last chosen
    /// from in the guide. Nil for a shelf that spans regions (News, Music) and for Surf.
    @State private var listRegion: String?
    /// The name of a shelf that spans regions, which titles the guide's first page.
    @State private var listTitle: String?
    /// The guide's neighbour-region fetches, cancelled when the guide or the player closes.
    @State private var prefetches: [Task<Void, Never>] = []

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
    @State private var controls = ReceiverControlsVisibility()
    @State private var hideTask: Task<Void, Never>?
    @State private var tuneTask: Task<Void, Never>?
    @State private var tuneIntent = ReceiverTuneIntent()
    @State private var changeTask: Task<Void, Never>?
    /// The Captions control takes focus only when the viewer moves right to it, so the focus engine
    /// never lands on it from an up or down press, which change channel.
    /// The strip control the remote has lit: Right lights Captions (when offered) then Like, Left
    /// lets go, Select works it. Focus never leaves the surface (see below).
    @State private var armed: Chip?
    @State private var likeNote: String?
    /// The song on the channel on screen (NowPlaying), or "".
    @State private var song = ""
    /// The guide, open over the left of the picture: the row the remote has lit, as an index in
    /// `list`. Up and down walk it, Select tunes, Left or Menu closes it. Like the strip's
    /// controls, it is lit by the remote and never takes focus.
    @State private var guideRow: Int?
    /// The region the guide shows (nil: the shelf the viewer came from, such as Surf's), and its
    /// channels of the medium playing. Left and right step through the regions.
    @State private var guideRegion: String?
    @State private var guideList: [Channel] = []
    @State private var guideLoading = false
    @State private var guideLoad: Task<Void, Never>?
    /// Set as the screen closes: the remote's recognisers stay on the window until the cover's
    /// animation ends, and a click then must not tune a player already stopped.
    @State private var leaving = false
    private enum Chip { case captions, like, guide }
    private var captionArmed: Bool { armed == .captions }
    @State private var stripHeight: CGFloat = 0
    @FocusState private var focus: PlayerFocus?

    /// The signal on screen, which everything on the screen reads.
    private var controller: PlayerController { aIsFront ? playerA : playerB }
    /// The signal a channel change tunes, behind the one on screen.
    private var incoming: PlayerController { aIsFront ? playerB : playerA }

    init(channel: Channel, list: [Channel], surfChoice: SurfChoice? = nil, regionId: String? = nil, listTitle: String? = nil) {
        _list = State(initialValue: list)
        self.surfChoice = surfChoice
        _listRegion = State(initialValue: regionId)
        _listTitle = State(initialValue: listTitle)
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
                    RadioNowPlaying(channel: current, song: song)
                }
            }
            // The focus target. It draws nothing; its job is to hold focus so the remote's
            // presses reach the handlers below. A click works the Captions control when the viewer
            // has moved to it, and otherwise wakes the overlay. Focus never leaves it: moving
            // focus onto a control as it appears did not take on a real Apple TV, so Select fell
            // through to here and captions could not be turned on (owner, 2026-10-06).
            Button(action: selectOnSurface) {
                Color.clear
            }
            .buttonStyle(SurfaceButtonStyle())
            .focused($focus, equals: .surface)
            .defaultFocus($focus, .surface)
            // The surface is the only thing VoiceOver lands on, so it says what is on and offers
            // what the arrows and the strip do.
            .accessibilityLabel(surfaceLabel)
            // No swipe in the hint: under VoiceOver a swipe moves VoiceOver; the Guide action is below.
            .accessibilityHint(surfaceHint)
            .accessibilityAction(named: "Next channel") { step(by: 1) }
            .accessibilityAction(named: previousActionName) { step(by: -1) }
            .accessibilityAction(named: captionsActionName) { model.captions.toggle(); wake() }
            .accessibilityAction(named: "Like") { like() }
            .accessibilityAction(named: "Guide") { openGuide() }
            overlay(palette)
            if let guideRow {
                ReceiverGuide(list: guideList, current: current, lit: guideRow,
                              medium: (destination ?? current).mediaType, title: guideTitle,
                              turns: guideRegions.count > 1, loading: guideLoading)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            CaptionLayer(text: model.captions.text, skin: model.skin, status: model.captions.sentenceStatus, lift: stripShown ? stripHeight : 0)
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        // A click and a swipe alike: up and down change channel, left and right open the guide.
        // Inside the guide up and down walk the rows and left and right turn the region.
        .onMoveCommand { direction in
            wake()
            if let row = guideRow {
                let count = guideList.count
                switch direction {
                case .up: if count > 0 { guideRow = (row - 1 + count) % count }
                case .down: if count > 0 { guideRow = (row + 1) % count }
                case .left: turnGuide(by: -1)
                case .right: turnGuide(by: 1)
                default: break
                }
                return
            }
            switch direction {
            case .up: click(by: -1)
            case .down: click(by: 1)
            case .right: moveRight()
            case .left: moveLeft()
            @unknown default: break
            }
        }
        .onPlayPauseCommand {
            switch controller.state {
            case .playing, .tuning:
                pauseReceiver()
            case .idle, .paused, .failed:
                if destination != nil { pauseReceiver() } else { tune(current) }
            }
            wake()
        }
        .onExitCommand {
            // Back closes the guide, then lets go of an armed control, as it leaves any control.
            if guideRow != nil {
                closeGuide()
                return
            }
            if armed != nil {
                armed = nil
                wake()
                return
            }
            // Radio plays on under the screens, in the small player, as Sonos keeps playing
            // while you browse; a picture stops with its screen.
            if current.mediaType == "radio", destination == nil, controller.state == .playing {
                model.radioAway = RadioAway(channel: current, list: list, controller: controller, surfChoice: surfChoice,
                                           listRegion: listRegion, listTitle: listTitle)
            }
            stopEverything()
            dismiss()
        }
        .onChange(of: controller.state) { wake() }
        .onChange(of: focus) { wake() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in wake() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in wake() }
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
        // A new channel starts with no song; the watch asks every 20 s while it stays on screen.
        .task(id: current.id) {
            song = ""
            guard current.mediaType == "radio" || current.mediaType == "tv" else { return }
            await NowPlaying.watch(current.id, active: { controller.state == .playing }) { song = $0 }
        }
        .onDisappear { stopEverything() }
    }

    // MARK: - Overlay

    /// The status band across the top and the panel on the ground below. Both go together.
    private func overlay(_ palette: Palette) -> some View {
        // During a change the strip names where the viewer is going, not the channel being left.
        let shown = destination ?? current
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            // Remove the hidden strip so its controls also leave accessibility traversal.
            // Hiding the container alone leaves its custom accessibility actions exposed on tvOS.
            if stripShown {
                PlayerStrip(
                    // Radio carries its name in display type on the ground; the strip leaves it out.
                    name: destination == nil && current.mediaType == "radio" && controller.state == .playing ? nil : shown.name,
                    detail: stripDetail,
                    attribution: shown.sourceLine,
                    trailing: stripTrailing,
                    accessory: AnyView(stripControls)
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                .transition(.opacity.combined(with: .offset(y: 40)))
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: stripShown)
        #if DEBUG
        .overlay(alignment: .topLeading) { KeepAwakeReadout() }
        // The state and the channel id, for the UI tests. Debug builds only: VoiceOver read the
        // raw id aloud, and the surface's label carries the name.
        .overlay(alignment: .bottomLeading) {
            Text(stateText)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("playerState")
                .overlay {
                    Text(current.id)
                        .font(.system(size: 1))
                        .opacity(0.01)
                        .accessibilityIdentifier("currentChannel")
                }
        }
        #endif
    }

    /// Select on the picture: tunes the lit guide row, works the lit strip control, or wakes.
    private func selectOnSurface() {
        if let guideRow {
            if guideList.indices.contains(guideRow) { pick(guideList[guideRow]) }
            return
        }
        switch armed {
        case .captions:
            model.captions.toggle()
            wake()
        case .like:
            like()
            wake()
        case .guide: openGuide()
        case nil:
            // With the strip showing, Select lights its first control; left and right
            // then walk the controls (right on the bare picture opens the guide).
            if stripShown { if case .failed = controller.state {} else { armed = .captions } }
            wake()
        }
    }

    // Taken out of the body, which grew past what the type checker reads in time.
    private var surfaceLabel: String {
        [(destination ?? current).name, (destination ?? current).place].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    private var surfaceHint: String {
        surfChoice == nil ? "Up or down changes channel, left or right opens the guide."
            : "Up or down surfs the whole selected atlas without repeats. Left or right opens the guide."
    }
    private var previousActionName: String { surfChoice == nil ? "Previous channel" : "Another unvisited channel" }
    private var captionsActionName: String { model.captions.isEnabled ? "Captions off" : "Captions on" }

    /// While a signal tunes the ground already says so; the strip waits for the picture.
    private var stripShown: Bool {
        guard controls.isVisible else { return false }
        switch controller.state {
        case .playing, .paused, .failed: return true
        case .idle, .tuning: return false
        }
    }

    /// What follows the name: a failure's reason, Paused, the captions' note, or the place.
    private var stripDetail: String? {
        if let destination { return destination.place.isEmpty ? nil : destination.place }
        switch controller.state {
        case .failed(let message): return message + " Click down for the next channel."
        case .paused: return "Paused"
        default:
            if let likeNote { return likeNote }
            if !model.captions.note.isEmpty { return model.captions.note }
            // Radio prints its song on the ground; television carries it after the place.
            let tvSong = current.mediaType == "tv" ? NowPlaying.caption(song: song, mediaType: "tv") : nil
            let line = [current.place.isEmpty ? nil : current.place, tvSong].compactMap { $0 }.joined(separator: " \u{00B7} ")
            return line.isEmpty ? nil : line
        }
    }

    /// The site's Captions button: its label says what is on and what is left. Right lights it,
    /// Select works it, left lets it go; no up or down press can land on it.
    private var captionsControl: some View {
        StripChipStyle.face(Text(rightCue + captionsFace), isOn: model.captions.isEnabled, selected: captionArmed)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(model.captions.label)
            .accessibilityIdentifier("captionsControl")
            .accessibilityAction { model.captions.toggle(); wake() }
            // Lit by the remote rather than focused: tests and VoiceOver read it as selected.
            .accessibilityAddTraits(captionArmed ? .isSelected : [])
            .accessibilityValue(model.captions.isEnabled ? "On" : "Off")
    }

    /// "CC Off" or "CC On · English", with what is left on the account: the chip says plainly
    /// that Select turns captions off as well as on (owner, 2026-11-04).
    private var captionsFace: String {
        let rest = model.captions.label.replacingOccurrences(of: "Captions", with: "")
        return "CC " + (model.captions.isEnabled ? "On" : "Off") + rest
    }

    private var stripControls: some View {
        HStack(spacing: 14) {
            captionsControl
            likeControl
            if guideOffered { guideControl }
        }
    }

    /// The guide, as a live TV app offers one: every channel of the shelf the viewer came from,
    /// LIVE on the one playing, one press to another.
    private var guideControl: some View {
        StripChipStyle.face(Text("Guide"), isOn: guideRow != nil, selected: armed == .guide)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Guide")
            .accessibilityIdentifier("guideControl")
            .accessibilityAction { openGuide() }
            .accessibilityAddTraits(armed == .guide ? .isSelected : [])
    }

    private func openGuide() {
        guard guideOffered else { return }
        hideTask?.cancel()
        guideLoad?.cancel()
        guideLoading = false
        // The medium playing only, as on every page the guide turns to.
        let medium = (destination ?? current).mediaType
        guideList = list.filter { $0.mediaType == medium }
        // A region page's list is titled by its region; a cross-region shelf and Surf by name.
        guideRegion = surfChoice == nil && listTitle == nil ? homeRegion : nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            guideRow = guideList.firstIndex { $0.id == (destination ?? current).id } ?? 0
        }
        prefetchGuide(around: guideRegion ?? homeRegion)
    }

    /// Every region with a list, in the atlas the receiver shows (the switch on its front).
    private var guideRegions: [ReceiverIndex.Region] {
        guard let index = model.receiver.index else { return [] }
        let scope: ShuffleScope = model.extendedAtlas ? .everywhere : .main
        return index.listedRegions.filter { scope.includes(tier: $0.tier) }
    }

    private var guideOffered: Bool { list.count > 1 || guideRegions.count > 1 }

    /// The region the shelf came from, or the first of the channel's own.
    private var homeRegion: String? {
        let ids = guideRegions.map(\.id)
        if let listRegion, ids.contains(listRegion) { return listRegion }
        return (destination ?? current).regionIds?.first { ids.contains($0) }
    }

    private var guideTitle: String {
        guard let guideRegion else { return listTitle ?? "Surf" }
        return guideRegions.first { $0.id == guideRegion }?.label ?? guideRegion
    }

    /// Left or right in the guide: the neighbouring region's channels of the medium playing. The
    /// name changes at once; the rows follow when the region's list has loaded (cached after once).
    private func turnGuide(by delta: Int) {
        let regions = guideRegions
        guard regions.count > 1 else { return }
        let from = regions.firstIndex { $0.id == (guideRegion ?? homeRegion) } ?? (delta > 0 ? -1 : 0)
        let target = regions[((from + delta) % regions.count + regions.count) % regions.count]
        let medium = (destination ?? current).mediaType
        guideRegion = target.id
        guideList = []
        guideRow = 0
        guideLoading = true
        guideLoad?.cancel()
        guideLoad = Task {
            let channels = (try? await model.receiver.channels(regionId: target.id, cameras: medium == "camera")) ?? []
            guard !Task.isCancelled, guideRow != nil, guideRegion == target.id else { return }
            guideList = channels.filter { $0.mediaType == medium }
            guideRow = guideList.firstIndex { $0.id == (destination ?? current).id } ?? 0
            guideLoading = false
        }
        prefetchGuide(around: target.id)
    }

    private func cancelPrefetches() {
        prefetches.forEach { $0.cancel() }
        prefetches = []
    }

    /// Fetches the regions either side of this one into the store's cache, so the next left or
    /// right shows its channels at once instead of "Loading".
    private func prefetchGuide(around regionId: String?) {
        let regions = guideRegions
        guard regions.count > 1, let at = regions.firstIndex(where: { $0.id == regionId }) else { return }
        let cameras = (destination ?? current).mediaType == "camera"
        cancelPrefetches()
        for delta in [1, -1] {
            let id = regions[((at + delta) % regions.count + regions.count) % regions.count].id
            prefetches.append(Task { _ = try? await model.receiver.channels(regionId: id, cameras: cameras) })
        }
    }

    /// Closing lets go of the Guide control too: the viewer has left it, and an armed control
    /// keeps the strip up and takes the next Menu.
    private func closeGuide() {
        guideLoad?.cancel()
        cancelPrefetches()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { guideRow = nil }
        armed = nil
        wake()
    }

    /// A channel chosen in the guide: the same change as a press up or down, behind the pigeon.
    private func pick(_ target: Channel) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { guideRow = nil }
        armed = nil
        // Up and down then step through the region chosen from. Surf keeps its own walk.
        if surfChoice == nil, guideList.count > 1 {
            list = guideList
            if guideRegion != nil { listRegion = guideRegion; listTitle = nil }
        }
        guard target.id != (destination ?? current).id else { return wake() }
        if let surfChoice { model.surfHistory.visit(target, for: surfChoice) }
        destination = target
        changeTask?.cancel()
        changeTask = Task { await change(to: target) }
    }

    /// Like: saved on the account, so it is on the dashboard and every device signed in to it.
    private var likeControl: some View {
        let liked = model.saves.isSaved(current)
        return StripChipStyle.face(Text(liked ? "Liked" : "Like"), isOn: liked, selected: armed == .like)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(liked ? "Liked" : "Like")
            .accessibilityIdentifier("likeControl")
            .accessibilityAction { like() }
            .accessibilityAddTraits(armed == .like ? .isSelected : [])
            .accessibilityValue(liked ? "On" : "Off")
    }

    /// "→ " before the first control on the strip while nothing is armed: the strip's controls are
    /// reached with a press right, and nothing else said so (owner, 2026-10-09).
    private var rightCue: String { armed == nil ? "\u{2192} " : "" }

    /// A click up or down, outside the guide: the neighbouring channel. In the guide the same
    /// click walks the rows instead, through onMoveCommand.
    private func click(by delta: Int) {
        guard guideRow == nil, !leaving else { return }
        wake()
        armed = nil
        step(by: delta)
    }

    private func moveRight() {
        switch armed {
        case nil: return openGuide()
        case .captions: armed = .like
        case .like: if guideOffered { armed = .guide }
        case .guide: break
        }
    }

    private func moveLeft() {
        switch armed {
        case .guide: armed = .like
        case .like: armed = .captions
        case .captions: armed = nil
        // Left or right on the picture opens the guide, as a live TV app does (owner, 2026-11-04).
        case nil: return openGuide()
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
        let ticket = tuneIntent.begin()
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
                guard tuneIntent.admits(ticket) else { return }
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
                if Task.isCancelled || !tuneIntent.admits(ticket) { return }
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
        if let surfChoice {
            guard let target = model.surfHistory.next(for: surfChoice) else {
                say("You have visited the available channels. Go back to Surf to load the rest of the atlas.")
                return
            }
            destination = target
            changeTask?.cancel()
            changeTask = Task { await change(to: target) }
            return
        }
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
        model.silenceRadio()
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
        UIAccessibility.post(notification: .announcement, argument: target.name)
    }

    /// Pause cancels a pending resolver/change immediately; no late attach can resume it.
    /// Captions release their lease. Resuming playback restores the saved CC preference.
    private func pauseReceiver() {
        tuneIntent.cancel()
        tuneTask?.cancel()
        changeTask?.cancel()
        destination = nil
        incoming.stop()
        if controller.state == .tuning {
            controller.cancelPendingPlayback()
        } else {
            controller.pause()
        }
        model.captions.detach()
        model.clips.clear()
        model.pigeon.clear()
    }

    /// Everything this screen started: the tuning, the wipe, the timer, the signal and the clip.
    private func stopEverything() {
        leaving = true
        guideRow = nil
        guideLoad?.cancel()
        cancelPrefetches()
        tuneIntent.cancel()
        tuneTask?.cancel()
        changeTask?.cancel()
        hideTask?.cancel()
        model.captions.detach()
        // The radio handed to the small player keeps playing.
        if model.radioAway?.controller !== playerA { playerA.stop() }
        if model.radioAway?.controller !== playerB { playerB.stop() }
        model.clips.clear()
        model.pigeon.clear()
    }

    private var controlsCanHide: Bool {
        controller.state == .playing && guideRow == nil && focus == .surface && OverlayTiming.hidesItself
    }

    /// Every remote interaction starts a fresh five seconds. An open guide, a system focus
    /// change, VoiceOver or Switch Control keeps the controls available. CaptionLayer is separate.
    private func wake() {
        hideTask?.cancel()
        controls.wake(at: ProcessInfo.processInfo.systemUptime, canHide: controlsCanHide)
        guard controlsCanHide else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(ReceiverControlsVisibility.idleSeconds))
            guard !Task.isCancelled else { return }
            if controls.expire(at: ProcessInfo.processInfo.systemUptime, canHide: controlsCanHide) {
                armed = nil
            }
        }
    }
}

/// What holds focus on a player: the picture, or the caption control in its strip.
enum PlayerFocus: Hashable {
    case surface, captions
}

/// A radio channel left playing when its player closed: the small player under every section
/// reads it, and opens the channel full screen again from it.
struct RadioAway: Identifiable {
    let channel: Channel
    let list: [Channel]
    let controller: PlayerController
    let surfChoice: SurfChoice?
    /// What the guide titles its first page by when the station is opened again.
    let listRegion: String?
    let listTitle: String?
    var id: String { channel.id }
}

/// Sonos's small player while you browse, on the remote: a band plate along the foot of the
/// screen with the channel's mark, its name and state, and Play/Pause and Off. Select on the name
/// opens the channel full screen again. Its own focus section, so Down from a page reaches it.
struct RadioBar: View {
    let away: RadioAway
    let open: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    /// The song while the radio plays on under the screens (NowPlaying).
    @State private var song = ""

    var body: some View {
        let state = away.controller.state
        let playing = state == .playing || state == .tuning
        HStack(spacing: 20) {
            Image(systemName: "radio")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(palette.onBand.opacity(0.16))
                .accessibilityHidden(true)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(away.channel.name).kjName(30).lineLimit(1)
                    // Where it is from, and the song while one is named (owner, 2026-11-05).
                    let country = away.channel.country?.trimmingCharacters(in: .whitespaces) ?? ""
                    let tail = state == .playing && !song.isEmpty ? song : Self.word(state)
                    Text((["Radio", country, tail].filter { !$0.isEmpty }).joined(separator: " \u{00B7} ")).kjSmall().lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityHint("Opens the channel full screen")
            .accessibilityIdentifier("radioBarName")
            // Play tunes the station afresh, full screen, as the player's own Play does: a live
            // signal paused or stopped is not the live signal any more.
            Button {
                if playing { away.controller.pause() } else { open() }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .bold)).frame(width: 60)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel(playing ? "Pause" : "Play")
            .accessibilityIdentifier("radioBarToggle")
            Button { model.silenceRadio() } label: {
                // Not a kicker: a kicker is the accent, which in Day is the band itself.
                Label("Off", systemImage: "xmark")
                    .font(.system(size: KJType.kicker, weight: .black))
                    .textCase(.uppercase)
            }
            .buttonStyle(OnBandStyle())
            .accessibilityLabel("Turn the radio off")
            .accessibilityIdentifier("radioBarOff")
        }
        .foregroundStyle(palette.onBand)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(palette.band)
        .padding(.horizontal, KJLayout.inset)
        .padding(.bottom, 24)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("radioBar")
        .task(id: away.channel.id) {
            song = ""
            await NowPlaying.watch(away.channel.id, active: { away.controller.state == .playing }) { song = $0 }
        }
    }

    private static func word(_ state: PlayerController.State) -> String {
        switch state {
        case .playing: return "On air"
        case .tuning: return "Tuning\u{2026}"
        case .paused: return "Paused"
        case .failed: return "The signal stopped"
        case .idle: return "Standing by"
        }
    }
}

/// A control on the band: onBand at rest; under focus the colours swap, the onBand plate with the
/// band's colour as its text, at 1.03. No outline.
private struct OnBandStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnBandFace(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct OnBandFace<Face: View>: View {
    let label: Face
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.palette) private var palette

    var body: some View {
        label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .foregroundStyle(isFocused ? palette.band : palette.onBand)
            .background(isFocused ? palette.onBand : Color.clear)
            .scaleEffect(isFocused && !isPressed ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
