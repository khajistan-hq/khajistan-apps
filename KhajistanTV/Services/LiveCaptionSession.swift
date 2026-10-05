import Foundation
import Observation

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
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var leaseTask: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var queue: [SubtitleCue] = []
    @ObservationIgnored private var lastEnd: Double = 0
    @ObservationIgnored private var seen = Set<Int>()
    @ObservationIgnored private var received = 0
    @ObservationIgnored private var lastReceivedAt = Date.distantPast
    @ObservationIgnored private var recovering = false
    @ObservationIgnored private var lags: [Double] = []
    @ObservationIgnored private var lastResync = Date.distantPast
    /// Rows waiting for their English, in arrival order, so a late translation never overtakes.
    @ObservationIgnored private var waiting: [(seq: Int, row: CaptionWireRow, english: String?, ready: Bool)] = []
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
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    private var viewerId: String {
        if let held = UserDefaults.standard.string(forKey: CaptionRules.viewerKey) { return held }
        let fresh = "v" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20)
        UserDefaults.standard.set(fresh, forKey: CaptionRules.viewerKey)
        return fresh
    }

    // MARK: - Attach and detach (the receiver's attach() / detach())

    /// A channel was tuned on `player`. A live carrier in a language the recogniser takes offers
    /// the control; anything else says why in one line, or nothing.
    func attach(_ target: Channel, player: PlayerController) {
        stop("")
        channel = target
        self.player = player
        detected = nil
        decide()
        label = CaptionRules.label(on: false, balance: balance)
        let gen = generation
        Task { await self.pullDetectedLanguage(target, generation: gen) }
        Task { await self.loadAccuracy(target, generation: gen) }
        guard offered else { return }
        askBalance()
        // A viewer who had captions on keeps them on from channel to channel (loadMode()).
        if UserDefaults.standard.string(forKey: CaptionRules.modeKey).map({ $0 != "off" }) == true { turnOn() }
    }

    func detach() {
        stop("")
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
        guard offered else {
            note = CaptionRules.parkedReason(channel, detected: detected, accuracy: Self.accuracy)
            return
        }
        // The server refuses the anon key with sign_in_required anyway; asking here saves the trip.
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
        queue = []; lastEnd = 0; seen = []; received = 0; lastReceivedAt = .distantPast; lags = []; waiting = []
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
        guard let channel, let token = try? await auth.validAccessToken() else { return nil }
        let request = CaptionRules.demandRequest(action: action, channelId: channel.id, viewerId: viewerId,
                                                 sessionId: billingSession, accessToken: token)
        guard let (data, _) = try? await urlSession.data(for: request) else { return nil }
        return try? JSONDecoder().decode(CaptionReply.self, from: data)
    }

    // MARK: - Off (stop())

    /// Every teardown releases the demand, so the paid worker stops for nobody watching.
    private func stop(_ why: String) {
        let wasOn = isOn || billingSession != nil
        generation += 1
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
        queue = []
        waiting = []
        text = nil
        firstAt = nil
        estimateAt = nil
        label = "Captions"
        note = why
    }

    // MARK: - The wire

    private func openSocket(_ channelId: String, generation gen: Int) async {
        guard let token = try? await auth.validAccessToken(), gen == generation else { return }
        let task = URLSession.shared.webSocketTask(with: CaptionRealtime.socketURL())
        socket = task
        task.resume()
        try? await task.send(.string(CaptionRealtime.join(channelId: channelId, accessToken: token, ref: "1")))
        let beat = Task {
            var ref = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                try? await task.send(.string(CaptionRealtime.heartbeat(ref: String(ref))))
                ref += 1
            }
        }
        defer { beat.cancel() }
        while gen == generation, !Task.isCancelled {
            guard let message = try? await task.receive() else { return }
            guard case .string(let frame) = message, gen == generation else { continue }
            switch CaptionRealtime.event(frame, channelId: channelId) {
            case .subscribed: await recover(channelId, generation: gen)
            case .row(let row): receive(row)
            case .closed: return
            case .other: continue
            }
        }
    }

    /// Until the first row, and whenever the wire has been quiet fifteen seconds, read it again.
    private func recoverLoop(_ channelId: String, generation gen: Int) async {
        await recover(channelId, generation: gen)
        while !Task.isCancelled, gen == generation {
            try? await Task.sleep(for: .seconds(3))
            if received == 0 || Date().timeIntervalSince(lastReceivedAt) > 15 { await recover(channelId, generation: gen) }
        }
    }

    private func recover(_ channelId: String, generation gen: Int) async {
        guard !recovering, let token = try? await auth.validAccessToken() else { return }
        recovering = true
        defer { recovering = false }
        let request = CaptionRules.wireRequest(channelId: channelId, now: Date(), accessToken: token)
        guard let (data, _) = try? await urlSession.data(for: request), gen == generation,
              let rows = try? JSONDecoder().decode([CaptionWireRow].self, from: data) else { return }
        rows.reversed().forEach(receive)
    }

    /// addCue(): one row, once, English or waiting for it.
    private func receive(_ row: CaptionWireRow) {
        guard isOn, let channel, CaptionRules.admits(row, channelId: channel.id) else { return }
        if let id = row.id {
            guard seen.insert(id).inserted else { return }
            if seen.count > 500 { seen.removeAll() }   // ponytail: the site evicts oldest-first; rows are pruned server-side anyway
        }
        lastReceivedAt = Date()
        received += 1
        // The worker withholds English when it could not hear reliably; never invent it.
        if row.uncertain == true { note = CaptionRules.uncertainLine; return }
        let english = CaptionRules.english(for: row)
        guard waiting.count < 200 else { note = "Caption translation is catching up."; return }
        sequence += 1
        let seq = sequence
        let needsTranslation = english == nil && !(row.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        waiting.append((seq, row, english, !needsTranslation))
        if needsTranslation {
            let gen = generation
            Task { await self.translate(row, seq: seq, generation: gen) }
        } else {
            flush()
        }
    }

    private func translate(_ row: CaptionWireRow, seq: Int, generation gen: Int) async {
        var english: String?
        if let token = try? await auth.validAccessToken(), let channel {
            let code = CaptionRules.effectiveLangCode(channel, detected: detected)
            let request = CaptionRules.translateRequest(row: row, channelLang: code, sessionId: billingSession, accessToken: token)
            if let (data, response) = try? await urlSession.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
               let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let checked = CaptionRules.checkedEnglish(reply["english"] as? String, row: row)
                english = checked.isEmpty ? nil : checked
            }
        }
        guard gen == generation, let index = waiting.firstIndex(where: { $0.seq == seq }) else { return }
        waiting[index].english = english
        waiting[index].ready = true
        flush()
    }

    private func flush() {
        while let head = waiting.first, head.ready {
            waiting.removeFirst()
            emit(head.row, english: head.english)
        }
    }

    // MARK: - Placing a line

    /// emit() and placeByClock() / placeCue(): a programme timestamp where the playlist carries one,
    /// else the row's wall-clock time under the hold. ponytail: hls.js exposes fragment sequence
    /// numbers for the site's `sn` placement and AVPlayer does not; those rows go by the clock.
    private func emit(_ row: CaptionWireRow, english: String?) {
        guard isOn, let clock = player?.captionClock else { return }
        guard let body = english, !body.isEmpty else { note = CaptionRules.untranslatedLine; return }
        var at: Double?
        if let epoch = row.program_epoch, let date = clock.programDate {
            let mt = clock.now + epoch - date.timeIntervalSince1970
            if clock.now - mt > 0.5 { holdBack((clock.now - mt).rounded(.up) + CaptionRules.holdMargin, clock: clock) }
            at = max(mt, clock.now)
        } else if let atEpoch = row.at_epoch {
            let now = Date().timeIntervalSince1970
            let lag = now - atEpoch
            if lag <= 180, lag >= -30 {
                lags.append(lag)
                if lags.count > 12 { lags.removeFirst() }
                if lag + CaptionRules.holdMargin > clock.behindLive, Date().timeIntervalSince(lastResync) > 60 { resync() }
            }
            at = CaptionRules.mediaTime(atEpoch: atEpoch, now: now, mediaNow: clock.now, behindLive: clock.behindLive)
        }
        guard let at else { return }
        paint(body, at: at, spoken: row.spoken_seconds, now: clock.now)
    }

    private func paint(_ body: String, at: Double, spoken: Double?, now: Double) {
        if lastEnd - max(at, now) > CaptionRules.maxQueueAhead {
            note = "Speech is arriving faster than captions can be read; some captions could not be displayed."
            return
        }
        if at - now > CaptionRules.holdMax + 15 || queue.count >= 200 { return }
        let cues = CaptionRules.timed(body, at: max(at, lastEnd), spokenSeconds: spoken)
        guard let last = cues.last else { return }
        if firstAt == nil, !counted { firstAt = cues[0].start }
        queue.append(contentsOf: cues)
        lastEnd = last.end
    }

    // MARK: - The hold (resync() and holdBack())

    private func ceiling(_ clock: PlayerController.CaptionClock) -> Double {
        // ponytail: the site keeps two target durations of headroom; AVPlayer does not say the
        // target duration, so twelve seconds stands in for it.
        guard let window = clock.window else { return CaptionRules.holdMax }
        return max(0, min(CaptionRules.holdMax, window.upperBound - window.lowerBound - 12))
    }

    private func resync() {
        guard isOn, let player, let clock = player.captionClock, let window = clock.window else { return }
        let want = CaptionRules.holdTarget(lags: lags, ceiling: ceiling(clock))
        let need = want - clock.behindLive
        guard need > 1, clock.now - need > window.lowerBound + 6 else { return }
        lastResync = Date()
        say("Resyncing \u{00B7} holding the signal back \(Int(want)) s so the captions land with the speech\u{2026}")
        player.seekBack(by: need)
        clearSayLater()
    }

    private func holdBack(_ seconds: Double, clock: PlayerController.CaptionClock) {
        guard let player, let window = clock.window, Date().timeIntervalSince(lastResync) > 60 else { return }
        let secs = min(seconds, max(0, ceiling(clock) - clock.behindLive))
        let target = max(clock.now - secs, window.lowerBound + 6)
        guard clock.now - target >= 3 else { return }
        lastResync = Date()
        say("Resyncing \u{00B7} holding the signal back \(Int((clock.now - target).rounded())) s so the captions land with the speech\u{2026}")
        player.seekBack(by: clock.now - target)
        clearSayLater()
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
            if let clock = player.captionClock {
                queue.removeAll { $0.end <= clock.now }
                let showing = queue.first { $0.start <= clock.now && clock.now < $0.end }?.text
                if text != showing { text = showing }
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
              channel?.id == target.id else { return }
        detected = row
        let code = CaptionRules.effectiveLangCode(target, detected: row)
        if let code, !CaptionRules.supported.contains(code) {
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
        guard channel?.id == target.id else { return }
        if CaptionRules.isExtension(target, accuracy: Self.accuracy),
           !CaptionRules.measured(target, code: CaptionRules.effectiveLangCode(target, detected: detected), accuracy: Self.accuracy) {
            if isOn { UserDefaults.standard.set("off", forKey: CaptionRules.modeKey) }
            stop(CaptionRules.parkedReason(target, detected: detected, accuracy: Self.accuracy))
            offered = false
        }
    }
}
