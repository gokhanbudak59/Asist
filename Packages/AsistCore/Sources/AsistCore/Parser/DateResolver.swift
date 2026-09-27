// Date/time resolution — 02 §8.2 (combination), §8.2a (today policy), §8.5 (hours), §9.3 (first occurrence).
import Foundation

struct Resolution {
    var due: Date?
    var hasTime: Bool
    var recurrence: Recurrence?
}

/// Time component: an explicit clock or a daypart default.
enum TimeComponent {
    case clock(ClockHit)
    case daypart(DaypartHit)
}

enum HourMode: Equatable {
    /// hour/minute on the reference day + dayOffset
    case fixed
    /// 7…11 without day: nearest future among h and h + 12
    case nearest
    /// NIGHT/EVENING hours that belong to the next day
    case nextDay
}

struct ResolvedHour {
    var hour: Int
    var minute: Int
    var dayOffset: Int
    var mode: HourMode
}

enum DateResolver {
    // MARK: - §8.5 hour resolution

    static func resolveHour(_ clock: ClockHit, daySpecified: Bool, explicitToday: Bool, settings: ParserSettings,
                            flags: inout Set<ParseFlag>) -> ResolvedHour {
        let h = clock.hour
        let m = clock.minute
        if h == 24 {
            return ResolvedHour(hour: 0, minute: m, dayOffset: 1, mode: .fixed)
        }
        if let qualifier = clock.qualifier {
            if h == 0 || (h >= 13 && h <= 23) {
                return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .fixed)
            }
            switch qualifier {
            case .am:
                return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .fixed)
            case .noon:
                if h >= 1 && h <= 5 {
                    return ResolvedHour(hour: h + 12, minute: m, dayOffset: 0, mode: .fixed)
                }
                if h == 6 {
                    return ResolvedHour(hour: 18, minute: m, dayOffset: 0, mode: .fixed)
                }
                return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .fixed)
            case .pm:
                if h == 12 {
                    return ResolvedHour(hour: 12, minute: m, dayOffset: 0, mode: .fixed)
                }
                if h == 6 {
                    return ResolvedHour(hour: 18, minute: m, dayOffset: 0, mode: .fixed)
                }
                return ResolvedHour(hour: h + 12, minute: m, dayOffset: 0, mode: .fixed)
            case .evening:
                if h == 12 {
                    return ResolvedHour(hour: 0, minute: m, dayOffset: 1, mode: .nextDay)
                }
                if h == 6 {
                    return ResolvedHour(hour: 18, minute: m, dayOffset: 0, mode: .fixed)
                }
                return ResolvedHour(hour: h + 12, minute: m, dayOffset: 0, mode: .fixed)
            case .night:
                if h >= 1 && h <= 6 {
                    return ResolvedHour(hour: h, minute: m, dayOffset: 1, mode: .nextDay)
                }
                if h == 12 {
                    return ResolvedHour(hour: 0, minute: m, dayOffset: 1, mode: .nextDay)
                }
                return ResolvedHour(hour: h + 12, minute: m, dayOffset: 0, mode: .fixed)
            }
        }
        if clock.leadingZero || h == 0 || (h >= 13 && h <= 23) {
            return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .fixed)
        }
        if h == 12 {
            return ResolvedHour(hour: 12, minute: m, dayOffset: 0, mode: .fixed)
        }
        if h >= 1 && h <= 6 && settings.belirsizSaatlerOgledenSonra {
            flags.insert(.ambiguousHourPM)
            return ResolvedHour(hour: h + 12, minute: m, dayOffset: 0, mode: .fixed)
        }
        // 7…11 (and 1…6 when the PM policy is off)
        if daySpecified && !explicitToday {
            return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .fixed)
        }
        flags.insert(.ambiguousHourNearest)
        return ResolvedHour(hour: h, minute: m, dayOffset: 0, mode: .nearest)
    }

    /// T on a known day D (`daySpecified = true`).
    static func timeOnDay(_ ctx: ParseContext, day: Date, _ time: TimeComponent, explicitToday: Bool,
                          flags: inout Set<ParseFlag>) -> Date {
        switch time {
        case .daypart(let hit):
            if hit.nextDay {
                return ctx.at(ctx.addDays(1, to: day), hit.time)
            }
            return ctx.at(day, hit.time)
        case .clock(let clock):
            let resolved = resolveHour(clock, daySpecified: true, explicitToday: explicitToday,
                                       settings: ctx.settings, flags: &flags)
            if resolved.mode == .nearest {
                let morning = ctx.at(day, resolved.hour, resolved.minute)
                let evening = ctx.at(day, resolved.hour + 12, resolved.minute)
                if morning > ctx.now {
                    return morning
                }
                // explicit today with both passed → h + 12 (pastDue is raised by the caller)
                return evening
            }
            return ctx.at(ctx.addDays(resolved.dayOffset, to: day), resolved.hour, resolved.minute)
        }
    }

    /// T without a day (§8.2 rule 5): candidate today; passed → tomorrow (`rolledToTomorrow`).
    static func timeOnly(_ ctx: ParseContext, _ time: TimeComponent, flags: inout Set<ParseFlag>) -> Date {
        let today = ctx.today
        let now = ctx.now
        switch time {
        case .daypart(let hit):
            if hit.explicitToday {
                let base = hit.nextDay ? ctx.addDays(1, to: today) : today
                let candidate = ctx.at(base, hit.time)
                if candidate < now {
                    flags.insert(.pastDue)
                }
                return candidate
            }
            var candidate = ctx.at(today, hit.time)
            if candidate <= now {
                candidate = ctx.at(ctx.addDays(1, to: today), hit.time)
                if !hit.nextDay {
                    flags.insert(.rolledToTomorrow)
                }
            }
            return candidate
        case .clock(let clock):
            let resolved = resolveHour(clock, daySpecified: false, explicitToday: false, settings: ctx.settings,
                                       flags: &flags)
            switch resolved.mode {
            case .nearest:
                let morning = ctx.at(today, resolved.hour, resolved.minute)
                if morning > now {
                    return morning
                }
                let evening = ctx.at(today, resolved.hour + 12, resolved.minute)
                if evening > now {
                    return evening
                }
                flags.insert(.rolledToTomorrow)
                return ctx.at(ctx.addDays(1, to: today), resolved.hour, resolved.minute)
            case .nextDay:
                // NIGHT/EVENING next-day hours: nearest future among today h and tomorrow h (no rolledToTomorrow).
                let sameDay = ctx.at(today, resolved.hour, resolved.minute)
                if sameDay > now {
                    return sameDay
                }
                return ctx.at(ctx.addDays(1, to: today), resolved.hour, resolved.minute)
            case .fixed:
                var candidate = ctx.at(ctx.addDays(resolved.dayOffset, to: today), resolved.hour, resolved.minute)
                if candidate <= now {
                    candidate = ctx.at(ctx.addDays(resolved.dayOffset + 1, to: today), resolved.hour, resolved.minute)
                    flags.insert(.rolledToTomorrow)
                }
                return candidate
            }
        }
    }

    /// §8.2a: today at defaultDayTime if ≥ now + 15 min, else now + 30 min rounded up to the next full hour
    /// (now + 30 min when that crosses midnight).
    static func todayPolicy(_ ctx: ParseContext) -> Date {
        let now = ctx.now
        let defaultToday = ctx.at(ctx.today, ctx.settings.defaultDayTime)
        if defaultToday >= now.addingTimeInterval(15 * 60) {
            return defaultToday
        }
        let plus30 = now.addingTimeInterval(30 * 60)
        let minute = ctx.calendar.component(.minute, from: plus30)
        let rounded = minute == 0 ? plus30 : plus30.addingTimeInterval(TimeInterval((60 - minute) * 60))
        if ctx.calendar.startOfDay(for: rounded) != ctx.today {
            return plus30
        }
        return rounded
    }

    static func timeComponent(_ ctx: ParseContext) -> TimeComponent? {
        if let clock = ctx.clocks.first {
            return .clock(clock)
        }
        if let daypart = ctx.dayparts.first {
            return .daypart(daypart)
        }
        return nil
    }

    static func recurrenceTime(_ ctx: ParseContext, _ time: TimeComponent?, flags: inout Set<ParseFlag>) -> ClockTime {
        guard let component = time else { return ctx.settings.defaultDayTime }
        switch component {
        case .daypart(let hit):
            return hit.time
        case .clock(let clock):
            let resolved = resolveHour(clock, daySpecified: true, explicitToday: false, settings: ctx.settings,
                                       flags: &flags)
            return ClockTime(resolved.hour % 24, resolved.minute)
        }
    }

    static func hasMonthDate(_ ctx: ParseContext, _ day: DayHit) -> Bool {
        guard day.start <= day.end else { return false }
        for k in day.start...day.end where k < ctx.count {
            let token = ctx.tokens[k]
            if TokenMatch.month(token) != nil {
                return true
            }
            if let number = token.number {
                switch number {
                case .dottedDate, .slashDate, .dotted:
                    return true
                default:
                    break
                }
            }
        }
        return false
    }

    /// §9 rule assembly: a weekday set overrides a daily phrase; weekly without weekdays → D's or today's weekday;
    /// monthly without day → today's day; yearly → the explicit N AY date or today.
    static func buildRecurrence(_ ctx: ParseContext, _ day: DayHit?, flags: inout Set<ParseFlag>)
        -> (rule: Recurrence, anchorToday: Bool, usedDate: Bool)? {
        if ctx.unsupportedRecurrence {
            flags.insert(.unsupportedRecurrence)
        }
        guard !ctx.recurrenceSpecs.isEmpty else {
            if ctx.yearlyAuto, let d = day, d.scope == .date, hasMonthDate(ctx, d) {
                let c = ctx.components(d.day)
                return (Recurrence(frequency: .yearly, interval: 1, monthDay: c.day, month: c.month), false, true)
            }
            return nil
        }
        var spec = ctx.recurrenceSpecs[0]
        for candidate in ctx.recurrenceSpecs where candidate.frequency == .weekly && !(candidate.weekdays ?? []).isEmpty {
            spec = candidate
            break
        }
        let today = ctx.components(ctx.today)
        switch spec.frequency {
        case .weekly:
            var weekdays = spec.weekdays ?? []
            if weekdays.isEmpty {
                if let d = day, d.scope == .date {
                    weekdays = [ctx.isoWeekday(d.day)]
                } else {
                    weekdays = [ctx.isoWeekday(ctx.today)]
                }
            }
            return (Recurrence(frequency: .weekly, interval: spec.interval, weekdays: Array(Set(weekdays)).sorted()),
                    false, false)
        case .daily:
            return (Recurrence(frequency: .daily, interval: spec.interval), false, false)
        case .monthly:
            let monthDay = spec.monthDay ?? today.day
            return (Recurrence(frequency: .monthly, interval: spec.interval, monthDay: monthDay), spec.anchorToday, false)
        case .yearly:
            if let d = day, hasMonthDate(ctx, d) {
                let c = ctx.components(d.day)
                return (Recurrence(frequency: .yearly, interval: spec.interval, monthDay: c.day, month: c.month),
                        false, true)
            }
            return (Recurrence(frequency: .yearly, interval: spec.interval, monthDay: today.day, month: today.month),
                    false, false)
        }
    }

    // MARK: - §8.2 combination

    static func resolve(_ ctx: ParseContext, flags: inout Set<ParseFlag>) -> Resolution {
        let now = ctx.now
        let today = ctx.today
        let time = timeComponent(ctx)
        var days = ctx.days
        var explicitTodayDaypart: DaypartHit? = nil
        for daypart in ctx.dayparts where daypart.explicitToday {
            explicitTodayDaypart = daypart
            break
        }
        if days.isEmpty, let daypart = explicitTodayDaypart {
            var hit = DayHit(day: today, start: daypart.start, end: daypart.end, scope: .today)
            hit.explicitToday = true
            days = [hit]
        }
        var dottedCandidate = false
        for hit in days {
            flags.formUnion(hit.flags)
            if hit.dottedCandidate {
                dottedCandidate = true
            }
        }
        if dottedCandidate && ctx.clocks.isEmpty {
            flags.insert(.ambiguousDotted)
        }
        if days.count > 1 {
            let first = days[0].day
            for hit in days.dropFirst() where hit.day != first {
                flags.insert(.conflictingDates)
            }
        }
        let day = days.first

        // G12 n'th weekday of the month: recurrence nil, due = next such day, review (flag set by buildRecurrence).
        if let ordinal = ctx.nthWeekdayOrdinal, let weekday = ctx.nthWeekdayDay {
            flags.insert(.unsupportedRecurrence)
            let clock = recurrenceTime(ctx, time, flags: &flags)
            let candidateDay = DateExtractor.nthWeekdayDate(ctx, ordinal: ordinal, weekday: weekday, from: today)
            var due = ctx.at(candidateDay, clock)
            if due <= now {
                let c = ctx.components(today)
                let firstOfMonth = ctx.makeDay(c.year, c.month, 1) ?? today
                let nextStart = ctx.addMonths(1, to: firstOfMonth)
                due = ctx.at(DateExtractor.nthWeekdayDate(ctx, ordinal: ordinal, weekday: weekday, from: nextStart), clock)
            }
            return Resolution(due: due, hasTime: time != nil, recurrence: nil)
        }
        // Rule 1: recurrence → first occurrence (§9.3, one implementation: RecurrenceEngine).
        if let built = buildRecurrence(ctx, day, flags: &flags) {
            let clock = recurrenceTime(ctx, time, flags: &flags)
            var after = now
            var anchor: Date? = nil
            if built.rule.frequency == .monthly && built.rule.interval > 1 && built.anchorToday {
                // G12: "her N ayda bir" → first occurrence today + N months.
                let anchorDate = ctx.at(today, clock)
                anchor = anchorDate
                after = anchorDate
            } else if let d = day, !built.usedDate, d.day > today {
                // An explicit D sets the search start ("her pazartesi, 5 ekim'den itibaren").
                after = max(now, d.day.addingTimeInterval(-60))
            }
            let due = RecurrenceEngine.nextOccurrence(of: built.rule, time: clock, after: after, anchor: anchor,
                                                      calendar: ctx.calendar)
            return Resolution(due: due, hasTime: time != nil, recurrence: built.rule)
        }
        // Rule 2: minute-granularity offset wins.
        if let offset = ctx.offset, !offset.isCalendar {
            if day != nil || time != nil {
                flags.insert(.conflictingDates)
            }
            return Resolution(due: now.addingTimeInterval(TimeInterval(offset.minutes * 60)), hasTime: true,
                              recurrence: nil)
        }
        // Rule 3: calendar offset.
        if let offset = ctx.offset, offset.isCalendar {
            var base = today
            if offset.days != 0 {
                base = ctx.addDays(offset.days, to: base)
            }
            if offset.months != 0 {
                base = ctx.addMonths(offset.months, to: base)
            }
            if offset.years != 0 {
                base = ctx.addYears(offset.years, to: base)
            }
            base = ctx.calendar.startOfDay(for: base)
            if day != nil {
                flags.insert(.conflictingDates)
            }
            if let component = time {
                return Resolution(due: timeOnDay(ctx, day: base, component, explicitToday: false, flags: &flags),
                                  hasTime: true, recurrence: nil)
            }
            flags.insert(.defaultTimeApplied)
            return Resolution(due: ctx.at(base, ctx.settings.defaultDayTime), hasTime: false, recurrence: nil)
        }
        // Rule 4: day expression.
        if let d = day {
            if let component = time {
                let explicitToday = d.explicitToday || (d.day == today && explicitTodayDaypart != nil)
                let due = timeOnDay(ctx, day: d.day, component, explicitToday: explicitToday, flags: &flags)
                if due < now {
                    flags.insert(.pastDue)
                }
                return Resolution(due: due, hasTime: true, recurrence: nil)
            }
            flags.insert(.defaultTimeApplied)
            if d.day == today {
                return Resolution(due: todayPolicy(ctx), hasTime: false, recurrence: nil)
            }
            let due = ctx.at(d.day, ctx.settings.defaultDayTime)
            if due < now {
                flags.insert(.pastDue)
            }
            return Resolution(due: due, hasTime: false, recurrence: nil)
        }
        // Rule 5: time only.
        if let component = time {
            return Resolution(due: timeOnly(ctx, component, flags: &flags), hasTime: true, recurrence: nil)
        }
        // G9: "hemen / şimdi / derhal / acilen" without another time → now + hemenMinutes.
        if ctx.hemenIndex != nil {
            return Resolution(due: now.addingTimeInterval(TimeInterval(ctx.settings.hemenMinutes * 60)), hasTime: true,
                              recurrence: nil)
        }
        return Resolution(due: nil, hasTime: false, recurrence: nil)
    }
}
