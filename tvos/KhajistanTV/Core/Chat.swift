import Foundation

// Live chat, against the website's own rooms (archive/chat.html, scripts/kj-chat.js;
// supabase/migrations/20260907_chat_rooms.sql). Foundation only: the Apple TV and the phone both
// link this file and draw their own screens. The database decides who may read and post; this
// file asks, and says what it answered in the site's words.

/// A room, as `chat_rooms` holds it.
struct ChatRoom: Decodable, Identifiable, Hashable, Sendable {
    let slug: String
    let label: String
    let kind: String
    let region: String?
    let country: String?
    let category: String?
    let adult: Bool?
    let description: String?
    let status: String
    let slow_mode_seconds: Int?
    var id: String { slug }
}

/// A line in a room, as `chat_messages` holds it.
struct ChatMessage: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let room_slug: String
    let author_id: String?
    let author_handle: String?
    let body: String
    let kind: String
    let created_at: String
    let hidden_at: String?
    let removed_at: String?
    let expires_at: String?

    /// "a closed account" when the author has gone, as the site prints it (kj-chat.js :446).
    var who: String { author_handle ?? "a closed account" }

    /// Shown unless the desk has hidden or removed it, or its room's clock has cleared it.
    func isVisible(now: Date = Date()) -> Bool {
        guard hidden_at == nil, removed_at == nil else { return false }
        if let expires_at, let at = ChatClock.date(expires_at), at <= now { return false }
        return true
    }
}

/// A moderation change to a line already on screen (`chat_message_state`).
struct ChatLineState: Decodable, Sendable {
    let message_id: Int64
    let state: String
    let at: String
}

enum ChatClock {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ text: String) -> Date? { withFraction.date(from: text) ?? plain.date(from: text) }
    static func text(_ date: Date) -> String { withFraction.string(from: date) }
}

// MARK: - The site's rules and words

enum ChatRules {
    /// The atlas regions in the site's order (data/chat/atlas.json); the last two are not drawn
    /// on the map and are listed all the same.
    static let regions: [(id: String, label: String)] = [
        ("maghreb", "Maghreb"), ("anatolia", "Anatolia"), ("mashriq", "Mashriq"), ("persia", "Persia"),
        ("khorasan", "Khorasan"), ("indus", "Indus"), ("hindustan", "Delhi \u{00B7} Awadh"), ("dakhan", "Dakhan"),
        ("qafqaz", "Qafqaz"), ("horn", "The Horn"),
    ]

    /// The house rules, in the site's words (kj-chat.js RULES), as they stand from 2026-10-25.
    static let houseRules = [
        "You need an account, and you need to be 16 or older.",
        "Four things are not allowed, and they are the only four: sexual material involving children; threats, and targeting a person so a room can find them; someone else\u{2019}s private material; attacking a person for what they are.",
        "Arguing, swearing, bad jokes, politics, filth and mess are not on the list.",
        "A reported line is hidden at once and a person reads it. If it was fine it comes back.",
        "What you write clears in 48 hours and is gone from the archive. Delete any of it sooner whenever you like.",
    ]

    /// Rooms an app offers: approved, and never a Partners (18+) room, which the apps leave out.
    static func offered(_ rooms: [ChatRoom]) -> [ChatRoom] {
        rooms.filter { $0.status == "approved" && $0.category != "partners" && $0.adult != true }
    }

    /// The house rooms first, then each region with its rooms: Daily feelings, Food, Sport and
    /// Fashion, then the rooms visitors made, in the order they were made (kj-chat.js roomRank).
    static func grouped(_ rooms: [ChatRoom]) -> [(title: String, rooms: [ChatRoom])] {
        let shown = offered(rooms)
        var groups: [(String, [ChatRoom])] = []
        let house = shown.filter { $0.kind == "house" || $0.region == nil }
        if !house.isEmpty { groups.append(("Khajistan", house)) }
        for region in regions {
            let inRegion = shown.filter { $0.region == region.id && $0.kind != "house" }
            if inRegion.isEmpty { continue }
            let ranked = inRegion.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
            groups.append((region.label, ranked))
        }
        return groups
    }

    private static let baseOrder = ["daily-feelings", "food", "sport", "fashion"]
    private static func rank(_ room: ChatRoom) -> Int {
        var base = room.slug
        if let region = room.region, room.slug.hasPrefix(region + "-") { base = String(room.slug.dropFirst(region.count + 1)) }
        return baseOrder.firstIndex(of: base) ?? 100
    }

    /// What a refused post means, in the site's words (kj-chat.js explain()).
    static func explain(status: Int, body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self)
        if text.contains("row-level security") || status == 401 || status == 403 {
            return "The room refused that. Booted, banned, slow mode, or the room is not open to you."
        }
        return "That did not send."
    }

    /// A line as it may be sent: trimmed, 1 to 2,000 characters (the table's own check).
    static func cleaned(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...2000).contains(trimmed.count) ? trimmed : nil
    }

    static func isSlug(_ text: String) -> Bool {
        text.range(of: "^[a-z0-9][a-z0-9-]{1,58}$", options: .regularExpression) != nil
    }

    static func isUserId(_ text: String) -> Bool {
        text.range(of: "^[0-9a-fA-F-]{36}$", options: .regularExpression) != nil
    }

    // MARK: Ignore, on this device only, as the site's (kj-chat-ignore)

    static let ignoreKey = "kj.chat.ignore"
    static func ignored(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: ignoreKey) ?? [])
    }
    static func setIgnored(_ handle: String, _ on: Bool, _ defaults: UserDefaults = .standard) {
        var all = ignored(defaults)
        if on { all.insert(handle) } else { all.remove(handle) }
        defaults.set(all.sorted(), forKey: ignoreKey)
    }
}

// MARK: - Requests

enum ChatAPI {
    static let historyLimit = 60

    static func roomsRequest(token: String?) -> URLRequest {
        request("/rest/v1/chat_rooms?select=slug,label,kind,region,country,category,adult,description,status,slow_mode_seconds&status=eq.approved&order=created_at.asc", token: token)
    }

    /// The newest lines, or those older than `before` (the room's paging cursor). Newest first;
    /// the caller reverses them.
    static func historyRequest(room: String, before: Int64?, token: String?) -> URLRequest? {
        guard ChatRules.isSlug(room) else { return nil }
        let cursor = before.map { "&id=lt.\($0)" } ?? ""
        return request("/rest/v1/chat_messages?select=\(columns)&room_slug=eq.\(room)\(cursor)&order=id.desc&limit=\(historyLimit)", token: token)
    }

    /// Lines after `after`, oldest first.
    static func newerRequest(room: String, after: Int64, token: String?) -> URLRequest? {
        guard ChatRules.isSlug(room) else { return nil }
        return request("/rest/v1/chat_messages?select=\(columns)&room_slug=eq.\(room)&id=gt.\(after)&order=id.asc&limit=200", token: token)
    }

    /// Moderation changes in a room since `since`.
    static func statesRequest(room: String, since: Date, token: String?) -> URLRequest? {
        guard ChatRules.isSlug(room) else { return nil }
        let at = ChatClock.text(since).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return request("/rest/v1/chat_message_state?select=message_id,state,at&room_slug=eq.\(room)&at=gt.\(at)", token: token)
    }

    static func postRequest(room: String, body: String, userId: String, handle: String, token: String) -> URLRequest? {
        guard ChatRules.isSlug(room), ChatRules.isUserId(userId), let line = ChatRules.cleaned(body) else { return nil }
        let row: [String: Any] = ["room_slug": room, "author_id": userId, "author_handle": handle, "body": line, "kind": "text"]
        return write("/rest/v1/chat_messages", method: "POST", row: row, token: token)
    }

    static func reportRequest(messageId: Int64, userId: String, token: String) -> URLRequest? {
        guard ChatRules.isUserId(userId) else { return nil }
        return write("/rest/v1/chat_reports", method: "POST", row: ["message_id": messageId, "reporter_id": userId], token: token)
    }

    static func deleteRequest(messageId: Int64, token: String) -> URLRequest {
        var call = request("/rest/v1/chat_messages?id=eq.\(messageId)", token: token)
        call.httpMethod = "DELETE"
        return call
    }

    /// The account's chat handle (`profiles.username`).
    static func handleRequest(userId: String, token: String) -> URLRequest? {
        guard ChatRules.isUserId(userId) else { return nil }
        return request("/rest/v1/profiles?select=username&id=eq.\(userId)", token: token)
    }

    /// The account itself, for the 16+ acknowledgement in its metadata (`min_age_ack`).
    static func userRequest(token: String) -> URLRequest {
        request("/auth/v1/user", token: token)
    }

    /// Records the 16+ acknowledgement on the account, as the site's room door does.
    static func ageAckRequest(token: String) -> URLRequest {
        var call = request("/auth/v1/user", token: token)
        call.httpMethod = "PUT"
        call.httpBody = try? JSONSerialization.data(withJSONObject: ["data": ["min_age_ack": 16]])
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return call
    }

    static func claimHandleRequest(want: String, token: String) -> URLRequest? {
        guard want.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else { return nil }
        return write("/rest/v1/rpc/chat_claim_handle", method: "POST", row: ["want": want], token: token)
    }

    private static let columns = "id,room_slug,author_id,author_handle,body,kind,created_at,hidden_at,removed_at,expires_at"

    private static func write(_ path: String, method: String, row: [String: Any], token: String) -> URLRequest? {
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        var call = request(path, token: token)
        call.httpMethod = method
        call.httpBody = body
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        call.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return call
    }

    private static func request(_ pathAndQuery: String, token: String?) -> URLRequest {
        var call = URLRequest(url: URL(string: pathAndQuery, relativeTo: KJConfig.supabase)!.absoluteURL)
        call.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        call.timeoutInterval = 15
        call.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(token ?? KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        call.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        return call
    }
}

// MARK: - A room, live

/// One room's lines, kept current. Reads need no account; posting and reporting need one. Asks
/// for new lines and moderation changes every three seconds while open.
/// ponytail: polling; a Supabase Realtime socket can replace `poll()` without changing `lines`.
@MainActor
final class ChatFeed {
    let room: ChatRoom
    /// The account's token and id, or nil signed out. Each app passes its own sign-in store's.
    private let account: () async -> (token: String, userId: String)?
    private let session: URLSession
    private var all: [Int64: ChatMessage] = [:]
    private var newest: Int64 = 0
    private var oldest: Int64?
    private var statesSince = Date()
    private var pollTask: Task<Void, Never>?
    private var continuation: AsyncStream<[ChatMessage]>.Continuation?
    private(set) var reachedStart = false

    /// The room's visible lines, oldest first, each time they change.
    let lines: AsyncStream<[ChatMessage]>

    init(room: ChatRoom, account: @escaping () async -> (token: String, userId: String)?) {
        self.room = room
        self.account = account
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        var held: AsyncStream<[ChatMessage]>.Continuation?
        lines = AsyncStream { held = $0 }
        continuation = held
    }

    /// The newest lines, then a check every three seconds until `stop()`.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.loadOlder()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Sixty lines older than the oldest on screen.
    func loadOlder() async {
        guard !reachedStart else { return }
        let token = await account()?.token
        guard let request = ChatAPI.historyRequest(room: room.slug, before: oldest, token: token),
              let rows: [ChatMessage] = await fetch(request) else { return }
        if rows.count < ChatAPI.historyLimit { reachedStart = true }
        for row in rows { all[row.id] = row }
        oldest = all.keys.min()
        newest = max(newest, all.keys.max() ?? 0)
        publish()
    }

    private func poll() async {
        let token = await account()?.token
        if let request = ChatAPI.newerRequest(room: room.slug, after: newest, token: token),
           let rows: [ChatMessage] = await fetch(request), !rows.isEmpty {
            for row in rows { all[row.id] = row }
            newest = max(newest, rows.map(\.id).max() ?? newest)
        }
        let since = statesSince
        statesSince = Date()
        if let request = ChatAPI.statesRequest(room: room.slug, since: since.addingTimeInterval(-5), token: token),
           let states: [ChatLineState] = await fetch(request) {
            for change in states where change.state != "visible" { all[change.message_id] = nil }
        }
        publish()
    }

    /// Sends a line. Nil when it was taken; otherwise the reason, in the site's words.
    func send(_ body: String, handle: String) async -> String? {
        guard let me = await account() else { return "Sign in under Account to write in a room." }
        guard let request = ChatAPI.postRequest(room: room.slug, body: body, userId: me.userId, handle: handle, token: me.token) else {
            return "A line is 1 to 2,000 characters."
        }
        guard let (data, response) = try? await session.data(for: request) else { return "That did not send." }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 201 || status == 204 {
            await poll()
            return nil
        }
        return ChatRules.explain(status: status, body: data)
    }

    /// Reports a line to the desk; the server hides it at once.
    func report(_ line: ChatMessage) async -> String {
        guard let me = await account(), let request = ChatAPI.reportRequest(messageId: line.id, userId: me.userId, token: me.token) else {
            return "Sign in under Account to report a line."
        }
        guard let (data, response) = try? await session.data(for: request) else { return "That did not reach the desk." }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 201 || status == 204 {
            all[line.id] = nil
            publish()
            return "Reported. It is with the desk."
        }
        if status == 409 || String(decoding: data, as: UTF8.self).contains("duplicate") { return "You already reported that." }
        return ChatRules.explain(status: status, body: data)
    }

    /// Deletes one of the account's own text lines.
    func delete(_ line: ChatMessage) async -> Bool {
        guard line.kind == "text", let me = await account(), line.author_id == me.userId else { return false }
        guard let (_, response) = try? await session.data(for: ChatAPI.deleteRequest(messageId: line.id, token: me.token)),
              let status = (response as? HTTPURLResponse)?.statusCode, status == 200 || status == 204 else { return false }
        all[line.id] = nil
        publish()
        return true
    }

    private func publish() {
        let now = Date()
        continuation?.yield(all.values.filter { $0.isVisible(now: now) }.sorted { $0.id < $1.id })
    }

    private func fetch<T: Decodable>(_ request: URLRequest) async -> T? {
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
