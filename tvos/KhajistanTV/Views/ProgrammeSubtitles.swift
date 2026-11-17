import AVFoundation
import Foundation

/// A Transmission programme's subtitles, loaded into the player's RecordedSubtitles. Called by the
/// player screen as each programme comes on air, and by the picture-in-picture window, which
/// follows the channel's handovers after the screen has closed (ProgrammeSubtitleFollower).
@MainActor
enum ProgrammeSubtitles {
    /// The programme on air, so a handover loads the next programme's file.
    static func key(_ phase: TransmissionStore.Phase) -> String? {
        guard case .onAir(let air) = phase else { return nil }
        return "\(air.date) \(air.slot.start) \(air.programmeId)"
    }

    /// A Cloudflare Stream programme offers the tracks its own manifest carries (Persian, Urdu,
    /// Arabic…), as the Screening Room does. Its prepared English file is the same text with the
    /// same timings as the manifest's English track (measured 2026-11-15 on all 11 on air), so
    /// the manifest wins; a manifest with no tracks falls back to the file. Any other programme
    /// shows its prepared file, in the language its name gives; without one, no control.
    static func load(into subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel) async {
        subtitles.clear()
        guard case .onAir(let air) = store.phase else { return }
        #if DEBUG
        // `-kjsubtitlefile` gives whatever is on air that file, Stream or not (README).
        if UserDefaults.standard.string(forKey: "kjsubtitlefile") != nil { await loadFile(air, into: subtitles, store: store, model: model); return }
        #endif
        if case .stream = air.programme?.play_url.flatMap(Transmission.route(for:)) {
            await followStreamTracks(air, into: subtitles, store: store, model: model)
        } else {
            await loadFile(air, into: subtitles, store: store, model: model)
        }
    }

    /// The programme's prepared file, read through the site's gate like the schedule.
    private static func loadFile(_ air: OnAir, into subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel) async {
        guard let source = await subtitleSource(air, model: model) else { return }
        let opened = Date()
        let code = SubtitleChoice.fileLanguage(air.programme?.subtitle_url ?? "")
        let language = RecordedSubtitles.Track(
            code: code, label: SubtitleChoice.label(code, listed: SubtitleChoice.house, fallback: nil))
        subtitles.load(vtt: source, language: language) {
            let player = store.player.player
            if player.currentItem != nil {
                let time = player.currentTime().seconds
                return time.isFinite ? time : nil
            }
            #if DEBUG
            // A schedule file plays no picture; the slot's own position stands in for the file's.
            if store.isScheduleFile { return air.seekTo + Date().timeIntervalSince(opened) }
            #endif
            return nil
        }
    }

    /// Lists the tracks of the Stream item the player holds. A handover can leave the last
    /// programme's item playing for a moment, so only stream-host items are read and a later one is
    /// followed when it arrives. A manifest with no tracks falls back to the prepared file. The task
    /// is cancelled when the programme changes.
    private static func followStreamTracks(_ air: OnAir, into subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel) async {
        var tried: AVPlayerItem?
        while !Task.isCancelled {
            if store.player.state == .playing, let item = store.player.player.currentItem, item !== tried,
               (item.asset as? AVURLAsset)?.url.host == KJConfig.streamHost {
                tried = item
                await subtitles.attach(item, film: nil, listed: SubtitleChoice.house, skin: model.skin)
                // Fall back only when this item is still the one playing: a previous Stream
                // programme's item without tracks is no reason to give up on this one. A read that
                // fails on the playing item does fall back, to the same English text.
                if subtitles.tracks.isEmpty, !Task.isCancelled, store.player.player.currentItem === item {
                    await loadFile(air, into: subtitles, store: store, model: model)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func subtitleSource(_ air: OnAir, model: AppModel) async -> String? {
        #if DEBUG
        // `-kjsubtitlefile <path>`: a UI test's WebVTT file for whatever is on air.
        if let path = UserDefaults.standard.string(forKey: "kjsubtitlefile") {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        #endif
        guard let path = air.programme?.subtitle_url, let url = KJURL.sitePath(path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard var (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if (response as? HTTPURLResponse)?.statusCode == 401, let password = model.auth.previewPassword {
            request.setValue(Transmission.basicAuthorization(user: KJConfig.previewUser, password: password), forHTTPHeaderField: "Authorization")
            guard let again = try? await URLSession.shared.data(for: request) else { return nil }
            (data, response) = again
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Keeps a programme's subtitles following the channel while it plays in the corner window: the
/// screen that loaded them has closed, and a handover brings a new programme with its own file or
/// tracks. Read by the window ten times a second (PictureInPicture.captions).
@MainActor
final class ProgrammeSubtitleFollower {
    let subtitles: RecordedSubtitles
    private let store: TransmissionStore
    private let model: AppModel
    private var follower: ChangeFollower<String>
    private var loading: Task<Void, Never>?
    private var ended = false

    /// `loaded` is the programme the screen already loaded for, nil if it had not finished.
    init(_ subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel, loaded: String?) {
        self.subtitles = subtitles
        self.store = store
        self.model = model
        follower = ChangeFollower(loaded: loaded)
    }

    deinit { loading?.cancel() }

    /// The caption on screen now, loading the next programme's first when the channel has moved on.
    /// A stream's tracks, once loaded, go straight to tvOS to draw (the window's); a file's text
    /// is returned for the window to draw into the picture.
    func text() -> String? {
        // A handover in the moment between Full screen and the window closing loads nothing more.
        guard !ended else { return nil }
        if follower.changed(to: ProgrammeSubtitles.key(store.phase)) {
            loading?.cancel()
            let subtitles = subtitles, store = store, model = model
            loading = Task { await ProgrammeSubtitles.load(into: subtitles, store: store, model: model) }
        }
        if !subtitles.tracks.isEmpty, !subtitles.isHandedOff { subtitles.handOff() }
        return subtitles.text
    }

    /// The window is done: stop loading, and clear what was shown unless a screen is taking the
    /// channel over (Full screen), whose own load replaces it.
    func end(clearing: Bool = true) {
        ended = true
        loading?.cancel()
        loading = nil
        if clearing { subtitles.clear() }
    }
}
