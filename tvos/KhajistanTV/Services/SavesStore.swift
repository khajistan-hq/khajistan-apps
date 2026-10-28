import Foundation
import Observation

/// The signed-in account's saves on the receiver and in the Reading Room, read from and written to
/// `passport_saves`, the table the website and the profile use. Signed out there is nothing to
/// save to: the screens say so rather than keep a save only on this device.
@MainActor @Observable
final class SavesStore {
    /// Refs the account holds, as the server last said, with this device's changes on top.
    private(set) var refs: Set<String> = []
    /// The account's saves as the server listed them, newest first.
    private(set) var rows: [PassportSave] = []
    /// The account's named Pics/Vids collections, newest first. A signed-in account may create one
    /// and change what it holds (the table's column grants; measured 2026-10-27).
    private(set) var collections: [PnvCollection] = []
    @ObservationIgnored private var loadedFor: String?
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Refs with a change on its way.
    @ObservationIgnored private var busy: Set<String> = []
    /// Collections with a change on its way: a second tap waits for none and changes nothing.
    @ObservationIgnored private var busyCollections: Set<String> = []
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
        guard let userId = auth.session?.userId else { refs = []; rows = []; collections = []; loadedFor = nil; return }
        if loadedFor == userId { return }
        if let running = loading { return await running.value }
        let task = Task { await read(userId) }
        loading = task
        await task.value
        loading = nil
    }

    private func read(_ userId: String) async {
        // Another account's saves are never shown while this one's are read.
        if loadedFor != userId { refs = []; rows = []; collections = [] }
        guard let token = try? await auth.validAccessToken(),
              let request = PassportSaves.listRequest(userId: userId, accessToken: token),
              let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([PassportSave].self, from: data),
              auth.session?.userId == userId else { return }
        refs = Set(rows.map(\.object_ref))
        self.rows = rows
        loadedFor = userId
        if let request = PassportSaves.collectionsRequest(userId: userId, accessToken: token),
           let (data, response) = try? await urlSession.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let found = try? JSONDecoder().decode([PnvCollection].self, from: data),
           auth.session?.userId == userId {
            collections = found
        }
    }

    /// Pics/Vids keys the account saved, newest first.
    var savedPnvKeys: [String] {
        guard known else { return [] }
        return rows.filter { $0.object_ref.hasPrefix("pnv:") && refs.contains($0.object_ref) }.map { String($0.object_ref.dropFirst(4)) }
    }

    /// Film handles on the account's watchlist, newest first.
    var watchlist: [String] {
        guard known else { return [] }
        return rows.filter { refs.contains($0.object_ref) }.compactMap { PassportSaves.filmHandle(ref: $0.object_ref) }
    }

    func isSaved(pnvKey key: String) -> Bool {
        known && (PassportSaves.pnvRef(key).map(refs.contains) ?? false)
    }

    func isSaved(page id: String) -> Bool {
        known && (PassportSaves.pageRef(id).map(refs.contains) ?? false)
    }

    /// Saved site pages (Madrassa essays): their ids, newest first.
    var savedPages: [String] {
        guard known else { return [] }
        return rows.filter { $0.object_ref.hasPrefix("page:") && refs.contains($0.object_ref) }.map { String($0.object_ref.dropFirst(5)) }
    }

    @discardableResult
    func toggle(page id: String, title: String, href: String) async -> Bool {
        guard let ref = PassportSaves.pageRef(id) else { return false }
        return await change([ref]) { saved in
            saved ? await self.remove([ref]) : await self.add(ref, wing: PassportSaves.otherWing, title: title, href: href)
        }
    }

    func isSaved(film handle: String) -> Bool {
        known && (PassportSaves.filmRef(handle).map(refs.contains) ?? false)
    }

    @discardableResult
    func toggle(pnvKey key: String) async -> Bool {
        guard let ref = PassportSaves.pnvRef(key) else { return false }
        return await change([ref]) { saved in
            saved ? await self.remove([ref])
                  : await self.add(ref, wing: PassportSaves.bornDigitalWing, title: nil, href: PassportSaves.pnvHref(key))
        }
    }

    @discardableResult
    func toggle(film handle: String, title: String) async -> Bool {
        guard let ref = PassportSaves.filmRef(handle) else { return false }
        return await change([ref]) { saved in
            saved ? await self.remove([ref])
                  : await self.add(ref, wing: PassportSaves.otherWing, title: title, href: PassportSaves.filmHref(handle))
        }
    }

    /// Makes a named collection, holding `keys`, and puts it first. Nil when the server did not take it.
    func createCollection(name: String, keys: [String] = []) async -> PnvCollection? {
        await load()
        guard known, let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.collectionInsertRequest(userId: userId, name: name, keys: keys, accessToken: token),
              let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 201,
              let made = (try? JSONDecoder().decode([PnvCollection].self, from: data))?.first,
              auth.session?.userId == userId else { return nil }
        collections.insert(made, at: 0)
        return made
    }

    /// Puts an object in a collection, or takes it out. False when the server did not take it, and
    /// the collection stays as it was.
    @discardableResult
    func toggle(pnvKey key: String, in collectionId: String) async -> Bool {
        guard known, !busyCollections.contains(collectionId),
              let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              // Found after the wait for the token: the list may have changed during it.
              let held = collections.first(where: { $0.id == collectionId }) else { return false }
        busyCollections.insert(collectionId)
        defer { busyCollections.remove(collectionId) }
        let keys = held.media_keys.contains(key) ? held.media_keys.filter { $0 != key } : [key] + held.media_keys
        guard let request = PassportSaves.collectionUpdateRequest(userId: userId, id: held.id, keys: keys, accessToken: token),
              let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              // No row back is no change: the collection was deleted elsewhere, or is not this account's.
              let changed = (try? JSONDecoder().decode([PnvCollection].self, from: data))?.first,
              auth.session?.userId == userId,
              let now = collections.firstIndex(where: { $0.id == held.id }) else { return false }
        collections[now] = changed
        return true
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

    private func add(_ ref: String, wing: String, title: String?, href: String) async -> Bool {
        guard let userId = auth.session?.userId, let token = try? await auth.validAccessToken(),
              let request = PassportSaves.insertRequest(userId: userId, ref: ref, wing: wing, title: title, href: href, accessToken: token) else { return false }
        refs.insert(ref)
        if !rows.contains(where: { $0.object_ref == ref }) {
            rows.insert(PassportSave(object_ref: ref, wing: wing, title: title, href: href), at: 0)
        }
        let reply = try? await urlSession.data(for: request)
        let code = (reply?.1 as? HTTPURLResponse)?.statusCode ?? 0
        // A unique-key refusal (23505) means the account already holds it, the state wanted.
        if code == 201 || code == 204 { return true }
        if code == 409, let body = reply?.0, String(decoding: body, as: UTF8.self).contains("23505") { return true }
        refs.remove(ref)
        rows.removeAll { $0.object_ref == ref }
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
