import Foundation
import Observation

/// Khajistan Transmission: one station, two channels. A channel is tuned and the clock says what is
/// on it; a programme is never chosen. The store holds the month's schedule for the station page
/// and, for the full-screen player, the tuning and the handover from one file to the next.
@MainActor @Observable
final class TransmissionStore {
    /// Where the month's schedule has got to. The station page reads this.
    enum ScheduleState: Equatable {
        case idle
        case loading
        case needsPreviewPassword(String?)
        case noSchedule
        case failed(String)
        case ready
    }

    /// What the player has got to.
    enum Phase: Equatable {
        case idle
        case tuning
        case needsSignIn
        case offAir(channelName: String, returns: String?)
        case onAir(OnAir)
        case failed(String)
    }

    private(set) var schedule: ScheduleState = .idle
    private(set) var phase: Phase = .idle
    private(set) var channelNumber = 1
    private(set) var programming: Programming?
    /// The moment the schedule is read at. In DEBUG, `-kjnow <ISO 8601>` pins the station clock to
    /// that moment at launch and lets it run on from there, so the UI tests can carry one month's
    /// schedule as a fixture (UITests/Fixtures) instead of reading the archive's live month file,
    /// which is not in this repository.
    static func now(_ real: Date = Date()) -> Date {
        #if DEBUG
        if let pinned = pinnedStart { return pinned.addingTimeInterval(real.timeIntervalSince(launched)) }
        #endif
        return real
    }

    #if DEBUG
    private static let launched = Date()
    private static let pinnedStart: Date? = UserDefaults.standard.string(forKey: "kjnow").flatMap { ISO8601DateFormatter().date(from: $0) }
    #endif

    /// Two signals, as in the Receiver: the programme on screen, and the other channel tuning out
    /// of sight and silent behind it during a change, until the cut (`switchBehind`,
    /// `commitSwitch`). Each keeps its own layer in the player screen.
    let playerA = PlayerController()
    let playerB = PlayerController()
    private(set) var aIsFront = true
    /// The signal on screen, which everything reads.
    var player: PlayerController { aIsFront ? playerA : playerB }
    /// The signal a channel change tunes, behind the one on screen.
    var incoming: PlayerController { aIsFront ? playerB : playerA }

    /// A channel tuning behind the one on screen, until `commitSwitch` puts it there.
    struct PendingSwitch {
        let channel: Int
        let air: OnAir
        fileprivate let generation: Int
    }

    /// The station month `programming` was fetched for.
    @ObservationIgnored private var month: String?
    /// Bumped by every schedule fetch. An answer that arrives under an older number belongs to a
    /// fetch a newer one has replaced, and is dropped.
    @ObservationIgnored private var scheduleGeneration = 0
    /// The fetch in flight, so that a second caller waits for it and does not start another.
    @ObservationIgnored private var scheduleLoad: (month: String, task: Task<Void, Never>)?
    /// Bumped by every tune, handover and stop. An answer that arrives under an older number
    /// belongs to a tuning the viewer has already left, and is dropped.
    @ObservationIgnored private var generation = 0
    /// Signed addresses already asked for, by route and viewer, so a switch back within ten
    /// minutes skips the signing round trip (1.4-1.8 s for a Dropbox-held programme, measured).
    @ObservationIgnored private var signed: [String: (url: URL, until: Date)] = [:]
    private static let signedLife: TimeInterval = 10 * 60
    @ObservationIgnored private var offAirWatch: Task<Void, Never>?
    /// Waits for the slot on air to end, then hands over to the next strip, as the website's
    /// once-a-minute tuneToNow does. Without it a file that runs past its slot kept the old
    /// show on screen, and the old "now" in the overlay, until the file ended.
    @ObservationIgnored private var slotWatch: Task<Void, Never>?
    private unowned let auth: AuthStore
    private let urlSession: URLSession

    private struct Reply {
        let data: Data
        let status: Int
    }

    init(auth: AuthStore) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        urlSession = URLSession(configuration: config)
    }

    // MARK: - What the schedule says

    func channelName(_ number: Int) -> String {
        programming?._meta.channels.first(where: { $0.number == number })?.name ?? "Channel \(number)"
    }

    /// The channel's own line from the schedule.
    func channelLine(_ number: Int) -> String? {
        programming?._meta.channels.first(where: { $0.number == number })?.line
    }

    /// True only in a DEBUG build handed a schedule file by a UI test: the player opens without
    /// an account and draws its overlay over no picture.
    var isScheduleFile: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "kjschedulefile") != nil
        #else
        return false
        #endif
    }

    var programmeCount: Int? {
        programming?.programme_order.count
    }

    /// What the clock puts on a channel at a moment. Nil when nothing is on it, or no schedule is held.
    func nowOn(channel: Int, at date: Date) -> OnAir? {
        guard let p = programming else { return nil }
        return StationClock.onAir(p, channel: channel, at: date)
    }

    /// The strips after `date` on a channel, soonest first: what is up next, and after it.
    func upcoming(channel: Int, at date: Date, count: Int = 3) -> [ScheduleStrip] {
        guard let p = programming, let id = StationClock.channelId(p, number: channel) else { return [] }
        return StationClock.upcoming(p, channelId: id, at: date, count: count)
    }

    /// When the channel is next on air, for the moment nothing is.
    func returnTime(channel: Int, at date: Date) -> String? {
        guard let p = programming, let id = StationClock.channelId(p, number: channel) else { return nil }
        return StationClock.returnTime(p, channelId: id, at: date)
    }

    // MARK: - Loading the month

    /// Brings in the schedule for the current station month. One already held for this month is
    /// not downloaded again, so coming back to the page, signing in or trying again costs nothing.
    /// A second call while a fetch is in flight waits for that fetch.
    func loadSchedule() async {
        let monthKey = StationClock.stationMonth(Self.now())
        if schedule == .ready, month == monthKey { return }
        if let held = scheduleLoad, held.month == monthKey {
            await held.task.value
            return
        }
        scheduleGeneration += 1
        let gen = scheduleGeneration
        // A schedule held for the month that has just ended stays in place until the new one
        // lands: a programme that finishes in the meantime still has a roster to walk.
        schedule = .loading
        let task = Task { [self] in
            await fetchSchedule(month: monthKey, generation: gen)
            if scheduleGeneration == gen { scheduleLoad = nil }
        }
        scheduleLoad = (monthKey, task)
        await task.value
    }

    private func fetchSchedule(month monthKey: String, generation gen: Int) async {
        let url = Transmission.scheduleURL(month: monthKey)
        var reply: Reply
        #if DEBUG
        // UI tests hand the app a schedule file on disk, so the station page and the player's
        // now and next can be photographed without the preview password or an account.
        if let path = UserDefaults.standard.string(forKey: "kjschedulefile"),
           let data = FileManager.default.contents(atPath: path) {
            await apply(Reply(data: data, status: 200), month: monthKey, generation: gen)
            return
        }
        #endif
        do {
            // Without the preview password first: after the launch switch the schedule is
            // public, and a stored password that no longer matches must not stand in the way.
            reply = try await send(URLRequest(url: url))
            if reply.status == 401, let password = auth.previewPassword {
                guard gen == scheduleGeneration else { return }
                var request = URLRequest(url: url)
                request.setValue(
                    Transmission.basicAuthorization(user: KJConfig.previewUser, password: password),
                    forHTTPHeaderField: "Authorization"
                )
                reply = try await send(request)
            }
        } catch {
            guard gen == scheduleGeneration else { return }
            dropSchedule(.failed(error.localizedDescription))
            return
        }
        guard gen == scheduleGeneration else { return }
        await apply(reply, month: monthKey, generation: gen)
    }

    private func apply(_ reply: Reply, month monthKey: String, generation gen: Int) async {
        switch reply.status {
        case 200:
            break
        case 401:
            dropSchedule(.needsPreviewPassword(auth.previewPassword == nil ? nil : "That password did not open the schedule."))
            return
        case 404:
            dropSchedule(.noSchedule)
            return
        default:
            dropSchedule(.failed("The schedule returned HTTP \(reply.status)."))
            return
        }
        let body = reply.data
        let decoded: Programming
        do {
            decoded = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(Programming.self, from: body)
            }.value
        } catch {
            guard gen == scheduleGeneration else { return }
            dropSchedule(.failed("The schedule could not be read."))
            return
        }
        guard gen == scheduleGeneration else { return }
        programming = decoded
        month = monthKey
        schedule = .ready
    }

    /// A fetch that ended without a schedule: nothing is held, and the page says why.
    private func dropSchedule(_ state: ScheduleState) {
        programming = nil
        month = nil
        schedule = state
    }

    // MARK: - Tuning

    /// Joins a channel where the clock says it has got to. The schedule is fetched first when it
    /// is not held for the current station month, so a month that has turned is picked up here.
    /// Needing a sign-in and failing are phases the player shows, not errors.
    func tune(channel: Int) async {
        channelNumber = channel
        let gen = beginTune()
        player.stop()
        incoming.stop()
        phase = .tuning
        await loadSchedule()
        guard gen == generation else { return }
        guard schedule == .ready else {
            phase = .failed("The schedule has not loaded.")
            return
        }
        await tune(generation: gen)
    }

    func switchChannel() async {
        await tune(channel: channelNumber == 1 ? 2 : 1)
    }

    /// Starts the other channel on the player behind the one on screen, silent, leaving the
    /// programme on screen, the phase and the channel number as they are. Nil when the other
    /// channel is off air, has no playable source, or needs a sign-in: the caller tunes it the
    /// ordinary way and the phase says why.
    func switchBehind() async -> PendingSwitch? {
        let target = channelNumber == 1 ? 2 : 1
        await loadSchedule()
        guard schedule == .ready, let p = programming,
              let air = StationClock.onAir(p, channel: target, at: Self.now()),
              let playURL = air.programme?.play_url, let route = Transmission.route(for: playURL) else { return nil }
        let gen = generation
        guard let url = await carrier(for: route, generation: gen), gen == generation else { return nil }
        let next = incoming
        next.stop()
        next.holdsSound = true
        next.attach(url: url, seekTo: air.seekTo, title: nowPlayingTitle(air), subtitle: air.show?.name,
                    listen: Self.dancerMayListen(air, channel: target))
        return PendingSwitch(channel: target, air: air, generation: gen)
    }

    /// The cut: the channel tuned behind comes on screen, the old one stops, and the new one's
    /// sound comes up. A tune or a stop since `switchBehind` has made the pending switch stale.
    func commitSwitch(_ pending: PendingSwitch) {
        guard pending.generation == generation else { return }
        let gen = beginTune()
        let old = player
        aIsFront.toggle()
        channelNumber = pending.channel
        old.onEnded = nil
        old.stop()
        player.onEnded = { [weak self] in
            Task { @MainActor in
                await self?.handover()
            }
        }
        player.releaseSound()
        phase = .onAir(pending.air)
        watchSlotEnd(pending.air, generation: gen)
        warmOtherChannel()
    }

    /// Resuming a paused transmission is joining it again, not continuing from where it paused.
    func rejoinLive() async {
        // A retry asks for a fresh address: the held one may be the one that failed.
        signed.removeAll()
        await tune(channel: channelNumber)
    }

    func stop() {
        _ = beginTune()
        playerA.stop()
        playerB.stop()
        phase = .idle
    }

    private func tune(generation gen: Int) async {
        guard let p = programming else {
            phase = .failed("The schedule has not loaded.")
            return
        }
        let now = Self.now()
        guard let air = StationClock.onAir(p, channel: channelNumber, at: now) else {
            goOffAir(p, channelId: StationClock.channelId(p, number: channelNumber), at: now, generation: gen)
            return
        }
        await play(air, generation: gen)
    }

    private func play(_ air: OnAir, generation gen: Int) async {
        #if DEBUG
        // With a schedule file there is no account: the overlay is drawn over no picture.
        if isScheduleFile {
            phase = .onAir(air)
            watchSlotEnd(air, generation: gen)
            return
        }
        #endif
        guard let playURL = air.programme?.play_url, let route = Transmission.route(for: playURL) else {
            phase = .failed("This programme has no playable source.")
            return
        }
        guard let url = await carrier(for: route, generation: gen) else { return }
        guard gen == generation else { return }
        player.onEnded = { [weak self] in
            Task { @MainActor in
                await self?.handover()
            }
        }
        player.attach(url: url, seekTo: air.seekTo, title: nowPlayingTitle(air), subtitle: air.show?.name,
                      listen: Self.dancerMayListen(air, channel: channelNumber))
        phase = .onAir(air)
        watchSlotEnd(air, generation: gen)
        warmOtherChannel()
    }

    /// Signs the other channel's programme in the background, so a switch to it starts with its
    /// address in hand. Quiet: a failure here changes nothing on screen.
    func warmOtherChannel() {
        let target = channelNumber == 1 ? 2 : 1
        guard schedule == .ready, let p = programming,
              let air = StationClock.onAir(p, channel: target, at: Self.now()),
              let playURL = air.programme?.play_url, let route = Transmission.route(for: playURL) else { return }
        if case .direct = route { return }
        Task {
            guard let token = try? await auth.validAccessToken(), let viewer = auth.session?.userId else { return }
            let key = "\(route)|\(viewer)"
            if let held = signed[key], held.until > Date() { return }
            guard let request = Transmission.request(for: route, accessToken: token),
                  let reply = try? await send(request, refusingRedirects: true), reply.status == 200,
                  let url = try? Transmission.carrier(from: reply.data, route: route),
                  auth.session?.userId == viewer else { return }
            signed[key] = (url, Date().addingTimeInterval(Self.signedLife))
        }
    }

    /// The file ended: the next programme of the same channel starts at its own beginning,
    /// as it does on air. With nothing following, the channel is off air until it returns.
    func handover() async {
        guard case .onAir(let current) = phase, let p = programming else { return }
        let now = Self.now()
        if let month, month != StationClock.stationMonth(now) {
            await tune(channel: channelNumber)
            return
        }
        let gen = beginTune()
        if let next = StationClock.following(current, in: p, at: now) {
            player.state = .tuning
            await play(next, generation: gen)
        } else {
            goOffAir(p, channelId: current.channelId, at: now, generation: gen)
        }
    }

    /// Sleeps until the slot `air` belongs to has ended, then hands over. A handover, a tune or
    /// a stop in the meantime replaces this watch.
    private func watchSlotEnd(_ air: OnAir, generation gen: Int) {
        slotWatch?.cancel()
        guard let left = StationClock.secondsLeft(in: air, at: Self.now()) else { return }
        slotWatch = Task { [weak self] in
            // A second past the end, so the clock has the next strip by the time it is asked.
            try? await Task.sleep(for: .seconds(left + 1))
            guard let self, !Task.isCancelled, gen == self.generation,
                  case .onAir(let current) = self.phase, current.slot == air.slot, current.date == air.date else { return }
            // A task of its own: the handover replaces this watch, and a cancelled task cannot
            // finish the network calls tuning makes.
            Task { await self.handover() }
        }
    }

    // MARK: - Off air

    private func goOffAir(_ p: Programming, channelId: String?, at date: Date, generation gen: Int) {
        player.stop()
        let returns = channelId.flatMap { StationClock.returnTime(p, channelId: $0, at: date) }
        phase = .offAir(channelName: channelName(channelNumber), returns: returns)
        watchForReturn(generation: gen)
    }

    /// Off air is a state the channel leaves by itself: the clock is looked at every fifteen
    /// seconds and the channel is tuned again the moment something is on it, or the month has
    /// turned and a new schedule is due, or no schedule is held any more.
    private func watchForReturn(generation gen: Int) {
        offAirWatch?.cancel()
        offAirWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled, gen == self.generation, case .offAir = self.phase else { return }
                let now = Self.now()
                let due: Bool
                if let p = self.programming, StationClock.stationMonth(now) == self.month {
                    due = StationClock.onAir(p, channel: self.channelNumber, at: now) != nil
                } else {
                    due = true
                }
                if due {
                    // A task of its own: tuning cancels this watcher, and a cancelled task
                    // cannot finish the network calls tuning makes.
                    Task { await self.tune(channel: self.channelNumber) }
                    return
                }
            }
        }
    }

    // MARK: - Helpers

    private func beginTune() -> Int {
        generation += 1
        offAirWatch?.cancel()
        offAirWatch = nil
        slotWatch?.cancel()
        slotWatch = nil
        return generation
    }

    private func send(_ request: URLRequest, refusingRedirects: Bool = false) async throws -> Reply {
        let (data, response) = try await urlSession.data(for: request, delegate: refusingRedirects ? RefuseRedirects() : nil)
        return Reply(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The URL to play for a route, or nil once the phase has been set to say why not. As in the
    /// website's resolve(), every route needs a signed-in session, a plain file included, and an
    /// answer is used only if the same viewer is still signed in when it arrives.
    private func carrier(for route: PlayRoute, generation gen: Int) async -> URL? {
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch {
            guard gen == generation else { return nil }
            // No session, or one the server refused, is a sign-in; a network failure is not.
            phase = error is AuthError ? .needsSignIn : .failed(error.localizedDescription)
            return nil
        }
        guard gen == generation else { return nil }
        let viewer = auth.session?.userId
        if case .direct(let url) = route { return url }
        if let viewer, let held = signed["\(route)|\(viewer)"], held.until > Date() {
            #if DEBUG
            print("KJTUNE carrier held")
            #endif
            return held.url
        }
        guard let request = Transmission.request(for: route, accessToken: token) else {
            phase = .failed("This programme has no playable source.")
            return nil
        }
        let reply: Reply
        #if DEBUG
        let signStart = ContinuousClock.now
        defer { print("KJTUNE sign took=\(ContinuousClock.now - signStart)") }
        #endif
        do {
            // A signer that redirects is refused, as the website's fetch does with redirect: 'error'.
            reply = try await send(request, refusingRedirects: true)
        } catch {
            if gen == generation, !Task.isCancelled { phase = .failed(error.localizedDescription) }
            return nil
        }
        guard gen == generation else { return nil }
        if reply.status == 401 {
            phase = .needsSignIn
            return nil
        }
        let url: URL
        do {
            url = try Transmission.carrier(from: reply.data, route: route)
        } catch {
            phase = .failed("This transmission is unavailable right now.")
            return nil
        }
        guard viewer != nil, auth.session?.userId == viewer else {
            phase = .needsSignIn
            return nil
        }
        #if DEBUG
        print("KJTUNE carrier host=\(url.host ?? "-") ext=\(url.pathExtension)")
        #endif
        if let viewer { signed["\(route)|\(viewer)"] = (url, Date().addingTimeInterval(Self.signedLife)) }
        return url
    }

    /// The dancer listens to a programme that is sound with no picture — every programme on
    /// channel 2, and channel 1's records — unless it is reverent. The site's house channel is
    /// named by its show (open-frequencies.js houseChannel()), so the show name is what the
    /// reverent rule reads. Whether the samples can be read is the carrier's to say: a Supabase
    /// storage file or a Dropbox link can be tapped, a Cloudflare Stream manifest cannot.
    static func dancerMayListen(_ air: OnAir, channel: Int) -> Bool {
        guard air.programme?.audio_only == true else { return false }
        let name = air.show?.name ?? "Khajistan Transmission \u{00B7} Channel \(channel)"
        return !Reverence.isReverent(name: name, nativeName: nil, broadcaster: nil)
    }

    /// Five vinyl transfers carry no title; the show name stands in for it.
    private func nowPlayingTitle(_ air: OnAir) -> String {
        let title = air.programme?.title ?? ""
        if !title.isEmpty { return title }
        return air.show?.name ?? "Khajistan TV"
    }
}

/// Turns down every redirect, so the 3xx itself comes back as the answer and is not used.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
