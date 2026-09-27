// FILE: App/Support/AppTime.swift
import Foundation
import AsistCore

enum AppTime {
    /// Device time zone (wall-clock reminders follow the user when travelling), Monday-first, POSIX locale.
    static var calendar: Calendar { AsistCalendar.make(timeZone: TimeZone.autoupdatingCurrent) }
}
