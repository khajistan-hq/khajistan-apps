import AVFoundation
import MediaPlayer
import Observation

@MainActor @Observable
final class RadioPlayer {
    var channels: [RadioChannel] = []
    var selected: RadioChannel?
    var isLoadingCatalogue = false
    var isTuning = false
    var isPlaying = false
    var error: String?
    private let service = RadioService()
    private let player = AVPlayer()
    private var tuneTask: Task<Void, Never>?
    private var tuneID = UUID()
    private var isResolving = false
    private var connectionTimeout: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init() {
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isTuning = self.isResolving || self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlaying()
            }
        }
        let commands = MPRemoteCommandCenter.shared()
        remoteTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }))
        remoteTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }))
        remoteTargets.append((commands.togglePlayPauseCommand, commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success
        }))
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let kind = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if kind == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.pause() } }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.pause(); self.error = "The station stopped responding. Tap play to reconnect."
            }
        })
    }
    func load() async {
        guard !isLoadingCatalogue else { return }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            channels = try await service.catalogue(); error = nil
            if let selected, !channels.contains(where: { $0.id == selected.id }) {
                pause(); error = "This station has been removed from the current receiver directory."
            }
        }
        catch { self.error = error.localizedDescription }
    }
    func play(_ channel: RadioChannel) {
        tuneTask?.cancel(); connectionTimeout?.cancel()
        isResolving = true
        player.pause(); player.replaceCurrentItem(with: nil)
        selected = channel; isPlaying = false; isTuning = true; error = nil
        let id = UUID(); tuneID = id
        tuneTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.service.resolve(channel)
                try Task.checkCancellation()
                guard self.tuneID == id else { return }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                let item = AVPlayerItem(url: url)
                self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                    let failure = observed.status == .failed
                    Task { @MainActor in
                        guard let self, self.tuneID == id, failure else { return }
                        self.pause(); self.error = "This signal could not be played. Try another station or open the web receiver."
                    }
                }
                self.player.replaceCurrentItem(with: item)
                self.isResolving = false
                self.player.play(); self.updateNowPlaying()
                self.connectionTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, self.tuneID == id, !self.isPlaying else { return }
                    self.pause(); self.error = "The signal did not start. Tap play to reconnect."
                }
            } catch is CancellationError { }
            catch {
                guard self.tuneID == id else { return }
                self.isResolving = false; self.isTuning = false; self.error = error.localizedDescription
            }
        }
    }
    func pause() {
        tuneTask?.cancel(); connectionTimeout?.cancel(); tuneID = UUID(); isResolving = false
        player.pause(); isPlaying = false; isTuning = false
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func resume() { if let selected { play(selected) } }
    func toggle() { if isPlaying || isTuning { pause() } else { resume() } }
    private func updateNowPlaying() {
        guard let selected else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: selected.name,
            MPMediaItemPropertyArtist: selected.country ?? "Khajistan Receiver",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
