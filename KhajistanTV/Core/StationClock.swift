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
}

/// One strip of a channel's schedule as the guide lists it: when it starts and ends, and whose
/// show it is. The show is nil when the schedule names one its `shows` lacks.
struct ScheduleStrip: Equatable, Sendable {
    let date: String
    let slot: Programming.Slot
    let show: Programming.Show?

    var startLabel: String { slot.start }
    var endLabel: String { StationClock.clockLabel(slot.start_minute + slot.minutes) }
}

/// The one answer to "what is on Khajistan TV right now", ported from kj-station-clock.js.
///
/// A SIGNAL COMES FROM SOMEWHERE: every reading is taken in Pakistan Standard Time (UTC+5, no
/// daylight saving), so the station's day is the same for every viewer in every timezone. The
/// civil-date arithmetic below is integer-only and takes no Calendar, which is what keeps it
/// identical to the JS's UTC getters on a shifted Date and free of any locale.
///
/// Everything is pure: the schedule is passed in, never held. `onAir` is nil when the schedule
/// does not cover the moment (the grid ends at 24:00 and the month runs out), which is a real
/// state of the station and not an error.
enum StationClock {
    static let utcOffsetMinutes = 300
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

    static func day(_ p: Programming, iso: String) -> Programming.Day? {
        p.days.first { $0.date == iso }
    }

    /// The slot covering a minute of a day. Strips are filed on the day they start and the
    /// grid never crosses midnight, so plain containment answers.
    static func slotAt(_ p: Programming, channel: String, iso: String, minute: Int) -> Programming.Slot? {
        guard let day = day(p, iso: iso) else { return nil }
        return (day.channels[channel] ?? []).first {
            minute >= $0.start_minute && minute < $0.start_minute + $0.minutes
        }
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
        let elapsed = Double(max(0, second - slot.start_minute * 60))
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

    /// The first strip that starts after `minute` today, else the first strip of the next
    /// calendar day, else nil (the month's grid ends).
    static func nextSlot(_ p: Programming, channel: String, iso: String, minute: Int) -> (slot: Programming.Slot, date: String)? {
        guard let today = day(p, iso: iso) else { return nil }
        if let slot = earliest(today.channels[channel] ?? [], startingAfter: minute) {
            return (slot, iso)
        }
        guard let tomorrowIso = isoDay(after: iso), let tomorrow = day(p, iso: tomorrowIso),
              let first = earliest(tomorrow.channels[channel] ?? [], startingAfter: Int.min) else { return nil }
        return (first, tomorrowIso)
    }

    static func clockLabel(_ minutes: Int) -> String {
        pad2(floorDiv(minutes, 60) % 24) + ":" + pad2(minutes % 60)
    }

    // MARK: On air

    static func onAir(_ p: Programming, channelId: String, at date: Date) -> OnAir? {
        let now = stationNow(date)
        guard let slot = slotAt(p, channel: channelId, iso: now.iso, minute: now.minutes),
              !slot.programmes.isEmpty else { return nil }
        let position = positionInSlot(p, slot: slot, second: now.seconds)
        // An index outside programme_order names no programme; the station cannot air it.
        guard let id = programmeId(p, index: slot.programmes[position.index]) else { return nil }
        let programme = p.programmes[id]
        let next = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes)
        return OnAir(
            channelId: channelId,
            date: now.iso,
            slot: slot,
            rosterIndex: position.index,
            show: p.shows[slot.show],
            programmeId: id,
            programme: programme,
            into: position.into,
            // The file offset is the leader the reel is read past plus how far the slot has run.
            seekTo: (programme?.clean_start ?? 0) + position.into,
            startLabel: slot.start,
            endLabel: clockLabel(slot.start_minute + slot.minutes),
            nextShow: next.flatMap { p.shows[$0.slot.show] },
            nextStart: next?.slot.start
        )
    }

    /// `onAir` for a channel given by its number (1 or 2); nil for a number the schedule lacks.
    static func onAir(_ p: Programming, channel number: Int, at date: Date) -> OnAir? {
        guard let id = channelId(p, number: number) else { return nil }
        return onAir(p, channelId: id, at: date)
    }

    /// When the channel is next on air (the next strip's start label), for the off-air state.
    static func returnTime(_ p: Programming, channelId: String, at date: Date) -> String? {
        let now = stationNow(date)
        return nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes)?.slot.start
    }

    /// The programme after `current`, for the moment a file ends. While the clock is still
    /// inside the slot it walks the SLOT's roster and never re-reads the clock: a file that ends
    /// a second early ends while the clock still says it is on, and asking the clock then hands
    /// back the programme that just finished. Once the slot is over it is `onAir` again.
    static func following(_ current: OnAir, in p: Programming, at date: Date) -> OnAir? {
        let now = stationNow(date)
        let slot = current.slot
        let insideSlot = now.iso == current.date
            && now.minutes >= slot.start_minute
            && now.minutes < slot.start_minute + slot.minutes
        guard insideSlot, !slot.programmes.isEmpty else {
            return onAir(p, channelId: current.channelId, at: date)
        }
        let count = slot.programmes.count
        let nextIndex = (((current.rosterIndex + 1) % count) + count) % count
        guard let id = programmeId(p, index: slot.programmes[nextIndex]) else { return nil }
        let programme = p.programmes[id]
        return OnAir(
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
        )
    }

    // MARK: Up next

    /// The strips that start after `date` on a channel, soonest first, at most `count` of them:
    /// what the station page and the player list under "Up next". The walk is nextSlot's, so it
    /// crosses midnight into the next day the schedule holds and stops where the month's grid
    /// ends; a channel on air and a channel off air both start from the first strip after now.
    static func upcoming(_ p: Programming, channelId: String, at date: Date, count: Int) -> [ScheduleStrip] {
        let now = stationNow(date)
        var found: [ScheduleStrip] = []
        var cursor = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes)
        while let hit = cursor, found.count < count {
            found.append(ScheduleStrip(date: hit.date, slot: hit.slot, show: p.shows[hit.slot.show]))
            cursor = nextSlot(p, channel: channelId, iso: hit.date, minute: hit.slot.start_minute)
        }
        return found
    }

    /// Whole seconds until the slot `air` belongs to ends, or nil once the clock has left it
    /// (another day, or past its end). The player uses it for the notice before a handover and
    /// to tune the next strip the moment this one ends.
    static func secondsLeft(in air: OnAir, at date: Date) -> Int? {
        let now = stationNow(date)
        let end = (air.slot.start_minute + air.slot.minutes) * 60
        guard now.iso == air.date, now.seconds >= air.slot.start_minute * 60, now.seconds < end else { return nil }
        return end - now.seconds
    }

    // MARK: Helpers

    private static func programmeId(_ p: Programming, index: Int) -> String? {
        p.programme_order.indices.contains(index) ? p.programme_order[index] : nil
    }

    private static func programme(_ p: Programming, index: Int) -> Programming.Programme? {
        programmeId(p, index: index).flatMap { p.programmes[$0] }
    }

    /// The strip with the smallest start_minute above `minute`; on a tie the earlier one in the
    /// file, which is what a stable sort followed by "first match" gives in the JS.
    private static func earliest(_ strips: [Programming.Slot], startingAfter minute: Int) -> Programming.Slot? {
        var best: Programming.Slot?
        for strip in strips where strip.start_minute > minute {
            if let held = best, held.start_minute <= strip.start_minute { continue }
            best = strip
        }
        return best
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func isoString(_ civil: (year: Int, month: Int, day: Int)) -> String {
        "\(civil.year)-\(pad2(civil.month))-\(pad2(civil.day))"
    }

    /// The calendar day after an ISO day, by day-number arithmetic. Nil for a string that is not
    /// a real yyyy-MM-dd date (the JS gets an Invalid Date there and finds no day).
    private static func isoDay(after iso: String) -> String? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        return isoString(civil(fromDayNumber: dayNumber(year: year, month: month, day: day) + 1))
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
