// FILE: Packages/AsistCore/Sources/AsistCore/Util/AsistCalendar.swift
import Foundation

public enum AsistCalendar {
    /// Gregorian, Monday-first, POSIX locale. App: device time zone. Tests/parser default: Europe/Istanbul.
    public static func make(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static var istanbul: TimeZone {
        TimeZone(identifier: "Europe/Istanbul") ?? TimeZone(secondsFromGMT: 3 * 3600)!
    }

    /// ISO weekday: 1 = Pazartesi … 7 = Pazar (Foundation `.weekday` is 1 = Sunday).
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        ((calendar.component(.weekday, from: date) + 5) % 7) + 1
    }

    /// ISO 1…7 → Foundation weekday 1 = Sunday … 7 = Saturday (for DateComponents.weekday).
    public static func foundationWeekday(fromISO iso: Int) -> Int {
        iso % 7 + 1
    }

    public static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    /// "yyyyMMdd" in `calendar`'s time zone.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return pad(c.year ?? 0, 4) + pad(c.month ?? 0, 2) + pad(c.day ?? 0, 2)
    }

    /// "yyyyMMddHHmm"
    public static func minuteKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return dayKey(date, calendar: calendar) + pad(c.hour ?? 0, 2) + pad(c.minute ?? 0, 2)
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// `day`'s calendar date at `time` (seconds = 0).
    public static func date(on day: Date, at time: ClockTime, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(time.minutesOfDay * 60))
    }

    public static func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 86_400))
    }

    public static func floorToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    public static func ceilToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.up) * 60)
    }

    /// Start of the day that is `count` workdays after `date`'s day (count >= 1).
    public static func addingWorkdays(_ count: Int, to date: Date, workdays: [Int], calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        var remaining = max(1, count)
        var guardCounter = 0
        while remaining > 0 && guardCounter < 400 {
            day = addingDays(1, to: day, calendar: calendar)
            if workdays.isEmpty || workdays.contains(isoWeekday(day, calendar: calendar)) {
                remaining -= 1
            }
            guardCounter += 1
        }
        return day
    }
}
