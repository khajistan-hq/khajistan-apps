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
    /// How long a pass or a failure is remembered. The playback URL outlives this while the id stays verified.
    static let memory: TimeInterval = ReceiverRules.verdictMemory
    /// How many checks run at once.
    static let cap = 8

    private struct Entry {
        var live: Bool
        var at: Date
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
    /// The carrier a live probe checked. Not cleared when the verdict ages out, so a tune
    /// eleven minutes later still has it while the id is verified. `forget`, a dead verdict,
    /// and `dropMemory` clear it.
    private var playbacks: [String: URL] = [:]
    /// Each remember or forget takes the next number under the lock, so a later call wins.
    /// The map is not cleared when memory is dropped. `writeEpoch` moves instead, so a write
    /// that was already in flight cannot match a generation that would otherwise start again at 1.
    private var generation: [String: Int] = [:]
    private var writeEpoch = 0
    private var hosts = ReceiverRules.HostBudget()
    private let lock = NSLock()
    private let slots = Slots(cap: ReceiverProbe.cap)
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            let limit = ReceiverRules.probeOuterWait(timeout: Self.timeout)
            config.timeoutIntervalForRequest = limit
            config.timeoutIntervalForResource = limit
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    /// The epoch and generation of one write. Both have to still be current for the commit to land.
    private struct WriteTicket {
        var epoch: Int
        var generation: Int
    }

    /// The next write for `id`. A later begin, or a drop, makes an earlier commit miss.
    private func beginWrite(_ id: String) -> WriteTicket {
        lock.lock()
        defer { lock.unlock() }
        let next = (generation[id] ?? 0) + 1
        generation[id] = next
        return WriteTicket(epoch: writeEpoch, generation: next)
    }

    /// Lands only when the ticket's epoch and generation are still current. An overtaken write does nothing.
    @discardableResult
    private func commit(_ id: String, live: Bool?, ticket: WriteTicket, playback: URL? = nil, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ticket.epoch == writeEpoch, ticket.generation == generation[id] else { return false }
        if let live {
            cache[id] = Entry(live: live, at: now)
            if live, let playback {
                playbacks[id] = playback
            }
            if !live { playbacks[id] = nil }
        } else {
            cache[id] = nil
            playbacks[id] = nil
        }
        return true
    }

    func remember(_ id: String, live: Bool, now: Date = Date()) async {
        let ticket = beginWrite(id)
        commit(id, live: live, ticket: ticket, now: now)
    }

    func forget(_ id: String) async {
        let ticket = beginWrite(id)
        commit(id, live: nil, ticket: ticket, now: Date())
    }

    /// The carrier and the verdict time, taken under one lock. A tune builds `CarrierMemory`
    /// only from this pair, so a fresh time cannot be matched with the previous URL.
    func remembered(_ id: String, now: Date = Date()) -> ReceiverRules.CarrierSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let entry = cache[id]
        let read = ReceiverRules.rememberedSnapshot(
            playback: playbacks[id], verdictAt: entry?.at, live: entry.map(\.live), now: now, memory: Self.memory
        )
        if read.dropVerdict { cache[id] = nil }
        return read.snapshot
    }

    /// Drops every remembered verdict and moves the epoch. Generation numbers are not reused,
    /// so an in-flight commit from before the drop cannot land on the next probe.
    func dropMemory() {
        lock.lock()
        cache.removeAll()
        playbacks.removeAll()
        writeEpoch += 1
        lock.unlock()
    }

    /// Probes `channels`. `found` runs as soon as one row passes, not after the whole list.
    /// `bypassCache` reads the network even when a recent verdict is remembered.
    /// `live` is who passed. `unprobed` is who never started, including after the in-walk retry.
    /// A slot that does not free in time does not drop the rest of the list on the floor.
    func verify(_ channels: [Channel], bypassCache: Bool = false,
                retriesLeft: Int = ReceiverRules.HostBudget.retryLimit,
                found: @escaping @Sendable (String) async -> Void = { _ in }) async -> (live: Set<String>, unprobed: Set<String>, skipped: Set<String>) {
        let pending = bypassCache ? channels : channels.filter { cached($0.id) == nil }
        let session = self.session
        let skipped = SkipBox()
        let probedSkip = IDBox()
        var neverStarted: [Channel] = []
        await withTaskGroup(of: Void.self) { group in
            for (index, channel) in pending.enumerated() {
                if Task.isCancelled {
                    neverStarted = ReceiverRules.unstarted(pending, from: index)
                    break
                }
                let acquired = await slots.acquire(within: ReceiverRules.slotWait(timeout: Self.timeout))
                if !acquired || Task.isCancelled {
                    if acquired { slots.release() }
                    neverStarted = ReceiverRules.unstarted(pending, from: index)
                    break
                }
                group.addTask { [slots] in
                    defer { slots.release() }
                    if Task.isCancelled { return }
                    let ticket = self.beginWrite(channel.id)
                    let sample = await ReceiverProbe.sample(channel, session: session, gate: self)
                    if Task.isCancelled { return }
                    switch sample.mark {
                    case .live:
                        guard self.commit(channel.id, live: true, ticket: ticket, playback: sample.playback) else { return }
                        await found(channel.id)
                    case .dead:
                        self.commit(channel.id, live: false, ticket: ticket)
                    case .skipped:
                        skipped.insert(channel)
                        probedSkip.insert(channel.id)
                    }
                }
            }
            await group.waitForAll()
        }
        for channel in neverStarted { skipped.insert(channel) }
        let again = skipped.take()
        if ReceiverRules.awaitHostRetry(skipped: again.count, retriesLeft: retriesLeft, cancelled: Task.isCancelled) {
            try? await Task.sleep(for: .seconds(ReceiverRules.HostBudget.backoff))
            // A cancelled wait commits nothing. The walk that owns this retry is the one that was cancelled.
            if !Task.isCancelled {
                let nested = await verify(again, bypassCache: true, retriesLeft: retriesLeft - 1, found: found)
                let live = Set(channels.map(\.id).filter { cached($0) == true })
                return (live, nested.unprobed, nested.skipped)
            }
        }
        let live = Set(channels.map(\.id).filter { cached($0) == true })
        let unprobed = Set(neverStarted.map(\.id))
        return (live, unprobed, probedSkip.take().subtracting(live))
    }

    private final class IDBox: @unchecked Sendable {
        private var values: Set<String> = []
        private let lock = NSLock()
        func insert(_ id: String) {
            lock.lock()
            values.insert(id)
            lock.unlock()
        }
        func take() -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            let copy = values
            values = []
            return copy
        }
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
            // The playback URL stays. A tune while this id is still verified must not see a miss.
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

    private struct Sample {
        var mark: ReceiverRules.ProbeMark
        /// The carrier that was probed, and only when every rendition of it passed.
        var playback: URL?
    }

    /// Resolves the carrier, then reads an HLS playlist or a timed sample of anything else.
    /// A master is live only when every rendition is. The player later opens this same carrier,
    /// so it cannot choose a variant the probe did not read.
    /// A quiet socket cannot hold a slot: the outer wait is just longer than the sample, so a
    /// read that is still delivering bytes is not replaced with a dead verdict.
    private static func sample(_ channel: Channel, session: URLSession, gate: ReceiverProbe) async -> Sample {
        guard let stream = channel.activeStream else { return Sample(mark: .dead, playback: nil) }
        let hls = stream.format?.lowercased() == "hls"
        let carrier: URL
        do {
            var request = URLRequest(url: ReceiverRules.carrierURL(streamID: stream.id), timeoutInterval: timeout)
            request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let url = try? ReceiverRules.carrier(from: data) else { return Sample(mark: .dead, playback: nil) }
            carrier = url
        } catch {
            return Sample(mark: Task.isCancelled ? .skipped : .dead, playback: nil)
        }
        let host = carrier.host?.lowercased() ?? ""
        switch gate.admit(host) {
        case .skip, .giveUp:
            return Sample(mark: .skipped, playback: nil)
        case .go:
            break
        }
        let read = await bounded(carrier, hls: hls, session: session)
        let outcome = await renditions(read, session: session, depth: 0)
        gate.finish(host: host, throttled: outcome.throttled)
        if Task.isCancelled { return Sample(mark: .skipped, playback: nil) }
        let playback = outcome.mark == .live ? carrier : nil
        return Sample(mark: outcome.mark, playback: playback)
    }

    private struct Outcome {
        var mark: ReceiverRules.ProbeMark
        var throttled: Bool
    }

    /// Every `#EXT-X-STREAM-INF` and `#EXT-X-MEDIA` URI, including a master that points at another
    /// master, up to `masterDepth`. One dead rendition fails the carrier. A 403 or a cancelled
    /// read is skipped, not stored as dead.
    private static func renditions(_ read: Read, session: URLSession, depth: Int) async -> Outcome {
        if read.cancelled || Task.isCancelled { return Outcome(mark: .skipped, throttled: false) }
        if read.status == 403 || read.status == 429 { return Outcome(mark: .skipped, throttled: true) }
        guard let status = read.status, (200..<300).contains(status) else {
            return Outcome(mark: .dead, throttled: false)
        }
        if !read.playlist {
            let live = ReceiverRules.responseIsLive(status: status, contentType: read.contentType, body: read.data,
                                                     hls: false, signal: read.signal)
            return Outcome(mark: live ? .live : .dead, throttled: false)
        }
        let playlist = ReceiverRules.FetchedPlaylist(data: read.data, finalURL: read.finalURL, truncated: read.truncated)
        switch ReceiverRules.nextRendition(playlist) {
        case .media(let ok):
            return Outcome(mark: ok ? .live : .dead, throttled: false)
        case .master(let urls):
            if depth >= ReceiverRules.masterDepth || urls.isEmpty {
                return Outcome(mark: .dead, throttled: false)
            }
            for url in urls {
                if Task.isCancelled { return Outcome(mark: .skipped, throttled: false) }
                let child = await bounded(url, hls: true, session: session)
                let outcome = await renditions(child, session: session, depth: depth + 1)
                if outcome.mark != .live { return outcome }
            }
            return Outcome(mark: .live, throttled: false)
        }
    }

    private struct Read {
        var status: Int?
        var data: Data
        var finalURL: URL
        var truncated: Bool
        var cancelled: Bool
        var signal: ReceiverRules.StreamSignal
        var contentType: String?
        var playlist: Bool
    }

    private static func emptyRead(_ url: URL, playlist: Bool, cancelled: Bool) -> Read {
        Read(status: nil, data: Data(), finalURL: url, truncated: false, cancelled: cancelled,
             signal: ReceiverRules.StreamSignal(), contentType: nil, playlist: playlist)
    }

    private static func bounded(_ url: URL, hls: Bool, session: URLSession) async -> Read {
        await withTaskGroup(of: Read?.self) { group in
            group.addTask { await read(url, hls: hls, session: session) }
            group.addTask {
                // Longer than the sample, so a mount that is still sending is judged by the sample.
                try? await Task.sleep(for: .seconds(ReceiverRules.probeOuterWait(timeout: timeout)))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? emptyRead(url, playlist: hls, cancelled: true)
        }
    }

    private static func read(_ url: URL, hls: Bool, session: URLSession) async -> Read {
        var request = URLRequest(url: url, timeoutInterval: ReceiverRules.probeOuterWait(timeout: timeout))
        request.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { return emptyRead(url, playlist: hls, cancelled: false) }
            let finalURL = http.url ?? url
            let type = http.mimeType ?? http.value(forHTTPHeaderField: "Content-Type")
            let playlist = hls || finalURL.path.lowercased().contains(".m3u8") || url.path.lowercased().contains(".m3u8")
                || (type ?? "").lowercased().contains("mpegurl") || (type ?? "").lowercased().contains("m3u8")
            if http.statusCode == 403 || http.statusCode == 429 {
                return Read(status: http.statusCode, data: Data(), finalURL: finalURL, truncated: false, cancelled: false,
                            signal: ReceiverRules.StreamSignal(), contentType: type, playlist: playlist)
            }
            var data = Data()
            var count = 0
            let endTag = Data("#EXT-X-ENDLIST".utf8)
            var hitCap = false
            var stillArriving = false
            var cancelled = false
            let started = Date()
            let deadline = started.addingTimeInterval(ReceiverRules.streamMinDuration)
            let storeCap = playlist ? ReceiverRules.playlistReadCap : ReceiverRules.streamFirstBytes
            do {
                for try await byte in bytes {
                    if Task.isCancelled {
                        cancelled = true
                        break
                    }
                    // A non-HLS body is still a stream only when a byte arrives at the sample deadline.
                    // Stopping at a byte cap is not that, and a body that ends before the deadline is a file.
                    if !playlist && Date() >= deadline {
                        stillArriving = true
                        count += 1
                        if data.count < storeCap { data.append(byte) }
                        break
                    }
                    count += 1
                    if data.count < storeCap { data.append(byte) }
                    if playlist {
                        if data.count.isMultiple(of: 4096), data.range(of: endTag) != nil { break }
                        if data.count >= ReceiverRules.playlistReadCap {
                            hitCap = true
                            break
                        }
                    }
                }
            } catch is CancellationError {
                cancelled = true
            } catch {
                let timedOut = (error as? URLError)?.code == .timedOut
                if ReceiverRules.failedReadIsCancelled(timedOut: timedOut, taskCancelled: Task.isCancelled) {
                    cancelled = true
                } else {
                    return emptyRead(url, playlist: playlist, cancelled: false)
                }
            }
            if Task.isCancelled { cancelled = true }
            let sawEnd = playlist && data.range(of: endTag) != nil
            let truncated = playlist && hitCap && !sawEnd
            // A playlist that hit its cap is unfinished, not a stream that is still open.
            // A non-HLS body ends unless a byte was still arriving at the deadline.
            let bodyEnded = playlist ? (!hitCap && !cancelled) : (!stillArriving && !cancelled)
            let icy = http.allHeaderFields.keys.contains { "\($0)".lowercased().hasPrefix("icy-") }
            let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
            let chunked = (http.value(forHTTPHeaderField: "Transfer-Encoding") ?? "").lowercased().contains("chunked")
            let signal = ReceiverRules.StreamSignal(
                icy: icy, contentLength: length, chunked: chunked, openEnded: length == nil && !chunked,
                bodyEnded: bodyEnded, stillArriving: stillArriving, elapsed: Date().timeIntervalSince(started), bytes: count)
            return Read(status: http.statusCode, data: data, finalURL: finalURL, truncated: truncated, cancelled: cancelled,
                        signal: signal, contentType: type, playlist: playlist)
        } catch is CancellationError {
            return emptyRead(url, playlist: hls, cancelled: true)
        } catch {
            let timedOut = (error as? URLError)?.code == .timedOut
            return emptyRead(url, playlist: hls, cancelled: ReceiverRules.failedReadIsCancelled(timedOut: timedOut, taskCancelled: Task.isCancelled))
        }
    }
}
