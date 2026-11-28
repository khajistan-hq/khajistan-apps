import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// A film from the Screening Room, full screen. It opens on the film's public preview, as the
/// site's receiver does when a film is chosen; a preview that ends stops there. "Watch the full film"
/// asks vod-token, and the answer decides: a token plays the film here, a refusal is shown in the
/// site's own words with a code for the film's own page, where it is rented, bought or licensed.
/// Nothing is decided in the app.
///
/// Subtitles are the tracks the stream's manifest announces, listed under the site's labels and
/// switched with a Subtitles control in the panel, beside Watch the full film.
///
/// In the full film the picture (FilmRemote) keeps the remote's focus. The panel's controls
/// (Subtitles, Play/Pause, PiP, Stop) are lit as the Transmission strip's are: Down lights the first, from the track bar too; left and
/// right walk them, Select works the lit one. With none lit the remote moves the film as Apple's
/// player does (FilmTransport). Back closes the bottom bar, and with it closed stops the film
/// (owner, 2026-11-17); the preview's one Back stops it (owner, 2026-11-15: "why cant you stop on
/// demand movies").
struct FilmPlayerView: View {
    let film: Film
    /// Opened by the film page's Play: ask for the full film at once, with no preview first.
    var startsFull = false
    /// Closes the screen when UIKit presented it (FilmRestore); SwiftUI's dismiss otherwise.
    var close: (() -> Void)? = nil
    /// The film in the picture-in-picture window, when this screen opens as its Full screen: the
    /// screen takes that player over as it plays, as Apple TV hands a film back, with no new token
    /// and no reload.
    private let resuming: FilmAway?

    init(film: Film, startsFull: Bool = false, close: (() -> Void)? = nil, resuming: FilmAway? = nil) {
        self.film = film
        self.startsFull = startsFull
        self.close = close
        self.resuming = resuming
        _controller = State(initialValue: resuming?.controller ?? PlayerController())
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    /// What vod-token granted, while the full film is the thing on screen.
    @State private var full: (kind: String?, expiresAt: String?)?
    @State private var refusal: Int?
    @State private var checking = false
    /// Set once the screen has gone: a token that answers afterwards must not start a film no one sees.
    @State private var gone = false
    @State private var showSignIn = false
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var position: Double = 0
    @State private var duration: Double?
    @FocusState private var watchFocused: Bool
    @State private var subtitles = RecordedSubtitles()
    @State private var panelHeight: CGFloat = 0
    /// The full film's control the remote has lit, if any.
    @State private var armed: Control?
    private typealias Control = FilmTransport.Control
    @State private var pip = PictureInPicture()
    /// A short line in the panel, such as PiP not opening.
    @State private var note: String?
    /// The picture holds focus under the overlay, so a press always has somewhere to land.
    @FocusState private var surfaceFocused: Bool
    /// A swipe's scrub: where the film was when it began, whether it was playing, and the place
    /// shown. Select or Play/Pause plays from the place, Back puts the film back (Apple's player).
    @State private var scrub: (from: Double, wasPlaying: Bool, to: Double)?
    /// Where this swipe starts from: a second swipe carries on from the place the first reached.
    @State private var swipeBase: Double?
    /// The pan on the touch surface, read step by step (FilmTransport.PanReader).
    @State private var pan = FilmTransport.PanReader()
    /// A held arrow's scan: its direction and speed, while the arrow is held.
    @State private var scan: (direction: Int, speed: Int)?
    @State private var scanTask: Task<Void, Never>?
    @State private var remoteHold = RemoteHold()
    /// Whether the film was playing when a scan began: a scan pauses it and steps it, as the scrub
    /// does, so it is silent as Apple's is and the player never buffers between steps.
    @State private var scanWasPlaying = false
    /// When a swipe last moved the scrub.
    @State private var lastSwipe: ContinuousClock.Instant?
    /// Moves still landing; the position poll waits for them.
    @State private var seeksInFlight = 0
    /// The full film has played on this screen, so its kept place has been reached.
    @State private var fullPlayed = false

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            // A picture that does not fill the screen sits on black, whatever the skin (owner,
            // 2026-10-05). Before and after the picture the screen keeps the skin's ground.
            // The full film keeps its black while a move buffers, so a caption in the lower bar
            // never sits on the day's yellow.
            (showsPicture || (full != nil && duration != nil) ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: controller.player, onLayer: pip.bind)
                .ignoresSafeArea()
            CaptionLayer(text: subtitles.text, skin: model.skin, lift: overlayVisible ? panelHeight : 0)
            // Under the overlay in the full film, which has no button of its own there, so focus
            // always has somewhere to go and Play and Back are not lost. Over the preview the
            // offer's buttons hold focus, and the surface waits until the overlay hides.
            if full != nil {
                // The full film's picture: it holds the focus, and a swipe across the remote scrubs.
                FilmRemote(onSelect: selectOnSurface, onSwipe: swipe)
                    .ignoresSafeArea()
            } else if !overlayVisible {
                Button { selectOnSurface() } label: { Color.clear }
                    .buttonStyle(SurfaceButtonStyle())
                    .focused($surfaceFocused)
            }
            if overlayVisible {
                overlay(palette)
            }
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        // tvOS hands each press to SwiftUI once, at its release: a click. A held edge is read by
        // RemoteHold, and the move that ends it is not counted as a click as well.
        .onMoveCommand { direction in
            guard full != nil else { return wake() }
            // A swipe can arrive as a move too: it scrubs, and is not also a skip or a Down. Any
            // move in the half second after a swipe is dropped, a real click included.
            if let lastSwipe, ContinuousClock.now - lastSwipe < .milliseconds(500) { return }
            switch direction {
            case .left: if !remoteHold.swallows(-1) { click(-1) }
            case .right: if !remoteHold.swallows(1) { click(1) }
            case .up: vertical(-1)
            case .down: vertical(1)
            @unknown default: break
            }
        }
        .onPlayPauseCommand { playPause() }
        .onExitCommand { back() }
        .onChange(of: full != nil) { _, on in
            if on {
                remoteHold.start { hold($0, $1) }
            } else {
                remoteHold.stop()
            }
        }
        .onChange(of: pipOffered) { _, offered in if !offered, armed == .pip { armed = nil } }
        .onChange(of: subtitles.tracks.isEmpty) { _, empty in if empty, armed == .subtitles { armed = nil } }
        .onChange(of: controller.state) { _, state in
            if full != nil, state == .playing { fullPlayed = true }
            // A stopped player has no seek left to land; the poll must not wait on one for good.
            if state == .idle { seeksInFlight = 0 }
            wake()
            followTracks()
        }
        .kjFullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: { refusal = nil })
                .environment(\.palette, palette)
        }
        .task { await open() }
        #if DEBUG
        // `-kjrestoreover YES`: eight seconds after the first player opens, the picture-in-picture
        // window's "full screen" is asked for, so a UI test sees the film reopen over a cover.
        .task {
            guard UserDefaults.standard.bool(forKey: "kjrestoreover"), !FilmRestore.debugFired else { return }
            FilmRestore.debugFired = true
            try? await Task.sleep(for: .seconds(8))
            model.restoringFilm = film
        }
        #endif
        .task { await trackPosition() }
        // A cover presented over the player (Sign in) can take its appearance and give it back.
        .onAppear { gone = false }
        .onDisappear { gone = true; stopEverything() }
    }

    // MARK: - Overlay

    private func overlay(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            StatusBand(leading: ["Khajistan Receiver", "On Demand"], trailing: [full == nil ? "Film" : "The full film"])
            Spacer(minLength: 0)
            panel
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ground, ignoresSafeAreaEdges: [.horizontal, .bottom])
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(stateText)
                .accessibilityIdentifier("playerState")
            Text(Films.displayTitle(film))
                .kjDisplay(KJType.headline, tracking: -0.055)
                .lineLimit(2)
            let detail = Films.detail(film)
            if !detail.isEmpty {
                Text(detail).kjBody()
            }
            Text(showingLine).kjBody()
            if let full {
                Text("Your access \u{00B7} \(Films.accessLine(kind: full.kind, expiresAt: full.expiresAt))").kjBody()
            } else if let offer = Films.offer(film) {
                Kicker(offer)
            }
            if movable {
                progress
            }
            Text(Films.attribution)
                .kjSmall(faint: true)
            actions
                .padding(.top, 12)
                .padding(.leading, -26)
            if let note {
                Text(note).kjBody()
            }
            if let refusal {
                // A staff account that still owes its authenticator code is refused like a buyer.
                Text(refusal == 403 && model.auth.pendingFactorId != nil
                     ? "Finish two-step sign-in."
                     : Films.denyText(film, status: refusal))
                    .kjBody()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filmNote")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Watch the full film, and Sign in where the answer was a sign-in. Nothing to press to start
    /// what is already playing.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if full == nil {
                Button {
                    Task { await watchFull() }
                } label: {
                    Text(checking ? "Checking your access\u{2026}" : "Watch the full film").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .disabled(checking)
                .focused($watchFocused)
                // The screen reopened from the window (FilmRestore, the one caller with `close`)
                // sits over a cover with its own Watch button: told apart for the UI tests.
                .accessibilityIdentifier(close == nil ? "watchFullFilm" : "watchFullFilmReopened")
            }
            if full != nil {
                fullFilmControls
            } else {
                if !subtitles.tracks.isEmpty {
                    Button {
                        subtitles.cycle()
                    } label: {
                        Text(subtitles.label).kjKicker()
                    }
                    .buttonStyle(HouseButtonStyle())
                    .accessibilityIdentifier("subtitlesControl")
                }
                Button {
                    stop()
                } label: {
                    Text("Stop").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                // Not while access is checked: a second Select on Watch must not land here.
                .disabled(checking)
                .accessibilityIdentifier("stopControl")
            }
            if refusal == 403 && model.auth.pendingFactorId != nil {
                Button {
                    showSignIn = true
                } label: {
                    Text("Finish two-step sign-in").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("filmFinishCode")
            }
            if refusal == 401 && !model.auth.isSignedIn {
                Button {
                    showSignIn = true
                } label: {
                    Text("Sign in").kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("filmSignIn")
            }
        }
    }

    // MARK: - The bar

    /// Where the film is, as Apple's bar shows it: the time played, the bar, the time left, and
    /// the scan speed or the scrub's way out while either is going on.
    private var progress: some View {
        let ink = Palette(model.skin).ink
        let fraction = duration.map { $0 > 0 ? min(max(position / $0, 0), 1) : 0 } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.22))
                    Capsule().fill(ink).frame(width: bar.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack(spacing: 24) {
                Text(Mixes.clock(position))
                if let scan {
                    Text((scan.direction < 0 ? "\u{25C0}\u{25C0} " : "\u{25B6}\u{25B6} ") + "\(scan.speed)\u{00D7}")
                } else if scrub != nil {
                    Text("Select plays from here \u{00B7} Back returns")
                }
                Spacer(minLength: 0)
                if let duration { Text(FilmTransport.remaining(position, of: duration)) }
            }
            .kjSmall()
            .monospacedDigit()
        }
        .frame(maxWidth: 1200)
        .accessibilityElement(children: .ignore)
        // The scrub's way out is read with the place: the bar's children are not elements of their own.
        .accessibilityLabel("\(Mixes.clock(position)) of \(duration.map(Mixes.clock) ?? "unknown")"
                            + (scrub != nil ? ". Select plays from here \u{00B7} Back returns" : ""))
        .accessibilityValue("\(Int(position))")
        .accessibilityIdentifier("filmProgress")
    }

    // MARK: - The full film's controls

    /// The controls, left to right, as the remote walks them.
    private var controls: [Control] {
        FilmTransport.controls(hasSubtitles: !subtitles.tracks.isEmpty, pipOffered: pipOffered)
    }

    /// The panel's own button faces, lit by the remote rather than focused: the picture under them
    /// keeps focus so left and right still skip. The first carries the Down hint while none is lit.
    private var fullFilmControls: some View {
        HStack(spacing: 12) {
            ForEach(Array(controls.enumerated()), id: \.offset) { index, control in
                let hint = armed == nil && index == 0 ? "\u{2193} " : ""
                switch control {
                case .subtitles:
                    HouseButtonStyle.face(Text(hint + subtitles.label).kjKicker(), selected: armed == .subtitles)
                        .accessibilityLabel(subtitles.label)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("subtitlesControl")
                        .accessibilityAction { subtitles.cycle() }
                        .accessibilityAddTraits(armed == .subtitles ? .isSelected : [])
                case .playPause:
                    // Connecting is on its way to playing: Pause, as the film is about to play.
                    let word = controller.state == .playing || controller.state == .tuning ? "Pause" : "Play"
                    HouseButtonStyle.face(Text(hint + word).kjKicker(), selected: armed == .playPause)
                        .accessibilityLabel(word)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("playPauseControl")
                        .accessibilityAction { playPause() }
                        .accessibilityAddTraits(armed == .playPause ? .isSelected : [])
                case .pip:
                    HouseButtonStyle.face(Text(hint + "PiP").kjKicker(), selected: armed == .pip)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Picture in picture")
                        .accessibilityIdentifier("pipControl")
                        .accessibilityAction { startPictureInPicture() }
                        .accessibilityAddTraits(armed == .pip ? .isSelected : [])
                case .stop:
                    HouseButtonStyle.face(Text(hint + "Stop").kjKicker(), selected: armed == .stop)
                        .accessibilityLabel("Stop")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("stopControl")
                        .accessibilityAction { stop() }
                        .accessibilityAddTraits(armed == .stop ? .isSelected : [])
                }
            }
        }
    }

    /// Play/Pause: plays from a scrubbed place, or pauses and plays.
    private func playPause() {
        wake()
        // A scan has paused the film and plays it on at release; playing under it would buffer.
        if scan != nil { return }
        if scrub != nil { return endScrub(play: true) }
        switch controller.state {
        case .playing, .paused: controller.toggle()
        // Not while first connecting: a pause then drops the seek to the place the film resumes
        // from. Once the film has played there is no such seek, and a lit Pause pauses.
        case .tuning: if fullPlayed { controller.pause() }
        // After the full film ends, Play plays it again from the start.
        case .idle, .failed: if full == nil { playPreview() } else { Task { await watchFull() } }
        }
    }

    /// Back, in order: puts a scrubbed film back where it was; closes the full film's bottom bar
    /// over its picture; lets go of a lit control (under VoiceOver, where the bar stays); otherwise
    /// stops the film and closes the screen. With no picture under the bar (connecting, ended,
    /// failed, refused) it stops at once, since the bar is then all there is to read.
    private func back() {
        if scrub != nil { return endScrub(play: false) }
        // In the full film Back closes the bottom bar first, as Apple's player does (owner,
        // 2026-11-17: "a back button shoud exit the bottom bar"); with the bar closed, Back stops
        // the film. Not under VoiceOver, where the bar never hides: there Back lets go of a lit control,
        // then stops the film.
        // `movable`: a picture is on, playing, paused or catching up after a skip.
        if movable, overlayVisible, refusal == nil, OverlayTiming.hidesItself {
            armed = nil
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.25)) { overlayVisible = false }
            return
        }
        // With no picture under the bar (connecting, ended, failed) a lit control does not hold
        // Back: the film stops at once, as the comment above says.
        if armed != nil, movable {
            armed = nil
            wake()
            return
        }
        stop()
    }

    /// Up lets go of a lit control; Down lights the first, from the track bar too.
    private func vertical(_ direction: Int) {
        wake()
        if direction < 0, armed != nil { armed = nil }
        guard direction > 0, armed == nil else { return }
        // Down from the track bar: the film stays, paused, at the place the swipe reached, and the
        // controls light, as Apple's player leaves the bar for its row of options.
        if scrub != nil { settleScrub() }
        armed = controls.first
    }

    /// Select on the picture plays from a scrubbed place, works the lit control, else shows the panel.
    private func selectOnSurface() {
        if scrub != nil { return endScrub(play: true) }
        switch armed {
        case .subtitles: subtitles.cycle()
        case .playPause: return playPause()
        case .pip: return startPictureInPicture()
        case .stop: return stop()
        case nil: break
        }
        wake()
    }

    /// Stops the film and closes the screen.
    private func stop() {
        stopEverything()
        leave()
    }

    private func leave() {
        if let close { close() } else { dismiss() }
    }

    // MARK: - Picture in picture

    /// The full film, playing, paused or reconnecting (owner, 2026-11-18: no PiP on a paused film
    /// read as no PiP at all). A preview is not put in the corner.
    private var pipOffered: Bool {
        PictureInPicture.isSupported && full != nil
            && (controller.state == .playing || controller.state == .paused || controller.state == .tuning)
    }

    /// The film goes to a corner window and the screen closes behind it; the film stays in
    /// `model.filmPiP`, which keeps it playing while the viewer browses (one signal at a time:
    /// the next player to start closes the window). Full screen from the window opens the film
    /// again where it had got to; closing the window stops it.
    private func startPictureInPicture() {
        // One window at a time: a second activation while the first opens would let go of its
        // closures (VoiceOver can activate twice; the remote unlights on the first Select).
        guard pipOffered, !pip.isOpening, !pip.isActive else { return }
        armed = nil
        let player = controller, film = film, model = model, pip = pip
        // Paused, it plays as it goes to the corner, as Apple TV's own player does; the window's
        // start reads .tuning or .playing as a film to keep. A window that does not open leaves
        // the film paused, where it was.
        let wasPaused = player.state == .paused
        // Where it was paused: a window that fails to open puts the film back there, not where it
        // played on to while the window started.
        let pausedAt = player.player.currentTime()
        let backToPause = {
            player.pause()
            if pausedAt.isNumeric { player.player.seek(to: pausedAt, toleranceBefore: .zero, toleranceAfter: .zero) }
        }
        if wasPaused { player.resume() }
        // The object, not the screen's state: the window reads it after the screen has closed.
        let subtitles = subtitles
        let away = FilmAway(film: film, controller: player, pip: pip, grant: full)
        pip.title = Films.displayTitle(film)
        // The film's track goes to tvOS as the window opens, which draws it in the skin's colours;
        // the bar's control moves it to the next language.
        pip.onHandOff = { subtitles.handOff() }
        pip.captionLabel = { subtitles.isHandedOff ? subtitles.label : nil }
        pip.onCaptionToggle = { subtitles.cycle() }
        pip.captions = { subtitles.text }
        pip.skin = { model.skin }
        pip.onSetPlaying = { $0 ? player.resume() : player.pause() }
        pip.controller = player
        pip.onStart = {
            guard player.state == .playing || player.state == .tuning else { pip.stop(); return }
            away.recordPlace()
            model.filmPiP = away
            leave()
        }
        pip.onFail = { line in
            if wasPaused, model.filmPiP?.controller !== player { backToPause() }
            say(line)
        }
        pip.onRestore = {
            guard model.filmPiP?.controller === player else { return }
            // The track stays selected, so the window keeps its subtitle until it has closed; the
            // screen that takes the film over attaches the tracks afresh, which hides tvOS's own.
            model.restoringFilm = film
        }
        pip.onEnd = {
            subtitles.clear()
            if model.filmPiP?.controller === player { model.silenceRadio() } else { player.stop() }
        }
        if !pip.start(player.player) {
            if wasPaused { backToPause() }
            pip.letGo()
            say("Picture in picture is not ready yet. Try again in a moment.")
        }
        wake()
    }

    /// A line in the panel for a few seconds.
    private func say(_ line: String) {
        note = line
        wake()
        Task {
            try? await Task.sleep(for: .seconds(4))
            if note == line { note = nil }
        }
    }

    /// A preview or the film is on screen, playing or paused.
    private var showsPicture: Bool {
        controller.state == .playing || controller.state == .paused
    }

    private var showingLine: String {
        if full != nil {
            return "The full film" + (film.runtime_minutes.map { " \u{00B7} \($0) minutes" } ?? "")
        }
        if Films.previewURL(film) != nil {
            return "\(film.preview_seconds ?? 60)-second preview \u{00B7} the full film plays here"
        }
        return "No preview clip \u{00B7} the full film plays here"
    }

    private var stateText: String {
        switch controller.state {
        case .idle: return "On Demand"
        case .tuning: return "Connecting\u{2026}"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .failed(let message): return message
        }
    }

    // MARK: - Playing

    /// The screen opens on the ground with the film's name and the preview tuning behind it.
    private func open() async {
        if let resuming, model.filmPiP?.controller === resuming.controller {
            // Taken over before anything else is silenced, so silenceRadio leaves the film playing.
            model.filmPiP = nil
            model.silenceRadio()
            full = resuming.grant ?? (kind: nil, expiresAt: nil)
            surfaceFocused = true
            // Paused in the window or playing, its tracks come back to the house view once the
            // window has closed into the screen (tvOS draws them in the window until then).
            try? await Task.sleep(for: PictureInPicture.restoreSettle)
            if !gone, let item = controller.player.currentItem {
                await subtitles.attach(item, film: film.handle, listed: film.subtitle_languages ?? [], skin: model.skin)
            }
            wake()
            return
        }
        model.silenceRadio()
        // The film's own subtitle language is turned on by RecordedSubtitles. Left automatic, the
        // player can put the device's subtitle setting over it once the item is ready.
        controller.player.appliesMediaSelectionCriteriaAutomatically = false
        if startsFull {
            await watchFull()
            if full == nil { watchFocused = true }
            return
        }
        // The offer's button first, not the picture under it.
        watchFocused = true
        guard Films.previewURL(film) != nil else {
            watchFocused = true
            return
        }
        model.clips.cover(caption: Films.displayTitle(film), animated: false)
        playPreview()
        await controller.settled()
        guard !Task.isCancelled else { return }
        model.clips.uncover()
        watchFocused = true
    }

    private func playPreview() {
        guard let url = Films.previewURL(film) else { return }
        // A preview that reaches its end stops there; the site does not roll on to another film.
        controller.onEnded = { [weak controller] in controller?.stop() }
        controller.attach(url: url, seekTo: nil, title: Films.displayTitle(film), subtitle: "Preview", isLive: false)
    }

    private func watchFull() async {
        // The answer is something to read: the panel stays until the viewer moves on.
        hideTask?.cancel()
        checking = true
        refusal = nil
        // A new connect, with its own seek to the kept place: Pause and the skips wait for it to
        // play again (playPause, movable), as on the first connect.
        fullPlayed = false
        #if DEBUG
        // `-kjfilmasfull YES`: the preview plays as the full film, so a UI test reaches the full
        // film's controls without an account that holds a film. Debug builds only.
        if UserDefaults.standard.bool(forKey: "kjfilmasfull"), let preview = Films.previewURL(film) {
            checking = false
            full = ("test", nil)
            controller.onEnded = { [weak controller, model] in
                if let controller, model.filmPiP?.controller === controller { model.silenceRadio() }
                controller?.stop()
            }
            controller.attach(url: preview, seekTo: nil, title: Films.displayTitle(film), subtitle: "Khajistan Screening Room", isLive: false)
            // `-kjscrubopen YES`: once the film plays, a swipe opens the track bar, so a UI test can
            // press Down from it (XCUIRemote sends no swipes). Debug builds only.
            if UserDefaults.standard.bool(forKey: "kjscrubopen") {
                Task {
                    for _ in 0..<60 where controller.state != .playing { try? await Task.sleep(for: .milliseconds(500)) }
                    try? await Task.sleep(for: .seconds(3))
                    swipe(.began, .zero)
                    swipe(.changed, CGPoint(x: 400, y: 0))
                }
            }
            return
        }
        #endif
        let answer = await model.films.requestFullFilm(film)
        checking = false
        // Back pressed while vod-token answered: the film would play, and keep the TV awake, with
        // no screen. The Play button's and the offer's Tasks are not the view's own.
        guard !gone, !Task.isCancelled else { return }
        switch answer {
        case .granted(let token, let kind, let expiresAt):
            guard let url = Films.fullFilmURL(token: token) else {
                refusal = 409
                return
            }
            // The picture (FilmRemote) takes the remote's focus once it is on screen: Watch the
            // full film, which held it, is gone, and with focus nowhere nothing answered on the
            // owner's Apple TV (2026-11-16: no pause, no skipping, no other languages).
            full = (kind, expiresAt)
            model.clips.cover(caption: Films.displayTitle(film))
            // Watched to the end: it leaves Up Next. Ended in the corner window, the window closes.
            controller.onEnded = { [weak controller, handle = film.handle, model] in
                if let controller, model.filmPiP?.controller === controller { model.silenceRadio() }
                FilmPlaces.forget(handle)
                controller?.stop()
            }
            let resume = FilmPlaces.position(film.handle)
            controller.attach(url: url, seekTo: resume,
                              title: Films.displayTitle(film), subtitle: "Khajistan Screening Room", isLive: false)
            await controller.settled()
            model.clips.uncover()
        case .refused(let status):
            if status == 403 { await model.auth.rearmCode() }
            refusal = status
        }
    }

    // MARK: - The remote, as Apple's player reads it

    /// The film is on screen and can be moved.
    /// Playing or paused, or catching up after a move (tuning) once its length is known, so quick
    /// clicks add up as Apple's do rather than the next one waiting for the last to buffer.
    private var movable: Bool {
        guard full != nil else { return false }
        switch controller.state {
        case .playing, .paused: return true
        // Not before the full film has first played: the move would land before its kept place.
        case .tuning: return duration != nil && fullPlayed
        default: return false
        }
    }

    /// Puts the film at `seconds`. `exact` for a place the viewer stops on; a scan or a scrub in
    /// progress takes the nearest frame a second either side, which answers faster.
    private func place(_ seconds: Double, exact: Bool) {
        let target = FilmTransport.clamp(seconds, duration: duration)
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 1, preferredTimescale: 600)
        // Counted until it lands: meanwhile the player's clock still reads the old place, and the
        // half-second poll would undo this move before the next click adds to it.
        seeksInFlight += 1
        controller.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            DispatchQueue.main.async { seeksInFlight = max(seeksInFlight - 1, 0) }
        }
        position = target
    }

    /// A click left or right: with a control lit, walks the controls; in a scrub, moves the place
    /// ten seconds; otherwise skips ten seconds.
    private func click(_ direction: Int) {
        guard full != nil else { return }
        wake()
        if let lit = armed, let index = controls.firstIndex(of: lit) {
            if controls.indices.contains(index + direction) { armed = controls[index + direction] }
            return
        }
        guard movable else { return }
        if let current = scrub {
            let to = FilmTransport.clamp(current.to + Double(direction) * FilmTransport.skip, duration: duration)
            scrub = (current.from, current.wasPlaying, to)
            place(to, exact: false)
            return
        }
        place(here + Double(direction) * FilmTransport.skip, exact: true)
    }

    /// Where the film is: the place a move under way goes to, else the player's own clock, which
    /// the half-second poll may not have read yet (a film back from the corner window reads 0
    /// until it does, and a first skip from there went to 0:10).
    private var here: Double {
        guard seeksInFlight == 0 else { return position }
        let now = controller.player.currentTime().seconds
        return now.isFinite ? now : position
    }

    /// A held arrow scans the film, faster the longer it is held; letting go plays from there.
    /// Answers whether the hold was taken: not while a control is lit, a scrub is up or the film
    /// is not on screen.
    private func hold(_ direction: Int, _ began: Bool) -> Bool {
        guard began else {
            // Whatever else is on screen, a scan in progress ends when the press is let go.
            let scanning = scanTask != nil
            scanTask?.cancel()
            scanTask = nil
            // A film that failed during the scan is left failed, for Play to try again.
            if scanning, movable {
                place(position, exact: true)
                if scanWasPlaying { controller.resume() }
            }
            scan = nil
            return scanning
        }
        guard full != nil, armed == nil, scrub == nil, movable else { return false }
        scanTask?.cancel()
        let started = ContinuousClock.now
        var at = here
        // Paused, a seek does not make the player wait to play: playing, each step buffered, the
        // film fell out of `movable` and the scan stopped (Fable, 2026-11-17).
        scanWasPlaying = controller.state != .paused
        if scanWasPlaying { controller.pause() }
        scanTask = Task {
            while !Task.isCancelled, movable {
                let held = (ContinuousClock.now - started) / .seconds(1)
                at = FilmTransport.clamp(at + Double(direction) * FilmTransport.scanStep(heldFor: held), duration: duration)
                scan = (direction, FilmTransport.scanSpeed(heldFor: held))
                place(at, exact: false)
                wake()
                try? await Task.sleep(for: .seconds(FilmTransport.scanTick))
            }
        }
        return true
    }

    /// A swipe across the touch surface scrubs: the film pauses on the place the swipe reaches.
    /// The place is kept until Select or Play/Pause plays from it, or Back puts the film back.
    private func swipe(_ state: UIGestureRecognizer.State, _ translation: CGPoint) {
        // A new pan starts a new reading even when this one is not taken, so its first step is
        // not measured from where the last pan ended.
        if state == .began { pan = FilmTransport.PanReader() }
        guard full != nil, armed == nil, scan == nil, movable else { return }
        if state == .began { swipeBase = scrub?.to }
        guard state == .changed else { return }
        let points = translation.x
        let step = pan.read(x: Double(translation.x), y: Double(translation.y))
        // A slide that runs down rather than across is not a scrub: it moves no place and stamps
        // nothing, so a click Down after it is not dropped as part of a swipe. During a scrub it
        // leaves the bar for the control row, as Down does (owner, 2026-11-18: "when you touch
        // down on the apple tv remote it should go to subtitles, stop/play and pip").
        if step.vertical {
            if scrub != nil, step.slideDown { vertical(1) }
            return
        }
        lastSwipe = .now
        if scrub == nil {
            // A small touch is a rest of the thumb, not a swipe.
            guard abs(points) > 40 else { return }
            let wasPlaying = controller.state != .paused
            if wasPlaying { controller.pause() }
            scrub = (position, wasPlaying, position)
        }
        guard let current = scrub else { return }
        let base = swipeBase ?? current.from
        let to = FilmTransport.clamp(base + FilmTransport.scrubSeconds(points: Double(points), duration: duration), duration: duration)
        scrub = (current.from, current.wasPlaying, to)
        place(to, exact: false)
        wake()
    }

    /// Leaves a scrub where it reached, paused: the place is kept and nothing plays.
    private func settleScrub() {
        guard let current = scrub else { return }
        scrub = nil
        swipeBase = nil
        place(current.to, exact: true)
        wake()
    }

    /// Ends a scrub: plays from the place reached, or puts the film back where it was.
    private func endScrub(play: Bool) {
        guard let current = scrub else { return }
        scrub = nil
        swipeBase = nil
        place(play ? current.to : current.from, exact: true)
        if play || current.wasPlaying { controller.resume() }
        wake()
    }

    private func trackPosition() async {
        while !Task.isCancelled {
            let now = controller.player.currentTime().seconds
            // A scan or a scrub sets the place itself; the clock catches up when it ends.
            if now.isFinite, scan == nil, scrub == nil, seeksInFlight == 0 { position = now }
            let length = controller.player.currentItem?.duration.seconds
            duration = (length?.isFinite == true && (length ?? 0) > 0) ? length : nil
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The tracks of whatever is playing: the preview's, then the full film's once it plays.
    private func followTracks() {
        switch controller.state {
        case .playing:
            guard let item = controller.player.currentItem, !subtitles.follows(item) else { return }
            Task { await subtitles.attach(item, film: film.handle, listed: film.subtitle_languages ?? [], skin: model.skin) }
        case .idle:
            subtitles.clear()
        default:
            break
        }
    }

    private func stopEverything() {
        // Only the full film's place is kept, as on the phone; a preview has none.
        // The player's own clock, not the half-second poll, which can still hold the preview's.
        if full != nil, [.playing, .paused, .tuning].contains(controller.state) {
            let now = controller.player.currentTime().seconds
            if (now.isFinite && now > 0) || controller.state != .tuning {
                FilmPlaces.record(film.handle, at: now.isFinite ? now : position, of: duration)
            }
        }
        hideTask?.cancel()
        armed = nil
        scanTask?.cancel()
        scanTask = nil
        remoteHold.stop()
        // The film handed to the corner window keeps playing.
        if model.filmPiP?.controller !== controller {
            subtitles.clear()
            controller.stop()
        }
        model.clips.clear()
    }

    /// Shows the overlay. While a picture plays it hides again after 2.6 seconds without a press;
    /// otherwise it stays, because it is what there is to read, and so does an answer from vod-token.
    private func wake() {
        if !overlayVisible {
            withAnimation(.easeOut(duration: 0.25)) { overlayVisible = true }
            if full == nil { watchFocused = true }
        }
        hideTask?.cancel()
        guard controller.state == .playing, !showSignIn, !checking, refusal == nil else { return }
        guard OverlayTiming.hidesItself else { return }
        hideTask = Task {
            try? await Task.sleep(for: OverlayTiming.idle)
            // A lit control stays long enough to read its label and press Select: at the plain idle
            // it let go before the press, and Select only woke the panel (Fable, 2026-11-17). It
            // still lets go in the end, so a stray swipe Down does not leave left and right walking
            // controls instead of skipping.
            if !Task.isCancelled, armed != nil { try? await Task.sleep(for: OverlayTiming.armedIdle) }
            if !Task.isCancelled { armed = nil; withAnimation(.easeOut(duration: 0.25)) { overlayVisible = false } }
        }
    }
}

/// A full film handed to the picture-in-picture window: the player keeps it playing after its
/// screen closes, as RadioAway keeps a channel.
struct FilmAway {
    let film: Film
    let controller: PlayerController
    let pip: PictureInPicture
    /// What vod-token granted, carried back to the screen that takes the film over.
    var grant: (kind: String?, expiresAt: String?)? = nil

    /// Where the film has got to, kept as the screen keeps it on Back.
    @MainActor func recordPlace() {
        // .tuning too: a paused film sent to the corner is resuming, and its place still counts.
        guard [.playing, .paused, .tuning].contains(controller.state) else { return }
        let now = controller.player.currentTime().seconds
        let length = controller.player.currentItem?.duration.seconds
        guard now.isFinite, now > 0 else { return }
        FilmPlaces.record(film.handle, at: now, of: (length?.isFinite == true && (length ?? 0) > 0) ? length : nil)
    }
}

/// Opens a film full screen again from its picture-in-picture window, over whatever screen is on
/// top. SwiftUI cannot present from the root while a film page or a room is a cover over it, and
/// the window has already closed by then: the film would play on as sound with nothing on screen.
@MainActor
enum FilmRestore {
    #if DEBUG
    static var debugFired = false
    #endif

    static func present(_ film: Film, model: AppModel) {
        // No window, or a closing screen in the way: stop the film with its place kept rather
        // than play it unseen.
        // The film in the window is handed back, not fetched again.
        let playing = model.filmPiP.flatMap { $0.film.handle == film.handle ? $0 : nil }
        TopScreen.present(model: model, otherwise: { model.silenceRadio() }) { close in
            FilmPlayerView(film: film, startsFull: true, close: close, resuming: playing)
        }
    }
}
