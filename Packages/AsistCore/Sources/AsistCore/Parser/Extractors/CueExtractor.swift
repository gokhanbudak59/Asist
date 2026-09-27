// Prefix markers (02 §7.1), priority (02 §7.8 + C2), fillers (02 §5.6) and command cues (02 §10.5 + G3–G6).
import Foundation

struct QueryMatch {
    var scope: QueryScope?
    var start: Int
    var end: Int
    var queryText: String?
    var phrase: [String]?
}

struct CommandMatch {
    var command: ParsedCommand
    var cueStart: Int
    var cueEnd: Int
    /// Kind certainty in hundredths (02 §10.1: 100 / 90 content verbs / 85 generic past).
    var certainty: Int
    /// Content-verb completion stem appended to queryText ("ara", "gönder" …).
    var stem: String?
}

enum CueExtractor {
    // MARK: - Helpers

    /// `hatırlat*` verb forms, excluding the object nouns "hatırlatma…", "hatırlatıcı…" (02 §10.2).
    static func isHatirlaVerb(_ token: Token) -> Bool {
        let word = token.plain
        guard word.hasPrefix("hatirla") else { return false }
        for prefix in Lexicon.reminderObjectNounPrefixes where word.hasPrefix(prefix) {
            return false
        }
        return true
    }

    static func isFiller(_ token: Token) -> Bool {
        return Lexicon.fillers.contains(token.plain) || Lexicon.fillersLower.contains(token.lower)
    }

    /// Last usable token that is not a trailing filler/pronoun (02 §10.5 "last verb phrase"), or -1.
    static func lastContentIndex(_ ctx: ParseContext) -> Int {
        var last = ctx.count - 1
        while last >= 0 {
            if ctx.usable(last) && !Lexicon.tailSkip.contains(ctx.tokens[last].plain)
                && !Lexicon.fillersLower.contains(ctx.tokens[last].lower) {
                return last
            }
            last -= 1
        }
        return -1
    }

    /// Usable, non-filler tokens (project tokens are protected and therefore excluded).
    static func contentIndices(_ ctx: ParseContext, skipping skip: Set<Int> = []) -> [Int] {
        var out: [Int] = []
        for j in 0..<ctx.count where ctx.usable(j) && !skip.contains(j) && !isFiller(ctx.tokens[j]) {
            out.append(j)
        }
        return out
    }

    /// Consumes every occurrence of the phrases; true when at least one was found.
    @discardableResult
    static func consumePhrases(_ ctx: inout ParseContext, _ phrases: [[String]]) -> Bool {
        var found = false
        var guardCounter = 0
        while let match = ctx.findPhrase(phrases), guardCounter < 64 {
            ctx.consume(match.start, match.end)
            found = true
            guardCounter += 1
        }
        return found
    }

    /// Dative-looking content ("Ahmet'e", "müşteriye", "ekibine") — an indirect object that is not the user.
    static func isDativeLike(_ token: Token) -> Bool {
        if token.hadApostrophe {
            return Lexicon.dative.contains(token.suffix)
        }
        let word = token.plain
        for ending in ["ye", "ya", "sine", "sina", "ine", "ina", "une", "una"]
            where word.hasSuffix(ending) && word.count > ending.count + 1 {
            return true
        }
        return false
    }

    // MARK: - Prefix markers (§7.1)

    static func extractPrefix(_ ctx: inout ParseContext) {
        guard ctx.count > 0 else { return }
        let first = ctx.tokens[0]
        let word = first.plain
        let punctuated = first.trailingPunct == ":" || first.trailingPunct == ","
        let second = ctx.plain(1)
        if word == "not" || word == "nota" {
            if punctuated {
                ctx.prefixKind = .note
                ctx.consume(0, 0)
            } else if word == "not" && ctx.count >= 2 && second == "al"
                        && (ctx.tokens[1].trailingPunct == ":" || ctx.tokens[1].trailingPunct == ",") {
                ctx.prefixKind = .note
                ctx.consume(0, 1)
            } else if word == "not" && ctx.count >= 3 && !Lexicon.notePrefixBlock.contains(second) {
                ctx.prefixKind = .note
                ctx.consume(0, 0)
            }
        } else if word == "fikir" {
            if punctuated || (ctx.count >= 3 && !Lexicon.notePrefixBlock.contains(second)) {
                ctx.prefixKind = .note
                ctx.tags.append("fikir")
                ctx.consume(0, 0)
            }
        } else if ["gorev", "yapilacak", "yapilacaklar", "is"].contains(word) && punctuated {
            ctx.prefixKind = .task
            ctx.consume(0, 0)
        } else if word == "bekliyorum" && punctuated {
            ctx.prefixKind = .waiting
            ctx.consume(0, 0)
        } else if word == "bilgi" && first.trailingPunct == ":" {
            ctx.prefixKind = .note
            ctx.consume(0, 0)
        }
    }

    // MARK: - Priority (§7.8, C2)

    static func extractPriority(_ ctx: inout ParseContext) {
        var excluded = Set<Int>()
        for i in 0..<ctx.count {
            for exception in Lexicon.priorityExceptions where i + exception.count <= ctx.count {
                var matches = true
                for k in 0..<exception.count {
                    let word = ctx.tokens[i + k].plain
                    let isLast = k == exception.count - 1
                    if !(word == exception[k] || (isLast && word.hasPrefix(exception[k]))) {
                        matches = false
                        break
                    }
                }
                if matches {
                    for k in 0..<exception.count {
                        excluded.insert(i + k)
                    }
                }
            }
        }
        var levels: [Priority] = []
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i), !excluded.contains(i) else {
                i += 1
                continue
            }
            var best: PriorityPhrase? = nil
            var bestEnd = -1
            for phrase in Lexicon.priorityPhrases {
                let e = ctx.matchSequence(i, phrase.words)
                guard e >= 0, phrase.words.count > (best?.words.count ?? 0) else { continue }
                var clear = true
                for k in i...e where excluded.contains(k) {
                    clear = false
                }
                if clear {
                    best = phrase
                    bestEnd = e
                }
            }
            guard let phrase = best else {
                i += 1
                continue
            }
            levels.append(phrase.level)
            var remove = phrase.alwaysRemove
            if !remove {
                var firstUsable = -1
                var lastUsable = -1
                for k in 0..<ctx.count where ctx.usable(k) {
                    if firstUsable < 0 {
                        firstUsable = k
                    }
                    lastUsable = k
                }
                if firstUsable == i || lastUsable == bestEnd || ctx.tokens[bestEnd].trailingPunct == ":" {
                    remove = true
                }
            }
            if remove {
                ctx.consume(i, bestEnd)
                for k in i...bestEnd {
                    ctx.priorityTokens.insert(k)
                }
            }
            if phrase.isReminderCue {
                ctx.priorityCue = true
                ctx.verbCue = true
            }
            i = bestEnd + 1
        }
        if let highest = levels.max() {
            ctx.priority = highest
        }
    }

    // MARK: - Fillers (§5.6)

    static func consumeFillers(_ ctx: inout ParseContext) {
        for j in 0..<ctx.count where ctx.usable(j) && isFiller(ctx.tokens[j]) {
            ctx.consume(j, j)
        }
        consumePhrases(&ctx, Lexicon.fillerPhrases)
    }

    // MARK: - Waiting verbs (§10.4 + G2)

    static func hasBekleVerb(_ ctx: ParseContext) -> Bool {
        for j in 0..<ctx.count where ctx.usable(j) && Lexicon.waitingBekle.contains(ctx.tokens[j].plain) {
            return true
        }
        return false
    }

    /// Final 3rd-person future waiting verb ("gönderecek", "haber verecek", final "gelecek").
    static func finalWaitingVerb(_ ctx: ParseContext) -> (start: Int, end: Int, isGelecek: Bool)? {
        let last = lastContentIndex(ctx)
        guard last >= 0 else { return nil }
        let start = ctx.phraseEnding(at: last, Lexicon.waitingFuture)
        guard start >= 0 else { return nil }
        return (start, last, ctx.plain(last) == "gelecek")
    }

    // MARK: - Commands (T1)

    static func isQueryNeutral(_ ctx: ParseContext, _ j: Int) -> Bool {
        let word = ctx.tokens[j].plain
        if Lexicon.queryObjectWords.contains(word) || Lexicon.queryScopeWords[word] != nil
            || Lexicon.queryGlue.contains(word) || Lexicon.questionParticles.contains(word) {
            return true
        }
        if let person = ctx.person, j >= person.start && j <= person.end {
            return true
        }
        return ctx.tokens[j].root == "ilgili"
    }

    static func remainingContent(_ ctx: ParseContext, skipping skip: Set<Int>) -> [Int] {
        return contentIndices(ctx, skipping: skip).filter { !isQueryNeutral(ctx, $0) }
    }

    static func detectQuery(_ ctx: ParseContext) -> QueryMatch? {
        // G6: "ne(yi|leri) unuttum / kaçırdım / atladım" — before the generic -DIm completion rule.
        for i in 0..<ctx.count where ctx.usable(i) && Lexicon.overdueQuestionWords.contains(ctx.tokens[i].plain) {
            guard Lexicon.overdueQuestionVerbs.contains(ctx.usablePlain(i + 1)) else { continue }
            if remainingContent(ctx, skipping: [i, i + 1]).isEmpty {
                return QueryMatch(scope: .overdue, start: i, end: i + 1, queryText: nil, phrase: nil)
            }
        }
        var varMi: (start: Int, end: Int)? = nil
        if ctx.count >= 2 {
            for i in 0..<(ctx.count - 1) where ctx.usablePlain(i) == "var" {
                let particle = ctx.usablePlain(i + 1)
                if particle == "mi" || particle == "mu" || particle == "midir" {
                    varMi = (i, i + 1)
                }
            }
        }
        var phraseMatch: (start: Int, end: Int, words: [String])? = nil
        for i in 0..<ctx.count {
            var bestLength = 0
            for phrase in Lexicon.queryPhrases {
                let e = ctx.matchSequence(i, phrase)
                if e >= 0 && phrase.count > bestLength {
                    phraseMatch = (i, e, phrase)
                    bestLength = phrase.count
                }
            }
            if phraseMatch != nil {
                break
            }
        }
        if phraseMatch == nil && varMi == nil {
            // "gecikenler", "bu hafta bekleyenler" — a scope word alone.
            for j in 0..<ctx.count where ctx.usable(j) && Lexicon.queryScopeWords[ctx.tokens[j].plain] != nil {
                if remainingContent(ctx, skipping: []).isEmpty {
                    return QueryMatch(scope: nil, start: j, end: j, queryText: nil, phrase: nil)
                }
                break
            }
            return nil
        }
        if let match = phraseMatch {
            var skip = Set<Int>()
            for k in match.start...match.end {
                skip.insert(k)
            }
            if remainingContent(ctx, skipping: skip).isEmpty {
                return QueryMatch(scope: nil, start: match.start, end: match.end, queryText: nil, phrase: match.words)
            }
        }
        if let question = varMi {
            let rest = remainingContent(ctx, skipping: [question.start, question.end])
            if rest.isEmpty {
                return QueryMatch(scope: nil, start: question.start, end: question.end, queryText: nil,
                                  phrase: ["var", "mi"])
            }
            if rest.allSatisfy({ $0 < question.start }) {
                let words = rest.map { TurkishText.lower(ctx.tokens[$0].originalRoot) }
                return QueryMatch(scope: nil, start: question.start, end: question.end,
                                  queryText: words.joined(separator: " "), phrase: ["var", "mi"])
            }
        }
        return nil
    }

    static func buildQuery(_ ctx: inout ParseContext, _ match: QueryMatch) -> CommandMatch {
        ctx.consume(match.start, match.end)
        var command = ParsedCommand(type: .query)
        command.queryText = match.queryText
        var scope = match.scope
        if scope == nil {
            for j in 0..<ctx.count {
                let inPhrase = j >= match.start && j <= match.end
                if let found = Lexicon.queryScopeWords[ctx.tokens[j].plain], ctx.usable(j) || inPhrase {
                    scope = found
                    break
                }
            }
        }
        if scope == nil, let phrase = match.phrase, Lexicon.queryWaitingPhrases.contains(phrase) {
            scope = .waiting
        }
        if scope == nil, let day = ctx.days.first {
            switch day.scope {
            case .today: scope = .today
            case .tomorrow: scope = .tomorrow
            case .thisWeek: scope = .thisWeek
            case .nextWeek: scope = .nextWeek
            case .date:
                scope = .date
                command.date = ctx.calendar.startOfDay(for: day.day)
            }
        }
        if scope == nil {
            let hasFilter = ctx.person != nil || ctx.project != nil
            if !hasFilter, let phrase = match.phrase, Lexicon.queryTodayPhrases.contains(phrase) {
                scope = .today
            } else {
                scope = .all
            }
        }
        command.scope = scope
        for j in 0..<ctx.count where ctx.usable(j) {
            let word = ctx.tokens[j].plain
            if Lexicon.queryScopeWords[word] != nil || Lexicon.queryObjectWords.contains(word)
                || Lexicon.queryGlue.contains(word) {
                ctx.consume(j, j)
            }
        }
        return CommandMatch(command: command, cueStart: match.start, cueEnd: match.end, certainty: 100, stem: nil)
    }

    /// Endings that report something NOT done ("aramadım", "gönderemedim", "yapacaktım", "arıyordum",
    /// "hazırlamalıydım", "unuttum") — they must never complete an item.
    static let notDoneEndings: [String] = ["madim", "medim", "madik", "medik", "yordum", "yorduk", "acaktim", "ecektim",
                                           "acaktik", "ecektik", "maliydim", "meliydim", "maliydik", "meliydik",
                                           "unuttum", "unuttuk", "kacirdim", "kacirdik", "atladim", "atladik"]

    /// Past 1sg / 1pl verb at the end ("tamamladım", "hallettik"), excluding look-alike nouns and negations.
    static func isGenericPast(_ token: Token) -> Bool {
        let word = token.plain
        guard !token.isSplit, word.count >= 6, !Lexicon.genericPastExclusions.contains(word) else { return false }
        for ending in notDoneEndings where word.hasSuffix(ending) {
            return false
        }
        for ending in ["dim", "dum", "tim", "tum", "dik", "duk", "tik", "tuk"] where word.hasSuffix(ending) {
            return true
        }
        return false
    }

    static func detectCommand(_ ctx: inout ParseContext) -> CommandMatch? {
        if let query = detectQuery(ctx) {
            return buildQuery(&ctx, query)
        }
        let last = lastContentIndex(ctx)
        guard last >= 0 else { return nil }
        var start = ctx.phraseEnding(at: last, Lexicon.completePlain)
        if start >= 0 {
            return CommandMatch(command: ParsedCommand(type: .complete), cueStart: start, cueEnd: last, certainty: 100,
                                stem: nil)
        }
        if ctx.usablePlain(last) == "tamam" {
            var before = 0
            for j in 0..<last where ctx.usable(j) || ctx.projectToken[j] {
                before += 1
            }
            if before >= 2 {
                return CommandMatch(command: ParsedCommand(type: .complete), cueStart: last, cueEnd: last,
                                    certainty: 100, stem: nil)
            }
        }
        for completion in Lexicon.completeContent {
            start = ctx.phraseEnding(at: last, [completion.words])
            if start >= 0 {
                return CommandMatch(command: ParsedCommand(type: .complete), cueStart: start, cueEnd: last,
                                    certainty: 90, stem: completion.stem)
            }
        }
        start = ctx.phraseEnding(at: last, Lexicon.completeFinal)
        if start >= 0 {
            return CommandMatch(command: ParsedCommand(type: .complete), cueStart: start, cueEnd: last, certainty: 90,
                                stem: nil)
        }
        start = ctx.phraseEnding(at: last, Lexicon.cancelPhrases)
        if start >= 0 {
            return CommandMatch(command: ParsedCommand(type: .cancel), cueStart: start, cueEnd: last, certainty: 100,
                                stem: nil)
        }
        if ctx.usablePlain(last) == "unut" {
            return CommandMatch(command: ParsedCommand(type: .cancel), cueStart: last, cueEnd: last, certainty: 100,
                                stem: nil)
        }
        start = ctx.phraseEnding(at: last, Lexicon.snoozePhrases)
        if start >= 0 {
            return CommandMatch(command: ParsedCommand(type: .snooze), cueStart: start, cueEnd: last, certainty: 100,
                                stem: nil)
        }
        if isDateDativeSnooze(ctx, last) {
            return CommandMatch(command: ParsedCommand(type: .snooze), cueStart: last, cueEnd: last, certainty: 100,
                                stem: nil)
        }
        // "bir saat sonra hatırlat" / "birazdan hatırlat" with nothing else → snooze.
        if ctx.usable(last) && isHatirlaVerb(ctx.tokens[last]), let offset = ctx.offset, offset.end == last - 1,
           offset.endsWithSonra, !offset.isCalendar {
            let others = contentIndices(ctx).filter { $0 != last }
            if others.isEmpty {
                return CommandMatch(command: ParsedCommand(type: .snooze), cueStart: last, cueEnd: last,
                                    certainty: 100, stem: nil)
            }
        }
        // Generic -DIm/-DIk completion — never when the utterance carries a time or a future day.
        var temporal = !ctx.clocks.isEmpty || !ctx.dayparts.isEmpty || ctx.offset != nil
            || !ctx.recurrenceSpecs.isEmpty
        for day in ctx.days where day.day > ctx.today {
            temporal = true
        }
        if !temporal && ctx.usable(last) && isGenericPast(ctx.tokens[last]) {
            return CommandMatch(command: ParsedCommand(type: .complete), cueStart: last, cueEnd: last, certainty: 85,
                                stem: nil)
        }
        return nil
    }

    /// G3: "DATE+DAT bırak / al / taşı" ("haftaya bırak", "bunu yarına al", "raporu pazartesiye taşı").
    static func isDateDativeSnooze(_ ctx: ParseContext, _ last: Int) -> Bool {
        let verb = ctx.usablePlain(last)
        guard Lexicon.snoozeDateVerbs.contains(verb) else { return false }
        var datStart = -1
        for day in ctx.days where day.end == last - 1 && day.endsWithDative {
            datStart = day.start
        }
        for clock in ctx.clocks where clock.end == last - 1 && clock.endsWithDative {
            datStart = clock.start
        }
        for daypart in ctx.dayparts where daypart.end == last - 1 && daypart.endsWithDative {
            datStart = daypart.start
        }
        guard datStart >= 0 else { return false }
        if verb == "al" {
            var lastObject = -1
            for j in 0..<datStart where ctx.usable(j) && !isFiller(ctx.tokens[j]) {
                lastObject = j
            }
            if lastObject >= 0 {
                let word = ctx.tokens[lastObject].plain
                if !["bunu", "onu", "sunu"].contains(word)
                    && !Lexicon.snoozeAlObjectEndings.contains(where: { word.hasSuffix($0) }) {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - multipleItems (§12)

    static func isVerbish(_ token: Token) -> Bool {
        return Lexicon.imperatives.contains(token.plain) || isHatirlaVerb(token)
    }

    /// Start index of a joiner ("ve ayrıca", "bir de", "sonra da", "ayrıca") between two content verbs, or nil.
    static func multipleItemsJoiner(_ ctx: ParseContext) -> Int? {
        for i in 0..<ctx.count where ctx.usable(i) {
            for joiner in Lexicon.multiJoiners {
                let e = ctx.matchSequence(i, joiner)
                guard e >= 0 else { continue }
                var verbBefore = false
                for j in 0..<i where ctx.usable(j) && isVerbish(ctx.tokens[j]) {
                    verbBefore = true
                }
                var verbAfter = false
                if e + 1 < ctx.count {
                    for j in (e + 1)..<ctx.count where ctx.usable(j) && isVerbish(ctx.tokens[j]) {
                        verbAfter = true
                    }
                }
                if verbBefore && verbAfter {
                    return i
                }
            }
        }
        return nil
    }
}
