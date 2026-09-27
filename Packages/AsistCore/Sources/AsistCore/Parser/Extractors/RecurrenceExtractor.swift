// Recurrence phrases — 02 §9.1 + G12 (04 §3.4.6). Resolution of the first occurrence lives in DateResolver.
import Foundation

enum RecurrenceExtractor {
    static let dayGlue: Set<String> = ["gunu", "gunleri", "gununde"]
    static let timesWords: Set<String> = ["kere", "kez", "defa"]
    static let recurringDayparts: Set<String> = ["sabah", "ogle", "oglen", "aksam", "gece", "aksamustu", "ogleden",
                                                 "aksamlari", "sabahlari"]

    static func extract(_ ctx: inout ParseContext) {
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i) else {
                i += 1
                continue
            }
            let word = ctx.plain(i)
            var end = -1
            if word == "her" {
                end = afterHer(&ctx, i)
            } else if word == "hergun" {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .daily))
                ctx.consume(i, i)
                end = i
            } else {
                end = withoutHer(&ctx, i)
            }
            i = end >= i ? end + 1 : i + 1
        }
    }

    /// "W (ve|ile|,) W …" → sorted weekdays, last index, whether a plural form ("salıları") was used.
    static func weekdayList(_ ctx: ParseContext, _ start: Int) -> (weekdays: [Int], end: Int, plural: Bool)? {
        var list: [Int] = []
        var j = start
        var end = -1
        var plural = false
        while ctx.usable(j) {
            guard let found = TokenMatch.weekday(ctx.tokens[j]) else { break }
            if Lexicon.pluralDays.contains(found.suffix) {
                plural = true
            } else if !found.suffix.isEmpty {
                break
            }
            list.append(found.iso)
            end = j
            let k = j + 1
            let joiner = ctx.usablePlain(k)
            if joiner == "ve" || joiner == "ile" || joiner == "veya" {
                if k + 1 < ctx.count && TokenMatch.weekday(ctx.tokens[k + 1]) != nil {
                    j = k + 1
                    continue
                }
                break
            }
            if ctx.tokens[j].trailingPunct == ",", k < ctx.count, TokenMatch.weekday(ctx.tokens[k]) != nil {
                j = k
                continue
            }
            break
        }
        guard !list.isEmpty else { return nil }
        return (Array(Set(list)).sorted(), end, plural)
    }

    /// "N günde/haftada/ayda/yılda bir" (+ "kere"), "N dakikada bir" (unsupported). Returns the last index or -1.
    static func everyN(_ ctx: inout ParseContext, _ numberStart: Int) -> Int {
        guard let number = ctx.numberPhrase(at: numberStart), number.suffix.isEmpty, !number.isHalf else { return -1 }
        let unitIndex = number.end + 1
        guard ctx.usable(unitIndex) else { return -1 }
        let unitWord = ctx.plain(unitIndex)
        var b = unitIndex + 1
        let hasBir = ctx.usablePlain(b) == "bir"
        if hasBir && timesWords.contains(ctx.usablePlain(b + 1)) {
            b += 1
        }
        guard hasBir else { return -1 }
        let n = number.value
        switch unitWord {
        case "gunde":
            if n == 15 {
                // "on beş günde bir" = every two weeks (02 §9.1).
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, interval: 2))
            } else {
                var spec = RecurrenceSpec(frequency: .daily, interval: max(1, n))
                if n > 30 {
                    spec.interval = 30
                    ctx.flags.insert(.vagueDate)
                }
                ctx.recurrenceSpecs.append(spec)
            }
            return b
        case "haftada":
            if n > 12 {
                ctx.flags.insert(.vagueDate)
            }
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, interval: max(1, min(12, n))))
            return b
        case "ayda":
            if n > 12 {
                ctx.flags.insert(.vagueDate)
            }
            var spec = RecurrenceSpec(frequency: .monthly, interval: max(1, min(12, n)))
            spec.anchorToday = n > 1
            ctx.recurrenceSpecs.append(spec)
            return b
        case "yilda", "senede":
            if n > 12 {
                ctx.flags.insert(.vagueDate)
            }
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .yearly, interval: max(1, min(12, n))))
            return b
        case "dakikada", "dkda", "saatte":
            ctx.unsupportedRecurrence = true
            return b
        default:
            return -1
        }
    }

    static func consumeDayGlue(_ ctx: ParseContext, after end: Int) -> Int {
        return dayGlue.contains(ctx.usablePlain(end + 1)) ? end + 1 : end
    }

    static func afterHer(_ ctx: inout ParseContext, _ i: Int) -> Int {
        let j = i + 1
        guard ctx.usable(j) else { return -1 }
        let word = ctx.plain(j)
        let next = ctx.usablePlain(j + 1)
        if word == "gun" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .daily))
            let e = next == "duzenli" ? j + 1 : j
            ctx.consume(i, e)
            return e
        }
        if recurringDayparts.contains(word) {
            // "her sabah" → daily; the daypart itself is read by the time extractor.
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .daily))
            ctx.consume(i, i)
            return i
        }
        if word == "is" && next == "gunu" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]))
            ctx.consume(i, j + 1)
            return j + 1
        }
        if word == "hafta" {
            if next == "ici" {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]))
                ctx.consume(i, j + 1)
                return j + 1
            }
            if next == "sonu" || next == "sonlari" {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [6, 7]))
                ctx.consume(i, j + 1)
                return j + 1
            }
            if let list = weekdayList(ctx, j + 1) {
                let e = consumeDayGlue(ctx, after: list.end)
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: list.weekdays))
                ctx.consume(i, e)
                return e
            }
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly))
            ctx.consume(i, j)
            return j
        }
        if word == "saat" || word == "dakika" {
            ctx.unsupportedRecurrence = true
            ctx.consume(i, j)
            return j
        }
        if word == "yarim" && next.hasPrefix("saat") {
            ctx.unsupportedRecurrence = true
            ctx.consume(i, j + 1)
            return j + 1
        }
        let every = everyN(&ctx, j)
        if every >= 0 {
            ctx.consume(i, every)
            return every
        }
        if let list = weekdayList(ctx, j) {
            let e = consumeDayGlue(ctx, after: list.end)
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: list.weekdays))
            ctx.consume(i, e)
            return e
        }
        if word == "ay" {
            return monthlyAfterAy(&ctx, i, j)
        }
        if word == "ayin" {
            return monthlyAfterAyin(&ctx, i, j)
        }
        if word == "yil" || word == "sene" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .yearly))
            ctx.consume(i, j)
            return j
        }
        return -1
    }

    /// "her ay (N'inde | sonu | başı)" — `j` is the "ay" token.
    static func monthlyAfterAy(_ ctx: inout ParseContext, _ i: Int, _ j: Int) -> Int {
        var spec = RecurrenceSpec(frequency: .monthly)
        var e = j
        let dayForms = Lexicon.joined([Lexicon.possessive3, Lexicon.possessive3Locative])
        let next = ctx.usablePlain(j + 1)
        if let number = ctx.numberPhrase(at: j + 1), dayForms.contains(number.suffix),
           number.value >= 1 && number.value <= 31 {
            spec.monthDay = number.value
            e = number.end
        } else if next == "sonu" || next == "sonunda" {
            spec.monthDay = -1
            e = j + 1
        } else if next == "basi" || next == "basinda" {
            spec.monthDay = 1
            e = j + 1
        }
        ctx.recurrenceSpecs.append(spec)
        ctx.consume(i, e)
        return e
    }

    /// "her ayın (N'i | son günü | ilk günü | başında | sonunda | ilk pazartesi)" — `j` is the "ayın" token.
    static func monthlyAfterAyin(_ ctx: inout ParseContext, _ i: Int, _ j: Int) -> Int {
        let k = j + 1
        let dayForms = Lexicon.joined([Lexicon.possessive3, Lexicon.possessive3Locative, [""], Lexicon.ordinal])
        if let number = ctx.numberPhrase(at: k), dayForms.contains(number.suffix) {
            if number.value >= 1 && number.value <= 31 {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .monthly, monthDay: number.value))
            } else {
                ctx.flags.insert(.invalidDateTime)
            }
            ctx.consume(i, number.end)
            return number.end
        }
        let word = ctx.usablePlain(k)
        let next = ctx.usablePlain(k + 1)
        let dayWords: Set<String> = ["gunu", "gununde", "gun"]
        if word == "son" && dayWords.contains(next) {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .monthly, monthDay: -1))
            ctx.consume(i, k + 1)
            return k + 1
        }
        if word == "ilk" && dayWords.contains(next) {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .monthly, monthDay: 1))
            ctx.consume(i, k + 1)
            return k + 1
        }
        if word == "basinda" || word == "basi" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .monthly, monthDay: 1))
            ctx.consume(i, k)
            return k
        }
        if word == "sonunda" || word == "sonu" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .monthly, monthDay: -1))
            ctx.consume(i, k)
            return k
        }
        // G12 v1: n'th weekday of the month is not representable → recurrence nil, review.
        if let ordinal = Lexicon.ordinalWords[word], k + 1 < ctx.count, ctx.usable(k + 1),
           let weekday = TokenMatch.weekday(ctx.tokens[k + 1]) {
            ctx.unsupportedRecurrence = true
            ctx.nthWeekdayOrdinal = ordinal
            ctx.nthWeekdayDay = weekday.iso
            let e = consumeDayGlue(ctx, after: k + 1)
            ctx.consume(i, e)
            return e
        }
        return -1
    }

    static func withoutHer(_ ctx: inout ParseContext, _ i: Int) -> Int {
        let word = ctx.plain(i)
        let next = ctx.usablePlain(i + 1)
        if let number = ctx.numberPhrase(at: i), number.suffix.isEmpty {
            let every = everyN(&ctx, i)
            if every >= 0 {
                ctx.consume(i, every)
                return every
            }
        }
        if word == "gunde" && next == "bir" {
            let e = timesWords.contains(ctx.usablePlain(i + 2)) ? i + 2 : i + 1
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .daily))
            ctx.consume(i, e)
            return e
        }
        if word == "ayda" && next == "bir" {
            var spec = RecurrenceSpec(frequency: .monthly)
            var e = i + 1
            let dayForms = Lexicon.joined([Lexicon.possessive3, Lexicon.possessive3Locative])
            if let number = ctx.numberPhrase(at: i + 2), dayForms.contains(number.suffix),
               number.value >= 1 && number.value <= 31 {
                spec.monthDay = number.value
                e = number.end
            }
            ctx.recurrenceSpecs.append(spec)
            ctx.consume(i, e)
            return e
        }
        if (word == "yilda" || word == "senede") && next == "bir" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .yearly))
            ctx.consume(i, i + 1)
            return i + 1
        }
        if word == "saatte" && next == "bir" {
            ctx.unsupportedRecurrence = true
            ctx.consume(i, i + 1)
            return i + 1
        }
        if word == "hafta" && (next == "ici" || next == "icleri") {
            var e = i + 1
            if ctx.usablePlain(e + 1) == "her" && ctx.usablePlain(e + 2) == "gun" {
                e += 2
            }
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]))
            ctx.consume(i, e)
            return e
        }
        if (word == "hafta" && next == "sonlari") || word == "haftasonlari" {
            let e = word == "hafta" ? i + 1 : i
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [6, 7]))
            ctx.consume(i, e)
            return e
        }
        if word == "is" && next == "gunleri" {
            ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]))
            ctx.consume(i, i + 1)
            return i + 1
        }
        if let list = weekdayList(ctx, i) {
            if list.plural {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: list.weekdays))
                ctx.consume(i, list.end)
                return list.end
            }
            if ctx.usablePlain(list.end + 1) == "gunleri" {
                ctx.recurrenceSpecs.append(RecurrenceSpec(frequency: .weekly, weekdays: list.weekdays))
                ctx.consume(i, list.end + 1)
                return list.end + 1
            }
        }
        // "doğum günü" / "yıl dönümü" + an explicit N AY date → yearly (02 §9.1); the words stay in the title.
        if word == "dogumgunu" || word == "yildonumu" {
            ctx.yearlyAuto = true
        }
        if word == "dogum" && ["gunu", "gununde", "gunun", "gunune"].contains(ctx.plain(i + 1)) {
            ctx.yearlyAuto = true
        }
        if word == "yil" && ["donumu", "donumunde"].contains(ctx.plain(i + 1)) {
            ctx.yearlyAuto = true
        }
        return -1
    }
}
