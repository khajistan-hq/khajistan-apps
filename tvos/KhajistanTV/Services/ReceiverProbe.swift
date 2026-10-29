import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Checks a stream before a row is shown, when `health.json` is stale or did not load.
/// One memory for the session: a pass or a failure is kept for about ten minutes, then checked again.
/// At most `cap` checks run at once, across every list asking at the same time.
final class ReceiverProbe: @unchecked Sendable {
    /// How long one playlist or first-bytes read may take.
    static let timeout: TimeInterval = 6
    /// How long a pass or a failure is remembered.
    static let memory: TimeInterval = 600
    /// How many checks run at once.
    static let cap = 8

    private struct Entry {
        let live: Bool
        let at: Date
    }

    /// One shared cap. A waiter takes the slot of the check that just finished.
    private final class Slots: @unchecked Sendable {
        private var used = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private let lock = NSLock()
        private let cap: Int

        init(cap: Int) { self.cap = cap }

        func acquire() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if used < cap {
                    used += 1
                    lock.unlock()
                    cont.resume()
                } else {
                    waiters.append(cont)
                    lock.unlock()
                }
            }
        }

        func release() {
            lock.lock()
            if let next = waiters.first {
                waiters.removeFirst()
                lock.unlock()
                next.resume()
            } else {
                used -= 1
                lock.unlock()
            }
        }
    }

    private var cache: [String: Entry] = [:]
    private let lock = NSLock()
    private let slots = Slots(cap: ReceiverProbe.cap)
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.timeout
            config.timeoutIntervalForResource = Self.timeout + 2
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    func remember(_ id: String, live: Bool, now: Date = Date()) {
        lock.lock()
        cache[id] = Entry(live: live, at: now)
        lock.unlock()
    }

    func forget(_ id: String) {
        lock.lock()
        cache[id] = nil
        lock.unlock()
    }

    /// Probes `channels` and returns the ids that are live, including ones still inside the memory.
    func verify(_ channels: [Channel]) async -> Set<String> {
        let pending = channels.filter { cached($0.id) == nil }
        let session = self.session
        await withTaskGroup(of: Void.self) { group in
            for channel in pending {
                await slots.acquire()
                group.addTask { [slots] in
                    defer { slots.release() }
                    let live = await ReceiverProbe.sample(channel, session: session)
                    self.remember(channel.id, live: live)
                }
            }
            await group.waitForAll()
        }
        return Set(channels.map(\.id).filter { cached($0) == true })
    }

    private func cached(_ id: String, now: Date = Date()) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[id] else { return nil }
        if now.timeIntervalSince(entry.at) >= Self.memory {
            cache[id] = nil
            return nil
        }
        return entry.live
    }

    /// Resolves the carrier, then reads an HLS playlist or the first bytes of anything else.
    /// A live mount is cancelled as soon as those bytes arrive, so a radio stream is not downloaded.
    private static func sample(_ channel: Channel, session: URLSession) async -> Bool {
        guard let stream = channel.activeStream else { return false }
        let hls = stream.format?.lowercased() == "hls"
        do {
            var request = URLRequest(url: ReceiverRules.carrierURL(streamID: stream.id), timeoutInterval: timeout)
            request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let url = try? ReceiverRules.carrier(from: data) else { return false }
            return await read(url, hls: hls, session: session)
        } catch {
            return false
        }
    }

    private static func read(_ url: URL, hls: Bool, session: URLSession) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            let type = (http.mimeType ?? http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let playlist = hls || url.path.lowercased().contains(".m3u8")
                || type.contains("mpegurl") || type.contains("m3u8")
            var data = Data()
            let limit = playlist ? 512 : 64
            for try await byte in bytes {
                data.append(byte)
                if playlist {
                    if data.count >= 7 && ReceiverRules.playlistIsLive(data) { return true }
                    if data.count >= limit { return ReceiverRules.playlistIsLive(data) }
                } else if !data.isEmpty {
                    return true
                }
            }
            return playlist ? ReceiverRules.playlistIsLive(data) : !data.isEmpty
        } catch {
            return false
        }
    }
}
