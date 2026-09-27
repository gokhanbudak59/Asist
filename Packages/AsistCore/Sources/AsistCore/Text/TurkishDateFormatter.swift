// API: Packages/AsistCore/Sources/AsistCore/Text/TurkishDateFormatter.swift
// WP1 — 02 §13 formatter (locale-independent, identical on Linux and iOS; never uses DateFormatter).
import Foundation

public enum TurkishDateFormatter {
    public static let months: [String] = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                                          "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    public static let monthsShort: [String] = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
                                               "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
    public static let weekdays: [String] = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    public static let weekdaysShort: [String] = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    /// "09:05"
    public static func hhmm(_ hour: Int, _ minute: Int) -> String {
        AsistCalendar.pad(hour, 2) + ":" + AsistCalendar.pad(minute, 2)
    }

    /// "15:00" of `date` in `calendar`.
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return hhmm(c.hour ?? 0, c.minute ?? 0)
    }

    /// "Bugün" / "Yarın" / "Dün" / weekday name.
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        switch dayOffset(date, now: now, calendar: calendar) {
        case 0: return "Bugün"
        case 1: return "Yarın"
        case -1: return "Dün"
        default: return weekdayName(date, calendar: calendar)
        }
    }

    /// 02 §13 date phrase: "Salı 29 Eylül", "Yarın 1 Ocak 2027".
    public static func datePhrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var text = dayLabel(date, now: now, calendar: calendar) + " " + String(c.day ?? 1) + " " + monthName(c.month ?? 1)
        if let year = c.year, year != calendar.component(.year, from: now) {
            text += " " + String(year)
        }
        return text
    }

    /// Row/notification label (03 §7.11): "Bugün 15:00", "Yarın 09:00", "Salı 15:00" (2–6 days),
    /// "6 Ekim Salı 15:00" (≥ 7 days or past beyond yesterday). `includeTime: false` drops the time.
    public static func shortDateTime(_ date: Date, now: Date, calendar: Calendar, includeTime: Bool) -> String {
        let offset = dayOffset(date, now: now, calendar: calendar)
        let day: String
        if offset >= -1 && offset <= 1 {
            day = dayLabel(date, now: now, calendar: calendar)
        } else if offset >= 2 && offset <= 6 {
            day = weekdayName(date, calendar: calendar)
        } else {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            var text = String(c.day ?? 1) + " " + monthName(c.month ?? 1)
            if let year = c.year, year != calendar.component(.year, from: now) {
                text += " " + String(year)
            }
            day = text + " " + weekdayName(date, calendar: calendar)
        }
        return includeTime ? day + " " + time(date, calendar: calendar) : day
    }

    /// 02 §13 relative phrase incl. parentheses: "(2 gün sonra)", "(yarın)", "(geçmiş)".
    public static func relativePhrase(to date: Date, now: Date, calendar: Calendar) -> String {
        let minutes = wholeMinutes(from: now, to: date)
        let days = dayOffset(date, now: now, calendar: calendar)
        if minutes < 0 {
            return "(geçmiş)"
        }
        if minutes == 0 {
            return "(şimdi)"
        }
        if minutes < 60 {
            return "(" + String(minutes) + " dakika sonra)"
        }
        if days == 0 || minutes < 720 {
            let hours = minutes / 60
            let rest = minutes % 60
            if rest == 0 {
                return "(" + String(hours) + " saat sonra)"
            }
            return "(" + String(hours) + " saat " + String(rest) + " dakika sonra)"
        }
        if days == 1 {
            return "(yarın)"
        }
        if days < 14 {
            return "(" + String(days) + " gün sonra)"
        }
        if days < 60 {
            return "(yaklaşık " + String((days + 3) / 7) + " hafta sonra)"
        }
        let monthCount = max(2, Int((Double(days) / 30.44).rounded()))
        return "(yaklaşık " + String(monthCount) + " ay sonra)"
    }

    /// List-row relative text without parentheses (03 §7.12 "Göreli zaman"): "10 dk sonra", "2 saat sonra",
    /// "3 gün sonra", "Şimdi", "5 dk gecikti", "2 saat gecikti", "3 gündür bekliyor".
    /// The first 5 minutes after the due time still read "Şimdi" (03 §3.1).
    public static func relativeShort(to date: Date, now: Date, calendar: Calendar) -> String {
        let minutes = wholeMinutes(from: now, to: date)
        if minutes >= 0 {
            if minutes == 0 {
                return "Şimdi"
            }
            if minutes < 60 {
                return String(minutes) + " dk sonra"
            }
            if minutes < 1440 {
                return String(minutes / 60) + " saat sonra"
            }
            let days = max(1, dayOffset(date, now: now, calendar: calendar))
            return String(days) + " gün sonra"
        }
        let late = -minutes
        if late < 5 {
            return "Şimdi"
        }
        if late < 60 {
            return String(late) + " dk gecikti"
        }
        if late < 1440 {
            return String(late / 60) + " saat gecikti"
        }
        let days = max(1, -dayOffset(date, now: now, calendar: calendar))
        return String(days) + " gündür bekliyor"
    }

    /// "10 dakika", "1 saat", "1 saat 30 dakika", "1 gün", "1 hafta" (for pre-alerts, snooze toasts).
    public static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m >= 10080 && m % 10080 == 0 {
            return String(m / 10080) + " hafta"
        }
        if m >= 1440 && m % 1440 == 0 {
            return String(m / 1440) + " gün"
        }
        if m >= 60 {
            let hours = m / 60
            let rest = m % 60
            return rest == 0 ? String(hours) + " saat" : String(hours) + " saat " + String(rest) + " dakika"
        }
        return String(m) + " dakika"
    }

    /// 02 §13 recurrence text: "Her gün", "Hafta içi her gün", "Her Pazartesi ve Perşembe", "Her ayın 1'i", …
    public static func recurrenceText(_ recurrence: Recurrence) -> String {
        let n = max(1, recurrence.interval)
        switch recurrence.frequency {
        case .daily:
            return n == 1 ? "Her gün" : "Her " + String(n) + " günde bir"
        case .weekly:
            let days = Array(Set((recurrence.weekdays ?? []).filter { $0 >= 1 && $0 <= 7 })).sorted()
            if n == 1 && days == [1, 2, 3, 4, 5] {
                return "Hafta içi her gün"
            }
            if n == 1 && days == [6, 7] {
                return "Her hafta sonu"
            }
            if n == 1 && days == [1, 2, 3, 4, 5, 6, 7] {
                return "Her gün"
            }
            let names = days.map { weekdays[$0 - 1] }
            guard let lastName = names.last else {
                return n == 1 ? "Her hafta" : String(n) + " haftada bir"
            }
            let list = names.count == 1 ? lastName : names.dropLast().joined(separator: ", ") + " ve " + lastName
            return n == 1 ? "Her " + list : String(n) + " haftada bir " + list
        case .monthly:
            let dayText: String
            let monthDay = recurrence.monthDay ?? 1
            if monthDay == -1 {
                dayText = "son günü"
            } else if monthDay >= 29 {
                // 03 §9 r36: 29–31 fire on the last day of shorter months.
                dayText = numeralPossessive(monthDay) + " (kısa aylarda son gün)"
            } else {
                dayText = numeralPossessive(max(1, monthDay))
            }
            return n == 1 ? "Her ayın " + dayText : String(n) + " ayda bir, ayın " + dayText
        case .yearly:
            let monthDay = recurrence.monthDay ?? 1
            let dayText = monthDay == -1 ? "son günü" : String(monthDay)
            let text = dayText + " " + monthName(recurrence.month ?? 1)
            return n == 1 ? "Her yıl " + text : String(n) + " yılda bir " + text
        }
    }

    /// Numeral + possessive suffix table (02 §13): 1 → "1'i", 3 → "3'ü", 20 → "20'si".
    public static func numeralPossessive(_ n: Int) -> String {
        // Suffix chosen by the spoken last word: bir, iki, üç, dört, beş, altı, yedi, sekiz, dokuz / on, yirmi, …
        let units = ["ı", "i", "si", "ü", "ü", "i", "sı", "si", "i", "u"]
        let tens = ["", "u", "si", "u", "ı", "si", "ı", "i", "i", "ı"]
        let a = Int(n.magnitude % 1000)
        let suffix: String
        if a % 10 != 0 {
            suffix = units[a % 10]
        } else if a == 0 {
            suffix = n == 0 ? "ı" : "i"          // sıfır / bin
        } else if a % 100 != 0 {
            suffix = tens[(a / 10) % 10]
        } else {
            suffix = "ü"                         // yüz
        }
        return String(n) + "'" + suffix
    }

    // MARK: - Helpers

    /// Calendar-day difference date − now.
    static func dayOffset(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Whole minutes from `now` (floored to the minute) to `date`, rounded down.
    static func wholeMinutes(from now: Date, to date: Date) -> Int {
        let seconds = date.timeIntervalSince(AsistCalendar.floorToMinute(now))
        return Int((seconds / 60).rounded(.down))
    }

    static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let iso = AsistCalendar.isoWeekday(date, calendar: calendar)
        return weekdays[min(6, max(0, iso - 1))]
    }

    static func monthName(_ month: Int) -> String {
        months[min(11, max(0, month - 1))]
    }
}
