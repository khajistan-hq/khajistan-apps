import Foundation

/// A signed-in viewer's tokens, stored in the Keychain as JSON.
struct Session: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String?
    let userId: String

    /// True once the access token is within 60 seconds of expiry, so a request never leaves with a
    /// token that dies in flight.
    func isExpired(at date: Date) -> Bool {
        expiresAt.timeIntervalSince(date) <= 60
    }
}

enum AuthError: Error, Equatable {
    /// The auth server refused, with its own words for the viewer.
    case server(String)
    /// The server issued an anonymous session; Khajistan Transmission is for signed-in accounts.
    case anonymous
    /// The body is not a session.
    case malformed
}

/// Supabase Auth REST, as plain requests and parsers. The app never holds a key beyond the public
/// anon key in KJConfig.
enum AuthAPI {
    private struct PasswordBody: Encodable { let email: String; let password: String }
    private struct RefreshBody: Encodable { let refresh_token: String }

    static func passwordRequest(email: String, password: String) -> URLRequest {
        post("/auth/v1/token?grant_type=password", bearer: KJConfig.anonKey,
             body: encode(PasswordBody(email: email, password: password)))
    }

    static func refreshRequest(refreshToken: String) -> URLRequest {
        post("/auth/v1/token?grant_type=refresh_token", bearer: KJConfig.anonKey,
             body: encode(RefreshBody(refresh_token: refreshToken)))
    }

    static func logoutRequest(accessToken: String) -> URLRequest {
        post("/auth/v1/logout", bearer: accessToken, body: nil)
    }

    private struct TokenBody: Decodable {
        struct User: Decodable {
            let id: String?
            let email: String?
            let role: String?
            let is_anonymous: Bool?
        }

        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let expires_at: Double?
        let user: User?
    }

    /// A success body reduced to a Session. An anonymous user (`is_anonymous` true, or role
    /// "anon") is refused before anything else is read. `expires_at` (unix seconds) is used when
    /// present, else `now + expires_in`.
    static func session(from data: Data, now: Date) throws -> Session {
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: data) else { throw AuthError.malformed }
        if body.user?.is_anonymous == true || body.user?.role == "anon" { throw AuthError.anonymous }
        guard let access = body.access_token, !access.isEmpty,
              let refresh = body.refresh_token, !refresh.isEmpty,
              let userId = body.user?.id, !userId.isEmpty else { throw AuthError.malformed }
        let expiresAt: Date
        if let at = body.expires_at, at > 0, at.isFinite {
            expiresAt = Date(timeIntervalSince1970: at)
        } else if let seconds = body.expires_in, seconds >= 0, seconds.isFinite {
            expiresAt = now.addingTimeInterval(seconds)
        } else {
            throw AuthError.malformed
        }
        return Session(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                       email: body.user?.email, userId: userId)
    }

    /// The server's own sentence from an error body. Three shapes exist:
    /// {"error","error_description"}, {"code","msg"} and {"code","message"}; first non-empty wins in
    /// that order. Nil when the body is not JSON or carries none of them.
    static func errorMessage(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in ["error_description", "message", "msg"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }

    private static func post(_ pathAndQuery: String, bearer: String, body: Data?) -> URLRequest {
        let url = URL(string: pathAndQuery, relativeTo: KJConfig.supabase)!.absoluteURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
