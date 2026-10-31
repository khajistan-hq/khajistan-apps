import Foundation

/// A monotonic-time policy, independent of Network.framework. Reconnects cannot be lost behind
/// an in-flight check. Failures back off 30/60/120/240/480 seconds; at most six starts per hour,
/// including foreground/network signals. This limits requests, never extends license validity.
struct OfflineReconciliationSchedule {
    private(set) var connected = false
    private(set) var next: TimeInterval?
    private(set) var inFlight: Int?
    private var version = 0
    private var failures = 0
    private var starts: [TimeInterval] = []

    mutating func network(_ value: Bool, at now: TimeInterval) {
        let reconnected = value && !connected
        connected = value
        if !value { next = nil }
        else if reconnected { request(at: now) }
    }

    mutating func request(at now: TimeInterval) {
        guard connected else { return }
        version += 1
        if inFlight == nil { schedule(now, now: now) }
    }

    mutating func begin(at now: TimeInterval) -> Int? {
        guard connected, inFlight == nil, let next, now >= next else { return nil }
        starts.removeAll { now - $0 >= 3600 }
        guard starts.count < 6 else { self.next = starts[0] + 3600; return nil }
        starts.append(now); inFlight = version; self.next = nil
        return version
    }

    mutating func finish(_ token: Int, succeeded: Bool, at now: TimeInterval) {
        guard inFlight == token else { return }
        inFlight = nil
        guard connected else { next = nil; return }
        if token != version { schedule(now, now: now) }
        else if succeeded { failures = 0; next = nil }
        else {
            failures += 1
            schedule(now + min(480, 30 * pow(2, Double(min(failures - 1, 4)))), now: now)
        }
    }

    mutating func stop() { connected = false; next = nil; inFlight = nil }

    private mutating func schedule(_ target: TimeInterval, now: TimeInterval) {
        starts.removeAll { now - $0 >= 3600 }
        next = starts.count < 6 ? target : max(target, starts[0] + 3600)
    }
}
