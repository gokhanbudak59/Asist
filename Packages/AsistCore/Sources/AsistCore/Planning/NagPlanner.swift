// API: Packages/AsistCore/Sources/AsistCore/Planning/NagPlanner.swift
// WP0 STUB (04 §3.5.3) — WP3 replaces this file with the §6.4 algorithm (plus NagChain.swift / PlanPostPass.swift).
import Foundation

public enum NagPlanner {
    /// Pure. Same input → same output (ids, order, fingerprints). Algorithm §6.4.
    public static func plan(_ input: PlanInput) -> PlanResult {
        // WP0 STUB: one `.first` notification per open notifiable item with a future anchor (tier 0, no badge).
        var planned: [PlannedNotification] = []
        for item in input.items where item.isNotifiable {
            guard let anchor = item.anchorDate, anchor > input.now else { continue }
            let categoryID = item.kind == .waiting ? NotificationCategoryID.followUp : NotificationCategoryID.item
            let notification = PlannedNotification(
                id: NotificationID.chain(item.id, 0),
                kind: .first,
                itemID: item.id,
                attempt: 0,
                fireDate: AsistCalendar.ceilToMinute(anchor),
                rule: .once,
                title: item.title.isEmpty ? "Asist" : item.title,
                subtitle: "",
                body: item.originalText ?? item.notes,
                threadID: NotificationID.thread(item.id),
                categoryID: categoryID,
                badge: nil,
                interruption: .active,
                relevance: 0.5,
                playsSound: true,
                tier: 0)
            planned.append(notification)
        }
        planned.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        }
        let budget = input.itemBudget
        let kept = Array(planned.prefix(budget))
        let dropped = Array(planned.dropFirst(budget))
        return PlanResult(notifications: kept,
                          droppedCount: dropped.count,
                          earliestDroppedDate: dropped.first?.fireDate,
                          rateLimitedCount: 0,
                          badgeNow: badgeCount(items: input.items, at: input.now, settings: input.settings,
                                               calendar: input.calendar),
                          itemBudget: budget)
    }

    /// 05b B1: the first `limit` one-shot (`.once`) notifications of `item`, computed exactly as `plan` would for an
    /// input that contains only this item (same ids, content and fingerprints; no reserved slots, no sentinels,
    /// no rate limiter, no budget). Used by ReminderEngine.handle before completionHandler().
    public static func immediateRequests(for item: Item, input: PlanInput, limit: Int) -> [PlannedNotification] {
        // WP0 STUB
        return []
    }

    /// Full chain for an anchor (index = k; element 0 == anchor; `.etkinlik` → [anchor]). Honours quiet hours,
    /// work hours, daily caps and the mute window (`settings.muteUntil`, active only while `now < muteUntil`).
    /// Used by plan(), tests and the Settings preview.
    public static func chain(anchor: Date, profile: NagProfile, profileKind: NagProfileKind, isCritical: Bool,
                             settings: AppSettings, now: Date, calendar: Calendar) -> [Date] {
        // WP0 STUB
        return [anchor]
    }

    /// "Yarın sabah": before 05:00 → today's day start; else next day's day start
    /// (workStart on workdays, offDayStart otherwise).
    public static func tomorrowMorning(after now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        let day = hour < 5 ? now : AsistCalendar.addingDays(1, to: now, calendar: calendar)
        return stubDayStart(on: day, settings: settings, calendar: calendar)
    }

    /// Takip re-ask: `workdays` workdays after `now` at settings.followUpAskTime.
    public static func followUpAsk(after now: Date, workdays: Int, settings: AppSettings, calendar: Calendar) -> Date {
        let day = AsistCalendar.addingWorkdays(max(1, workdays), to: now, workdays: settings.workdays, calendar: calendar)
        return AsistCalendar.date(on: day, at: settings.followUpAskTime, calendar: calendar)
    }

    /// "Bu akşam" = today at settings.aksam; nil if now is past 18:30.
    public static func thisEvening(now: Date, settings: AppSettings, calendar: Calendar) -> Date? {
        if AsistCalendar.minuteOfDay(now, calendar: calendar) > 18 * 60 + 30 { return nil }
        return AsistCalendar.date(on: now, at: settings.aksam, calendar: calendar)
    }

    /// "Pazartesi" = next Monday (strictly after today) at day start.
    public static func nextMonday(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        var day = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: now), calendar: calendar)
        var guardCounter = 0
        while AsistCalendar.isoWeekday(day, calendar: calendar) != 1 && guardCounter < 8 {
            day = AsistCalendar.addingDays(1, to: day, calendar: calendar)
            guardCounter += 1
        }
        return stubDayStart(on: day, settings: settings, calendar: calendar)
    }

    /// Mute preset "Mesai sonuna kadar" (D32): today's workEnd when now is before it on a workday, else now + 2 h
    /// (ceil to minute).
    public static func muteUntilWorkEnd(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let iso = AsistCalendar.isoWeekday(now, calendar: calendar)
        let end = AsistCalendar.date(on: now, at: settings.workEnd, calendar: calendar)
        if settings.isWorkday(isoWeekday: iso) && now < end { return end }
        return AsistCalendar.ceilToMinute(now.addingTimeInterval(2 * 3600))
    }

    /// Open, non-note, non-event items overdue at `date` (+ due today when mode == .overdueAndToday; 0 when .off).
    public static func badgeCount(items: [Item], at date: Date, settings: AppSettings, calendar: Calendar) -> Int {
        if settings.badgeMode == .off { return 0 }
        var count = 0
        for item in items where item.isNotifiable && !item.isEvent {
            if item.isOverdue(at: date, calendar: calendar) {
                count += 1
            } else if settings.badgeMode == .overdueAndToday && item.isDueToday(at: date, calendar: calendar) {
                count += 1
            }
        }
        return count
    }

    // MARK: - Stub helpers (file-private)

    private static func stubDayStart(on day: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let iso = AsistCalendar.isoWeekday(day, calendar: calendar)
        let time = settings.isWorkday(isoWeekday: iso) ? settings.workStart : settings.offDayStart
        return AsistCalendar.date(on: day, at: time, calendar: calendar)
    }
}
