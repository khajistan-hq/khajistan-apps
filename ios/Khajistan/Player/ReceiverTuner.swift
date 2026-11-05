import Foundation
import Observation

/// What the Receiver tab is playing. A channel plays in the screen docked at the top of the tab
/// and goes full screen only when full screen is chosen (owner, 2026-10-08: "it should go
/// fullscreen only if fullscreen is chosen"). The docked screen and the full-screen view both read
/// this one tuner, so opening and closing full screen never retunes the signal.
///
/// A change goes behind the pigeon: the ground and the bird come up, the next signal tunes behind
/// them, and they lift once it plays.
@MainActor @Observable
final class ReceiverTuner {
    enum Source: Equatable {
        case live(Channel)
        case transmission(Int)
    }

    /// The viewer's choice, kept on the device (owner, 2026-10-28): leaving the Receiver keeps the
    /// channel on in the small player (the default), or turns it off.
    static let keepsPlayingKey = "kj.receiverKeepsPlaying"
    /// And whether it plays on with the app closed or the phone locked (the default), or pauses.
    static let playsInBackgroundKey = "kj.receiverPlaysInBackground"

    /// Nil when the receiver is off.
    private(set) var source: Source?
    /// The list a live channel was chosen from: up and down move through it.
    private(set) var list: [Channel] = []
    /// The live channels' player. Transmission plays on its store's own.
    let controller = PlayerController()
    /// The song on the live channel (NowPlaying), or "". Every surface showing the channel reads it.
    private(set) var song = ""
    @ObservationIgnored private var songTask: Task<Void, Never>?

    let captions: LiveCaptionSession
    @ObservationIgnored private var initialOpenAttempted = false
    @ObservationIgnored private var openingPending = false
    @ObservationIgnored private var openingRevision = 0
    @ObservationIgnored private var surfRevision = 0
    @ObservationIgnored private var intentRevision = 0
    #if DEBUG
    @ObservationIgnored private var heldFirstOpeningForTest = false
    #endif
    @ObservationIgnored private let clips: StationClips
    @ObservationIgnored private let receiver: ReceiverStore
    @ObservationIgnored private let transmission: TransmissionStore
    /// The channel the last step asked for, until the change has tuned it.
    @ObservationIgnored private var destination: Channel?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    /// True while a channel opens or changes: those flows cover and uncover the picture themselves.
    @ObservationIgnored private var changing = false
    /// When the last change settled. A stream often stalls once just after it starts; covering
    /// that would flash the ground over a picture that is about to play.
    @ObservationIgnored private var settledAt = Date.distantPast
    /// Bumped by every open and change. Transmission's network calls do not stop on cancel, so
    /// a flow left behind still finishes; only the newest may clear `changing`.
    @ObservationIgnored private var run = 0

    init(clips: StationClips, receiver: ReceiverStore, transmission: TransmissionStore, captions: LiveCaptionSession) {
        self.captions = captions
        self.clips = clips
        self.receiver = receiver
        self.transmission = transmission
        controller.onPlaybackUnavailable = { [weak captions] in captions?.suspendForPlaybackInterruption() }
    }

    var channel: Channel? {
        if case .live(let channel) = source { return channel }
        return nil
    }

    /// The player carrying the current source.
    var player: PlayerController {
        if case .transmission = source { return transmission.player }
        return controller
    }

    var canStep: Bool {
        switch source {
        case .live: return list.count > 1
        case .transmission: return true
        case nil: return false
        }
    }

    /// A canceled pre-selection opening may retry; explicit Stop remains off on tab return.
    func receiverOpened(isActive: @escaping @MainActor () -> Bool) async {
        guard isActive(), !initialOpenAttempted else { return }
        initialOpenAttempted = true
        guard source == nil else { return }
        openingRevision += 1
        let opening = openingRevision
        let startingIntent = intentRevision
        openingPending = true
        defer {
            if opening == openingRevision {
                openingPending = false
                if source == nil, startingIntent == intentRevision, Task.isCancelled || !isActive() {
                    initialOpenAttempted = false
                }
            }
        }
        #if DEBUG
        // Hold only the first opening until normal navigation cancels it. A fixed delay can
        // elapse while XCUITest is attaching, accidentally testing an already-selected channel.
        if UserDefaults.standard.bool(forKey: "kjholdfirstopening"), !heldFirstOpeningForTest {
            heldFirstOpeningForTest = true
            while !Task.isCancelled, isActive(), opening == openingRevision {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return
        }
        // Reproduce a tab change while automatic selection is suspended without depending on network speed.
        let delay = UserDefaults.standard.integer(forKey: "kjopeningdelayms")
        if delay > 0 {
            try? await Task.sleep(for: .milliseconds(min(delay, 10_000)))
            guard !Task.isCancelled, isActive(), opening == openingRevision else { return }
        }
        #endif
        await surf(allowSelection: { isActive() && self.openingRevision == opening })
        guard !Task.isCancelled, isActive(), opening == openingRevision, let first = channel else { return }
        var attempted = Set([first.id])
        // Only a definite failure advances. Slow buffering does not switch a working station.
        for _ in 0..<2 {
            let revision = intentRevision
            await controller.settled(within: .seconds(32))
            guard !Task.isCancelled, isActive(), opening == openingRevision, revision == intentRevision else { return }
            guard case .failed = controller.state,
                  let next = list.first(where: { !attempted.contains($0.id) }) else { return }
            attempted.insert(next.id)
            play(next, in: list)
        }
    }

    /// Cancel only pending automatic selection. Already-playing radio remains background audio,
    /// unless the viewer turned "Keep playing on other pages" off (`turnOffOnLeaving`).
    func receiverClosed() {
        guard openingPending else { return }
        openingPending = false
        openingRevision += 1
        if source == nil {
            initialOpenAttempted = false
            intentRevision += 1
            surfRevision += 1
            surfing = false
        }
    }

    // MARK: - Choosing

    /// A region tap supersedes pending Surf/region loads, and never walks a previous global pool.
    func selectRegion(_ id: String, allowSelection: @escaping @MainActor () -> Bool = { true }) async {
        guard !Task.isCancelled, allowSelection() else { return }
        initialOpenAttempted = true
        openingPending = false
        openingRevision += 1
        intentRevision += 1
        let intent = intentRevision
        surfRevision += 1
        let search = surfRevision
        surfing = false
        let currentID = (destination ?? channel)?.id
        let medium = ShuffleMedium.stored(UserDefaults.standard.string(forKey: ShuffleMedium.key))
        guard let eligible = try? await receiver.channels(regionId: id, cameras: false) else { return }
        // A later Stop, step, play, Surf or region selection owns the receiver now.
        guard !Task.isCancelled, allowSelection(), intent == intentRevision, search == surfRevision,
              let choice = ReceiverRegionChoice.choose(from: eligible, currentID: currentID, medium: medium) else { return }
        play(choice.channel, in: choice.list)
    }

    func play(_ channel: Channel, in list: [Channel]) {
        stop()
        self.list = list
        source = .live(channel)
        tune(channel)
        changeTask = Task { await open(channel) }
    }

    func playTransmission(_ number: Int) {
        stop()
        source = .transmission(number)
        watchHouseSong()
        transmission.player.state = .tuning
        changeTask = Task { await openTransmission(number) }
    }

    /// The next channel (1) or the one before (-1), round the list or the dial.
    func step(_ delta: Int) {
        intentRevision += 1
        switch source {
        case .live(let current):
            let from = destination ?? current
            guard list.count > 1, let position = list.firstIndex(where: { $0.id == from.id }) else { return }
            let target = list[(position + delta + list.count) % list.count]
            destination = target
            changeTask?.cancel()
            changeTask = Task { await change(to: target) }
        case .transmission:
            changeTask?.cancel()
            changeTask = Task { await switchTransmission(step: delta) }
        case nil:
            return
        }
    }

    /// A live signal paused is not the live signal any more: play tunes it afresh.
    func playPause() {
        intentRevision += 1
        switch source {
        case .live(let channel):
            if controller.state == .tuning {
                // Pause while connecting stops the connecting, or the signal would start anyway.
                run += 1
                changing = false
                captions.suspendForPlaybackInterruption()
                tuneTask?.cancel()
                changeTask?.cancel()
                controller.stop()
                controller.state = .paused
                clips.uncover()
            } else if controller.state == .playing {
                captions.suspendForPlaybackInterruption()
                controller.pause()
            } else {
                tune(channel)
            }
        case .transmission:
            if transmission.player.state == .playing || transmission.player.state == .tuning {
                changeTask?.cancel()
                run += 1
                changing = false
                clips.uncover()
                transmission.pause()
            } else {
                Task { await transmission.rejoinLive() }
            }
        case nil:
            return
        }
    }

    /// The app left the screen with Play in the background off: what is on pauses, to be played
    /// again on return.
    func appLeftTheScreen() {
        guard !(UserDefaults.standard.object(forKey: Self.playsInBackgroundKey) as? Bool ?? true) else { return }
        if player.state == .playing || player.state == .tuning { playPause() }
    }

    /// True while Surf is looking for a channel.
    private(set) var surfing = false
    /// Why the last Surf found nothing, until the next one.
    private(set) var surfNote: String?

    /// A live channel at random, of the medium and from the part of the atlas kept in the Surf
    /// settings (owner, 2026-10-07); next and previous then walk every channel of that setting
    /// (owner, 2026-10-29: "true surf").
    func surf(allowSelection: @escaping @MainActor () -> Bool = { true }) async {
        guard !surfing else { return }
        let revision = intentRevision
        surfRevision += 1
        let search = surfRevision
        surfing = true
        surfNote = nil
        defer { if search == surfRevision { surfing = false } }
        await receiver.loadIndex()
        guard !Task.isCancelled, allowSelection(), search == surfRevision, revision == intentRevision else { return }
        guard let index = receiver.index else {
            surfNote = "The receiver has not loaded."
            return
        }
        let defaults = UserDefaults.standard
        let pool = await ShufflePick.surf(index, medium: .stored(defaults.string(forKey: ShuffleMedium.key)),
                                          // Surf follows the Beyond the atlas switch, as on the Apple TV
                                          // (owner, 2026-10-29: one control for both).
                                          scope: defaults.bool(forKey: "kj.extendedAtlas") ? .everywhere : .main) { region in
            try? await self.receiver.channels(regionId: region, cameras: false)
        }
        guard !Task.isCancelled, allowSelection(), search == surfRevision, revision == intentRevision else { return }
        if let channel = pool.first {
            play(channel, in: pool)
            return
        }
        surfNote = "Nothing to surf there right now."
    }

    /// Turns the receiver off.
    /// Leaving the Receiver with "Keep playing on other pages" off: what is on turns off, and a
    /// Surf or selection still in flight is dropped (stop() bumps intentRevision, which both check),
    /// so nothing lands under another page. It is not an explicit Stop: a selection that leaving
    /// canceled (receiverClosed() cleared initialOpenAttempted) is tried again on return.
    func turnOffOnLeaving() {
        let selectsOnReturn = !initialOpenAttempted
        stop()
        initialOpenAttempted = !selectsOnReturn
    }

    func stop() {
        initialOpenAttempted = true
        openingPending = false
        intentRevision += 1
        run += 1
        captions.detach()
        tuneTask?.cancel()
        changeTask?.cancel()
        songTask?.cancel()
        song = ""
        controller.stop()
        if case .transmission = source { transmission.stop() }
        clips.clear()
        destination = nil
        changing = false
        source = nil
    }

    /// The pigeon covers a buffer mid-broadcast too, as on the site. Only outside a change, and only
    /// for a stall that lasts: a blip must not flash the bird.
    func playerStateChanged(from old: PlayerController.State, to new: PlayerController.State) {
        // Before the change guard: the first play after a retune is what brings carried CC back.
        if new == .playing, source != nil { captions.playbackResumed() }
        guard !changing, source != nil else { return }
        if old == .playing && new == .tuning, Date().timeIntervalSince(settledAt) > 3 {
            Task {
                try? await Task.sleep(for: .seconds(1))
                if !changing, player.state == .tuning, transmissionIsOnAir { clips.cover(caption: caption) }
            }
        } else if clips.coverage > 0, new == .playing || Self.isFailure(new) {
            // A stall that runs out fails (PlayerController.watchForStall): the reason must not
            // sit under the bird, so a failure lifts it as playing does.
            clips.uncover()
        }
    }

    private static func isFailure(_ state: PlayerController.State) -> Bool {
        if case .failed = state { return true }
        return false
    }

    /// A Transmission handover sets its player tuning, and a carrier that then needs a sign-in or
    /// fails leaves it there: the screen's message must not sit under the ground.
    func transmissionPhaseChanged() {
        guard case .transmission = source, !changing, clips.coverage > 0, !transmissionIsOnAir else { return }
        if case .tuning = transmission.phase { return }
        clips.uncover()
    }

    private var transmissionIsOnAir: Bool {
        guard case .transmission = source else { return true }
        if case .onAir = transmission.phase { return true }
        return false
    }

    private var caption: String? {
        switch source {
        case .live(let channel): return channel.name
        case .transmission: return transmission.channelName(transmission.channelNumber)
        case nil: return nil
        }
    }

    // MARK: - Live channels

    private func tune(_ target: Channel) {
        captions.detach(keepingCarry: true)
        tuneTask?.cancel()
        controller.stop()
        controller.state = .tuning
        source = .live(target)
        captions.attach(target, player: controller)
        songTask?.cancel()
        song = ""
        if target.mediaType == "radio" || target.mediaType == "tv" {
            songTask = Task { [weak self] in
                // Not asked while paused or tuning: the worker would listen for nobody.
                await NowPlaying.watch(target.id, active: { self?.controller.state == .playing }) { line in
                    // Left for Transmission or another channel: the line is not this one's.
                    guard let self else { return }
                    self.song = self.channel?.id == target.id ? line : ""
                }
            }
        }
        tuneTask = Task {
            do {
                let url = try await receiver.resolve(target)
                try Task.checkCancellation()
                controller.attach(url: url, seekTo: nil, title: target.name, subtitle: target.place.isEmpty ? nil : target.place)
            } catch {
                if Task.isCancelled { return }
                controller.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Khajistan Transmission's song: the span of songs.json the player's position is in, checked
    /// each second while the receiver stays on Transmission (the website reads `timeupdate`).
    private func watchHouseSong() {
        songTask?.cancel()
        song = ""
        songTask = Task { [weak self] in
            var heldFor = "", spans: [SongSpan] = []
            while !Task.isCancelled {
                guard let self, case .transmission(let number) = self.source else { return }
                var line = ""
                // Until the store has tuned the channel asked for, its phase is the programme
                // being left, whose song must not print under the new channel's name.
                if self.transmission.channelNumber == number, case .onAir(let air) = self.transmission.phase {
                    if air.programmeId != heldFor {
                        heldFor = air.programmeId
                        spans = await HouseSongs.shared.spans(for: air.programmeId, previewPassword: self.transmission.previewPassword)
                    }
                    let time = self.transmission.player.player.currentTime().seconds
                    if time.isFinite { line = HouseSongs.song(in: spans, at: time) }
                }
                if line != self.song { self.song = line }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func begin() -> Int {
        run += 1
        changing = true
        return run
    }

    private func open(_ channel: Channel) async {
        guard !Task.isCancelled else { return }
        let mine = begin()
        defer { if run == mine { changing = false } }
        clips.cover(caption: channel.name, animated: false)
        await controller.settled()
        guard !Task.isCancelled else { return }
        clips.uncover()
        settledAt = Date()
    }

    private func change(to target: Channel) async {
        guard !Task.isCancelled else { return }
        let mine = begin()
        defer { if run == mine, destination == nil || destination?.id == target.id { changing = false } }
        async let quiet: Void = controller.fadeOut()
        await clips.flyThrough(caption: target.name) {
            guard self.destination?.id == target.id else { return }
            self.tune(target)
            self.destination = nil
        }
        await quiet
        guard !Task.isCancelled else { return }
        await controller.settled()
        guard !Task.isCancelled else { return }
        clips.uncover()
        settledAt = Date()
    }

    // MARK: - Khajistan Transmission

    private func openTransmission(_ number: Int) async {
        guard !Task.isCancelled else { return }
        let mine = begin()
        defer { if run == mine { changing = false } }
        clips.signOnPlayed = true
        clips.cover(caption: transmission.channelName(number), animated: false)
        await transmission.tune(channel: number)
        guard !Task.isCancelled else { return }
        await transmission.player.settled()
        guard !Task.isCancelled else { return }
        clips.uncover()
        settledAt = Date()
    }

    private func switchTransmission(step: Int) async {
        guard !Task.isCancelled else { return }
        let mine = begin()
        defer { if run == mine { changing = false } }
        // From the channel this tuner last asked for, not the one the store has reached: a second
        // swipe lands before the first has tuned, and stepping from the store would lose it.
        let from: Int
        if case .transmission(let number) = source { from = number } else { from = transmission.channelNumber }
        let next = transmission.channel(from: from, step: step)
        source = .transmission(next)
        watchHouseSong()
        async let quiet: Void = transmission.player.fadeOut()
        clips.cover(caption: transmission.channelName(next), animated: false)
        await quiet
        guard !Task.isCancelled else { return }
        await transmission.tune(channel: next)
        guard !Task.isCancelled else { return }
        await transmission.player.settled()
        guard !Task.isCancelled else { return }
        clips.uncover()
        settledAt = Date()
    }
}
