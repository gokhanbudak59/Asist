// FILE: Packages/AsistCore/Sources/AsistCore/Model/Item+Logic.swift
import Foundation

extension Item {
    public var isOpen: Bool { status == .open }
    public var isRecurring: Bool { recurrence != nil }
    /// Items that can ever produce notifications.
    public var isNotifiable: Bool { status == .open && kind != .note }

    /// The nag anchor: explicit snooze, else due date; place-only items use the location delivery time.
    public var anchorDate: Date? {
        if let snoozed = snoozedUntil { return snoozed }
        if let due = dueDate { return due }
        if placeID != nil { return locationFiredAt }
        return nil
    }

    /// Instant at which the item counts as "geciken" (03 §3.1):
    /// notes and events never; waiting → start of the day after the anchor; untimed task → start of the day after;
    /// everything else → the anchor itself.
    public func overdueStart(calendar: Calendar) -> Date? {
        guard kind != .note, !isEvent, let anchor = anchorDate else { return nil }
        let endOfDayRule = (kind == .waiting) || (kind == .task && !hasTime && snoozedUntil == nil)
        if endOfDayRule {
            let start = calendar.startOfDay(for: anchor)
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        return anchor
    }

    public func isOverdue(at now: Date, calendar: Calendar) -> Bool {
        guard isOpen, let start = overdueStart(calendar: calendar) else { return false }
        return start <= now
    }

    /// Anchor lies on `now`'s calendar day and the item is not (yet) overdue.
    public func isDueToday(at now: Date, calendar: Calendar) -> Bool {
        guard isOpen, kind != .note, let anchor = anchorDate else { return false }
        return calendar.isDate(anchor, inSameDayAs: now) && !isOverdue(at: now, calendar: calendar)
    }

    /// Minutes after the anchor at which an event is auto-closed (D31).
    public static let eventDurationMinutes = 120

    /// anchor + eventDurationMinutes for open events; nil otherwise.
    public var eventEnd: Date? {
        guard isEvent, let anchor = anchorDate else { return nil }
        return anchor.addingTimeInterval(TimeInterval(Item.eventDurationMinutes * 60))
    }

    public func profileKind(settings: AppSettings) -> NagProfileKind {
        if kind == .waiting { return .takip }
        if let explicit = nagProfile, explicit != .takip, explicit != .etkinlik { return explicit }
        if isEvent { return .etkinlik }
        return settings.profileKind(for: priority)
    }

    public mutating func appendHistory(_ event: HistoryEvent, at date: Date, detail: String? = nil) {
        history.append(HistoryEntry(date: date, event: event, detail: detail))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }

    /// Resets nag state after the due date was changed by the user (edit/reschedule).
    public mutating func resetNagState() {
        snoozedUntil = nil
        snoozeCount = 0
        lastDismissedAt = nil
        locationFiredAt = nil
    }
}
