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
    let player = PlayerController()

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
    @ObservationIgnored private var offAirWatch: Task<Void, Never>?
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

    var programmeCount: Int? {
        programming?.programme_order.count
    }

    /// What the clock puts on a channel at a moment. Nil when nothing is on it, or no schedule is held.
    func nowOn(channel: Int, at date: Date) -> OnAir? {
        guard let p = programming else { return nil }
        return StationClock.onAir(p, channel: channel, at: date)
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
        let monthKey = StationClock.stationMonth(Date())
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

    /// Resuming a paused transmission is joining it again, not continuing from where it paused.
    func rejoinLive() async {
        await tune(channel: channelNumber)
    }

    func stop() {
        _ = beginTune()
        player.stop()
        phase = .idle
    }

    private func tune(generation gen: Int) async {
        guard let p = programming else {
            phase = .failed("The schedule has not loaded.")
            return
        }
        let now = Date()
        guard let air = StationClock.onAir(p, channel: channelNumber, at: now) else {
            goOffAir(p, channelId: StationClock.channelId(p, number: channelNumber), at: now, generation: gen)
            return
        }
        await play(air, generation: gen)
    }

    private func play(_ air: OnAir, generation gen: Int) async {
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
        player.attach(url: url, seekTo: air.seekTo, title: nowPlayingTitle(air), subtitle: air.show?.name)
        phase = .onAir(air)
    }

    /// The file ended: the next programme of the same channel starts at its own beginning,
    /// as it does on air. With nothing following, the channel is off air until it returns.
    func handover() async {
        guard case .onAir(let current) = phase, let p = programming else { return }
        let now = Date()
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
                let now = Date()
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
        guard let request = Transmission.request(for: route, accessToken: token) else {
            phase = .failed("This programme has no playable source.")
            return nil
        }
        let reply: Reply
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
        return url
    }

    /// Five vinyl transfers carry no title; the show name stands in for it.
    private func nowPlayingTitle(_ air: OnAir) -> String {
        let title = air.programme?.title ?? ""
        if !title.isEmpty { return title }
        return air.show?.name ?? "Khajistan TV"
    }
}

/// Turns down every redirect, so the 3xx itself comes back as the answer and is not used.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
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
