// API: Packages/AsistCore/Sources/AsistCore/Parser/TurkishParser.swift
// WP1 — orchestration of the 02 §2 pipeline (public surface frozen by 04 §3.4.3).
import Foundation

public struct TurkishParser {
    public let settings: ParserSettings
    public let calendar: Calendar

    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = TurkishParser.defaultCalendar()) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Pure: depends only on (text, now, settings, calendar). Never reads Date()/Locale.current/TimeZone.current.
    public func parse(_ text: String, now: Date) -> ParseResult {
        let reference = AsistCalendar.floorToMinute(now)
        let normalized = Normalizer.normalize(text)
        let tokenized = Tokenizer.tokenize(normalized)
        var ctx = ParseContext(tokens: tokenized.tokens, chars: tokenized.chars, normalized: normalized,
                               now: reference, settings: settings, calendar: calendar)
        guard ctx.count > 0 else {
            return emptyResult(originalText: text, normalized: normalized)
        }

        // §7 extraction, fixed order (each step consumes token spans).
        CueExtractor.extractPrefix(&ctx)
        ProjectPlaceExtractor.extractProjects(&ctx)
        TimeExtractor.protectNumbers(&ctx)
        ProjectPlaceExtractor.extractPlaces(&ctx)
        LeadTimeExtractor.extract(&ctx)
        RecurrenceExtractor.extract(&ctx)
        DateExtractor.extractOffsets(&ctx)
        TimeExtractor.extractDayparts(&ctx)
        DateExtractor.extractDates(&ctx)
        TimeExtractor.extractClocks(&ctx)
        TimeExtractor.applyClockRanges(&ctx)
        TimeExtractor.applyClockCorrections(&ctx)
        TimeExtractor.assignQualifiers(&ctx)
        TimeExtractor.extractWrappers(&ctx)
        for j in 0..<ctx.count where ctx.usable(j) && Lexicon.hemenWords.contains(ctx.tokens[j].plain) {
            ctx.hemenIndex = j
            break
        }
        CueExtractor.extractPriority(&ctx)
        let waitingVerbPresent = CueExtractor.finalWaitingVerb(ctx) != nil || CueExtractor.hasBekleVerb(ctx)
        PersonExtractor.extract(&ctx, waitingVerbPresent: waitingVerbPresent)

        // T1 commands (queries first, G6), then the item tiers.
        if ctx.prefixKind == nil, let command = CueExtractor.detectCommand(&ctx) {
            return commandResult(&ctx, command, originalText: text)
        }
        return itemResult(&ctx, originalText: text)
    }

    public static func defaultCalendar() -> Calendar {
        AsistCalendar.make(timeZone: AsistCalendar.istanbul)
    }

    // MARK: - Commands

    private func commandResult(_ ctx: inout ParseContext, _ match: CommandMatch, originalText: String) -> ParseResult {
        ctx.consume(match.cueStart, match.cueEnd)
        var command = match.command
        if command.type != .query {
            command.queryText = TitleBuilder.queryText(ctx, cueStart: match.cueStart, stem: match.stem)
        }
        command.person = ctx.person?.value
        command.project = ctx.project
        for filter in ctx.filterDays {
            let day = calendar.startOfDay(for: filter.day)
            if command.type == .snooze {
                command.targetDate = day
            } else if command.date == nil && (command.type == .complete || command.type == .cancel) {
                command.date = day
            }
        }
        if (command.type == .complete || command.type == .cancel) && command.date == nil, let first = ctx.days.first {
            command.date = calendar.startOfDay(for: first.day)
        }
        var flags = ctx.flags
        if command.type == .snooze {
            if let offset = ctx.offset, !offset.isCalendar {
                command.snoozeMinutes = offset.minutes
                command.date = ctx.now.addingTimeInterval(TimeInterval(offset.minutes * 60))
            } else {
                command.date = DateResolver.resolve(ctx, flags: &flags).due
            }
        }
        var confidence = Confidence.score(certainty: match.certainty, flags: flags, isCommand: true)
        if confidence < settings.smartModeThreshold {
            flags.insert(.smartModeSuggested)
        }
        confidence = (confidence * 100).rounded() / 100
        let understood = TurkishParser.understood(command: command, now: ctx.now, calendar: calendar)
        var relative: String? = nil
        if command.type == .snooze, let date = command.date {
            relative = TurkishDateFormatter.relativePhrase(to: date, now: ctx.now, calendar: calendar)
        }
        return ParseResult(kind: .command, item: nil, command: command, confidence: confidence, flags: flags,
                           understood: understood, relativePhrase: relative, originalText: originalText,
                           normalizedText: ctx.normalized)
    }

    // MARK: - Items

    private func itemResult(_ ctx: inout ParseContext, originalText: String) -> ParseResult {
        let classification = Classifier.classify(&ctx)
        let kind = classification.kind
        var flags = Set<ParseFlag>()
        var resolution = Resolution(due: nil, hasTime: false, recurrence: nil)
        if kind != .note {
            resolution = DateResolver.resolve(ctx, flags: &flags)
        }
        flags.formUnion(ctx.flags)
        if kind == .note {
            // Notes are verbatim (02 §10.2): date words inside them are neither extracted nor judged.
            flags.remove(.vagueDate)
            flags.remove(.correctionApplied)
            flags.remove(.unknownPlace)
        }

        let title: String
        var body: String? = nil
        if kind == .note {
            let noteText = TitleBuilder.noteBody(ctx)
            body = noteText
            if noteText.isEmpty || TitleBuilder.letterCount(noteText) < 2 || isPronounOnlyText(noteText) {
                title = TitleBuilder.fallbackTitle(ctx)
                flags.insert(.titleFallback)
            } else {
                title = TurkishText.upperFirst(TurkishText.truncated(noteText, max: 60))
            }
        } else {
            if let built = TitleBuilder.itemTitle(ctx, kind: kind, verbCue: ctx.verbCue,
                                                  multipleItemsJoiner: classification.multipleItemsJoiner) {
                title = built
            } else if kind == .waiting {
                title = "Dönüş bekleniyor"
            } else if classification.alarmCue {
                title = "Alarm"
            } else {
                title = TitleBuilder.fallbackTitle(ctx)
                flags.insert(.titleFallback)
            }
            if TitleBuilder.hasUnusedNumber(ctx, multipleItemsJoiner: classification.multipleItemsJoiner) {
                flags.insert(.unusedNumber)
            }
        }
        if kind == .reminder && classification.tier == .t5 && resolution.due == nil && ctx.place == nil
            && resolution.recurrence == nil {
            flags.insert(.needsTime)
        }
        if ctx.count < 2 {
            flags.insert(.tooShort)
        }
        if ctx.count > 40 {
            flags.insert(.tooLong)
        }
        let cap: Int? = (ctx.nthWeekdayOrdinal != nil && kind != .note) ? 59 : nil
        var confidence = Confidence.score(certainty: classification.certainty, flags: flags, isCommand: false, capAt: cap)
        if confidence < settings.smartModeThreshold {
            flags.insert(.smartModeSuggested)
        }
        confidence = (confidence * 100).rounded() / 100

        let item = ParsedItem(kind: kind, title: title, body: body, dueDate: resolution.due,
                              hasTime: resolution.hasTime, recurrence: resolution.recurrence, priority: ctx.priority,
                              person: ctx.person?.value, project: ctx.project, place: ctx.place, tags: ctx.tags,
                              leadTimesMinutes: ctx.leads)
        let understood = TurkishParser.understood(item: item, now: ctx.now, calendar: calendar)
        var relative: String? = nil
        if let due = resolution.due {
            relative = TurkishDateFormatter.relativePhrase(to: due, now: ctx.now, calendar: calendar)
        }
        return ParseResult(kind: TurkishParser.parsedKind(kind), item: item, command: nil, confidence: confidence,
                           flags: flags, understood: understood, relativePhrase: relative, originalText: originalText,
                           normalizedText: ctx.normalized)
    }

    private func isPronounOnlyText(_ text: String) -> Bool {
        let words = text.split(separator: " ").map { TurkishText.fold(String($0)) }
        for word in words where !Lexicon.pronouns.contains(word) {
            return false
        }
        return true
    }

    private func emptyResult(originalText: String, normalized: String) -> ParseResult {
        let item = ParsedItem(kind: .note, title: "Not", body: "")
        let flags: Set<ParseFlag> = [.titleFallback, .tooShort, .noKindCue, .smartModeSuggested]
        return ParseResult(kind: .note, item: item, command: nil, confidence: 0, flags: flags,
                           understood: "Not — Not", relativePhrase: nil, originalText: originalText,
                           normalizedText: normalized)
    }

    static func parsedKind(_ kind: ItemKind) -> ParsedKind {
        switch kind {
        case .reminder: return .reminder
        case .task: return .task
        case .note: return .note
        case .waiting: return .waiting
        }
    }

    // MARK: - Understood text (02 §13)

    static func understood(item: ParsedItem, now: Date, calendar: Calendar) -> String {
        let head: String
        if let due = item.dueDate {
            head = TurkishDateFormatter.datePhrase(due, now: now, calendar: calendar) + ", "
                + TurkishDateFormatter.time(due, calendar: calendar) + " — " + item.title
        } else if let place = item.place {
            head = "Konum: " + place.name + " (" + place.trigger.label + ") — " + item.title
        } else if item.kind == .waiting, let person = item.person {
            head = "Bekleniyor (" + person + ") — " + item.title
        } else {
            let label: String
            switch item.kind {
            case .reminder: label = "Hatırlatma"
            case .task: label = "Görev"
            case .note: label = "Not"
            case .waiting: label = "Bekleniyor"
            }
            head = label + " — " + item.title
        }
        var segments: [String] = []
        if let recurrence = item.recurrence {
            segments.append(TurkishDateFormatter.recurrenceText(recurrence))
        }
        // DEVIATION(02 §13): "Kritik" (Priority.label) instead of "Acil" for critical — after C2 "acil" means high.
        switch item.priority {
        case .critical: segments.append("Kritik")
        case .high: segments.append("Önemli")
        case .low: segments.append("Düşük öncelik")
        case .normal: break
        }
        if let person = item.person, !(item.kind == .waiting && item.dueDate == nil && item.place == nil) {
            segments.append("Kişi: " + person)
        }
        if let project = item.project {
            segments.append("Proje: " + project)
        }
        if !item.leadTimesMinutes.isEmpty {
            let leads = item.leadTimesMinutes.map { TurkishDateFormatter.duration(minutes: $0) }
            segments.append("Ön uyarı: " + leads.joined(separator: ", ") + " önce")
        }
        if segments.isEmpty {
            return head
        }
        return head + " · " + segments.joined(separator: " · ")
    }

    static func understood(command: ParsedCommand, now: Date, calendar: Calendar) -> String {
        switch command.type {
        case .query:
            switch command.scope ?? .all {
            case .today: return "Bugünün ajandası"
            case .tomorrow: return "Yarının ajandası"
            case .thisWeek: return "Bu haftanın ajandası"
            case .nextWeek: return "Gelecek haftanın ajandası"
            case .date:
                if let date = command.date {
                    return TurkishDateFormatter.datePhrase(date, now: now, calendar: calendar) + " ajandası"
                }
                return "Tüm açık işler"
            case .overdue: return "Geciken işler"
            case .waiting: return "Beklenenler"
            case .notes: return "Notlar"
            case .tasks: return "Görevler"
            case .all: return "Tüm açık işler"
            }
        case .complete:
            return "Tamamlanacak: " + (command.queryText ?? "son hatırlatma")
        case .cancel:
            return "İptal edilecek: " + (command.queryText ?? "son hatırlatma")
        case .snooze:
            var text = "Ertelenecek: " + (command.queryText ?? "son hatırlatma")
            if let date = command.date {
                text += " → " + TurkishDateFormatter.datePhrase(date, now: now, calendar: calendar) + ", "
                    + TurkishDateFormatter.time(date, calendar: calendar)
            }
            return text
        }
    }
}
