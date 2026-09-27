// Internal parse state shared by the extractors (02 §2: every extractor CONSUMES token spans).
import Foundation

enum DayScope: Equatable {
    case today, tomorrow, thisWeek, nextWeek, date
}

enum DaypartQualifier: Equatable {
    case am, noon, pm, evening, night
}

enum SuffixClass: Equatable {
    case bare, ablative, dative, accusative, genitive, instrumental, locative
}

/// One resolved day expression (02 §8.3), `day` = start of that day.
struct DayHit {
    var day: Date
    var start: Int
    var end: Int
    var flags: Set<ParseFlag> = []
    var explicitToday = false
    var scope: DayScope = .date
    /// "yarınki", "cuma günkü": a filter of an existing item, never the new date (G3).
    var isFilter = false
    /// Dotted "15.10" read as a date without a confirming word (§8.6 → ambiguousDotted unless a clock exists).
    var dottedCandidate = false
    /// The phrase ends in a dative ("cumaya", "yarına") — G3 "DATE+DAT bırak/al/taşı".
    var endsWithDative = false

    init(day: Date, start: Int, end: Int, scope: DayScope = .date) {
        self.day = day
        self.start = start
        self.end = end
        self.scope = scope
    }
}

struct ClockHit {
    var hour: Int
    var minute: Int
    var start: Int
    var end: Int
    var leadingZero = false
    var qualifier: DaypartQualifier? = nil
    var endsWithDative = false

    init(hour: Int, minute: Int, start: Int, end: Int) {
        self.hour = hour
        self.minute = minute
        self.start = start
        self.end = end
    }
}

struct DaypartHit {
    var time: ClockTime
    var qualifier: DaypartQualifier?
    var start: Int
    var end: Int
    /// "bu sabah", "bu akşam" — the day is today and is never rolled.
    var explicitToday = false
    /// "gece yarısı" — 00:00 of the following day.
    var nextDay = false
    var endsWithDative = false
}

struct OffsetHit {
    var start: Int
    var end: Int
    var minutes = 0
    var days = 0
    var months = 0
    var years = 0
    var isCalendar = false
    var endsWithSonra = false

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

struct RecurrenceSpec {
    var frequency: Recurrence.Frequency
    var interval = 1
    var weekdays: [Int]? = nil
    var monthDay: Int? = nil
    var month: Int? = nil
    /// G12 "her N ayda bir": the first occurrence is today + N months.
    var anchorToday = false

    init(frequency: Recurrence.Frequency, interval: Int = 1, weekdays: [Int]? = nil, monthDay: Int? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthDay = monthDay
    }
}

struct PersonHit {
    var value: String
    var start: Int
    var end: Int
    var suffixClass: SuffixClass
    var rule: String
}

struct ParseContext {
    let tokens: [Token]
    let chars: [Character]
    let normalized: String
    let now: Date
    let today: Date
    let settings: ParserSettings
    let calendar: Calendar

    var consumed: [Bool]
    /// Kept in the title but never read as a date/number/person (projects, equipment numbers, units, invalid dates).
    var protected: [Bool]
    var projectToken: [Bool]
    var invalidToken: [Bool]
    var flags: Set<ParseFlag> = []

    var prefixKind: ItemKind? = nil
    var tags: [String] = []
    var project: String? = nil
    var explicitTaskPhrase = false
    var place: PlaceRef? = nil
    var leads: [Int] = []
    var leadCue = false
    var recurrenceSpecs: [RecurrenceSpec] = []
    var unsupportedRecurrence = false
    var nthWeekdayOrdinal: Int? = nil
    var nthWeekdayDay: Int? = nil
    var yearlyAuto = false
    var offset: OffsetHit? = nil
    var days: [DayHit] = []
    var filterDays: [DayHit] = []
    var clocks: [ClockHit] = []
    var dayparts: [DaypartHit] = []
    var nightAnywhere = false
    var hemenIndex: Int? = nil
    var priority: Priority = .normal
    var priorityCue = false
    var priorityTokens: Set<Int> = []
    var person: PersonHit? = nil
    var verbCue = false
    var modalityIndices: [Int] = []

    init(tokens: [Token], chars: [Character], normalized: String, now: Date, settings: ParserSettings,
         calendar: Calendar) {
        self.tokens = tokens
        self.chars = chars
        self.normalized = normalized
        self.now = now
        self.today = calendar.startOfDay(for: now)
        self.settings = settings
        self.calendar = calendar
        let count = tokens.count
        consumed = Array(repeating: false, count: count)
        protected = Array(repeating: false, count: count)
        projectToken = Array(repeating: false, count: count)
        invalidToken = Array(repeating: false, count: count)
    }

    var count: Int { tokens.count }

    /// Not consumed and not protected.
    func usable(_ j: Int) -> Bool {
        return j >= 0 && j < tokens.count && !consumed[j] && !protected[j]
    }

    /// Not consumed (protected tokens allowed).
    func free(_ j: Int) -> Bool {
        return j >= 0 && j < tokens.count && !consumed[j]
    }

    mutating func consume(_ a: Int, _ b: Int) {
        guard a <= b else { return }
        for k in a...b where k >= 0 && k < tokens.count {
            consumed[k] = true
        }
    }

    mutating func protect(_ a: Int, _ b: Int, invalid: Bool = false) {
        guard a <= b else { return }
        for k in a...b where k >= 0 && k < tokens.count {
            protected[k] = true
            if invalid {
                invalidToken[k] = true
            }
        }
    }

    func plain(_ j: Int) -> String {
        return j >= 0 && j < tokens.count ? tokens[j].plain : ""
    }

    /// Plain word of a usable token, "" otherwise.
    func usablePlain(_ j: Int) -> String {
        return usable(j) ? tokens[j].plain : ""
    }

    /// Consecutive usable tokens equal to `words` starting at `i` → index of the last one, or -1.
    func matchSequence(_ i: Int, _ words: [String]) -> Int {
        guard !words.isEmpty else { return -1 }
        for k in 0..<words.count {
            let j = i + k
            if !usable(j) || tokens[j].plain != words[k] {
                return -1
            }
        }
        return i + words.count - 1
    }

    /// Longest of `phrases` starting at `i` → end index or -1.
    func matchAny(_ i: Int, _ phrases: [[String]]) -> Int {
        var best = -1
        var bestLength = 0
        for phrase in phrases {
            let e = matchSequence(i, phrase)
            if e >= 0 && phrase.count > bestLength {
                best = e
                bestLength = phrase.count
            }
        }
        return best
    }

    /// Longest phrase whose last token is `last` → start index or -1.
    func phraseEnding(at last: Int, _ phrases: [[String]]) -> Int {
        var bestStart = -1
        var bestLength = 0
        for phrase in phrases {
            let a = last - phrase.count + 1
            if a < 0 {
                continue
            }
            if matchSequence(a, phrase) == last && phrase.count > bestLength {
                bestStart = a
                bestLength = phrase.count
            }
        }
        return bestStart
    }

    /// Leftmost (then longest) occurrence of any phrase.
    func findPhrase(_ phrases: [[String]], from start: Int = 0) -> (start: Int, end: Int)? {
        var i = max(0, start)
        while i < tokens.count {
            let e = matchAny(i, phrases)
            if e >= 0 {
                return (i, e)
            }
            i += 1
        }
        return nil
    }

    // MARK: - Calendar helpers (all arithmetic through the injected calendar, 02 §8)

    func addDays(_ n: Int, to date: Date) -> Date {
        return AsistCalendar.addingDays(n, to: date, calendar: calendar)
    }

    func addMonths(_ n: Int, to date: Date) -> Date {
        return calendar.date(byAdding: .month, value: n, to: date) ?? addDays(30 * n, to: date)
    }

    func addYears(_ n: Int, to date: Date) -> Date {
        return calendar.date(byAdding: .year, value: n, to: date) ?? addDays(365 * n, to: date)
    }

    func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
        return AsistCalendar.date(on: day, at: ClockTime(hour, minute), calendar: calendar)
    }

    func at(_ day: Date, _ time: ClockTime) -> Date {
        return AsistCalendar.date(on: day, at: time, calendar: calendar)
    }

    func isoWeekday(_ date: Date) -> Int {
        return AsistCalendar.isoWeekday(date, calendar: calendar)
    }

    func weekStart(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        return addDays(-(isoWeekday(day) - 1), to: day)
    }

    func components(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    func daysInMonth(year: Int, month: Int) -> Int {
        return ParserDates.daysInMonth(year: year, month: month, calendar: calendar)
    }

    /// Start of day of y-m-d, nil when the date does not exist.
    func makeDay(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        return ParserDates.makeDay(year, month, day, calendar: calendar)
    }
}

/// Calendar utilities shared by the parser and `RecurrenceEngine`.
enum ParserDates {
    static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        guard month >= 1 && month <= 12 else { return 30 }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        comps.hour = 12
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return fallbackDaysInMonth(year: year, month: month)
        }
        return range.count
    }

    static func fallbackDaysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    static func makeDay(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date? {
        guard month >= 1 && month <= 12 && day >= 1 else { return nil }
        guard day <= daysInMonth(year: year, month: month, calendar: calendar) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        guard let noon = calendar.date(from: comps) else { return nil }
        return calendar.startOfDay(for: noon)
    }

    static func isValid(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Bool {
        return makeDay(year, month, day, calendar: calendar) != nil
    }

    /// Calendar-day difference `to − from` (start of day to start of day).
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

/// Suffix-tolerant lexicon matching on folded tokens (02 §5: "root equals the key and the suffix belongs to the
/// entry's class; for tokens without apostrophe the scanner tries key + suffix").
enum TokenMatch {
    /// Matched folded suffix ("" for the bare word) or nil.
    static func suffix(_ token: Token, _ key: String, _ allowed: [String]) -> String? {
        if token.isSplit && token.root == key && allowed.contains(token.suffix) {
            return token.suffix
        }
        if let rest = TurkishNumbers.remainder(token.plain, afterPrefix: key), allowed.contains(rest) {
            return rest
        }
        return nil
    }

    static let defaultWeekdaySuffixes: [String] = Lexicon.joined([Lexicon.weekdaySuffixes, Lexicon.pluralDays])

    /// ISO weekday + suffix ("salıya" → (2, "ya")); the longest key wins ("pazartesi" before "pazar").
    static func weekday(_ token: Token, allowed: [String]? = nil) -> (iso: Int, suffix: String)? {
        let suffixes = allowed ?? defaultWeekdaySuffixes
        var best: (iso: Int, suffix: String, length: Int)? = nil
        for entry in Lexicon.weekdays {
            guard let found = suffix(token, entry.key, suffixes) else { continue }
            if best == nil || entry.key.count > (best?.length ?? 0) {
                best = (entry.iso, found, entry.key.count)
            }
        }
        guard let result = best else { return nil }
        return (result.iso, result.suffix)
    }

    static func month(_ token: Token, allowed: [String]? = nil) -> (month: Int, suffix: String)? {
        let suffixes = allowed ?? Lexicon.monthSuffixes
        for entry in Lexicon.months {
            if let found = suffix(token, entry.key, suffixes) {
                return (entry.month, found)
            }
        }
        return nil
    }

    /// Single-token daypart ("sabah", "akşamı", "gece" …).
    static func daypart(_ token: Token) -> (slot: DaypartSlot, qualifier: DaypartQualifier)? {
        let word = token.plain
        if Lexicon.daypartSabah.contains(word) {
            return (.sabah, .am)
        }
        if Lexicon.daypartOgle.contains(word) {
            return (.ogle, .noon)
        }
        if Lexicon.daypartAksamustu.contains(word) {
            return (.aksamustu, .pm)
        }
        if Lexicon.daypartAksam.contains(word) {
            return (.aksam, .evening)
        }
        if Lexicon.daypartGece.contains(word) {
            return (.gece, .night)
        }
        return nil
    }

    static func isDative(_ suffix: String) -> Bool {
        return Lexicon.dative.contains(suffix)
    }
}
