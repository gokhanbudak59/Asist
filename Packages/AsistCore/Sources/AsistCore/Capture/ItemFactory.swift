// API: Packages/AsistCore/Sources/AsistCore/Capture/ItemFactory.swift
// WP2 (04 §3.5.6 rules R1–R12; D10, D20, D21, D31, D33; 05b P2–P4).
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

    /// Trailing words ignored by `isEventTitle` ("var", "var mı", "olacak", "yapılacak", "başlıyor", "başlayacak").
    private static let eventTrailingWords: Set<String> = ["var", "mi", "olacak", "yapilacak", "basliyor", "baslayacak"]

    /// Possessive endings accepted after an event noun (folded: ı→i, ü→u).
    private static let eventPossessives: [String] = ["", "i", "u", "si", "su"]

    /// Sources that capture new work from the user's own words (R7 today policy applies).
    private static let capturingSources: Set<CaptureSource> = [.voice, .keyboard, .siri, .shortcut]

    /// true when the last content word of `title` — ignoring trailing "var", "var mı", "olacak", "yapılacak",
    /// "başlıyor", "başlayacak" — is an event noun. "ABB ile toplantı var" → true; "toplantı notlarını gönder" → false.
    public static func isEventTitle(_ title: String) -> Bool {
        // Original-case words (the apostrophe part is dropped: "SAT'ı" → "SAT") so that the verb "sat" (sell)
        // is not mistaken for the acronym SAT.
        var originalWords: [String] = []
        for raw in title.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            var word = String(raw)
            if let index = word.firstIndex(where: { $0 == "'" || $0 == "’" || $0 == "‘" }) {
                word = String(word[word.startIndex..<index])
            }
            let key = TurkishText.searchKey(word)
            if !key.isEmpty {
                originalWords.append(word)
            }
        }
        while let last = originalWords.last, eventTrailingWords.contains(TurkishText.searchKey(last)) {
            originalWords.removeLast()
        }
        guard let lastOriginal = originalWords.last else { return false }
        let last = TurkishText.searchKey(lastOriginal).replacingOccurrences(of: " ", with: "")
        for noun in eventNouns {
            for suffix in eventPossessives where last == noun + suffix {
                if noun == "sat" {
                    // "SAT", "SAT'ı" (acronym, upper case) — never the lowercase verb "sat".
                    let letters = lastOriginal.filter { $0.isLetter }
                    return letters.count >= 3 && TurkishText.upper(letters) == letters
                }
                return true
            }
        }
        return false
    }

    /// nil when result.kind == .command. Rules R1–R12 below.
    public static func proposal(from result: ParseResult, source: CaptureSource, context: CaptureContext,
                                now: Date, calendar: Calendar) -> CaptureProposal? {
        guard result.kind != .command else { return nil }
        let settings = context.settings
        let original = result.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: ParsedItem
        if let item = result.item {
            parsed = item
        } else {
            parsed = ParsedItem(kind: .task, title: original)
        }

        // R1 kind (+ 02 T10 fallback note → task, D33).
        var kind = context.forcedKind ?? parsed.kind
        var fallbackApplied = false
        if context.forcedKind == nil && parsed.kind == .note && result.flags.contains(.noKindCue) {
            kind = .task
            fallbackApplied = true
        }

        // R11 level (D10) — capped below.
        var confirmationLevel = level(for: result)
        if fallbackApplied && confirmationLevel == .autoSave {
            confirmationLevel = .confirm
        }

        // R2 project: parser name → Project (folded over allNames, active projects first), else forced, else active.
        var projectID: UUID? = nil
        if let name = parsed.project {
            projectID = matchProject(named: name, in: context.projects)
        }
        if projectID == nil {
            projectID = context.forcedProjectID ?? settings.activeProjectID
        }

        // R4 copy.
        var dueDate = parsed.dueDate.map { AsistCalendar.floorToMinute($0) }
        var hasTime = dueDate == nil ? false : parsed.hasTime
        var recurrence = parsed.recurrence
        var leads = sanitizedLeads(parsed.leadTimesMinutes)
        var title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = parsed.body ?? ""

        // Notes (forced or parsed) never carry scheduling data (notes are never notified).
        if kind == .note {
            if parsed.kind != .note {
                // Forced note over a non-note parse: keep the user's words verbatim (02 §11.4).
                let verbatim = original.isEmpty ? title : original
                notes = verbatim
                title = TurkishText.upperFirst(TurkishText.truncated(verbatim, max: 60))
            }
            dueDate = nil
            hasTime = false
            recurrence = nil
            leads = []
        }
        if title.isEmpty {
            title = defaultTitle(for: kind)
        }
        if kind != .note && notes.trimmingCharacters(in: .whitespacesAndNewlines) == title {
            notes = ""      // T10 fallback note → task: the body only repeats the title
        }
        let person = parsed.person.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var item = Item(kind: kind,
                        title: title,
                        notes: notes,
                        originalText: result.originalText,
                        priority: parsed.priority,
                        dueDate: dueDate,
                        hasTime: hasTime,
                        recurrence: recurrence,
                        leadTimesMinutes: leads,
                        person: person,
                        projectID: projectID,
                        tags: parsed.tags,
                        source: source,
                        parseConfidence: result.confidence,
                        createdAt: now,
                        history: [HistoryEntry(date: now, event: .created)])

        // R3 place → notes line (no geofences in v1.0).
        if let place = parsed.place, kind != .note {
            let line = "Yer: " + place.name + " (" + place.trigger.label + ")"
            item.notes = item.notes.isEmpty ? line : item.notes + "\n" + line
        }

        var needsTime = false
        var appliedDefaultTime = false
        var defaultedToToday = false

        // R5 urgent task without date (P4) → reminder; R6 applies.
        if item.kind == .task && item.dueDate == nil && item.priority >= .high {
            item.kind = .reminder
        }
        // R6 reminder without due (D20).
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
        // R7 task without due (D33): today policy, untimed.
        if item.kind == .task && item.dueDate == nil && capturingSources.contains(source) {
            item.dueDate = todayPolicy(now: now, settings: settings, calendar: calendar)
            item.hasTime = false
            defaultedToToday = true
        }
        // R8 waiting without due (D21).
        if item.kind == .waiting {
            if item.dueDate == nil {
                item.dueDate = defaultWaitingDue(now: now, settings: settings, calendar: calendar)
                item.hasTime = false
                appliedDefaultTime = true
            } else if !item.hasTime, let due = item.dueDate, item.recurrence == nil {
                // DEVIATION(04 §3.5.6 R4): a spoken deadline day without a time ("cuma gününe kadar gönderecek") is
                // asked at settings.followUpAskTime on that day (03 §5.8 #7) and counts as a spoken deadline
                // (hasTime = true) so the copy says "Son tarih: Cuma" (05b F8), never "n gündür bekliyor".
                var ask = AsistCalendar.date(on: due, at: settings.followUpAskTime, calendar: calendar)
                if ask <= now {
                    ask = AsistCalendar.ceilToMinute(now.addingTimeInterval(3600))
                }
                item.dueDate = ask
                item.hasTime = true
            }
        }
        // R9 events (D31).
        let eventCandidate = item.kind == .reminder || item.kind == .task
        if eventCandidate && item.hasTime && item.dueDate != nil && isEventTitle(item.title) {
            item.kind = .reminder
            item.isEvent = true
            if item.leadTimesMinutes.isEmpty && settings.eventDefaultLeadMinutes > 0 {
                item.leadTimesMinutes = [settings.eventDefaultLeadMinutes]
            }
        }

        // R10 alternatives.
        let alternatives = alternativeTimes(for: item, result: result, now: now, calendar: calendar)

        // R12 needsReview.
        item.needsReview = !context.interactive && (confirmationLevel == .review || fallbackApplied)

        return CaptureProposal(item: item, level: confirmationLevel, needsTime: needsTime,
                               appliedDefaultTime: appliedDefaultTime, defaultedToToday: defaultedToToday,
                               alternativeTimes: alternatives)
    }

    public static func level(for result: ParseResult) -> ConfirmationLevel {
        let flags = result.flags
        if flags.contains(.pastDue) || flags.contains(.conflictingDates) || flags.contains(.needsTime) {
            return .review
        }
        if result.confidence >= 0.80 {
            return flags.contains(.nextWeekAmbiguous) ? .confirm : .autoSave
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
            let morning = NagPlanner.tomorrowMorning(after: now, settings: settings, calendar: calendar)
            return morning > now ? morning : inOneHour
        }
    }

    /// D21: +waitingDefaultWorkdays workdays at waitingDefaultTime (item.hasTime = false).
    public static func defaultWaitingDue(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let day = AsistCalendar.addingWorkdays(max(1, settings.waitingDefaultWorkdays), to: now,
                                               workdays: settings.workdays, calendar: calendar)
        return AsistCalendar.date(on: day, at: settings.waitingDefaultTime, calendar: calendar)
    }

    /// R7 / 02 §8.2a today policy: today at `defaultDayTime` if that is ≥ now + 15 min, else now + 30 min rounded up
    /// to the next full hour; the next day at `defaultDayTime` when now ≥ workEnd or the result would cross midnight.
    public static func todayPolicy(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowDay = AsistCalendar.addingDays(1, to: todayStart, calendar: calendar)
        let tomorrow = AsistCalendar.date(on: tomorrowDay, at: settings.defaultDayTime, calendar: calendar)
        if AsistCalendar.minuteOfDay(now, calendar: calendar) >= settings.workEnd.minutesOfDay {
            return tomorrow
        }
        let todayDefault = AsistCalendar.date(on: now, at: settings.defaultDayTime, calendar: calendar)
        if todayDefault >= now.addingTimeInterval(15 * 60) {
            return todayDefault
        }
        let later = now.addingTimeInterval(30 * 60)
        guard calendar.isDate(later, inSameDayAs: now) else { return tomorrow }
        let hour = calendar.component(.hour, from: later)
        var candidate = AsistCalendar.date(on: later, at: ClockTime(hour, 0), calendar: calendar)
        if candidate < later {
            candidate = calendar.date(byAdding: .hour, value: 1, to: candidate) ?? candidate.addingTimeInterval(3600)
        }
        if !calendar.isDate(candidate, inSameDayAs: now) {
            return tomorrow
        }
        return candidate
    }

    // MARK: - Private helpers

    private static func defaultTitle(for kind: ItemKind) -> String {
        switch kind {
        case .reminder: return "Hatırlatma"
        case .task: return "Görev"
        case .note: return "Not"
        case .waiting: return "Dönüş bekleniyor"
        }
    }

    /// Positive, ≤ 366 days, unique, sorted (same clamp as `Item` decoding).
    private static func sanitizedLeads(_ leads: [Int]) -> [Int] {
        Array(Set(leads.filter { $0 > 0 && $0 <= 527_040 })).sorted()
    }

    /// Folded (searchKey) match over `allNames`; non-archived projects win over archived ones.
    private static func matchProject(named name: String, in projects: [Project]) -> UUID? {
        let key = TurkishText.searchKey(name)
        guard !key.isEmpty else { return nil }
        var archivedMatch: UUID? = nil
        for project in projects where project.allNames.contains(where: { TurkishText.searchKey($0) == key }) {
            if !project.archived {
                return project.id
            }
            if archivedMatch == nil {
                archivedMatch = project.id
            }
        }
        return archivedMatch
    }

    /// R10: ambiguous hours, P2 "+7 gün", P3 "Bugün". Sorted, unique, never equal to the due date, never in the past.
    private static func alternativeTimes(for item: Item, result: ParseResult, now: Date, calendar: Calendar) -> [Date] {
        guard item.kind != .note, let due = item.dueDate else { return [] }
        var candidates: [Date] = []
        let flags = result.flags
        let clock = calendar.dateComponents([.hour, .minute], from: due)
        let hour = clock.hour ?? 0
        let minute = clock.minute ?? 0

        if item.hasTime && flags.contains(.ambiguousHourNearest) {
            // Nearest-future reading was chosen; offer the other 12-hour reading at its next occurrence.
            let other = ClockTime((hour + 12) % 24, minute)
            var candidate = AsistCalendar.date(on: now, at: other, calendar: calendar)
            if candidate <= now {
                candidate = AsistCalendar.date(on: AsistCalendar.addingDays(1, to: now, calendar: calendar),
                                               at: other, calendar: calendar)
            }
            candidates.append(candidate)
        } else if item.hasTime && flags.contains(.ambiguousHourPM) {
            // Day was specified and 1–6 became 13–18: offer the morning reading on the same day.
            let other = ClockTime((hour + 12) % 24, minute)
            candidates.append(AsistCalendar.date(on: due, at: other, calendar: calendar))
        }
        if flags.contains(.nextWeekAmbiguous) {
            candidates.append(AsistCalendar.addingDays(7, to: due, calendar: calendar))
        }
        if isBareSameWeekday(due: due, originalText: result.originalText, now: now, calendar: calendar) {
            let todayCandidate = AsistCalendar.date(on: now, at: ClockTime(hour, minute), calendar: calendar)
            if todayCandidate > now {
                candidates.append(todayCandidate)
            }
        }
        var seen = Set<Date>()
        var out: [Date] = []
        for date in candidates.sorted() where date > now && date != due && !seen.contains(date) {
            seen.insert(date)
            out.append(date)
        }
        return out
    }

    /// P3: the due date is exactly 7 days ahead on today's weekday and the utterance named that weekday without a
    /// "next week" word ("salı" said on a Tuesday).
    private static func isBareSameWeekday(due: Date, originalText: String, now: Date, calendar: Calendar) -> Bool {
        guard TurkishSpeech.dayOffset(from: now, to: due, calendar: calendar) == 7 else { return false }
        let iso = AsistCalendar.isoWeekday(now, calendar: calendar)
        let weekdayKey = TurkishText.searchKey(TurkishDateFormatter.weekdays[min(6, max(0, iso - 1))])
        let words = TurkishText.searchKey(originalText).split(separator: " ").map { String($0) }
        let nextWeekWords: Set<String> = ["haftaya", "gelecek", "onumuzdeki", "sonraki", "hafta", "haftaki", "ertesi"]
        var namedWeekday = false
        for word in words {
            if nextWeekWords.contains(word) {
                return false
            }
            guard word.hasPrefix(weekdayKey) else { continue }
            // "pazar" must not match "pazartesi"; allow short case/possessive endings ("salıya", "cuma günü").
            if weekdayKey == "pazar" && word.hasPrefix("pazartesi") {
                continue
            }
            if word.count - weekdayKey.count <= 4 {
                namedWeekday = true
            }
        }
        return namedWeekday
    }
}
