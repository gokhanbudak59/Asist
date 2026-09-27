// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9 (which switches the targets to the NagPlanner helpers).
// Declares `SnoozeOption` (only here).
import Foundation
import AsistCore

enum SnoozeOption: String, CaseIterable, Identifiable {
    case min10, min30, hour1, hour2, thisEvening, tomorrowMorning, monday, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .min10: return "10 dk"
        case .min30: return "30 dk"
        case .hour1: return "1 saat"
        case .hour2: return "2 saat"
        case .thisEvening: return "Bu akşam"
        case .tomorrowMorning: return "Yarın sabah"
        case .monday: return "Pazartesi"
        case .custom: return "Tarih seç…"
        }
    }

    /// nil for .custom, and for .thisEvening after 18:30. Results ceil to the minute.
    func target(now: Date, settings: AppSettings, calendar: Calendar) -> Date? {
        switch self {
        case .min10:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(10 * 60))
        case .min30:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(30 * 60))
        case .hour1:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(60 * 60))
        case .hour2:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(2 * 60 * 60))
        case .thisEvening:
            guard AsistCalendar.minuteOfDay(now, calendar: calendar) <= 18 * 60 + 30 else { return nil }
            return AsistCalendar.date(on: now, at: settings.aksam, calendar: calendar)
        case .tomorrowMorning:
            let tomorrow = AsistCalendar.addingDays(1, to: now, calendar: calendar)
            return AsistCalendar.date(on: tomorrow, at: settings.workStart, calendar: calendar)
        case .monday:
            var day = AsistCalendar.addingDays(1, to: now, calendar: calendar)
            var steps = 0
            while AsistCalendar.isoWeekday(day, calendar: calendar) != 1 && steps < 7 {
                day = AsistCalendar.addingDays(1, to: day, calendar: calendar)
                steps += 1
            }
            return AsistCalendar.date(on: day, at: settings.workStart, calendar: calendar)
        case .custom:
            return nil
        }
    }
}
