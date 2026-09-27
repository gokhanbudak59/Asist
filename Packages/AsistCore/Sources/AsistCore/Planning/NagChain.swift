// NagChain.swift — WP3 (04 §6.4, normative): the time rules of the nag planner (quiet hours, work hours,
// day starts, mute window) and the incremental chain generator behind `NagPlanner.chain`, `plan` and
// `immediateRequests`. Internal to AsistCore; pure, synchronous and bounded (§4.1 r11).
import Foundation

// MARK: - Time rules

/// 04 §6.4 definitions bound to one (settings, calendar, now). Every instant is interpreted in `calendar`.
struct NagTimeRules {
    let settings: AppSettings
    let calendar: Calendar
    let now: Date

    private let quietStartMinute: Int
    private let quietEndMinute: Int
    private let workStartMinute: Int
    private let workEndMinute: Int

    /// `nextDayStart` searches at most this many days for an eligible day (05a #8).
    static let dayStartSearchDays = 14

    init(settings: AppSettings, calendar: Calendar, now: Date) {
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.quietStartMinute = settings.quietStart.minutesOfDay
        self.quietEndMinute = settings.quietEnd.minutesOfDay
        self.workStartMinute = settings.workStart.minutesOfDay
        self.workEndMinute = settings.workEnd.minutesOfDay
    }

    /// `mod(t)`
    func minuteOfDay(_ date: Date) -> Int {
        AsistCalendar.minuteOfDay(date, calendar: calendar)
    }

    /// `day(t)` (used as the key of per-day counters).
    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// `workday(d)`
    func isWorkday(_ date: Date) -> Bool {
        settings.workdays.contains(AsistCalendar.isoWeekday(date, calendar: calendar))
    }

    /// `inQuiet(t)`: window [qs, qe) with wrap-around when qs > qe; qs == qe means "no quiet hours".
    func inQuiet(_ date: Date) -> Bool {
        let mod = minuteOfDay(date)
        if quietStartMinute > quietEndMinute {
            return mod >= quietStartMinute || mod < quietEndMinute
        }
        return mod >= quietStartMinute && mod < quietEndMinute
    }

    /// `quiet(t, c)`
    func isQuiet(_ date: Date, critical: Bool) -> Bool {
        if critical && settings.criticalIgnoresQuietHours { return false }
        return inQuiet(date)
    }

    /// `quietExit(t)`: the next instant >= t whose minute of day is qe (same day when mod(t) < qe, else next day).
    func quietExit(_ date: Date) -> Date {
        let day = minuteOfDay(date) < quietEndMinute
            ? date
            : AsistCalendar.addingDays(1, to: date, calendar: calendar)
        return AsistCalendar.date(on: day, at: settings.quietEnd, calendar: calendar)
    }

    /// `muted(t)`: the mute window is active at `now` and covers `t`.
    func isMuted(_ date: Date) -> Bool {
        settings.isMuted(date, now: now)
    }

    /// `inWork(t)`
    func inWork(_ date: Date) -> Bool {
        guard isWorkday(date) else { return false }
        let mod = minuteOfDay(date)
        return mod >= workStartMinute && mod < workEndMinute
    }

    /// `dayStart(day)`: workStart on workdays, offDayStart otherwise; `.takip` always uses followUpAskTime.
    func dayStart(onDay day: Date, takip: Bool) -> Date {
        let time: ClockTime
        if takip {
            time = settings.followUpAskTime
        } else if isWorkday(day) {
            time = settings.workStart
        } else {
            time = settings.offDayStart
        }
        return AsistCalendar.date(on: day, at: time, calendar: calendar)
    }

    /// `nextDayStart(t)`: day start of the first eligible day strictly after t's day (at most 14 days searched;
    /// `.takip` is eligible on workdays only). When nothing is eligible every day counts as eligible.
    func nextDayStart(after date: Date, takip: Bool) -> Date {
        let today = startOfDay(date)
        var offset = 1
        while offset <= NagTimeRules.dayStartSearchDays {
            let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
            if !takip || isWorkday(day) {
                return dayStart(onDay: day, takip: takip)
            }
            offset += 1
        }
        let tomorrow = AsistCalendar.addingDays(1, to: today, calendar: calendar)
        return dayStart(onDay: tomorrow, takip: takip)
    }

    /// First fire of a repeating rule strictly after `date` (nil for `.once` or an unusable rule).
    func nextFire(of rule: PlannedNotification.Rule, after date: Date) -> Date? {
        switch rule {
        case .once:
            return nil
        case .daily(let hour, let minute):
            let time = ClockTime(min(23, max(0, hour)), min(59, max(0, minute)))
            let today = startOfDay(date)
            var offset = 0
            while offset < 3 {
                let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
                let candidate = AsistCalendar.date(on: day, at: time, calendar: calendar)
                if candidate > date { return candidate }
                offset += 1
            }
            return nil
        case .weekly(let weekday, let hour, let minute):
            let time = ClockTime(min(23, max(0, hour)), min(59, max(0, minute)))
            let today = startOfDay(date)
            var offset = 0
            while offset <= 8 {
                let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
                if calendar.component(.weekday, from: day) == weekday {
                    let candidate = AsistCalendar.date(on: day, at: time, calendar: calendar)
                    if candidate > date { return candidate }
                }
                offset += 1
            }
            return nil
        case .monthly(let dayOfMonth, let hour, let minute):
            guard dayOfMonth >= 1 && dayOfMonth <= 28 else { return nil }
            let time = ClockTime(min(23, max(0, hour)), min(59, max(0, minute)))
            let parts = calendar.dateComponents([.year, .month], from: date)
            var firstComponents = DateComponents()
            firstComponents.year = parts.year
            firstComponents.month = parts.month
            firstComponents.day = 1
            guard let firstOfMonth = calendar.date(from: firstComponents) else { return nil }
            var monthOffset = 0
            while monthOffset < 3 {
                if let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: firstOfMonth) {
                    let day = AsistCalendar.addingDays(dayOfMonth - 1, to: monthStart, calendar: calendar)
                    let candidate = AsistCalendar.date(on: day, at: time, calendar: calendar)
                    if candidate > date { return candidate }
                }
                monthOffset += 1
            }
            return nil
        }
    }
}

// MARK: - Chain generator

/// Produces the chain of 04 §6.4 one element at a time (index = k; element 0 == anchor). Stopping early yields a
/// prefix identical to the full chain, which is what `plan()` relies on ("MAY stop generating once plan() has
/// what it needs"). Bounded: ≤ 400 elements, phase 2 only while the last element is before anchor + 14 days,
/// ≤ 30 day jumps per element.
struct NagChainGenerator {
    static let maxElements = 400
    static let horizonDays = 14
    static let dailyCapGuard = 30
    /// Minutes clamp for hand-built profiles (decoded/code-defined values are far below; avoids Int overflow).
    static let maxStepMinutes = 1_000_000

    let anchor: Date
    let profile: NagProfile
    let kind: NagProfileKind
    let isCritical: Bool
    let rules: NagTimeRules

    private let isTakip: Bool
    private let dailyCap: Int
    private let horizon: Date
    private var produced = 0
    private var last: Date
    private var countsByDay: [Date: Int] = [:]
    private var offsetIndex = 0
    private var finished = false

    init(anchor: Date, profile: NagProfile, kind: NagProfileKind, isCritical: Bool, rules: NagTimeRules) {
        self.anchor = anchor
        self.profile = profile
        self.kind = kind
        self.isCritical = isCritical
        self.rules = rules
        self.isTakip = kind == .takip
        // A cap of 0 (hand-built profile only) would make every emit loop 30 day jumps; 1 keeps the semantics sane.
        self.dailyCap = max(1, profile.dailyCap)
        self.horizon = AsistCalendar.addingDays(NagChainGenerator.horizonDays, to: anchor, calendar: rules.calendar)
        self.last = anchor
    }

    /// Next chain element, or nil when the chain is complete.
    mutating func next() -> Date? {
        if produced == 0 {
            // k = 0, exactly at A — never shifted (explicit time or snooze).
            produced = 1
            countsByDay[rules.startOfDay(anchor)] = 1
            last = anchor
            return anchor
        }
        if finished { return nil }
        if kind == .etkinlik {
            finished = true
            return nil
        }
        // Phase 1: follow-up offsets relative to the anchor.
        let offsets = profile.followUpOffsetsMinutes
        while offsetIndex < offsets.count && produced < NagChainGenerator.maxElements {
            let minutes = min(NagChainGenerator.maxStepMinutes, max(-NagChainGenerator.maxStepMinutes, offsets[offsetIndex]))
            offsetIndex += 1
            if let emitted = emit(anchor.addingTimeInterval(TimeInterval(minutes * 60))) {
                return emitted
            }
        }
        // Phase 2: repeat steps until the 14-day window (or 400 elements) is exhausted.
        guard produced < NagChainGenerator.maxElements && last < horizon else {
            finished = true
            return nil
        }
        let candidate = phaseTwoCandidate()
        if let emitted = emit(candidate) {
            return emitted
        }
        if let emitted = emit(followingDayStart(after: last)) {
            return emitted
        }
        finished = true
        return nil
    }

    private func phaseTwoCandidate() -> Date {
        let lastInWork = rules.inWork(last)
        if lastInWork, let step = profile.repeatMinutesWorkHours {
            let candidate = last.addingTimeInterval(TimeInterval(clampedStep(step) * 60))
            if !rules.inWork(candidate) && profile.repeatMinutesOffHours == nil {
                return followingDayStart(after: last)
            }
            return candidate
        }
        if !lastInWork, let step = profile.repeatMinutesOffHours {
            return last.addingTimeInterval(TimeInterval(clampedStep(step) * 60))
        }
        return followingDayStart(after: last)
    }

    // DEVIATION(04 §6.4 phase 2): when `last` lies before the day start of its own eligible day — typically the
    // quiet-hours exit 07:30 before workStart 08:30 after a night-time anchor ("gece 2'de …", A = 23:00) — the
    // next repeat is that same day's start instead of the next day's. The literal `nextDayStart(last)` would skip
    // the whole workday after the 07:30 nag, contradicting 03 §3.5 ("ertesi gün ilk hatırlatması: mesai başı").
    // No worked example reaches this case (their phase-2 `last` is never before its day start), so all of them
    // are unchanged. The daily-cap loop in `emit` keeps the literal `nextDayStart`.
    private func followingDayStart(after date: Date) -> Date {
        if !isTakip || rules.isWorkday(date) {
            let sameDay = rules.dayStart(onDay: date, takip: isTakip)
            if sameDay > date { return sameDay }
        }
        return rules.nextDayStart(after: date, takip: isTakip)
    }

    private func clampedStep(_ minutes: Int) -> Int {
        min(NagChainGenerator.maxStepMinutes, max(0, minutes))
    }

    private func count(on date: Date) -> Int {
        countsByDay[rules.startOfDay(date)] ?? 0
    }

    /// 04 §6.4 `emit(raw)`: mute collapse, quiet exit, daily cap / takip workdays; nil = merged.
    private mutating func emit(_ raw: Date) -> Date? {
        var t = raw
        if rules.isMuted(t), let until = rules.settings.muteUntil {
            t = AsistCalendar.ceilToMinute(until)          // muted nags collapse into one
        }
        if rules.isQuiet(t, critical: isCritical) {
            t = rules.quietExit(t)
        }
        var guardCount = 0
        while guardCount < NagChainGenerator.dailyCapGuard
                && (count(on: t) >= dailyCap || (isTakip && !rules.isWorkday(t))) {
            t = rules.nextDayStart(after: t, takip: isTakip)
            guardCount += 1
            if rules.isQuiet(t, critical: isCritical) {
                t = rules.quietExit(t)                     // user quiet hours may cover the day start
            }
        }
        if t <= last { return nil }
        let dayKey = rules.startOfDay(t)
        let newCount = (countsByDay[dayKey] ?? 0) + 1
        countsByDay[dayKey] = newCount
        produced += 1
        last = t
        return t
    }
}
