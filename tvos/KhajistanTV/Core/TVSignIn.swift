import Foundation

/// Signing in on the television from a phone (owner, 2026-10-27: "allow people to sign in with
/// their phone or with a qr code"). The TV asks the tv-sign-in function for a code and shows it
/// with a QR for the archive's /activate page; a signed-in phone, on that page or in the iPhone
/// app, approves it; the TV, asking every few seconds, is handed a one-time token hash and turns it
/// into its own session at /auth/v1/verify. No password crosses between the devices.
/// Shared by the two apps (linked into the phone), so it is Foundation only.
enum TVSignIn {
    static let function = KJConfig.supabase.appendingPathComponent("functions/v1/tv-sign-in")
    /// The alphabet the function draws codes from: no vowels, no look-alikes.
    static let alphabet = "CDFGHJKMNPQRTVWXYZ234679"
    static let codeLength = 8

    /// What the TV is given to show and to keep.
    struct Start: Decodable, Equatable, Sendable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let verification_uri_complete: String
        let interval: Int
        let expires_in: Int
    }

    /// One answer to the TV's question "has anyone approved me yet?".
    enum Poll: Equatable, Sendable {
        case pending
        /// Asked too fast: wait longer before the next.
        case slowDown
        case expired
        case approved(tokenHash: String)
    }

    /// What a phone is told about a code before it approves it.
    struct Pending: Decodable, Equatable, Sendable {
        let device_label: String?
        let created_at: String
        let expires_at: String
        /// False when the TV asked from another network than this phone's: the approver is warned.
        let same_network: Bool?
    }

    // MARK: Requests

    /// The function names the device itself ("Apple TV"): a caller's label is not shown to anyone.
    static func startRequest() -> URLRequest {
        call(["action": "start"], bearer: KJConfig.anonKey)
    }

    static func pollRequest(deviceCode: String) -> URLRequest {
        call(["action": "poll", "device_code": deviceCode], bearer: KJConfig.anonKey)
    }

    /// A signed-in phone asks what is waiting on a code; nil for a code that cannot be one.
    static func peekRequest(code: String, accessToken: String) -> URLRequest? {
        normalise(code).map { call(["action": "peek", "user_code": $0], bearer: accessToken) }
    }

    static func approveRequest(code: String, accessToken: String) -> URLRequest? {
        normalise(code).map { call(["action": "approve", "user_code": $0], bearer: accessToken) }
    }

    /// The one-time token hash turned into a session, as a password sign-in answers.
    static func verifyRequest(tokenHash: String) -> URLRequest {
        var request = URLRequest(url: KJConfig.supabase.appendingPathComponent("auth/v1/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KJConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "email", "token_hash": tokenHash])
        return request
    }

    private static func call(_ body: [String: String], bearer: String) -> URLRequest {
        var request = URLRequest(url: function)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Answers

    static func start(from data: Data) -> Start? {
        guard let start = try? JSONDecoder().decode(Start.self, from: data),
              normalise(start.user_code) != nil, start.device_code.count >= 40,
              start.verification_uri_complete.hasPrefix("https://") else { return nil }
        return start
    }

    static func poll(from data: Data) -> Poll? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = object["status"] as? String else { return nil }
        switch status {
        case "pending": return .pending
        case "slow_down": return .slowDown
        case "expired": return .expired
        case "approved":
            guard let hash = object["token_hash"] as? String, !hash.isEmpty else { return nil }
            return .approved(tokenHash: hash)
        default: return nil
        }
    }

    // MARK: Codes

    /// What a person typed or a camera read, as the function wants it: upper case, no spaces or
    /// dashes, eight symbols of the alphabet. Nil if it cannot be a code.
    static func normalise(_ typed: String) -> String? {
        let code = typed.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard code.count == codeLength, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }

    /// "QRT4MXZ7" → "QRT4-MXZ7".
    static func display(_ code: String) -> String {
        guard let clean = normalise(code) else { return code }
        return String(clean.prefix(4)) + "-" + String(clean.suffix(4))
    }

    /// A code from what a phone's camera read: the /activate address the TV's QR carries (on the
    /// archive's own host only), or the code itself. The host is KJConfig.site's: when the function's
    /// TV_SIGN_IN_URL moves, this moves with it.
    static func code(fromScanned text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = normalise(trimmed) { return direct }
        guard let parts = URLComponents(string: trimmed), parts.scheme == "https",
              parts.host == KJConfig.site.host, parts.path == "/activate" || parts.path == "/activate.html",
              let value = parts.queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        return normalise(value)
    }
}
