// Kind classification — 02 §10 (template-free, tiered) with the G2/G6 ordering of 04 §3.4.6.
import Foundation

enum KindTier: String {
    case t0 = "T0", t2 = "T2", t3 = "T3", t4 = "T4", t5 = "T5", t6 = "T6", t7 = "T7", t8 = "T8", t9 = "T9"
    case t10a = "T10a", t10b = "T10b"
}

struct Classification {
    var tier: KindTier
    var kind: ItemKind
    /// Kind certainty in hundredths (02 §10.1).
    var certainty: Int
    var negation = false
    var alarmCue = false
    /// Start of a "ve ayrıca / bir de" joiner: only the first item is represented (02 §16.1).
    var multipleItemsJoiner: Int? = nil

    init(tier: KindTier, kind: ItemKind, certainty: Int) {
        self.tier = tier
        self.kind = kind
        self.certainty = certainty
    }

    /// Notes keep their text verbatim (02 §10.2).
    var isVerbatimNote: Bool { kind == .note }
}

enum Classifier {
    /// Decides the item kind (T0, T2…T10) and consumes the cue words. Commands (T1) are detected before this.
    static func classify(_ ctx: inout ParseContext) -> Classification {
        var chosen: (tier: KindTier, kind: ItemKind, certainty: Int)? = nil
        if let prefix = ctx.prefixKind {
            chosen = (tier: KindTier.t0, kind: prefix, certainty: 100)
        }
        let joiner = CueExtractor.multipleItemsJoiner(ctx)
        if joiner != nil {
            ctx.flags.insert(.multipleItems)
        }

        // T2 strong note phrases
        let strongNote = CueExtractor.consumePhrases(&ctx, Lexicon.noteStrongPhrases)
        if strongNote && chosen == nil {
            chosen = (tier: KindTier.t2, kind: ItemKind.note, certainty: 100)
        }
        // T3 explicit task phrases
        let foundTaskPhrase = CueExtractor.consumePhrases(&ctx, Lexicon.taskPhrases)
        if foundTaskPhrase || ctx.explicitTaskPhrase {
            ctx.verbCue = true
            if chosen == nil {
                chosen = (tier: KindTier.t3, kind: ItemKind.task, certainty: 100)
            }
        }
        // T4 waiting-for cues
        var waiting = false
        for j in 0..<ctx.count where ctx.usable(j) && Lexicon.waitingBekle.contains(ctx.tokens[j].plain) {
            ctx.consume(j, j)
            waiting = true
        }
        if CueExtractor.consumePhrases(&ctx, Lexicon.waitingFollow) {
            waiting = true
        }
        if let finalVerb = CueExtractor.finalWaitingVerb(ctx) {
            // G2: final "gelecek" with a person subject is a visit ("Ahmet Bey gelecek"), not a waiting item.
            if !(finalVerb.isGelecek && ctx.person != nil) {
                ctx.consume(finalVerb.start, finalVerb.end)
                waiting = true
            }
        }
        if waiting {
            ctx.verbCue = true
            if chosen == nil {
                chosen = (tier: KindTier.t4, kind: ItemKind.waiting, certainty: 95)
            }
        }
        // T5 reminder cues
        var negation = false
        var alarmCue = false
        var reminder = ctx.leadCue || ctx.priorityCue
        let last = CueExtractor.lastContentIndex(ctx)
        for j in 0..<ctx.count where ctx.usable(j) {
            let token = ctx.tokens[j]
            if token.plain == "hatirlatma" {
                let next = ctx.usablePlain(j + 1)
                if next == "kur" || next == "ekle" || next == "olustur" {
                    ctx.consume(j, j + 1)
                    reminder = true
                } else if j == last {
                    ctx.consume(j, j)
                    reminder = true
                    negation = true
                }
                continue
            }
            if CueExtractor.isHatirlaVerb(token) {
                var end = j
                if Lexicon.questionParticles.contains(ctx.usablePlain(j + 1)) {
                    end = j + 1
                }
                ctx.consume(j, end)
                reminder = true
            }
        }
        if CueExtractor.consumePhrases(&ctx, Lexicon.reminderPhrases) {
            reminder = true
        }
        let hasTimeWord = !ctx.clocks.isEmpty || !ctx.dayparts.isEmpty || ctx.offset != nil
        for j in 0..<ctx.count where ctx.usable(j) && ctx.tokens[j].plain == "alarm" && hasTimeWord {
            ctx.consume(j, j)
            reminder = true
            alarmCue = true
        }
        // haber ver / bildir / söyle / uyar: reminder cues only when the indirect object is the user (§10.3).
        var userObject = false
        for token in ctx.tokens where token.plain == "bana" || token.plain == "beni" {
            userObject = true
        }
        var personObject = false
        if let person = ctx.person, person.suffixClass == .dative || person.suffixClass == .accusative {
            personObject = true
        }
        var guardCounter = 0
        while let match = ctx.findPhrase(Lexicon.reminderConditional), guardCounter < 16 {
            guardCounter += 1
            var dativeBefore = false
            for k in 0..<match.start where ctx.usable(k) && CueExtractor.isDativeLike(ctx.tokens[k]) {
                dativeBefore = true
            }
            if userObject || (!personObject && !dativeBefore) {
                ctx.consume(match.start, match.end)
                reminder = true
            } else {
                break
            }
        }
        if reminder {
            ctx.verbCue = true
            if chosen == nil {
                chosen = (tier: KindTier.t5, kind: ItemKind.reminder, certainty: 100)
            }
        }
        // T6 task modality
        var modality = false
        for j in 0..<ctx.count where ctx.usable(j) && Lexicon.taskModality.contains(ctx.tokens[j].plain) {
            ctx.consume(j, j)
            ctx.modalityIndices.append(j)
            modality = true
        }
        let lastContent = CueExtractor.lastContentIndex(ctx)
        if lastContent >= 0 {
            let word = ctx.tokens[lastContent].plain
            for suffix in Lexicon.modalitySuffixes where word.hasSuffix(suffix) {
                modality = true
            }
        }
        if modality {
            ctx.verbCue = true
            if chosen == nil {
                chosen = (tier: KindTier.t6, kind: ItemKind.task, certainty: 90)
            }
        }
        // T7 weak note cues (only without any date/time)
        let temporal = !ctx.days.isEmpty || !ctx.clocks.isEmpty || !ctx.dayparts.isEmpty || ctx.offset != nil
            || !ctx.recurrenceSpecs.isEmpty || ctx.nthWeekdayOrdinal != nil
        if chosen == nil && !temporal {
            let weakNote = CueExtractor.consumePhrases(&ctx, Lexicon.noteWeakPhrases)
            if weakNote {
                chosen = (tier: KindTier.t7, kind: ItemKind.note, certainty: 85)
            }
        }
        // A leading "kaydet" (save) that did not make a weak note is an instruction, not title content.
        if chosen == nil && ctx.usablePlain(0) == "kaydet" {
            ctx.consume(0, 0)
        }
        // T8 any date/time/offset/recurrence/place (or G9 "hemen")
        if chosen == nil && (temporal || ctx.place != nil || ctx.hemenIndex != nil) {
            chosen = (tier: KindTier.t8, kind: ItemKind.reminder, certainty: 90)
        }
        CueExtractor.consumeFillers(&ctx)
        // T9 imperative content verb at the end (+ "X'e sor … mi")
        let finalIndex = CueExtractor.lastContentIndex(ctx)
        if chosen == nil && finalIndex >= 0 {
            let word = ctx.tokens[finalIndex].plain
            let pair = finalIndex >= 1 ? [ctx.plain(finalIndex - 1), word] : [word]
            if Lexicon.imperatives.contains(word) || Lexicon.imperativePhrases.contains(pair) {
                chosen = (tier: KindTier.t9, kind: ItemKind.task, certainty: 80)
            } else if Lexicon.questionParticles.contains(word) {
                for j in 0..<finalIndex where ctx.usable(j) && Lexicon.askVerbs.contains(ctx.tokens[j].plain) {
                    chosen = (tier: KindTier.t9, kind: ItemKind.task, certainty: 80)
                }
            }
        }
        if chosen == nil {
            var contentCount = 0
            for j in 0..<ctx.count where ctx.usable(j) || ctx.projectToken[j] {
                contentCount += 1
            }
            if contentCount >= 8 {
                chosen = (tier: KindTier.t10a, kind: ItemKind.note, certainty: 70)
            } else {
                chosen = (tier: KindTier.t10b, kind: ItemKind.note, certainty: 55)
            }
            ctx.flags.insert(.noKindCue)
        }
        var result = Classification(tier: KindTier.t10b, kind: ItemKind.note, certainty: 55)
        if let decided = chosen {
            result = Classification(tier: decided.tier, kind: decided.kind, certainty: decided.certainty)
        }
        result.negation = negation
        result.alarmCue = alarmCue
        result.multipleItemsJoiner = joiner
        if negation {
            ctx.flags.insert(.negation)
        }
        return result
    }
}
