// Title / body / queryText — 02 §11 (consumed material removed, suffix repair on the last token, edge trimming,
// capitalisation, never empty) and 02 §10.6 (command target text).
import Foundation

enum TitleBuilder {
    static let vowels: Set<Character> = ["a", "e", "ı", "i", "o", "ö", "u", "ü", "â", "î", "û"]
    static let closeVowels: Set<Character> = ["ı", "i", "u", "ü"]

    /// Suffix repair of the LAST remaining token (02 §11.2). `verbCue`: a consumed verb cue exists (S2–S4);
    /// `modalityAfter`: a consumed "lazım/gerek…" follows the token (S5).
    static func repairLast(_ word: String, verbCue: Bool, modalityAfter: Bool) -> String {
        let chars = Array(word)
        let lowered = Array(TurkishText.lower(word))
        guard chars.count == lowered.count, !chars.isEmpty else { return word }
        let lowerString = String(lowered)
        let count = lowered.count

        func replacing(last n: Int, with replacement: String) -> String {
            return String(chars.prefix(count - n)) + replacement
        }

        // S5 modality: "yazmam lazım" → "yazmak", "yapmalıyım" → "yapmak"
        if modalityAfter && count > 4 && (lowerString.hasSuffix("mam") || lowerString.hasSuffix("mem")) {
            return replacing(last: 1, with: "k")
        }
        let modalityForms: [(suffix: String, replacement: String)] = [
            ("malıyım", "mak"), ("meliyim", "mek"), ("malıyız", "mak"), ("meliyiz", "mek"), ("maliyim", "mak"),
            ("maliyiz", "mak")
        ]
        for form in modalityForms where lowerString.hasSuffix(form.suffix) && count > form.suffix.count + 1 {
            return replacing(last: form.suffix.count, with: form.replacement)
        }
        // S1 (always): "aramayı" → "aramak", "aramamı" → "aramak"; nouns such as "malzemeyi" are left alone.
        let verbalNounForms: [(suffix: String, replacement: String)] = [
            ("mamızı", "mak"), ("memizi", "mek"), ("mamizi", "mak"), ("mayı", "mak"), ("meyi", "mek"),
            ("mayi", "mak"), ("mamı", "mak"), ("memi", "mek"), ("mami", "mak")
        ]
        for form in verbalNounForms where lowerString.hasSuffix(form.suffix) && count - form.suffix.count >= 2 {
            let stem = String(lowered.prefix(count - form.suffix.count)) + String(form.suffix.prefix(2))
            if Lexicon.s1NounExceptions.contains(TurkishText.fold(stem)) {
                break
            }
            return replacing(last: form.suffix.count, with: form.replacement)
        }
        guard verbCue else { return word }
        // S2: "konusunu" → "konusu", "PLC'sini" → "PLC'si" (noun compounds incl. "ödemesini" → "ödemesi")
        if count >= 5 {
            let v1 = lowered[count - 3]
            let n = lowered[count - 2]
            let v2 = lowered[count - 1]
            if n == "n" && v1 == v2 && closeVowels.contains(v1) {
                let stemLast = lowered[count - 3]
                let withoutFinalVowel = String(lowered.prefix(count - 1))
                if vowels.contains(stemLast) && count - 2 >= 3 && !Lexicon.s2Exceptions.contains(withoutFinalVowel) {
                    return replacing(last: 2, with: "")
                }
            }
        }
        let hasApostrophe = word.contains("'")
        // S3: "çizimleri" → "çizimler"
        if !hasApostrophe && count >= 6 && (lowerString.hasSuffix("leri") || lowerString.hasSuffix("ları")) {
            return replacing(last: 1, with: "")
        }
        // S4: "toplantıyı" → "toplantı"
        if !hasApostrophe && count >= 4 && lowered[count - 2] == "y" && closeVowels.contains(lowered[count - 1])
            && vowels.contains(lowered[count - 3]) {
            return replacing(last: 2, with: "")
        }
        return word
    }

    /// Strips connector words (02 §5.7) at both edges, repeatedly.
    static func trimEdges(_ ctx: ParseContext, _ indices: [Int]) -> [Int] {
        var result = indices
        var changed = true
        while changed && !result.isEmpty {
            changed = false
            if Lexicon.connectors.contains(ctx.plain(result[0])) {
                result.removeFirst()
                changed = true
                continue
            }
            if result.count >= 2 && Lexicon.connectorPhrases.contains([ctx.plain(result[0]), ctx.plain(result[1])]) {
                result.removeFirst(2)
                changed = true
                continue
            }
            if let last = result.last, Lexicon.connectors.contains(ctx.plain(last)), !ctx.projectToken[last] {
                result.removeLast()
                changed = true
            }
        }
        return result
    }

    static func isPronounOnly(_ ctx: ParseContext, _ indices: [Int]) -> Bool {
        for j in indices where !Lexicon.pronouns.contains(ctx.plain(j)) {
            return false
        }
        return true
    }

    static func letterCount(_ text: String) -> Int {
        var count = 0
        for ch in text where ch.isLetter {
            count += 1
        }
        return count
    }

    /// 02 §11.6: normalised original text, first letter upper-cased.
    static func fallbackTitle(_ ctx: ParseContext) -> String {
        let text = ctx.normalized.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Not" : TurkishText.upperFirst(text)
    }

    // MARK: - Items

    /// Title from the unconsumed tokens. Returns nil when the title must fall back (§11.6).
    static func itemTitle(_ ctx: ParseContext, kind: ItemKind, verbCue: Bool, multipleItemsJoiner: Int?) -> String? {
        var indices: [Int] = []
        for j in 0..<ctx.count where !ctx.consumed[j] {
            if let joiner = multipleItemsJoiner, j >= joiner {
                continue
            }
            if kind == .waiting, let person = ctx.person, person.suffixClass == .bare || person.suffixClass == .ablative,
               j >= person.start && j <= person.end {
                continue
            }
            indices.append(j)
        }
        indices = trimEdges(ctx, indices)
        guard let lastIndex = indices.last else { return nil }
        if isPronounOnly(ctx, indices) {
            return nil
        }
        var words = indices.map { ctx.tokens[$0].original }
        if letterCount(words.joined()) < 2 {
            return nil
        }
        var modalityAfter = false
        for m in ctx.modalityIndices where m > lastIndex {
            var onlyConsumedBetween = true
            if m > lastIndex + 1 {
                for k in (lastIndex + 1)..<m where !ctx.consumed[k] {
                    onlyConsumedBetween = false
                }
            }
            if onlyConsumedBetween {
                modalityAfter = true
            }
        }
        words[words.count - 1] = repairLast(words[words.count - 1], verbCue: verbCue, modalityAfter: modalityAfter)
        return TurkishText.upperFirst(words.joined(separator: " "))
    }

    /// `unusedNumber` (02 §12): a bare integer that stayed in the title (not a protected equipment/unit number).
    static func hasUnusedNumber(_ ctx: ParseContext, multipleItemsJoiner: Int?) -> Bool {
        for j in 0..<ctx.count where !ctx.consumed[j] && !ctx.protected[j] && !ctx.invalidToken[j] {
            if let joiner = multipleItemsJoiner, j >= joiner {
                continue
            }
            if ctx.tokens[j].integerValue != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Notes (verbatim, §11.4)

    /// Tokens removed from a verbatim note: the prefix marker and the note phrases.
    static func noteRemovedIndices(_ ctx: ParseContext) -> Set<Int> {
        var removed = Set<Int>()
        if ctx.prefixKind != nil {
            let prefixWords: Set<String> = ["not", "nota", "fikir", "al", "bilgi", "gorev", "yapilacak",
                                            "yapilacaklar", "is", "bekliyorum"]
            for j in 0..<min(2, ctx.count) where ctx.consumed[j] && prefixWords.contains(ctx.plain(j)) {
                removed.insert(j)
            }
        }
        let phrases = Lexicon.noteStrongPhrases + Lexicon.noteWeakPhrases
        for phrase in phrases {
            for i in 0..<ctx.count where i + phrase.count <= ctx.count {
                var matches = true
                for k in 0..<phrase.count where ctx.tokens[i + k].plain != phrase[k] {
                    matches = false
                }
                if matches {
                    for k in 0..<phrase.count {
                        removed.insert(i + k)
                    }
                }
            }
        }
        return removed
    }

    /// Normalised text minus the note phrase, minus fillers/priority words/pronouns at the edges; internal text
    /// (including dates and punctuation) verbatim.
    static func noteBody(_ ctx: ParseContext) -> String {
        let removed = noteRemovedIndices(ctx)
        var kept: [Int] = []
        for j in 0..<ctx.count where !removed.contains(j) {
            kept.append(j)
        }
        func droppableAtEdge(_ j: Int) -> Bool {
            let token = ctx.tokens[j]
            return Lexicon.pronouns.contains(token.plain) || CueExtractor.isFiller(token)
                || ctx.priorityTokens.contains(j)
        }
        while let first = kept.first, droppableAtEdge(first) {
            kept.removeFirst()
        }
        while let last = kept.last, droppableAtEdge(last) {
            kept.removeLast()
        }
        guard !kept.isEmpty else { return "" }
        var parts: [String] = []
        var runStart = kept[0]
        var previous = kept[0]
        for j in kept.dropFirst() {
            if j == previous + 1 {
                previous = j
                continue
            }
            parts.append(slice(ctx, from: runStart, to: previous))
            runStart = j
            previous = j
        }
        parts.append(slice(ctx, from: runStart, to: previous))
        var body = parts.joined(separator: " ")
        while let last = body.last, last == "," || last == ";" || last == ":" || last == " " {
            body.removeLast()
        }
        return body.trimmingCharacters(in: .whitespaces)
    }

    static func slice(_ ctx: ParseContext, from a: Int, to b: Int) -> String {
        let start = ctx.tokens[a].start
        let end = ctx.tokens[b].end
        guard start >= 0, end <= ctx.chars.count, start < end else { return ctx.tokens[a].original }
        return String(ctx.chars[start..<end])
    }

    // MARK: - Commands (§10.6)

    /// Tokens before the command cue → lowercase, apostrophe suffix removed, last token repaired, + verb stem.
    static func queryText(_ ctx: ParseContext, cueStart: Int, stem: String?) -> String? {
        var indices: [Int] = []
        for j in 0..<max(0, cueStart) where (ctx.usable(j) || ctx.projectToken[j]) && !ctx.consumed[j] {
            let token = ctx.tokens[j]
            if CueExtractor.isFiller(token) || Lexicon.commandObjectWords.contains(token.plain) {
                continue
            }
            indices.append(j)
        }
        indices = trimEdges(ctx, indices)
        var words: [String] = []
        if !indices.isEmpty && !isPronounOnly(ctx, indices) {
            for (position, j) in indices.enumerated() {
                let token = ctx.tokens[j]
                var word = token.hadApostrophe ? token.originalRoot : token.original
                if position == indices.count - 1 && !token.hadApostrophe {
                    word = repairLast(word, verbCue: true, modalityAfter: false)
                }
                words.append(TurkishText.lower(word))
            }
        }
        if let verbStem = stem {
            words.append(verbStem)
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
