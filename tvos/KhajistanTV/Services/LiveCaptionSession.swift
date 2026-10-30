import Foundation
import UIKit
import Observation
#if DEBUG && canImport(os)
import os
#endif

/// Live captions on a receiver channel: archive/scripts/kj-captions-live.js on the television.
///
/// The account is the meter and the server keeps it (request-captions): a signed-in, confirmed
/// account, info@ and saad@ uncapped, everyone else ten minutes once. This asks the viewer to sign
/// in before spending a round trip, registers demand with "start", keeps it with a heartbeat inside
/// the 90-second lease, releases it with "stop", and paints what the server says is left. Cues
/// arrive on the realtime postgres_changes subscription to `live_caption_wire`, with the site's REST
/// read of the last thirty seconds as recovery, and are placed on the media clock with the picture
/// held back so a line lands with the speech. English only, as the receiver is.
///
/// What the site's captions menu carries and the television does not: the spoken-language picker
/// (sixty languages in a list), "Not this language?" (a vote is a write), "How accurate?", and
/// "Get an hour of captions · $5" (buying happens on the website).
@MainActor @Observable
final class LiveCaptionSession {
    /// The channel offers captions: the control is shown.
    private(set) var offered = false
    private(set) var isOn = false
    private(set) var label = "Captions"
    /// The site's `#captions-note` line: a refusal, a reason, the countdown to the first line.
    private(set) var note = ""
    /// What is on screen now.
    private(set) var text: String?

    @ObservationIgnored private let auth: AuthStore
    @ObservationIgnored private weak var player: PlayerController?
    @ObservationIgnored private var channel: Channel?
    @ObservationIgnored private var detected: DetectedLanguage?
    @ObservationIgnored private static var accuracy: CaptionAccuracy?
    @ObservationIgnored private var balance: Double?
    @ObservationIgnored private var billingSession: String?
    /// Bumped by every start and stop; work that carries an older number is dropped.
    @ObservationIgnored private var generation = 0
    /// Channel metadata remains valid across caption toggles, but never across a new attachment.
    @ObservationIgnored private var attachment = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var leaseTask: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var timeline = CaptionTimeline()
    @ObservationIgnored private var socketSubscribed = false
    @ObservationIgnored private var needsRecovery = true
    @ObservationIgnored private var resyncing = false
    @ObservationIgnored private var seekSerial = 0
    @ObservationIgnored private var seekDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var translationTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var seen = Set<Int>()
    @ObservationIgnored private var seenOrder: [Int] = []
    @ObservationIgnored private var received = 0
    @ObservationIgnored private var lastReceivedAt = Date.distantPast
    @ObservationIgnored private var recoveryGeneration: Int?
    @ObservationIgnored private var lags: [Double] = []
    @ObservationIgnored private var lastResync = Date.distantPast
    /// Rows waiting for their English, in arrival order, so a late translation never overtakes.
    @ObservationIgnored private var waiting: [(seq: Int, row: CaptionWireRow, english: String?, ready: Bool, canAdjust: Bool, deadline: ContinuousClock.Instant)] = []
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var firstAt: Double?
    /// The count has reached the first line and stops there.
    @ObservationIgnored private var counted = false
    @ObservationIgnored private var estimateAt: Date?
    @ObservationIgnored private var countSaid = ""
    private let urlSession: URLSession

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    private var viewerId: String {
        if let held = UserDefaults.standard.string(forKey: CaptionRules.viewerKey) { return held }
        let fresh = "v" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20)
        UserDefaults.standard.set(fresh, forKey: CaptionRules.viewerKey)
        return fresh
    }

    // Numeric-only DEBUG telemetry: 1 receive, 2 English update, 3 placement,
    // 4 display change, 5 seek start, 6 seek completion, 7 seek timeout,
    // 8 translation expiry, 9 stop. Never log text, channel/account IDs or tokens.
    #if DEBUG && canImport(os)
    private static let diagnosticLog = Logger(subsystem: "org.khajistan.receiver", category: "CaptionTiming")
    #endif
    private func trace(_ event: Int, row: CaptionWireRow? = nil, source: Double = .nan,
                       display: Double = .nan, cue: SubtitleCue? = nil, value: Double = 0) {
        #if DEBUG && canImport(os)
        let clock = player?.captionClock
        let created = row?.created_at.flatMap(CaptionRules.isoDate)?.timeIntervalSince1970 ?? .nan
        Self.diagnosticLog.notice("event=\(event) gen=\(self.generation) row=\(row?.id ?? -1) wall=\(Date().timeIntervalSince1970) created=\(created) epoch=\(row?.at_epoch ?? .nan) programme=\(row?.program_epoch ?? .nan) media=\(clock?.now ?? .nan) playerProgramme=\(clock?.programDate?.timeIntervalSince1970 ?? .nan) hold=\(clock?.behindLive ?? .nan) low=\(clock?.window?.lowerBound ?? .nan) high=\(clock?.window?.upperBound ?? .nan) source=\(source) display=\(display) start=\(cue?.start ?? .nan) end=\(cue?.end ?? .nan) chars=\(cue?.text.count ?? 0) waiting=\(self.waiting.count) dropped=\(self.timeline.dropped) value=\(value)")
        #endif
    }

    // MARK: - Attach and detach (the receiver's attach() / detach())

    /// A channel was tuned on `player`. A live carrier in a language the recogniser takes offers
    /// the control; anything else says why in one line, or nothing.
    func attach(_ target: Channel, player: PlayerController) {
        self.player?.onPlaybackUnavailable = nil
        stop("")
        attachment += 1
        channel = target
        self.player = player
        player.onPlaybackUnavailable = { [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            self.suspendForPlaybackInterruption()
        }
        detected = nil
        decide()
        label = CaptionRules.label(on: false, balance: balance)
        let gen = attachment
        Task { await self.pullDetectedLanguage(target, generation: gen) }
        Task { await self.loadAccuracy(target, generation: gen) }
        guard offered else { return }
        askBalance()
        // Opening Receiver or changing channel never spends a caption allowance.
        // Starting live captions requires a deliberate press on CC for this channel.
    }

    /// Keep the channel attached, but require a deliberate CC press after playback returns.
    func suspendForPlaybackInterruption() {
        guard isOn || billingSession != nil else { return }
        stop("Captions stopped. Turn CC on again after playback resumes.")
    }

    func detach() {
        player?.onPlaybackUnavailable = nil
        stop("")
        attachment += 1
        channel = nil
        offered = false
        note = ""
    }

    private func decide() {
        guard let channel else { offered = false; return }
        offered = CaptionRules.eligible(channel, detected: detected, accuracy: Self.accuracy)
        note = offered ? "" : CaptionRules.parkedReason(channel, detected: detected, accuracy: Self.accuracy)
    }

    func toggle() {
        guard offered else {
            note = channel.map { CaptionRules.parkedReason($0, detected: detected, accuracy: Self.accuracy) } ?? "Captions are unavailable for this channel."
            return
        }
        if isOn {
            UserDefaults.standard.set("off", forKey: CaptionRules.modeKey)
            stop("Captions off.")
        } else {
            turnOn()
        }
    }

    // MARK: - On (setMode("english") from off)

    private func turnOn() {
        guard let channel, let player else { return }
        guard player.state == .playing else {
            note = "Wait for the signal to connect before turning captions on."
            return
        }
        guard offered else {
            note = CaptionRules.parkedReason(channel, detected: detected, accuracy: Self.accuracy)
            return
        }
        // The server refuses the anon key with sign_in_required anyway; asking here saves the trip.
        #if DEBUG
        // Caption UI fixtures never start paid demand, even on a simulator with a saved account.
        if UserDefaults.standard.bool(forKey: "kjcaptiontestsignedout") {
            note = CaptionRules.billingReason("sign_in_required") ?? ""
            return
        }
        #endif
        guard auth.isSignedIn else {
            note = CaptionRules.billingReason("sign_in_required") ?? ""
            return
        }
        UserDefaults.standard.set("english", forKey: CaptionRules.modeKey)
        generation += 1
        let gen = generation
        if billingSession == nil { billingSession = UUID().uuidString.lowercased() }
        isOn = true
        note = ""
        timeline = CaptionTimeline(); seen = []; seenOrder = []; received = 0; lastReceivedAt = .distantPast; lags = []; waiting = []
        lastResync = .distantPast
        label = CaptionRules.label(on: true, balance: balance)
        firstAt = nil
        counted = false
        estimateAt = Date().addingTimeInterval(CaptionRules.firstLineSeconds)
        resync()

        tasks.append(Task { await self.start(channel, generation: gen) })
        tasks.append(Task { await self.openSocket(channel.id, generation: gen) })
        tasks.append(Task { await self.recoverLoop(channel.id, generation: gen) })
        tasks.append(Task { await self.tick(player, generation: gen) })
    }

    private func start(_ channel: Channel, generation gen: Int) async {
        let res = await ask("start")
        guard gen == generation else { return }
        guard let res else {
            // The demand may have registered and only the answer been lost: beat anyway.
            tasks.append(Task { await self.heartbeat(every: 30, generation: gen) })
            return
        }
        acceptBilling(res)
        guard isOn, gen == generation else { return }
        if res.allowed == false {
            stop(CaptionRules.startRefusal(res.reason))
            return
        }
        tasks.append(Task { await self.heartbeat(every: res.heartbeat_seconds ?? 30, generation: gen) })
    }

    private func heartbeat(every seconds: Double, generation gen: Int) async {
        let interval = max(10, min(60, seconds == 0 ? 30 : seconds))
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            guard gen == generation, isOn else { return }
            let res = await ask("heartbeat")
            guard gen == generation, isOn else { return }
            guard let res else { continue }
            acceptBilling(res)
            if res.allowed == false { stop(CaptionRules.heartbeatRefusal(res.reason)); return }
        }
    }

    /// acceptBilling(): an enforced reply renews the lease and says what is left.
    private func acceptBilling(_ res: CaptionReply) {
        if res.billing_mode == "legacy" { balance = nil; leaseTask?.cancel(); return }
        guard res.billing_mode == "enforced", res.allowed != false, isOn else { return }
        guard let session = billingSession, let expiry = CaptionRules.leaseExpiry(of: res, session: session, now: Date()) else {
            stop(CaptionRules.renewFailed)
            return
        }
        balance = CaptionRules.balance(of: res)
        label = CaptionRules.label(on: true, balance: balance, reserved: res.reserved_seconds ?? 0)
        leaseTask?.cancel()
        let gen = generation
        leaseTask = Task {
            try? await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow)))
            guard !Task.isCancelled, gen == self.generation, self.isOn else { return }
            self.stop(CaptionRules.leaseExpired)
        }
    }

    /// action "balance": what the account has left, no worker started.
    private func askBalance() {
        guard auth.isSignedIn else { return }
        let gen = generation
        Task {
            guard let res = await ask("balance"), gen == generation, !isOn else { return }
            guard res.allowed == true, res.billing_mode == "enforced",
                  res.unlimited == true || res.remaining_seconds != nil else { return }
            balance = CaptionRules.balance(of: res)
            label = CaptionRules.label(on: false, balance: balance)
        }
    }

    private func ask(_ action: String) async -> CaptionReply? {
        guard let channel else { return nil }
        let gen = generation
        let session = billingSession
        guard let token = try? await auth.validAccessToken(), !Task.isCancelled,
              gen == generation, self.channel?.id == channel.id else { return nil }
        let request = CaptionRules.demandRequest(action: action, channelId: channel.id, viewerId: viewerId,
                                                 sessionId: session, accessToken: token)
        guard let (data, _) = try? await urlSession.data(for: request) else { return nil }
        return try? JSONDecoder().decode(CaptionReply.self, from: data)
    }

    // MARK: - Off (stop())

    /// Every teardown releases the demand, so the paid worker stops for nobody watching.
    private func stop(_ why: String) {
        trace(9)
        let wasOn = isOn || billingSession != nil
        generation += 1
        if resyncing { player?.cancelCaptionSeek() }
        tasks.forEach { $0.cancel() }
        tasks = []
        leaseTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if wasOn, let channel {
            let request = (channel.id, viewerId, billingSession)
            Task {
                guard let token = try? await auth.validAccessToken() else { return }
                _ = try? await urlSession.data(for: CaptionRules.demandRequest(
                    action: "stop", channelId: request.0, viewerId: request.1, sessionId: request.2, accessToken: token))
            }
        }
        billingSession = nil
        isOn = false
        timeline = CaptionTimeline()
        socketSubscribed = false
        resyncing = false
        seekDeadline = nil
        recoveryGeneration = nil
        translationTasks.values.forEach { $0.cancel() }
        translationTasks = [:]
        waiting = []
        text = nil
        firstAt = nil
        estimateAt = nil
        label = "Captions"
        note = why
    }

    // MARK: - The wire

    private func openSocket(_ channelId: String, generation gen: Int) async {
        var failures = 0
        while gen == generation, isOn, !Task.isCancelled {
            let subscribed = await connectSocket(channelId, generation: gen)
            guard gen == generation, isOn, !Task.isCancelled else { return }
            failures = subscribed ? 0 : min(failures + 1, 3)
            try? await Task.sleep(for: .seconds(pow(2, Double(failures))))
        }
    }

    /// One connection owns its heartbeat and join deadline. Recovery never blocks live reads.
    private func connectSocket(_ channelId: String, generation gen: Int) async -> Bool {
        guard let token = try? await auth.validAccessToken(), gen == generation, isOn, !Task.isCancelled else { return false }
        let task = urlSession.webSocketTask(with: CaptionRealtime.socketURL())
        socket = task
        socketSubscribed = false
        task.resume()
        var didSubscribe = false
        let joinDeadline = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, gen == self.generation, self.socket === task, !self.socketSubscribed else { return }
            task.cancel(with: .goingAway, reason: nil)
        }
        let beat = Task {
            var ref = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, gen == self.generation, self.socket === task else { return }
                do { try await task.send(.string(CaptionRealtime.heartbeat(ref: String(ref)))) }
                catch { task.cancel(with: .goingAway, reason: nil); return }
                ref += 1
            }
        }
        defer {
            joinDeadline.cancel()
            beat.cancel()
            task.cancel(with: .goingAway, reason: nil)
            if socket === task { socket = nil; socketSubscribed = false }
        }
        do {
            try await task.send(.string(CaptionRealtime.join(channelId: channelId, accessToken: token, ref: "1")))
            while gen == generation, isOn, !Task.isCancelled {
                let message = try await task.receive()
                guard gen == generation, isOn, !Task.isCancelled else { return didSubscribe }
                guard case .string(let frame) = message else { continue }
                switch CaptionRealtime.event(frame, channelId: channelId) {
                case .subscribed:
                    needsRecovery = true
                    didSubscribe = true
                    socketSubscribed = true
                    joinDeadline.cancel()
                    // The recovery loop fills gaps independently of the websocket reader.
                case .row(let row): receive(row)
                case .closed: return didSubscribe
                case .other: continue
                }
            }
        } catch { /* The outer loop reconnects; recovery remains active meanwhile. */ }
        return didSubscribe
    }

    private func recoverLoop(_ channelId: String, generation gen: Int) async {
        while !Task.isCancelled, gen == generation, isOn {
            // A dead or silently stalled socket must not turn captions into 15-second batches.
            if needsRecovery || !socketSubscribed || received == 0 || Date().timeIntervalSince(lastReceivedAt) > 3 {
                needsRecovery = false
                await recover(channelId, generation: gen)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func recover(_ channelId: String, generation gen: Int) async {
        guard recoveryGeneration != gen, gen == generation, isOn, !Task.isCancelled else { return }
        recoveryGeneration = gen
        defer { if recoveryGeneration == gen { recoveryGeneration = nil } }
        guard let token = try? await auth.validAccessToken(), gen == generation, isOn, !Task.isCancelled else { return }
        let request = CaptionRules.wireRequest(channelId: channelId, now: Date(), accessToken: token)
        guard let (data, response) = try? await urlSession.data(for: request), gen == generation, isOn, !Task.isCancelled,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([CaptionWireRow].self, from: data) else { return }
        rows.reversed().forEach { receive($0, recovered: true) }
    }

    /// addCue(): one row, once, English or waiting for it.
    private func receive(_ row: CaptionWireRow, recovered: Bool = false) {
        guard isOn, let channel, CaptionRules.admits(row, channelId: channel.id) else { return }
        if let id = row.id {
            if seen.contains(id) {
                // The worker PATCHes English when its inline translation finishes late.
                // Complete only this still-pending source row; never replay a displayed cue.
                if row.uncertain != true,
                   let index = waiting.firstIndex(where: { $0.row.id == id && !$0.ready && ContinuousClock.now < $0.deadline }),
                   row.text == waiting[index].row.text, row.lang == waiting[index].row.lang,
                   row.program_epoch == waiting[index].row.program_epoch, row.at_epoch == waiting[index].row.at_epoch,
                   let english = CaptionRules.english(for: row) {
                    trace(2, row: row)
                    waiting[index].english = english
                    waiting[index].ready = true
                    translationTasks.removeValue(forKey: waiting[index].seq)?.cancel()
                    flush()
                }
                return
            }
            seen.insert(id)
            seenOrder.append(id)
            if seenOrder.count > 500 { seen.remove(seenOrder.removeFirst()) }
        }
        trace(1, row: row, value: recovered ? 1 : 0)
        lastReceivedAt = Date()
        received += 1
        // The worker withholds English when it could not hear reliably; never invent it.
        if row.uncertain == true { note = CaptionRules.uncertainLine; return }
        let english = CaptionRules.english(for: row)
        // Capture freshness on arrival: waiting for a valid translation must not turn a
        // newly delivered REST row into stale backfill halfway through its deadline.
        let freshRecovery = row.created_at.flatMap(CaptionRules.isoDate).map {
            let age = Date().timeIntervalSince($0)
            return age >= -2 && age <= 5
        } ?? false
        let canAdjust = !recovered || freshRecovery
        guard waiting.count < 200 else { note = "Caption translation is catching up."; return }
        sequence += 1
        let seq = sequence
        let needsTranslation = english == nil && !(row.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        waiting.append((seq, row, english, !needsTranslation, canAdjust, ContinuousClock.now.advanced(by: .seconds(CaptionRules.translationWait))))
        if needsTranslation {
            let gen = generation
            translationTasks[seq] = Task { await self.translate(row, seq: seq, generation: gen) }
        } else {
            flush()
        }
    }

    private func translate(_ row: CaptionWireRow, seq: Int, generation gen: Int) async {
        guard let channel, isOn, gen == generation, !Task.isCancelled else { return }
        let continuation = CaptionContinuation(generation: gen, channelID: channel.id, sessionID: billingSession)
        let code = CaptionRules.effectiveLangCode(channel, detected: detected)
        var english: String?
        if let token = try? await auth.validAccessToken() {
            guard continuation.admits(generation: generation, channelID: self.channel?.id,
                                      sessionID: billingSession, on: isOn, cancelled: Task.isCancelled),
                  waiting.contains(where: { $0.seq == seq && ContinuousClock.now < $0.deadline }) else { return }
            let request = CaptionRules.translateRequest(row: row, channelLang: code, sessionId: continuation.sessionID, accessToken: token)
            if let (data, response) = try? await urlSession.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
               let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let checked = CaptionRules.checkedEnglish(reply["english"] as? String, row: row)
                english = checked.isEmpty ? nil : checked
            }
        }
        guard continuation.admits(generation: generation, channelID: self.channel?.id,
                                  sessionID: billingSession, on: isOn, cancelled: Task.isCancelled),
              let index = waiting.firstIndex(where: { $0.seq == seq && ContinuousClock.now < $0.deadline }) else { return }
        translationTasks.removeValue(forKey: seq)
        // A failed fallback is not the server's final word: its original translation
        // can still arrive as an UPDATE/REST refresh inside this same absolute deadline.
        guard let english else { return }
        waiting[index].english = english
        waiting[index].ready = true
        flush()
    }

    private func flush() {
        guard !resyncing else { return }
        while let head = waiting.first {
            if !head.ready {
                guard ContinuousClock.now >= head.deadline else { return }
                trace(8, row: head.row)
                waiting.removeFirst()
                translationTasks.removeValue(forKey: head.seq)?.cancel()
                note = CaptionRules.untranslatedLine
                continue
            }
            guard emit(head.row, english: head.english, canAdjust: head.canAdjust) else { return }
            waiting.removeFirst()
        }
    }

    // MARK: - Placing a line

    /// emit() and placeByClock() / placeCue(): a programme timestamp where the playlist carries one,
    /// else the row's wall-clock time under the hold. ponytail: hls.js exposes fragment sequence
    /// numbers for the site's `sn` placement and AVPlayer does not; those rows go by the clock.
    /// False means a seek is in flight: retain the row and remap it after completion.
    private func emit(_ row: CaptionWireRow, english: String?, canAdjust: Bool) -> Bool {
        guard isOn, let clock = player?.captionClock else { return true }
        guard let body = english, !body.isEmpty else { note = CaptionRules.untranslatedLine; return true }
        var at: Double?
        if let epoch = row.program_epoch, epoch.isFinite, let date = clock.programDate {
            let mt = clock.now + epoch - date.timeIntervalSince1970
            // Stale recovery rows never rewind the picture. Modest live lateness can be
            // corrected once, then the SAME source anchor is recomputed on the new clock.
            let late = clock.now - mt
            if canAdjust, late > 0.5, late <= CaptionRules.holdMax,
               holdBack(late.rounded(.up) + CaptionRules.holdMargin, clock: clock) { return false }
            at = mt
        } else if let atEpoch = row.at_epoch {
            let lag = Date().timeIntervalSince1970 - atEpoch
            if canAdjust, lag.isFinite, lag >= 0, lag <= CaptionRules.holdMax {
                lags.append(lag)
                if lags.count > 12 { lags.removeFirst() }
                if lag + CaptionRules.holdMargin > clock.behindLive,
                   Date().timeIntervalSince(lastResync) > 60, resync() { return false }
            }
            at = CaptionRules.mediaTime(atEpoch: atEpoch, now: Date().timeIntervalSince1970,
                                       mediaNow: clock.now, behindLive: clock.behindLive)
        }
        guard let sourceTime = at else { return true }
        // A non-seekable radio cannot replay the source clock; keep its timing explicitly
        // approximate, while still bounding display backlog.
        let lateness = clock.now - sourceTime
        let freshButLate = canAdjust && lateness > CaptionRules.maxQueueAhead && lateness <= CaptionRules.holdMax
        let approximate = clock.window == nil || freshButLate
        let displayAt = approximate ? max(sourceTime, clock.now) : sourceTime
        let timingNote = "Captions are delayed; timing is approximate on this signal."
        if freshButLate { note = timingNote }
        else if note == timingNote { note = "" }
        let before = timeline.dropped
        timeline.append(body, at: displayAt, spoken: row.spoken_seconds, now: clock.now)
        trace(3, row: row, source: sourceTime, display: displayAt, value: freshButLate ? 1 : 0)
        if timeline.dropped > before { note = "Captions caught up; some delayed speech could not be displayed." }
        if !counted { firstAt = timeline.cues.first?.start }
        return true
    }

    // MARK: - The hold (resync() and holdBack())

    private func ceiling(_ clock: PlayerController.CaptionClock) -> Double {
        // ponytail: the site keeps two target durations of headroom; AVPlayer does not say the
        // target duration, so twelve seconds stands in for it.
        guard let window = clock.window else { return CaptionRules.holdMax }
        return max(0, min(CaptionRules.holdMax, window.upperBound - window.lowerBound - 12))
    }

    @discardableResult
    private func resync() -> Bool {
        guard isOn, !resyncing, let player, let clock = player.captionClock, let window = clock.window else { return false }
        let want = CaptionRules.holdTarget(lags: lags, ceiling: ceiling(clock))
        let need = want - clock.behindLive
        guard need > 1, clock.now - need > window.lowerBound + 6 else { return false }
        lastResync = Date()
        say("Resyncing \u{00B7} holding the signal back \(Int(want)) s so the captions land with the speech\u{2026}")
        seekBack(by: need, player: player)
        return true
    }

    private func holdBack(_ seconds: Double, clock: PlayerController.CaptionClock) -> Bool {
        guard !resyncing, let player, let window = clock.window, Date().timeIntervalSince(lastResync) > 60 else { return false }
        let secs = min(seconds, max(0, ceiling(clock) - clock.behindLive))
        let target = max(clock.now - secs, window.lowerBound + 6)
        guard clock.now - target >= 3 else { return false }
        lastResync = Date()
        say("Resyncing \u{00B7} holding the signal back \(Int((clock.now - target).rounded())) s so the captions land with the speech\u{2026}")
        seekBack(by: clock.now - target, player: player)
        return true
    }

    private func seekBack(by seconds: Double, player: PlayerController) {
        trace(5, value: seconds)
        resyncing = true
        seekSerial += 1
        let serial = seekSerial
        seekDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        text = nil
        let gen = generation
        player.seekBack(by: seconds) { [weak self] in
            guard let self, gen == self.generation, serial == self.seekSerial, self.isOn else { return }
            self.trace(6)
            self.seekDeadline = nil
            self.resyncing = false
            self.clearSayLater()
            self.flush()
        }
    }

    private func say(_ line: String) {
        note = line
        countSaid = ""
    }

    private func clearSayLater() {
        let said = note, gen = generation
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if gen == generation, note == said { note = "" }
        }
    }

    // MARK: - The overlay clock and the countdown

    /// Ten times a second: what is on screen, and the count to the first line (tickCountdown()).
    private func tick(_ player: PlayerController, generation gen: Int) async {
        while !Task.isCancelled, gen == generation {
            if resyncing, let deadline = seekDeadline, ContinuousClock.now >= deadline {
                trace(7)
                seekSerial += 1 // a late completion cannot settle another seek
                seekDeadline = nil
                resyncing = false
                player.cancelCaptionSeek()
                note = "The signal could not resync; caption timing is approximate."
            }
            flush() // absolute translation deadlines include authentication and slow downloads
            if !resyncing, let clock = player.captionClock {
                timeline.advance(to: clock.now)
                let cue = timeline.cues.first { $0.start <= clock.now && clock.now < $0.end }
                let showing = cue?.text
                if text != showing { trace(4, cue: cue); text = showing }
                countdown(clock)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func countdown(_ clock: PlayerController.CaptionClock) {
        if counted { return }
        if let firstAt {
            let left = firstAt - clock.now
            if left > 0 {
                sayCount("Captions in \(max(1, Int(left.rounded(.up)))) s")
            } else {
                counted = true
                self.firstAt = nil
                estimateAt = nil
                sayCount("")
            }
            return
        }
        guard let estimateAt else { return }
        let hold = max(clock.behindLive, clock.window == nil ? 0 : min(ceiling(clock), CaptionRules.holdStart))
        let estimate = Int((estimateAt.timeIntervalSinceNow + hold).rounded(.up))
        sayCount(estimate > 0 ? "Captions in about \(estimate) s" : CaptionRules.waitingLine)
    }

    /// Writes only over its own last line or an empty note, so a reason the viewer must read stays.
    private func sayCount(_ line: String) {
        guard note.isEmpty || note == countSaid else { return }
        countSaid = line
        if note != line { note = line }
    }

    // MARK: - What the channel is (pullDetectedLanguage(), the accuracy file)

    private func pullDetectedLanguage(_ target: Channel, generation gen: Int) async {
        guard let (data, _) = try? await urlSession.data(for: CaptionRules.detectedRequest(channelId: target.id)),
              let row = (try? JSONDecoder().decode([DetectedLanguage].self, from: data))?.first, row.lang_code != nil,
              gen == attachment, channel?.id == target.id else { return }
        detected = row
        let code = CaptionRules.effectiveLangCode(target, detected: row)
        if (code.map { !CaptionRules.supported.contains($0) } ?? false) ||
           !CaptionRules.eligible(target, detected: row, accuracy: Self.accuracy) {
            let reason = CaptionRules.parkedReason(target, detected: row, accuracy: Self.accuracy)
            stop(reason.isEmpty ? "The current source language is not supported by the live recognizer." : reason)
            offered = false
            return
        }
        if !isOn { decide() }
    }

    private func loadAccuracy(_ target: Channel, generation gen: Int) async {
        if Self.accuracy == nil {
            guard let url = KJURL.sitePath(CaptionRules.accuracyPath),
                  let (data, _) = try? await urlSession.data(from: url),
                  let file = try? JSONDecoder().decode(CaptionAccuracy.self, from: data) else { return }
            Self.accuracy = file
        }
        guard gen == attachment, channel?.id == target.id else { return }
        if CaptionRules.isExtension(target, accuracy: Self.accuracy),
           !CaptionRules.measured(target, code: CaptionRules.effectiveLangCode(target, detected: detected), accuracy: Self.accuracy) {
            if isOn { UserDefaults.standard.set("off", forKey: CaptionRules.modeKey) }
            stop(CaptionRules.parkedReason(target, detected: detected, accuracy: Self.accuracy))
            offered = false
        }
    }
}
