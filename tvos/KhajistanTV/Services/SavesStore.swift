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
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Refs with a change on its way.
    @ObservationIgnored private var busy: Set<String> = []
    private unowned let auth: AuthStore
    private let urlSession: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: config)
    }

    var canSave: Bool { auth.isSignedIn }

    /// Reads the account's saves, once per account. One read at a time; a failed read leaves the
    /// saves unknown, and nothing is drawn or toggled on an unknown answer.
    func load() async {
        guard let userId = auth.session?.userId else { refs = []; loadedFor = nil; return }
        if loadedFor == userId { return }
        if let running = loading { return await running.value }
        let task = Task { await read(userId) }
        loading = task
        await task.value
        loading = nil
    }

    private func read(_ userId: String) async {
        guard let token = try? await auth.validAccessToken(),
              let request = PassportSaves.listRequest(userId: userId, accessToken: token),
              let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([PassportSave].self, from: data),
              auth.session?.userId == userId else { return }
        refs = Set(rows.map(\.object_ref))
        loadedFor = userId
    }

    /// The saves are known for the account signed in now.
    private var known: Bool { loadedFor != nil && loadedFor == auth.session?.userId }

    func isSaved(_ channel: Channel) -> Bool {
        known && !refs.isDisjoint(with: PassportSaves.channelRefs(slug: channel.slug, id: channel.id, legacyIds: channel.legacyIds))
    }

    func isSaved(_ title: RRTitle) -> Bool {
        known && (PassportSaves.titleRef(slug: title.slug).map(refs.contains) ?? false)
    }

    /// Likes a channel, or unlikes it under every name it answers to. Returns false when the
    /// server did not take it, and the heart goes back to what it was.
    @discardableResult
    func toggle(_ channel: Channel) async -> Bool {
        let all = PassportSaves.channelRefs(slug: channel.slug, id: channel.id, legacyIds: channel.legacyIds)
        guard let first = all.first else { return false }
        return await change(all) { saved in
            saved ? await self.remove(all)
                  : await self.add(first, wing: PassportSaves.receiverWing, title: channel.name,
                                   href: PassportSaves.channelHref(slug: channel.slug, id: channel.id))
        }
    }

    @discardableResult
    func toggle(_ title: RRTitle) async -> Bool {
        guard let ref = PassportSaves.titleRef(slug: title.slug) else { return false }
        return await change([ref]) { saved in
            saved ? await self.remove([ref])
                  : await self.add(ref, wing: PassportSaves.readingRoomWing, title: title.name, href: PassportSaves.titleHref(slug: title.slug))
        }
    }

    /// One change per item at a time, on saves known for this account. A press while the last
    /// change to the same item is on its way is not a second change.
    private func change(_ all: [String], _ act: (Bool) async -> Bool) async -> Bool {
        await load()
        guard known else { return false }
        guard busy.isDisjoint(with: all) else { return true }
        busy.formUnion(all)
        defer { busy.subtract(all) }
        return await act(!refs.isDisjoint(with: all))
    }

    private func add(_ ref: String, wing: String, title: String, href: String) async -> Bool {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.insertRequest(userId: userId, ref: ref, wing: wing, title: title, href: href, accessToken: token) else { return false }
        refs.insert(ref)
        let reply = try? await urlSession.data(for: request)
        let code = (reply?.1 as? HTTPURLResponse)?.statusCode ?? 0
        // A unique-key refusal (23505) means the account already holds it, the state wanted.
        if code == 201 || code == 204 { return true }
        if code == 409, let body = reply?.0, String(decoding: body, as: UTF8.self).contains("23505") { return true }
        refs.remove(ref)
        return false
    }

    private func remove(_ all: [String]) async -> Bool {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.deleteRequest(userId: userId, refs: all, accessToken: token) else { return false }
        let held = refs.intersection(all)
        refs.subtract(all)
        let code = (try? await urlSession.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
        if code == 200 || code == 204 { return true }
        refs.formUnion(held)
        return false
    }
}
