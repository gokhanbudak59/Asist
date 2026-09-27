// API: Packages/AsistCore/Sources/AsistCore/Planning/RecurrenceEngine.swift
// WP1 — occurrence arithmetic for `Recurrence` (04 §3.4.5, D27). Every search is bounded (≤ 400 steps, 04 §4.1 r11).
import Foundation

public enum RecurrenceEngine {
    static let maxSteps = 400

    /// Earliest instant **strictly after** `after` that matches `rule`, at wall-clock `time` in `calendar`.
    /// `anchor` = the item's current occurrence (used for interval > 1: weeks/days/months are counted from it;
    /// nil → counting starts at the first match). monthDay -1 = last day; 29–31 clamp to month length
    /// (03 §9 r36). yearly uses `month`/`monthDay`. Returns nil only for an invalid rule (e.g. weekly with no weekdays).
    public static func nextOccurrence(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                      calendar: Calendar) -> Date? {
        let n = min(120, max(1, rule.interval))
        switch rule.frequency {
        case .daily:
            return nextDaily(interval: n, time: time, after: after, anchor: anchor, calendar: calendar)
        case .weekly:
            return nextWeekly(rule, interval: n, time: time, after: after, anchor: anchor, calendar: calendar)
        case .monthly:
            return nextMonthly(rule, interval: n, time: time, after: after, anchor: anchor, calendar: calendar)
        case .yearly:
            return nextYearly(rule, interval: n, time: time, after: after, anchor: anchor, calendar: calendar)
        }
    }

    /// Up to `count` consecutive occurrences strictly after `after` (planner uses count = 7, D27). Never loops
    /// more than 400 candidate days/months internally (invalid rules return []).
    public static func occurrences(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                   count: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = after
        var currentAnchor = anchor
        let wanted = min(max(0, count), maxSteps)
        while result.count < wanted {
            guard let next = nextOccurrence(of: rule, time: time, after: cursor, anchor: currentAnchor,
                                            calendar: calendar), next > cursor else { break }
            result.append(next)
            if currentAnchor == nil {
                // Interval counting continues from the first match (weekly ×2 stays on its two-week grid).
                currentAnchor = next
            }
            cursor = next
        }
        return result
    }

    /// Latest occurrence `<= now` that is strictly after `current` (for roll-over of missed occurrences).
    /// Interval counting is anchored on `current`.
    public static func latestOccurrence(of rule: Recurrence, time: ClockTime, after current: Date, upTo now: Date,
                                        calendar: Calendar) -> Date? {
        guard now > current else { return nil }
        let n = min(120, max(1, rule.interval))
        switch rule.frequency {
        case .daily:
            return latestDaily(interval: n, time: time, current: current, now: now, calendar: calendar)
        case .weekly:
            return latestWeekly(rule, interval: n, time: time, current: current, now: now, calendar: calendar)
        case .monthly:
            return latestMonthly(rule, interval: n, time: time, current: current, now: now, calendar: calendar)
        case .yearly:
            return latestYearly(rule, interval: n, time: time, current: current, now: now, calendar: calendar)
        }
    }

    // MARK: - Helpers

    static func instant(_ day: Date, _ time: ClockTime, _ calendar: Calendar) -> Date {
        return AsistCalendar.date(on: day, at: time, calendar: calendar)
    }

    static func addDays(_ n: Int, _ date: Date, _ calendar: Calendar) -> Date {
        return AsistCalendar.addingDays(n, to: date, calendar: calendar)
    }

    static func weekStart(_ date: Date, _ calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return addDays(-(AsistCalendar.isoWeekday(day, calendar: calendar) - 1), day, calendar)
    }

    static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        return ((value % modulus) + modulus) % modulus
    }

    static func monthIndex(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 2000) * 12 + (c.month ?? 1) - 1
    }

    /// Instant of `monthDay` (-1 = last day, 29–31 clamped) in the month `index` (year × 12 + month − 1).
    static func monthInstant(index: Int, monthDay: Int, time: ClockTime, calendar: Calendar) -> Date? {
        let year = index / 12
        let month = index % 12 + 1
        let length = ParserDates.daysInMonth(year: year, month: month, calendar: calendar)
        let day = monthDay == -1 ? length : min(max(1, monthDay), length)
        guard let start = ParserDates.makeDay(year, month, day, calendar: calendar) else { return nil }
        return instant(start, time, calendar)
    }

    static func weekdaySet(_ rule: Recurrence) -> [Int] {
        return Array(Set((rule.weekdays ?? []).filter { $0 >= 1 && $0 <= 7 })).sorted()
    }

    static func monthDay(_ rule: Recurrence, fallback: Date, _ calendar: Calendar) -> Int? {
        let day = rule.monthDay ?? calendar.component(.day, from: fallback)
        guard day == -1 || (day >= 1 && day <= 31) else { return nil }
        return day
    }

    static func yearlyParts(_ rule: Recurrence, fallback: Date, _ calendar: Calendar) -> (month: Int, day: Int)? {
        let month = rule.month ?? calendar.component(.month, from: fallback)
        let day = rule.monthDay ?? calendar.component(.day, from: fallback)
        guard month >= 1 && month <= 12, day == -1 || (day >= 1 && day <= 31) else { return nil }
        return (month, day)
    }

    // MARK: - Forward search

    static func nextDaily(interval n: Int, time: ClockTime, after: Date, anchor: Date?, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: after)
        var day = start
        var step = 1
        if let anchorDate = anchor {
            step = n
            let offset = positiveModulo(ParserDates.daysBetween(anchorDate, start, calendar: calendar), n)
            if offset != 0 {
                day = addDays(n - offset, start, calendar)
            }
        }
        for _ in 0..<maxSteps {
            let candidate = instant(day, time, calendar)
            if candidate > after {
                return candidate
            }
            day = addDays(step, day, calendar)
        }
        return nil
    }

    static func nextWeekly(_ rule: Recurrence, interval n: Int, time: ClockTime, after: Date, anchor: Date?,
                           calendar: Calendar) -> Date? {
        let weekdays = weekdaySet(rule)
        guard !weekdays.isEmpty else { return nil }
        var week = weekStart(after, calendar)
        var step = 1
        if let anchorDate = anchor {
            step = n
            let weeks = ParserDates.daysBetween(weekStart(anchorDate, calendar), week, calendar: calendar) / 7
            let offset = positiveModulo(weeks, n)
            if offset != 0 {
                week = addDays(7 * (n - offset), week, calendar)
            }
        }
        for _ in 0..<maxSteps {
            for weekday in weekdays {
                let candidate = instant(addDays(weekday - 1, week, calendar), time, calendar)
                if candidate > after {
                    return candidate
                }
            }
            week = addDays(7 * step, week, calendar)
        }
        return nil
    }

    static func nextMonthly(_ rule: Recurrence, interval n: Int, time: ClockTime, after: Date, anchor: Date?,
                            calendar: Calendar) -> Date? {
        guard let day = monthDay(rule, fallback: anchor ?? after, calendar) else { return nil }
        var index = monthIndex(after, calendar)
        var step = 1
        if let anchorDate = anchor {
            step = n
            let offset = positiveModulo(index - monthIndex(anchorDate, calendar), n)
            if offset != 0 {
                index += n - offset
            }
        }
        for _ in 0..<maxSteps {
            if let candidate = monthInstant(index: index, monthDay: day, time: time, calendar: calendar),
               candidate > after {
                return candidate
            }
            index += step
        }
        return nil
    }

    static func nextYearly(_ rule: Recurrence, interval n: Int, time: ClockTime, after: Date, anchor: Date?,
                           calendar: Calendar) -> Date? {
        guard let parts = yearlyParts(rule, fallback: anchor ?? after, calendar) else { return nil }
        var year = calendar.component(.year, from: after)
        var step = 1
        if let anchorDate = anchor {
            step = n
            let offset = positiveModulo(year - calendar.component(.year, from: anchorDate), n)
            if offset != 0 {
                year += n - offset
            }
        }
        for _ in 0..<maxSteps {
            let index = year * 12 + parts.month - 1
            if let candidate = monthInstant(index: index, monthDay: parts.day, time: time, calendar: calendar),
               candidate > after {
                return candidate
            }
            year += step
        }
        return nil
    }

    // MARK: - Backward search (latest occurrence in (current, now])

    static func latestDaily(interval n: Int, time: ClockTime, current: Date, now: Date, calendar: Calendar) -> Date? {
        let lastDay = calendar.startOfDay(for: now)
        let offset = positiveModulo(ParserDates.daysBetween(current, lastDay, calendar: calendar), n)
        var day = addDays(-offset, lastDay, calendar)
        for _ in 0..<maxSteps {
            let candidate = instant(day, time, calendar)
            if candidate <= current {
                return nil
            }
            if candidate <= now {
                return candidate
            }
            day = addDays(-n, day, calendar)
        }
        return nil
    }

    static func latestWeekly(_ rule: Recurrence, interval n: Int, time: ClockTime, current: Date, now: Date,
                             calendar: Calendar) -> Date? {
        let weekdays = weekdaySet(rule)
        guard !weekdays.isEmpty else { return nil }
        let anchorWeek = weekStart(current, calendar)
        var week = weekStart(now, calendar)
        let weeks = ParserDates.daysBetween(anchorWeek, week, calendar: calendar) / 7
        let offset = positiveModulo(weeks, n)
        week = addDays(-7 * offset, week, calendar)
        for _ in 0..<maxSteps {
            if week < anchorWeek {
                return nil
            }
            for weekday in weekdays.reversed() {
                let candidate = instant(addDays(weekday - 1, week, calendar), time, calendar)
                if candidate <= now && candidate > current {
                    return candidate
                }
            }
            week = addDays(-7 * n, week, calendar)
        }
        return nil
    }

    static func latestMonthly(_ rule: Recurrence, interval n: Int, time: ClockTime, current: Date, now: Date,
                              calendar: Calendar) -> Date? {
        guard let day = monthDay(rule, fallback: current, calendar) else { return nil }
        let anchorIndex = monthIndex(current, calendar)
        var index = monthIndex(now, calendar)
        index -= positiveModulo(index - anchorIndex, n)
        for _ in 0..<maxSteps {
            if index < anchorIndex {
                return nil
            }
            if let candidate = monthInstant(index: index, monthDay: day, time: time, calendar: calendar) {
                if candidate <= current {
                    return nil
                }
                if candidate <= now {
                    return candidate
                }
            }
            index -= n
        }
        return nil
    }

    static func latestYearly(_ rule: Recurrence, interval n: Int, time: ClockTime, current: Date, now: Date,
                             calendar: Calendar) -> Date? {
        guard let parts = yearlyParts(rule, fallback: current, calendar) else { return nil }
        let anchorYear = calendar.component(.year, from: current)
        var year = calendar.component(.year, from: now)
        year -= positiveModulo(year - anchorYear, n)
        for _ in 0..<maxSteps {
            if year < anchorYear {
                return nil
            }
            let index = year * 12 + parts.month - 1
            if let candidate = monthInstant(index: index, monthDay: parts.day, time: time, calendar: calendar) {
                if candidate <= current {
                    return nil
                }
                if candidate <= now {
                    return candidate
                }
            }
            year -= n
        }
        return nil
    }
}
