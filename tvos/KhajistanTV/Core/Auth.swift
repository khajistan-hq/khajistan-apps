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

    /// The access token's `aal` claim ("aal1", "aal2"), or nil when it cannot be read.
    var assurance: String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var text = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return claims["aal"] as? String
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

    // MARK: - Two-step sign-in (kj-mfa.js on the site)
    //
    // vod-token opens its staff door only on an aal2 session when the account has a verified
    // authenticator (staff_second_factor_ok, 2026-11-02). A password or phone sign-in is aal1, so
    // an account with a factor finishes signing in with its six-digit code.

    private struct VerifyBody: Encodable { let challenge_id: String; let code: String }
    private struct UserBody: Decodable {
        struct Factor: Decodable { let id: String?; let factor_type: String?; let status: String? }
        let factors: [Factor]?
    }
    private struct ChallengeBody: Decodable { let id: String? }

    static func userRequest(accessToken: String) -> URLRequest {
        var request = post("/auth/v1/user", bearer: accessToken, body: nil)
        request.httpMethod = "GET"
        return request
    }

    /// The account's verified authenticator, or nil when it has none.
    static func verifiedTOTP(from data: Data) -> String? {
        let factors = (try? JSONDecoder().decode(UserBody.self, from: data))?.factors ?? []
        return factors.first { $0.factor_type == "totp" && $0.status == "verified" && !($0.id ?? "").isEmpty }?.id
    }

    static func challengeRequest(factorId: String, accessToken: String) -> URLRequest {
        post("/auth/v1/factors/\(KJURL.encodeQueryValue(factorId))/challenge", bearer: accessToken, body: Data("{}".utf8))
    }

    static func challengeId(from data: Data) -> String? {
        guard let id = (try? JSONDecoder().decode(ChallengeBody.self, from: data))?.id, !id.isEmpty else { return nil }
        return id
    }

    /// Answered like a password sign-in: the body is the aal2 session.
    static func verifyRequest(factorId: String, challengeId: String, code: String, accessToken: String) -> URLRequest {
        post("/auth/v1/factors/\(KJURL.encodeQueryValue(factorId))/verify", bearer: accessToken,
             body: encode(VerifyBody(challenge_id: challengeId, code: code)))
    }

    /// The verified authenticator a fresh sign-in still owes a code for. A failed lookup asks for
    /// nothing: the server still decides what plays.
    static func factorOwed(by session: Session, using urlSession: URLSession) async -> String? {
        guard let (data, response) = try? await urlSession.data(for: userRequest(accessToken: session.accessToken)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return verifiedTOTP(from: data)
    }

    /// Challenges the authenticator and verifies the typed code; the answer is the aal2 session.
    /// The refusals are kj-mfa.js's words.
    static func verify(_ typed: String, factorId: String, session: Session, using urlSession: URLSession) async throws -> Session {
        guard let code = code(typed) else { throw AuthError.server("Six digits.") }
        let (challenge, challengeResponse) = try await urlSession.data(
            for: challengeRequest(factorId: factorId, accessToken: session.accessToken))
        guard (challengeResponse as? HTTPURLResponse)?.statusCode ?? 0 < 400,
              let challengeId = challengeId(from: challenge) else {
            throw AuthError.server("Two-step sign-in is unavailable right now.")
        }
        let (data, response) = try await urlSession.data(
            for: verifyRequest(factorId: factorId, challengeId: challengeId, code: code, accessToken: session.accessToken))
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400 else {
            throw AuthError.server("That code did not work. Try the next one.")
        }
        return try AuthAPI.session(from: data, now: Date())
    }

    /// The six digits out of whatever was typed, or nil when there are not exactly six.
    static func code(_ typed: String) -> String? {
        let digits = typed.filter { $0.isASCII && $0.isNumber }
        return digits.count == 6 ? String(digits) : nil
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
    /// {"error","error_description"}, {"code","msg"} and {"code","message"}. The first non-empty of
    /// error_description, message and msg wins, in that order. Nil when the body is not JSON or carries none of them.
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
        let url = SupabaseRoute.url(pathAndQuery)!
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
