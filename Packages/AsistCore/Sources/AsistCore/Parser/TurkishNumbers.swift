// TurkishNumbers — 02 §6 (cardinal words, number phrases, durations).
import Foundation

/// A number read from one or two tokens ("15'te", "on beşte", "yirmi birinde").
struct NumberPhrase {
    let value: Int
    /// Folded suffix of the last token ("te", "inde", "" …).
    let suffix: String
    let start: Int
    /// Inclusive.
    let end: Int
    let isWord: Bool
    /// "1,5" / "1.5".
    let isHalf: Bool
}

enum DurationUnit: Equatable {
    case minute, hour, day, week, month, year
}

/// "10 dakika", "bir buçuk saat", "1 saat 20 dakika", "iki hafta" (02 §6.4).
struct DurationPhrase {
    var start: Int
    var end: Int
    var minutes = 0
    var days = 0
    var months = 0
    var years = 0
    /// Folded suffix of the unit token ("" / "ya" in "dakikaya" / "dan" …).
    var unitSuffix = ""
    var isCalendar = false

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    var totalMinutes: Int {
        return minutes + days * 1440 + months * 43_200 + years * 525_600
    }
}

enum TurkishNumbers {
    /// Stems in Turkish lowercase, with ASCII typing variants (matched on the unfolded form so "önde" ≠ "on"+"de").
    static let unitStems: [(stem: String, value: Int)] = [
        ("bir", 1), ("iki", 2), ("üç", 3), ("uc", 3), ("dört", 4), ("dörd", 4), ("dort", 4), ("dord", 4),
        ("beş", 5), ("bes", 5), ("altı", 6), ("alti", 6), ("yedi", 7), ("sekiz", 8), ("dokuz", 9)
    ]
    static let tensStems: [(stem: String, value: Int)] = [
        ("yirmi", 20), ("otuz", 30), ("kırk", 40), ("kirk", 40), ("elli", 50), ("altmış", 60), ("altmis", 60),
        ("yetmiş", 70), ("yetmis", 70), ("seksen", 80), ("doksan", 90), ("on", 10)
    ]
    static let hundredStems: [String] = ["yüz", "yuz"]
    /// Folded suffixes allowed after a number word (02 §6.1): LOC, DAT, ACC, POSS3, POSS3LOC, ordinal, ABL.
    static let numberSuffixes: Set<String> = [
        "", "de", "da", "te", "ta", "e", "a", "ye", "ya", "i", "u", "yi", "yu", "si", "su", "inde", "inda", "unde",
        "unda", "sinde", "sinda", "sunde", "sunda", "inci", "nci", "uncu", "ncu", "den", "dan", "ten", "tan", "ine",
        "ina", "une", "una", "sine", "sina", "sune", "suna"
    ]

    static func remainder(_ word: String, afterPrefix prefix: String) -> String? {
        guard word.hasPrefix(prefix) else { return nil }
        return String(word.dropFirst(prefix.count))
    }

    /// Unit stem (1…9) + allowed suffix; the longest stem wins.
    static func unitMatch(_ word: String) -> (value: Int, suffix: String)? {
        var best: (value: Int, suffix: String, length: Int)? = nil
        for entry in unitStems {
            guard let rest = remainder(word, afterPrefix: entry.stem) else { continue }
            let foldedRest = TurkishText.fold(rest)
            guard numberSuffixes.contains(foldedRest) else { continue }
            if best == nil || entry.stem.count > (best?.length ?? 0) {
                best = (entry.value, foldedRest, entry.stem.count)
            }
        }
        guard let found = best else { return nil }
        return (found.value, found.suffix)
    }

    /// Cardinal word (1…199) with its folded suffix. `lowerWord` is Turkish-lowercase without apostrophe.
    static func parseWord(_ lowerWord: String) -> (value: Int, suffix: String)? {
        guard !lowerWord.isEmpty else { return nil }
        for hundred in hundredStems {
            guard let rest = remainder(lowerWord, afterPrefix: hundred) else { continue }
            let foldedRest = TurkishText.fold(rest)
            if numberSuffixes.contains(foldedRest) {
                return (100, foldedRest)
            }
            for tens in tensStems {
                guard let rest2 = remainder(rest, afterPrefix: tens.stem) else { continue }
                let foldedRest2 = TurkishText.fold(rest2)
                if numberSuffixes.contains(foldedRest2) {
                    return (100 + tens.value, foldedRest2)
                }
                if let unit = unitMatch(rest2) {
                    return (100 + tens.value + unit.value, unit.suffix)
                }
            }
            if let unit = unitMatch(rest) {
                return (100 + unit.value, unit.suffix)
            }
        }
        for tens in tensStems {
            guard let rest = remainder(lowerWord, afterPrefix: tens.stem) else { continue }
            let foldedRest = TurkishText.fold(rest)
            if numberSuffixes.contains(foldedRest) {
                return (tens.value, foldedRest)
            }
            if let unit = unitMatch(rest) {
                return (tens.value + unit.value, unit.suffix)
            }
        }
        return unitMatch(lowerWord)
    }

    /// Number word of a token (apostrophe forms: "bir'de" → root "bir" + suffix "de").
    static func wordNumber(of token: Token) -> (value: Int, suffix: String)? {
        guard token.number == nil else { return nil }
        guard let parsed = parseWord(token.lowerRoot) else { return nil }
        if token.hadApostrophe {
            guard parsed.suffix.isEmpty else { return nil }
            return (parsed.value, token.suffix)
        }
        return parsed
    }
}

extension ParseContext {
    /// Number phrase starting at `i`: digits, "1,5", or one/two word tokens (02 §6.1).
    func numberPhrase(at i: Int) -> NumberPhrase? {
        guard usable(i) else { return nil }
        let token = tokens[i]
        if let number = token.number {
            switch number {
            case .integer(let value):
                return NumberPhrase(value: value, suffix: token.suffix, start: i, end: i, isWord: false, isHalf: false)
            case .half(let value):
                return NumberPhrase(value: value, suffix: token.suffix, start: i, end: i, isWord: false, isHalf: true)
            default:
                return nil
            }
        }
        guard let first = TurkishNumbers.wordNumber(of: token) else { return nil }
        let isRoundTens = first.value >= 10 && first.value <= 90 && first.value % 10 == 0
        if isRoundTens && first.suffix.isEmpty && usable(i + 1) {
            if let second = TurkishNumbers.wordNumber(of: tokens[i + 1]), second.value >= 1 && second.value <= 9 {
                return NumberPhrase(value: first.value + second.value, suffix: second.suffix, start: i, end: i + 1,
                                    isWord: true, isHalf: false)
            }
        }
        if first.value == 100 && first.suffix.isEmpty && usable(i + 1) {
            if let rest = numberPhrase(at: i + 1), rest.isWord, rest.value < 100 {
                return NumberPhrase(value: 100 + rest.value, suffix: rest.suffix, start: i, end: rest.end,
                                    isWord: true, isHalf: false)
            }
        }
        return NumberPhrase(value: first.value, suffix: first.suffix, start: i, end: i, isWord: true, isHalf: false)
    }

    // MARK: Durations (02 §6.4)

    static let unitKeys: [(key: String, unit: DurationUnit)] = [
        ("dakika", .minute), ("dakkika", .minute), ("dakka", .minute), ("dak", .minute), ("dk", .minute),
        ("saat", .hour), ("sa", .hour), ("gun", .day), ("hafta", .week), ("ay", .month), ("yil", .year),
        ("sene", .year)
    ]
    static let unitSuffixes: Set<String> = ["", "e", "a", "ye", "ya", "dir", "dur", "lik", "luk", "den", "dan", "ten",
                                            "tan", "de", "da", "te", "ta", "nde", "nda", "inde", "unde", "inda",
                                            "unda", "icinde"]

    /// Duration unit word with its suffix ("dakikaya" → (.minute, "ya")).
    func durationUnit(of token: Token) -> (unit: DurationUnit, suffix: String)? {
        var best: (unit: DurationUnit, suffix: String, length: Int)? = nil
        for entry in ParseContext.unitKeys {
            var suffix: String? = nil
            if token.isSplit && token.root == entry.key && ParseContext.unitSuffixes.contains(token.suffix) {
                suffix = token.suffix
            } else if let rest = TurkishNumbers.remainder(token.plain, afterPrefix: entry.key),
                      ParseContext.unitSuffixes.contains(rest) {
                suffix = rest
            }
            guard let found = suffix else { continue }
            if entry.key == "sa" && !found.isEmpty {
                continue
            }
            if best == nil || entry.key.count > (best?.length ?? 0) {
                best = (entry.unit, found, entry.key.count)
            }
        }
        guard let result = best else { return nil }
        return (result.unit, result.suffix)
    }

    /// Amount in halves ("yarım" = 1, "bir buçuk" = 3, "1,5" = 3) and its last index.
    func durationAmount(at i: Int) -> (halves: Int, end: Int)? {
        guard usable(i) else { return nil }
        if tokens[i].plain == "yarim" {
            return (1, i)
        }
        guard let number = numberPhrase(at: i), number.suffix.isEmpty else { return nil }
        var halves = number.value * 2 + (number.isHalf ? 1 : 0)
        var end = number.end
        if usable(end + 1) && tokens[end + 1].plain == "bucuk" {
            halves += 1
            end += 1
        }
        return (halves, end)
    }

    /// `AMOUNT UNIT [AMOUNT dakika]` starting at `i`.
    func durationPhrase(at i: Int) -> DurationPhrase? {
        if usable(i) && tokens[i].plain == "ceyrek" && usable(i + 1),
           let unit = durationUnit(of: tokens[i + 1]), unit.unit == .hour {
            var quarter = DurationPhrase(start: i, end: i + 1)
            quarter.minutes = 15
            quarter.unitSuffix = unit.suffix
            return quarter
        }
        guard let amount = durationAmount(at: i) else { return nil }
        let unitIndex = amount.end + 1
        guard usable(unitIndex), let unit = durationUnit(of: tokens[unitIndex]) else { return nil }
        var phrase = DurationPhrase(start: i, end: unitIndex)
        phrase.unitSuffix = unit.suffix
        let halves = amount.halves
        let whole = halves / 2
        let hasHalf = halves % 2 == 1
        switch unit.unit {
        case .minute:
            phrase.minutes = whole
        case .hour:
            phrase.minutes = halves * 30
        case .day:
            if hasHalf { return nil }
            phrase.days = whole
            phrase.isCalendar = true
        case .week:
            if hasHalf { return nil }
            phrase.days = whole * 7
            phrase.isCalendar = true
        case .month:
            if hasHalf { return nil }
            phrase.months = whole
            phrase.isCalendar = true
        case .year:
            if hasHalf { return nil }
            phrase.years = whole
            phrase.isCalendar = true
        }
        // "1 saat 20 dakika"
        if unit.unit == .hour && unit.suffix.isEmpty, let extra = durationAmount(at: unitIndex + 1),
           usable(extra.end + 1), let minuteUnit = durationUnit(of: tokens[extra.end + 1]), minuteUnit.unit == .minute {
            phrase.minutes += extra.halves / 2
            phrase.end = extra.end + 1
            phrase.unitSuffix = minuteUnit.suffix
        }
        if !phrase.isCalendar && phrase.minutes <= 0 {
            return nil
        }
        if phrase.isCalendar && phrase.days == 0 && phrase.months == 0 && phrase.years == 0 {
            return nil
        }
        return phrase
    }
}
