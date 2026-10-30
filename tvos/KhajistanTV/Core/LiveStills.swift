import Foundation

// The rules behind the Receiver's picture cards (Services/LiveStillsStore.swift): a still is a
// frame the viewer's own device takes from a channel's live stream, kept in memory and never
// written anywhere. These two types decide how many are kept and when the next one is taken;
// they know nothing of pictures, so the core tests can hold them to their numbers.

/// The stills on hand, by channel id, with a bound on what they cost together (bytes of decoded
/// pixels). Inserting past the bound drops the oldest first; a still older than `maxAge` reads as
/// missing, so a channel seen long ago is taken again. One that costs more than the whole bound is
/// refused.
struct StillCache<Value> {
    let costLimit: Int
    let maxAge: TimeInterval
    private var entries: [String: (value: Value, cost: Int, at: TimeInterval)] = [:]
    /// Oldest first.
    private var order: [String] = []
    private(set) var totalCost = 0

    init(costLimit: Int, maxAge: TimeInterval) {
        self.costLimit = costLimit
        self.maxAge = maxAge
    }

    var count: Int { entries.count }

    func value(for id: String, now: TimeInterval) -> Value? {
        guard let entry = entries[id], now - entry.at <= maxAge else { return nil }
        return entry.value
    }

    mutating func insert(_ value: Value, for id: String, cost: Int, now: TimeInterval) {
        remove(id)
        guard cost <= costLimit else { return }
        entries[id] = (value, cost, now)
        order.append(id)
        totalCost += cost
        while totalCost > costLimit, let oldest = order.first {
            remove(oldest)
        }
    }

    mutating func remove(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        totalCost -= entry.cost
        order.removeAll { $0 == id }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }
}

/// When the next still is taken, for one visit to a page: one at a time, at least `spacing`
/// seconds between starts, at most `perVisit` in all, each channel tried once. The page says which
/// channels it wants, nearest the viewer's focus first.
struct StillPlan {
    static let spacing: TimeInterval = 1.5
    static let perVisit = 24

    private(set) var started = 0
    private(set) var lastStart: TimeInterval?
    private(set) var busy = false
    private var tried: Set<String> = []

    /// The channel to take now, or nil: one is being taken, the visit has had its share, the last
    /// start was too recent, or every wanted channel has a still or has been tried. A channel
    /// returned here counts as tried, whether or not a picture comes of it.
    mutating func next(wanted: [String], has: (String) -> Bool, now: TimeInterval) -> String? {
        guard !busy, started < Self.perVisit else { return nil }
        if let lastStart, now - lastStart < Self.spacing { return nil }
        guard let id = wanted.first(where: { !tried.contains($0) && !has($0) }) else { return nil }
        tried.insert(id)
        started += 1
        lastStart = now
        busy = true
        return id
    }

    /// The still under way is done, with a picture or without.
    mutating func finished() { busy = false }

    /// Seconds until a start may come, from `now`.
    func wait(now: TimeInterval) -> TimeInterval {
        guard let lastStart else { return 0 }
        return max(0, Self.spacing - (now - lastStart))
    }

    var exhausted: Bool { started >= Self.perVisit }
}
