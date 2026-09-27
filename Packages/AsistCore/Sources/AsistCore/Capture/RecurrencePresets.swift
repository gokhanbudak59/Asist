// API: Packages/AsistCore/Sources/AsistCore/Capture/RecurrencePresets.swift
// Revision 4 (07 §4.4, F1): the "Tekrar" choices of the Düzenle sheet for a given due date. Same rules as
// ItemDetailView.recurrenceChoices (which stays untouched).
import Foundation

public struct RecurrencePreset: Equatable, Identifiable {
    /// "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly"
    public var id: String
    public var title: String
    public var rule: Recurrence

    public init(id: String, title: String, rule: Recurrence) {
        self.id = id
        self.title = title
        self.rule = rule
    }
}

public enum RecurrencePresets {
    /// For `due` (in `calendar`): "Her gün", "Hafta içi her gün" (weekly [1…5]), "Her <Salı>" (weekly [iso]),
    /// "İki haftada bir <Salı>" (weekly interval 2), "Her ayın <29'u>" (monthly monthDay = day), "Her yıl <29 Eylül>"
    /// (yearly monthDay + month).
    public static func presets(for due: Date, calendar: Calendar) -> [RecurrencePreset] {
        let iso = AsistCalendar.isoWeekday(due, calendar: calendar)
        let comps = calendar.dateComponents([.month, .day], from: due)
        let day = comps.day ?? 1
        let month = comps.month ?? 1
        let weekdayNames = TurkishDateFormatter.weekdays
        let weekdayName = weekdayNames[min(weekdayNames.count - 1, max(0, iso - 1))]
        let monthNames = TurkishDateFormatter.months
        let monthName = monthNames[min(monthNames.count - 1, max(0, month - 1))]
        var result: [RecurrencePreset] = []
        result.append(RecurrencePreset(id: "daily", title: "Her gün",
                                       rule: Recurrence(frequency: .daily)))
        result.append(RecurrencePreset(id: "weekdays", title: "Hafta içi her gün",
                                       rule: Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5])))
        result.append(RecurrencePreset(id: "weekly", title: "Her " + weekdayName,
                                       rule: Recurrence(frequency: .weekly, weekdays: [iso])))
        result.append(RecurrencePreset(id: "biweekly", title: "İki haftada bir " + weekdayName,
                                       rule: Recurrence(frequency: .weekly, interval: 2, weekdays: [iso])))
        result.append(RecurrencePreset(id: "monthly", title: "Her ayın " + TurkishDateFormatter.numeralPossessive(day),
                                       rule: Recurrence(frequency: .monthly, monthDay: day)))
        result.append(RecurrencePreset(id: "yearly", title: "Her yıl " + String(day) + " " + monthName,
                                       rule: Recurrence(frequency: .yearly, monthDay: day, month: month)))
        return result
    }
}
