// API: Packages/AsistCore/Sources/AsistCore/Capture/ItemFactory.swift
// WP0 STUB (04 §3.5.6) — WP2 replaces this file (rules R1–R12). Simplified R1/R3/R5–R9/R11/R12; no alternatives.
import Foundation

public enum ConfirmationLevel: String, Equatable {
    case autoSave     // confidence ≥ 0.80 → countdown settings.autoSaveSeconds (4 s)
    case confirm      // 0.60 ..< 0.80   → countdown 6 s, uncertain fields marked "?"
    case review       // < 0.60 or pastDue/conflictingDates/needs-time → no auto-save
}

public struct CaptureContext: Equatable {
    public var settings: AppSettings
    public var projects: [Project]
    public var places: [Place]
    public var forcedKind: ItemKind?        // "asist://dinle?tur=not", "Bu projeye sesli not"
    public var forcedProjectID: UUID?       // project detail voice note
    public var interactive: Bool            // true = app UI (card can ask); false = Siri/Shortcut

    public init(settings: AppSettings, projects: [Project], places: [Place], forcedKind: ItemKind? = nil,
                forcedProjectID: UUID? = nil, interactive: Bool) {
        self.settings = settings
        self.projects = projects
        self.places = places
        self.forcedKind = forcedKind
        self.forcedProjectID = forcedProjectID
        self.interactive = interactive
    }
}

public struct CaptureProposal: Equatable {
    public var item: Item
    public var level: ConfirmationLevel
    /// Reminder without any time and interactive && noTimeBehavior == .ask → card shows "Ne zaman?".
    public var needsTime: Bool
    /// A default time/offset was applied that the user did not say (D20 headless +1 h, D21 waiting default).
    public var appliedDefaultTime: Bool
    /// D33: an undated task was put on today (or tomorrow after workEnd), untimed → card chips Bugün / Yarın / Zamanı belirsiz.
    public var defaultedToToday: Bool
    /// Alternative instants: ambiguous hours (21:00 chosen → [tomorrow 09:00]; 15:00 → [03:00 next]),
    /// `.nextWeekAmbiguous` → [due + 7 days] (P2), bare weekday = today → [today same time if still ahead] (P3).
    public var alternativeTimes: [Date]

    public init(item: Item, level: ConfirmationLevel, needsTime: Bool, appliedDefaultTime: Bool,
                defaultedToToday: Bool, alternativeTimes: [Date]) {
        self.item = item
        self.level = level
        self.needsTime = needsTime
        self.appliedDefaultTime = appliedDefaultTime
        self.defaultedToToday = defaultedToToday
        self.alternativeTimes = alternativeTimes
    }
}

public enum ItemFactory {
    /// Folded event head nouns (possessive -ı/-i/-u/-ü/-sı/-si/-su/-sü accepted): toplanti, gorusme, randevu, ziyaret,
    /// sunum, egitim, denetim, fat, sat, mulakat, ucus, yemek, mac, webinar, kickoff, acilis, toren, fuar, konferans.
    public static let eventNouns: [String] = [
        "toplanti", "gorusme", "randevu", "ziyaret", "sunum", "egitim", "denetim", "fat", "sat", "mulakat",
        "ucus", "yemek", "mac", "webinar", "kickoff", "acilis", "toren", "fuar", "konferans"
    ]

    /// true when the last content word of `title` — ignoring trailing "var", "var mı", "olacak", "yapılacak",
    /// "başlıyor", "başlayacak" — is an event noun. "ABB ile toplantı var" → true; "toplantı notlarını gönder" → false.
    public static func isEventTitle(_ title: String) -> Bool {
        var words = TurkishText.searchKey(title).split(separator: " ").map { String($0) }
        let ignoredTrailing: Set<String> = ["var", "mi", "olacak", "yapilacak", "basliyor", "baslayacak"]
        while let last = words.last, ignoredTrailing.contains(last) {
            words.removeLast()
        }
        guard let last = words.last else { return false }
        for noun in eventNouns {
            if last == noun { return true }
            for suffix in ["i", "u", "si", "su"] where last == noun + suffix {
                return true
            }
        }
        return false
    }

    /// nil when result.kind == .command. Rules R1–R12 below.
    public static func proposal(from result: ParseResult, source: CaptureSource, context: CaptureContext,
                                now: Date, calendar: Calendar) -> CaptureProposal? {
        // WP0 STUB (simplified R1–R12).
        guard result.kind != .command else { return nil }
        let settings = context.settings
        let fallbackTitle = result.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = result.item ?? ParsedItem(kind: .task, title: fallbackTitle.isEmpty ? "Kayıt" : fallbackTitle)

        // R1 kind (+ T10 fallback note → task).
        var kind = context.forcedKind ?? parsed.kind
        var fallbackApplied = false
        if context.forcedKind == nil && parsed.kind == .note && result.flags.contains(.noKindCue) {
            kind = .task
            fallbackApplied = true
        }
        var confirmationLevel = ItemFactory.level(for: result)
        if fallbackApplied && confirmationLevel == .autoSave {
            confirmationLevel = .confirm
        }

        // R2 project (folded match over allNames), else forced/active project.
        var projectID: UUID? = nil
        if let name = parsed.project {
            let key = TurkishText.fold(name)
            projectID = context.projects.first(where: { project in
                project.allNames.contains(where: { TurkishText.fold($0) == key })
            })?.id
        }
        if projectID == nil {
            projectID = context.forcedProjectID ?? settings.activeProjectID
        }

        // R4 copy.
        let trimmedTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = Item(kind: kind,
                        title: trimmedTitle.isEmpty ? "Kayıt" : trimmedTitle,
                        notes: parsed.body ?? "",
                        originalText: result.originalText,
                        priority: parsed.priority,
                        dueDate: parsed.dueDate,
                        hasTime: parsed.hasTime,
                        recurrence: parsed.recurrence,
                        leadTimesMinutes: parsed.leadTimesMinutes,
                        person: parsed.person,
                        projectID: projectID,
                        tags: parsed.tags,
                        source: source,
                        parseConfidence: result.confidence,
                        createdAt: now,
                        history: [HistoryEntry(date: now, event: .created)])

        // R3 place → notes line (no geofences in v1.0).
        if let place = parsed.place {
            let line = "Yer: " + place.name + " (" + place.trigger.label + ")"
            item.notes = item.notes.isEmpty ? line : item.notes + "\n" + line
        }

        var needsTime = false
        var appliedDefaultTime = false
        var defaultedToToday = false

        // R5 urgent task without date → reminder.
        if item.kind == .task && item.dueDate == nil && item.priority >= .high {
            item.kind = .reminder
        }
        // R6 reminder without due.
        if item.kind == .reminder && item.dueDate == nil {
            if context.interactive && settings.noTimeBehavior == .ask {
                needsTime = true
                confirmationLevel = .review
            } else {
                item.dueDate = noTimeDefault(settings.noTimeBehavior, now: now, settings: settings, calendar: calendar)
                item.hasTime = true
                appliedDefaultTime = true
            }
        }
        // R7 task without due → today policy, untimed.
        let capturingSources: [CaptureSource] = [.voice, .keyboard, .siri, .shortcut]
        if item.kind == .task && item.dueDate == nil && capturingSources.contains(source) {
            item.dueDate = stubTodayPolicy(now: now, settings: settings, calendar: calendar)
            item.hasTime = false
            defaultedToToday = true
        }
        // R8 waiting without due.
        if item.kind == .waiting && item.dueDate == nil {
            item.dueDate = defaultWaitingDue(now: now, settings: settings, calendar: calendar)
            item.hasTime = false
            appliedDefaultTime = true
        }
        // R9 events.
        if item.hasTime && (item.kind == .reminder || item.kind == .task) && isEventTitle(item.title) {
            item.kind = .reminder
            item.isEvent = true
            if item.leadTimesMinutes.isEmpty && settings.eventDefaultLeadMinutes > 0 {
                item.leadTimesMinutes = [settings.eventDefaultLeadMinutes]
            }
        }
        // R12 needsReview.
        item.needsReview = !context.interactive && (confirmationLevel == .review || fallbackApplied)

        return CaptureProposal(item: item, level: confirmationLevel, needsTime: needsTime,
                               appliedDefaultTime: appliedDefaultTime, defaultedToToday: defaultedToToday,
                               alternativeTimes: [])
    }

    public static func level(for result: ParseResult) -> ConfirmationLevel {
        if result.flags.contains(.pastDue) || result.flags.contains(.conflictingDates) || result.flags.contains(.needsTime) {
            return .review
        }
        if result.confidence >= 0.80 {
            return result.flags.contains(.nextWeekAmbiguous) ? .confirm : .autoSave
        }
        if result.confidence >= 0.60 {
            return .confirm
        }
        return .review
    }

    /// D20 resolution: .inOneHour → ceilToMinute(now + 60 min); .thisEvening → today aksam (or +1 h if passed);
    /// .tomorrowMorning → NagPlanner.tomorrowMorning; .ask → same as .inOneHour.
    public static func noTimeDefault(_ behavior: NoTimeBehavior, now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let inOneHour = AsistCalendar.ceilToMinute(now.addingTimeInterval(3600))
        switch behavior {
        case .ask, .inOneHour:
            return inOneHour
        case .thisEvening:
            let evening = AsistCalendar.date(on: now, at: settings.aksam, calendar: calendar)
            return evening > now ? evening : inOneHour
        case .tomorrowMorning:
            return NagPlanner.tomorrowMorning(after: now, settings: settings, calendar: calendar)
        }
    }

    /// D21: +waitingDefaultWorkdays workdays at waitingDefaultTime (item.hasTime = false).
    public static func defaultWaitingDue(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let day = AsistCalendar.addingWorkdays(max(1, settings.waitingDefaultWorkdays), to: now,
                                               workdays: settings.workdays, calendar: calendar)
        return AsistCalendar.date(on: day, at: settings.waitingDefaultTime, calendar: calendar)
    }

    // MARK: - Stub helpers (file-private)

    /// 02 §8.2a today policy (simplified): today at defaultDayTime if ≥ now + 15 min, else now + 30 min rounded up
    /// to the next full hour; tomorrow at defaultDayTime after workEnd or when the result would cross midnight.
    private static func stubTodayPolicy(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let tomorrowDay = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: now), calendar: calendar)
        let tomorrow = AsistCalendar.date(on: tomorrowDay, at: settings.defaultDayTime, calendar: calendar)
        if AsistCalendar.minuteOfDay(now, calendar: calendar) >= settings.workEnd.minutesOfDay {
            return tomorrow
        }
        let todayDefault = AsistCalendar.date(on: now, at: settings.defaultDayTime, calendar: calendar)
        if todayDefault >= now.addingTimeInterval(15 * 60) {
            return todayDefault
        }
        let later = now.addingTimeInterval(30 * 60)
        let hour = calendar.component(.hour, from: later)
        var candidate = AsistCalendar.date(on: later, at: ClockTime(hour, 0), calendar: calendar)
        if candidate < later {
            candidate = candidate.addingTimeInterval(3600)
        }
        if !calendar.isDate(candidate, inSameDayAs: now) {
            return tomorrow
        }
        return candidate
    }
}
