import Foundation
import Observation

/// The rooms and what this account needs to write in them: a handle and the 16+ acknowledgement,
/// both the website's own (profiles.username, user_metadata.min_age_ack).
@MainActor @Observable
final class ChatStore {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }
    struct Group: Identifiable { let title: String; let rooms: [ChatRoom]; var id: String { title } }

    private(set) var phase: Phase = .idle
    private(set) var groups: [Group] = []
    /// Nil until read, "" when the account has none yet.
    private(set) var handle: String?
    private(set) var ageAcknowledged = false

    private unowned let auth: AuthStore
    private let session: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func start() async {
        if phase == .loading || phase == .ready { return }
        phase = .loading
        guard let (data, response) = try? await session.data(for: ChatAPI.roomsRequest(token: await account()?.token)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rooms = try? JSONDecoder().decode([ChatRoom].self, from: data) else {
            phase = .failed("The rooms did not answer.")
            return
        }
        groups = ChatRules.grouped(rooms).map { Group(title: $0.title, rooms: $0.rooms) }
        phase = .ready
    }

    /// The account's token and id, refreshed when needed; nil signed out.
    func account() async -> (token: String, userId: String)? {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken() else { return nil }
        return (token, userId)
    }

    /// Reads the handle and the 16+ acknowledgement for the account signed in.
    func loadAccount() async {
        guard let me = await account() else { handle = nil; ageAcknowledged = false; return }
        if let request = ChatAPI.handleRequest(userId: me.userId, token: me.token),
           let (data, _) = try? await session.data(for: request),
           let rows = try? JSONDecoder().decode([HandleRow].self, from: data) {
            handle = rows.first?.username ?? ""
        }
        if let (data, _) = try? await session.data(for: ChatAPI.userRequest(token: me.token)),
           let user = try? JSONDecoder().decode(UserRow.self, from: data) {
            ageAcknowledged = (user.user_metadata?.min_age_ack ?? 0) >= 16
        }
    }

    /// Records "I am 16 or older" on the account, as the website's room door does.
    func acknowledgeAge() async -> Bool {
        guard let me = await account(),
              let (_, response) = try? await session.data(for: ChatAPI.ageAckRequest(token: me.token)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        ageAcknowledged = true
        return true
    }

    /// Claims a handle. Nil when it was taken; otherwise why not, in the server's words.
    func claim(_ want: String) async -> String? {
        let name = want.trimmingCharacters(in: .whitespaces).lowercased()
        guard let me = await account() else { return "Sign in under Account first." }
        guard let request = ChatAPI.claimHandleRequest(want: name, token: me.token) else {
            return "A handle is 3 to 20 letters, numbers or underscores."
        }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return "That did not reach the server." }
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if answer?["ok"] as? Bool == true {
            handle = name
            return nil
        }
        return (answer?["error"] as? String) ?? "That handle is not available."
    }

    private struct HandleRow: Decodable { let username: String? }
    private struct UserRow: Decodable {
        struct Meta: Decodable { let min_age_ack: Int? }
        let user_metadata: Meta?
    }
}
