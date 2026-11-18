import AVFoundation
import Foundation
import Observation

/// Prepared subtitles, drawn by the house caption view rather than by AVPlayer.
///
/// Two sources, as on the site:
/// - A Khajistan Transmission programme's `subtitle_url`, a WebVTT file timed to the programme's
///   own file, so cues are read against the player's clock. On by default per programme, toggled
///   with the control (video.html).
/// - A Screening Room film's tracks, which are read off the HLS manifest's legible group and never
///   off the record (open-frequencies.js availableSubtitles()). AVPlayer still selects and times
///   the track; its own rendering is suppressed and its text comes here.
@MainActor @Observable
final class RecordedSubtitles {
    struct Track: Hashable {
        let code: String
        let label: String
    }

    /// What is on screen now.
    private(set) var text: String?
    /// The languages this programme or film carries. Empty means no control.
    private(set) var tracks: [Track] = []
    /// The language on, nil for off.
    private(set) var current: String?

    @ObservationIgnored private var fileCues: [String: [SubtitleCue]] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var group: AVMediaSelectionGroup?
    @ObservationIgnored private var options: [String: AVMediaSelectionOption] = [:]
    @ObservationIgnored private weak var item: AVPlayerItem?
    @ObservationIgnored private var output: AVPlayerItemLegibleOutput?
    @ObservationIgnored private let relay = LegibleRelay()
    @ObservationIgnored private var generation = 0
    /// Where the choice is remembered while manifest tracks are attached: the film's own key, or
    /// the shared one on Transmission.
    @ObservationIgnored private var choiceKey: String?

    /// "Subtitles · English", "Subtitles · Off": the receiver's recorded-subtitle picker, as one control.
    var label: String {
        let on = tracks.first { $0.code == current }?.label ?? "Off"
        return "Subtitles \u{00B7} \(on)"
    }

    /// The track AVPlayer can draw itself, handed to it for the picture-in-picture window, where
    /// the house view does not reach: the suppressing output comes off and the track stays
    /// selected, so tvOS draws it, in the skin's colours (`attach`'s text style rules). The
    /// languages stay, so the PiP bar can still move to the next one. A programme's prepared file
    /// is not a track and stays here: the window's compositor draws it (HouseCaptionCompositor).
    /// True when a track was handed over.
    @discardableResult
    func handOff() -> Bool {
        guard group != nil else { return false }
        // A stored file in a language the manifest lacks (a staged Urdu beside a Stream
        // programme's English) is not a track AVPlayer holds and the window cannot draw it on a
        // stream: the window takes the manifest language the viewer would get, without
        // remembering it, so the corner shows subtitles rather than none.
        if let current, fileCues[current] != nil {
            let stored = choiceKey.flatMap { UserDefaults.standard.string(forKey: $0) }
            apply(SubtitleChoice.desired(available: manifestCodes, stored: stored, preferred: Locale.preferredLanguages))
        }
        if let output, let item { item.remove(output) }
        output = nil
        text = nil
        // tvOS draws only the manifest's tracks: a stored file's language on (a staged Urdu beside
        // the manifest's English) would leave the window bare under "Subtitles · Urdu". The window
        // takes the manifest language the viewer would get; the screen they return to loads afresh.
        let choice = SubtitleChoice.windowChoice(
            current: current, manifest: Self.windowCodes(tracks.map(\.code), manifest: Set(options.keys), handedOff: true),
            stored: choiceKey.flatMap { UserDefaults.standard.string(forKey: $0) }, preferred: Locale.preferredLanguages)
        if choice != current { apply(choice) }
        return true
    }

    /// The languages the control steps through: once handed off, only the manifest's, since tvOS
    /// has no track of a stored file to draw in the window.
    static func windowCodes(_ codes: [String], manifest: Set<String>, handedOff: Bool) -> [String] {
        handedOff ? codes.filter(manifest.contains) : codes
    }

    /// The window has closed and a screen takes the channel back: the suppressing output goes on
    /// again, so tvOS stops drawing the track before the screen's own load replaces it.
    func reclaim() {
        guard isHandedOff, let item else { return }
        let legible = AVPlayerItemLegibleOutput()
        legible.suppressesPlayerRendering = true
        legible.setDelegate(relay, queue: .main)
        item.add(legible)
        output = legible
    }

    /// The manifest's languages, in order: what AVPlayer can draw itself.
    private var manifestCodes: [String] { tracks.map(\.code).filter { options[$0] != nil } }

    /// True once the track is drawn by AVPlayer rather than this object (`handOff()`).
    var isHandedOff: Bool { group != nil && output == nil }

    /// True while a programme's prepared file is loaded: text the PiP window must draw into the
    /// picture itself (HouseCaptionCompositor), as tvOS has no track of it.
    var hasFile: Bool { !fileCues.isEmpty }

    /// The skin's caption colours for the text tvOS draws itself: bold and half again as large,
    /// since the window shows it at a third of the size (Apple TV HD, 2026-11-17: yellow on the
    /// Grove plate in the window). Set again by the window when the skin turns.
    /// The viewer's "Text only" choice (CaptionStyle) draws yellow text with a black edge and no plate.
    static func styleRules(_ skin: Skin, style: CaptionStyle = .current) -> [AVTextStyleRule] {
        let bare = style == .bare
        return [AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: Skin.argb(bare ? Skin.bareCaptionHex : skin.captionTextHex),
            kCMTextMarkupAttribute_BackgroundColorARGB as String: bare ? [0, 0, 0, 0] : Skin.argb(skin.captionPlateHex),
            kCMTextMarkupAttribute_CharacterEdgeStyle as String: bare ? kCMTextMarkupCharacterEdgeStyle_Uniform as String
                                                                      : kCMTextMarkupCharacterEdgeStyle_None as String,
            kCMTextMarkupAttribute_BoldStyle as String: true,
            kCMTextMarkupAttribute_RelativeFontSize as String: 150,
        ])].compactMap { $0 }
    }

    func clear() {
        generation += 1
        ticker?.cancel()
        ticker = nil
        // Deselect too: with its suppressing output gone, a selected track would be drawn by the
        // system itself, in its own style, in the picture-in-picture window.
        if let group, let item { item.select(nil, in: group) }
        if let output, let item { item.remove(output) }
        output = nil
        group = nil
        options = [:]
        fileCues = [:]
        tracks = []
        current = nil
        text = nil
        choiceKey = nil
    }

    /// Moves on every clear: a load that sees it moved by more than its own clear was taken over
    /// by another load (the screen's and the window's, overlapping as the screen closes).
    var revision: Int { generation }

    /// True while the tracks shown are this item's.
    func follows(_ other: AVPlayerItem) -> Bool { item === other }

    /// The next language, then off, then the first again.
    func cycle() {
        // Handed to AVPlayer (the PiP window over a stream), only what it can draw is offered.
        let codes = isHandedOff ? manifestCodes : tracks.map(\.code)
        guard !codes.isEmpty else { return }
        let next: String?
        if let current, let index = codes.firstIndex(of: current) {
            next = index + 1 < codes.count ? codes[index + 1] : nil
        } else {
            next = codes[0]
        }
        select(next)
    }

    // MARK: - A programme's WebVTT file

    /// Reads the file and follows `clock` (seconds into the programme's file). A file that does not
    /// parse offers nothing: there is no control for subtitles that cannot be shown.
    func load(vtt source: String, language: Track, clock: @escaping @MainActor () -> Double?) {
        load(files: [(language, source)], first: language.code, clock: clock)
    }

    /// Several files for one programme (English, and Urdu, Persian or Arabic where made), one per
    /// language, on in `first` when it is among them, else the first that parses. The control steps
    /// through them and off, as with a film's tracks; a file's choice is not remembered (video.html).
    func load(files: [(Track, String)], first: String?, clock: @escaping @MainActor () -> Double?) {
        clear()
        addFiles(files, first: first, clock: clock)
    }

    /// Stored files beside what is already offered. After `attach`, a file in a language the
    /// manifest carries is skipped (a Stream programme's English file is its manifest's English),
    /// and the opener is chosen again over the union by the manifest's rule (desiredSubtitle()).
    /// Alone, files are on by default in `first`.
    func addFiles(_ files: [(Track, String)], first: String?, clock: @escaping @MainActor () -> Double?) {
        var added = false
        for (track, source) in files where fileCues[track.code] == nil && options[track.code] == nil {
            guard let parsed = WebVTT.parse(source), !parsed.isEmpty else { continue }
            fileCues[track.code] = parsed
            tracks.append(track)
            added = true
        }
        guard added else { return }
        if group == nil {
            current = tracks.contains { $0.code == first } ? first : tracks.first?.code
        } else {
            let stored = UserDefaults.standard.string(forKey: SubtitleChoice.storeKey)
            let want = SubtitleChoice.desired(available: tracks.map(\.code), stored: stored, preferred: Locale.preferredLanguages)
            // Only when the union changes the opener: re-applying the same option blanks a line.
            if want != current { apply(want) }
        }
        guard ticker == nil else { return }
        let gen = generation
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, gen == self.generation else { return }
                // A file is on: its cues. A manifest track is on: the legible output writes the text.
                if let code = self.current, let cues = self.fileCues[code] {
                    let showing = clock().flatMap { WebVTT.text(at: $0, in: cues) }
                    if self.text != showing { self.text = showing }
                } else if self.current == nil, self.text != nil {
                    self.text = nil
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - A film's manifest tracks

    /// Lists the legible options of `item`, one per language, labelled from `listed`, and
    /// switches on the language remembered for this film (or, with no film, the one Transmission
    /// choice), or the device's, else English, else none (desiredSubtitle()).
    func attach(_ item: AVPlayerItem, film handle: String?, listed: [SubtitleLanguage], skin: Skin) async {
        clear()
        let gen = generation
        // The house view draws the text full screen. In the picture-in-picture window AVPlayer
        // draws it (handOff()), and these rules give it the skin's caption plate there.
        item.textStyleRules = Self.styleRules(skin)
        guard let found = try? await item.asset.loadMediaSelectionGroup(for: .legible), gen == generation else { return }
        var byCode: [String: AVMediaSelectionOption] = [:]
        var order: [Track] = []
        for option in found.options {
            let code = SubtitleChoice.langOf(option.extendedLanguageTag ?? option.locale?.identifier)
            guard !code.isEmpty, byCode[code] == nil else { continue }
            byCode[code] = option
            order.append(Track(code: code, label: SubtitleChoice.label(code, listed: listed, fallback: option.displayName)))
        }
        guard !order.isEmpty else { return }
        self.item = item
        group = found
        options = byCode
        tracks = order
        let legible = AVPlayerItemLegibleOutput()
        legible.suppressesPlayerRendering = true
        relay.onText = { [weak self] text in
            guard let self, gen == self.generation else { return }
            if let code = self.current, self.fileCues[code] != nil { return }   // a stored file is on
            self.text = self.current == nil ? nil : text
        }
        legible.setDelegate(relay, queue: .main)
        item.add(legible)
        output = legible
        let key = handle.map(SubtitleChoice.filmKey) ?? SubtitleChoice.storeKey
        choiceKey = key
        let stored = UserDefaults.standard.string(forKey: key)
        apply(SubtitleChoice.desired(available: order.map(\.code), stored: stored, preferred: Locale.preferredLanguages))
    }

    /// The viewer's choice, remembered under `choiceKey` ("off" or the code).
    private func select(_ code: String?) {
        if group != nil, let choiceKey { UserDefaults.standard.set(code ?? "off", forKey: choiceKey) }
        apply(code)
    }

    private func apply(_ code: String?) {
        current = code
        text = nil
        if let group, let item { item.select(code.flatMap { options[$0] }, in: group) }
    }
}

/// AVPlayerItemLegibleOutput's delegate, delivered on the main queue.
private final class LegibleRelay: NSObject, AVPlayerItemLegibleOutputPushDelegate {
    var onText: (@MainActor (String?) -> Void)?

    func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime) {
        let joined = strings.map(\.string).filter { !$0.isEmpty }.joined(separator: "\n")
        let text = joined.isEmpty ? nil : joined
        MainActor.assumeIsolated { onText?(text) }
    }
}
