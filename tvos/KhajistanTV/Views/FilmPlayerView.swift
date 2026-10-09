import AVFoundation
import CoreImage
import SwiftUI

/// A film from the Screening Room, full screen. It opens on the film's public preview, as the
/// site's receiver does when a film is chosen; a preview that ends stops there. "Watch the full film"
/// asks vod-token, and the answer decides: a token plays the film here, a refusal is shown in the
/// site's own words with a code for the film's own page, where it is rented, bought or licensed.
/// Nothing is decided in the app.
///
/// Subtitles are the tracks the stream's manifest announces, listed under the site's labels and
/// switched with a Subtitles control in the panel, beside Watch the full film.
struct FilmPlayerView: View {
    let film: Film

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = PlayerController()
    /// What vod-token granted, while the full film is the thing on screen.
    @State private var full: (kind: String?, expiresAt: String?)?
    @State private var refusal: Int?
    @State private var checking = false
    @State private var showSignIn = false
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var position: Double = 0
    @State private var duration: Double?
    @FocusState private var watchFocused: Bool
    @State private var subtitles = RecordedSubtitles()
    @State private var panelHeight: CGFloat = 0

    private static let jump: Double = 30

    var body: some View {
        let palette = Palette(model.skin)
        ZStack {
            // A picture that does not fill the screen sits on black, whatever the skin (owner,
            // 2026-10-05). Before and after the picture the screen keeps the skin's ground.
            (showsPicture ? Color.black : palette.ground).ignoresSafeArea()
            PlayerLayerView(player: controller.player)
                .ignoresSafeArea()
            CaptionLayer(text: subtitles.text, skin: model.skin, lift: overlayVisible ? panelHeight : 0)
            if overlayVisible {
                overlay(palette)
            } else {
                // While the picture plays alone, this holds focus so a press wakes the overlay.
                Button { wake() } label: { Color.clear }
                    .buttonStyle(SurfaceButtonStyle())
            }
            StationClipLayer(clips: model.clips)
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .onMoveCommand { direction in
            let hidden = !overlayVisible
            wake()
            guard hidden, full != nil else { return }
            switch direction {
            case .left: seek(by: -Self.jump)
            case .right: seek(by: Self.jump)
            default: break
            }
        }
        .onPlayPauseCommand {
            wake()
            switch controller.state {
            case .playing, .paused: controller.toggle()
            case .idle, .failed: if full == nil { playPreview() }
            case .tuning: break
            }
        }
        .onExitCommand {
            stopEverything()
            dismiss()
        }
        .onChange(of: controller.state) {
            wake()
            followTracks()
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: { refusal = nil })
                .environment(\.palette, palette)
        }
        .task { await open() }
        .task { await trackPosition() }
        .onDisappear { stopEverything() }
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
            if full != nil, controller.state == .playing || controller.state == .paused {
                Text(duration.map { "\(Mixes.clock(position)) / \(Mixes.clock($0))" } ?? Mixes.clock(position))
                    .kjSmall()
                    .monospacedDigit()
            }
            Text(Films.attribution)
                .kjSmall(faint: true)
            actions
                .padding(.top, 12)
                .padding(.leading, -26)
            if let refusal {
                Text(Films.denyText(film, status: refusal))
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
            if !subtitles.tracks.isEmpty {
                Button {
                    subtitles.cycle()
                } label: {
                    Text(subtitles.label).kjKicker()
                }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("subtitlesControl")
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
        controller.onEnded = { controller.stop() }
        controller.attach(url: url, seekTo: nil, title: Films.displayTitle(film), subtitle: "Preview", isLive: false)
    }

    private func watchFull() async {
        // The answer is something to read: the panel stays until the viewer moves on.
        hideTask?.cancel()
        checking = true
        refusal = nil
        let answer = await model.films.requestFullFilm(film)
        checking = false
        switch answer {
        case .granted(let token, let kind, let expiresAt):
            guard let url = Films.fullFilmURL(token: token) else {
                refusal = 409
                return
            }
            full = (kind, expiresAt)
            model.clips.cover(caption: Films.displayTitle(film))
            controller.onEnded = { controller.stop() }
            controller.attach(url: url, seekTo: nil, title: Films.displayTitle(film), subtitle: "Khajistan Screening Room", isLive: false)
            await controller.settled()
            model.clips.uncover()
        case .refused(let status):
            refusal = status
        }
    }

    private func seek(by seconds: Double) {
        guard controller.state == .playing || controller.state == .paused else { return }
        var target = max(position + seconds, 0)
        if let duration { target = min(target, max(duration - 1, 0)) }
        controller.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
    }

    private func trackPosition() async {
        while !Task.isCancelled {
            let now = controller.player.currentTime().seconds
            if now.isFinite { position = now }
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
            Task { await subtitles.attach(item, listed: film.subtitle_languages ?? []) }
        case .idle:
            subtitles.clear()
        default:
            break
        }
    }

    private func stopEverything() {
        hideTask?.cancel()
        subtitles.clear()
        controller.stop()
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
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.25)) { overlayVisible = false } }
        }
    }
}
