// Day expressions (02 §8.3–8.4 + G3/G8/G9/G11, P1/P2) and relative offsets (02 §6.4, §8.2).
import Foundation

enum DateExtractor {
    // MARK: - Relative offsets (§6.4)

    static let birazdanPhrases: [[String]] = [["az", "sonra"], ["biraz", "sonra"], ["kisa", "sure", "sonra"],
                                              ["birazcik", "sonra"]]
    /// "sonra" and its suffixed forms after a duration ("1 dakika sonrasına", "yarım saat sonrasında").
    static let sonraTailWords: Set<String> = ["sonra", "sonraya", "sonrasi", "sonrasina", "sonrasinda"]
    static let offsetTailWords: Set<String> = sonraTailWords.union(["icinde", "icerisinde"])
    static let snoozeVerbWords: Set<String> = ["ertele", "otele", "erteler", "ertelesene"]

    static func extractOffsets(_ ctx: inout ParseContext) {
        for i in 0..<ctx.count {
            guard ctx.usable(i) else { continue }
            if ctx.plain(i) == "birazdan" {
                var hit = OffsetHit(start: i, end: i)
                hit.minutes = ctx.settings.birazdanMinutes
                hit.endsWithSonra = true
                addOffset(&ctx, hit)
                continue
            }
            let e = ctx.matchAny(i, birazdanPhrases)
            if e >= 0 {
                var hit = OffsetHit(start: i, end: e)
                hit.minutes = ctx.settings.birazdanMinutes
                hit.endsWithSonra = true
                addOffset(&ctx, hit)
                continue
            }
            guard let duration = ctx.durationPhrase(at: i) else { continue }
            let next = duration.end + 1
            let nextWord = ctx.usablePlain(next)
            var end = -1
            var sonra = false
            if duration.unitSuffix.isEmpty && offsetTailWords.contains(nextWord) {
                end = next
                sonra = sonraTailWords.contains(nextWord)
            } else if Lexicon.dative.contains(duration.unitSuffix) && !duration.unitSuffix.isEmpty {
                end = duration.end
            } else if Lexicon.ablative.contains(duration.unitSuffix) && sonraTailWords.contains(nextWord) {
                end = next
                sonra = true
            } else if duration.unitSuffix.isEmpty && snoozeVerbWords.contains(nextWord) {
                end = duration.end
            }
            guard end >= 0 else { continue }
            var hit = OffsetHit(start: duration.start, end: end)
            hit.minutes = duration.minutes
            hit.days = duration.days
            hit.months = duration.months
            hit.years = duration.years
            hit.isCalendar = duration.isCalendar
            hit.endsWithSonra = sonra
            addOffset(&ctx, hit)
        }
    }

    static func addOffset(_ ctx: inout ParseContext, _ hit: OffsetHit) {
        ctx.consume(hit.start, hit.end)
        if ctx.offset == nil {
            ctx.offset = hit
        }
    }

    // MARK: - Day expressions

    static func extractDates(_ ctx: inout ParseContext) {
        var hits: [DayHit] = []
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i), let hit = dayExpression(&ctx, i) else {
                i += 1
                continue
            }
            hits.append(hit)
            i = hit.end + 1
        }
        var days: [DayHit] = []
        for hit in hits {
            if hit.isFilter {
                ctx.filterDays.append(hit)
            } else {
                days.append(hit)
            }
        }
        let corrected = applyCorrections(&ctx, days)
        ctx.days = corrected
    }

    /// G8: a correction marker between two values of the same type → the last one wins.
    static func applyCorrections(_ ctx: inout ParseContext, _ hits: [DayHit]) -> [DayHit] {
        guard hits.count >= 2 else { return hits }
        var out: [DayHit] = [hits[0]]
        for hit in hits.dropFirst() {
            let previous = out[out.count - 1]
            if isCorrectionSpan(ctx, from: previous.end + 1, to: hit.start - 1) {
                ctx.consume(previous.end + 1, hit.start - 1)
                ctx.flags.insert(.correctionApplied)
                out[out.count - 1] = hit
            } else {
                out.append(hit)
            }
        }
        return out
    }

    /// Tokens a...b (non-empty, all usable) consist only of correction markers ("hayır", "yok", "değil de" …).
    static func isCorrectionSpan(_ ctx: ParseContext, from a: Int, to b: Int) -> Bool {
        guard a <= b else { return false }
        for k in a...b where !ctx.usable(k) {
            return false
        }
        var k = a
        while k <= b {
            var matched = false
            for marker in Lexicon.correctionMarkers {
                let e = ctx.matchSequence(k, marker)
                if e >= 0 && e <= b {
                    k = e + 1
                    matched = true
                    break
                }
            }
            if !matched {
                return false
            }
        }
        return true
    }

    // MARK: Resolution helpers (§8.3)

    /// qualifier: nil (strictly after today), "this", "next", "nextweek", "past".
    static func resolveWeekday(_ ctx: ParseContext, _ weekday: Int, _ qualifier: String?) -> Date {
        let today = ctx.today
        let current = ctx.isoWeekday(today)
        switch qualifier {
        case "this"?:
            return ctx.addDays((weekday - current + 7) % 7, to: today)
        case "nextweek"?:
            return ctx.addDays(7 + (weekday - 1), to: ctx.weekStart(today))
        case "past"?:
            var delta = (current - weekday + 7) % 7
            if delta == 0 {
                delta = 7
            }
            return ctx.addDays(-delta, to: today)
        default:
            var delta = (weekday - current + 7) % 7
            if delta == 0 {
                delta = 7
            }
            return ctx.addDays(delta, to: today)
        }
    }

    /// Day `n` of this month if not passed, else of next month (clamped to the month length).
    static func thisOrNextMonthDay(_ ctx: ParseContext, _ n: Int) -> (day: Date, clamped: Bool) {
        let c = ctx.components(ctx.today)
        let last = ctx.daysInMonth(year: c.year, month: c.month)
        if let candidate = ctx.makeDay(c.year, c.month, min(n, last)), candidate >= ctx.today {
            return (candidate, n > last)
        }
        var year = c.year
        var month = c.month + 1
        if month > 12 {
            month = 1
            year += 1
        }
        let nextLast = ctx.daysInMonth(year: year, month: month)
        let day = ctx.makeDay(year, month, min(n, nextLast)) ?? ctx.today
        return (day, n > nextLast)
    }

    /// "15 ekim" → this year, or next year when passed (`rolledToNextYear`). nil = impossible date.
    static func monthDate(_ ctx: ParseContext, day: Int, month: Int, year: Int?) -> (date: Date, flags: Set<ParseFlag>)? {
        if let explicitYear = year {
            guard let date = ctx.makeDay(explicitYear, month, day) else { return nil }
            return (date, [])
        }
        guard day >= 1 && day <= 31, ParserDates.isValid(2024, month, day, calendar: ctx.calendar) else { return nil }
        let thisYear = ctx.components(ctx.today).year
        if let candidate = ctx.makeDay(thisYear, month, day), candidate >= ctx.today {
            return (candidate, [])
        }
        var year = thisYear + 1
        while year < thisYear + 9 {
            if let candidate = ctx.makeDay(year, month, day) {
                return (candidate, [.rolledToNextYear])
            }
            year += 1
        }
        return nil
    }

    /// "ekim başı / ortası / sonu" (this year; next year when passed).
    static func monthPositionDate(_ ctx: ParseContext, month: Int, position: Int) -> (date: Date, flags: Set<ParseFlag>) {
        let thisYear = ctx.components(ctx.today).year
        func make(_ year: Int) -> Date {
            let day: Int
            if position == 0 {
                day = 1
            } else if position == 1 {
                day = 15
            } else {
                day = ctx.daysInMonth(year: year, month: month)
            }
            return ctx.makeDay(year, month, day) ?? ctx.today
        }
        let candidate = make(thisYear)
        if candidate < ctx.today {
            return (make(thisYear + 1), [.rolledToNextYear])
        }
        return (candidate, [])
    }

    /// First day on/after `from` that is the `ordinal`-th (-1 = last) `weekday` of its month.
    static func nthWeekdayDate(_ ctx: ParseContext, ordinal: Int, weekday: Int, from: Date) -> Date {
        let start = ctx.calendar.startOfDay(for: from)
        let c = ctx.components(start)
        var year = c.year
        var month = c.month
        for _ in 0..<14 {
            if let candidate = nthWeekdayInMonth(ctx, ordinal: ordinal, weekday: weekday, year: year, month: month),
               candidate >= start {
                return candidate
            }
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
        return start
    }

    static func nthWeekdayInMonth(_ ctx: ParseContext, ordinal: Int, weekday: Int, year: Int, month: Int) -> Date? {
        if ordinal == -1 {
            let lastDay = ctx.daysInMonth(year: year, month: month)
            guard let last = ctx.makeDay(year, month, lastDay) else { return nil }
            let delta = (ctx.isoWeekday(last) - weekday + 7) % 7
            return ctx.addDays(-delta, to: last)
        }
        guard let first = ctx.makeDay(year, month, 1) else { return nil }
        let delta = (weekday - ctx.isoWeekday(first) + 7) % 7
        let candidate = ctx.addDays(delta + 7 * (ordinal - 1), to: first)
        guard ctx.components(candidate).month == month else { return nil }
        return candidate
    }

    // MARK: Matching (first matching rule wins; each rule consumes its tokens)

    /// "gününde", "günkü" after a weekday → (end, isFilter).
    static func weekdayGlue(_ ctx: ParseContext, _ end: Int) -> (end: Int, isFilter: Bool) {
        let next = ctx.usablePlain(end + 1)
        if next == "gunu" || next == "gununde" || next == "gunune" {
            return (end + 1, false)
        }
        if next == "gunku" || next == "gunki" {
            return (end + 1, true)
        }
        return (end, false)
    }

    /// 02 §5.2 "pazar" (Sunday / market) rules.
    static func pazarIsWeekday(_ ctx: ParseContext, _ i: Int, _ suffix: String) -> Bool {
        let next = ctx.plain(i + 1)
        if ["gunu", "gununde", "gunleri", "gunku", "gunki"].contains(next) {
            return true
        }
        if i > 0 && ["bu", "gelecek", "onumuzdeki", "haftaya", "her"].contains(ctx.plain(i - 1)) {
            return true
        }
        if suffix.isEmpty && startsTimePhrase(ctx, i + 1) {
            return true
        }
        if suffix == "a" || suffix == "dan" {
            let triggers = Lexicon.arriveTriggers + Lexicon.leaveTriggers
            if i + 1 < ctx.count && ctx.matchAny(i + 1, triggers) >= 0 {
                return false
            }
            return true
        }
        return false
    }

    static func startsTimePhrase(_ ctx: ParseContext, _ j: Int) -> Bool {
        guard j >= 0 && j < ctx.count else { return false }
        let token = ctx.tokens[j]
        if TokenMatch.daypart(token) != nil || token.plain == "saat" {
            return true
        }
        if let number = token.number {
            switch number {
            case .clock, .dotted:
                return true
            case .integer:
                return Lexicon.locative.contains(token.suffix) || Lexicon.dative.contains(token.suffix)
            default:
                return false
            }
        }
        if let word = TurkishNumbers.wordNumber(of: token) {
            return ["de", "da", "te", "ta"].contains(word.suffix)
        }
        return false
    }

    static func finishAbsolute(_ ctx: inout ParseContext, _ a: Int, _ b: Int,
                               _ resolved: (date: Date, flags: Set<ParseFlag>)?) -> DayHit? {
        guard let value = resolved else {
            ctx.flags.insert(.invalidDateTime)
            ctx.protect(a, b, invalid: true)
            return nil
        }
        var hit = DayHit(day: value.date, start: a, end: b)
        hit.flags = value.flags
        ctx.consume(a, b)
        if Lexicon.dateGlueWords.contains(ctx.usablePlain(b + 1)) {
            ctx.consume(b + 1, b + 1)
            hit.end = b + 1
        }
        return hit
    }

    static func dayExpression(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        if let hit = qualifiedWeekday(&ctx, i) {
            return hit
        }
        if let hit = dayWord(&ctx, i) {
            return hit
        }
        if let hit = weekAndMonthWord(&ctx, i) {
            return hit
        }
        if let hit = dayOfMonth(&ctx, i) {
            return hit
        }
        if let hit = numericDate(&ctx, i) {
            return hit
        }
        if let hit = numberMonth(&ctx, i) {
            return hit
        }
        if let hit = monthExpression(&ctx, i) {
            return hit
        }
        return bareWeekday(&ctx, i)
    }

    /// "bu salı", "gelecek cuma", "haftaya salı", "gelecek hafta salı", "geçen salı".
    static func qualifiedWeekday(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let word = ctx.plain(i)
        let next = ctx.usablePlain(i + 1)
        var qualifier: String? = nil
        var length = 0
        if (word == "gelecek" || word == "onumuzdeki") && next == "hafta" && ctx.usable(i + 2)
            && TokenMatch.weekday(ctx.tokens[i + 2]) != nil {
            qualifier = "nextweek"
            length = 2
        } else if let q = Lexicon.weekdayQualifiers[word], ctx.usable(i + 1),
                  TokenMatch.weekday(ctx.tokens[i + 1]) != nil {
            qualifier = q
            length = 1
        }
        guard let qual = qualifier,
              let weekday = TokenMatch.weekday(ctx.tokens[i + length]),
              !Lexicon.pluralDays.contains(weekday.suffix) else { return nil }
        let day = resolveWeekday(ctx, weekday.iso, qual)
        let glue = weekdayGlue(ctx, i + length)
        var hit = DayHit(day: day, start: i, end: glue.end)
        hit.isFilter = glue.isFilter
        if qual == "past" {
            hit.flags.insert(.pastDue)
        }
        if qual == "this" && day == ctx.today {
            hit.explicitToday = true
        }
        let todayIso = ctx.isoWeekday(ctx.today)
        if qual == "nextweek" && (todayIso == 6 || todayIso == 7) {
            hit.flags.insert(.nextWeekAmbiguous)
        }
        hit.endsWithDative = TokenMatch.isDative(weekday.suffix)
        ctx.consume(i, glue.end)
        return hit
    }

    /// bugün, yarın, öbür gün, dün, ertesi gün, haftaya bugün …
    static func dayWord(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let token = ctx.tokens[i]
        let word = token.plain
        let next = ctx.usablePlain(i + 1)
        let afterNext = ctx.usablePlain(i + 2)
        let today = ctx.today
        if word == "haftaya" && next == "bugun" {
            ctx.consume(i, i + 1)
            return DayHit(day: ctx.addDays(7, to: today), start: i, end: i + 1)
        }
        if word == "yarindan" && next == "sonra" {
            ctx.consume(i, i + 1)
            return DayHit(day: ctx.addDays(2, to: today), start: i, end: i + 1)
        }
        if word == "obur" && (next == "gun" || next == "gune" || next == "gunu") {
            var hit = DayHit(day: ctx.addDays(2, to: today), start: i, end: i + 1)
            hit.endsWithDative = next == "gune"
            ctx.consume(i, i + 1)
            return hit
        }
        if word == "oburgun" || word == "oburgune" {
            ctx.consume(i, i)
            return DayHit(day: ctx.addDays(2, to: today), start: i, end: i)
        }
        if word == "ertesi" && (next == "gun" || next == "gunu") {
            var hit = DayHit(day: ctx.addDays(1, to: today), start: i, end: i + 1)
            hit.flags.insert(.vagueDate)
            ctx.consume(i, i + 1)
            return hit
        }
        if word == "evvelsi" && (next == "gun" || next == "gunu") {
            var hit = DayHit(day: ctx.addDays(-2, to: today), start: i, end: i + 1)
            hit.flags.insert(.pastDue)
            ctx.consume(i, i + 1)
            return hit
        }
        if word == "bu" && next == "gun" {
            var hit = DayHit(day: today, start: i, end: i + 1, scope: .today)
            hit.explicitToday = true
            ctx.consume(i, i + 1)
            return hit
        }
        if let suffix = TokenMatch.suffix(token, "bugun", ["", "e", "ku", "ki", "den", "u"]) {
            var hit = DayHit(day: today, start: i, end: i, scope: .today)
            hit.explicitToday = true
            if next == "icinde" {
                hit.end = i + 1
            } else if next == "bir" && afterNext == "ara" {
                hit.end = i + 2
            }
            hit.isFilter = suffix == "ku" || suffix == "ki"
            hit.endsWithDative = suffix == "e"
            ctx.consume(i, hit.end)
            return hit
        }
        if word == "gun" && next == "icinde" {
            var hit = DayHit(day: today, start: i, end: i + 1, scope: .today)
            hit.explicitToday = true
            ctx.consume(i, i + 1)
            return hit
        }
        if let suffix = TokenMatch.suffix(token, "yarin", ["", "a", "ki", "dan", "in"]) {
            var hit = DayHit(day: ctx.addDays(1, to: today), start: i, end: i, scope: .tomorrow)
            hit.isFilter = suffix == "ki"
            hit.endsWithDative = suffix == "a"
            ctx.consume(i, i)
            return hit
        }
        if word == "dun" || word == "dunku" {
            var hit = DayHit(day: ctx.addDays(-1, to: today), start: i, end: i)
            hit.flags.insert(.pastDue)
            hit.isFilter = word == "dunku"
            ctx.consume(i, i)
            return hit
        }
        return nil
    }

    /// hafta sonu/başı/ortası, bu hafta (G9), haftaya / gelecek hafta (P1), gelecek ay, seneye, ay sonu/başı/ortası,
    /// yıl sonu, yılbaşı.
    static func weekAndMonthWord(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let word = ctx.plain(i)
        let next = ctx.usablePlain(i + 1)
        let afterNext = ctx.usablePlain(i + 2)
        let today = ctx.today
        let c = ctx.components(today)

        if (word == "hafta" && ["sonu", "sonunda", "sonuna"].contains(next)) || word == "haftasonu"
            || word == "haftasonunda" {
            let end = word == "hafta" ? i + 1 : i
            let current = ctx.isoWeekday(today)
            let delta = current == 7 ? 6 : (6 - current + 7) % 7
            var hit = DayHit(day: ctx.addDays(delta, to: today), start: i, end: end)
            hit.endsWithDative = ctx.plain(end) == "sonuna"
            ctx.consume(i, end)
            return hit
        }
        if (word == "hafta" && ["basi", "basinda", "basina"].contains(next))
            || (word == "haftaya" && next == "basinda") || (word == "haftanin" && next == "basinda") {
            ctx.consume(i, i + 1)
            return DayHit(day: resolveWeekday(ctx, 1, nil), start: i, end: i + 1)
        }
        if word == "hafta" && (next == "ortasi" || next == "ortasinda") {
            var hit = DayHit(day: resolveWeekday(ctx, 3, nil), start: i, end: i + 1)
            hit.flags.insert(.vagueDate)
            ctx.consume(i, i + 1)
            return hit
        }
        // G9: "bu hafta (içinde)" / "hafta bitmeden" → this week's last workday (Friday), vague.
        if (word == "bu" && next == "hafta") || (word == "hafta" && next == "bitmeden") {
            var end = i + 1
            if word == "bu" && (afterNext == "icinde" || afterNext == "icerisinde") {
                end = i + 2
            }
            var friday = ctx.addDays(4, to: ctx.weekStart(today))
            if friday < today {
                friday = ctx.addDays(7, to: friday)
            }
            var hit = DayHit(day: friday, start: i, end: end, scope: .thisWeek)
            hit.flags.insert(.vagueDate)
            hit.explicitToday = friday == today
            ctx.consume(i, end)
            return hit
        }
        // P1: "haftaya" / "gelecek hafta" without weekday → next week's first workday (Monday).
        if ((word == "gelecek" || word == "onumuzdeki") && (next == "hafta" || next == "haftaya")) || word == "haftaya" {
            let end = word == "haftaya" ? i : i + 1
            var hit = DayHit(day: ctx.addDays(7, to: ctx.weekStart(today)), start: i, end: end, scope: .nextWeek)
            if word != "haftaya" {
                hit.flags.insert(.vagueDate)
            }
            hit.endsWithDative = word == "haftaya" || next == "haftaya"
            ctx.consume(i, end)
            return hit
        }
        if (word == "gelecek" || word == "onumuzdeki") && next == "ay" {
            if afterNext == "basi" || afterNext == "basinda" {
                let firstOfMonth = ctx.makeDay(c.year, c.month, 1) ?? today
                ctx.consume(i, i + 2)
                return DayHit(day: ctx.addMonths(1, to: firstOfMonth), start: i, end: i + 2)
            }
            var hit = DayHit(day: ctx.addMonths(1, to: today), start: i, end: i + 1)
            hit.flags.insert(.vagueDate)
            ctx.consume(i, i + 1)
            return hit
        }
        if word == "seneye" || (word == "gelecek" && (next == "yil" || next == "sene")) {
            let end = word == "seneye" ? i : i + 1
            var hit = DayHit(day: ctx.addYears(1, to: today), start: i, end: end)
            hit.flags.insert(.vagueDate)
            ctx.consume(i, end)
            return hit
        }
        let lastOfMonth = ctx.makeDay(c.year, c.month, ctx.daysInMonth(year: c.year, month: c.month)) ?? today
        if (word == "ay" && ["sonu", "sonunda", "sonuna"].contains(next))
            || (word == "ayin" && (next == "sonunda" || next == "sonu")) {
            ctx.consume(i, i + 1)
            return DayHit(day: lastOfMonth, start: i, end: i + 1)
        }
        if word == "ayin" && next == "son" && ["gunu", "gununde", "gun"].contains(afterNext) {
            ctx.consume(i, i + 2)
            return DayHit(day: lastOfMonth, start: i, end: i + 2)
        }
        if (word == "ay" && ["basi", "basinda", "basina"].contains(next))
            || (word == "ayin" && (next == "basinda" || next == "basi")) {
            let firstOfMonth = ctx.makeDay(c.year, c.month, 1) ?? today
            ctx.consume(i, i + 1)
            return DayHit(day: ctx.addMonths(1, to: firstOfMonth), start: i, end: i + 1)
        }
        if (word == "ay" || word == "ayin") && (next == "ortasi" || next == "ortasinda") {
            ctx.consume(i, i + 1)
            return DayHit(day: thisOrNextMonthDay(ctx, 15).day, start: i, end: i + 1)
        }
        if (word == "yil" || word == "sene") && ["sonu", "sonunda", "sonuna"].contains(next) {
            ctx.consume(i, i + 1)
            return DayHit(day: ctx.makeDay(c.year, 12, 31) ?? today, start: i, end: i + 1)
        }
        if ["yilbasi", "yilbasinda", "yilbasina"].contains(word) || (word == "yil" && (next == "basi" || next == "basinda")) {
            let end = word.hasPrefix("yilbasi") ? i : i + 1
            ctx.consume(i, end)
            return DayHit(day: ctx.makeDay(c.year + 1, 1, 1) ?? today, start: i, end: end)
        }
        return nil
    }

    /// Day `n` of this month (shift 0) or next month (shift 1), clamped to the month length.
    static func shiftedMonthDay(_ ctx: ParseContext, _ n: Int, shift: Int) -> (day: Date, clamped: Bool) {
        let c = ctx.components(ctx.today)
        var year = c.year
        var month = c.month + shift
        if month > 12 {
            month -= 12
            year += 1
        }
        let last = ctx.daysInMonth(year: year, month: month)
        let day = ctx.makeDay(year, month, min(n, last)) ?? ctx.today
        return (day, n > last)
    }

    /// "ayın 15'i / 15'inde / biri / ilk günü / ilk pazartesi", optionally "gelecek/önümüzdeki/bu ayın …".
    static func dayOfMonth(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let word = ctx.plain(i)
        var ayinIndex = i
        var shift: Int? = nil
        if (word == "gelecek" || word == "onumuzdeki") && ctx.usablePlain(i + 1) == "ayin" {
            ayinIndex = i + 1
            shift = 1
        } else if word == "bu" && ctx.usablePlain(i + 1) == "ayin" {
            ayinIndex = i + 1
            shift = 0
        }
        guard ctx.plain(ayinIndex) == "ayin", ayinIndex + 1 < ctx.count else { return nil }
        let k = ayinIndex + 1
        let next = ctx.usablePlain(k)
        let afterNext = ctx.usablePlain(k + 1)
        let dayForms = Lexicon.joined([Lexicon.possessive3, Lexicon.possessive3Locative, Lexicon.possessive3Dative,
                                       Lexicon.ordinal])
        if let number = ctx.numberPhrase(at: k), dayForms.contains(number.suffix) {
            if number.value >= 1 && number.value <= 31 {
                var resolved = thisOrNextMonthDay(ctx, number.value)
                if let monthShift = shift {
                    resolved = shiftedMonthDay(ctx, number.value, shift: monthShift)
                }
                var hit = DayHit(day: resolved.day, start: i, end: number.end)
                if resolved.clamped {
                    hit.flags.insert(.vagueDate)
                }
                ctx.consume(i, number.end)
                return hit
            }
            ctx.flags.insert(.invalidDateTime)
            ctx.protect(i, number.end, invalid: true)
            return nil
        }
        if next == "ilk" && ["gunu", "gununde", "gun"].contains(afterNext) {
            var first = thisOrNextMonthDay(ctx, 1).day
            if let monthShift = shift {
                first = shiftedMonthDay(ctx, 1, shift: monthShift).day
            }
            ctx.consume(i, k + 1)
            return DayHit(day: first, start: i, end: k + 1)
        }
        if let ordinal = Lexicon.ordinalWords[next], ctx.usable(k + 1),
           let weekday = TokenMatch.weekday(ctx.tokens[k + 1]) {
            var from = ctx.today
            if let monthShift = shift {
                from = shiftedMonthDay(ctx, 1, shift: monthShift).day
            }
            let day = nthWeekdayDate(ctx, ordinal: ordinal, weekday: weekday.iso, from: from)
            ctx.consume(i, k + 1)
            return DayHit(day: day, start: i, end: k + 1)
        }
        return nil
    }

    /// dd.mm.yyyy, dd/mm(/yyyy), dotted a.b read as a date (§8.6).
    static func numericDate(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let token = ctx.tokens[i]
        guard let number = token.number else { return nil }
        switch number {
        case .dottedDate(let d, let m, let y):
            let resolved = monthDate(ctx, day: d, month: m, year: y)
            return finishAbsolute(&ctx, i, i, resolved)
        case .slashDate(let d, let m, let y):
            let resolved = monthDate(ctx, day: d, month: m, year: y)
            return finishAbsolute(&ctx, i, i, resolved)
        case .dotted(let a, let b):
            let previousIsTimeWord = i > 0 && (ctx.plain(i - 1) == "saat" || TokenMatch.daypart(ctx.tokens[i - 1]) != nil
                || ctx.dayparts.contains(where: { $0.end == i - 1 }))
            let hasTimeSuffix = Lexicon.locative.contains(token.suffix) || Lexicon.dative.contains(token.suffix)
            let timeLike = previousIsTimeWord || hasTimeSuffix || b > 12 || b == 0
            guard !timeLike, b >= 1 && b <= 12, a >= 1 && a <= 31 else { return nil }
            guard let resolved = monthDate(ctx, day: a, month: b, year: nil) else {
                return finishAbsolute(&ctx, i, i, nil)
            }
            var hit = DayHit(day: resolved.date, start: i, end: i)
            hit.flags = resolved.flags
            let next = ctx.usablePlain(i + 1)
            if ["tarihinde", "tarihli", "tarihine", "tarihe", "gunu", "tarihinden"].contains(next) {
                ctx.consume(i, i + 1)
                hit.end = i + 1
            } else {
                hit.dottedCandidate = true
                ctx.consume(i, i)
            }
            return hit
        default:
            return nil
        }
    }

    /// "15 ekim", "15 Ekim 2027'de", "on beş ekimde", "15. ekim".
    static func numberMonth(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        let dayForms = Lexicon.joined([[""], Lexicon.ordinal, Lexicon.possessive3])
        guard let number = ctx.numberPhrase(at: i), dayForms.contains(number.suffix), !number.isHalf else { return nil }
        let monthIndex = number.end + 1
        guard ctx.usable(monthIndex), let month = TokenMatch.month(ctx.tokens[monthIndex]) else { return nil }
        // "bir aralık" (at some point), "bir ocak" (a stove), "bir nisan" — homonyms (02 §5.3), not dates.
        if number.isWord && number.value == 1 && number.start == number.end
            && (month.month == 1 || month.month == 4 || month.month == 12) {
            return nil
        }
        var end = monthIndex
        var year: Int? = nil
        if month.suffix.isEmpty, ctx.usable(end + 1), let value = ctx.tokens[end + 1].integerValue,
           value >= 1900 && value <= 2199 {
            year = value
            end += 1
        }
        guard number.value >= 1 && number.value <= 31 else {
            ctx.flags.insert(.invalidDateTime)
            ctx.protect(i, end, invalid: true)
            return nil
        }
        let resolved = monthDate(ctx, day: number.value, month: month.month, year: year)
        guard var hit = finishAbsolute(&ctx, i, end, resolved) else {
            return nil
        }
        hit.endsWithDative = TokenMatch.isDative(month.suffix)
        return hit
    }

    /// "ekimin 15'i", "şubatın son günü", "ekim başı/ortası/sonu", "ekimde" (month only, vague).
    static func monthExpression(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        guard let month = TokenMatch.month(ctx.tokens[i]) else { return nil }
        let next = ctx.usablePlain(i + 1)
        let afterNext = ctx.usablePlain(i + 2)
        if Lexicon.genitive.contains(month.suffix) {
            let dayForms = Lexicon.joined([Lexicon.possessive3, Lexicon.possessive3Locative, Lexicon.possessive3Dative])
            if let number = ctx.numberPhrase(at: i + 1), dayForms.contains(number.suffix) {
                let resolved = monthDate(ctx, day: number.value, month: month.month, year: nil)
                return finishAbsolute(&ctx, i, number.end, resolved)
            }
            if next == "son" && (afterNext == "gunu" || afterNext == "gununde") {
                let resolved = monthPositionDate(ctx, month: month.month, position: 2)
                var hit = DayHit(day: resolved.date, start: i, end: i + 2)
                hit.flags = resolved.flags
                ctx.consume(i, i + 2)
                return hit
            }
        }
        if month.suffix.isEmpty {
            var position = -1
            if Lexicon.monthStartWords.contains(next) {
                position = 0
            } else if Lexicon.monthMiddleWords.contains(next) {
                position = 1
            } else if Lexicon.monthEndWords.contains(next) {
                position = 2
            }
            if position >= 0 {
                let resolved = monthPositionDate(ctx, month: month.month, position: position)
                var hit = DayHit(day: resolved.date, start: i, end: i + 1)
                hit.flags = resolved.flags
                ctx.consume(i, i + 1)
                return hit
            }
        }
        let isLocativeOrDative = Lexicon.locative.contains(month.suffix) || Lexicon.dative.contains(month.suffix)
        if (isLocativeOrDative && !month.suffix.isEmpty) || (month.suffix.isEmpty && Lexicon.monthAyiWords.contains(next)) {
            let end = month.suffix.isEmpty ? i + 1 : i
            var day = ctx.today
            var flags: Set<ParseFlag> = []
            if ctx.components(ctx.today).month != month.month {
                let resolved = monthPositionDate(ctx, month: month.month, position: 0)
                day = resolved.date
                flags = resolved.flags
            }
            var hit = DayHit(day: day, start: i, end: end)
            hit.flags = flags
            hit.flags.insert(.vagueDate)
            hit.endsWithDative = TokenMatch.isDative(month.suffix)
            ctx.consume(i, end)
            return hit
        }
        return nil
    }

    /// "salı", "cumaya", "perşembe günü", "cuma günkü" (strictly after today, §8.3).
    static func bareWeekday(_ ctx: inout ParseContext, _ i: Int) -> DayHit? {
        guard let weekday = TokenMatch.weekday(ctx.tokens[i]), !Lexicon.pluralDays.contains(weekday.suffix) else {
            return nil
        }
        if weekday.iso == 7 && (weekday.suffix.isEmpty || weekday.suffix == "a" || weekday.suffix == "dan")
            && !pazarIsWeekday(ctx, i, weekday.suffix) {
            return nil
        }
        let glue = weekdayGlue(ctx, i)
        var hit = DayHit(day: resolveWeekday(ctx, weekday.iso, nil), start: i, end: glue.end)
        hit.isFilter = glue.isFilter || Lexicon.ki.contains(weekday.suffix)
        hit.endsWithDative = TokenMatch.isDative(weekday.suffix)
        ctx.consume(i, glue.end)
        return hit
    }
}
