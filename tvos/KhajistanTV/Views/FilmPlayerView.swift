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
/// (Subtitles, PiP, Stop) are lit as the Transmission strip's are: Down lights the first, left and
/// right walk them, Select works the lit one. With none lit the remote moves the film as Apple's
/// player does (FilmTransport). One Back stops the film (owner, 2026-11-15: "why cant you stop on
/// demand movies").
struct FilmPlayerView: View {
    let film: Film
    /// Opened by the film page's Play: ask for the full film at once, with no preview first.
    var startsFull = false
    /// Closes the screen when UIKit presented it (FilmRestore); SwiftUI's dismiss otherwise.
    var close: (() -> Void)? = nil

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
    private enum Control { case subtitles, pip, stop }
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
    /// A held arrow's scan: its direction and speed, while the arrow is held.
    @State private var scan: (direction: Int, speed: Int)?
    @State private var scanTask: Task<Void, Never>?
    @State private var remoteHold = RemoteHold()
    /// Whether the player was muted before a scan, which is silent as Apple's is.
    @State private var scanWasMuted = false
    /// When a swipe last moved the scrub.
    @State private var lastSwipe: ContinuousClock.Instant?

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            // A picture that does not fill the screen sits on black, whatever the skin (owner,
            // 2026-10-05). Before and after the picture the screen keeps the skin's ground.
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
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
            // A swipe can arrive as a move too: it scrubs, and is not also a skip or a Down.
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
        .onChange(of: controller.state) {
            wake()
            followTracks()
        }
        .fullScreenCover(isPresented: $showSignIn) {
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
                     ? "Finish two-step sign-in, then press Watch the full film again."
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
                .accessibilityIdentifier("watchFullFilm")
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
        .accessibilityLabel("\(Mixes.clock(position)) of \(duration.map(Mixes.clock) ?? "unknown")")
        .accessibilityValue("\(Int(position))")
        .accessibilityIdentifier("filmProgress")
    }

    // MARK: - The full film's controls

    /// The controls, left to right, as the remote walks them.
    private var controls: [Control] {
        [subtitles.tracks.isEmpty ? nil : .subtitles, pipOffered ? .pip : nil, .stop].compactMap { $0 }
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
        if scrub != nil { return endScrub(play: true) }
        switch controller.state {
        case .playing, .paused: controller.toggle()
        // Not while connecting: a pause then drops the seek to the place the film resumes from.
        case .tuning: break
        // After the full film ends, Play plays it again from the start.
        case .idle, .failed: if full == nil { playPreview() } else { Task { await watchFull() } }
        }
    }

    /// Back puts a scrubbed film back where it was, as Apple's player does; then it lets go of a
    /// lit control; otherwise one Back stops the film and closes the screen. It used to hide the
    /// panel first, which read as Back doing nothing.
    private func back() {
        if scrub != nil { return endScrub(play: false) }
        if armed != nil {
            armed = nil
            wake()
            return
        }
        stop()
    }

    /// Up lets go of a lit control; Down lights the first.
    private func vertical(_ direction: Int) {
        wake()
        if direction < 0, armed != nil { armed = nil }
        if direction > 0, armed == nil, scrub == nil { armed = controls.first }
    }

    /// Select on the picture plays from a scrubbed place, works the lit control, else shows the panel.
    private func selectOnSurface() {
        if scrub != nil { return endScrub(play: true) }
        switch armed {
        case .subtitles: subtitles.cycle()
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

    /// The full film, playing. A preview is not put in the corner.
    private var pipOffered: Bool {
        PictureInPicture.isSupported && full != nil && controller.state == .playing
    }

    /// The film goes to a corner window and the screen closes behind it; the film stays in
    /// `model.filmPiP`, which keeps it playing while the viewer browses (one signal at a time:
    /// the next player to start closes the window). Full screen from the window opens the film
    /// again where it had got to; closing the window stops it.
    private func startPictureInPicture() {
        guard pipOffered else { return }
        armed = nil
        let player = controller, film = film, model = model, pip = pip
        let away = FilmAway(film: film, controller: player, pip: pip)
        pip.onStart = {
            guard player.state == .playing || player.state == .tuning else { pip.stop(); return }
            away.recordPlace()
            // AVPlayer draws the chosen subtitles itself in the corner: the house caption view
            // stays with the closed screen, and the track stays selected.
            subtitles.handOff()
            model.filmPiP = away
            leave()
        }
        pip.onFail = { say($0) }
        pip.onRestore = {
            guard model.filmPiP?.controller === player else { return }
            model.restoringFilm = film
        }
        pip.onEnd = {
            if model.filmPiP?.controller === player { model.silenceRadio() } else { player.stop() }
        }
        if !pip.start(player.player) {
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
    private var movable: Bool {
        full != nil && (controller.state == .playing || controller.state == .paused)
    }

    /// Puts the film at `seconds`. `exact` for a place the viewer stops on; a scan or a scrub in
    /// progress takes the nearest frame a second either side, which answers faster.
    private func place(_ seconds: Double, exact: Bool) {
        let target = FilmTransport.clamp(seconds, duration: duration)
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 1, preferredTimescale: 600)
        controller.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
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
        place(position + Double(direction) * FilmTransport.skip, exact: true)
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
            if scanning {
                place(position, exact: true)
                controller.player.isMuted = scanWasMuted
            }
            scan = nil
            return scanning
        }
        guard full != nil, armed == nil, scrub == nil, movable else { return false }
        scanTask?.cancel()
        let started = ContinuousClock.now
        var at = position
        scanWasMuted = controller.player.isMuted
        controller.player.isMuted = true
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
    private func swipe(_ state: UIGestureRecognizer.State, _ points: CGFloat) {
        guard full != nil, armed == nil, scan == nil, movable else { return }
        if state == .began { swipeBase = scrub?.to }
        guard state == .changed else { return }
        lastSwipe = .now
        if scrub == nil {
            // A small touch is a rest of the thumb, not a swipe.
            guard abs(points) > 40 else { return }
            let wasPlaying = controller.state == .playing
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
            if now.isFinite, scan == nil, scrub == nil { position = now }
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
        if full != nil, controller.state == .playing || controller.state == .paused {
            let now = controller.player.currentTime().seconds
            FilmPlaces.record(film.handle, at: now.isFinite ? now : position, of: duration)
        }
        hideTask?.cancel()
        armed = nil
        if scanTask != nil { controller.player.isMuted = scanWasMuted }
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
            // A lit control lets go after the same idle, so a stray swipe Down does not leave
            // left and right walking controls instead of skipping.
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

    /// Where the film has got to, kept as the screen keeps it on Back.
    @MainActor func recordPlace() {
        guard controller.state == .playing || controller.state == .paused else { return }
        let now = controller.player.currentTime().seconds
        let length = controller.player.currentItem?.duration.seconds
        guard now.isFinite else { return }
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
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // The key window, else the app's one window: on a restore from another app the window
        // may not be key yet when the delegate is called.
        let windows = scenes.flatMap(\.windows)
        guard var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else {
            // No window to present on: stop the film with its place kept rather than play it unseen.
            model.silenceRadio()
            return
        }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        // A screen still closing above `top` refuses a present: wait for it to finish, and if
        // it does not, stop the film with its place kept rather than play it unseen.
        if let closing = top.presentedViewController {
            if let coordinator = closing.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in present(film, model: model) }
            } else {
                model.silenceRadio()
            }
            return
        }
        weak var host: UIViewController?
        let screen = FilmPlayerView(film: film, startsFull: true, close: { host?.dismiss(animated: true) })
            .environment(model)
        let controller = UIHostingController(rootView: screen)
        controller.modalPresentationStyle = .fullScreen
        host = controller
        top.present(controller, animated: true)
    }
}
