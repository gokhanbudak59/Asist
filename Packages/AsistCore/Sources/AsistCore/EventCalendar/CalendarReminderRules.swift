// API: Packages/AsistCore/Sources/AsistCore/EventCalendar/CalendarReminderRules.swift
// Revision 4 — F7 (07 §10.2, R4-D8): pure rules behind the Bugün "TAKVİM" section. The calendar is read-only;
// "Öncesinde hatırlat" creates an Asist *event item* (isEvent = true, dueDate = start, one pre-alert), which gets the
// D31 semantics: pre-alert N min before, first alert at start, no nag chain, auto-closed 120 min after start.
import Foundation

public enum CalendarReminderRules {
    public static let tagPrefix = "takvim:"
    /// "Öncesinde hatırlat" is offered only for events that start more than this many seconds from now.
    public static let minimumLeadSeconds: TimeInterval = 60

    /// identifier + "@" + AsistCalendar.minuteKey(start) — recurring events share one identifier, so the start minute
    /// tells their occurrences apart.
    public static func eventKey(identifier: String, start: Date, calendar: Calendar) -> String {
        identifier + "@" + AsistCalendar.minuteKey(start, calendar: calendar)
    }

    /// tagPrefix + StableHash.fnv1a64(eventKey) — stored in `Item.tags` of the created reminder.
    public static func tag(forEventKey key: String) -> String {
        tagPrefix + StableHash.fnv1a64(key)
    }

    /// !isAllDay && start > now + 60 s.
    public static func canRemind(start: Date, isAllDay: Bool, now: Date) -> Bool {
        !isAllDay && start > now.addingTimeInterval(minimumLeadSeconds)
    }

    /// Some open item (not done, not deleted) carries `tag(forEventKey: eventKey)`.
    public static func hasReminder(items: [Item], eventKey: String) -> Bool {
        let wanted = tag(forEventKey: eventKey)
        return items.contains { item in
            item.isOpen && item.tags.contains(wanted)
        }
    }

    /// The Asist event item for "Öncesinde hatırlat":
    /// kind .reminder, title = trimmed title or "Toplantı", notes "Takvim: <timeRange>" (+ " · <location>"),
    /// dueDate floorToMinute(start), hasTime, leadTimesMinutes [leadMinutes] (none when ≤ 0), isEvent,
    /// tags [tag], source .calendar, createdAt now, history [.created] (rendered "takvimden oluşturuldu").
    public static func makeItem(title: String, start: Date, end: Date, location: String?, eventKey: String,
                                leadMinutes: Int, now: Date, calendar: Calendar) -> Item {
        let cleanTitle = singleLine(title)
        var notes = "Takvim: " + timeRange(start: start, end: end, isAllDay: false, calendar: calendar)
        let place = singleLine(location ?? "")
        if !place.isEmpty {
            notes += " · " + place
        }
        let leads: [Int] = (leadMinutes > 0 && leadMinutes <= 527_040) ? [leadMinutes] : []
        return Item(kind: .reminder,
                    title: cleanTitle.isEmpty ? "Toplantı" : cleanTitle,
                    notes: notes,
                    dueDate: AsistCalendar.floorToMinute(start),
                    hasTime: true,
                    leadTimesMinutes: leads,
                    isEvent: true,
                    tags: [tag(forEventKey: eventKey)],
                    source: .calendar,
                    createdAt: now,
                    history: [HistoryEntry(date: now, event: .created)])
    }

    /// "10:00–11:00"; end on another day → "10:00–…"; end == start → "10:00"; all-day → "Tüm gün".
    /// An event that ends exactly at the next midnight reads "23:00–00:00".
    public static func timeRange(start: Date, end: Date, isAllDay: Bool, calendar: Calendar) -> String {
        if isAllDay {
            return "Tüm gün"
        }
        let startText = TurkishDateFormatter.time(start, calendar: calendar)
        guard end > start else { return startText }
        let lastInstant = end.addingTimeInterval(-1)
        guard calendar.isDate(lastInstant, inSameDayAs: start) else { return startText + "–…" }
        return startText + "–" + TurkishDateFormatter.time(end, calendar: calendar)
    }

    /// Range shown in the Bugün list for the day starting at `dayStart`: an event that began on an earlier day reads
    /// "…–17:00" (or "Tüm gün" when it also lasts past this day); otherwise `timeRange`.
    public static func displayRange(start: Date, end: Date, isAllDay: Bool, dayStart: Date,
                                    calendar: Calendar) -> String {
        if isAllDay {
            return "Tüm gün"
        }
        guard start < dayStart else {
            return timeRange(start: start, end: end, isAllDay: false, calendar: calendar)
        }
        let nextDay = AsistCalendar.addingDays(1, to: dayStart, calendar: calendar)
        if end >= nextDay {
            return "Tüm gün"
        }
        return "…–" + TurkishDateFormatter.time(end, calendar: calendar)
    }

    /// Time shown in the toast: start − lead when that is > now + 60 s, else the start itself.
    public static func alertTime(start: Date, leadMinutes: Int, now: Date) -> Date {
        let due = AsistCalendar.floorToMinute(start)
        guard leadMinutes > 0 else { return due }
        let preAlert = due.addingTimeInterval(-TimeInterval(leadMinutes) * 60)
        return preAlert > now.addingTimeInterval(minimumLeadSeconds) ? preAlert : due
    }

    /// Line breaks → spaces (scalar-wise), trimmed.
    static func singleLine(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
