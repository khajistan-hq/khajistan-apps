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

    @ObservationIgnored private var cues: [SubtitleCue] = []
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
        if let output, let item { item.remove(output) }
        output = nil
        text = nil
        return true
    }

    /// True once the track is drawn by AVPlayer rather than this object (`handOff()`).
    var isHandedOff: Bool { group != nil && output == nil }

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
        cues = []
        tracks = []
        current = nil
        text = nil
        choiceKey = nil
    }

    /// True while the tracks shown are this item's.
    func follows(_ other: AVPlayerItem) -> Bool { item === other }

    /// The next language, then off, then the first again.
    func cycle() {
        let codes = tracks.map(\.code)
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
        clear()
        guard let parsed = WebVTT.parse(source), !parsed.isEmpty else { return }
        cues = parsed
        tracks = [language]
        current = language.code
        let gen = generation
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, gen == self.generation else { return }
                let showing = self.current == nil ? nil : clock().flatMap { WebVTT.text(at: $0, in: self.cues) }
                if self.text != showing { self.text = showing }
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
        // draws it (handOff()), and these rules give it the skin's caption plate there, bold and
        // half again as large, since the window shows it at a third of the size (Apple TV HD,
        // 2026-11-17: yellow on the Grove plate in the window).
        item.textStyleRules = [AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: Skin.argb(skin.captionTextHex),
            kCMTextMarkupAttribute_BackgroundColorARGB as String: Skin.argb(skin.captionPlateHex),
            kCMTextMarkupAttribute_BoldStyle as String: true,
            kCMTextMarkupAttribute_RelativeFontSize as String: 150,
        ])].compactMap { $0 }
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
