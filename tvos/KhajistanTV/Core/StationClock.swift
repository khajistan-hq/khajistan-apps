import Foundation

/// What is on air on one channel at one moment. Mirrors the object `KJStation.onAir` returns
/// on the site (archive/scripts/kj-station-clock.js), with `rosterIndex` added so a player can
/// step to the next programme in the slot without asking the clock again.
struct OnAir: Equatable, Sendable {
    let channelId: String
    let date: String
    let slot: Programming.Slot
    let rosterIndex: Int
    let show: Programming.Show?
    let programmeId: String
    let programme: Programming.Programme?
    let into: Double
    let seekTo: Double
    let startLabel: String
    let endLabel: String
    let nextShow: Programming.Show?
    let nextStart: String?
    /// The programme after this one and when it starts (owner, 2026-11-08: "now playing and up
    /// next"), as `KJStation.onAir` gives them on the site. Nil past the month's grid.
    var nextProgrammeId: String? = nil
    var nextProgramme: Programming.Programme? = nil
    var nextProgrammeStart: String? = nil
    /// True when the next programme belongs to this slot's show, false when the next slot opens.
    var nextInSlot = false
    /// What every surface prints, decided once (kj-station-clock.js computes the same three):
    /// Now is the programme's clean title, else its show; Up next is the programme at `nextAt` by
    /// its clean title, else by its show, and never Now itself.
    var nowName: String? = nil
    var nextName: String? = nil
    var nextAt: String? = nil
}

/// One strip of a channel's schedule as the guide lists it: when it starts and ends, and whose
/// show it is. The show is nil when the schedule names one its `shows` lacks.
struct ScheduleStrip: Equatable, Sendable {
    let date: String
    let slot: Programming.Slot
    let show: Programming.Show?

    var startLabel: String { slot.start }
    var endLabel: String { StationClock.endLabel(slot) }
}

/// The one answer to "what is on Khajistan TV right now", ported from kj-station-clock.js.
///
/// A SIGNAL COMES FROM SOMEWHERE: every reading is taken in Pakistan Standard Time (UTC+5, no
/// daylight saving), so the station's day is the same for every viewer in every timezone. The
/// civil-date arithmetic below is integer-only and takes no Calendar, which is what keeps it
/// identical to the JS's UTC getters on a shifted Date and free of any locale.
///
/// Everything is pure: the schedule is passed in, never held. `onAir` is nil when the schedule
/// does not cover the moment (the month runs out), which is a real state of the station and not
/// an error. Strips are read in SECONDS (`Slot.startSecond`, `lengthSeconds`), as the site reads
/// them, and an evening strip may run past midnight into the next day.
enum StationClock {
    static let utcOffsetMinutes = 300
    static let daySeconds = 86_400.0
    static let tzLabel = "PKT"

    // MARK: Station time

    /// The ISO day, minute of day and second of day in station time. Seconds are whole.
    static func stationNow(_ date: Date) -> (iso: String, minutes: Int, seconds: Int) {
        let epoch = date.timeIntervalSince1970
        let whole = abs(epoch) < 1e15 ? Int(floor(epoch)) : 0
        let shifted = whole + utcOffsetMinutes * 60
        let dayNumber = floorDiv(shifted, 86_400)
        let secondOfDay = shifted - dayNumber * 86_400
        return (isoString(civil(fromDayNumber: dayNumber)), secondOfDay / 60, secondOfDay)
    }

    /// "yyyy-MM" in station time: which programming-YYYY-MM.json holds this moment.
    static func stationMonth(_ date: Date) -> String {
        String(stationNow(date).iso.prefix(7))
    }

    // MARK: Schedule lookups

    static func channelId(_ p: Programming, number: Int) -> String? {
        p._meta.channels.first { $0.number == number }?.id
    }

    /// The channel numbers the schedule names, lowest first. The schedule is the only list.
    static func channelNumbers(_ p: Programming) -> [Int] {
        p._meta.channels.map(\.number).sorted()
    }

    /// The channel `step` places on from `number`, round the dial: Channel Up from the last
    /// channel is the first, Channel Down from the first is the last. From a number the schedule
    /// does not name, the first channel.
    static func channel(_ p: Programming, from number: Int, step: Int) -> Int {
        let numbers = channelNumbers(p)
        guard let index = numbers.firstIndex(of: number) else { return numbers.first ?? number }
        let count = numbers.count
        return numbers[((index + step) % count + count) % count]
    }

    static func day(_ p: Programming, iso: String) -> Programming.Day? {
        p.days.first { $0.date == iso }
    }

    /// Yesterday's strips, for a show still running after midnight. On the 1st yesterday is in
    /// the previous month's file, so each month file carries it as `prev_day` (kj-station-clock.js
    /// lateStrips).
    static func lateStrips(_ p: Programming, channel: String, iso: String) -> [Programming.Slot] {
        guard let yesterday = isoDay(iso, offset: -1) else { return [] }
        let prev = day(p, iso: yesterday) ?? p.prev_day.flatMap { $0.date == yesterday ? $0 : nil }
        return prev?.channels[channel] ?? []
    }

    /// The slot covering a moment, and the day it is filed under. Every strip is filed on the day
    /// it STARTS, so containment answers, plus yesterday's last strip when a show runs past
    /// midnight (kj-station-clock.js slotAt). `second` is seconds since 00:00 station time.
    static func locate(_ p: Programming, channel: String, iso: String, second: Double) -> (slot: Programming.Slot, date: String)? {
        if let slot = (day(p, iso: iso)?.channels[channel] ?? []).first(where: { second >= $0.startSecond && second < $0.endSecond }) {
            return (slot, iso)
        }
        let late = second + daySeconds
        guard let slot = lateStrips(p, channel: channel, iso: iso).first(where: { late >= $0.startSecond && late < $0.endSecond }),
              let yesterday = isoDay(iso, offset: -1) else { return nil }
        return (slot, yesterday)
    }

    /// The slot on air at the top of `minute`, or at `second` when given.
    static func slotAt(_ p: Programming, channel: String, iso: String, minute: Int, second: Double? = nil) -> Programming.Slot? {
        locate(p, channel: channel, iso: iso, second: second ?? Double(minute * 60))?.slot
    }

    /// Where a strip ends, as the site labels it: the minute, rounded up.
    static func endLabel(_ slot: Programming.Slot) -> String {
        clockLabel(Int((slot.endSecond / 60).rounded(.up)))
    }

    /// How long a programme runs ON AIR. `seconds` is the whole file; `nominal_minutes` is the
    /// placeholder the grid was laid out from (8 minutes when that is missing too). The head
    /// and tail trims are where the reel is read past, so they are not airtime.
    static func runSeconds(_ prog: Programming.Programme?) -> Double {
        let whole: Double
        if let seconds = prog?.seconds, seconds > 0 {
            whole = seconds
        } else {
            let nominal = prog?.nominal_minutes ?? 0
            whole = (nominal != 0 ? nominal : 8) * 60
        }
        return max(1, whole - (prog?.clean_start ?? 0) - (prog?.clean_end ?? 0))
    }

    /// Where inside a slot the clock has reached: which roster entry, and how many seconds into
    /// it. Seconds and not minutes, because a set that rounds to the minute always joins on a
    /// cut. A roster shorter than its slot runs round again (the floating remainder, as in JS).
    static func positionInSlot(_ p: Programming, slot: Programming.Slot, second: Int) -> (index: Int, into: Double) {
        var elapsed = Double(second) - slot.startSecond
        if elapsed < 0 { elapsed += daySeconds }   // a strip from yesterday that ran past midnight
        elapsed = max(0, elapsed)
        let lengths = slot.programmes.map { runSeconds(programme(p, index: $0)) }
        let total = lengths.reduce(0.0, +)
        guard total > 0 else { return (0, 0) }
        var remaining = elapsed.truncatingRemainder(dividingBy: total)
        for (index, length) in lengths.enumerated() {
            if remaining < length { return (index, remaining) }
            remaining -= length
        }
        return (0, 0)
    }

    /// The first strip that starts after `minute` (or `second`) today, else the first strip of
    /// the next calendar day, else nil (the month's grid ends).
    static func nextSlot(_ p: Programming, channel: String, iso: String, minute: Int, second: Double? = nil) -> (slot: Programming.Slot, date: String)? {
        guard let today = day(p, iso: iso) else { return nil }
        if let slot = earliest(today.channels[channel] ?? [], startingAfter: second ?? Double(minute * 60)) {
            return (slot, iso)
        }
        guard let tomorrowIso = isoDay(iso, offset: 1), let tomorrow = day(p, iso: tomorrowIso),
              let first = earliest(tomorrow.channels[channel] ?? [], startingAfter: -.infinity) else { return nil }
        return (first, tomorrowIso)
    }

    static func clockLabel(_ minutes: Int) -> String {
        pad2(floorDiv(minutes, 60) % 24) + ":" + pad2(minutes % 60)
    }

    // MARK: On air

    static func onAir(_ p: Programming, channelId: String, at date: Date) -> OnAir? {
        let now = stationNow(date)
        let second = Double(now.seconds)
        guard let hit = locate(p, channel: channelId, iso: now.iso, second: second),
              !hit.slot.programmes.isEmpty else { return nil }
        let slot = hit.slot
        let position = positionInSlot(p, slot: slot, second: now.seconds)
        // An index outside programme_order names no programme; the station cannot air it.
        guard let id = programmeId(p, index: slot.programmes[position.index]) else { return nil }
        let programme = p.programmes[id]
        let next = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: second)
        return withNextProgramme(OnAir(
            channelId: channelId,
            // The day the strip is filed under: yesterday's, for a show still running past
            // midnight. A caller keys on it, and keying on today would read 00:00 as a new slot.
            date: hit.date,
            slot: slot,
            rosterIndex: position.index,
            show: p.shows[slot.show],
            programmeId: id,
            programme: programme,
            into: position.into,
            // The file offset is the leader the reel is read past plus how far the slot has run.
            seekTo: (programme?.clean_start ?? 0) + position.into,
            startLabel: slot.start,
            endLabel: endLabel(slot),
            nextShow: next.flatMap { p.shows[$0.slot.show] },
            nextStart: next?.slot.start
        ), in: p, slotSecond: slotSecond(hit.date, now: now), iso: now.iso, second: second)
    }

    /// `onAir` for a channel given by its number (1 or 2); nil for a number the schedule lacks.
    static func onAir(_ p: Programming, channel number: Int, at date: Date) -> OnAir? {
        guard let id = channelId(p, number: number) else { return nil }
        return onAir(p, channelId: id, at: date)
    }

    /// When the channel is next on air (the next strip's start label), for the off-air state.
    static func returnTime(_ p: Programming, channelId: String, at date: Date) -> String? {
        let now = stationNow(date)
        return nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: Double(now.seconds))?.slot.start
    }

    /// The clock read in the frame of the day a strip is filed under: past 86 400 the day after,
    /// nil on any other day. One reading, so a strip from yesterday keeps counting past midnight.
    static func slotSecond(_ filed: String, now: (iso: String, minutes: Int, seconds: Int)) -> Double? {
        if now.iso == filed { return Double(now.seconds) }
        if isoDay(filed, offset: 1) == now.iso { return Double(now.seconds) + daySeconds }
        return nil
    }

    /// The programme after `current`, for the moment a file ends. While the clock is still
    /// inside the slot it walks the SLOT's roster and never re-reads the clock: a file that ends
    /// a second early ends while the clock still says it is on, and asking the clock then hands
    /// back the programme that just finished. Once the slot is over it is `onAir` again.
    static func following(_ current: OnAir, in p: Programming, at date: Date) -> OnAir? {
        let now = stationNow(date)
        let slot = current.slot
        let at = slotSecond(current.date, now: now)
        let insideSlot = at.map { $0 >= slot.startSecond && $0 < slot.endSecond } ?? false
        guard insideSlot, !slot.programmes.isEmpty else {
            return onAir(p, channelId: current.channelId, at: date)
        }
        let count = slot.programmes.count
        let nextIndex = (((current.rosterIndex + 1) % count) + count) % count
        guard let id = programmeId(p, index: slot.programmes[nextIndex]) else { return nil }
        let programme = p.programmes[id]
        return withNextProgramme(OnAir(
            channelId: current.channelId,
            date: current.date,
            slot: slot,
            rosterIndex: nextIndex,
            show: current.show,
            programmeId: id,
            programme: programme,
            into: 0,
            seekTo: programme?.clean_start ?? 0,
            startLabel: current.startLabel,
            endLabel: current.endLabel,
            nextShow: current.nextShow,
            nextStart: current.nextStart
        ), in: p, slotSecond: at, iso: now.iso, second: Double(now.seconds))
    }

    /// The programme after the one on air, the website's rule (kj-station-clock.js onAir):
    /// inside the slot the roster's next entry, once this one ends before the slot does; else the
    /// next slot opens on its first. A roster of one that runs round again is not "next".
    /// `slotSecond` is now in the strip's own day (see slotSecond(_:now:)); `iso` and `second`
    /// are today's, for the walk to the next strip.
    static func withNextProgramme(_ air: OnAir, in p: Programming, slotSecond: Double?, iso: String, second: Double) -> OnAir {
        var out = air
        let endsAt = (slotSecond ?? second) + runSeconds(air.programme) - air.into
        let slot = air.slot
        if endsAt < slot.endSecond, slot.programmes.count > 1 {
            let index = slot.programmes[(air.rosterIndex + 1) % slot.programmes.count]
            out.nextProgrammeId = programmeId(p, index: index)
            out.nextProgrammeStart = clockLabel(Int(endsAt / 60))
            out.nextInSlot = true
        } else if let next = nextSlot(p, channel: air.channelId, iso: iso, minute: 0, second: second),
                  let first = next.slot.programmes.first {
            out.nextProgrammeId = programmeId(p, index: first)
            out.nextProgrammeStart = next.slot.start
        }
        out.nextProgramme = out.nextProgrammeId.flatMap { p.programmes[$0] }
        // The names, the site's rule (kj-station-clock.js onAir): Up next is the first programme
        // after this one, in this slot, whose name differs from Now, at the minute it starts;
        // failing that, the next slot's first programme by its title, else by its show.
        let next = nextSlot(p, channel: air.channelId, iso: iso, minute: 0, second: second)
        let nextSlotShow = next.flatMap { p.shows[$0.slot.show] }
        func title(_ id: String?) -> String? { nonEmpty(id.flatMap { p.programmes[$0]?.display_title }) }
        out.nowName = title(air.programmeId) ?? nonEmpty(air.show?.name)
        // Neither name already on screen is said again: not Now, and not the show the plate carries.
        let nowName = out.nowName
        func said(_ name: String?) -> Bool { name == nil || name == nowName || name == air.show?.name }
        let count = slot.programmes.count
        var t = endsAt
        var k = 1
        while k < count, t < slot.endSecond {
            let id = programmeId(p, index: slot.programmes[(air.rosterIndex + k) % count])
            let name = title(id)                 // an untitled programme is walked past, not named
            if !said(name) {
                out.nextName = name
                out.nextAt = clockLabel(Int(t / 60))
                break
            }
            t += runSeconds(id.flatMap { p.programmes[$0] })
            k += 1
        }
        if out.nextName == nil, let next {
            // The next slot: its first programme or its show if new to the screen, else down its
            // roster, each programme at the minute it starts (the site's rule).
            let roster = next.slot.programmes
            let first = roster.first.flatMap { programmeId(p, index: $0) }
            if let name = [title(first), nonEmpty(nextSlotShow?.name)].first(where: { !said($0) }) {
                out.nextName = name
                out.nextAt = next.slot.start
            } else {
                var u = next.slot.startSecond
                let end = next.slot.endSecond
                for index in roster where u < end {
                    let id = programmeId(p, index: index)
                    if let name = title(id), !said(name) {
                        out.nextName = name
                        out.nextAt = clockLabel(Int(u / 60))
                        break
                    }
                    u += runSeconds(id.flatMap { p.programmes[$0] })
                }
            }
        }
        return out
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: Up next

    /// The strips that start after `date` on a channel, soonest first, at most `count` of them:
    /// what the station page and the player list under "Up next". The walk is nextSlot's, so it
    /// crosses midnight into the next day the schedule holds and stops where the month's grid
    /// ends; a channel on air and a channel off air both start from the first strip after now.
    static func upcoming(_ p: Programming, channelId: String, at date: Date, count: Int) -> [ScheduleStrip] {
        let now = stationNow(date)
        var found: [ScheduleStrip] = []
        var cursor = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: Double(now.seconds))
        while let hit = cursor, found.count < count {
            found.append(ScheduleStrip(date: hit.date, slot: hit.slot, show: p.shows[hit.slot.show]))
            cursor = nextSlot(p, channel: channelId, iso: hit.date, minute: 0, second: hit.slot.startSecond)
        }
        return found
    }

    /// Whole seconds until the slot `air` belongs to ends, or nil once the clock has left it
    /// (another day, or past its end). The player uses it for the notice before a handover and
    /// to tune the next strip the moment this one ends.
    static func secondsLeft(in air: OnAir, at date: Date) -> Int? {
        guard let at = slotSecond(air.date, now: stationNow(date)),
              at >= air.slot.startSecond, at < air.slot.endSecond else { return nil }
        return Int((air.slot.endSecond - at).rounded(.up))
    }

    // MARK: Helpers

    private static func programmeId(_ p: Programming, index: Int) -> String? {
        p.programme_order.indices.contains(index) ? p.programme_order[index] : nil
    }

    private static func programme(_ p: Programming, index: Int) -> Programming.Programme? {
        programmeId(p, index: index).flatMap { p.programmes[$0] }
    }

    /// The strip with the smallest start above `second`; on a tie the earlier one in the
    /// file, which is what a stable sort followed by "first match" gives in the JS.
    private static func earliest(_ strips: [Programming.Slot], startingAfter second: Double) -> Programming.Slot? {
        var best: Programming.Slot?
        for strip in strips where strip.startSecond > second {
            if let held = best, held.startSecond <= strip.startSecond { continue }
            best = strip
        }
        return best
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func isoString(_ civil: (year: Int, month: Int, day: Int)) -> String {
        "\(civil.year)-\(pad2(civil.month))-\(pad2(civil.day))"
    }

    /// The calendar day `offset` days from an ISO day, by day-number arithmetic. Nil for a string
    /// that is not a real yyyy-MM-dd date (the JS gets an Invalid Date there and finds no day).
    private static func isoDay(_ iso: String, offset: Int) -> String? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        return isoString(civil(fromDayNumber: dayNumber(year: year, month: month, day: day) + offset))
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient
    }

    // Proleptic Gregorian civil-date conversion (Howard Hinnant's algorithms), day 0 = 1970-01-01.
    private static func civil(fromDayNumber days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

/// The server's time, not the device's (2026-11-10, ported from kj-station-clock.js). A device
/// whose clock is wrong joined every programme that far behind everyone else. One HEAD of the
/// site's clock file reads the server's `Date` header. The header is whole seconds, so a reading
/// is only good to about ±0.5 s plus half the round trip: a device already within `floor` of it
/// keeps its own clock, because a coarser correction would move an accurate set off the second.
/// Read at launch and again (`force`) each time the app comes back to the screen: an Apple TV
/// can start before its own clock is set, and a skew kept after the device is corrected would
/// put the set that far AHEAD. A failed reading is never kept, so the next call asks again.
enum ServerClock {
    static let floor: TimeInterval = 2
    /// A request that hangs must not hold the first tune.
    static let wait: TimeInterval = 1.5
    private static let lock = NSLock()
    nonisolated(unsafe) private static var skew: TimeInterval = 0
    nonisolated(unsafe) private static var reading: Task<TimeInterval?, Never>?

    /// Server time minus device time, in seconds; 0 while no reading is held or the device is close.
    static var currentSkew: TimeInterval { lock.withLock { skew } }
    static func now(_ real: Date = Date()) -> Date { real.addingTimeInterval(currentSkew) }

    /// +0.5: the header truncates to the second. Returns the skew now in force.
    @discardableResult
    static func apply(server: Date, sent: Date, received: Date) -> TimeInterval {
        guard received >= sent else { return currentSkew }
        let midpoint = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
        let s = server.addingTimeInterval(0.5).timeIntervalSince(midpoint)
        return lock.withLock { skew = abs(s) > floor ? s : 0; return skew }
    }

    static func parseHTTPDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: text)
    }

    /// Concurrent callers share one request. `force` asks the server again even when a reading
    /// is held. Never throws: no answer keeps the skew in force (0 before any reading), which is
    /// what the station ran on before this existed.
    @discardableResult
    static func sync(clockFile: URL, session: URLSession = .shared, force: Bool = false) async -> TimeInterval {
        let task: Task<TimeInterval?, Never> = lock.withLock {
            if !force, let reading { return reading }
            let made = Task<TimeInterval?, Never> {
                var request = URLRequest(url: clockFile.appending(queryItems: [URLQueryItem(name: "clock", value: String(Int(Date().timeIntervalSince1970 * 1000)))]),
                                         cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: wait)
                request.httpMethod = "HEAD"
                let sent = Date()
                guard let (_, response) = try? await session.data(for: request),
                      let server = parseHTTPDate((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"))
                else { return nil }
                return apply(server: server, sent: sent, received: Date())
            }
            reading = made
            return made
        }
        if let read = await task.value { return read }
        lock.withLock { if reading == task { reading = nil } }   // a failed reading is not kept
        return currentSkew
    }
}
