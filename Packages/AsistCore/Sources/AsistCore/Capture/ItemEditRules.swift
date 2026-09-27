// FILE: Packages/AsistCore/Sources/AsistCore/Capture/ItemEditRules.swift
import Foundation

/// Result of the "Düzenle" sheet (07 §F1). `event` is nil when nothing changed.
public struct ItemEditOutcome: Equatable {
    public var item: Item
    public var changed: Bool
    public var event: HistoryEvent?

    public init(item: Item, changed: Bool, event: HistoryEvent?) {
        self.item = item
        self.changed = changed
        self.event = event
    }
}

/// Pure edit semantics shared by the edit sheet (and its tests). The sheet edits a copy (`edited`) of the item as it
/// was when the sheet opened (`original`); only the fields the user really changed are written onto the store's
/// latest copy (`current`), so a concurrent change (a notification action, a roll-over) is never overwritten.
/// `updatedAt` and history are added by `DataStore.update`.
public enum ItemEditRules {
    public static func apply(original: Item, edited: Item, onto current: Item, now: Date,
                             settings: AppSettings, calendar: Calendar) -> ItemEditOutcome {
        var result = current
        if edited.title != original.title {
            let trimmed = edited.title.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.title = trimmed
            }
        }
        if edited.kind != original.kind {
            result.kind = edited.kind
        }
        if edited.priority != original.priority {
            result.priority = edited.priority
        }
        if edited.projectID != original.projectID {
            result.projectID = edited.projectID
        }
        if edited.person != original.person {
            let trimmed = (edited.person ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            result.person = trimmed.isEmpty ? nil : trimmed
        }
        if edited.dueDate != original.dueDate || edited.hasTime != original.hasTime {
            result.dueDate = edited.dueDate.map { (date: Date) -> Date in AsistCalendar.floorToMinute(date) }
            result.hasTime = edited.hasTime
            // The store moved the due day while the sheet was open (a "Yaptım" advancing a recurrence, a move to the
            // next workday, a roll-over) and the user changed only the clock / hasTime (same day as the snapshot):
            // apply the new clock to the store's current day instead of writing the stale day back.
            if let originalDue = original.dueDate, let editedDue = edited.dueDate, let currentDue = current.dueDate,
               currentDue != originalDue, calendar.isDate(editedDue, inSameDayAs: originalDue) {
                let clock = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(editedDue, calendar: calendar))
                result.dueDate = AsistCalendar.date(on: currentDue, at: clock, calendar: calendar)
            }
        }
        if edited.recurrence != original.recurrence {
            result.recurrence = edited.recurrence
        }
        if edited.leadTimesMinutes != original.leadTimesMinutes {
            result.leadTimesMinutes = edited.leadTimesMinutes
        }
        if edited.isEvent != original.isEvent {
            result.isEvent = edited.isEvent
        }

        // Normalization — the same rules as ItemDetailView / ConfirmationSheet.
        if result.kind == .waiting && result.dueDate == nil {
            result.dueDate = ItemFactory.defaultWaitingDue(now: now, settings: settings, calendar: calendar)
            result.hasTime = false
        }
        if result.kind == .note || result.kind == .waiting {
            result.isEvent = false
        }
        if result.dueDate == nil {
            result.hasTime = false
            result.recurrence = nil
            result.leadTimesMinutes = []
            result.isEvent = false
        }
        if !result.hasTime {
            result.isEvent = false
        }
        // Default pre-alert only when the edited copy did not itself arrive as an event without leads: the sheet's
        // Etkinlik toggle already applies the default, so an event with no leads there is the user's "Yok".
        let eventLeadsChosen = edited.isEvent && edited.leadTimesMinutes.isEmpty
        if result.isEvent && !current.isEvent && result.leadTimesMinutes.isEmpty && !eventLeadsChosen
            && settings.eventDefaultLeadMinutes > 0 {
            result.leadTimesMinutes = [settings.eventDefaultLeadMinutes]
        }
        result.leadTimesMinutes = Array(Set(result.leadTimesMinutes.filter { $0 > 0 && $0 <= 527_040 })).sorted()

        let rescheduled = result.dueDate != current.dueDate || result.hasTime != current.hasTime
        if rescheduled {
            result.resetNagState()
        }
        if result != current {
            result.needsReview = false          // editing = the user confirmed the record
        }
        let changed = result != current
        let event: HistoryEvent? = changed ? (rescheduled ? HistoryEvent.rescheduled : HistoryEvent.edited) : nil
        return ItemEditOutcome(item: result, changed: changed, event: event)
    }
}
