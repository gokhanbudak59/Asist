// FILE: Widgets/WidgetSupport.swift
// Revision 4 (07 §5.8): deep links and clock texts shared by every widget view. Every tap is an asist:// link
// (custom scheme works for widgetURL / Link); nothing in the extension writes data.
import Foundation
import AsistCore

enum WidgetLinks {
    static var listen: URL { DeepLink.listen(kind: nil, projectID: nil).url }
    static var compose: URL { DeepLink.compose.url }
    static var today: URL { DeepLink.today.url }
    static func item(_ id: UUID) -> URL { DeepLink.item(id).url }
}

enum WidgetClock {
    /// Same rules as AppTime.calendar (device zone, Monday-first, POSIX): AsistCalendar.make(timeZone: .autoupdatingCurrent).
    static var calendar: Calendar { AsistCalendar.make(timeZone: TimeZone.autoupdatingCurrent) }

    /// Overdue at `now` → "gecikti"; anchor nil → "Zamanı belirsiz"; else
    /// TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: entry.hasTime || entry.kind == .reminder).
    static func whenText(_ entry: WidgetSnapshot.Entry, snapshot: WidgetSnapshot, now: Date) -> String {
        if snapshot.isOverdue(entry, at: now) {
            return "gecikti"
        }
        guard let anchor = entry.anchor else {
            return "Zamanı belirsiz"
        }
        let includeTime = entry.hasTime || entry.kind == .reminder
        return TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: includeTime)
    }

    /// Counter values of `entry` (time-driven: entries that became overdue since the app wrote the snapshot).
    static func counts(_ entry: AsistEntry) -> (overdue: Int, today: Int, followUp: Int) {
        let snapshot = entry.snapshot
        return (snapshot.overdueCount(at: entry.date),
                snapshot.todayCount(at: entry.date, calendar: calendar),
                snapshot.followUpCount)
    }
}
