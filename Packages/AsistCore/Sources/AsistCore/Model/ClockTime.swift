// FILE: Packages/AsistCore/Sources/AsistCore/Model/ClockTime.swift
import Foundation

public struct ClockTime: Codable, Equatable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(minutesOfDay: Int) {
        let m = ((minutesOfDay % 1440) + 1440) % 1440
        self.hour = m / 60
        self.minute = m % 60
    }

    public var minutesOfDay: Int { hour * 60 + minute }

    /// "08:30"
    public var display: String { AsistCalendar.pad(hour, 2) + ":" + AsistCalendar.pad(minute, 2) }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutesOfDay < rhs.minutesOfDay }

    enum CodingKeys: String, CodingKey { case hour, minute }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hour = min(23, max(0, c.lenient(Int.self, forKey: .hour, default: 9)))
        minute = min(59, max(0, c.lenient(Int.self, forKey: .minute, default: 0)))
    }
}
