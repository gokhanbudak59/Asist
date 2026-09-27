// API: Packages/AsistCore/Sources/AsistCore/Planning/RecurrenceEngine.swift
// WP0 STUB (04 §3.4.5): daily semantics only — WP1 replaces this file with the full engine.
import Foundation

public enum RecurrenceEngine {
    /// Earliest instant **strictly after** `after` that matches `rule`, at wall-clock `time` in `calendar`.
    /// `anchor` = the item's current occurrence (used for interval > 1: weeks/days/months are counted from it;
    /// nil → counting starts at the first match). monthDay -1 = last day; 29–31 clamp to month length
    /// (03 §9 r36). yearly uses `month`/`monthDay`. Returns nil only for an invalid rule (e.g. weekly with no weekdays).
    public static func nextOccurrence(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                      calendar: Calendar) -> Date? {
        // WP0 STUB: daily semantics (next `time` strictly after `after`).
        var candidate = AsistCalendar.date(on: after, at: time, calendar: calendar)
        var guardCounter = 0
        while candidate <= after && guardCounter < 3 {
            let nextDay = AsistCalendar.addingDays(1, to: candidate, calendar: calendar)
            candidate = AsistCalendar.date(on: nextDay, at: time, calendar: calendar)
            guardCounter += 1
        }
        return candidate > after ? candidate : nil
    }

    /// Up to `count` consecutive occurrences strictly after `after` (planner uses count = 7, D27). Never loops
    /// more than 400 candidate days/months internally (invalid rules return []).
    public static func occurrences(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                   count: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = after
        let wanted = min(max(0, count), 400)
        while result.count < wanted {
            guard let next = nextOccurrence(of: rule, time: time, after: cursor, anchor: anchor, calendar: calendar),
                  next > cursor else { break }
            result.append(next)
            cursor = next
        }
        return result
    }

    /// Latest occurrence `<= now` that is strictly after `current` (for roll-over of missed occurrences).
    public static func latestOccurrence(of rule: Recurrence, time: ClockTime, after current: Date, upTo now: Date,
                                        calendar: Calendar) -> Date? {
        // WP0 STUB: daily semantics.
        guard now > current else { return nil }
        var candidate = AsistCalendar.date(on: now, at: time, calendar: calendar)
        if candidate > now {
            let previousDay = AsistCalendar.addingDays(-1, to: candidate, calendar: calendar)
            candidate = AsistCalendar.date(on: previousDay, at: time, calendar: calendar)
        }
        return (candidate > current && candidate <= now) ? candidate : nil
    }
}
