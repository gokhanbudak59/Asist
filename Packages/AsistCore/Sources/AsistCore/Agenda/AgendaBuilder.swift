// API: Packages/AsistCore/Sources/AsistCore/Agenda/AgendaBuilder.swift
// WP0 STUB (04 §3.5.5) — WP2 replaces this file. Types are final; builders are simplified.
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
    public static func snapshot(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> AgendaSnapshot {
        // WP0 STUB: plain section filters, no upcoming groups.
        let open = items.filter { $0.isOpen && $0.kind != .note }
        let overdue = stubSortedByAnchor(open.filter { $0.isOverdue(at: now, calendar: calendar) })
        let review = open.filter { $0.needsReview }
        let today = stubSortedByAnchor(open.filter { $0.kind != .waiting && $0.isDueToday(at: now, calendar: calendar) })
        let followUps = stubSortedByAnchor(open.filter { $0.kind == .waiting && $0.isDueToday(at: now, calendar: calendar) })
        let unscheduled = open.filter { $0.anchorDate == nil }
        return AgendaSnapshot(overdue: overdue, review: review, today: today, followUps: followUps, upcoming: [],
                              upcomingTotal: 0, unscheduled: unscheduled, doneThisWeek: 0)
    }

    /// Query command (02 §10.5.1 scopes + project/person/queryText filters) → spoken + on-screen answer (03 §5.9).
    public static func answer(to command: ParsedCommand, items: [Item], projects: [Project], now: Date,
                              settings: AppSettings, calendar: Calendar) -> SpokenAnswer {
        // WP0 STUB
        if command.scope == .overdue {
            return overdueSpoken(items: items, now: now, settings: settings, calendar: calendar)
        }
        return todaySpoken(items: items, projects: projects, now: now, settings: settings, calendar: calendar)
    }

    public static func todaySpoken(items: [Item], projects: [Project], now: Date, settings: AppSettings,
                                   calendar: Calendar) -> SpokenAnswer {
        // WP0 STUB
        let snap = snapshot(items: items, now: now, settings: settings, calendar: calendar)
        let list = snap.overdue + snap.today + snap.followUps
        let text = list.isEmpty
            ? "Bugün için kayıtlı bir iş yok."
            : "Bugün " + TurkishSpeech.numberWords(list.count) + " iş var."
        return SpokenAnswer(title: "Bugünün ajandası", text: TurkishSpeech.dialogSafe(text), itemIDs: list.map { $0.id })
    }

    public static func overdueSpoken(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> SpokenAnswer {
        // WP0 STUB
        let overdue = snapshot(items: items, now: now, settings: settings, calendar: calendar).overdue
        let text = overdue.isEmpty
            ? "Geciken işin yok."
            : TurkishSpeech.numberWords(overdue.count) + " geciken iş var."
        return SpokenAnswer(title: "Gecikenler", text: TurkishSpeech.dialogSafe(TurkishText.upperFirst(text)),
                            itemIDs: overdue.map { $0.id })
    }

    /// Content projected for the moment the briefing fires (03 §3.9). Body lists up to 3 titles overdue at
    /// `fireDate`: "Geciken: Teklif konusu, Ahmet'i ara +2" (05b B3), then today's count. nil = do not send
    /// (nothing overdue/today and !briefingWhenEmpty).
    public static func briefing(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText? {
        // WP0 STUB
        return nil
    }

    /// 03 §3.10. Candidates as `endOfDayCandidates`; later-today timed items are listed separately
    /// ("Bu akşam: 18:00 Ekmek al") and are NOT moved (05b B6). nil = no candidates → do not send.
    public static func endOfDay(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText? {
        // WP0 STUB
        return nil
    }

    /// Items affected by "Sonraki iş gününe taşı" at `now`: overdue + untimed today + timed today with anchor ≤ now;
    /// open reminder/task/waiting only; excludes notes, events and recurring items (05b B6).
    public static func endOfDayCandidates(items: [Item], now: Date, calendar: Calendar) -> [Item] {
        // WP0 STUB
        return []
    }

    /// Pure move to the next day (the next **workday** when settings.moveSkipsWeekend): timed → same clock time;
    /// untimed → defaultDayTime with hasTime = false; resets nag state; appends history .movedEndOfDay.
    public static func movedToTomorrow(_ item: Item, now: Date, settings: AppSettings, calendar: Calendar) -> Item {
        // WP0 STUB (simplified)
        var moved = item
        let day: Date
        if settings.moveSkipsWeekend {
            day = AsistCalendar.addingWorkdays(1, to: now, workdays: settings.workdays, calendar: calendar)
        } else {
            day = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: now), calendar: calendar)
        }
        let time: ClockTime
        if item.hasTime, let anchor = item.anchorDate {
            time = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(anchor, calendar: calendar))
        } else {
            time = settings.defaultDayTime
        }
        moved.dueDate = AsistCalendar.date(on: day, at: time, calendar: calendar)
        moved.resetNagState()
        moved.updatedAt = now
        moved.appendHistory(.movedEndOfDay, at: now)
        return moved
    }

    /// Human-readable safety copy written next to the backups (05b A1): header "Asist — açık işler (27 Eylül 2026 10:30)",
    /// then open non-note items sorted by anchor (undated last), one per line:
    /// "Salı 29.09 15:00 · Teklif konusu · Ahmet · Arka Cep", overdue lines prefixed "GECİKEN · ". Plain UTF-8, LF.
    public static func openItemsText(items: [Item], projects: [Project], now: Date, calendar: Calendar) -> String {
        // WP0 STUB (titles only)
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let month = TurkishDateFormatter.months[min(11, max(0, (c.month ?? 1) - 1))]
        let header = "Asist — açık işler (" + String(c.day ?? 1) + " " + month + " " + String(c.year ?? 0) + " "
            + TurkishDateFormatter.time(now, calendar: calendar) + ")"
        var lines = [header]
        for item in items where item.isOpen && item.kind != .note {
            lines.append(item.title)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Stub helpers (file-private)

    private static func stubSortedByAnchor(_ items: [Item]) -> [Item] {
        items.sorted { ($0.anchorDate ?? Date.distantFuture) < ($1.anchorDate ?? Date.distantFuture) }
    }
}
