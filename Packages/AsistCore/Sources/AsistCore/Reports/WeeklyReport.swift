// API: Packages/AsistCore/Sources/AsistCore/Reports/WeeklyReport.swift
// Revision 4 (07 §7.2, F4): "Haftalık durum raporu" — a pure builder (Linux-tested) and the plain-text format that
// the report screen shows, copies and shares (e-mail, WhatsApp). Locale-free: TurkishDateFormatter only.
import Foundation

public struct WeeklyReport: Equatable {
    public struct Line: Equatable, Identifiable {
        /// Item uuidString; occurrence lines: uuidString + "#" + minuteKey.
        public var id: String
        public var itemID: UUID
        public var title: String
        /// "25 Eylül Cuma", "Dün 15:00", "Zamanı belirsiz", "3 gündür"
        public var detail: String

        public init(id: String, itemID: UUID, title: String, detail: String) {
            self.id = id
            self.itemID = itemID
            self.title = title
            self.detail = detail
        }
    }

    public struct PersonGroup: Equatable, Identifiable {
        public var id: String { person }
        /// Display spelling, or "Kişi belirtilmemiş".
        public var person: String
        public var lines: [Line]

        public init(person: String, lines: [Line]) {
            self.person = person
            self.lines = lines
        }
    }

    public struct ProjectSection: Equatable, Identifiable {
        /// Project uuidString, or WeeklyReportBuilder.noProjectID.
        public var id: String
        /// Project name, or "Projesiz".
        public var title: String
        public var done: [Line]
        public var overdue: [Line]
        public var open: [Line]
        public var nextWeek: [Line]
        public var waiting: [PersonGroup]

        public init(id: String, title: String, done: [Line] = [], overdue: [Line] = [], open: [Line] = [],
                    nextWeek: [Line] = [], waiting: [PersonGroup] = []) {
            self.id = id
            self.title = title
            self.done = done
            self.overdue = overdue
            self.open = open
            self.nextWeek = nextWeek
            self.waiting = waiting
        }

        /// Number of waiting lines over all person groups.
        public var waitingCount: Int {
            var count = 0
            for group in waiting {
                count += group.lines.count
            }
            return count
        }

        public var isEmpty: Bool {
            done.isEmpty && overdue.isEmpty && open.isEmpty && nextWeek.isEmpty && waitingCount == 0
        }
    }

    public struct Totals: Equatable {
        public var done: Int
        public var overdue: Int
        public var open: Int
        public var nextWeek: Int
        public var waiting: Int

        public init(done: Int = 0, overdue: Int = 0, open: Int = 0, nextWeek: Int = 0, waiting: Int = 0) {
            self.done = done
            self.overdue = overdue
            self.open = open
            self.nextWeek = nextWeek
            self.waiting = waiting
        }

        /// "5 tamamlandı · 2 geciken · 7 açık · 4 gelecek hafta · 3 bekleniyor"
        public var summaryLine: String {
            let parts: [String] = [
                String(done) + " tamamlandı",
                String(overdue) + " geciken",
                String(open) + " açık",
                String(nextWeek) + " gelecek hafta",
                String(waiting) + " bekleniyor"
            ]
            return parts.joined(separator: " · ")
        }
    }

    /// Monday 00:00.
    public var weekStart: Date
    /// Next Monday 00:00 (exclusive).
    public var weekEnd: Date
    /// "21–27 Eylül 2026" · "28 Eylül – 4 Ekim 2026" · "28 Aralık 2026 – 3 Ocak 2027"
    public var rangeTitle: String
    /// Non-empty sections only; projects by weight desc then name; "Projesiz" last.
    public var sections: [ProjectSection]
    public var totals: Totals

    public init(weekStart: Date, weekEnd: Date, rangeTitle: String, sections: [ProjectSection], totals: Totals) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.rangeTitle = rangeTitle
        self.sections = sections
        self.totals = totals
    }

    public var isEmpty: Bool { sections.isEmpty }
}

public enum WeeklyReportBuilder {
    public static let maxLinesPerList = 12
    public static let noProjectID = "projesiz"
    public static let noProjectTitle = "Projesiz"
    public static let noPersonTitle = "Kişi belirtilmemiş"

    /// Monday 00:00 of the ISO week containing `date` (AsistCalendar.isoWeekday; independent of firstWeekday).
    public static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let iso = AsistCalendar.isoWeekday(day, calendar: calendar)
        return AsistCalendar.addingDays(1 - iso, to: day, calendar: calendar)
    }

    /// weekOffset 0 = this week, −1 = last week. Deleted items and notes are ignored; open items are evaluated at
    /// `now` (07 §7.2 rules 1–5).
    public static func build(items: [Item], projects: [Project], now: Date, weekOffset: Int,
                             calendar: Calendar) -> WeeklyReport {
        let thisWeek = weekStart(containing: now, calendar: calendar)
        let start = AsistCalendar.addingDays(7 * weekOffset, to: thisWeek, calendar: calendar)
        let end = AsistCalendar.addingDays(7, to: start, calendar: calendar)
        let until = min(end, now)
        let followingEnd = AsistCalendar.addingDays(7, to: end, calendar: calendar)

        var projectNames: [UUID: String] = [:]
        for project in projects {
            projectNames[project.id] = project.name
        }

        var buckets: [String: Bucket] = [:]
        var seenDoneIDs = Set<String>()

        for item in items where item.status != .deleted && item.kind != .note {
            var sectionID = noProjectID
            var sectionTitle = noProjectTitle
            if let projectID = item.projectID, let name = projectNames[projectID] {
                sectionID = projectID.uuidString
                sectionTitle = name
            }
            var bucket = buckets[sectionID] ?? Bucket(title: sectionTitle)
            let title = lineTitle(item.title)

            // Rule 2: completed in [start, until).
            if item.status == .done, let completed = item.completedAt, completed >= start, completed < until {
                let id = item.id.uuidString
                if !seenDoneIDs.contains(id) {
                    seenDoneIDs.insert(id)
                    let detail = TurkishDateFormatter.shortDateTime(completed, now: now, calendar: calendar,
                                                                    includeTime: false)
                    let line = WeeklyReport.Line(id: id, itemID: item.id, title: title, detail: detail)
                    bucket.done.append(Entry(primary: completed, secondary: completed, line: line))
                }
            }
            for entry in item.history where entry.event == .occurrenceDone && entry.date >= start && entry.date < until {
                let id = item.id.uuidString + "#" + AsistCalendar.minuteKey(entry.date, calendar: calendar)
                if seenDoneIDs.contains(id) {
                    continue
                }
                seenDoneIDs.insert(id)
                let detail = TurkishDateFormatter.shortDateTime(entry.date, now: now, calendar: calendar,
                                                                includeTime: false)
                let line = WeeklyReport.Line(id: id, itemID: item.id, title: title + " (tekrar)", detail: detail)
                bucket.done.append(Entry(primary: entry.date, secondary: entry.date, line: line))
            }

            // Rule 3: open items at `now`.
            if item.status == .open {
                classifyOpen(item, title: title, into: &bucket, now: now, end: end, followingEnd: followingEnd,
                             calendar: calendar)
            }
            buckets[sectionID] = bucket
        }

        // Rule 4: sections by weight, "Projesiz" last.
        var ranked: [RankedSection] = []
        var projectless: WeeklyReport.ProjectSection? = nil
        for (sectionID, bucket) in buckets {
            let section = WeeklyReport.ProjectSection(id: sectionID, title: bucket.title,
                                                      done: sortedLines(bucket.done),
                                                      overdue: sortedLines(bucket.overdue),
                                                      open: sortedLines(bucket.open),
                                                      nextWeek: sortedLines(bucket.nextWeek),
                                                      waiting: waitingGroups(bucket.waiting))
            if section.isEmpty {
                continue
            }
            if sectionID == noProjectID {
                projectless = section
            } else {
                ranked.append(RankedSection(weight: weight(of: section), sortName: TurkishText.searchKey(section.title),
                                            section: section))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.weight != rhs.weight {
                return lhs.weight > rhs.weight
            }
            if lhs.sortName != rhs.sortName {
                return lhs.sortName < rhs.sortName
            }
            return lhs.section.id < rhs.section.id
        }
        var sections: [WeeklyReport.ProjectSection] = ranked.map { (entry: RankedSection) -> WeeklyReport.ProjectSection in
            entry.section
        }
        if let projectless = projectless {
            sections.append(projectless)
        }

        // Rule 5: totals over all lines (uncapped).
        var totals = WeeklyReport.Totals()
        for section in sections {
            totals.done += section.done.count
            totals.overdue += section.overdue.count
            totals.open += section.open.count
            totals.nextWeek += section.nextWeek.count
            totals.waiting += section.waitingCount
        }
        return WeeklyReport(weekStart: start, weekEnd: end, rangeTitle: rangeTitle(start: start, calendar: calendar),
                            sections: sections, totals: totals)
    }

    /// Plain text for e-mail / WhatsApp. Lists are capped at `maxLinesPerList` lines + "- … ve N iş daha";
    /// empty lists are omitted; the signature is added only when `userName` is non-empty after trimming.
    public static func text(_ report: WeeklyReport, userName: String) -> String {
        var lines: [String] = []
        lines.append("HAFTALIK DURUM · " + report.rangeTitle)
        if report.isEmpty {
            lines.append("Bu hafta için raporlanacak kayıt yok.")
        } else {
            lines.append(report.totals.summaryLine)
            for section in report.sections {
                lines.append("")
                lines.append(TurkishText.upper(section.title))
                appendList("Tamamlanan", entries: section.done.map(lineText), to: &lines)
                appendList("Geciken", entries: section.overdue.map(lineText), to: &lines)
                appendList("Açık", entries: section.open.map(lineText), to: &lines)
                appendList("Gelecek hafta", entries: section.nextWeek.map(lineText), to: &lines)
                var waiting: [String] = []
                for group in section.waiting {
                    for line in group.lines {
                        if group.person == noPersonTitle {
                            waiting.append(lineText(line))
                        } else {
                            waiting.append(group.person + ": " + lineText(line))
                        }
                    }
                }
                appendList("Beklenenler", entries: waiting, to: &lines)
            }
        }
        let signature = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !signature.isEmpty {
            lines.append("")
            lines.append(signature)
        }
        return lines.joined(separator: "\n")
    }

    /// "21–27 Eylül 2026" · "28 Eylül – 4 Ekim 2026" · "28 Aralık 2026 – 3 Ocak 2027" (Monday … Sunday).
    public static func rangeTitle(start: Date, calendar: Calendar) -> String {
        let last = AsistCalendar.addingDays(6, to: start, calendar: calendar)
        let firstParts = calendar.dateComponents([.year, .month, .day], from: start)
        let lastParts = calendar.dateComponents([.year, .month, .day], from: last)
        let firstDay: String = String(firstParts.day ?? 1)
        let firstMonth: String = TurkishDateFormatter.monthName(firstParts.month ?? 1)
        let firstYear: String = String(firstParts.year ?? 0)
        let lastDay: String = String(lastParts.day ?? 1)
        let lastMonth: String = TurkishDateFormatter.monthName(lastParts.month ?? 1)
        let lastYear: String = String(lastParts.year ?? 0)
        if firstYear != lastYear {
            return firstDay + " " + firstMonth + " " + firstYear + " – " + lastDay + " " + lastMonth + " " + lastYear
        }
        if firstMonth != lastMonth {
            return firstDay + " " + firstMonth + " – " + lastDay + " " + lastMonth + " " + lastYear
        }
        return firstDay + "–" + lastDay + " " + lastMonth + " " + lastYear
    }

    // MARK: - Private

    fileprivate struct Entry {
        /// Sort instant; nil = undated (sorts last).
        var primary: Date?
        /// Tie-break (creation / completion instant).
        var secondary: Date
        var line: WeeklyReport.Line
    }

    fileprivate struct WaitingBucket {
        var display: String
        var entries: [Entry]
    }

    fileprivate struct Bucket {
        var title: String
        var done: [Entry] = []
        var overdue: [Entry] = []
        var open: [Entry] = []
        var nextWeek: [Entry] = []
        /// Keyed by TurkishText.searchKey(person); "" = no person.
        var waiting: [String: WaitingBucket] = [:]

        init(title: String) {
            self.title = title
        }
    }

    fileprivate struct RankedSection {
        var weight: Int
        var sortName: String
        var section: WeeklyReport.ProjectSection
    }

    private static func classifyOpen(_ item: Item, title: String, into bucket: inout Bucket, now: Date, end: Date,
                                     followingEnd: Date, calendar: Calendar) {
        if item.kind == .waiting {
            let display = (item.person ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TurkishText.searchKey(display)
            let days = dayDistance(from: item.createdAt, to: now, calendar: calendar)
            let detail = days >= 1 ? String(days) + " gündür" : "bugün"
            let line = WeeklyReport.Line(id: item.id.uuidString, itemID: item.id, title: title, detail: detail)
            var group = bucket.waiting[key] ?? WaitingBucket(display: key.isEmpty ? noPersonTitle : display, entries: [])
            group.entries.append(Entry(primary: item.createdAt, secondary: item.createdAt, line: line))
            bucket.waiting[key] = group
            return
        }
        let showsClock = item.hasTime || item.snoozedUntil != nil || item.kind == .reminder
        guard let anchor = item.anchorDate else {
            let line = WeeklyReport.Line(id: item.id.uuidString, itemID: item.id, title: title,
                                         detail: "Zamanı belirsiz")
            bucket.open.append(Entry(primary: nil, secondary: item.createdAt, line: line))
            return
        }
        let detail = TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: showsClock)
        let line = WeeklyReport.Line(id: item.id.uuidString, itemID: item.id, title: title, detail: detail)
        let entry = Entry(primary: anchor, secondary: item.createdAt, line: line)
        if item.isOverdue(at: now, calendar: calendar) {
            bucket.overdue.append(entry)
        } else if anchor < end {
            bucket.open.append(entry)
        } else if anchor < followingEnd {
            bucket.nextWeek.append(entry)
        }
    }

    /// Primary instant ascending (undated last), then the tie-break instant, then the line id.
    private static func sortedLines(_ entries: [Entry]) -> [WeeklyReport.Line] {
        let ordered = entries.sorted { (lhs: Entry, rhs: Entry) -> Bool in
            switch (lhs.primary, rhs.primary) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            if lhs.secondary != rhs.secondary {
                return lhs.secondary < rhs.secondary
            }
            return lhs.line.id < rhs.line.id
        }
        return ordered.map { (entry: Entry) -> WeeklyReport.Line in entry.line }
    }

    /// Named groups by key, "Kişi belirtilmemiş" last; lines by creation.
    private static func waitingGroups(_ groups: [String: WaitingBucket]) -> [WeeklyReport.PersonGroup] {
        let keys = groups.keys.sorted { (lhs: String, rhs: String) -> Bool in
            if lhs.isEmpty != rhs.isEmpty {
                return !lhs.isEmpty
            }
            return lhs < rhs
        }
        var result: [WeeklyReport.PersonGroup] = []
        for key in keys {
            guard let group = groups[key] else { continue }
            result.append(WeeklyReport.PersonGroup(person: group.display, lines: sortedLines(group.entries)))
        }
        return result
    }

    /// 3·overdue + open + done + nextWeek + waiting lines.
    private static func weight(of section: WeeklyReport.ProjectSection) -> Int {
        3 * section.overdue.count + section.open.count + section.done.count + section.nextWeek.count
            + section.waitingCount
    }

    private static func lineTitle(_ raw: String) -> String {
        let flat = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? "Başlıksız" : flat
    }

    private static func lineText(_ line: WeeklyReport.Line) -> String {
        line.detail.isEmpty ? line.title : line.title + " · " + line.detail
    }

    private static func appendList(_ title: String, entries: [String], to lines: inout [String]) {
        guard !entries.isEmpty else { return }
        lines.append(title + " (" + String(entries.count) + ")")
        for entry in entries.prefix(maxLinesPerList) {
            lines.append("- " + entry)
        }
        if entries.count > maxLinesPerList {
            lines.append("- … ve " + String(entries.count - maxLinesPerList) + " iş daha")
        }
    }

    /// Calendar days between the two instants' days (b − a).
    private static func dayDistance(from a: Date, to b: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: a)
        let endDay = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }
}
