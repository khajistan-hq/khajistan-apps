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

    /// "Subtitles · English", "Subtitles · Off": the receiver's recorded-subtitle picker, as one control.
    var label: String {
        let on = tracks.first { $0.code == current }?.label ?? "Off"
        return "Subtitles \u{00B7} \(on)"
    }

    func clear() {
        generation += 1
        ticker?.cancel()
        ticker = nil
        if let output, let item { item.remove(output) }
        output = nil
        group = nil
        options = [:]
        cues = []
        tracks = []
        current = nil
        text = nil
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

    /// Lists the legible options of `item`, one per language, labelled from the film's record, and
    /// switches on the remembered or device language, else English, else none (desiredSubtitle()).
    func attach(_ item: AVPlayerItem, listed: [SubtitleLanguage]) async {
        clear()
        let gen = generation
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
        let stored = UserDefaults.standard.string(forKey: SubtitleChoice.storeKey)
        apply(SubtitleChoice.desired(available: order.map(\.code), stored: stored, preferred: Locale.preferredLanguages))
    }

    /// The viewer's choice, remembered as the site remembers it ("off" or the code).
    private func select(_ code: String?) {
        if group != nil { UserDefaults.standard.set(code ?? "off", forKey: SubtitleChoice.storeKey) }
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
