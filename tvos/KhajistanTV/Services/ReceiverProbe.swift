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
        private var waiters: [(Ticket, CheckedContinuation<Bool, Never>)] = []
        private let lock = NSLock()
        private let cap: Int

        init(cap: Int) { self.cap = cap }

        /// True when a slot was taken. False when `seconds` passed with none free, so a leaked
        /// slot cannot stall the walk. A timed-out waiter is dropped and not resumed later.
        /// If the slot was taken in the same moment the deadline won, it is given back.
        func acquire(within seconds: Double) async -> Bool {
            let ticket = Ticket()
            return await withTaskGroup(of: Bool.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return false }
                    return await self.acquireTicket(ticket)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(seconds))
                    return false
                }
                let won = await group.next() ?? false
                group.cancelAll()
                if !won { abandon(ticket) }
                return won
            }
        }

        private func acquireTicket(_ ticket: Ticket) async -> Bool {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                lock.lock()
                if ticket.phase == .dropped {
                    lock.unlock()
                    cont.resume(returning: false)
                    return
                }
                if used < cap {
                    used += 1
                    ticket.phase = .held
                    lock.unlock()
                    cont.resume(returning: true)
                    return
                }
                waiters.append((ticket, cont))
                lock.unlock()
            }
        }

        /// The deadline won. A slot already taken is released. A waiter still queued is resumed
        /// with false. One that has not entered yet is marked so it never takes a slot.
        private func abandon(_ ticket: Ticket) {
            lock.lock()
            switch ticket.phase {
            case .held:
                ticket.phase = .dropped
                lock.unlock()
                release()
            case .dropped:
                lock.unlock()
            case .waiting:
                if let index = waiters.firstIndex(where: { $0.0 === ticket }) {
                    let pair = waiters.remove(at: index)
                    ticket.phase = .dropped
                    lock.unlock()
                    pair.1.resume(returning: false)
                } else {
                    ticket.phase = .dropped
                    lock.unlock()
                }
            }
        }

        func release() {
            lock.lock()
            if waiters.isEmpty {
                used = max(0, used - 1)
                lock.unlock()
                return
            }
            let next = waiters.removeFirst()
            next.0.phase = .held
            lock.unlock()
            next.1.resume(returning: true)
        }
    }

    private final class Ticket {
        enum Phase { case waiting, held, dropped }
        var phase: Phase = .waiting
    }

    private var cache: [String: Entry] = [:]
    /// Each remember or forget takes the next number under the lock, so a later call wins.
    private var generation: [String: Int] = [:]
    private var hosts = ReceiverRules.HostBudget()
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

    /// The next write number for `id`. A later begin makes an earlier commit miss.
    func beginWrite(_ id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = (generation[id] ?? 0) + 1
        generation[id] = next
        return next
    }

    /// Lands only when `gen` is still the current write. An overtaken write does nothing.
    @discardableResult
    func commit(_ id: String, live: Bool?, generation gen: Int, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard gen == generation[id] else { return false }
        if let live {
            cache[id] = Entry(live: live, at: now)
        } else {
            cache[id] = nil
        }
        return true
    }

    func remember(_ id: String, live: Bool, now: Date = Date()) async {
        let gen = beginWrite(id)
        commit(id, live: live, generation: gen, now: now)
    }

    func forget(_ id: String) async {
        let gen = beginWrite(id)
        commit(id, live: nil, generation: gen, now: Date())
    }

    /// Drops every remembered verdict. A stale flip calls this so the next probe is a real read.
    func dropMemory() {
        lock.lock()
        cache.removeAll()
        generation.removeAll()
        lock.unlock()
    }

    /// Probes `channels`. `found` runs as soon as one row passes, not after the whole list.
    /// `bypassCache` reads the network even when a recent verdict is remembered.
    func verify(_ channels: [Channel], bypassCache: Bool = false,
                retriesLeft: Int = ReceiverRules.HostBudget.retryLimit,
                found: @escaping @Sendable (String) async -> Void = { _ in }) async -> Set<String> {
        let pending = bypassCache ? channels : channels.filter { cached($0.id) == nil }
        let session = self.session
        let skipped = SkipBox()
        await withTaskGroup(of: Void.self) { group in
            for channel in pending {
                if Task.isCancelled { break }
                let acquired = await slots.acquire(within: Self.timeout + 2)
                if !acquired || Task.isCancelled {
                    if acquired { slots.release() }
                    break
                }
                group.addTask { [slots] in
                    defer { slots.release() }
                    if Task.isCancelled { return }
                    let gen = self.beginWrite(channel.id)
                    let mark = await ReceiverProbe.sample(channel, session: session, gate: self)
                    if Task.isCancelled { return }
                    switch mark {
                    case .live:
                        guard self.commit(channel.id, live: true, generation: gen) else { return }
                        await found(channel.id)
                    case .dead:
                        self.commit(channel.id, live: false, generation: gen)
                    case .skipped:
                        skipped.insert(channel)
                    }
                }
            }
            await group.waitForAll()
        }
        let again = skipped.take()
        if ReceiverRules.awaitHostRetry(skipped: again.count, retriesLeft: retriesLeft, cancelled: Task.isCancelled) {
            try? await Task.sleep(for: .seconds(ReceiverRules.HostBudget.backoff))
            // A cancelled wait commits nothing. The walk that owns this retry is the one that was cancelled.
            if !Task.isCancelled {
                _ = await verify(again, bypassCache: true, retriesLeft: retriesLeft - 1, found: found)
            }
        }
        return Set(channels.map(\.id).filter { cached($0) == true })
    }

    private func admit(_ host: String, now: Date = Date()) -> ReceiverRules.HostBudget.Admit {
        lock.lock()
        defer { lock.unlock() }
        return hosts.begin(host: host, now: now)
    }

    private func finish(host: String, throttled: Bool, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        hosts.end(host: host, throttled: throttled, now: now)
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

    private final class SkipBox: @unchecked Sendable {
        private var values: [Channel] = []
        private let lock = NSLock()
        func insert(_ channel: Channel) {
            lock.lock()
            values.append(channel)
            lock.unlock()
        }
        func take() -> [Channel] {
            lock.lock()
            defer { lock.unlock() }
            let copy = values
            values = []
            return copy
        }
    }

    /// Resolves the carrier, then reads an HLS playlist or the first bytes of anything else.
    /// A live mount is cancelled as soon as those bytes arrive, so a radio stream is not downloaded.
    /// The whole check gives up at `timeout`, so a quiet socket cannot hold a slot.
    private static func sample(_ channel: Channel, session: URLSession, gate: ReceiverProbe) async -> ReceiverRules.ProbeMark {
        guard let stream = channel.activeStream else { return .dead }
        let hls = stream.format?.lowercased() == "hls"
        let carrier: URL
        do {
            var request = URLRequest(url: ReceiverRules.carrierURL(streamID: stream.id), timeoutInterval: timeout)
            request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let url = try? ReceiverRules.carrier(from: data) else { return .dead }
            carrier = url
        } catch {
            return Task.isCancelled ? .skipped : .dead
        }
        let host = carrier.host?.lowercased() ?? ""
        switch gate.admit(host) {
        case .skip, .giveUp:
            return .skipped
        case .go:
            break
        }
        var read = await bounded(carrier, hls: hls, session: session)
        if let variant = read.variant {
            // A master is not live until its first media playlist passes the same test.
            read = await bounded(variant, hls: true, session: session)
        }
        let throttled = read.status == 403 || read.status == 429
        gate.finish(host: host, throttled: throttled)
        if Task.isCancelled { return .skipped }
        return ReceiverRules.probeMark(status: read.status, skipped: throttled, bodyLive: read.live)
    }

    private struct Read {
        var status: Int?
        var live: Bool
        var variant: URL?
    }

    private static func bounded(_ url: URL, hls: Bool, session: URLSession) async -> Read {
        await withTaskGroup(of: Read?.self) { group in
            group.addTask { await read(url, hls: hls, session: session) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? Read(status: nil, live: false, variant: nil)
        }
    }

    private static func read(_ url: URL, hls: Bool, session: URLSession) async -> Read {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { return Read(status: nil, live: false, variant: nil) }
            if http.statusCode == 403 || http.statusCode == 429 {
                return Read(status: http.statusCode, live: false, variant: nil)
            }
            let type = http.mimeType ?? http.value(forHTTPHeaderField: "Content-Type")
            let playlist = hls || url.path.lowercased().contains(".m3u8")
                || (type ?? "").lowercased().contains("mpegurl") || (type ?? "").lowercased().contains("m3u8")
            var data = Data()
            let limit = playlist ? ReceiverRules.playlistReadCap : 256
            let endTag = Data("#EXT-X-ENDLIST".utf8)
            var hitCap = false
            for try await byte in bytes {
                if Task.isCancelled { break }
                data.append(byte)
                if playlist, data.count.isMultiple(of: 4096), data.range(of: endTag) != nil { break }
                if data.count >= limit {
                    hitCap = true
                    break
                }
            }
            let sawEnd = playlist && data.range(of: endTag) != nil
            let truncated = playlist && hitCap && !sawEnd
            let bodyEnded = !hitCap && !Task.isCancelled
            if playlist, ReceiverRules.isMasterPlaylist(data),
               let variant = ReceiverRules.firstVariantURL(in: data, relativeTo: url) {
                return Read(status: http.statusCode, live: false, variant: variant)
            }
            let icy = http.allHeaderFields.keys.contains { "\($0)".lowercased().hasPrefix("icy-") }
            let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
            let chunked = (http.value(forHTTPHeaderField: "Transfer-Encoding") ?? "").lowercased().contains("chunked")
            let signal = ReceiverRules.StreamSignal(icy: icy, contentLength: length, chunked: chunked, bodyEnded: bodyEnded)
            let live = ReceiverRules.responseIsLive(status: http.statusCode, contentType: type, body: data, hls: playlist,
                                                     playlistTruncated: truncated, signal: signal)
            return Read(status: http.statusCode, live: live, variant: nil)
        } catch {
            return Read(status: nil, live: false, variant: nil)
        }
    }
}
