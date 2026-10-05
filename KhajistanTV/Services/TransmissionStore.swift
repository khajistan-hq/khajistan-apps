import Foundation
import Observation

/// Khajistan TV: one station, two channels. A channel is tuned and the clock says what is
/// on it; a programme is never chosen. This store owns the schedule, the tuning and the
/// handover from one file to the next.
@MainActor @Observable
final class TransmissionStore {
    enum Phase: Equatable {
        case idle
        case loading
        case needsPreviewPassword(String?)
        case noSchedule
        case needsSignIn
        case offAir(channelName: String, returns: String?)
        case onAir(OnAir)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var channelNumber = 1
    private(set) var programming: Programming?
    let player = PlayerController()

    @ObservationIgnored private var month: String?
    /// Bumped by every load, tune, handover and stop. An answer that arrives under an older
    /// number belongs to a tuning the viewer has already left, and is dropped.
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

    func channelName(_ number: Int) -> String {
        programming?._meta.channels.first(where: { $0.number == number })?.name ?? "Channel \(number)"
    }

    // MARK: - Loading the month

    /// Tunes in. The month's schedule is fetched only when it is not already held, so coming
    /// back to the tab, signing in or trying again does not download it a second time.
    func load() async {
        let monthKey = StationClock.stationMonth(Date())
        if programming != nil, month == monthKey {
            await tune()
            return
        }
        let gen = beginTune()
        player.stop()
        phase = .loading
        programming = nil
        month = monthKey
        let url = Transmission.scheduleURL(month: monthKey)
        var reply: Reply
        do {
            // Without the preview password first: after the launch switch the schedule is
            // public, and a stored password that no longer matches must not stand in the way.
            reply = try await send(URLRequest(url: url))
            if reply.status == 401, let password = auth.previewPassword {
                guard gen == generation else { return }
                var request = URLRequest(url: url)
                request.setValue(
                    Transmission.basicAuthorization(user: KJConfig.previewUser, password: password),
                    forHTTPHeaderField: "Authorization"
                )
                reply = try await send(request)
            }
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
            return
        }
        guard gen == generation else { return }
        switch reply.status {
        case 200:
            break
        case 401:
            phase = .needsPreviewPassword(auth.previewPassword == nil ? nil : "That password did not open the schedule.")
            return
        case 404:
            phase = .noSchedule
            return
        default:
            phase = .failed("The schedule returned HTTP \(reply.status).")
            return
        }
        let body = reply.data
        let decoded: Programming
        do {
            decoded = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(Programming.self, from: body)
            }.value
        } catch {
            guard gen == generation else { return }
            phase = .failed("The schedule could not be read.")
            return
        }
        guard gen == generation else { return }
        programming = decoded
        await tune(generation: gen)
    }

    // MARK: - Tuning

    /// Joins the current channel where the clock says it has got to. When the calendar has
    /// moved into a month the loaded schedule does not cover, the new month is fetched first.
    func tune() async {
        if let month, month != StationClock.stationMonth(Date()) {
            await load()
            return
        }
        let gen = beginTune()
        await tune(generation: gen)
    }

    func switchChannel() async {
        channelNumber = channelNumber == 1 ? 2 : 1
        await tune()
    }

    /// Resuming a paused transmission is joining it again, not continuing from where it paused.
    func rejoinLive() async {
        await tune()
    }

    func stop() {
        _ = beginTune()
        player.stop()
        phase = .idle
    }

    private func tune(generation gen: Int) async {
        guard let p = programming else { return }
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
            await load()
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
    /// seconds and the channel is tuned again the moment something is on it, or the month
    /// has turned and a new schedule is due.
    private func watchForReturn(generation gen: Int) {
        offAirWatch?.cancel()
        offAirWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled, gen == self.generation,
                      case .offAir = self.phase, let p = self.programming else { return }
                let now = Date()
                let monthMoved = StationClock.stationMonth(now) != self.month
                if monthMoved || StationClock.onAir(p, channel: self.channelNumber, at: now) != nil {
                    // A task of its own: tuning cancels this watcher, and a cancelled task
                    // cannot finish the network calls tuning makes.
                    Task { await self.tune() }
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
