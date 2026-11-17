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
