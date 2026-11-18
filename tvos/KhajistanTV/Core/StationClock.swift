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
    var into: Double
    var seekTo: Double
    let startLabel: String
    let endLabel: String
    /// The next strip's show and start, under 24 hours away. `withNextProgramme` sets them again
    /// from the clock, so `following()` cannot carry an empty pair beside a filled Up next.
    var nextShow: Programming.Show?
    var nextStart: String?
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

/// One block of the guide's time grid: a programme from its start to its end, or a stretch the
/// channel is off air (no title).
struct GuideSlot: Hashable, Sendable {
    var start: Date
    var end: Date
    /// The programme's title as every surface prints it (OnAir.nowName), or the show's name for a
    /// run of short programmes; nil while off air.
    let title: String?
    /// Off air past the end of the schedule asked for: when the channel is back, as every surface
    /// prints it after "returns at" (StationClock.returnLabel). Nil otherwise.
    var returnLabel: String? = nil
    /// A run of short programmes of one strip, drawn as one block named for its show.
    var grouped = false
    /// The block runs to the end of what the guide reads, or of the months held, not to a time the
    /// schedule gives: its end is not when anything changes. An off-air one says when the channel
    /// is back from `returnLabel`, never from its end.
    var openEnd = false

    var isOffAir: Bool { title == nil }
    func contains(_ moment: Date) -> Bool { start <= moment && moment < end }
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
    /// How close to a strip's end a programme may finish and still count as the roster's last
    /// (kj-station-clock.js HANDOVER_TOLERANCE). The builder writes a strip's length as the sum of
    /// its programmes, and the clock adds the same lengths in another order: 216.6 + ... + 552.4 is
    /// 2979.7999999999997 against a strip of 2979.8, which read as the roster going round again and
    /// put the strip's own opener in Up next (Fable, 2026-11-16). The builder also rounds a strip's
    /// length to the millisecond.
    static let handoverTolerance = 0.5
    /// The same drift inside a roster (kj-station-clock.js SUM_EPSILON): taking programme lengths
    /// off the elapsed time puts a handover written at second 17780 a hair later, and at 17780 the
    /// clock still read the programme that had ended. A microsecond is far above the drift and far
    /// below a clock tick.
    static let sumEpsilon = 1e-6
    /// How long before its strip's end a file may finish and still hand over to the next strip
    /// rather than run the roster round to its opener. The clock reads whole seconds and a strip
    /// ends on a fraction: radio 01:39 on 1 November ends at 8943.9, so a last file ending on time
    /// was asked about at 8943, inside the strip, and tuned "Khawree Mi Zargai Sha" until the slot
    /// watch moved on (Fable, 2026-11-16). Small, because the next strip then plays up to this far
    /// ahead of the clock, and under a second more where it starts a fraction after this one ends.
    static let handoverLead = 2.0
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

    /// Seconds until the station month turns, when that is at most `lead` away; else nil.
    static func monthTurns(after date: Date, within lead: Double) -> Double? {
        guard stationMonth(date.addingTimeInterval(lead)) != stationMonth(date) else { return nil }
        let epoch = date.timeIntervalSince1970
        return daySeconds - Double(stationNow(date).seconds) - (epoch - epoch.rounded(.down))
    }

    /// How long the player waits before tuning, when `current`'s file ends with the month about to
    /// turn: the roster's last entry, within `handoverLead` of the turn. What follows is in next
    /// month's file, which this one does not hold; tuning after the turn loads it (both
    /// TransmissionStore.handover()). Nil otherwise, so a file ending mid-roster walks on at once.
    static func monthHandoverWait(after current: OnAir, at date: Date) -> Double? {
        guard current.rosterIndex == current.slot.programmes.count - 1 else { return nil }
        return monthTurns(after: date, within: handoverLead)
    }

    // MARK: Schedule lookups

    static func channelId(_ p: Programming, number: Int) -> String? {
        p._meta.channels.first { $0.number == number }?.id
    }

    /// The channel numbers the schedule names, in the schedule's own order. The schedule is the
    /// only list: since 2026-11-13 it puts C18 Mujra, C1 Bioscope and C12 Raqs first (owner).
    static func channelNumbers(_ p: Programming) -> [Int] {
        p._meta.channels.map(\.number)
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

    /// Where a strip ends: the minute, rounded down, the same rounding Up next uses for the
    /// programme that starts there (owner, 2026-11-15: "Now 08:46–10:03" beside "Up next 10:02").
    static func endLabel(_ slot: Programming.Slot) -> String {
        clockLabel(Int((slot.endSecond / 60).rounded(.down)))
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
            if remaining < length - sumEpsilon { return (index, max(0, remaining)) }
            remaining -= length
        }
        return (0, 0)
    }

    /// The first strip that starts after `minute` (or `second`) today, else the first strip of
    /// the next calendar day, else nil (the month's grid ends).
    /// The first strip that starts after the moment: today's strips AND yesterday's strips filed
    /// at or past 86400 (an evening pushed past midnight is filed on the day it began; see
    /// lateStrips), read in today's seconds by taking 86400 off. Reading today's alone said
    /// "back at 03:06" at 00:20 while yesterday's chain had a strip at 02:07. Port of
    /// kj-station-clock.js nextSlot (archive 6463ddcc7).
    static func nextSlot(_ p: Programming, channel: String, iso: String, minute: Int, second: Double? = nil) -> (slot: Programming.Slot, date: String)? {
        let at = second ?? Double(minute * 60)
        let today = day(p, iso: iso)
        var best: (slot: Programming.Slot, date: String)? = nil
        var bestAt = Double.infinity
        for slot in today?.channels[channel] ?? [] where slot.startSecond > at && slot.startSecond < bestAt {
            best = (slot, iso); bestAt = slot.startSecond
        }
        if let yesterdayIso = isoDay(iso, offset: -1) {
            for slot in lateStrips(p, channel: channel, iso: iso) {
                let s = slot.startSecond - 86_400
                if s > at && s < bestAt { best = (slot, yesterdayIso); bestAt = s }
            }
        }
        if let best { return best }
        guard today != nil, let from = dayNumber(iso) else { return nil }
        // Nothing more today: the earliest strip on any later day of the loaded month, not only
        // tomorrow (Fable, 2026-11-16). antenna-indus opens on 12 November, and reading one day
        // ahead left it with no return time from the 1st to the 10th. A later day's strip is placed
        // by its own day, so one filed tomorrow past 86400 is weighed against the day after's. (Today's
        // strips past 86400 were answered above, before tomorrow's are read, as they always were.)
        // Past the month's last day, `next_day`: the next month's first strip per channel, which
        // the builder copies into each month file (owner, 2026-11-16), as kj-station-clock.js.
        var later: (slot: Programming.Slot, date: String)? = nil
        var laterAt = Double.infinity
        for d in p.days + (p.next_day.map { [$0] } ?? []) {
            guard let n = dayNumber(d.date), n > from else { continue }
            for slot in d.channels[channel] ?? [] {
                let s = Double(n - from) * daySeconds + slot.startSecond
                if s < laterAt { later = (slot, d.date); laterAt = s }
            }
        }
        return later
    }

    /// Seconds from `second` on `iso` to the start of a nextSlot answer, across the days between.
    static func secondsAhead(_ next: (slot: Programming.Slot, date: String), iso: String, second: Double) -> Double? {
        guard let from = dayNumber(iso), let filed = dayNumber(next.date) else { return nil }
        return Double(filed - from) * daySeconds + next.slot.startSecond - second
    }

    /// nextSlot, for Up next: printed as an hour with no day, it names only a strip under 24 hours
    /// away. A strip further off is the off-air plate's, where returnLabel gives its day.
    static func nextSlotSoon(_ p: Programming, channel: String, iso: String, second: Double) -> (slot: Programming.Slot, date: String)? {
        guard let next = nextSlot(p, channel: channel, iso: iso, minute: Int((second / 60).rounded(.down)), second: second),
              let ahead = secondsAhead(next, iso: iso, second: second), ahead < daySeconds else { return nil }
        return next
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]

    /// When a dark channel comes back, as every surface prints it after "returns at": the strip's
    /// start and the zone, and its day as well once it is a day or more away, where the hour alone
    /// would read as the next time the clock shows it ("13:03 PKT on Thursday 12 November"). Nil
    /// when the loaded month holds nothing more on the channel. kj-station-clock.js returnLabel.
    static func returnLabel(_ p: Programming, channel: String, iso: String, second: Double) -> String? {
        guard let next = nextSlot(p, channel: channel, iso: iso, minute: Int((second / 60).rounded(.down)), second: second),
              let ahead = secondsAhead(next, iso: iso, second: second), let filed = dayNumber(next.date) else { return nil }
        let at = "\(next.slot.start) \(tzLabel)"
        if ahead < daySeconds { return at }
        // The day it airs on: the day it is filed under, plus one for a strip filed past 86400. A
        // start the builder cannot have written (beyond a week, NaN) keeps the hour alone.
        let shift = (next.slot.startSecond / daySeconds).rounded(.down)
        guard shift >= 0, shift <= 6 else { return at }
        let airs = filed + Int(shift)
        let civil = civil(fromDayNumber: airs)
        let weekday = weekdays[((airs + 4) % 7 + 7) % 7]   // day 0, 1970-01-01, was a Thursday
        return "\(at) on \(weekday) \(civil.day) \(monthNames[civil.month - 1])"
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
            nextShow: nil,                  // set from the clock by withNextProgramme
            nextStart: nil
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

    /// The strip a dark channel comes back with, however far off in the loaded month (the one
    /// returnLabel times). `upcoming` stops at 24 hours; this does not.
    static func returnStrip(_ p: Programming, channelId: String, at date: Date) -> ScheduleStrip? {
        let now = stationNow(date)
        return nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: Double(now.seconds))
            .map { ScheduleStrip(date: $0.date, slot: $0.slot, show: p.shows[$0.slot.show]) }
    }

    /// `returnLabel` for a moment: what the off-air plate and the guide print after "returns at".
    static func returnLabel(_ p: Programming, channelId: String, at date: Date) -> String? {
        let now = stationNow(date)
        return returnLabel(p, channel: channelId, iso: now.iso, second: Double(now.seconds))
    }

    /// The clock read in the frame of the day a strip is filed under: past 86 400 the day after,
    /// nil on any other day. One reading, so a strip from yesterday keeps counting past midnight.
    /// Before 00:00 of the day after, negative: a strip tuned early from the last before midnight.
    static func slotSecond(_ filed: String, now: (iso: String, minutes: Int, seconds: Int)) -> Double? {
        if now.iso == filed { return Double(now.seconds) }
        if isoDay(filed, offset: 1) == now.iso { return Double(now.seconds) + daySeconds }
        if isoDay(filed, offset: -1) == now.iso { return Double(now.seconds) - daySeconds }
        return nil
    }

    /// The programme after `current`, for the moment a file ends. While the clock is still
    /// inside the slot it walks the SLOT's roster and never re-reads the clock: a file that ends
    /// a second early ends while the clock still says it is on, and asking the clock then hands
    /// back the programme that just finished. Once the slot is over it is `onAir` again, and so it
    /// is within `handoverLead` of the slot's end: the next strip, from its head.
    static func following(_ current: OnAir, in p: Programming, at date: Date) -> OnAir? {
        let now = stationNow(date)
        let slot = current.slot
        let at = slotSecond(current.date, now: now)
        // A strip this method tuned early is inside from then on, as secondsLeft counts it: a 2.4 s
        // strip tuned 1.9 s early ends before the clock reaches its start, and asking the clock then
        // handed back the strip before it (night-bazaar, 9 November; Fable, 2026-11-16).
        let insideSlot = at.map { $0 >= slot.startSecond - handoverLead - 1 && $0 < slot.endSecond } ?? false
        guard insideSlot, let at, !slot.programmes.isEmpty else {
            return onAir(p, channelId: current.channelId, at: date)
        }
        let whole = date.timeIntervalSince1970.rounded(.down)
        let exact = at + (date.timeIntervalSince1970 - whole)
        // The clock at the first whole second past the end, as a whole epoch second (no float
        // drift). In another month this file holds nothing there: the stores wait for the turn
        // and tune before they ask (monthTurns), and the roster walk below is only a fallback.
        let end = slot.endSecond.rounded(.up)
        let then = Date(timeIntervalSince1970: whole + (end - at))
        // Only after the roster's last entry: an ident under two seconds that closes the roster
        // (state-tv 05:47 on 2 November) still airs.
        if current.rosterIndex == slot.programmes.count - 1, slot.endSecond - exact <= handoverLead,
           stationMonth(then) == stationMonth(date) {
            guard var next = onAir(p, channelId: current.channelId, at: then) else { return nil }
            // No further in than the strip has run by now, so it is never pushed further ahead.
            let into = max(0, next.into - (end - exact))
            next.seekTo -= next.into - into
            next.into = into
            return next
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
            nextShow: nil,                  // read again from the clock by withNextProgramme
            nextStart: nil
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
        let next = nextSlotSoon(p, channel: air.channelId, iso: iso, second: second)
        out.nextShow = next.flatMap { p.shows[$0.slot.show] }
        out.nextStart = next?.slot.start
        let rosterEnd = slot.endSecond - handoverTolerance
        if endsAt < rosterEnd, slot.programmes.count > 1 {
            let index = slot.programmes[(air.rosterIndex + 1) % slot.programmes.count]
            out.nextProgrammeId = programmeId(p, index: index)
            out.nextProgrammeStart = clockLabel(Int(endsAt / 60))
            out.nextInSlot = true
        } else if let next, let first = next.slot.programmes.first {
            out.nextProgrammeId = programmeId(p, index: first)
            out.nextProgrammeStart = next.slot.start
        }
        out.nextProgramme = out.nextProgrammeId.flatMap { p.programmes[$0] }
        // The names, the site's rule (kj-station-clock.js onAir): Up next is the first programme
        // after this one, in this slot, whose name differs from Now, at the minute it starts;
        // failing that, the next slot's first programme by its title, else by its show.
        let nextSlotShow = next.flatMap { p.shows[$0.slot.show] }
        func title(_ id: String?) -> String? { nonEmpty(id.flatMap { p.programmes[$0]?.display_title }) }
        out.nowName = title(air.programmeId) ?? nonEmpty(air.show?.name)
        // Neither name already on screen is said again: not Now, and not the show the plate carries.
        let nowName = out.nowName
        func said(_ name: String?) -> Bool { name == nil || name == nowName || name == air.show?.name }
        let count = slot.programmes.count
        var t = endsAt
        var k = 1
        while k < count, t < rosterEnd {
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
    /// crosses midnight and stops where the month's grid ends; a channel on air and a channel off
    /// air both start from the first strip after now. Only strips under 24 hours away: the list
    /// prints hours with no day, as onAir's Up next does.
    static func upcoming(_ p: Programming, channelId: String, at date: Date, count: Int) -> [ScheduleStrip] {
        let now = stationNow(date)
        var found: [ScheduleStrip] = []
        var cursor = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: Double(now.seconds))
        while let hit = cursor, found.count < count,
              let ahead = secondsAhead(hit, iso: now.iso, second: Double(now.seconds)), ahead < daySeconds {
            found.append(ScheduleStrip(date: hit.date, slot: hit.slot, show: p.shows[hit.slot.show]))
            cursor = nextSlot(p, channel: channelId, iso: hit.date, minute: 0, second: hit.slot.startSecond)
        }
        return found
    }

    /// Whole seconds until the slot `air` belongs to ends, or nil once the clock has left it
    /// (another day, or past its end). The player uses it for the notice before a handover and
    /// to tune the next strip the moment this one ends. It counts a strip that `following()`
    /// tuned up to `handoverLead` early, so that strip has an end watch too.
    static func secondsLeft(in air: OnAir, at date: Date) -> Int? {
        guard let at = slotSecond(air.date, now: stationNow(date)),
              at >= air.slot.startSecond - handoverLead - 1, at < air.slot.endSecond else { return nil }
        return Int((air.slot.endSecond - at).rounded(.up))
    }

    // MARK: Helpers

    private static func programmeId(_ p: Programming, index: Int) -> String? {
        p.programme_order.indices.contains(index) ? p.programme_order[index] : nil
    }

    private static func programme(_ p: Programming, index: Int) -> Programming.Programme? {
        programmeId(p, index: index).flatMap { p.programmes[$0] }
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func isoString(_ civil: (year: Int, month: Int, day: Int)) -> String {
        "\(civil.year)-\(pad2(civil.month))-\(pad2(civil.day))"
    }

    /// The calendar day `offset` days from an ISO day, by day-number arithmetic. Nil for a string
    /// that is not a real yyyy-MM-dd date (the JS gets an Invalid Date there and finds no day).
    private static func isoDay(_ iso: String, offset: Int) -> String? {
        dayNumber(iso).map { isoString(civil(fromDayNumber: $0 + offset)) }
    }

    /// The day number of an ISO day, nil for a string that is not a real yyyy-MM-dd date.
    private static func dayNumber(_ iso: String) -> Int? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        // Digits only: Int() takes a sign, so "2026-11-+5" was a day here and not in the JS.
        guard parts.count == 3, parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }), parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        return dayNumber(year: year, month: month, day: day)
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

    // MARK: The guide's time grid

    /// The moment `second` seconds into station day `iso` (station time is UTC+5).
    static func date(iso: String, second: Double) -> Date? {
        dayNumber(iso).map { Date(timeIntervalSince1970: Double($0) * daySeconds + second - Double(utcOffsetMinutes * 60)) }
    }

    /// A programme shorter than this, beside another of its strip, is drawn in a run named for
    /// the show: at three hours across the screen a block under ten minutes has no room for a word,
    /// and Right would step through a strip of thirty-second items one at a time.
    static let shortProgramme: TimeInterval = 10 * 60
    /// An off-air stretch shorter than this is a seam between two strips, not a pause a viewer
    /// sees: it is drawn as part of the programme before it.
    static let shortGap: TimeInterval = 60

    /// The first instant of the station month after the last day a schedule file holds; nil when
    /// the file names no day.
    static func monthEnd(_ p: Programming) -> Date? {
        guard let first = p.days.map(\.date).max(), first.count >= 7,
              let year = Int(first.prefix(4)), let month = Int(first.dropFirst(5).prefix(2)) else { return nil }
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        return date(iso: "\(next.0)-\(next.1 < 10 ? "0" : "")\(next.1)-01", second: 0)
    }

    /// The programme on air on a channel at a moment, by its Now name, from the months held: the
    /// month that holds the moment, so after midnight on the 1st it is the second file.
    static func nowName(_ months: [Programming], channel number: Int, at date: Date) -> String? {
        guard let p = months.first(where: { monthEnd($0).map { date < $0 } ?? false }) else { return nil }
        return onAir(p, channel: number, at: date)?.nowName
    }

    /// The station month the guide needs fetched, "yyyy-MM", when it reads to `until` past the month
    /// held and the month after is not held too; nil otherwise.
    static func monthToFetch(held: Programming?, next: Programming?, until: Date) -> String? {
        guard let held, let end = monthEnd(held), until >= end else { return nil }
        if let next, let nextEnd = monthEnd(next), nextEnd > end { return nil }
        return stationMonth(end)
    }

    /// What a channel airs from `from` to `to`, programme by programme, and the stretches it is
    /// off air, end to end, for the guide's time grid (owner, 2026-11-17: "showing schedule on an
    /// hourly basis"). `months` are the schedule files held, in order; a walk that reaches the end
    /// of the last one stops there, with no block after it, rather than read the month the device
    /// does not hold as off air. Each programme is asked of `onAir` at its own start, so the grid
    /// keeps every rule the player keeps: a roster that runs round, a strip past midnight, a strip's
    /// end cutting its last programme. A run of short programmes of one strip is one block named
    /// for its show; an off-air seam under a minute joins the programme before it.
    static func timeline(_ months: [Programming], channel number: Int, from: Date, to: Date, limit: Int = 5000) -> [GuideSlot] {
        var raw: [(slot: GuideSlot, strip: String?, show: String?, length: TimeInterval)] = []
        // Read from inside a run of short programmes, the walk starts at the run's strip, so the
        // run reads the same start and name whenever the guide is opened (Fable, round 2: opened at
        // 11:00 a run that began at 10:07 read 10:57).
        var at = runStart(months, channel: number, at: from) ?? from
        // Never before the first day the months held can read: a run carried over from the month
        // before, or a guide read from before the month turned, starts where the file does (Fable,
        // round 4: from 00:00 on 1 December with December alone, 8 of 29 rows read off air).
        if let day = months.first?.days.map(\.date).min(), let start = date(iso: day, second: 0), at < start { at = start }
        var last: (p: Programming, id: String, end: Date)?
        for p in months {
            guard at < to, let end = monthEnd(p) else { continue }
            guard at < end else { continue }
            guard let id = channelId(p, number: number) else {
                // The channel is not in this month's file: off air until the month ends.
                raw.append((GuideSlot(start: at, end: min(to, end), title: nil), nil, nil, 0))
                at = min(to, end)
                continue
            }
            last = (p, id, end)
            at = walk(p, channelId: id, from: at, to: min(to, end), monthEnd: end, into: &raw, limit: limit)
        }
        var out = group(raw).filter { $0.end > from }
        // A stretch off air that runs to the end of what was asked for, or of the months held, says
        // when the channel is back, never "back at" the edge of what was read.
        if let tail = out.last, tail.isOffAir, let last, tail.end >= min(to, last.end) {
            out[out.count - 1].openEnd = true
            // Asked no earlier than the first day that month's file holds: a stretch begun on the
            // last day of the month before is not a day it can read (Fable, round 5: dark from 21:00
            // on 30 November, the return on 2 December was lost read before midnight).
            let first = last.p.days.map(\.date).min().flatMap { date(iso: $0, second: 0) } ?? tail.start
            out[out.count - 1].returnLabel = returnLabel(last.p, channelId: last.id, at: max(tail.start, first))
        }
        return out
    }

    /// Where the strip of a short programme on air at `date` starts, when there is one: the walk
    /// begins there. Nil for a long programme, off air, or a moment no month held covers.
    private static func runStart(_ months: [Programming], channel number: Int, at date: Date) -> Date? {
        guard let p = months.first(where: { monthEnd($0).map { date < $0 } ?? false }),
              let id = channelId(p, number: number), let air = onAir(p, channelId: id, at: date),
              runSeconds(air.programme) < shortProgramme,
              let start = Self.date(iso: air.date, second: air.slot.startSecond), start < date else { return nil }
        return start
    }

    /// One month's part of a timeline. Returns where it stopped: `to`, or later when a programme
    /// running past the month's end was read whole.
    private static func walk(_ p: Programming, channelId: String, from: Date, to: Date, monthEnd: Date,
                             into raw: inout [(slot: GuideSlot, strip: String?, show: String?, length: TimeInterval)], limit: Int) -> Date {
        var at = from
        var steps = 0
        // Until the last block reaches `to` (a programme ending a fraction before it has the next one
        // start before it too, though the reading rounds up to `to` or past), and on to the end of a
        // run of short programmes it stopped inside, so the run's end is the run's own; never past
        // the month's end, which this file cannot read beyond.
        func insideRun() -> Bool { raw.last.map { $0.strip != nil && $0.length < shortProgramme } ?? false }
        while at < to || (raw.last.map { $0.slot.end < to } ?? false) || (insideRun() && at < monthEnd), steps < limit {
            steps += 1
            let whole = at.timeIntervalSince1970.rounded(.down)
            let finishingRun = at >= to && !(raw.last.map { $0.slot.end < to } ?? false)
            let reading = onAir(p, channelId: channelId, at: at)
            // Past `to` the walk only finishes a run: it stops at the first reading that is not one
            // more short programme of the same strip.
            if finishingRun {
                guard let air = reading, runSeconds(air.programme) < shortProgramme,
                      raw.last?.strip == "\(air.date) \(air.slot.startSecond)" else { break }
            }
            if let air = reading {
                let began = Date(timeIntervalSince1970: whole - air.into)
                var start = began
                // A programme is on screen from where the one before ended: the clock places both
                // from whole seconds and fractional lengths, which disagree inside a second, and two
                // strips the schedule overlaps (channel 10, 21 November) hand over when the first
                // ends, the clock joining the second partway through.
                if let prior = raw.last?.slot, start < prior.end.addingTimeInterval(1) { start = prior.end }
                var end = began.addingTimeInterval(runSeconds(air.programme))
                if let slotEnd = date(iso: air.date, second: air.slot.endSecond), slotEnd < end { end = slotEnd }
                // The clock reads whole seconds: a programme ending inside this second is over.
                end = max(end, Date(timeIntervalSince1970: whole + 1))
                raw.append((GuideSlot(start: start, end: end, title: air.nowName ?? air.show?.name ?? ""),
                            "\(air.date) \(air.slot.startSecond)", air.show?.name, runSeconds(air.programme)))
                at = Date(timeIntervalSince1970: end.timeIntervalSince1970.rounded(.up))
            } else {
                let now = stationNow(at)
                var end = to
                if let next = nextSlot(p, channel: channelId, iso: now.iso, minute: now.minutes, second: Double(now.seconds)),
                   let ahead = secondsAhead(next, iso: now.iso, second: Double(now.seconds)) {
                    end = min(to, Date(timeIntervalSince1970: whole + max(1, ahead)))
                }
                end = max(end, Date(timeIntervalSince1970: whole + 1))
                // One stretch off air, however many readings it took to cross, starting where the
                // programme before ended (that end is inside the second this reading rounded up to).
                if let prior = raw.last?.slot, prior.isOffAir, prior.end >= at {
                    raw[raw.count - 1].slot.end = end
                } else {
                    let start = raw.last.map { abs($0.slot.end.timeIntervalSince(at)) < 1 ? $0.slot.end : at } ?? at
                    raw.append((GuideSlot(start: start, end: end, title: nil), nil, nil, 0))
                }
                at = end
            }
        }
        return at
    }

    /// Runs of short programmes of one strip become one block named for the show, and off-air seams
    /// under `shortGap` join the programme before them.
    private static func group(_ raw: [(slot: GuideSlot, strip: String?, show: String?, length: TimeInterval)]) -> [GuideSlot] {
        var out: [GuideSlot] = []
        var index = 0
        while index < raw.count {
            let item = raw[index]
            var runEnd = index
            // Short by the programme's own length: a long one cut short by its strip's end is not.
            if let strip = item.strip, item.length < shortProgramme {
                while runEnd + 1 < raw.count, raw[runEnd + 1].strip == strip, raw[runEnd + 1].length < shortProgramme {
                    runEnd += 1
                }
            }
            if runEnd > index {
                // One block per strip: each strip is a slot the schedule starts at its own time, so two
                // strips of one show side by side are two blocks, each with its own times.
                out.append(GuideSlot(start: item.slot.start, end: raw[runEnd].slot.end,
                                     title: item.show ?? item.slot.title, grouped: true))
            } else if item.slot.end.timeIntervalSince(item.slot.start) < shortGap, let prior = out.last,
                      item.slot.isOffAir || !prior.isOffAir {
                // Under a minute, an off-air seam or a lone programme after a programme: too narrow
                // to see or to light, so it is drawn inside the block before it. A programme after
                // an off-air stretch keeps its own block: off air must never cover something on.
                out[out.count - 1].end = item.slot.end
            } else if let prior = out.last, prior.isOffAir, item.slot.isOffAir {
                out[out.count - 1].end = item.slot.end
            } else {
                out.append(item.slot)
            }
            index = runEnd + 1
        }
        return out
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

/// Where the guide's time grid stands, and how the remote moves it (owner, 2026-11-17: "showing
/// schedule on an hourly basis"). Channels run down the side and time across, three hours at a
/// time. One programme is lit: Up and Down change the channel and keep the moment, Right lights
/// the next programme on the channel and Left the one before, never one that has already ended.
/// The window moves in half hours, enough to keep the lit programme's start in view, and never
/// starts before the half hour now is in.
struct GuideGrid: Equatable, Sendable {
    /// Three hours across the screen.
    static let span: TimeInterval = 3 * 3600
    /// The window moves by half hours, the marks along its top.
    static let step: TimeInterval = 30 * 60
    /// How far ahead Right reaches.
    static let horizon: TimeInterval = 12 * 3600

    /// The lit channel, an index into the guide's channel list.
    var row: Int
    /// The lit moment: now, or the start of a later programme.
    var cursor: Date
    /// The left edge of the three hours on screen.
    var windowStart: Date
    /// The moment the grid is read at, moved on every half minute while the guide is open (refresh).
    private(set) var now: Date

    init(row: Int, now: Date) {
        self.row = row
        self.now = now
        cursor = now
        windowStart = Self.halfHour(now)
    }

    var windowEnd: Date { windowStart.addingTimeInterval(Self.span) }
    var horizonEnd: Date { now.addingTimeInterval(Self.horizon) }

    /// The half hour a moment falls in. Station time is UTC+5, a whole number of hours, so the
    /// half hours fall at the same instants in station time as in UTC.
    static func halfHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded(.down) * step)
    }

    /// The lit programme on a channel's row: the one airing at the lit moment, else the first
    /// after it. Nil for a row with nothing at or after it.
    func lit(in slots: [GuideSlot]) -> Int? {
        slots.firstIndex { $0.contains(cursor) } ?? slots.firstIndex { $0.start >= cursor }
    }

    /// Right: the next programme on the lit channel, within the horizon.
    mutating func later(on slots: [GuideSlot]) {
        guard let index = lit(in: slots), index + 1 < slots.count else { return }
        let next = slots[index + 1]
        guard next.start < horizonEnd else { return }
        cursor = max(next.start, now)
        follow()
    }

    /// Left: the programme before, never earlier than now.
    mutating func earlier(on slots: [GuideSlot]) {
        if let index = lit(in: slots), index > 0, slots[index - 1].end > now {
            cursor = max(slots[index - 1].start, now)
        } else {
            cursor = now
        }
        follow()
    }

    /// The clock moves on while the guide is open: the lit moment is never before now, and the
    /// window never starts before now's half hour.
    mutating func refresh(now: Date) {
        self.now = now
        if cursor < now { cursor = now }
        follow()
    }

    /// Up and Down: the channel before or after, round the list. The moment stays.
    mutating func move(rows step: Int, count: Int) {
        guard count > 0 else { return }
        row = ((row + step) % count + count) % count
    }

    /// Moves the window by half hours until the lit moment sits in it with half an hour to spare
    /// on the right, and never before the half hour now is in.
    mutating func follow() {
        let first = Self.halfHour(now)
        while cursor >= windowEnd.addingTimeInterval(-Self.step) { windowStart.addTimeInterval(Self.step) }
        while cursor < windowStart, windowStart > first { windowStart.addTimeInterval(-Self.step) }
        if windowStart < first { windowStart = first }
    }

    /// The half-hour marks along the window's top.
    var marks: [Date] {
        stride(from: 0, to: Self.span, by: Self.step).map { windowStart.addingTimeInterval($0) }
    }
}
