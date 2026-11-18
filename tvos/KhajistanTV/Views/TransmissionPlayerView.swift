import AVFoundation
import SwiftUI
import UIKit

/// One channel of Khajistan Transmission, full screen. The first time in a launch the station signs
/// on (the wing, the ident, the wing), then the channel is joined where the clock has reached.
/// Up and down switch channel through the wing wipe. There is no list of programmes and no
/// scrub bar: a channel is tuned, a programme is not chosen.
///
/// A programme that carries a prepared subtitle file (`subtitle_url`) shows it, on by default as on
/// the website, and the strip ends in the Subtitles control: right moves to it, left comes back.
///
/// The strip also carries Guide and PiP, as the Receiver's does. The guide rises from the bottom
/// with every channel and what is on it now; picture in picture keeps the channel playing in a
/// corner while the viewer browses, handovers included.
struct TransmissionPlayerView: View {
    /// The channel the viewer chose. The store holds the channel now on air, which Up and Down change.
    let channel: Int
    /// Closes the screen when UIKit presented it (TopScreen, a restore from the PiP window);
    /// SwiftUI's dismiss otherwise.
    var close: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showSignIn = false
    @State private var switching = false
    /// Set when the viewer leaves, so a sequence that is part-way through does not start the next step.
    @State private var left = false
    @State private var subtitles = RecordedSubtitles()
    /// The strip control the remote has lit, if any.
    @State private var armed: Chip?
    private enum Chip { case subtitles, guide, pip }
    /// The guide's lit row, as an index into `guideRows`; nil while it is closed.
    @State private var guideRow: Int?
    @State private var guideRows: [TransmissionGuide.Row] = []
    @State private var pip = PictureInPicture()
    /// Set when the picture went to the corner window: the screen closes, the channel plays on.
    @State private var handedToPiP = false
    /// A short line the strip shows in place of its detail, such as PiP not opening.
    @State private var note: String?
    @State private var stripHeight: CGFloat = 0
    /// The song playing inside the programme, from songs.json (HouseSongs), or "".
    @State private var song = ""
    /// The channel number in the top corner, while it shows.
    @State private var plateChannel: Int?
    /// Set when the channel changes (and at the first tune): the number shows once it plays.
    @State private var plateOwed = true
    @State private var plateTask: Task<Void, Never>?
    @FocusState private var focus: PlayerFocus?

    private var store: TransmissionStore { model.transmission }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            content
            if let number = plateChannel {
                ChannelNumberOSD(number: number, overPicture: !isOffAirNow)
                    .padding(.top, 64)
                    .padding(.trailing, KJLayout.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
            // On air the focus target sits inside the picture's layers, under the strip, so the
            // Subtitles control in the strip can take focus; a view covered by the picture cannot.
            if holdsFocus && !isOnAir {
                focusTarget
            }
            StationClipLayer(clips: model.clips)
        }
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            move(direction)
        }
        .onPlayPauseCommand {
            playPause()
        }
        .onExitCommand {
            // Back closes the guide, then lets go of a lit control, as the Receiver does.
            if guideRow != nil {
                closeGuide()
                return
            }
            var soundOnly = false
            if case .onAir(let air) = store.phase { soundOnly = air.programme?.audio_only == true }
            let hidesStrip = stripShown && !soundOnly && store.player.state == .playing && !switching && OverlayTiming.hidesItself
            if armed != nil {
                armed = nil
                if hidesStrip { hideTask?.cancel(); overlayVisible = false } else { wake() }
                return
            }
            // Then hides the strip over a playing picture, as Apple's info panel goes. A sound-only
            // programme has no picture to uncover, so its first Back leaves.
            if hidesStrip {
                hideTask?.cancel()
                overlayVisible = false
                return
            }
            leave()
            if let close { close() } else { dismiss() }
        }
        .onChange(of: store.phase) { wake() }
        // A control cannot stay lit once it is gone from the strip.
        .onChange(of: pipOffered) { _, offered in if !offered, armed == .pip { armed = nil } }
        .onChange(of: guideOffered) { _, offered in if !offered, armed == .guide { armed = nil } }
        // Off air or re-tuning: the guide and the strip's controls go with the picture.
        .onChange(of: isOnAir) { _, onAir in if !onAir { guideRow = nil; armed = nil } }
        .onChange(of: store.player.state) { wake(); showNumberWhenTuned() }
        // The last channel's number goes at once: it must not sit over the next one.
        .onChange(of: store.channelNumber) {
            plateTask?.cancel()
            plateChannel = nil
            plateOwed = true
            showNumberWhenTuned()
        }
        .onChange(of: store.phase) { showNumberWhenTuned() }
        // The number waits for the channel change, the bird and the sign-on cover to be done.
        .onChange(of: switching) { showNumberWhenTuned() }
        .onChange(of: model.pigeon.isFlying) { showNumberWhenTuned() }
        .onChange(of: model.clips.coverage) { showNumberWhenTuned() }
        // A schedule that now needs the preview password, or is not published, is answered on
        // the station page, which carries the password step. The player goes back to it.
        .onChange(of: store.schedule) { _, schedule in
            switch schedule {
            case .needsPreviewPassword, .noSchedule:
                leave()
                if let close { close() } else { dismiss() }
            default:
                break
            }
        }
        .task { await start() }
        #if DEBUG
        // `-kjautoswitch 6` switches channel that many times, fifteen seconds apart, so the
        // switch can be measured on a device with no one at the remote.
        .task {
            let n = UserDefaults.standard.integer(forKey: "kjautoswitch")
            for _ in 0..<n {
                try? await Task.sleep(for: .seconds(15))
                print("KJSWITCH press ch=\(store.channelNumber) state=\(store.player.state) switching=\(switching)")
                move(.up)
            }
        }
        #endif
        .task(id: subtitleKey) { await loadSubtitles() }
        .task(id: subtitleKey) { await watchSong() }
        .onDisappear { leave() }
        .kjFullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: { await store.tune(channel: store.channelNumber) })
        }
    }

    // MARK: - What the phase puts on screen

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .tuning:
            TuningLoader("Connecting\u{2026}")
        case .needsSignIn:
            message("Sign in to watch Khajistan Transmission.") {
                Button("Sign in") {
                    showSignIn = true
                }
                .buttonStyle(HouseButtonStyle())
            }
        case .offAir(channelName: let name, returns: let returns):
            VStack(alignment: .leading, spacing: 28) {
                Text("Off air").kjDisplay()
                Text(returns.map { "\(name) returns at \($0)." } ?? "\(name) is off air.")
                    .kjBody()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
        case .onAir(let air):
            onAir(air)
        case .failed(let text):
            message(text) {
                Button("Try again") {
                    Task { await store.tune(channel: store.channelNumber) }
                }
                .buttonStyle(HouseButtonStyle())
            }
        }
    }

    private func message<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(text).kjBody()
            actions()
        }
        .kjBody()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, KJLayout.inset)
    }

    private func onAir(_ air: OnAir) -> some View {
        ZStack {
            if air.programme?.audio_only == true {
                DancerLayer(controller: store.player) {
                    soundOnly(air)
                }
            } else {
                // A picture that does not fill the screen sits on black (owner, 2026-10-05).
                Color.black.ignoresSafeArea()
                // Both signals keep a layer of their own; the cut is which one shows.
                PlayerLayerView(player: store.playerA.player, onLayer: pip.bind)
                    .ignoresSafeArea()
                    .opacity(store.aIsFront ? 1 : 0)
                PlayerLayerView(player: store.playerB.player, onLayer: pip.bind)
                    .ignoresSafeArea()
                    .opacity(store.aIsFront ? 0 : 1)
            }
            if store.player.state == .tuning {
                // The ground covers the picture while the signal is on its way; the loader itself
                // sits in the overlay, between the band and the panel.
                palette.ground.ignoresSafeArea()
            }
            focusTarget
            overlay(air)
            if let guideRow {
                TransmissionGuide(rows: guideRows, current: store.channelNumber, lit: guideRow)
                    .transition(.move(edge: .bottom))
            }
            CaptionLayer(text: subtitles.text, skin: model.skin,
                         overPicture: air.programme?.audio_only != true, lift: stripShown ? stripHeight : 0)
                // Not over the guide's rows: the guide covers the lower part of the picture.
                .opacity(guideRow == nil ? 1 : 0)
            HandoverNotice(
                air: air,
                next: store.upcoming(channel: store.channelNumber, at: TransmissionStore.now(), count: 1).first,
                overlayVisible: overlayVisible
            )
        }
    }

    /// What an audio-only transmission shows in place of a picture. The panel does not repeat the
    /// title or the credits while this is on screen.
    private func soundOnly(_ air: OnAir) -> some View {
        VStack(spacing: 24) {
            Kicker("Channel \(store.channelNumber) \u{00B7} sound only")
            Text(headline(air))
                .kjDisplay()
                .multilineTextAlignment(.center)
            if !song.isEmpty {
                Text("Now playing: " + song).kjBody().multilineTextAlignment(.center)
            }
            if let country = nonEmpty(air.programme?.country) {
                Text(country).kjSmall(faint: true)
            }
            if let custodian = nonEmpty(air.programme?.custodian) {
                Text(custodian).kjSmall(faint: true)
            }
            if let transfer = nonEmpty(air.programme?.transfer) {
                Text(transfer).kjSmall(faint: true)
            }
        }
        .padding(.horizontal, KJLayout.inset)
    }

    // MARK: - The overlay

    /// The slim strip, as the Receiver's (owner, 2026-10-05: the bar was "too thick"): the slot
    /// and the show at left with the show's line under them, the channel and what is up next at
    /// right. It rises and fades with the overlay; while the signal tunes the ground says so.
    private func overlay(_ air: OnAir) -> some View {
        let soundOnly = air.programme?.audio_only == true
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            // Redrawn on the minute, so what is up next moves on at a handover.
            TimelineView(.everyMinute) { _ in
                PlayerStrip(
                    // A sound programme carries its name on the ground, with the dancer.
                    name: soundOnly ? nil : headline(air),
                    detail: stripDetail(air, soundOnly: soundOnly),
                    attribution: credit(air),
                    // The channel's own name, always: a show name in the headline read as the
                    // channel's (owner, 2026-11-08: "qawalli as chanel name doesnt make sense").
                    trailing: ["\u{25CF} " + store.channelName(store.channelNumber)],
                    // The station clock's answer (StationClock.withNextProgramme, the site's rule).
                    upNext: air.nextName.flatMap { name in air.nextAt.map { ($0, upNextName(name, air)) } },
                    accessory: chips.isEmpty ? nil : AnyView(stripControls)
                )
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
            .offset(y: stripShown ? 0 : 40)
            .opacity(stripShown ? 1 : 0)
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.35), value: stripShown)
        .overlay(alignment: .bottomLeading) {
            Text(stateText(air))
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("playerState")
        }
        // The channel tuned, for the UI tests; nothing on screen.
        .overlay(alignment: .bottomTrailing) {
            Text("\(store.channelNumber)")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("transmissionChannel")
        }
    }

    private var stripShown: Bool {
        guard overlayVisible else { return false }
        // A schedule file (DEBUG, UI tests) plays no picture; its strip shows as a playing one does.
        if store.isScheduleFile { return true }
        switch store.player.state {
        case .playing, .paused, .failed: return true
        case .idle, .tuning: return false
        }
    }

    /// One small line under the name: the custodian and the transfer, a person's credit or
    /// nothing. The show's own line is not shown here (owner, 2026-11-15: "i dont want any
    /// subtitle it looks AI").
    private func credit(_ air: OnAir) -> String? {
        let parts = [air.programme?.custodian, air.programme?.transfer].compactMap { nonEmpty($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Words

    /// Up next carries the country too, as Now does.
    private func upNextName(_ name: String, _ air: OnAir) -> String {
        guard let id = air.nextProgrammeId,
              let country = nonEmpty(store.programming?.programmes[id]?.country) else { return name }
        return name + " \u{00B7} " + country
    }

    /// Now playing: the programme, by the standardized name the schedule carries (owner,
    /// 2026-11-08: "add now playing and up next ... names need to be standardized"). Where a
    /// title could not be cleaned there is none, and the show stands in, as it did for every
    /// programme under the 2026-09-06 ruling ("no file names").
    private func headline(_ air: OnAir) -> String {
        air.nowName ?? store.channelName(store.channelNumber)
    }

    /// The show, where the headline is the programme: it moves to the head of the detail line.
    /// Not when the show IS the channel (Jordan Television, Home Movies): the trailing name says it.
    private func showUnderTitle(_ air: OnAir) -> String? {
        guard nonEmpty(air.programme?.display_title) != nil, let show = nonEmpty(air.show?.name) else { return nil }
        return store.channelName(store.channelNumber).hasSuffix("\u{00B7} " + show) ? nil : show
    }

    /// The slot, then where the programme is from and, on a picture, the song inside it. A sound
    /// programme already carries both on the ground.
    private func stripDetail(_ air: OnAir, soundOnly: Bool) -> String {
        // The country is not a playback state: it stays through a pause. A failure's message stands alone.
        if let note { return note }
        if case .failed = store.player.state { return stateText(air) }
        if soundOnly { return stateText(air) }
        let playing = store.player.state == .playing || store.player.state == .idle
        // Country first, then year (owner, 2026-11-15: "country is imp").
        return [nonEmpty(air.programme?.country), air.programme?.year.map(String.init), showUnderTitle(air), stateText(air), playing && !song.isEmpty ? "Now playing: " + song : nil]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// The song at the player's position, checked each second (the website reads `timeupdate`).
    private func watchSong() async {
        song = ""
        guard case .onAir(let air) = store.phase else { return }
        var spans: [SongSpan] = []
        // A file that has not arrived yet (or names no song here) is asked again each minute.
        while !Task.isCancelled {
            spans = await HouseSongs.shared.spans(for: air.programmeId, previewPassword: model.auth.previewPassword)
            if !spans.isEmpty { break }
            try? await Task.sleep(for: .seconds(60))
        }
        while !Task.isCancelled {
            let time = store.player.player.currentTime().seconds
            let now = time.isFinite ? HouseSongs.song(in: spans, at: time) : ""
            if now != song { song = now }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// While the programme plays, the slot it belongs to, as the station page says it.
    private func stateText(_ air: OnAir) -> String {
        switch store.player.state {
        case .idle, .playing: return "Now \(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)"
        case .tuning: return "Tuning\u{2026}"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - The remote

    /// A full-screen button that draws nothing. It holds focus so the remote's presses reach the
    /// handlers above, and a click wakes the overlay. It is left out while a
    /// button of the screen's own (Sign in, Try again) is the thing to focus.
    private var focusTarget: some View {
        Button {
            selectOnSurface()
        } label: {
            Color.clear
        }
        .buttonStyle(SurfaceButtonStyle())
        .focused($focus, equals: .surface)
        .accessibilityLabel("Show details")
    }

    /// Right lights it, Select on the picture works it, left lets it go.
    private var subtitlesControl: some View {
        StripChipStyle.face(Text(subtitles.label), isOn: subtitles.current != nil, selected: armed == .subtitles)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("subtitlesControl")
            // Lit by the remote rather than focused: tests and VoiceOver read it as selected.
            .accessibilityAddTraits(armed == .subtitles ? .isSelected : [])
    }

    // MARK: - The channel number

    /// Once the channel changed to is on screen (playing, or off air with its return), its number
    /// shows in the top corner for three seconds, as an old set's did: on and off at once.
    private func showNumberWhenTuned() {
        guard plateOwed, !left, !switching, !model.pigeon.isFlying, model.clips.coverage == 0 else { return }
        let ready: Bool
        switch store.phase {
        case .offAir: ready = true
        // A sound-only programme puts the channel in that corner already, with the dancer.
        case .onAir(let air) where air.programme?.audio_only == true:
            plateOwed = false
            return
        case .onAir: ready = store.player.state == .playing || store.isScheduleFile
        default: ready = false
        }
        guard ready else { return }
        plateOwed = false
        plateTask?.cancel()
        plateChannel = store.channelNumber
        UIAccessibility.post(notification: .announcement, argument: "Channel \(store.channelNumber)")
        plateTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            plateChannel = nil
        }
    }

    // MARK: - Strip controls, the guide and picture in picture

    /// The strip's controls, left to right, as the remote walks them.
    private var chips: [Chip] {
        [subtitles.tracks.isEmpty ? nil : .subtitles, guideOffered ? .guide : nil, pipOffered ? .pip : nil]
            .compactMap { $0 }
    }

    private var stripControls: some View {
        HStack(spacing: 14) {
            if !subtitles.tracks.isEmpty { subtitlesControl }
            if guideOffered {
                StripChipStyle.face(Text("Guide"), isOn: guideRow != nil, selected: armed == .guide)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Guide")
                    .accessibilityIdentifier("guideControl")
                    .accessibilityAction { openGuide() }
                    .accessibilityAddTraits(armed == .guide ? .isSelected : [])
            }
            if pipOffered {
                StripChipStyle.face(Text("PiP"), isOn: false, selected: armed == .pip)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Picture in picture")
                    .accessibilityIdentifier("pipControl")
                    .accessibilityAction { startPictureInPicture() }
                    .accessibilityAddTraits(armed == .pip ? .isSelected : [])
            }
        }
    }

    /// Select on the picture: tunes the lit guide row, works the lit control, or, with the strip
    /// up, lights its first control (the Receiver's rule).
    private func selectOnSurface() {
        if let guideRow {
            if guideRows.indices.contains(guideRow) { pick(guideRows[guideRow].number) }
            return
        }
        switch armed {
        // Focus never leaves the surface: see ReceiverPlayerView's surface (2026-10-06).
        case .subtitles: subtitles.cycle()
        case .guide: return openGuide()
        case .pip: return startPictureInPicture()
        case nil: if stripShown, !isFailed { armed = chips.first }
        }
        wake()
    }

    private var isFailed: Bool { if case .failed = store.player.state { return true } else { return false } }

    /// Not while a change, a handover or the sign-on tunes: the control shows only when it works.
    private var guideOffered: Bool {
        isOnAir && store.channelNumbers.count > 1 && !switching && store.player.state != .tuning
    }

    /// Every channel, with what the clock has on it now, the tuned one lit.
    private func openGuide() {
        guard guideOffered else { return }
        hideTask?.cancel()
        armed = nil
        let now = TransmissionStore.now()
        guideRows = store.channelNumbers.map { number in
            let air = store.nowOn(channel: number, at: now)
            let line: String
            if let air {
                line = air.nowName ?? air.show?.name ?? ""
            } else if let back = store.returnLabel(channel: number, at: now) {
                line = "Off air \u{00B7} returns at \(back)"
            } else {
                line = "Off air"
            }
            return .init(number: number, name: store.channelName(number), now: line,
                         soundOnly: air?.programme?.audio_only == true)
        }
        withAnimation(CardMotion.panel(reduceMotion: reduceMotion)) {
            guideRow = guideRows.firstIndex { $0.number == store.channelNumber } ?? 0
        }
    }

    private func closeGuide() {
        withAnimation(CardMotion.panel(reduceMotion: reduceMotion)) { guideRow = nil }
        wake()
    }

    /// A channel chosen in the guide: the same change as Up or Down, behind the pigeon.
    private func pick(_ number: Int) {
        // A change already under way: the guide stays open with the choice still lit.
        guard !switching else { return }
        closeGuide()
        guard number != store.channelNumber, holdsFocus else { return }
        switching = true
        Task {
            await switchUnderThePigeon(to: number)
            switching = false
        }
    }

    /// Picture in picture: a picture playing, with no change under way. A sound-only programme
    /// has no picture to put in the corner.
    private var pipOffered: Bool {
        guard PictureInPicture.isSupported, !switching, store.player.state == .playing,
              case .onAir(let air) = store.phase else { return false }
        return air.programme?.audio_only != true
    }

    /// The picture goes to a corner and the screen closes behind it; the store keeps the channel
    /// on air, handing over programme to programme. Full screen from the window opens the channel
    /// again; closing the window stops it; any other player starting closes it (silenceRadio).
    private func startPictureInPicture() {
        guard pipOffered else { return }
        armed = nil
        let store = store, model = model, pip = pip
        let player = store.player
        let access = store.accessRevision
        // The window carries the programme's subtitles, following the channel's handovers once
        // this screen has closed: a stream's track drawn by tvOS, a file's drawn into the picture
        // (PictureInPicture). The object, not the screen's state.
        let follower = ProgrammeSubtitleFollower(subtitles, store: store, model: model,
                                                 loaded: subtitles.tracks.isEmpty ? nil : subtitleKey)
        pip.title = store.channelName(store.channelNumber)
        pip.onHandOff = { follower.subtitles.handOff() }
        pip.captions = { follower.text() }
        pip.hasFileCaptions = { follower.subtitles.hasFile }
        // Offered only where the window can draw it: a track tvOS draws, or a file drawn into the
        // picture. A stream that fell back to a file cannot be drawn there, and says nothing.
        pip.captionLabel = { [weak pip] in
            let subtitles = follower.subtitles
            let drawn = subtitles.isHandedOff || (subtitles.hasFile && pip?.drawsIntoPicture == true)
            return drawn && !subtitles.tracks.isEmpty ? subtitles.label : nil
        }
        pip.onCaptionToggle = { follower.subtitles.cycle() }
        pip.skin = { model.skin }
        // A paused transmission is not the transmission any more: Play joins it again, live.
        // A Pause pressed while the channel retunes waits for the new picture; a Play after it wins.
        final class PendingPause { var task: Task<Void, Never>? }
        let pending = PendingPause()
        pip.onSetPlaying = { playing in
            pending.task?.cancel()
            pending.task = nil
            if playing {
                Task { await store.rejoinLive() }
            } else if store.player.state == .playing || store.player.state == .paused {
                store.player.pause()
            } else {
                pending.task = Task {
                    // The rejoin's own stop leaves the player idle while it signs and loads (up to
                    // 20 s): the Pause waits for the new picture, then for it to settle.
                    let deadline = ContinuousClock.now + .seconds(20)
                    while !Task.isCancelled, store.player.state == .idle, store.phase == .tuning, ContinuousClock.now < deadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    await store.player.settled()
                    // Only while this window still carries the channel: a screen opened since (a
                    // card, another channel) is not paused by a Pause pressed in a window now gone.
                    if !Task.isCancelled, model.transmissionPiP === pip, store.player === player,
                       store.player.state == .playing { store.player.pause() }
                }
            }
        }
        pip.controller = player
        pip.rejoinsOnPlay = true
        pip.onStart = {
            // AVKit can finish starting after a retune or after this screen has left.
            guard !left, !switching, store.player === player, store.accessRevision == access,
                  player.state == .playing || player.state == .tuning else { pip.stop(); return }
            model.transmissionPiP = pip
            handedToPiP = true
            if let close { close() } else { dismiss() }
        }
        pip.onFail = { say($0) }
        pip.onRestore = {
            guard model.transmissionPiP === pip else { return }
            // The screen that opens loads the programme's subtitles afresh; the window's stay until
            // it has closed.
            follower.end(clearing: false)
            // transmissionPiP stays set: the player that opens over whatever is on top takes the
            // channel over as it plays (start(), RootView). If it cannot open, the next signal to
            // start still stops this one rather than playing over it.
            model.restoringTransmission = store.channelNumber
        }
        pip.onEnd = {
            follower.end()
            guard model.transmissionPiP === pip else { return }
            model.transmissionPiP = nil
            store.stop()
        }
        if !pip.start(player.player) {
            pip.letGo()
            say("Picture in picture is not ready yet. Try again in a moment.")
        }
        wake()
    }

    /// A line in the strip for a few seconds.
    private func say(_ line: String) {
        note = line
        wake()
        Task {
            try? await Task.sleep(for: .seconds(4))
            if note == line { note = nil }
        }
    }

    // MARK: - Subtitles

    /// The programme on air, so a handover loads the next programme's file.
    private var subtitleKey: String? { ProgrammeSubtitles.key(store.phase) }

    private func loadSubtitles() async {
        await ProgrammeSubtitles.load(into: subtitles, store: store, model: model)
    }

    private var isOnAir: Bool {
        if case .onAir = store.phase { return true }
        return false
    }

    private var holdsFocus: Bool {
        switch store.phase {
        case .needsSignIn, .failed: return false
        default: return true
        }
    }

    /// Up and down switch channel behind the pigeon. While a change is under way they skip it; one
    /// made while the sign-on flies switches under that bird.
    private func move(_ direction: MoveCommandDirection) {
        // Read before wake() shows the strip: right on the bare picture opens the guide, right
        // with the strip up walks its controls (the Receiver's rule, owner 2026-11-08).
        let stripWasUp = stripShown
        wake()
        // Inside the guide up and down walk the rows.
        if let row = guideRow {
            let count = guideRows.count
            if count > 0, direction == .up { guideRow = (row - 1 + count) % count }
            if count > 0, direction == .down { guideRow = (row + 1) % count }
            return
        }
        switch direction {
        case .right:
            hideTask?.cancel()
            if let armed, let at = chips.firstIndex(of: armed) {
                if at + 1 < chips.count { self.armed = chips[at + 1] }
            } else if stripWasUp, !isFailed, let first = chips.first {
                armed = first
            } else {
                openGuide()
            }
            return
        case .left:
            if let armed {
                let at = chips.firstIndex(of: armed) ?? 0
                self.armed = at > 0 ? chips[at - 1] : nil
                if self.armed == nil { wake() }
            } else if !stripWasUp {
                openGuide()
            }
            return
        default:
            break
        }
        guard direction == .up || direction == .down else { return }
        armed = nil
        guard holdsFocus, !switching else { return }
        switching = true
        // Up is Channel Up, to the next number; down is Channel Down. Both go round the dial.
        let step = direction == .up ? 1 : -1
        Task {
            // Resolved after the schedule, from the channel tuned by then (the sign-on may still
            // be setting it at the press).
            await store.loadSchedule()
            await switchUnderThePigeon(to: store.channel(step: step))
            switching = false
        }
    }

    /// The channel `step` places on tunes behind the programme on screen while the pigeon flies
    /// over it, and cuts in under the bird, as in the Receiver (owner, 2026-10-06): the moment the
    /// channel plays, with the bird flying on over it (2026-10-07).
    /// A channel off air, or one that needs a sign-in, is tuned the ordinary way under the bird.
    private func switchUnderThePigeon(to target: Int) async {
        let pigeon = model.pigeon
        let key = "transmission-\(target)"
        if !UIAccessibility.isReduceMotionEnabled, let pick = pigeon.pick(expected: TuneTimes.expected(key, fallback: 2.5)) {
            await pigeon.arm(pick)
            guard !left else { return }
            pigeon.start()
        }
        async let quiet: Void = store.player.fadeOut()
        let started = ContinuousClock.now
        if let pending = await store.switchBehind(to: target), !left {
            let next = store.incoming
            // The channel's own tune time, signing included, to its first frame; never the bird.
            TuneTimes.recordWhenPlaying(key, player: next, since: started) { !left }
            while !left, !Task.isCancelled {
                let ready = next.state == .playing || { if case .failed = next.state { return true }; return false }()
                if ready {
                    #if DEBUG
                    print("KJSWITCH cut ch=\(pending.channel) state=\(next.state) after=\(ContinuousClock.now - started) bird=\(pigeon.current?.name ?? "-")")
                    #endif
                    store.commitSwitch(pending)
                    break
                }
                // The bird has gone and the channel still tunes: cut now, one flight per press,
                // never a loop (owner, 2026-10-06). The channel shows its own tuning state.
                if !pigeon.isFlying {
                    #if DEBUG
                    print("KJSWITCH early-cut ch=\(pending.channel) state=\(next.state) after=\(ContinuousClock.now - started)")
                    #endif
                    store.commitSwitch(pending)
                    break
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        } else if !left {
            await store.tune(channel: target)
        }
        await quiet
    }

    /// Pauses a picture that is playing. Anything else joins the channel again, live: a paused
    /// transmission is not the transmission any more.
    private func playPause() {
        wake()
        // Mid-switch the picture on screen is about to be replaced: a pause now would be undone
        // by the cut, so the press waits for the new channel.
        guard !switching else { return }
        if store.player.state == .playing || store.player.state == .tuning {
            store.player.pause()
        } else {
            Task { await store.rejoinLive() }
        }
    }

    // MARK: - Coming and going

    /// The sign-on once per launch, then the channel. Every step checks that the viewer is still
    /// here: a clip must not start after the screen has gone.
    private func start() async {
        // Full screen from the corner window, as Apple TV does it: the channel playing in the
        // window is this one, so the screen takes it over as it plays, with no retune.
        let window = model.transmissionPiP
        let adopted = window != nil && store.channelNumber == channel
            && (store.player.state == .playing || store.player.state == .tuning)
        if adopted {
            // Reached by full screen the window is already closing; opened from the channel's card
            // it is not, and is closed here without ending the channel.
            model.transmissionPiP = nil
            window?.stop()
        }
        model.silenceRadio()
        if adopted { return }
        // The sign-on, once per launch: the skin's colour with the channel's name, a pigeon
        // flying over it while the programme tunes behind, and the cut to the picture.
        if !model.clips.signOnPlayed {
            model.clips.signOnPlayed = true
            model.clips.cover(caption: store.channelName(channel))
            let pigeon = model.pigeon
            if !UIAccessibility.isReduceMotionEnabled, let pick = pigeon.pick(expected: TuneTimes.expected("transmission-\(channel)", fallback: 2.5)) {
                await pigeon.arm(pick)
                if !gone { pigeon.start() }
            }
            if !gone { await store.tune(channel: channel) }
            if !gone { await store.player.settled() }
            if !gone { model.clips.uncover() }
            return
        }
        if !gone { await store.tune(channel: channel) }
    }

    private var gone: Bool {
        left || Task.isCancelled
    }

    private var isOffAirNow: Bool {
        if case .offAir = store.phase { return true }
        return false
    }

    private func leave() {
        left = true
        plateTask?.cancel()
        plateChannel = nil
        // The bird is on the window, over every screen: it goes with the player.
        model.pigeon.clear()
        hideTask?.cancel()
        // A picture in the corner window plays on, its subtitles with it: the store keeps it until
        // the window closes, and the window clears the subtitles then.
        if !handedToPiP {
            subtitles.clear()
            store.stop()
        }
        model.clips.clear()
    }

    /// Shows the overlay. Once the programme is playing it hides again after 2.6 seconds without
    /// a press; while tuning, paused or failed it stays.
    private func wake() {
        overlayVisible = true
        hideTask?.cancel()
        // A schedule file (DEBUG, UI tests) plays no picture; its overlay hides as a playing one does.
        guard store.player.state == .playing || store.isScheduleFile else { return }
        guard OverlayTiming.hidesItself else { return }
        hideTask = Task {
            try? await Task.sleep(for: OverlayTiming.idle)
            // The strip stays while a control is lit or the guide is open.
            if !Task.isCancelled, armed == nil, guideRow == nil {
                overlayVisible = false
            }
        }
    }
}
