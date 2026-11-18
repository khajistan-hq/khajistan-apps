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
    /// All of it waits for tv_subtitles() (Screen & Signal, owner 2026-11-17): closed, a Stream
    /// programme's own tracks are deselected and no file is shown. The files come back as text
    /// in the answer; the site no longer serves /assets/tv-subtitles/ (404 in every gate state).
    static func load(into subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel) async {
        subtitles.clear()
        guard case .onAir(let air) = store.phase else { return }
        #if DEBUG
        // `-kjsubtitlefile` gives whatever is on air that file, Stream or not (README).
        if UserDefaults.standard.string(forKey: "kjsubtitlefile") != nil {
            await loadFile(air, .closed, into: subtitles, store: store); return
        }
        #endif
        let onStream: Bool
        if case .stream = air.programme?.play_url.flatMap(Transmission.route(for:)) { onStream = true } else { onStream = false }
        // Which programmes hold a stored track is still read from subtitle_url, which the
        // schedule writes for every prepared file although the path itself now answers 404:
        // a schedule built without it would leave every file programme silent.
        guard air.programme?.subtitle_url != nil || onStream else { return }
        guard onStream else {
            let stored = await storedSubtitles(air, model: model)
            if stored.open, !Task.isCancelled { await loadFile(air, stored, into: subtitles, store: store) }
            return
        }
        // A Stream programme's own tracks are silenced from the moment it attaches, not after the
        // answer: with tvOS's Closed Captions setting on, AVPlayer would otherwise draw one itself
        // while tv_subtitles() is asked. Open, the silencing stops and the tracks are followed;
        // closed, it runs until the programme changes (this task is cancelled).
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await silenceStreamTracks(store: store) }
            let stored = await storedSubtitles(air, model: model)
            guard !Task.isCancelled else { group.cancelAll(); return }
            if stored.open {
                group.cancelAll()
                await followStreamTracks(air, stored, into: subtitles, store: store, model: model)
            }
        }
    }

    /// tv_subtitles() for the programme on air, asked with the viewer's session. A failed try
    /// (no token, no answer, not 200) is tried again after 2, 10 and 30 seconds while this
    /// programme is still on, so one dropped request or a token refresh caught in a network gap
    /// does not silence a whole film; an answer, open or closed, is final for the programme.
    private static func storedSubtitles(_ air: OnAir, model: AppModel) async -> StoredSubtitles {
        for delay in StoredSubtitles.retryDelays where !Task.isCancelled {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { break }
            guard let token = try? await model.auth.validAccessToken() else { continue }
            guard let request = StoredSubtitles.request(programme: air.programmeId, accessToken: token) else { return .closed }
            if let (data, response) = try? await SupabaseRoute.data(for: request, session: .shared),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return StoredSubtitles.parse(data)
            }
        }
        return .closed
    }

    /// Closed on a Stream programme: AVPlayer could still render a manifest track itself when the
    /// system caption setting asks for one, so each item of this signal has its legible group cleared.
    private static func silenceStreamTracks(store: TransmissionStore) async {
        var done: AVPlayerItem?
        while !Task.isCancelled {
            if let item = store.player.player.currentItem, item !== done,
               let asset = item.asset as? AVURLAsset, asset.url.host == KJConfig.streamHost,
               asset.url == store.player.attachedURL {
                done = item
                if let group = try? await asset.loadMediaSelectionGroup(for: .legible), !Task.isCancelled {
                    item.select(nil, in: group)
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The programme's prepared files, the text tv_subtitles() returned with the answer: English,
    /// and Urdu, Persian or Arabic where made. Opens as video.html does (SubtitleChoice.fileOpener).
    private static func loadFile(_ air: OnAir, _ stored: StoredSubtitles, into subtitles: RecordedSubtitles, store: TransmissionStore) async {
        let files = fileTracks(subtitleSources(air, stored))
        guard !files.isEmpty else { return }
        let opened = Date()
        let first = SubtitleChoice.fileOpener(
            available: files.map(\.0.code), stored: UserDefaults.standard.string(forKey: SubtitleChoice.storeKey),
            preferred: Locale.preferredLanguages, named: SubtitleChoice.fileLanguage(air.programme?.subtitle_url ?? ""))
        subtitles.load(files: files, first: first) {
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
    /// programme's item playing for a moment, so only the item of the signal this programme started
    /// (PlayerController.attachedURL) is read, and a later one (a re-tune mints a new address) is
    /// followed when it arrives. A manifest with no tracks falls back to the prepared file. The
    /// task is cancelled when the programme changes.
    private static func followStreamTracks(_ air: OnAir, _ stored: StoredSubtitles, into subtitles: RecordedSubtitles,
                                           store: TransmissionStore, model: AppModel) async {
        var tried: AVPlayerItem?
        while !Task.isCancelled {
            if store.player.state == .playing, let item = store.player.player.currentItem, item !== tried,
               let asset = item.asset as? AVURLAsset, asset.url.host == KJConfig.streamHost,
               asset.url == store.player.attachedURL {
                tried = item
                let before = subtitles.revision
                await subtitles.attach(item, film: nil, listed: SubtitleChoice.house, skin: model.skin)
                // Another load cleared them while this one attached: it owns them now, and an empty
                // list here is not a manifest without tracks, so nothing falls back over it.
                guard subtitles.revision == before + 1 else { return }
                // Stored files in languages the manifest does not carry (a staged Urdu beside the
                // manifest's English and Persian), as video.html offers them.
                if !subtitles.tracks.isEmpty, !Task.isCancelled, store.player.player.currentItem === item {
                    subtitles.addFiles(fileTracks(subtitleSources(air, stored)), first: nil) {
                        let time = store.player.player.currentTime().seconds
                        return time.isFinite ? time : nil
                    }
                }
                // Fall back only when this item is still the one playing. A read that fails on the
                // playing item does fall back, to the same English text.
                if subtitles.tracks.isEmpty, !Task.isCancelled, store.player.player.currentItem === item {
                    await loadFile(air, stored, into: subtitles, store: store)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func fileTracks(_ sources: [(String, String)]) -> [(RecordedSubtitles.Track, String)] {
        sources.map { source, code in
            (RecordedSubtitles.Track(code: code, label: SubtitleChoice.label(code, listed: SubtitleChoice.house, fallback: nil)), source)
        }
    }

    private static func subtitleSources(_ air: OnAir, _ stored: StoredSubtitles) -> [(String, String)] {
        #if DEBUG
        // `-kjsubtitlefile <path>`: a UI test's WebVTT file for whatever is on air.
        if let file = UserDefaults.standard.string(forKey: "kjsubtitlefile") {
            let named = SubtitleChoice.fileLanguage(air.programme?.subtitle_url ?? "")
            return (try? String(contentsOfFile: file, encoding: .utf8)).map { [($0, named)] } ?? []
        }
        #endif
        return stored.tracks.map { ($0.vtt, $0.lang) }
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
    private var step: PiPSubtitleStep
    private var loading: Task<Void, Never>?

    /// `loaded` is the key (`key(_:)`) the screen already loaded for, nil if it had not finished.
    init(_ subtitles: RecordedSubtitles, store: TransmissionStore, model: AppModel, loaded: String?) {
        self.subtitles = subtitles
        self.store = store
        self.model = model
        step = PiPSubtitleStep(loaded: loaded)
    }

    deinit { loading?.cancel() }

    /// The programme on air and the signal it plays on (PiPSubtitleKey).
    static func key(_ store: TransmissionStore) -> String? {
        PiPSubtitleKey.of(programme: ProgrammeSubtitles.key(store.phase), signal: store.player.attachedURL)
    }

    /// The caption on screen now, loading the next programme's first when the channel has moved on.
    /// A stream's tracks, once loaded, go straight to tvOS to draw (the window's); a file's text
    /// is returned for the window to draw into the picture.
    func text() -> String? {
        // A handover in the moment between Full screen and the window closing loads nothing more;
        // the line on screen stays until the window has gone.
        let read = step.read(key: Self.key(store), hasTracks: !subtitles.tracks.isEmpty, handedOff: subtitles.isHandedOff)
        if read.load {
            loading?.cancel()
            let subtitles = subtitles, store = store, model = model
            loading = Task { await ProgrammeSubtitles.load(into: subtitles, store: store, model: model) }
        }
        if read.handOff { subtitles.handOff() }
        return subtitles.text
    }

    /// The window is done: stop loading, and clear what was shown unless a screen is taking the
    /// channel over (Full screen), whose own load replaces it.
    func end(clearing: Bool = true) {
        step.end()
        loading?.cancel()
        loading = nil
        if clearing { subtitles.clear() } else { subtitles.reclaim() }
    }
}
