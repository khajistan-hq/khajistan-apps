/// Who closed the picture-in-picture window, and so what follows when it has gone. Kept apart from
/// AVKit so every order of events can be tested (Tests/CoreTests).
///
/// Three ways to close it, and AVKit asks to "restore the interface" after each of them, so the
/// reason is remembered from the asking and read when the window has gone:
/// - Full screen (the window's own control, or the PiP bar): the player screen opens again.
/// - Close (the window's own close, or the bar's): the signal ends.
/// - Stop: another signal started, or the screen took the picture over; nothing else happens.
struct PiPLifecycle: Equatable {
    enum Reason: Equatable { case none, restore, close, stop }

    private(set) var reason: Reason = .none
    private(set) var isActive = false

    /// The window opened.
    mutating func started() {
        isActive = true
        reason = .none
    }

    /// The viewer asked for full screen from the bar. True when the screen should open now.
    mutating func restoreAsked() -> Bool {
        guard isActive, reason == .none else { return false }
        reason = .restore
        return true
    }

    /// AVKit asks to restore the interface. True when that is the viewer asking from the window's
    /// own control, so the screen should open now; false when the bar already asked, or when the
    /// window is closing for Close or Stop.
    mutating func systemRestoreAsked() -> Bool {
        guard reason == .none else { return false }
        reason = .restore
        return true
    }

    /// Close from the bar. True when the window should be told to close.
    mutating func closeAsked() -> Bool {
        guard isActive, reason == .none else { return false }
        reason = .close
        return true
    }

    /// Stop: another signal started. True when the window should be told to close.
    mutating func stopAsked() -> Bool {
        guard isActive, reason != .restore, reason != .stop else { return false }
        reason = .stop
        return true
    }

    /// The window has gone. True when the signal should end with it: closed from the bar, or by
    /// the window's own close (AVKit stops without asking to restore).
    mutating func stopped() -> Bool {
        defer {
            isActive = false
            reason = .none
        }
        return reason == .close || reason == .none
    }
}

/// Follows a value that changes over time (the programme on air) and says when it has changed,
/// starting from what was already loaded. Used by the PiP window to load each programme's
/// subtitles after the screen that loaded the first has closed.
struct ChangeFollower<Key: Equatable> {
    private(set) var key: Key?

    init(loaded: Key?) { key = loaded }

    /// True when `now` differs from the last key seen, which is then remembered.
    mutating func changed(to now: Key?) -> Bool {
        guard now != key else { return false }
        key = now
        return true
    }
}

/// What the PiP window does with each reading of its player, ten times a second: what the bar shows
/// (playing or paused), and whether the window's own Play or Pause has to be passed on.
///
/// The bar's and the remote's Play/Pause are asked here (`ask`): the bar shows the asked state while
/// the player catches up (a Transmission Play retunes, which stops the picture for a moment), for ten
/// seconds at most. The window's own controls work AVPlayer directly. Only a pause of the item that
/// was playing, and a Play of that same item afterwards, are the window's: a new item loading paused
/// (a rejoin, a handover, a seek before play) is never, so a rejoin cannot set off another.
struct PiPPlayFollower {
    enum Event: Equatable { case none, windowPlay, windowPause }

    static let hold: Double = 10

    private(set) var shown: Bool
    private var asked: (playing: Bool, at: Double)?
    private var playingItem: ObjectIdentifier?
    private var pausedItem: ObjectIdentifier?

    init(playing: Bool) { shown = playing }

    /// The bar or the remote asked for `playing` at `now` (seconds).
    mutating func ask(_ playing: Bool, at now: Double) {
        asked = (playing, now)
        shown = playing
    }

    /// The player reads `playing` on `item` at `now`.
    mutating func read(playing: Bool, item: ObjectIdentifier?, at now: Double) -> Event {
        var askedNow = false
        if let asked {
            if asked.playing == playing || now - asked.at >= Self.hold {
                self.asked = nil
                askedNow = asked.playing == playing
            } else {
                return .none
            }
        }
        defer { shown = playing }
        if playing {
            let windowPlay = !shown && !askedNow && pausedItem != nil && pausedItem == item
            pausedItem = nil
            playingItem = item
            return windowPlay ? .windowPlay : .none
        }
        if pausedItem == nil, shown, !askedNow, item != nil, item == playingItem {
            pausedItem = item
            return .windowPause
        }
        if item != pausedItem { pausedItem = nil }
        return .none
    }
}

/// The caption the PiP window draws into a file's picture, read on every tick whether it is drawn
/// or not: the reading is what follows a Transmission handover (ProgrammeSubtitleFollower loads the
/// next programme and hands its track to tvOS), so a window showing a stream must still read.
enum PiPCaptionFeed {
    static func drawn(read: () -> String?, intoPicture: Bool) -> String? {
        let text = read()
        guard intoPicture, let text, !text.isEmpty else { return nil }
        return text
    }
}
