import Foundation

/// How a Khajistan TV `play_url` becomes something the player can open. Mirrors resolve() in
/// archive/scripts/kj-transmission-auth.js: the server checks the viewer's session before it
/// issues any media, and the app only builds the two requests and validates what comes back.
enum PlayRoute: Equatable, Sendable {
    /// Any other https URL is played as it is.
    case direct(URL)
    /// The tv-play function: GET with the session, answer is {"url":"https://…"}.
    case tvPlay(URL)
    /// A Cloudflare Stream manifest: trade the 32-hex uid for a signed token, then rebuild the
    /// URL on the stream host from that token and `suffix` ("manifest/video.m3u8").
    case stream(uid: String, suffix: String)
}

enum Transmission {
    private static let streamSuffix = "manifest/video.m3u8"

    /// Classifies a play_url. Nil for anything that must not be fetched: not https, credentials in
    /// the URL, unparseable, or a stream-host URL that is not exactly /<32 hex>/manifest/video.m3u8.
    static func route(for playURL: String) -> PlayRoute? {
        // Classified as the project names it, whichever way it was built (direct or the site's
        // proxy); the token request is moved onto the route when it is sent.
        guard let url = URL(string: playURL).map(SupabaseRoute.unrouted),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        let path = parts.percentEncodedPath
        if host == KJConfig.streamHost {
            guard let uid = streamUID(inPath: path) else { return nil }
            return .stream(uid: uid, suffix: streamSuffix)
        }
        if host == SupabaseRoute.host, parts.port == nil || parts.port == 443, path == "/functions/v1/tv-play" {
            return .tvPlay(url)
        }
        return .direct(url)
    }

    /// The request that turns a route into media access. Nil for `.direct`, which needs none.
    /// A GET carrying the viewer's access token, never cached. The site's fetch also refuses
    /// redirects; URLRequest cannot say so, so the caller's session delegate should.
    static func request(for route: PlayRoute, accessToken: String) -> URLRequest? {
        let url: URL
        switch route {
        case .direct:
            return nil
        case .tvPlay(let target):
            url = target
        case .stream(let uid, _):
            var parts = URLComponents(url: KJConfig.supabase.appendingPathComponent("functions/v1/tv-stream-token"),
                                      resolvingAgainstBaseURL: false)
            parts?.percentEncodedQuery = "uid=" + KJURL.encodeQueryValue(uid)
            guard let built = parts?.url else { return nil }
            url = built
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct TokenBody: Decodable { let token: String? }

    /// The playable URL out of the server's answer. `.tvPlay`: {"url"} that must be https with no
    /// credentials. `.stream`: {"token"} of [A-Za-z0-9_.-]+ placed on the stream host. `.direct`
    /// has nothing to resolve and returns its own URL.
    static func carrier(from data: Data, route: PlayRoute) throws -> URL {
        switch route {
        case .direct(let url):
            return url
        case .tvPlay:
            return try ReceiverRules.carrier(from: data)
        case .stream(_, let suffix):
            guard let token = (try? JSONDecoder().decode(TokenBody.self, from: data))?.token,
                  isToken(token),
                  let url = URL(string: "https://\(KJConfig.streamHost)/\(token)/\(suffix)") else {
                throw CarrierError.malformed
            }
            return url
        }
    }

    static func scheduleURL(month: String) -> URL {
        KJConfig.site.appendingPathComponent("data/khajistan-tv/programming-\(month).json")
    }

    /// The preview gate's HTTP Basic header value.
    static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    /// "/<32 lowercase hex>/manifest/video.m3u8" and nothing else, returning the uid.
    private static func streamUID(inPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty,
              parts[2] == "manifest", parts[3] == "video.m3u8", parts[1].utf8.count == 32,
              parts[1].utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }) else { return nil }
        return String(parts[1])
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
                || $0 == 95 || $0 == 46 || $0 == 45
        }
    }
}

// MARK: - The song on air

/// The song on a channel, as the website's receiver shows it (open-frequencies.js
/// watchSongMetadata; owner, 2026-11-04: "shazam so our channels show metadata of songs being
/// played"). A live channel asks the now_playing() RPC, which also marks the channel wanted, so
/// the fingerprinting worker (scripts/signal-room/now_playing_worker.py) listens to it. A
/// Khajistan TV programme is a fixed file, so its songs were heard once and sit in songs.json.
enum NowPlaying {
    static let unavailable = "Current song title unavailable."
    static let pollSeconds = 20
    /// Failed calls in a row before a kept song is dropped (60 s), as on the website.
    static let misses = 3
    /// Seconds not playing before the song is cleared (a stall shorter than this keeps it).
    static let stallTicks = 3

    /// "Artist – Title", or the title alone.
    static func line(artist: String?, title: String) -> String {
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? title : artist + " \u{2013} " + title
    }

    /// What a player prints for a live channel: the song, or for radio the site's
    /// "unavailable" line; television with no song prints nothing.
    static func caption(song: String, mediaType: String) -> String? {
        if !song.isEmpty { return "Now playing: " + song }
        return mediaType == "radio" ? unavailable : nil
    }

    private struct Row: Decodable { let artist: String?; let title: String? }

    /// The RPC's answer as a line: "" when nothing is playing, nil when it could not be read.
    static func parse(_ data: Data) -> String? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        guard let row = rows.first, let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return "" }
        return line(artist: row.artist, title: title)
    }

    /// One call. Nil: the call failed.
    static func fetch(_ channelId: String) async -> String? {
        guard let url = SupabaseRoute.url("/rest/v1/rpc/now_playing"),
              let body = try? JSONSerialization.data(withJSONObject: ["p_channel": channelId]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await SupabaseRoute.data(for: request, session: .shared),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// One poll's effect on what is shown: an answer replaces the song ("" clears it at once);
    /// a failed call keeps it until `misses` failures in a row.
    static func step(kept: String, failures: Int, answer: String?) -> (kept: String, failures: Int) {
        guard let answer else { return (failures + 1 >= misses ? "" : kept, failures + 1) }
        return (answer, 0)
    }

    /// Asks every 20 s for as long as the calling task lives (a view's `.task(id:)`), handing each
    /// change to `update`. While `active` says no (paused, tuning, failed) nothing is asked, so a
    /// paused radio does not keep the worker listening for nobody, and the song is cleared: a
    /// paused channel is playing nothing. It asks at once when the channel plays again.
    static func watch(_ channelId: String, active: @MainActor @escaping () -> Bool = { true },
                      update: @MainActor @escaping (String) -> Void) async {
        var state = (kept: "", failures: 0)
        var wasActive = false
        var idleTicks = 0
        var due = Date.distantPast
        while !Task.isCancelled {
            if await active() {
                idleTicks = 0
                if !wasActive || Date() >= due {
                    state = step(kept: state.kept, failures: state.failures, answer: await fetch(channelId))
                    if Task.isCancelled { return }
                    due = Date().addingTimeInterval(TimeInterval(pollSeconds))
                    let shown = state.kept
                    await update(shown)
                }
                wasActive = true
            } else if wasActive {
                // A buffer stall of a second or two keeps the song and its 20 s cadence; only a
                // pause or a stop that lasts clears it.
                idleTicks += 1
                if idleTicks >= stallTicks {
                    wasActive = false
                    state = ("", 0)
                    if Task.isCancelled { return }
                    await update("")
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// songs.json: [start_s, end_s, artist, title] spans, seconds into a programme's file, keyed by
/// programme id (scripts/khajistan_tv/song_pass.py). Read once an hour, as the site does.
struct SongSpan: Decodable, Equatable, Sendable {
    let start: Double, end: Double, artist: String, title: String
    init(start: Double, end: Double, artist: String, title: String) {
        self.start = start; self.end = end; self.artist = artist; self.title = title
    }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        start = try c.decode(Double.self); end = try c.decode(Double.self)
        // A null artist is no artist; a failed decode would not move past it.
        artist = try c.decodeNil() ? "" : c.decode(String.self)
        title = try c.decode(String.self)
    }
}

/// A span that does not read is dropped alone, never the file round it.
private struct LossySpan: Decodable {
    let span: SongSpan?
    init(from decoder: Decoder) throws { span = try? SongSpan(from: decoder) }
}

/// And a programme whose value is not a list of spans is no songs, not a lost file.
private struct LossySpans: Decodable {
    let spans: [SongSpan]
    init(from decoder: Decoder) throws { spans = ((try? [LossySpan](from: decoder)) ?? []).compactMap(\.span) }
}

actor HouseSongs {
    static let shared = HouseSongs()
    private struct File: Decodable { let songs: [String: LossySpans] }
    private var songs: [String: [SongSpan]] = [:]
    private var loadedAt = Date.distantPast
    private var loading: Task<[String: [SongSpan]]?, Never>?

    static func decode(_ data: Data) -> [String: [SongSpan]]? {
        (try? JSONDecoder().decode(File.self, from: data))?.songs.mapValues(\.spans)
    }

    /// The song playing `seconds` into a programme, or "".
    static func song(in spans: [SongSpan], at seconds: Double) -> String {
        guard let span = spans.first(where: { seconds >= $0.start && seconds < $0.end }) else { return "" }
        return NowPlaying.line(artist: span.artist, title: span.title)
    }

    /// Asked without the preview password first and with it on a 401, as the schedule is
    /// (TransmissionStore.fetchSchedule): the file sits behind the gate until launch.
    func spans(for programmeId: String, previewPassword: String?) async -> [SongSpan] {
        if Date().timeIntervalSince(loadedAt) > 3600 {
            // A second caller while the file is on its way waits for the same read.
            let task = loading ?? Task { await Self.read(previewPassword: previewPassword) }
            loading = task
            let read = await task.value
            loading = nil
            // A failed read keeps the songs already known and is asked again next time.
            if let read { songs = read; loadedAt = Date() }
        }
        return songs[programmeId] ?? []
    }

    private static func read(previewPassword: String?) async -> [String: [SongSpan]]? {
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        guard let url = KJURL.sitePath("/data/khajistan-tv/songs.json?h=\(hour)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        var reply = try? await URLSession.shared.data(for: request)
        if (reply?.1 as? HTTPURLResponse)?.statusCode == 401, let previewPassword {
            request.setValue(Transmission.basicAuthorization(user: KJConfig.previewUser, password: previewPassword),
                             forHTTPHeaderField: "Authorization")
            reply = try? await URLSession.shared.data(for: request)
        }
        guard let (data, response) = reply, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return decode(data)
    }
}
