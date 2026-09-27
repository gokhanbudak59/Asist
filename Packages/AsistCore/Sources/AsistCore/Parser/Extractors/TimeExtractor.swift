// Clock phrases (02 §6.3), dayparts (02 §5.5) and number guards G1/G7/G11 (04 §3.4.6).
import Foundation

enum TimeExtractor {
    // MARK: - G1 / G11 guards (run before any date/time reading)

    static func isUnitToken(_ token: Token) -> Bool {
        if token.isSplit {
            return Lexicon.unitWords.contains(token.root)
        }
        return Lexicon.unitWords.contains(token.plain)
    }

    /// Equipment numbers ("Hat 2'de", "3 nolu"), engineering units ("24 volt") and versions ("4.20'ye güncelle")
    /// are kept in the title and never read as clocks; they do not raise `unusedNumber`.
    static func protectNumbers(_ ctx: inout ParseContext) {
        for j in 0..<ctx.count {
            guard ctx.usable(j), let number = ctx.tokens[j].number else { continue }
            let previous: Token? = j > 0 ? ctx.tokens[j - 1] : nil
            let next: Token? = j + 1 < ctx.count ? ctx.tokens[j + 1] : nil
            var isScalar = false
            var isDotted = false
            switch number {
            case .integer, .half:
                isScalar = true
            case .dotted:
                isScalar = true
                isDotted = true
            default:
                break
            }
            guard isScalar else { continue }
            if let p = previous, Lexicon.equipmentNouns.contains(p.plain), !p.hadApostrophe {
                ctx.protected[j] = true
                continue
            }
            if let n = next, Lexicon.numberNameWords.contains(n.plain) || (n.hadApostrophe && n.root == "no") {
                ctx.protected[j] = true
                ctx.protected[j + 1] = true
                continue
            }
            if let n = next, isUnitToken(n), ctx.usable(j + 1) {
                ctx.protected[j] = true
                continue
            }
            if isDotted {
                var version = false
                for back in 1...2 where j - back >= 0 {
                    let candidate = ctx.tokens[j - back]
                    if Lexicon.versionWords.contains(candidate.root) || Lexicon.versionWords.contains(candidate.plain) {
                        version = true
                    }
                }
                if let n = next, Lexicon.versionVerbs.contains(n.plain) {
                    version = true
                }
                if version {
                    ctx.protected[j] = true
                }
            }
        }
    }

    // MARK: - Dayparts

    static func time(for slot: DaypartSlot, _ settings: ParserSettings) -> ClockTime {
        switch slot {
        case .sabah: return settings.sabah
        case .ogledenOnce: return settings.ogledenOnce
        case .ogle: return settings.ogle
        case .oglePlus60: return ClockTime(minutesOfDay: settings.ogle.minutesOfDay + 60)
        case .ogledenSonra: return settings.ogledenSonra
        case .aksamustu: return settings.aksamustu
        case .aksam: return settings.aksam
        case .gece: return settings.gece
        case .midnight: return ClockTime(0, 0)
        case .mesaiBasi: return settings.mesaiBasi
        case .mesaiBitimi: return settings.mesaiBitimi
        }
    }

    static func extractDayparts(_ ctx: inout ParseContext) {
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i) else {
                i += 1
                continue
            }
            var best: DaypartPhrase? = nil
            var bestEnd = -1
            for phrase in Lexicon.daypartPhrases {
                let e = ctx.matchSequence(i, phrase.words)
                if e >= 0 && phrase.words.count > (best?.words.count ?? 0) {
                    best = phrase
                    bestEnd = e
                }
            }
            if let phrase = best {
                if phrase.slot == .gece && phrase.explicitToday {
                    ctx.nightAnywhere = true
                }
                var hit = DaypartHit(time: time(for: phrase.slot, ctx.settings), qualifier: phrase.qualifier, start: i,
                                     end: bestEnd)
                hit.explicitToday = phrase.explicitToday
                hit.nextDay = phrase.slot == .midnight
                hit.endsWithDative = Lexicon.daypartDativeForms.contains(ctx.plain(bestEnd))
                ctx.dayparts.append(hit)
                ctx.consume(i, bestEnd)
                i = bestEnd + 1
                continue
            }
            if let single = TokenMatch.daypart(ctx.tokens[i]) {
                if single.slot == .gece && isGeceMinutePhrase(ctx, i) {
                    // "üçü çeyrek geçe": "geçe" (past) folds to "gece" (night).
                    i += 1
                    continue
                }
                if single.slot == .gece && ctx.plain(i + 1).hasPrefix("vardiya") {
                    // G7 "gece vardiyası": qualifies a 1–6 clock as night, stays in the title.
                    ctx.nightAnywhere = true
                    i += 1
                    continue
                }
                var hit = DaypartHit(time: time(for: single.slot, ctx.settings), qualifier: single.qualifier, start: i,
                                     end: i)
                hit.endsWithDative = Lexicon.daypartDativeForms.contains(ctx.plain(i))
                ctx.dayparts.append(hit)
                ctx.consume(i, i)
            }
            i += 1
        }
    }

    static func isGeceMinutePhrase(_ ctx: ParseContext, _ i: Int) -> Bool {
        if ctx.tokens[i].lower.hasPrefix("geçe") {
            return true
        }
        guard i > 0 else { return false }
        let previous = ctx.tokens[i - 1]
        if previous.plain == "ceyrek" || previous.number != nil {
            return true
        }
        return TurkishNumbers.wordNumber(of: previous) != nil
    }

    // MARK: - Clocks

    static func extractClocks(_ ctx: inout ParseContext) {
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i) else {
                i += 1
                continue
            }
            let end = clockPhrase(&ctx, i)
            i = end >= i ? end + 1 : i + 1
        }
    }

    /// Records a clock (or an invalid one) spanning start...end (+ trailing "civarı/gibi"). Returns the last index.
    static func finishClock(_ ctx: inout ParseContext, hour: Int, minute: Int, start: Int, end: Int,
                            leadingZero: Bool = false, invalid: Bool = false, dative: Bool = false) -> Int {
        var e = end
        if Lexicon.approximateWords.contains(ctx.usablePlain(e + 1)) {
            e += 1
        }
        if invalid || hour < 0 || hour > 24 || minute < 0 || minute > 59 {
            ctx.flags.insert(.invalidDateTime)
            ctx.protect(start, e, invalid: true)
            return e
        }
        var hit = ClockHit(hour: hour, minute: minute, start: start, end: e)
        hit.leadingZero = leadingZero
        hit.endsWithDative = dative
        ctx.clocks.append(hit)
        ctx.consume(start, e)
        return e
    }

    /// Word hours "bir" / "on" are hours only inside a clock context (02 §6.1, §6.3).
    static func wordHourAllowed(_ ctx: ParseContext, _ number: NumberPhrase, hasSaat: Bool, _ j: Int) -> Bool {
        guard number.isWord, number.start == number.end else { return true }
        let previous = j - 1
        let afterDayOrDaypart = previous >= 0 && ctx.consumed[previous]
            && (ctx.days.contains(where: { $0.end == previous }) || ctx.dayparts.contains(where: { $0.end == previous }))
        if number.value == 1 {
            return hasSaat || afterDayOrDaypart
        }
        if number.value == 10 {
            return hasSaat || (number.suffix == "da" && afterDayOrDaypart)
        }
        return true
    }

    /// Clock phrase starting at `i` → last consumed index, or -1.
    static func clockPhrase(_ ctx: inout ParseContext, _ i: Int) -> Int {
        let first = ctx.tokens[i]
        let hasSaat = first.plain == "saat" && !first.isSplit
        let j = hasSaat ? i + 1 : i
        guard ctx.usable(j) else { return -1 }
        let token = ctx.tokens[j]
        let previousIsDaypart = ctx.dayparts.contains(where: { $0.end == i - 1 })
        let locOrDat = Lexicon.joined([Lexicon.locative, Lexicon.dative])
        let hasLocOrDat = locOrDat.contains(token.suffix)

        if let number = token.number {
            switch number {
            case .clock(let h, let m):
                if token.suffix.isEmpty || hasLocOrDat {
                    return finishClock(&ctx, hour: h, minute: m, start: i, end: j, leadingZero: token.leadingZero,
                                       dative: TokenMatch.isDative(token.suffix))
                }
                if Lexicon.ablative.contains(token.suffix) && ctx.usablePlain(j + 1) == "sonra" {
                    return finishClock(&ctx, hour: h, minute: m, start: i, end: j + 1, leadingZero: token.leadingZero)
                }
                return -1
            case .dotted(let a, let b):
                let timeLike = hasSaat || previousIsDaypart || hasLocOrDat || b > 12 || b == 0
                if !timeLike && b >= 1 && b <= 12 && a >= 1 && a <= 31 {
                    return -1
                }
                if a <= 24 && b <= 59 {
                    return finishClock(&ctx, hour: a, minute: b, start: i, end: j, leadingZero: token.leadingZero,
                                       dative: TokenMatch.isDative(token.suffix))
                }
                if hasSaat || hasLocOrDat {
                    return finishClock(&ctx, hour: a, minute: b, start: i, end: j, invalid: true)
                }
                return -1
            case .integer, .half:
                break
            default:
                return -1
            }
        }
        if hasSaat && token.plain.hasPrefix("yarim") {
            let rest = String(token.plain.dropFirst(5))
            if rest.isEmpty || locOrDat.contains(rest) {
                return finishClock(&ctx, hour: 12, minute: 30, start: i, end: j)
            }
        }
        guard let number = ctx.numberPhrase(at: j), !number.isHalf else { return -1 }
        let hour = number.value
        let next = number.end + 1
        let nextWord = ctx.usablePlain(next)

        // "N buçuk(ta)" → H:30
        if number.suffix.isEmpty && (nextWord.hasPrefix("bucuk") || nextWord.hasPrefix("bucug")) {
            let rest = String(nextWord.dropFirst(5))
            if rest.isEmpty || locOrDat.contains(rest) {
                if hour > 24 {
                    return -1
                }
                return finishClock(&ctx, hour: hour, minute: 30, start: i, end: next, dative: TokenMatch.isDative(rest))
            }
        }
        // "saat 15 30'da", "on beş otuzda", "dokuz kırk beşte"
        if number.suffix.isEmpty && ctx.usable(next), let minutes = ctx.numberPhrase(at: next), !minutes.isHalf,
           minutes.value >= 0 && minutes.value <= 59, hasSaat || locOrDat.contains(minutes.suffix) {
            let followedByUnit = ctx.usable(minutes.end + 1) && ctx.durationUnit(of: ctx.tokens[minutes.end + 1]) != nil
            if !followedByUnit && hour <= 24 {
                return finishClock(&ctx, hour: hour, minute: minutes.value, start: i, end: minutes.end,
                                   dative: TokenMatch.isDative(minutes.suffix))
            }
        }
        // "üçü çeyrek geçe", "beşi yirmi beş geçe"
        if Lexicon.accusative.contains(number.suffix) && ctx.usable(next) {
            if nextWord == "ceyrek" && ctx.usablePlain(next + 1) == "gece" {
                return finishClock(&ctx, hour: hour, minute: 15, start: i, end: next + 1)
            }
            if let minutes = ctx.numberPhrase(at: next), minutes.suffix.isEmpty, minutes.value >= 1 && minutes.value <= 59,
               ctx.usablePlain(minutes.end + 1) == "gece" {
                return finishClock(&ctx, hour: hour, minute: minutes.value, start: i, end: minutes.end + 1)
            }
        }
        // "dörde çeyrek var", "beşe on kala"
        if Lexicon.dative.contains(number.suffix) && ctx.usable(next) {
            let previousHour = hour == 0 ? 23 : hour - 1
            let varKala: Set<String> = ["var", "kala"]
            if nextWord == "ceyrek" && varKala.contains(ctx.usablePlain(next + 1)) {
                return finishClock(&ctx, hour: previousHour, minute: 45, start: i, end: next + 1)
            }
            if let minutes = ctx.numberPhrase(at: next), minutes.suffix.isEmpty, minutes.value >= 1 && minutes.value <= 59,
               varKala.contains(ctx.usablePlain(minutes.end + 1)) {
                return finishClock(&ctx, hour: previousHour, minute: 60 - minutes.value, start: i, end: minutes.end + 1)
            }
        }
        guard wordHourAllowed(ctx, number, hasSaat: hasSaat, j) else { return -1 }
        let followedByUnit = ctx.usable(next) && ctx.durationUnit(of: ctx.tokens[next]) != nil
        // "3'te", "üçte", "saat 15'e"
        if locOrDat.contains(number.suffix) && !["nde", "nda", "ne", "na"].contains(number.suffix) {
            if hour > 24 {
                return hasSaat ? finishClock(&ctx, hour: hour, minute: 0, start: i, end: number.end, invalid: true) : -1
            }
            var end = number.end
            if TokenMatch.isDative(number.suffix) && nextWord == "dogru" {
                end = next
            }
            return finishClock(&ctx, hour: hour, minute: 0, start: i, end: end, dative: TokenMatch.isDative(number.suffix))
        }
        // G7 "10'dan sonra"
        if Lexicon.ablative.contains(number.suffix) && nextWord == "sonra" && (!number.isWord || hasSaat) {
            if hour > 24 {
                return -1
            }
            return finishClock(&ctx, hour: hour, minute: 0, start: i, end: next)
        }
        if number.suffix.isEmpty {
            // G7 "4 gibi / civarı"
            if Lexicon.approximateWords.contains(nextWord) && hour <= 24 {
                return finishClock(&ctx, hour: hour, minute: 0, start: i, end: number.end)
            }
            if hasSaat {
                if hour > 24 {
                    return finishClock(&ctx, hour: hour, minute: 0, start: i, end: number.end, invalid: true)
                }
                if followedByUnit {
                    return -1
                }
                return finishClock(&ctx, hour: hour, minute: 0, start: i, end: number.end)
            }
            // "sabah 9", "akşam 8"
            if previousIsDaypart && hour <= 24 && !followedByUnit {
                return finishClock(&ctx, hour: hour, minute: 0, start: i, end: number.end)
            }
        }
        return -1
    }

    /// "15:00 ile 16:00 arası" → the range start.
    static func applyClockRanges(_ ctx: inout ParseContext) {
        guard ctx.clocks.count >= 2 else { return }
        let first = ctx.clocks[0]
        let second = ctx.clocks[1]
        let middle = first.end + 1
        guard middle == second.start - 1, ctx.usable(middle) else { return }
        let joiner = ctx.plain(middle)
        let tail = ctx.usablePlain(second.end + 1)
        if (joiner == "ile" || joiner == "ve" || joiner == "ila") && (tail == "arasi" || tail == "arasinda" || tail == "arasina") {
            ctx.consume(middle, second.end + 1)
            ctx.clocks.remove(at: 1)
        }
    }

    /// G8 for clocks ("3'te hayır 4'te").
    static func applyClockCorrections(_ ctx: inout ParseContext) {
        guard ctx.clocks.count >= 2 else { return }
        var out: [ClockHit] = [ctx.clocks[0]]
        for hit in ctx.clocks.dropFirst() {
            let previous = out[out.count - 1]
            if DateExtractor.isCorrectionSpan(ctx, from: previous.end + 1, to: hit.start - 1) {
                ctx.consume(previous.end + 1, hit.start - 1)
                ctx.flags.insert(.correctionApplied)
                out[out.count - 1] = hit
            } else {
                out.append(hit)
            }
        }
        ctx.clocks = out
    }

    /// The daypart adjacent to a clock is its qualifier (02 §8.5); a single daypart elsewhere also qualifies it;
    /// G7: "bu gece / gece vardiyası" anywhere makes a 1–6 clock NIGHT.
    static func assignQualifiers(_ ctx: inout ParseContext) {
        guard !ctx.clocks.isEmpty else { return }
        for index in 0..<ctx.clocks.count {
            let clock = ctx.clocks[index]
            var qualifierSource: DaypartHit? = nil
            for daypart in ctx.dayparts where daypart.end + 1 == clock.start || clock.end + 1 == daypart.start {
                qualifierSource = daypart
            }
            if qualifierSource == nil && ctx.dayparts.count == 1 {
                qualifierSource = ctx.dayparts[0]
            }
            if let source = qualifierSource, let qualifier = source.qualifier {
                ctx.clocks[index].qualifier = qualifier
            } else if ctx.nightAnywhere && clock.hour >= 1 && clock.hour <= 6 {
                ctx.clocks[index].qualifier = .night
            }
        }
    }

    /// Deadline wrappers (02 §8.3 last row): "D'ye kadar", "en geç D", "D'den önce", "D'den itibaren".
    static func extractWrappers(_ ctx: inout ParseContext) {
        var ends: [Int] = []
        var starts: [Int] = []
        for hit in ctx.days {
            ends.append(hit.end)
            starts.append(hit.start)
        }
        for hit in ctx.filterDays {
            ends.append(hit.end)
        }
        for hit in ctx.clocks {
            ends.append(hit.end)
            starts.append(hit.start)
        }
        for hit in ctx.dayparts {
            ends.append(hit.end)
            starts.append(hit.start)
        }
        for end in ends {
            let next = end + 1
            let word = ctx.usablePlain(next)
            if word == "kadar" || word == "itibaren" || word == "itibariyle" || word == "baslayarak" {
                ctx.consume(next, next)
            } else if word == "once" && end >= 0 && end < ctx.count && Lexicon.ablative.contains(ctx.tokens[end].suffix) {
                ctx.consume(next, next)
            }
        }
        for start in starts where start >= 2 {
            if ctx.usablePlain(start - 2) == "en" && ctx.usablePlain(start - 1) == "gec" {
                ctx.consume(start - 2, start - 1)
            }
        }
    }
}
