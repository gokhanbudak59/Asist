// FILE: Packages/AsistCore/Sources/AsistCore/Planning/NotificationStaleness.swift
import Foundation

/// Pure rules that keep an old notification — or a reconcile running just before a request fires — from acting on
/// the wrong occurrence or day. Used by ReminderEngine / NotificationScheduler (App); no platform types here.
public enum NotificationStaleness {
    /// The diff-apply never removes a pending one-shot request that fires within this window just because the
    /// planner left it out (its margins are 10 s for k0/nags/occurrences and 60 s for pre-alerts, briefing,
    /// end-of-day, signing and sentinels). 60 s + 30 s slack.
    public static let nearDueProtection: TimeInterval = 90

    /// Allowed clock skew when an `.occurrenceDone` entry lies in the future (manual clock change): such an entry
    /// is ignored instead of making every later notification look stale.
    public static let futureSkew: TimeInterval = 60

    /// Date of the newest `.occurrenceDone` entry of a recurring item (history is newest-last and the newest entry
    /// always survives the 50-entry cap). nil when the item is not recurring or no occurrence was completed yet.
    public static func lastOccurrenceDone(of item: Item) -> Date? {
        guard item.recurrence != nil else { return nil }
        return item.history.last(where: { $0.event == .occurrenceDone })?.date
    }

    /// True when a notification of `item` delivered at `deliveredAt` belongs to an occurrence that the user has
    /// already completed (the completion happened at or after the delivery). An action on such a notification must
    /// not complete / snooze the *next* occurrence.
    public static func isCompletedOccurrence(_ item: Item, deliveredAt: Date, now: Date) -> Bool {
        guard let done = lastOccurrenceDone(of: item) else { return false }
        guard done <= now.addingTimeInterval(futureSkew) else { return false }
        return done >= deliveredAt
    }

    /// A delivered notification of an open recurring item that is older than (or as old as) the item's last
    /// completed occurrence: it only reminds about work that is already done.
    public static func isDeliveredBeforeCompletion(deliveredAt: Date, lastOccurrenceDone: Date?) -> Bool {
        guard let done = lastOccurrenceDone else { return false }
        return deliveredAt <= done
    }

    /// History events whose writers clear `locationFiredAt` through `Item.resetNagState()`: a completed occurrence
    /// (markDone of a recurring item), a missed occurrence (roll-over), a new due date (date picker, "Düzenle",
    /// clearing the due) and the end-of-day move. From that moment on the geofence is armed again (07 §9.10).
    /// `.edited` is deliberately not one of them: it is also written by unrelated edits (checklist, priority), and a
    /// place edit already removes the old delivery itself (ItemDetailView.setPlace → LocationService.forgetDelivered).
    public static func rearmsLocation(_ event: HistoryEvent) -> Bool {
        switch event {
        case .occurrenceDone, .occurrenceMissed, .rescheduled, .movedEndOfDay:
            return true
        default:
            return false
        }
    }

    /// Newest re-arm moment of the item's geofence (see `rearmsLocation`). Entries stamped more than `futureSkew`
    /// after `now` (manual clock change) are ignored. nil = the geofence was never re-armed.
    public static func locationRearmDate(of item: Item, now: Date) -> Date? {
        let limit = now.addingTimeInterval(futureSkew)
        var newest: Date? = nil
        for entry in item.history where rearmsLocation(entry.event) && entry.date <= limit {
            if let current = newest, current >= entry.date { continue }
            newest = entry.date
        }
        return newest
    }

    /// True when a geofence notification of `item` delivered at `deliveredAt` belongs to a period before the
    /// geofence was re-armed (the occurrence was completed / missed or the item rescheduled afterwards): recording
    /// it again would set `locationFiredAt` for the *new* period and the geofence would never be added again.
    public static func isLocationDeliveryBeforeRearm(_ item: Item, deliveredAt: Date, now: Date) -> Bool {
        guard let rearm = locationRearmDate(of: item, now: now) else { return false }
        return deliveredAt <= rearm
    }

    /// The end-of-day action ("Sonraki iş gününe taşı") only applies on the day its notification was delivered.
    public static func isStaleEndOfDay(deliveredAt: Date, now: Date, calendar: Calendar) -> Bool {
        return !calendar.isDate(deliveredAt, inSameDayAs: now)
    }

    /// Diff-apply guard for a pending request missing from the plan: true = keep it (it is a one-shot that fires
    /// within `nearDueProtection`). Repeating triggers and undated triggers are never kept.
    public static func isNearDue(nextFire: Date?, repeats: Bool, now: Date) -> Bool {
        guard !repeats, let fire = nextFire else { return false }
        return fire <= now.addingTimeInterval(nearDueProtection)
    }

    /// Items whose near-due pending requests the diff-apply keeps: notifiable (open, not a note) and not an
    /// occurrence completed within `nearDueProtection` (that completion re-planned the item on purpose).
    public static func protectsNearDue(_ item: Item, now: Date) -> Bool {
        guard item.isNotifiable else { return false }
        if let done = lastOccurrenceDone(of: item), done > now.addingTimeInterval(-nearDueProtection) {
            return false
        }
        return true
    }
}
