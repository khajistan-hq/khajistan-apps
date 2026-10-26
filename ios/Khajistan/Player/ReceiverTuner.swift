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

    init(clips: StationClips, receiver: ReceiverStore, transmission: TransmissionStore) {
        self.clips = clips
        self.receiver = receiver
        self.transmission = transmission
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

    // MARK: - Choosing

    func play(_ channel: Channel, in list: [Channel]) {
        // A directory pick is not a draw. Surf skips it only when it is the card at the cursor.
        shuffle.observe(channel.id)
        stop()
        self.list = list
        source = .live(channel)
        changeTask = Task { await open(channel) }
    }

    func playTransmission(_ number: Int) {
        stop()
        source = .transmission(number)
        changeTask = Task { await openTransmission(number) }
    }

    /// The next channel (1) or the one before (-1). Transmission has two, so either way switches.
    func step(_ delta: Int) {
        switch source {
        case .live(let current):
            let from = destination ?? current
            guard let position = list.firstIndex(where: { $0.id == from.id }) else { return }
            // The list Surf dealt does not wrap. Previous on its first card stays. Next past
            // its end deals the next permutation. A shelf opened by hand still wraps.
            switch SurfNavigation.step(delta: delta, from: position, count: list.count, surfList: shuffle.plays(list.map(\.id))) {
            case .stay:
                return
            case .deal:
                changeTask?.cancel()
                changeTask = Task { await dealNext(after: from) }
                return
            case .move(let index):
                let target = list[index]
                shuffle.observe(target.id)
                destination = target
                changeTask?.cancel()
                changeTask = Task { await change(to: target) }
            }
        case .transmission:
            changeTask?.cancel()
            changeTask = Task { await switchTransmission() }
        case nil:
            return
        }
    }

    /// A live signal paused is not the live signal any more: play tunes it afresh.
    func playPause() {
        switch source {
        case .live(let channel):
            if controller.state == .tuning {
                // Pause while connecting stops the connecting, or the signal would start anyway.
                tuneTask?.cancel()
                changeTask?.cancel()
                controller.stop()
                controller.state = .paused
                clips.uncover()
            } else if controller.state == .playing {
                controller.pause()
            } else {
                tune(channel)
            }
        case .transmission:
            if transmission.player.state == .playing {
                transmission.player.pause()
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
    /// True when the chosen scope has nothing that can play, until the medium, scope or region changes.
    private(set) var surfBlocked = false
    /// The deck Surf deals, shared with the step past the end of that deck.
    @ObservationIgnored private let shuffle = ShuffleSession()

    /// The medium, the scope or the region changed, so Surf can be tried again.
    func shuffleSelectionChanged() {
        shuffle.noteSelectionChanged()
        surfBlocked = false
        surfNote = nil
    }

    /// The next card of the deck kept in the Surf settings (owner, 2026-10-07). The deck is one
    /// permutation of the playable channels. Next and previous move through that order. The step
    /// past the end deals the next permutation.
    func surf() async {
        guard !surfing else { return }
        surfing = true
        surfNote = nil
        defer { surfing = false }
        await receiver.loadIndex()
        guard let index = receiver.index else {
            surfNote = "The receiver has not loaded."
            return
        }
        let (medium, scope, regionId) = shuffle.settings()
        guard let prepared = await shuffle.prepare(
            index: index, medium: medium, scope: scope, regionId: regionId,
            load: { try await self.receiver.channels(regionId: $0, cameras: false, fileOrder: true) }
        ) else {
            guard !Task.isCancelled else { return }
            surfNote = shuffle.note
            surfBlocked = shuffle.blocked
            return
        }
        guard !Task.isCancelled else { return }
        guard let pick = shuffle.commit(prepared, finishList: nil, playingId: destination?.id ?? channel?.id) else {
            guard !Task.isCancelled else { return }
            surfNote = shuffle.note
            surfBlocked = shuffle.blocked
            return
        }
        guard !Task.isCancelled else { return }
        surfBlocked = false
        play(pick.channel, in: pick.list)
    }

    /// Turns the receiver off.
    func stop() {
        tuneTask?.cancel()
        changeTask?.cancel()
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
        tuneTask?.cancel()
        controller.stop()
        controller.state = .tuning
        source = .live(target)
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

    private func begin() -> Int {
        run += 1
        changing = true
        return run
    }

    private func open(_ channel: Channel) async {
        let mine = begin()
        defer { if run == mine { changing = false } }
        clips.cover(caption: channel.name, animated: false)
        tune(channel)
        await controller.settled()
        guard !Task.isCancelled else { return }
        clips.uncover()
        settledAt = Date()
    }

    /// The card after the permutation on screen. The channel that was playing is the last id of
    /// that deck, so the new one does not open on it.
    private func dealNext(after from: Channel) async {
        guard let index = receiver.index else { return }
        let (medium, scope, regionId) = shuffle.settings()
        let order = list.map(\.id)
        guard let prepared = await shuffle.prepare(
            index: index, medium: medium, scope: scope, regionId: regionId,
            load: { try await self.receiver.channels(regionId: $0, cameras: false, fileOrder: true) }
        ) else {
            guard !Task.isCancelled else { return }
            surfNote = shuffle.note
            surfBlocked = shuffle.blocked
            return
        }
        guard !Task.isCancelled else { return }
        guard let pick = shuffle.commit(prepared, finishList: order, playingId: from.id) else {
            guard !Task.isCancelled else { return }
            surfNote = shuffle.note
            surfBlocked = shuffle.blocked
            return
        }
        guard !Task.isCancelled else { return }
        list = pick.list
        destination = pick.channel
        await change(to: pick.channel)
    }

    private func change(to target: Channel) async {
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
