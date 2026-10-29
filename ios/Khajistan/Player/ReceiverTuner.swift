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

    /// Nil when the receiver is off.
    private(set) var source: Source?
    /// The list a live channel was chosen from: up and down move through it.
    private(set) var list: [Channel] = []
    /// The live channels' player. Transmission plays on its store's own.
    let controller = PlayerController()

    let captions: LiveCaptionSession
    @ObservationIgnored private var initialOpenAttempted = false
    @ObservationIgnored private var openingPending = false
    @ObservationIgnored private var openingRevision = 0
    @ObservationIgnored private var surfRevision = 0
    @ObservationIgnored private var intentRevision = 0
    @ObservationIgnored private let clips: StationClips
    @ObservationIgnored private let receiver: ReceiverStore
    @ObservationIgnored private let transmission: TransmissionStore
    /// The channel the last step asked for, until the change has tuned it.
    @ObservationIgnored private var destination: Channel?
    @ObservationIgnored private var tuneTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var skipTask: Task<Void, Never>?
    /// Channels in the current scope that have already failed. The skip does not return to them.
    @ObservationIgnored private var failedInScope: Set<String> = []
    /// The tune now in flight: its channel and the intent revision it started with.
    @ObservationIgnored private var tuned: (id: String, revision: Int)?
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
        // Reproduce a tab change while automatic selection is suspended without depending on network speed.
        let delay = UserDefaults.standard.integer(forKey: "kjopeningdelayms")
        if delay > 0 {
            try? await Task.sleep(for: .milliseconds(min(delay, 10_000)))
            guard !Task.isCancelled, isActive(), opening == openingRevision else { return }
        }
        #endif
        await surf(allowSelection: { isActive() && self.openingRevision == opening })
    }

    /// Cancel only pending automatic selection. Already-playing radio remains background audio.
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

    func play(_ channel: Channel, in list: [Channel]) {
        failedInScope = []
        stop()
        self.list = list
        source = .live(channel)
        tune(channel)
        changeTask = Task { await open(channel) }
    }

    func playTransmission(_ number: Int) {
        stop()
        source = .transmission(number)
        transmission.player.state = .tuning
        changeTask = Task { await openTransmission(number) }
    }

    /// The next channel (1) or the one before (-1). Transmission has two, so either way switches.
    func step(_ delta: Int) {
        intentRevision += 1
        switch source {
        case .live(let current):
            let from = destination ?? current
            let order = list.filter { !failedInScope.contains($0.id) && receiver.lists($0) }
            guard order.count > 1, let position = order.firstIndex(where: { $0.id == from.id }) else { return }
            let target = order[(position + delta + order.count) % order.count]
            destination = target
            changeTask?.cancel()
            changeTask = Task { await change(to: target) }
        case .transmission:
            changeTask?.cancel()
            changeTask = Task { await switchTransmission() }
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
                // Play on a failed signal tries that signal once more, then the skip moves on if it fails again.
                if case .failed = controller.state {
                    failedInScope.remove(channel.id)
                    let asked = intentRevision
                    Task {
                        guard await self.receiver.confirm(channel), asked == self.intentRevision else { return }
                        self.tune(channel)
                    }
                    return
                }
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

    /// True while Surf is looking for a channel.
    private(set) var surfing = false
    /// Why the last Surf found nothing, until the next one.
    private(set) var surfNote: String?

    /// A live channel at random, of the medium and from the part of the atlas kept in the Surf
    /// settings (owner, 2026-10-07). The region is drawn by how many channels of that medium it
    /// carries; next and previous then move through that region's list.
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
        let medium = defaults.string(forKey: ShuffleMedium.key).flatMap(ShuffleMedium.init(rawValue:)) ?? .tv
        let scope = defaults.string(forKey: ShuffleScope.key).flatMap(ShuffleScope.init(rawValue:)) ?? .main
        let weights = ShufflePick.weights(index, medium: medium, scope: scope)
        // Up to three regions, in case one's list will not load.
        for _ in 0..<3 {
            guard let region = ShufflePick.region(weights) else { break }
            guard let list = try? await receiver.channels(regionId: region, cameras: false) else { continue }
            guard !Task.isCancelled, allowSelection(), search == surfRevision, revision == intentRevision else { return }
            let pool = list.filter { $0.mediaType == medium.rawValue }
            if let channel = pool.randomElement() {
                play(channel, in: pool)
                return
            }
        }
        // The three draws were empty. A region in the same scope that already has a verified
        // signal can still be surfed. This does not probe any further region.
        guard !Task.isCancelled, allowSelection(), search == surfRevision, revision == intentRevision else { return }
        for region in index.listedRegions where scope.includes(tier: region.tier) {
            let pool = receiver.verifiedChannels(regionId: region.id, medium: medium.rawValue)
            if let channel = pool.randomElement() {
                play(channel, in: pool)
                return
            }
        }
        surfNote = "Nothing to surf there right now."
    }

    /// Turns the receiver off.
    func stop() {
        initialOpenAttempted = true
        openingPending = false
        intentRevision += 1
        run += 1
        failedInScope = []
        captions.detach()
        tuneTask?.cancel()
        changeTask?.cancel()
        skipTask?.cancel()
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
        if case .failed = new, let tuned, case .live(let showing) = source,
           ReceiverRules.mayActOnFailure(failedID: tuned.id, tuneRevision: tuned.revision,
                                         currentRevision: intentRevision, showingID: showing.id) {
            scheduleSkip(failedID: tuned.id, ticket: tuned.revision)
        }
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
        captions.detach()
        tuneTask?.cancel()
        controller.stop()
        controller.state = .tuning
        source = .live(target)
        captions.attach(target, player: controller)
        let ticket = intentRevision
        tuned = (id: target.id, revision: ticket)
        tuneTask = Task {
            do {
                let url = try await receiver.resolve(target)
                try Task.checkCancellation()
                guard ReceiverRules.mayActOnFailure(failedID: target.id, tuneRevision: ticket,
                                                    currentRevision: self.intentRevision, showingID: target.id) else { return }
                controller.attach(url: url, seekTo: nil, title: target.name, subtitle: target.place.isEmpty ? nil : target.place)
            } catch {
                if Task.isCancelled { return }
                guard case .live(let showing) = self.source,
                      ReceiverRules.mayActOnFailure(failedID: target.id, tuneRevision: ticket,
                                                    currentRevision: self.intentRevision, showingID: showing.id) else { return }
                controller.state = .failed(error.localizedDescription)
                self.scheduleSkip(failedID: target.id, ticket: ticket)
            }
        }
    }

    /// A failed play moves to the next verified signal in this list, and only if this tune is
    /// still the one showing. The viewer having moved on withdraws nothing and skips nothing.
    private func scheduleSkip(failedID: String, ticket: Int) {
        guard case .live(let current) = source else { return }
        guard ReceiverRules.mayActOnFailure(failedID: failedID, tuneRevision: ticket,
                                            currentRevision: intentRevision, showingID: current.id) else { return }
        guard case .failed = controller.state else { return }
        guard !failedInScope.contains(failedID) else { return }
        failedInScope.insert(failedID)
        receiver.withdraw(failedID)
        guard let next = ReceiverRules.nextLive(after: failedID, in: list, excluding: failedInScope) else {
            list.removeAll { failedInScope.contains($0.id) }
            return
        }
        list.removeAll { failedInScope.contains($0.id) }
        skipTask?.cancel()
        skipTask = Task { await self.retune(next, failedID: failedID, ticket: ticket) }
    }

    private func retune(_ channel: Channel, failedID: String, ticket: Int) async {
        // The viewer stepped away while this skip was waiting. Leave their tune alone.
        guard !Task.isCancelled, ticket == intentRevision else { return }
        _ = failedID
        list.removeAll { failedInScope.contains($0.id) }
        guard list.contains(where: { $0.id == channel.id }) else {
            list.append(channel)
        }
        changeTask?.cancel()
        tune(channel)
        changeTask = Task { await self.open(channel) }
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
        if case .failed = controller.state, let tuned, case .live(let on) = source, on.id == channel.id,
           ReceiverRules.mayActOnFailure(failedID: tuned.id, tuneRevision: tuned.revision,
                                         currentRevision: intentRevision, showingID: on.id) {
            scheduleSkip(failedID: tuned.id, ticket: tuned.revision)
        }
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
        if case .failed = controller.state, let tuned, case .live(let on) = source, on.id == target.id,
           ReceiverRules.mayActOnFailure(failedID: tuned.id, tuneRevision: tuned.revision,
                                         currentRevision: intentRevision, showingID: on.id) {
            scheduleSkip(failedID: tuned.id, ticket: tuned.revision)
        }
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

    private func switchTransmission() async {
        guard !Task.isCancelled else { return }
        let mine = begin()
        defer { if run == mine { changing = false } }
        let next = transmission.channelNumber == 1 ? 2 : 1
        source = .transmission(next)
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
