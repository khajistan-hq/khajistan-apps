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
    init(configuration: URLSessionConfiguration) {}
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url!.path.hasSuffix("logout") {
            return (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        // The authenticator lookup a sign-in now makes (tv/mfa-code): no factor, answered at once,
        // so the race scenarios below still release only the requests they are about.
        if request.httpMethod == "GET" && request.url!.path.hasSuffix("/auth/v1/user") {
            return (Data(#"{"factors":[]}"#.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
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
        print("PASS seven actual AuthStore race scenarios; no external network")
    }
}
