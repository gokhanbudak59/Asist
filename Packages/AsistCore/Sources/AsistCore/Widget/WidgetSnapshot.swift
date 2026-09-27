// FILE: Packages/AsistCore/Sources/AsistCore/Widget/WidgetSnapshot.swift
import Foundation

/// Disposable widget data written by the app into the App Group container (07 §F2). The same build writes and
/// reads it; a file that fails to decode just puts the widgets into launcher mode until the app writes again.
public struct WidgetSnapshot: Codable, Equatable {
    public struct Entry: Codable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// Item.anchorDate (nil = zamanı belirsiz).
        public var anchor: Date?
        /// Item.overdueStart(calendar:) — nil for events, notes and undated items.
        public var overdueAt: Date?
        public var hasTime: Bool
        public var kind: ItemKind
        public var priority: Priority
        public var isEvent: Bool

        public init(id: UUID, title: String, anchor: Date?, overdueAt: Date?, hasTime: Bool, kind: ItemKind,
                    priority: Priority, isEvent: Bool) {
            self.id = id
            self.title = title
            self.anchor = anchor
            self.overdueAt = overdueAt
            self.hasTime = hasTime
            self.kind = kind
            self.priority = priority
            self.isEvent = isEvent
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var overdueCount: Int
    public var todayCount: Int
    public var followUpCount: Int
    /// !AppSettings.lockScreenShowsContent → lock-screen widgets redact titles while the phone is locked.
    public var hideTitlesWhenLocked: Bool
    /// Overdue first (priority desc, oldest first), then anchored items of the next 7 days by anchor; ≤ 12.
    public var entries: [Entry]

    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, overdueCount: Int, todayCount: Int,
                followUpCount: Int, hideTitlesWhenLocked: Bool, entries: [Entry]) {
        self.version = version
        self.generatedAt = generatedAt
        self.overdueCount = overdueCount
        self.todayCount = todayCount
        self.followUpCount = followUpCount
        self.hideTitlesWhenLocked = hideTitlesWhenLocked
        self.entries = entries
    }

    public static let empty = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), overdueCount: 0,
                                             todayCount: 0, followUpCount: 0, hideTitlesWhenLocked: false,
                                             entries: [])

    /// Gallery / placeholder content.
    public static func placeholder(now: Date) -> WidgetSnapshot {
        let first = Entry(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID(),
                          title: "Teklif revizyonunu gönder", anchor: now.addingTimeInterval(3600),
                          overdueAt: now.addingTimeInterval(3600), hasTime: true, kind: .reminder,
                          priority: .high, isEvent: false)
        let second = Entry(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID(),
                           title: "Pano FAT tarihini netleştir", anchor: nil, overdueAt: nil, hasTime: false,
                           kind: .task, priority: .normal, isEvent: false)
        return WidgetSnapshot(generatedAt: now, overdueCount: 1, todayCount: 2, followUpCount: 1,
                              hideTitlesWhenLocked: false, entries: [first, second])
    }

    public func isOverdue(_ entry: Entry, at date: Date) -> Bool {
        guard let start = entry.overdueAt else { return false }
        return start <= date
    }

    /// End of an event entry: anchor + Item.eventDurationMinutes (the same rule as Item.eventEnd; the app closes the
    /// event at that instant on its next reconcile). nil for non-events and undated entries. Derived, so the stored
    /// schema is unchanged.
    public func eventEnd(_ entry: Entry) -> Date? {
        guard entry.isEvent, let anchor = entry.anchor else { return nil }
        return anchor.addingTimeInterval(TimeInterval(Item.eventDurationMinutes * 60))
    }

    /// true when `entry` is an event that has ended at `date` (the widget hides it without waiting for the app).
    public func isEnded(_ entry: Entry, at date: Date) -> Bool {
        guard let end = eventEnd(entry) else { return false }
        return end <= date
    }

    /// Entries still worth showing at `date`: ended events dropped, order kept.
    public func visibleEntries(at date: Date) -> [Entry] {
        return entries.filter { (entry: Entry) -> Bool in !isEnded(entry, at: date) }
    }

    /// Overdue count as time passes without the app running.
    public func overdueCount(at date: Date) -> Int {
        var added = 0
        for entry in entries {
            if let start = entry.overdueAt, start > generatedAt, start <= date {
                added += 1
            }
        }
        // Explicit type: `overdueCount` also names the method `overdueCount(at:)`.
        let stored: Int = self.overdueCount
        return stored + added
    }

    /// "bugün" counter at `date`: same day as `generatedAt` → stored count minus today's entries that became overdue
    /// or (events) ended since; another day → entries anchored on that day that are neither overdue nor ended
    /// (approximate: entries are capped).
    public func todayCount(at date: Date, calendar: Calendar) -> Int {
        if calendar.isDate(date, inSameDayAs: generatedAt) {
            var left: Int = self.todayCount       // the stored counter, not `todayCount(at:calendar:)`
            for entry in entries {
                guard let anchor = entry.anchor, calendar.isDate(anchor, inSameDayAs: generatedAt) else { continue }
                if let start = entry.overdueAt, start > generatedAt, start <= date {
                    left -= 1
                } else if let end = eventEnd(entry), end > generatedAt, end <= date {
                    left -= 1
                }
            }
            return max(0, left)
        }
        var count = 0
        for entry in entries {
            guard let anchor = entry.anchor, calendar.isDate(anchor, inSameDayAs: date) else { continue }
            if !isOverdue(entry, at: date) && !isEnded(entry, at: date) {
                count += 1
            }
        }
        return count
    }

    /// Timeline instants after `from`: overdue transitions and event ends within 24 h plus the next midnight;
    /// sorted, unique, ≤ limit.
    public func timelineDates(after from: Date, calendar: Calendar, limit: Int) -> [Date] {
        let horizon = from.addingTimeInterval(24 * 3600)
        var unique = Set<Date>()
        for entry in entries {
            if let start = entry.overdueAt, start > from, start <= horizon {
                unique.insert(start)
            }
            if let end = eventEnd(entry), end > from, end <= horizon {
                unique.insert(end)
            }
        }
        let midnight = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: from), calendar: calendar)
        if midnight > from && midnight <= horizon {
            unique.insert(midnight)
        }
        let sorted = Array(unique).sorted()
        return Array(sorted.prefix(max(0, limit)))
    }
}
