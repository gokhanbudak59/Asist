// API: Packages/AsistCore/Sources/AsistCore/Agenda/AgendaBuilder.swift
// WP2 (04 §3.5.5; behaviour 03 §3.9, §3.10, §4.3, §5.9 as amended by 04 §5.5 and 05b B3/B6/A1).
// Pure: every function depends only on its arguments (items, instant, settings, injected calendar).
import Foundation

public struct DayGroup: Equatable, Identifiable {
    public var id: String { AsistCalendar.pad(Int(day.timeIntervalSince1970), 12) }
    public var day: Date            // start of day
    public var title: String        // "Yarın", "Salı", "6 Ekim Salı"
    public var items: [Item]

    public init(day: Date, title: String, items: [Item]) {
        self.day = day
        self.title = title
        self.items = items
    }
}

public struct AgendaSnapshot: Equatable {
    public var overdue: [Item]      // priority desc, then oldest anchor first (hero = first); never events
    public var review: [Item]       // needsReview && open (any kind except note) — section "EMİN OLAMADIKLARIM"
    public var today: [Item]        // due today, not overdue, by anchor (events included); untimed tasks last ("Gün içinde")
    public var followUps: [Item]    // open .waiting items whose anchor is today (not overdue)
    public var upcoming: [DayGroup] // next 7 days after today, max 5 rows total → `upcomingTotal`
    public var upcomingTotal: Int
    public var unscheduled: [Item]  // open task/waiting/reminder without anchor — section "ZAMANI BELİRSİZ"
    public var doneThisWeek: Int    // completedAt in current Monday-first week
    public var overdueCount: Int { overdue.count }

    public init(overdue: [Item], review: [Item], today: [Item], followUps: [Item], upcoming: [DayGroup],
                upcomingTotal: Int, unscheduled: [Item], doneThisWeek: Int) {
        self.overdue = overdue
        self.review = review
        self.today = today
        self.followUps = followUps
        self.upcoming = upcoming
        self.upcomingTotal = upcomingTotal
        self.unscheduled = unscheduled
        self.doneThisWeek = doneThisWeek
    }
}

public struct SpokenAnswer: Equatable, Identifiable {
    public var id: String { title + "|" + text }
    public var title: String        // sheet title: "Bugünün ajandası"
    public var text: String         // TTS text (numbers as words, ≤ 5 items then "Diğerleri ekranda."), dialogSafe
    public var itemIDs: [UUID]      // items to list on screen, in spoken order

    public init(title: String, text: String, itemIDs: [UUID]) {
        self.title = title
        self.text = text
        self.itemIDs = itemIDs
    }
}

public struct NotificationText: Equatable {
    public var title: String
    public var subtitle: String
    public var body: String

    public init(title: String, subtitle: String, body: String) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

public enum AgendaBuilder {
    /// At most this many items are read aloud; the rest is "Diğerleri ekranda." (03 §5.9).
    static let spokenItemLimit = 5
    /// YAKLAŞAN shows at most this many rows (03 §4.3).
    static let upcomingRowLimit = 5
    /// YAKLAŞAN covers the days after today up to this many days ahead.
    static let upcomingDays = 7
    /// Titles listed in briefing / end-of-day bodies.
    static let digestTitleCount = 3
    static let digestTitleLimit = 32

    // MARK: - Today screen

    public static func snapshot(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> AgendaSnapshot {
        let open = items.filter { $0.isOpen && $0.kind != .note }
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = AsistCalendar.addingDays(1, to: todayStart, calendar: calendar)
        let horizon = AsistCalendar.addingDays(upcomingDays + 1, to: todayStart, calendar: calendar)

        var overdue: [Item] = []
        var today: [Item] = []
        var followUps: [Item] = []
        var upcomingItems: [Item] = []
        var unscheduled: [Item] = []
        for item in open {
            guard let anchor = item.anchorDate else {
                unscheduled.append(item)
                continue
            }
            if item.isOverdue(at: now, calendar: calendar) {
                overdue.append(item)
            } else if calendar.isDate(anchor, inSameDayAs: now) {
                if item.kind == .waiting {
                    followUps.append(item)
                } else {
                    today.append(item)
                }
            } else if anchor >= tomorrowStart && anchor < horizon {
                upcomingItems.append(item)
            }
        }

        let review = open.filter { $0.needsReview }.sorted(by: anchorOrder)
        let groups = upcomingGroups(upcomingItems, now: now, calendar: calendar)
        return AgendaSnapshot(overdue: overdue.sorted(by: overdueOrder),
                              review: review,
                              today: today.sorted(by: anchorOrder),
                              followUps: followUps.sorted(by: anchorOrder),
                              upcoming: groups,
                              upcomingTotal: upcomingItems.count,
                              unscheduled: unscheduled.sorted(by: unscheduledOrder),
                              doneThisWeek: doneThisWeek(items: items, now: now, calendar: calendar))
    }

    // MARK: - Spoken answers

    /// Query command (02 §10.5.1 scopes + project/person/queryText filters) → spoken + on-screen answer (03 §5.9).
    public static func answer(to command: ParsedCommand, items: [Item], projects: [Project], now: Date,
                              settings: AppSettings, calendar: Calendar) -> SpokenAnswer {
        var pool = items.filter { $0.isOpen }

        var projectDisplay: String? = nil
        if let projectName = nonEmpty(command.project) {
            let ids = FuzzyMatcher.projectIDs(named: projectName, in: projects)
            pool = pool.filter { item in
                guard let id = item.projectID else { return false }
                return ids.contains(id)
            }
            let canonical = projects.first(where: { ids.contains($0.id) })?.name
            projectDisplay = canonical ?? projectName
        }
        let personDisplay = nonEmpty(command.person)
        if let person = personDisplay {
            pool = pool.filter { FuzzyMatcher.personMatches(person, item: $0) }
        }

        // G6 "… var mı": the content noun narrows the scope. When nothing in the scope matches, say so and read
        // the whole scope instead of a misleading "nothing planned".
        if let query = nonEmpty(command.queryText), !FuzzyMatcher.tokens(query).isEmpty {
            let matched = pool.filter { item in
                let projectName = FuzzyMatcher.name(ofProject: item.projectID, in: projects)
                return FuzzyMatcher.score(query: query, item: item, projectName: projectName) >= 0.5
            }
            let narrowed = scopedAnswer(command, pool: matched, projectDisplay: projectDisplay,
                                        personDisplay: personDisplay, now: now, settings: settings, calendar: calendar)
            if !narrowed.itemIDs.isEmpty {
                return narrowed
            }
            var whole = scopedAnswer(command, pool: pool, projectDisplay: projectDisplay,
                                     personDisplay: personDisplay, now: now, settings: settings, calendar: calendar)
            whole.text = TurkishSpeech.dialogSafe("“" + query + "” ile ilgili bir kayıt bulamadım. " + whole.text)
            return whole
        }
        return scopedAnswer(command, pool: pool, projectDisplay: projectDisplay, personDisplay: personDisplay,
                            now: now, settings: settings, calendar: calendar)
    }

    /// The scope switch of `answer` over an already filtered pool of open items.
    private static func scopedAnswer(_ command: ParsedCommand, pool: [Item], projectDisplay: String?,
                                     personDisplay: String?, now: Date, settings: AppSettings,
                                     calendar: Calendar) -> SpokenAnswer {
        let todayStart = calendar.startOfDay(for: now)
        let result: SpokenAnswer
        switch command.scope ?? .today {
        case .today:
            let snap = snapshot(items: pool, now: now, settings: settings, calendar: calendar)
            result = todayAnswer(snap: snap, now: now, calendar: calendar)
        case .tomorrow:
            let day = AsistCalendar.addingDays(1, to: todayStart, calendar: calendar)
            result = dayAnswer(pool: pool, day: day, dayText: "Yarın", title: "Yarının ajandası",
                               now: now, calendar: calendar)
        case .date:
            let day = calendar.startOfDay(for: command.date ?? now)
            let offset = TurkishSpeech.dayOffset(from: now, to: day, calendar: calendar)
            if offset == 0 {
                let snap = snapshot(items: pool, now: now, settings: settings, calendar: calendar)
                result = todayAnswer(snap: snap, now: now, calendar: calendar)
            } else if offset == 1 {
                result = dayAnswer(pool: pool, day: day, dayText: "Yarın", title: "Yarının ajandası",
                                   now: now, calendar: calendar)
            } else {
                let spokenDay = TurkishText.upperFirst(TurkishSpeech.spokenDay(day, now: now, calendar: calendar))
                let dayText = offset == -1 ? spokenDay : spokenDay + " günü"
                let title = TurkishDateFormatter.datePhrase(day, now: now, calendar: calendar) + " ajandası"
                result = dayAnswer(pool: pool, day: day, dayText: dayText, title: title,
                                   now: now, calendar: calendar)
            }
        case .thisWeek:
            let end = nextMondayStart(now: now, calendar: calendar)
            result = rangeAnswer(pool: pool, start: todayStart, end: end, intro: "Bu hafta",
                                 title: "Bu haftanın ajandası", now: now, calendar: calendar)
        case .nextWeek:
            let start = nextMondayStart(now: now, calendar: calendar)
            let end = AsistCalendar.addingDays(7, to: start, calendar: calendar)
            result = rangeAnswer(pool: pool, start: start, end: end, intro: "Gelecek hafta",
                                 title: "Gelecek haftanın ajandası", now: now, calendar: calendar)
        case .overdue:
            let overdue = pool.filter { $0.kind != .note && $0.isOverdue(at: now, calendar: calendar) }
            result = overdueAnswer(overdue.sorted(by: overdueOrder))
        case .waiting:
            let waiting = pool.filter { $0.kind == .waiting }.sorted(by: anchorOrder)
            result = listAnswer(items: waiting, title: "Beklenenler", countPhrase: " takip var: ",
                                emptyText: "Bekleyen bir takip yok.")
        case .notes:
            let notes = pool.filter { $0.kind == .note }.sorted(by: newestFirst)
            result = listAnswer(items: notes, title: "Notlar", countPhrase: " notun var: ",
                                emptyText: "Kayıtlı notun yok.")
        case .tasks:
            let tasks = pool.filter { $0.kind == .task }.sorted(by: anchorOrder)
            result = listAnswer(items: tasks, title: "Görevler", countPhrase: " açık görevin var: ",
                                emptyText: "Açık görevin yok.")
        case .all:
            result = allAnswer(pool: pool, projectDisplay: projectDisplay, personDisplay: personDisplay)
        }
        return result
    }

    public static func todaySpoken(items: [Item], projects: [Project], now: Date, settings: AppSettings,
                                   calendar: Calendar) -> SpokenAnswer {
        let snap = snapshot(items: items, now: now, settings: settings, calendar: calendar)
        return todayAnswer(snap: snap, now: now, calendar: calendar)
    }

    public static func overdueSpoken(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> SpokenAnswer {
        let overdue = snapshot(items: items, now: now, settings: settings, calendar: calendar).overdue
        return overdueAnswer(overdue)
    }

    // MARK: - Briefing and end of day

    /// Content projected for the moment the briefing fires (03 §3.9). Body lists up to 3 titles overdue at
    /// `fireDate`: "Geciken: Teklif konusu, Ahmet'i ara +2" (05b B3), then today's count. nil = do not send
    /// (nothing overdue/today and !briefingWhenEmpty).
    public static func briefing(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText? {
        let snap = snapshot(items: items, now: fireDate, settings: settings, calendar: calendar)
        let total = snap.overdue.count + snap.today.count + snap.followUps.count
        let greeting = greetingHead(at: fireDate, settings: settings, calendar: calendar)
        if total == 0 {
            guard settings.briefingWhenEmpty else { return nil }
            return NotificationText(title: greeting + " — bugün planlı iş yok", subtitle: "",
                                    body: "Aklına bir şey gelirse söylemen yeterli.")
        }

        var lines: [String] = []
        if !snap.overdue.isEmpty {
            lines.append("Geciken: " + digestTitles(snap.overdue))
        }
        var segments: [String] = []
        if !snap.today.isEmpty {
            segments.append("Bugün " + String(snap.today.count) + " iş")
        }
        if !snap.followUps.isEmpty {
            segments.append(String(snap.followUps.count) + " takip")
        }
        var todayAll: [Item] = snap.today
        todayAll.append(contentsOf: snap.followUps)
        if let first = firstUpcomingTimed(todayAll, from: fireDate) {
            let time = TurkishDateFormatter.time(first.anchorDate ?? fireDate, calendar: calendar)
            segments.append("İlk: " + time + " " + TurkishText.truncated(spokenLabel(first), max: digestTitleLimit))
        }
        if segments.isEmpty {
            segments.append("Bugün için yeni iş yok")
        }
        lines.append(segments.joined(separator: " · "))

        let subtitle = snap.overdue.isEmpty ? "" : String(snap.overdue.count) + " geciken"
        return NotificationText(title: greeting + " — bugün " + String(total) + " iş", subtitle: subtitle,
                                body: lines.joined(separator: "\n"))
    }

    /// 03 §3.10. Candidates as `endOfDayCandidates`; later-today timed items are listed separately
    /// ("Bu akşam: 18:00 Ekmek al") and are NOT moved (05b B6). nil = no candidates → do not send.
    public static func endOfDay(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText? {
        let candidates = endOfDayCandidates(items: items, now: fireDate, calendar: calendar)
        guard !candidates.isEmpty else { return nil }

        let tomorrow = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: fireDate), calendar: calendar)
        let tomorrowIsWorkday = settings.isWorkday(isoWeekday: AsistCalendar.isoWeekday(tomorrow, calendar: calendar))
        let question = (settings.moveSkipsWeekend && !tomorrowIsWorkday)
            ? "Sonraki iş gününe taşıyayım mı? "
            : "Yarına taşıyayım mı? "
        var lines: [String] = [question + digestTitles(candidates)]

        let candidateIDs = Set(candidates.map { $0.id })
        let later = items.filter { item in
            guard item.isOpen, item.kind != .note, !candidateIDs.contains(item.id),
                  item.hasTime || item.snoozedUntil != nil,
                  let anchor = item.anchorDate else { return false }
            return anchor > fireDate && calendar.isDate(anchor, inSameDayAs: fireDate)
        }.sorted(by: anchorOrder)
        if !later.isEmpty {
            var entries: [String] = []
            for item in later.prefix(2) {
                let time = TurkishDateFormatter.time(item.anchorDate ?? fireDate, calendar: calendar)
                entries.append(time + " " + TurkishText.truncated(spokenLabel(item), max: digestTitleLimit))
            }
            var line = "Bu akşam: " + entries.joined(separator: ", ")
            if later.count > 2 {
                line += " +" + String(later.count - 2)
            }
            lines.append(line)
        }
        return NotificationText(title: "Gün sonu — " + String(candidates.count) + " iş açık kaldı", subtitle: "",
                                body: lines.joined(separator: "\n"))
    }

    /// Items affected by "Sonraki iş gününe taşı" at `now`: overdue + untimed today + timed today with anchor ≤ now;
    /// open reminder/task/waiting only; excludes notes, events and recurring items (05b B6).
    public static func endOfDayCandidates(items: [Item], now: Date, calendar: Calendar) -> [Item] {
        var result: [Item] = []
        for item in items {
            guard item.isOpen, item.kind != .note, !item.isEvent, item.recurrence == nil,
                  let anchor = item.anchorDate else { continue }
            if item.isOverdue(at: now, calendar: calendar) {
                result.append(item)
                continue
            }
            guard calendar.isDate(anchor, inSameDayAs: now) else { continue }
            let untimed = !item.hasTime && item.snoozedUntil == nil
            if untimed || anchor <= now {
                result.append(item)
            }
        }
        return result.sorted(by: overdueOrder)
    }

    /// Pure move to the next day (the next **workday** when settings.moveSkipsWeekend): timed → same clock time;
    /// untimed → defaultDayTime with hasTime = false; resets nag state; appends history .movedEndOfDay.
    public static func movedToTomorrow(_ item: Item, now: Date, settings: AppSettings, calendar: Calendar) -> Item {
        var moved = item
        let day: Date
        if settings.moveSkipsWeekend {
            day = AsistCalendar.addingWorkdays(1, to: now, workdays: settings.workdays, calendar: calendar)
        } else {
            day = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: now), calendar: calendar)
        }
        if item.hasTime, let anchor = item.anchorDate {
            let time = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(anchor, calendar: calendar))
            moved.dueDate = AsistCalendar.date(on: day, at: time, calendar: calendar)
            moved.hasTime = true
        } else {
            moved.dueDate = AsistCalendar.date(on: day, at: settings.defaultDayTime, calendar: calendar)
            moved.hasTime = false
        }
        moved.resetNagState()
        moved.updatedAt = now
        moved.appendHistory(.movedEndOfDay, at: now)
        return moved
    }

    // MARK: - Open-items safety file

    /// Human-readable safety copy written next to the backups (05b A1): header "Asist — açık işler (27 Eylül 2026 10:30)",
    /// then open non-note items sorted by anchor (undated last), one per line:
    /// "Salı 29.09 15:00 · Teklif konusu · Ahmet · Arka Cep", overdue lines prefixed "GECİKEN · ". Plain UTF-8, LF.
    public static func openItemsText(items: [Item], projects: [Project], now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let month = TurkishDateFormatter.months[min(11, max(0, (c.month ?? 1) - 1))]
        let stamp: String = String(c.day ?? 1) + " " + month + " " + String(c.year ?? 0)
        let header: String = "Asist — açık işler (" + stamp + " " + TurkishDateFormatter.time(now, calendar: calendar) + ")"
        let open = items.filter { $0.isOpen && $0.kind != .note }.sorted(by: fileOrder)
        var lines: [String] = [header]
        if open.isEmpty {
            lines.append("Açık iş yok.")
        }
        let nowYear = calendar.component(.year, from: now)
        for item in open {
            lines.append(openItemLine(item, projects: projects, now: now, nowYear: nowYear, calendar: calendar))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Ordering (internal: shared by tests and the spoken answers)

    /// Untimed tasks ("Gün içinde") last, then anchor ascending, priority descending, creation, id.
    static func anchorOrder(_ a: Item, _ b: Item) -> Bool {
        let untimedA = isUntimedTask(a)
        let untimedB = isUntimedTask(b)
        if untimedA != untimedB {
            return !untimedA
        }
        let anchorA = a.anchorDate ?? Date.distantFuture
        let anchorB = b.anchorDate ?? Date.distantFuture
        if anchorA != anchorB {
            return anchorA < anchorB
        }
        return tieBreak(a, b)
    }

    /// Priority descending, then oldest anchor first (hero card = first).
    static func overdueOrder(_ a: Item, _ b: Item) -> Bool {
        if a.priority != b.priority {
            return a.priority > b.priority
        }
        let anchorA = a.anchorDate ?? Date.distantFuture
        let anchorB = b.anchorDate ?? Date.distantFuture
        if anchorA != anchorB {
            return anchorA < anchorB
        }
        if a.createdAt != b.createdAt {
            return a.createdAt < b.createdAt
        }
        return a.id.uuidString < b.id.uuidString
    }

    static func isUntimedTask(_ item: Item) -> Bool {
        item.kind == .task && !item.hasTime && item.snoozedUntil == nil
    }

    // MARK: - Private helpers

    private static func tieBreak(_ a: Item, _ b: Item) -> Bool {
        if a.priority != b.priority {
            return a.priority > b.priority
        }
        if a.createdAt != b.createdAt {
            return a.createdAt < b.createdAt
        }
        return a.id.uuidString < b.id.uuidString
    }

    private static func unscheduledOrder(_ a: Item, _ b: Item) -> Bool {
        tieBreak(a, b)
    }

    private static func newestFirst(_ a: Item, _ b: Item) -> Bool {
        if a.createdAt != b.createdAt {
            return a.createdAt > b.createdAt
        }
        return a.id.uuidString < b.id.uuidString
    }

    /// Day first (so multi-day lists stay grouped), then `anchorOrder` inside the day; undated last.
    private static func dayThenAnchorOrder(_ a: Item, _ b: Item, calendar: Calendar) -> Bool {
        let dayA = a.anchorDate.map { calendar.startOfDay(for: $0) } ?? Date.distantFuture
        let dayB = b.anchorDate.map { calendar.startOfDay(for: $0) } ?? Date.distantFuture
        if dayA != dayB {
            return dayA < dayB
        }
        return anchorOrder(a, b)
    }

    /// Anchor ascending (undated last), untimed after timed on the same instant, then tie-break.
    private static func fileOrder(_ a: Item, _ b: Item) -> Bool {
        let anchorA = a.anchorDate ?? Date.distantFuture
        let anchorB = b.anchorDate ?? Date.distantFuture
        if anchorA != anchorB {
            return anchorA < anchorB
        }
        return tieBreak(a, b)
    }

    private static func upcomingGroups(_ items: [Item], now: Date, calendar: Calendar) -> [DayGroup] {
        var byDay: [Date: [Item]] = [:]
        for item in items {
            guard let anchor = item.anchorDate else { continue }
            let day = calendar.startOfDay(for: anchor)
            byDay[day, default: []].append(item)
        }
        var groups: [DayGroup] = []
        var rows = 0
        for day in byDay.keys.sorted() {
            if rows >= upcomingRowLimit {
                break
            }
            let dayItems = (byDay[day] ?? []).sorted(by: anchorOrder)
            let taken = Array(dayItems.prefix(upcomingRowLimit - rows))
            rows += taken.count
            let title = TurkishDateFormatter.shortDateTime(day, now: now, calendar: calendar, includeTime: false)
            groups.append(DayGroup(day: day, title: title, items: taken))
        }
        return groups
    }

    private static func doneThisWeek(items: [Item], now: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: now)
        let iso = AsistCalendar.isoWeekday(now, calendar: calendar)
        let weekStart = AsistCalendar.addingDays(-(iso - 1), to: todayStart, calendar: calendar)
        let weekEnd = AsistCalendar.addingDays(7, to: weekStart, calendar: calendar)
        var count = 0
        for item in items where item.status != .deleted {
            if item.recurrence != nil {
                for entry in item.history where entry.event == .occurrenceDone {
                    if entry.date >= weekStart && entry.date < weekEnd {
                        count += 1
                    }
                }
            }
            if item.status == .done, let completed = item.completedAt, completed >= weekStart, completed < weekEnd {
                count += 1
            }
        }
        return count
    }

    private static func nextMondayStart(now: Date, calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        let iso = AsistCalendar.isoWeekday(now, calendar: calendar)
        return AsistCalendar.addingDays(8 - iso, to: todayStart, calendar: calendar)
    }

    /// Spoken/list label: waiting items with a person read "Mehmet, I/O listesi" (no suffix after a name, 03 §5.12).
    static func spokenLabel(_ item: Item) -> String {
        var title = NotificationCopy.cleanTitle(item)
        while title.hasSuffix(".") {
            title.removeLast()
        }
        if item.kind == .waiting, let person = nonEmpty(item.person) {
            return person + ", " + title
        }
        return title
    }

    private static func todayAnswer(snap: AgendaSnapshot, now: Date, calendar: Calendar) -> SpokenAnswer {
        let title = "Bugünün ajandası"
        let overdue = snap.overdue
        let timed = snap.today.filter { !isUntimedTask($0) }
        let untimed = snap.today.filter { isUntimedTask($0) }
        let follow = snap.followUps
        let total = overdue.count + snap.today.count + follow.count
        guard total > 0 else {
            return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe("Bugün planlı bir işin yok."), itemIDs: [])
        }

        var sentences: [String] = ["Bugün " + TurkishSpeech.numberWords(total) + " işin var."]
        var budget = spokenItemLimit
        var spoken: [UUID] = []

        if !overdue.isEmpty {
            let taken = Array(overdue.prefix(budget))
            budget -= taken.count
            spoken.append(contentsOf: taken.map { $0.id })
            let head = TurkishText.upperFirst(TurkishSpeech.numberWords(overdue.count)) + " geciken iş: "
            let labels = joinedLabels(taken)
            sentences.append(head + labels + ".")
        }
        if budget > 0 && !timed.isEmpty {
            let taken = Array(timed.prefix(budget))
            budget -= taken.count
            for (index, item) in taken.enumerated() {
                spoken.append(item.id)
                let anchor = item.anchorDate ?? now
                let clock = calendar.dateComponents([.hour, .minute], from: anchor)
                let when = TurkishSpeech.spokenTimeOfDay(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
                let lead = (index == 0 && anchor >= now) ? "Sıradaki, " + when : TurkishText.upperFirst(when)
                sentences.append(lead + ": " + spokenLabel(item) + ".")
            }
        }
        if budget > 0 && !untimed.isEmpty {
            let taken = Array(untimed.prefix(budget))
            budget -= taken.count
            spoken.append(contentsOf: taken.map { $0.id })
            let labels = joinedLabels(taken)
            sentences.append("Gün içinde: " + labels + ".")
        }
        if !follow.isEmpty {
            let count = TurkishSpeech.numberWords(follow.count)
            if budget > 0 {
                let taken = Array(follow.prefix(budget))
                budget -= taken.count
                spoken.append(contentsOf: taken.map { $0.id })
                let labels = joinedLabels(taken)
                sentences.append("Ayrıca " + count + " takip var: " + labels + ".")
            } else {
                sentences.append("Ayrıca " + count + " takip var.")
            }
        }
        if spoken.count < total {
            sentences.append("Diğerleri ekranda.")
        }

        var ordered: [Item] = overdue
        ordered.append(contentsOf: timed)
        ordered.append(contentsOf: untimed)
        ordered.append(contentsOf: follow)
        let ids = spokenFirst(spoken, rest: ordered)
        return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(sentences.joined(separator: " ")), itemIDs: ids)
    }

    private static func overdueAnswer(_ overdue: [Item]) -> SpokenAnswer {
        let title = "Gecikenler"
        guard !overdue.isEmpty else {
            return SpokenAnswer(title: title, text: "Geciken işin yok.", itemIDs: [])
        }
        let taken = Array(overdue.prefix(spokenItemLimit))
        let head = TurkishText.upperFirst(TurkishSpeech.numberWords(overdue.count))
        let labels = joinedLabels(taken)
        var text = head + " geciken iş var: " + labels + "."
        if overdue.count > taken.count {
            text += " Diğerleri ekranda."
        }
        return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(text), itemIDs: overdue.map { $0.id })
    }

    /// One day other than today: "Yarın iki işin var. Sabah dokuzda: Haftalık rapor. Gün içinde: Sipariş formu."
    private static func dayAnswer(pool: [Item], day: Date, dayText: String, title: String,
                                  now: Date, calendar: Calendar) -> SpokenAnswer {
        let dayEnd = AsistCalendar.addingDays(1, to: day, calendar: calendar)
        let list = pool.filter { item in
            guard item.kind != .note, let anchor = item.anchorDate else { return false }
            return anchor >= day && anchor < dayEnd && !item.isOverdue(at: now, calendar: calendar)
        }.sorted(by: anchorOrder)
        guard !list.isEmpty else {
            return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(dayText + " planlı bir işin yok."), itemIDs: [])
        }
        var sentences: [String] = [dayText + " " + TurkishSpeech.numberWords(list.count) + " işin var."]
        for item in list.prefix(spokenItemLimit) {
            sentences.append(entrySentence(item, withDay: false, now: now, calendar: calendar))
        }
        if list.count > spokenItemLimit {
            sentences.append("Diğerleri ekranda.")
        }
        return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(sentences.joined(separator: " ")),
                            itemIDs: list.map { $0.id })
    }

    /// A range of days: "Bu hafta üç işin var. Salı öğleden sonra üçte: Teklif konusu. …"
    private static func rangeAnswer(pool: [Item], start: Date, end: Date, intro: String, title: String,
                                    now: Date, calendar: Calendar) -> SpokenAnswer {
        let list = pool.filter { item in
            guard item.kind != .note, let anchor = item.anchorDate else { return false }
            return anchor >= start && anchor < end && !item.isOverdue(at: now, calendar: calendar)
        }.sorted { lhs, rhs in
            dayThenAnchorOrder(lhs, rhs, calendar: calendar)
        }
        guard !list.isEmpty else {
            return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(intro + " planlı bir işin yok."), itemIDs: [])
        }
        var sentences: [String] = [intro + " " + TurkishSpeech.numberWords(list.count) + " işin var."]
        for item in list.prefix(spokenItemLimit) {
            sentences.append(entrySentence(item, withDay: true, now: now, calendar: calendar))
        }
        if list.count > spokenItemLimit {
            sentences.append("Diğerleri ekranda.")
        }
        return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(sentences.joined(separator: " ")),
                            itemIDs: list.map { $0.id })
    }

    /// "Üç takip var: Mehmet, I/O listesi; Ahmet, teklif. Diğerleri ekranda."
    private static func listAnswer(items: [Item], title: String, countPhrase: String, emptyText: String) -> SpokenAnswer {
        guard !items.isEmpty else {
            return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(emptyText), itemIDs: [])
        }
        let taken = Array(items.prefix(spokenItemLimit))
        let head = TurkishText.upperFirst(TurkishSpeech.numberWords(items.count))
        let labels = joinedLabels(taken)
        var text = head + countPhrase + labels + "."
        if items.count > taken.count {
            text += " Diğerleri ekranda."
        }
        return SpokenAnswer(title: title, text: TurkishSpeech.dialogSafe(text), itemIDs: items.map { $0.id })
    }

    private static func allAnswer(pool: [Item], projectDisplay: String?, personDisplay: String?) -> SpokenAnswer {
        let filtered = projectDisplay != nil || personDisplay != nil
        let list = pool.filter { filtered || $0.kind != .note }.sorted(by: anchorOrder)
        if let project = projectDisplay {
            return listAnswer(items: list, title: "Proje: " + project,
                              countPhrase: " açık kayıt var: ",
                              emptyText: project + " projesinde açık kayıt yok.")
                .prefixed(list.isEmpty ? nil : project + " projesinde")
        }
        if let person = personDisplay {
            return listAnswer(items: list, title: "Kişi: " + person,
                              countPhrase: " açık kayıt var: ",
                              emptyText: person + " ile ilgili açık kayıt yok.")
                .prefixed(list.isEmpty ? nil : person + " ile ilgili")
        }
        return listAnswer(items: list, title: "Tüm açık işler", countPhrase: " açık işin var: ",
                          emptyText: "Açık işin yok.")
    }

    /// "Öğleden sonra üçte: Teklif konusu." / "Salı öğleden sonra üçte: …" / "Gün içinde: …" / "Cuma: …".
    private static func entrySentence(_ item: Item, withDay: Bool, now: Date, calendar: Calendar) -> String {
        let label = spokenLabel(item)
        guard let anchor = item.anchorDate else { return label + "." }
        if isUntimedTask(item) || (item.kind == .waiting && !item.hasTime) {
            if withDay {
                return TurkishText.upperFirst(TurkishSpeech.spokenDay(anchor, now: now, calendar: calendar)) + ": " + label + "."
            }
            return "Gün içinde: " + label + "."
        }
        let when: String
        if withDay {
            when = TurkishSpeech.spokenWhen(anchor, now: now, calendar: calendar)
        } else {
            let clock = calendar.dateComponents([.hour, .minute], from: anchor)
            when = TurkishSpeech.spokenTimeOfDay(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
        }
        return TurkishText.upperFirst(when) + ": " + label + "."
    }

    /// "Pano ısınması; Ahmet'i ara".
    private static func joinedLabels(_ items: [Item]) -> String {
        var labels: [String] = []
        for item in items {
            labels.append(spokenLabel(item))
        }
        return labels.joined(separator: "; ")
    }

    /// Spoken ids first (in spoken order), then every other listed item.
    private static func spokenFirst(_ spoken: [UUID], rest: [Item]) -> [UUID] {
        var ids = spoken
        var seen = Set(spoken)
        for item in rest where !seen.contains(item.id) {
            seen.insert(item.id)
            ids.append(item.id)
        }
        return ids
    }

    /// "Günaydın" / "Günaydın, Gökhan" by the hour of `date` (same rule as the Today header).
    private static func greetingHead(at date: Date, settings: AppSettings, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting: String
        if hour < 12 {
            greeting = "Günaydın"
        } else if hour < 18 {
            greeting = "İyi günler"
        } else if hour < 22 {
            greeting = "İyi akşamlar"
        } else {
            greeting = "İyi geceler"
        }
        let name = settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? greeting : greeting + ", " + name
    }

    /// "Teklif konusu, Ahmet'i ara, Rapor +2".
    private static func digestTitles(_ items: [Item]) -> String {
        let names = items.prefix(digestTitleCount).map { TurkishText.truncated(spokenLabel($0), max: digestTitleLimit) }
        var text = names.joined(separator: ", ")
        if items.count > digestTitleCount {
            text += " +" + String(items.count - digestTitleCount)
        }
        return text
    }

    /// Earliest item with an explicit time at or after `date`.
    private static func firstUpcomingTimed(_ items: [Item], from date: Date) -> Item? {
        var best: Item? = nil
        for item in items where item.hasTime || item.snoozedUntil != nil {
            guard let anchor = item.anchorDate, anchor >= date else { continue }
            if let current = best, let currentAnchor = current.anchorDate, currentAnchor <= anchor {
                continue
            }
            best = item
        }
        return best
    }

    private static func openItemLine(_ item: Item, projects: [Project], now: Date, nowYear: Int,
                                     calendar: Calendar) -> String {
        var parts: [String] = []
        if let anchor = item.anchorDate {
            let c = calendar.dateComponents([.year, .month, .day], from: anchor)
            let dayMonth: String = AsistCalendar.pad(c.day ?? 1, 2) + "." + AsistCalendar.pad(c.month ?? 1, 2)
            var date: String = TurkishSpeech.weekdayName(anchor, calendar: calendar) + " " + dayMonth
            if let year = c.year, year != nowYear {
                date += "." + String(year)
            }
            if item.hasTime || item.snoozedUntil != nil {
                date += " " + TurkishDateFormatter.time(anchor, calendar: calendar)
            }
            parts.append(date)
        } else {
            parts.append("Zamanı belirsiz")
        }
        let title = NotificationCopy.cleanTitle(item).replacingOccurrences(of: "\n", with: " ")
        parts.append(item.kind == .waiting ? "Takip: " + title : title)
        if let person = nonEmpty(item.person) {
            parts.append(person)
        }
        if let projectName = FuzzyMatcher.name(ofProject: item.projectID, in: projects) {
            parts.append(projectName)
        }
        if item.priority >= .high {
            parts.append(item.priority.label)
        }
        if let rule = item.recurrence {
            parts.append(TurkishDateFormatter.recurrenceText(rule))
        }
        let line = parts.joined(separator: " · ")
        return item.isOverdue(at: now, calendar: calendar) ? "GECİKEN · " + line : line
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension SpokenAnswer {
    /// "Arka Cep projesinde" + " " + "üç açık kayıt var: …" — lower-cases the number word that followed.
    func prefixed(_ head: String?) -> SpokenAnswer {
        guard let head = head else { return self }
        var copy = self
        copy.text = TurkishSpeech.dialogSafe(head + " " + TurkishText.lower(String(text.prefix(1))) + String(text.dropFirst()))
        return copy
    }
}
