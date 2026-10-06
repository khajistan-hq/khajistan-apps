import Foundation
import Observation

/// The signed-in account's saves on the receiver and in the Reading Room, read from and written to
/// `passport_saves`, the table the website and the dashboard use. Signed out there is nothing to
/// save to: the screens say so rather than keep a save only on this device.
@MainActor @Observable
final class SavesStore {
    /// Refs the account holds, as the server last said, with this device's changes on top.
    private(set) var refs: Set<String> = []
    @ObservationIgnored private var loadedFor: String?
    private unowned let auth: AuthStore
    private let urlSession: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: config)
    }

    var canSave: Bool { auth.isSignedIn }

    /// Reads the account's saves, once per account.
    func load() async {
        guard let userId = auth.session?.userId else { refs = []; loadedFor = nil; return }
        if loadedFor == userId { return }
        guard let token = try? await auth.validAccessToken(),
              let request = PassportSaves.listRequest(userId: userId, accessToken: token),
              let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([PassportSave].self, from: data) else { return }
        refs = Set(rows.map(\.object_ref))
        loadedFor = userId
    }

    func isSaved(_ channel: Channel) -> Bool {
        !refs.isDisjoint(with: PassportSaves.channelRefs(slug: channel.slug, id: channel.id, legacyIds: channel.legacyIds))
    }

    func isSaved(_ title: RRTitle) -> Bool {
        PassportSaves.titleRef(slug: title.slug).map(refs.contains) ?? false
    }

    /// Likes a channel, or unlikes it under every name it answers to. Returns false when the
    /// server did not take it, and the heart goes back to what it was.
    @discardableResult
    func toggle(_ channel: Channel) async -> Bool {
        let all = PassportSaves.channelRefs(slug: channel.slug, id: channel.id, legacyIds: channel.legacyIds)
        guard let first = all.first else { return false }
        if isSaved(channel) {
            return await remove(all)
        }
        return await add(first, wing: PassportSaves.receiverWing, title: channel.name,
                         href: PassportSaves.channelHref(slug: channel.slug, id: channel.id))
    }

    @discardableResult
    func toggle(_ title: RRTitle) async -> Bool {
        guard let ref = PassportSaves.titleRef(slug: title.slug) else { return false }
        if refs.contains(ref) { return await remove([ref]) }
        return await add(ref, wing: PassportSaves.readingRoomWing, title: title.name, href: PassportSaves.titleHref(slug: title.slug))
    }

    private func add(_ ref: String, wing: String, title: String, href: String) async -> Bool {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.insertRequest(userId: userId, ref: ref, wing: wing, title: title, href: href, accessToken: token) else { return false }
        refs.insert(ref)
        let code = (try? await urlSession.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
        // 409 is the unique constraint: the account already holds it, which is the state wanted.
        if code == 201 || code == 204 || code == 409 { return true }
        refs.remove(ref)
        return false
    }

    private func remove(_ all: [String]) async -> Bool {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.deleteRequest(userId: userId, refs: all, accessToken: token) else { return false }
        let before = refs
        refs.subtract(all)
        let code = (try? await urlSession.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
        if code == 200 || code == 204 { return true }
        refs = before
        return false
    }
}
