// FILE: Packages/AsistCore/Sources/AsistCore/Parser/ParserTypes.swift
import Foundation

public enum ParsedKind: String, Codable, CaseIterable {
    case reminder, task, note, waiting, command
}

public struct PlaceRef: Equatable, Codable {
    public var name: String            // canonical spelling from ParserSettings.knownPlaces
    public var trigger: PlaceTrigger
    public init(name: String, trigger: PlaceTrigger) { self.name = name; self.trigger = trigger }
}

public enum CommandType: String, Codable {
    case query, complete, cancel, snooze
}

public enum QueryScope: String, Codable {
    case today, tomorrow, thisWeek, nextWeek, date, overdue, waiting, notes, tasks, all
}

public struct ParsedCommand: Equatable {
    public var type: CommandType
    public var scope: QueryScope?
    /// complete/cancel: day filter; snooze: the NEW date/time; query `.date` scope: the day.
    public var date: Date?
    public var queryText: String?
    public var snoozeMinutes: Int?
    public var project: String?
    public var person: String?
    /// snooze only (G3): day filter of the item to move ("cuma günkü toplantıyı pazartesiye ertele" → cuma).
    public var targetDate: Date?
    public init(type: CommandType, scope: QueryScope? = nil, date: Date? = nil, queryText: String? = nil,
                snoozeMinutes: Int? = nil, project: String? = nil, person: String? = nil, targetDate: Date? = nil) {
        self.type = type; self.scope = scope; self.date = date; self.queryText = queryText
        self.snoozeMinutes = snoozeMinutes; self.project = project; self.person = person
        self.targetDate = targetDate
    }
}

public struct ParsedItem: Equatable {
    public var kind: ItemKind
    public var title: String
    public var body: String?
    public var dueDate: Date?
    public var hasTime: Bool
    public var recurrence: Recurrence?
    public var priority: Priority
    public var person: String?
    public var project: String?
    public var place: PlaceRef?
    public var tags: [String]
    /// G10: spoken pre-alerts ("yarım saat önce hatırlat" → [30], "bir hafta önce" → [10080]); sorted, unique.
    public var leadTimesMinutes: [Int]
    public init(kind: ItemKind, title: String, body: String? = nil, dueDate: Date? = nil, hasTime: Bool = false,
                recurrence: Recurrence? = nil, priority: Priority = .normal, person: String? = nil,
                project: String? = nil, place: PlaceRef? = nil, tags: [String] = [], leadTimesMinutes: [Int] = []) {
        self.kind = kind; self.title = title; self.body = body; self.dueDate = dueDate; self.hasTime = hasTime
        self.recurrence = recurrence; self.priority = priority; self.person = person; self.project = project
        self.place = place; self.tags = tags; self.leadTimesMinutes = leadTimesMinutes
    }
}

public enum ParseFlag: String, Codable, Hashable, CaseIterable {
    case ambiguousHourPM, ambiguousHourNearest, ambiguousDotted, rolledToTomorrow, rolledToNextYear
    case defaultTimeApplied, pastDue, conflictingDates, invalidDateTime, needsTime, unsupportedRecurrence
    case multipleItems, unknownPlace, uncertainPerson, negation, titleFallback, vagueDate, noKindCue
    case tooShort, tooLong, unusedNumber, smartModeSuggested
    /// P2: "haftaya salı" said on Saturday/Sunday (2 or 9 days?) — confidence < 0.80, card offers "+7 gün".
    case nextWeekAmbiguous
    /// G8: a self-correction ("3'te hayır 4'te") replaced an earlier value.
    case correctionApplied
}

public struct ParseResult: Equatable {
    public var kind: ParsedKind
    public var item: ParsedItem?
    public var command: ParsedCommand?
    public var confidence: Double
    public var flags: Set<ParseFlag>
    public var understood: String
    public var relativePhrase: String?
    public var originalText: String
    public var normalizedText: String
    public init(kind: ParsedKind, item: ParsedItem?, command: ParsedCommand?, confidence: Double,
                flags: Set<ParseFlag>, understood: String, relativePhrase: String?, originalText: String,
                normalizedText: String) {
        self.kind = kind; self.item = item; self.command = command; self.confidence = confidence
        self.flags = flags; self.understood = understood; self.relativePhrase = relativePhrase
        self.originalText = originalText; self.normalizedText = normalizedText
    }
}

public struct ParserSettings: Equatable {
    public var defaultDayTime = ClockTime(9, 0)
    public var sabah = ClockTime(9, 0)
    public var ogledenOnce = ClockTime(11, 0)
    public var ogle = ClockTime(12, 0)
    public var ogledenSonra = ClockTime(14, 0)
    public var aksamustu = ClockTime(17, 0)
    public var aksam = ClockTime(19, 0)
    public var gece = ClockTime(22, 0)
    public var mesaiBasi = ClockTime(8, 30)
    public var mesaiBitimi = ClockTime(17, 30)
    public var birazdanMinutes = 15
    /// G9: "hemen / şimdi / derhal / acilen" without another time → now + hemenMinutes.
    public var hemenMinutes = 5
    public var belirsizSaatlerOgledenSonra = true
    public var knownProjects: [String] = []
    public var knownPlaces: [String] = []
    public var knownPeople: [String] = []
    public var smartModeThreshold = 0.60
    public var autoSaveThreshold = 0.80
    public init() {}
}
