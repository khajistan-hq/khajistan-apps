// Actual AuthStore and AuthAPI; in-memory keychain and suspended HTTP boundary only.
import Foundation

enum SupabaseRoute {
    static let base = URL(string: "https://auth-test.invalid")!
    static func url(_ path: String) -> URL? { URL(string: base.absoluteString + path) }
}
@MainActor enum Keychain {
    static var values: [String: Data] = [:]
    static func read(_ account: String) -> Data? { values[account] }
    static func write(_ data: Data, account: String, shared: Bool = false) throws { values[account] = data }
    static func delete(_ account: String) { values.removeValue(forKey: account) }
}
@MainActor final class URLSession {
    static var pending: [(URLRequest, CheckedContinuation<(Data, URLResponse), Error>)] = []
    static var hasFactor = false
    init(configuration: URLSessionConfiguration) {}
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url!.path.hasSuffix("logout") {
            return (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        // Answer setup requests at once so each race suspends only the response under test.
        if request.httpMethod == "GET" && request.url!.path.hasSuffix("/auth/v1/user") {
            let body = Self.hasFactor ? #"{"factors":[{"id":"factor-a","factor_type":"totp","status":"verified"}]}"# : #"{"factors":[]}"#
            return (Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        if request.url!.path.hasSuffix("/challenge") {
            return (Data(#"{"id":"challenge-a"}"#.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        return try await withCheckedThrowingContinuation { Self.pending.append((request,$0)) }
    }
    static func release(_ user: String, code: Int = 200) {
        let (request, waiter) = pending.removeFirst()
        let object: [String: Any] = ["access_token":"token-"+user,"refresh_token":"refresh-"+user,"expires_in":3600,"user":["id":user,"email":user+"@example.invalid"]]
        waiter.resume(returning:(try! JSONSerialization.data(withJSONObject:object),HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!))
    }
}
struct Failure: Error { let message: String }
@MainActor func check(_ condition: @autoclosure () -> Bool, _ text: String) throws {
    if !condition() { throw Failure(message:text) }
}
@MainActor func waitRequest() async throws {
    for _ in 0..<100 {
        if !URLSession.pending.isEmpty { return }
        try await Task.sleep(for:.milliseconds(5))
    }
    throw Failure(message:"Missing synthetic auth request")
}
@MainActor func store() throws -> AuthStore {
    let old=Session(accessToken:"old",refreshToken:"old-refresh",expiresAt:.distantPast,email:"a@example.invalid",userId:"a")
    Keychain.values=["session":try JSONEncoder().encode(old)]
    return AuthStore()
}
@main struct AuthSessionHarness {
    @MainActor static func main() async throws {
        // A stale refresh must neither resurrect a signed-out account nor persist a token.
        for code in [200,401] {
            let auth=try store(); var changes=0
            let observer=auth.observeAccess { changes += 1 }
            let task=Task { try? await auth.validAccessToken() }
            try await waitRequest();await auth.signOut()
            try check(changes == 1 && auth.session == nil,"signout synchronous observer")
            URLSession.release("a",code:code)
            let result=await task.value
            try check(result == nil && auth.session == nil && Keychain.read("session") == nil,"stale refresh after logout")
            auth.removeAccessObserver(observer)
        }
        // A new login wins over an older refresh even when the older request later fails.
        for code in [200,401] {
            let auth=try store()
            let refresh=Task { try? await auth.validAccessToken() };try await waitRequest()
            let login=Task { try? await auth.signIn(email:"b@example.invalid",password:"fixture") }
            while URLSession.pending.count < 2 { try await Task.sleep(for:.milliseconds(5)) }
            // Resolve login first, then the obsolete refresh.
            URLSession.pending.swapAt(0,1);URLSession.release("b");await login.value
            URLSession.release("a",code:code);let result=await refresh.value
            try check(auth.session?.userId == "b" && result == nil,"stale refresh cannot overwrite or clear new account")
        }
        // A login response after logout cannot sign the viewer back in.
        let auth=try store()
        let login=Task { try? await auth.signIn(email:"b@example.invalid",password:"fixture") };try await waitRequest()
        await auth.signOut();URLSession.release("b");await login.value
        try check(auth.session == nil,"stale login after signout")
        // A normal same-account refresh retains caption access generation.
        let normal=try store();let generation=normal.accessGeneration
        let refresh=Task { try? await normal.validAccessToken() };try await waitRequest();URLSession.release("a")
        let token=await refresh.value
        try check(token == "token-a" && normal.accessGeneration == generation,"same-account refresh preserves lifecycle")
        let same=try store();var invalidated=0
        _ = same.observeAccess { invalidated += 1 }
        let sameLogin=Task { try? await same.signIn(email:"a@example.invalid",password:"fixture") }
        try await waitRequest();URLSession.release("a");await sameLogin.value
        try check(invalidated == 1,"explicit same-account login invalidates old captions")
        // A delayed MFA response must not undo logout or a newer login, including the same user.
        URLSession.hasFactor = true
        for replacement in ["logout", "a", "b", "none"] {
            let mfa = try store()
            let login = Task { try await mfa.signIn(email:"a@example.invalid",password:"fixture") }
            try await waitRequest(); URLSession.release("a"); try await login.value
            try check(mfa.pendingFactorId == "factor-a", "MFA factor is armed")
            let verification = Task { () -> Bool in
                do { try await mfa.verifyCode("123456"); return true } catch { return false }
            }
            try await waitRequest()
            try check(URLSession.pending.first?.0.url?.path.hasSuffix("/verify") == true, "MFA verification is suspended")
            if replacement == "logout" { await mfa.signOut() }
            else if replacement != "none" {
                let newer = Task { try await mfa.signIn(email:replacement+"@example.invalid",password:"fixture") }
                while URLSession.pending.count < 2 { try await Task.sleep(for:.milliseconds(5)) }
                URLSession.pending.swapAt(0,1); URLSession.release(replacement); try await newer.value
            }
            let saved = Keychain.read("session")
            URLSession.release("a")
            let succeeded = await verification.value
            if replacement == "none" {
                try check(succeeded && mfa.session?.userId == "a" && mfa.pendingFactorId == nil, "current MFA succeeds")
            } else {
                try check(!succeeded && Keychain.read("session") == saved, "stale MFA cannot persist a session")
                try check(mfa.session?.userId == (replacement == "logout" ? nil : replacement), "stale MFA cannot replace current account")
                try check(mfa.pendingFactorId == (replacement == "logout" ? nil : "factor-a"), "stale MFA cannot clear a newer factor")
            }
        }
        let preview = try store()
        var observed: [String?] = []
        preview.onPreviewPasswordChange = { observed.append(preview.previewPassword) }
        preview.setPreviewPassword("fixture-preview-one")
        preview.setPreviewPassword("fixture-preview-one")
        preview.setPreviewPassword("fixture-preview-two")
        preview.clearPreviewPassword()
        preview.clearPreviewPassword()
        try check(observed == ["fixture-preview-one", "fixture-preview-two", nil, nil],
                  "preview callbacks see updated state; unchanged save is quiet and every Clear invalidates")
        print("PASS twelve actual AuthStore scenarios; no external network")
    }
}
