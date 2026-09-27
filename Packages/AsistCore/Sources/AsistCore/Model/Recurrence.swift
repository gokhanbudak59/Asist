// FILE: Packages/AsistCore/Sources/AsistCore/Model/Recurrence.swift
import Foundation

public struct Recurrence: Codable, Equatable, Hashable {
    public enum Frequency: String, Codable, CaseIterable, Hashable {
        case daily, weekly, monthly, yearly

        public init(from decoder: Decoder) throws {
            let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
            self = Frequency(rawValue: raw) ?? .daily
        }
    }

    public var frequency: Frequency
    /// >= 1 ("iki haftada bir" → weekly, 2)
    public var interval: Int
    /// weekly only; ISO 1 = Pazartesi … 7 = Pazar; sorted, unique, non-empty
    public var weekdays: [Int]?
    /// monthly/yearly: 1…31, or -1 = last day of month
    public var monthDay: Int?
    /// yearly only: 1…12
    public var month: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil, monthDay: Int? = nil, month: Int? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthDay = monthDay
        self.month = month
    }

    enum CodingKeys: String, CodingKey { case frequency, interval, weekdays, monthDay, month }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(Frequency.self, forKey: .frequency, default: .daily)
        interval = min(120, max(1, c.lenient(Int.self, forKey: .interval, default: 1)))
        // Clamps (05a #20): invalid values become nil; RecurrenceEngine treats an unusable rule as "no next occurrence".
        let rawWeekdays = c.lenientOptional([Int].self, forKey: .weekdays) ?? []
        let validWeekdays = Array(Set(rawWeekdays.filter { (1...7).contains($0) })).sorted()
        weekdays = validWeekdays.isEmpty ? nil : validWeekdays
        monthDay = c.lenientOptional(Int.self, forKey: .monthDay).flatMap { (day: Int) -> Int? in
            (day == -1 || (1...31).contains(day)) ? day : nil
        }
        month = c.lenientOptional(Int.self, forKey: .month).flatMap { (value: Int) -> Int? in
            (1...12).contains(value) ? value : nil
        }
    }
}
