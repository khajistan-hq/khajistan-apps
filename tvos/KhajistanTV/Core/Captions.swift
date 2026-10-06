import Foundation

// Subtitles and live captions, Foundation only so the core tests reach every rule.
//
// Three paths, one caption view (Views/CaptionView.swift):
// - WebVTT: a Khajistan Transmission programme's `subtitle_url` (video.html, kj-captions.css).
// - The Screening Room's film tracks, read off the HLS manifest's legible group (the player).
// - Live captions on the receiver, ported from archive/scripts/kj-captions-live.js and the
//   request-captions edge function. `CaptionRules` below is that file's rules and words.

// MARK: - WebVTT

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

/// A WebVTT reader for prepared subtitle files. Cue settings (line, align, position) are ignored:
/// the house caption view places every cue (frontend.md §7, kj-captions.css). Tags are dropped and
/// the five entities WebVTT defines are decoded.
enum WebVTT {
    /// The cues, sorted by start, or nil when the text is not a WebVTT file (no signature).
    static func parse(_ source: String) -> [SubtitleCue]? {
        var text = source
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix("WEBVTT") else { return nil }
        let rest = first.dropFirst(6)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }

        // Blocks are separated by blank lines; the first block is the header.
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var cues: [SubtitleCue] = []
        for block in blocks {
            // An identifier may sit on the line above the timing; nothing else may.
            guard let timing = block.prefix(2).firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = block[timing].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = timestamp(parts[0].trimmingCharacters(in: .whitespaces)),
                  let endToken = parts[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
                  let end = timestamp(String(endToken)), end > start else { continue }
            let payload = block[(timing + 1)...].map { plainText($0) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            guard !payload.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: payload))
        }
        return cues.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
    }

    /// `hh:mm:ss.ttt` or `mm:ss.ttt`, in seconds. Minutes and seconds are two digits under 60, the
    /// fraction exactly three digits, as the format requires.
    static func timestamp(_ text: String) -> Double? {
        let halves = text.split(separator: ".", omittingEmptySubsequences: false)
        guard halves.count == 2, halves[1].count == 3, halves[1].allSatisfy({ $0.isASCII && $0.isNumber }), let millis = Int(halves[1]) else { return nil }
        let fields = halves[0].split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2 || fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        let hours = fields.count == 3 ? numbers[0] : 0
        let minutes = numbers[numbers.count - 2], seconds = numbers[numbers.count - 1]
        guard fields[fields.count - 2].count == 2, fields[fields.count - 1].count == 2,
              minutes < 60, seconds < 60, fields.count == 2 || fields[0].count >= 2 else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(millis) / 1000
    }

    /// A cue line without its tags (`<i>`, `<c.x>`, `<v Name>`, timestamps), entities decoded.
    static func plainText(_ line: String) -> String {
        var out = line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", "\u{00A0}"), ("&lrm;", "\u{200E}"), ("&rlm;", "\u{200F}"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    /// What is on screen at `time`: every cue that covers it, in order, one under the other.
    static func text(at time: Double, in cues: [SubtitleCue]) -> String? {
        // ponytail: linear scan, ~1,500 cues at 10 Hz; binary search if a file runs to tens of thousands.
        let on = cues.filter { $0.start <= time && time < $0.end }.map(\.text)
        return on.isEmpty ? nil : on.joined(separator: "\n")
    }
}

// MARK: - The plate and the direction

extension Skin {
    /// The caption plate, from kj-captions.css's `.captions-audio-line > span` per skin: black on
    /// the house yellow by day, yellow on #002800 in grove and on #6E003F in smut.
    var captionPlateHex: UInt32 {
        switch self {
        case .day: return 0xF3FB04
        case .grove: return 0x002800
        case .smut: return 0x6E003F
        }
    }

    var captionTextHex: UInt32 { self == .day ? 0x000000 : 0xF3FB04 }
}

enum CaptionText {
    /// True when the first strong letter is Hebrew, Arabic, Syriac, Thaana or N'Ko, so a line in
    /// Urdu, Persian or Arabic is laid out right to left (its full stop on the left).
    static func isRightToLeft(_ line: String) -> Bool {
        for scalar in line.unicodeScalars where scalar.properties.isAlphabetic {
            let v = scalar.value
            return (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
        }
        return false
    }

    /// The lines of a caption, each laid out on its own direction.
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

// MARK: - Recorded subtitle choice (the receiver's film picker)

/// A film's subtitle languages as vod.json lists them. A LABEL SOURCE only: which tracks exist is
/// read off the manifest (open-frequencies.js filmChannel()).
struct SubtitleLanguage: Decodable, Hashable, Sendable {
    let code: String
    let name: String?
    let native: String?
}

enum SubtitleChoice {
    /// The site's stored choice, "off" or a two-letter code (open-frequencies.js SUBS_KEY).
    static let storeKey = "kj-of-subtitles"

    static func langOf(_ value: String?) -> String { String((value ?? "").prefix(2)).lowercased() }

    /// One entry per language, the first announcement winning (availableSubtitles()).
    static func distinct(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes.map(langOf).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "Urdu · اردو" from the film's record, else the track's own name, else the code (subtitleLabel()).
    static func label(_ code: String, listed: [SubtitleLanguage], fallback: String?) -> String {
        if let entry = listed.first(where: { langOf($0.code) == code }), let name = entry.name, !name.isEmpty {
            return (entry.native ?? "").isEmpty ? name : "\(name) \u{00B7} \(entry.native!)"
        }
        return fallback ?? code.uppercased()
    }

    /// Which language starts on when the viewer has not said (desiredSubtitle()): the remembered
    /// choice, then the device's languages, then English, else none. Nothing else is guessed.
    static func desired(available: [String], stored: String?, preferred: [String]) -> String? {
        if stored == "off" { return nil }
        if let stored, available.contains(stored) { return stored }
        for language in preferred.map(langOf) where available.contains(language) { return language }
        return available.contains("en") ? "en" : nil
    }
}

// MARK: - Live captions: kj-captions-live.js

/// The language of a channel as `channel_language_detected` holds it (pullDetectedLanguage()).
struct DetectedLanguage: Decodable, Equatable, Sendable {
    let lang_code: String?
    let confirmed_lang_code: String?
    let needs_confirmation: Bool?
}

/// data/open-frequencies/caption-accuracy.json: which regions are extensions, and which languages
/// and channels have been measured. Only what the eligibility rule reads.
struct CaptionAccuracy: Decodable, Sendable {
    let extended_regions: [String]?
    let languages: [String: Row]?
    let by_channel: [String: Row]?

    struct Row: Decodable, Sendable {
        let name: String?
    }
}

/// What request-captions answers. Only the fields kj-captions-live.js reads.
struct CaptionReply: Decodable, Equatable, Sendable {
    let allowed: Bool?
    let reason: String?
    let billing_mode: String?
    let session_id: String?
    let lease_expires_at: String?
    let unlimited: Bool?
    let remaining_seconds: Double?
    let reserved_seconds: Double?
    let heartbeat_seconds: Double?
}

/// One row of public.live_caption_wire, as receiveRow() maps it.
struct CaptionWireRow: Decodable, Equatable, Sendable {
    let id: Int?
    let channel_id: String?
    let text: String?
    let english: String?
    let lang: String?
    let script: String?
    let at_epoch: Double?
    let spoken_seconds: Double?
    let final: Bool?
    let uncertain: Bool?
    let program_epoch: Double?
}

enum CaptionRules {
    static let demandURL = KJConfig.supabase.appendingPathComponent("functions/v1/request-captions")
    static let translateURL = KJConfig.supabase.appendingPathComponent("functions/v1/translate-caption")
    static let accuracyPath = "/data/open-frequencies/caption-accuracy.json"
    static let modeKey = "kj-caption-mode"
    static let viewerKey = "kj-viewer-id"

    // The delay line and the page geometry, as the site's constants.
    static let holdStart: Double = 24
    static let holdMargin: Double = 4
    static let holdMax: Double = 60
    static let minOnScreen: Double = 2
    static let maxOnScreen: Double = 7
    static let readingCPS: Double = 20
    static let maxQueueAhead: Double = 30
    static let lineChars = 42
    static let translationWait: Double = 8
    static let firstLineSeconds: Double = 10
    static let waitCold: Double = 75

    /// Media types the live recogniser may listen to: somebody else's transmitter.
    static let liveMedia: Set<String> = ["tv", "radio", "camera"]

    static let supported: Set<String> = ["af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca", "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl", "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn", "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa", "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw", "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"]
    static let parked = ["ps": "The current live recognizer does not support Pashto. Select Persian / Dari only when that is what is being spoken."]
    static let langNames: [String: String] = ["af": "Afrikaans", "sq": "Albanian", "ar": "Arabic", "az": "Azerbaijani", "eu": "Basque", "be": "Belarusian", "bn": "Bengali", "bs": "Bosnian", "bg": "Bulgarian", "ca": "Catalan", "zh": "Chinese", "hr": "Croatian", "cs": "Czech", "da": "Danish", "nl": "Dutch", "en": "English", "et": "Estonian", "fi": "Finnish", "fr": "French", "gl": "Galician", "de": "German", "el": "Greek", "gu": "Gujarati", "he": "Hebrew", "hi": "Hindi", "hu": "Hungarian", "id": "Indonesian", "it": "Italian", "ja": "Japanese", "kn": "Kannada", "kk": "Kazakh", "ko": "Korean", "lv": "Latvian", "lt": "Lithuanian", "mk": "Macedonian", "ms": "Malay", "ml": "Malayalam", "mr": "Marathi", "no": "Norwegian", "fa": "Persian / Dari", "pl": "Polish", "pt": "Portuguese", "pa": "Punjabi", "ro": "Romanian", "ru": "Russian", "sr": "Serbian", "sk": "Slovak", "sl": "Slovenian", "es": "Spanish", "sw": "Swahili", "sv": "Swedish", "tl": "Tagalog", "ta": "Tamil", "te": "Telugu", "th": "Thai", "tr": "Turkish", "uk": "Ukrainian", "ur": "Urdu", "vi": "Vietnamese", "cy": "Welsh", "ps": "Pashto", "hy": "Armenian", "ckb": "Kurdish (Sorani)", "sd": "Sindhi", "skr": "Saraiki", "ks": "Kashmiri", "bal": "Balochi", "hno": "Hindko", "brh": "Brahui", "kab": "Kabyle", "syr": "Syriac", "ku": "Kurdish (Kurmanji)", "pnb": "Punjabi (Shahmukhi)"]
    /// Last resort, one-language countries only (COUNTRY_LANG). A language inference, never filing.
    static let countryLang: [String: String] = [
        "T\u{00FC}rkiye": "tr", "Turkey": "tr", "Iran": "fa", "Pakistan": "ur",
        "Saudi Arabia": "ar", "Qatar": "ar", "United Arab Emirates": "ar", "Oman": "ar",
        "Jordan": "ar", "Iraq": "ar", "Lebanon": "ar", "Palestine": "ar", "Egypt": "ar",
        "Yemen": "ar", "Bahrain": "ar", "Libya": "ar", "Tunisia": "ar", "Syria": "ar",
        "Sudan": "ar", "Kuwait": "ar", "Algeria": "ar", "Morocco": "ar", "Mauritania": "ar"
    ]
    private static let aliases: [String: String] = ["farsi": "fa", "dari": "fa", "فارسی": "fa", "bangla": "bn", "বাংলা": "bn", "español": "es", "castellano": "es", "bahasa indonesia": "id", "bahasa melayu": "ms", "kiswahili": "sw", "azeri": "az", "filipino": "tl", "mandarin": "zh", "pushto": "ps", "sorani": "ckb", "kurdish": "ckb", "русский": "ru", "العربية": "ar", "اردو": "ur", "עברית": "he", "türkçe": "tr"]

    /// langCodeFromName(): a code, an alias, or a name that begins with a known language.
    static func langCode(fromName name: String?) -> String? {
        guard let name else { return nil }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.isEmpty { return nil }
        if supported.contains(n) || langNames[n] != nil { return n }
        if let alias = aliases[n] { return alias }
        for code in langNames.keys.sorted() {
            let label = (langNames[code] ?? "").lowercased().components(separatedBy: " / ")[0]
            if n == label || n.hasPrefix(label + " ") || n.hasPrefix(label + ",") || n.hasPrefix(label + "/") { return code }
        }
        return nil
    }

    /// effectiveLangCode(): a viewer-confirmed language, the registry's code, the machine's, the
    /// detected name, the stated language, and last the one-language country.
    static func effectiveLangCode(_ ch: Channel, detected: DetectedLanguage?) -> String? {
        if let confirmed = detected?.confirmed_lang_code, !confirmed.isEmpty { return confirmed }
        if let code = ch.languageCode, !code.isEmpty { return code }
        if let code = detected?.lang_code, !code.isEmpty { return code }
        if let code = langCode(fromName: ch.detectedLanguageName) { return code }
        if let code = langCode(fromName: ch.primaryLanguage) { return code }
        return countryLang[(ch.country ?? "").trimmingCharacters(in: .whitespaces)]
    }

    /// Every region the channel sits in is an extension of the atlas. Unknown reads as core.
    static func isExtension(_ ch: Channel, accuracy: CaptionAccuracy?) -> Bool {
        guard let ext = accuracy?.extended_regions, !ext.isEmpty, let ids = ch.regionIds, !ids.isEmpty else { return false }
        return ids.allSatisfy(ext.contains)
    }

    static func measured(_ ch: Channel, code: String?, accuracy: CaptionAccuracy?) -> Bool {
        guard let accuracy else { return false }
        if accuracy.by_channel?[ch.id] != nil { return true }
        let dari = (ch.primaryLanguage ?? "").range(of: "dari", options: .caseInsensitive) != nil
        if code == "fa", dari, accuracy.languages?["prs"] != nil { return true }
        return code.map { accuracy.languages?[$0] != nil } ?? false
    }

    /// eligible(): a live carrier with a stream, in a language the recogniser takes or none known
    /// (Auto). The source-language picker is not carried on the television, so its override is not.
    static func eligible(_ ch: Channel, detected: DetectedLanguage?, accuracy: CaptionAccuracy?) -> Bool {
        guard ch.activeStreamId != nil, liveMedia.contains(ch.mediaType) else { return false }
        guard let code = effectiveLangCode(ch, detected: detected) else { return true }
        if parked[code] != nil || !supported.contains(code) { return false }
        if isExtension(ch, accuracy: accuracy) && !measured(ch, code: code, accuracy: accuracy) { return false }
        return true
    }

    /// parkedReason(): the one line a channel without a Captions control gets, or "" for none.
    static func parkedReason(_ ch: Channel, detected: DetectedLanguage?, accuracy: CaptionAccuracy?) -> String {
        guard ch.activeStreamId != nil, let code = effectiveLangCode(ch, detected: detected) else { return "" }
        if let reason = parked[code] { return reason }
        let name = langNames[code] ?? code
        if !supported.contains(code) { return "No captions: \(name) is not on the live recogniser." }
        if isExtension(ch, accuracy: accuracy) && !measured(ch, code: code, accuracy: accuracy) {
            return "No captions here yet: \(name) has not been measured on this atlas."
        }
        return ""
    }

    // MARK: Words the site says

    /// billingReason(), for the reasons that are not a residency terminal's (the app is never one).
    static func billingReason(_ reason: String?) -> String? {
        switch reason {
        // The site says "from the top of the page"; the app has no page, and sign-in is under Account.
        case "sign_in_required": return "Sign in under Account to use live captions."
        case "email_unverified": return "Verify your email address to use your caption allowance."
        case "credits_exhausted": return "Your free caption minutes are used up. The channel keeps playing."
        case "not_live": return "Live captions are for live television and radio. This channel carries its own subtitles."
        case "session_conflict": return "Captions are already running in another session. Turn them off there before starting here."
        case "global_cap": return "Live captioning has reached its spending limit for now. The channel keeps playing."
        case "trial_budget_exhausted": return "Free caption trials are unavailable right now. The channel keeps playing."
        default: return nil
        }
    }

    /// What a refused start says (setMode()'s start branch).
    static func startRefusal(_ reason: String?) -> String {
        if let line = billingReason(reason) { return line }
        switch reason {
        case "at_capacity":
            return "As many channels as we can caption at once are already being captioned. Try again in a few minutes \u{2014} nothing was counted against your minutes."
        case "daily_cap_reached", "monthly_cap_reached":
            return "Live captioning has reached its spending limit for now. Nothing was counted against your minutes."
        case "captions_disabled": return "Live captioning is switched off at the source right now."
        case "passphrase_required", "passphrase_incorrect":
            return "Live captions are owner-only and the passphrase was not accepted. Nothing was counted against your minutes."
        case "owner_pass_not_configured", "settings_unavailable": return "Live captioning is not configured at the source right now."
        default: return "Captions could not be started for this channel just now. Nothing was counted against your minutes."
        }
    }

    /// What a refused heartbeat says (startHeartbeat()).
    static func heartbeatRefusal(_ reason: String?) -> String {
        if let line = billingReason(reason) { return line }
        switch reason {
        case "daily_cap_reached", "monthly_cap_reached": return "Live captioning has reached its spending limit for now. The channel keeps playing."
        case "captions_disabled": return "Live captioning is switched off at the source right now."
        case "passphrase_required", "passphrase_incorrect": return "Caption access has expired. Turn captions on to enter the owner passphrase again."
        default: return "Live captions are unavailable right now. The channel keeps playing."
        }
    }

    static let renewFailed = "Caption access could not be renewed. Turn captions on to reconnect."
    static let leaseExpired = "Caption access expired. Turn captions on to reconnect."
    static let uncertainLine = "Some speech could not be transcribed reliably."
    static let untranslatedLine = "English translation is temporarily unavailable for this line."
    static let waitingLine = "Captions start when someone speaks."

    /// The control's label: idleLabel() off, modeLabel("english") on, with what is left when the
    /// account is metered. `balance` nil is not known yet, infinity is uncapped.
    static func label(on: Bool, balance: Double?, reserved: Double = 0) -> String {
        let base = on ? "Captions \u{00B7} English" : "Captions"
        guard let balance, balance.isFinite else { return base }
        let left = on ? (balance + max(0, reserved)) : balance
        return base + " \u{00B7} \(Int((left / 60).rounded(.up))) min left"
    }

    /// The remaining seconds a reply carries: infinity for an uncapped account (null remaining).
    static func balance(of reply: CaptionReply) -> Double {
        if reply.unlimited == true || reply.remaining_seconds == nil { return .infinity }
        return max(0, reply.remaining_seconds ?? 0)
    }

    /// acceptBilling()'s check on an allowed enforced reply: our session, a lease still ahead.
    static func leaseExpiry(of reply: CaptionReply, session: String, now: Date) -> Date? {
        guard reply.session_id == session, let text = reply.lease_expires_at, let date = isoDate(text), date > now else { return nil }
        return date
    }

    static func isoDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: Requests

    /// askForCaptions(): the demand request, the same body the receiver sends. The site's owner
    /// passphrase field is sent empty; the live mode is "public" and the television prompts for none.
    static func demandRequest(action: String, channelId: String, viewerId: String, sessionId: String?, accessToken: String) -> URLRequest {
        var body: [String: Any] = [
            "channel_id": channelId, "viewer_id": viewerId, "mode": "english", "action": action,
            "session_id": sessionId.map { $0 as Any } ?? NSNull()
        ]
        if action != "stop" {
            body["src_lang"] = NSNull()
            body["pass"] = ""
        }
        return post(demandURL, body: body, token: accessToken)
    }

    /// requestTranslation(): English for one wire row that arrived without it.
    static func translateRequest(row: CaptionWireRow, channelLang: String?, sessionId: String?, accessToken: String) -> URLRequest {
        let body: [String: Any] = [
            "session_id": sessionId.map { $0 as Any } ?? NSNull(), "pass": "",
            "text": (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "source_lang": row.lang ?? channelLang ?? "auto", "target": "en",
            "wire_id": row.id.map { $0 as Any } ?? NSNull(), "channel_id": row.channel_id.map { $0 as Any } ?? NSNull()
        ]
        return post(translateURL, body: body, token: accessToken)
    }

    /// recoverWire(): the last thirty seconds of the channel's wire, newest first, fifty rows.
    static func wireRequest(channelId: String, now: Date, accessToken: String) -> URLRequest {
        let since = ISO8601DateFormatter().string(from: now.addingTimeInterval(-30))
        let columns = "id,channel_id,text,english,lang,script,at_epoch,spoken_seconds,final,sn,sn_offset,seg_dur,confidence,uncertain,program_epoch"
        let query = "select=\(columns)&channel_id=eq.\(KJURL.encodeQueryValue(channelId))&created_at=gte.\(KJURL.encodeQueryValue(since))&order=id.desc&limit=50"
        var request = URLRequest(url: URL(string: KJConfig.supabase.absoluteString + "/rest/v1/live_caption_wire?" + query)!)
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// pullDetectedLanguage(): the machine verdict for a channel, read with the anon key.
    static func detectedRequest(channelId: String) -> URLRequest {
        let query = "select=lang_code,lang_name,confidence,needs_confirmation,confirmed_lang_code&channel_id=eq.\(KJURL.encodeQueryValue(channelId))"
        var request = URLRequest(url: URL(string: KJConfig.supabase.absoluteString + "/rest/v1/channel_language_detected?" + query)!)
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func post(_ url: URL, body: [String: Any], token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.timeoutInterval = 8
        return request
    }

    // MARK: English

    /// isEnglishSource(): said in English and written only in Latin letters.
    static func isEnglishSource(_ row: CaptionWireRow) -> Bool {
        let source = row.text ?? ""
        return row.lang == "en" && (row.script == nil || row.script == "Latn") && !hasNonLatinLetter(source)
    }

    /// checkedEnglish(): provider output that is untranslated script, a code fence or JSON, or
    /// the model talking about the task is rejected whole.
    static func checkedEnglish(_ value: String?, row: CaptionWireRow) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if isEnglishSource(row), text == (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) { return text }
        if hasNonLatinLetter(text) { return "" }
        let probe = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if matches(#"^(?:\{|\[\s*[{"])|```|</?(?:think|analysis|reasoning|tool_call)\b"#, text) { return "" }
        let commentary = [
            #"(?:as an ai(?: language model)?|\b(?:system|developer) prompt\b|\b(?:analysis|reasoning|translator(?:'s)? note|translation note)\s*:)"#,
            #"(?:(?:could|can|would) you|please)\s+(?:provide|share|send|give)[^.\n]{0,160}(?:translat(?:e|ed|ion)|complete (?:sentence|phrase))"#,
            #"\bi(?:['’]m| am)?\s+(?:(?:am )?(?:not able|unable) to|cannot|can['’]t)\s+(?:provide (?:a )?(?:meaningful |accurate |reliable )?translation|translate (?:this|the (?:provided|given|source)) (?:input|text|fragment))"#,
            #"(?:\b(?:input|provided text|text provided|text you.{0,12}provided|source text)\b.{0,100}\b(?:unclear|incomplete|fragment|untranslatable|noise|gibberish|nonsensical|meaningful translation)\b|\bappears to be (?:incomplete|unclear)|\bcontains (?:Hindi|Urdu|Arabic|Persian)(?:/(?:Hindi|Urdu|Arabic|Persian))? script\b|\bsentence or phrase you.{0,12}like translated\b)"#
        ]
        return commentary.contains { matches($0, probe) } ? "" : text
    }

    /// What an English-only receiver paints for a row: its checked English, or the line itself
    /// when it was spoken in English. Nil means there is nothing to show yet.
    static func english(for row: CaptionWireRow) -> String? {
        let checked = checkedEnglish(row.english, row: row)
        if !checked.isEmpty { return checked }
        if isEnglishSource(row) {
            let native = (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return native.isEmpty ? nil : native
        }
        return nil
    }

    /// A row worth taking at all: final, of this channel, carrying a letter or a digit.
    static func admits(_ row: CaptionWireRow, channelId: String) -> Bool {
        if let other = row.channel_id, other != channelId { return false }
        if row.final == false { return false }
        let probe = (row.text ?? "").isEmpty ? (row.english ?? "") : (row.text ?? "")
        return probe.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    private static func hasNonLatinLetter(_ text: String) -> Bool {
        matches(#"(?=\p{L})\P{Script=Latin}"#, text)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Blocks and timing

    /// blocks(): up to two lines of up to 42 characters, the pair balanced at the best word break.
    /// ponytail: the site's last-page rebalance (a short tail joined to the page before) is left out;
    /// it only shortens reading time on a sentence that ends in a tiny third line.
    static func blocks(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        for raw in text.split(whereSeparator: \.isWhitespace) {
            var word = String(raw)
            while word.count > lineChars {
                if !current.isEmpty { lines.append(current); current = "" }
                lines.append(String(word.prefix(lineChars)))
                word = String(word.dropFirst(lineChars))
            }
            if word.isEmpty { continue }
            let joined = current.isEmpty ? word : current + " " + word
            if joined.count > lineChars { lines.append(current); current = word } else { current = joined }
        }
        if !current.isEmpty { lines.append(current) }
        var out: [String] = []
        var index = 0
        while index < lines.count {
            let pair = Array(lines[index..<min(index + 2, lines.count)])
            index += 2
            guard pair.count == 2 else { out.append(pair[0]); continue }
            let words = (pair[0] + " " + pair[1]).components(separatedBy: " ")
            var best: String?
            var bestDiff = Int.max
            for k in 1..<words.count {
                let a = words[..<k].joined(separator: " "), b = words[k...].joined(separator: " ")
                if a.count > lineChars || b.count > lineChars { continue }
                let diff = abs(a.count - b.count)
                if diff < bestDiff { bestDiff = diff; best = a + "\n" + b }
            }
            out.append(best ?? pair.joined(separator: "\n"))
        }
        return out
    }

    /// paintBlocks(): each block on screen for its share of the spoken time, never under two
    /// seconds or its reading time at twenty characters a second, never over seven.
    static func timed(_ text: String, at start: Double, spokenSeconds: Double?) -> [SubtitleCue] {
        let list = blocks(text)
        let characters = list.reduce(0) { $0 + $1.replacingOccurrences(of: "\n", with: "").count }
        let spoken = max(0, spokenSeconds ?? 3.5)
        var cursor = start
        return list.map { block in
            let length = Double(block.replacingOccurrences(of: "\n", with: "").count)
            let share = characters > 0 ? spoken * length / Double(characters) : 0
            let duration = min(maxOnScreen, max(minOnScreen, length / readingCPS, share))
            defer { cursor += duration }
            return SubtitleCue(start: cursor, end: cursor + duration, text: block)
        }
    }

    /// placeByClock(): where on the media clock a row's speech lands, given how far behind the live
    /// edge the picture is. Nil for a row whose clock is too far off to trust.
    static func mediaTime(atEpoch: Double, now: Double, mediaNow: Double, behindLive: Double) -> Double? {
        let lag = now - atEpoch
        if lag > 180 || lag < -30 { return nil }
        return mediaNow + max(0, atEpoch + behindLive - now)
    }

    /// The hold the picture wants: the site's resync() target, the 90th percentile of the measured
    /// lag plus a margin, at least 24 s, at most what the live window allows.
    static func holdTarget(lags: [Double], ceiling: Double) -> Double {
        let sorted = lags.sorted()
        let p90 = sorted.isEmpty ? holdStart - holdMargin : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        return min(ceiling, max(holdStart, (p90 + holdMargin).rounded(.up)))
    }
}

// MARK: - Supabase Realtime (the receiver's postgres_changes subscription)

enum CaptionRealtime {
    static func socketURL() -> URL {
        var parts = URLComponents(url: KJConfig.supabase, resolvingAgainstBaseURL: false)!
        parts.scheme = "wss"
        parts.path = "/realtime/v1/websocket"
        parts.queryItems = [URLQueryItem(name: "apikey", value: KJConfig.anonKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return parts.url!
    }

    static func topic(_ channelId: String) -> String { "realtime:captions:\(channelId)" }

    /// sb.channel("captions:<id>").on("postgres_changes", INSERT on live_caption_wire for the channel).
    static func join(channelId: String, accessToken: String, ref: String) -> String {
        let message: [String: Any] = [
            "topic": topic(channelId), "event": "phx_join", "ref": ref, "join_ref": ref,
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false], "presence": ["key": ""], "private": false,
                    "postgres_changes": [["event": "INSERT", "schema": "public", "table": "live_caption_wire", "filter": "channel_id=eq.\(channelId)"]]
                ] as [String: Any],
                "access_token": accessToken
            ] as [String: Any]
        ]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }

    static func heartbeat(ref: String) -> String {
        #"{"event":"heartbeat","payload":{},"ref":"\#(ref)","topic":"phoenix"}"#
    }

    enum Event: Equatable {
        case subscribed
        case row(CaptionWireRow)
        case closed
        case other
    }

    /// What one frame from the socket says about the caption topic.
    static func event(_ text: String, channelId: String) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["topic"] as? String == topic(channelId) else { return .other }
        let payload = object["payload"] as? [String: Any]
        switch object["event"] as? String {
        case "phx_reply":
            return payload?["status"] as? String == "ok" ? .subscribed : .closed
        case "phx_error", "phx_close":
            return .closed
        case "postgres_changes":
            guard let data = payload?["data"] as? [String: Any], data["type"] as? String == "INSERT",
                  let record = data["record"],
                  let bytes = try? JSONSerialization.data(withJSONObject: record),
                  let row = try? JSONDecoder().decode(CaptionWireRow.self, from: bytes) else { return .other }
            return .row(row)
        default:
            return .other
        }
    }
}
