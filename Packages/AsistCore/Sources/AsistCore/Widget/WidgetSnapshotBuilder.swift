// FILE: Packages/AsistCore/Sources/AsistCore/Widget/WidgetSnapshotBuilder.swift
// Revision 4 (07 §5.4): pure selection of the widget data. The app writes the result into the App Group
// container (WidgetSnapshotWriter); the widget extension only reads it.
import Foundation

public enum WidgetSnapshotBuilder {
    public static let maxEntries = 12
    public static let horizonDays = 7
    public static let maxTitleLength = 80

    /// pool = items.filter(isNotifiable). overdue = isOverdue(at: now) sorted (priority desc, overdueStart asc,
    /// createdAt asc, id.uuidString asc). upcoming = not overdue, anchorDate != nil, anchor < startOfDay(now) + 7 days,
    /// sorted (anchor asc, priority desc, createdAt asc, id). entries = (overdue + upcoming).prefix(12) with
    /// title = TurkishText.truncated(title, max: 80) ("Başlıksız" when empty), overdueAt = overdueStart(calendar:).
    /// overdueCount = overdue.count; todayCount = pool.filter(isDueToday(at: now)).count;
    /// followUpCount = pool.filter(kind == .waiting).count; hideTitlesWhenLocked = !settings.lockScreenShowsContent;
    /// generatedAt = now.
    public static func build(items: [Item], settings: AppSettings, now: Date, calendar: Calendar) -> WidgetSnapshot {
        let pool = items.filter { (item: Item) -> Bool in item.isNotifiable }
        let horizonEnd = AsistCalendar.addingDays(horizonDays, to: calendar.startOfDay(for: now), calendar: calendar)

        var overdue: [Candidate] = []
        var upcoming: [Candidate] = []
        var todayCount = 0
        var followUpCount = 0
        for item in pool {
            if item.kind == .waiting {
                followUpCount += 1
            }
            if item.isDueToday(at: now, calendar: calendar) {
                todayCount += 1
            }
            let overdueAt = item.overdueStart(calendar: calendar)
            if item.isOverdue(at: now, calendar: calendar) {
                overdue.append(Candidate(item: item, anchor: item.anchorDate, overdueAt: overdueAt))
            } else if let anchor = item.anchorDate, anchor < horizonEnd {
                upcoming.append(Candidate(item: item, anchor: anchor, overdueAt: overdueAt))
            }
        }

        overdue.sort { (a: Candidate, b: Candidate) -> Bool in
            if a.item.priority != b.item.priority {
                return a.item.priority > b.item.priority
            }
            let startA = a.overdueAt ?? Date.distantPast
            let startB = b.overdueAt ?? Date.distantPast
            if startA != startB {
                return startA < startB
            }
            return tieBreak(a.item, b.item)
        }
        upcoming.sort { (a: Candidate, b: Candidate) -> Bool in
            let anchorA = a.anchor ?? Date.distantFuture
            let anchorB = b.anchor ?? Date.distantFuture
            if anchorA != anchorB {
                return anchorA < anchorB
            }
            if a.item.priority != b.item.priority {
                return a.item.priority > b.item.priority
            }
            return tieBreak(a.item, b.item)
        }

        var entries: [WidgetSnapshot.Entry] = []
        for candidate in overdue + upcoming {
            if entries.count >= maxEntries {
                break
            }
            let item = candidate.item
            entries.append(WidgetSnapshot.Entry(id: item.id, title: displayTitle(item.title), anchor: candidate.anchor,
                                                overdueAt: candidate.overdueAt, hasTime: item.hasTime,
                                                kind: item.kind, priority: item.priority, isEvent: item.isEvent))
        }

        return WidgetSnapshot(generatedAt: now, overdueCount: overdue.count, todayCount: todayCount,
                              followUpCount: followUpCount, hideTitlesWhenLocked: !settings.lockScreenShowsContent,
                              entries: entries)
    }

    /// One widget line: line breaks become spaces, surrounding blanks trimmed, cut at a word boundary to
    /// `maxTitleLength` characters ("…"); empty → "Başlıksız".
    public static func displayTitle(_ raw: String) -> String {
        let parts = raw.components(separatedBy: CharacterSet.newlines)
            .map { (part: String) -> String in part.trimmingCharacters(in: .whitespaces) }
            .filter { (part: String) -> Bool in !part.isEmpty }
        let flat = parts.joined(separator: " ")
        if flat.isEmpty {
            return "Başlıksız"
        }
        return TurkishText.truncated(flat, max: maxTitleLength)
    }

    /// true when `a` and `b` show the same widget content: equal apart from `generatedAt`, and generated on the same
    /// calendar day (the "bugün" counter of a snapshot depends on its day). The writer skips identical rewrites.
    public static func isEquivalent(_ a: WidgetSnapshot, _ b: WidgetSnapshot, calendar: Calendar) -> Bool {
        guard calendar.isDate(a.generatedAt, inSameDayAs: b.generatedAt) else { return false }
        var left = a
        var right = b
        let epoch = Date(timeIntervalSince1970: 0)
        left.generatedAt = epoch
        right.generatedAt = epoch
        return left == right
    }

    // MARK: Private

    private struct Candidate {
        let item: Item
        let anchor: Date?
        let overdueAt: Date?
    }

    private static func tieBreak(_ a: Item, _ b: Item) -> Bool {
        if a.createdAt != b.createdAt {
            return a.createdAt < b.createdAt
        }
        return a.id.uuidString < b.id.uuidString
    }
}
