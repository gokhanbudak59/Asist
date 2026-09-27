// Persons — 02 §7.9 (P1–P7) + G2 restrictions (04 §3.4.6). Person tokens are NOT consumed (they stay in titles,
// except for waiting-for items, §11.4).
import Foundation

enum PersonExtractor {
    static func suffixClass(_ suffix: String) -> SuffixClass? {
        if suffix.isEmpty {
            return .bare
        }
        if Lexicon.ablative.contains(suffix) {
            return .ablative
        }
        if Lexicon.dative.contains(suffix) {
            return .dative
        }
        if Lexicon.accusative.contains(suffix) {
            return .accusative
        }
        if Lexicon.genitive.contains(suffix) {
            return .genitive
        }
        if Lexicon.instrumental.contains(suffix) {
            return .instrumental
        }
        if Lexicon.locative.contains(suffix) {
            return .locative
        }
        return nil
    }

    static func honorific(_ token: Token) -> (canonical: String, strong: Bool, suffix: String)? {
        for entry in Lexicon.honorifics {
            if token.isSplit && token.root == entry.key {
                return (entry.canonical, entry.strong, token.suffix)
            }
            if let rest = TurkishNumbers.remainder(token.plain, afterPrefix: entry.key),
               Lexicon.honorificSuffixes.contains(rest) {
                return (entry.canonical, entry.strong, rest)
            }
        }
        return nil
    }

    /// A bare word that may be a name (not a lexicon word, number word, weekday, month …).
    static func isNameCandidate(_ ctx: ParseContext, _ j: Int, requireCapital: Bool) -> Bool {
        guard ctx.usable(j) else { return false }
        let token = ctx.tokens[j]
        if token.isAllCaps || token.isSplit || token.number != nil {
            return false
        }
        if requireCapital && !token.isCapitalized {
            return false
        }
        if Lexicon.lexiconWords.contains(token.plain) || TokenMatch.weekday(token) != nil
            || TokenMatch.month(token, allowed: [""]) != nil {
            return false
        }
        if TurkishNumbers.wordNumber(of: token) != nil {
            return false
        }
        return token.plain.count >= 2
    }

    /// Each word first-letter upper-cased with Turkish rules ("ahmet" → "Ahmet").
    static func personValue(_ text: String) -> String {
        let words = text.split(separator: " ").map { TurkishText.upperFirst(TurkishText.lower(String($0))) }
        return words.joined(separator: " ")
    }

    /// `waitingSubjectVerb`: a final 3rd-person future waiting verb or a "bekliyorum" family verb exists (P7).
    static func extract(_ ctx: inout ParseContext, waitingVerbPresent: Bool) {
        if let known = knownPerson(ctx) {
            ctx.person = known
            return
        }
        if let strong = strongRules(ctx) {
            ctx.person = strong
            return
        }
        if waitingVerbPresent, let subject = waitingSubject(ctx) {
            ctx.person = subject
            return
        }
        if let weak = noApostropheRule(ctx) {
            ctx.person = weak
            ctx.flags.insert(.uncertainPerson)
        }
    }

    /// P1: contact list (folded, suffix-tolerant).
    static func knownPerson(_ ctx: ParseContext) -> PersonHit? {
        let personSuffixes = Lexicon.joined([Lexicon.caseSuffixes, ["yle", "yla", "nin", "nun"]])
        for name in ctx.settings.knownPeople {
            let words = ProjectPlaceExtractor.words(of: name)
            guard let lastWord = words.last else { continue }
            for i in 0..<ctx.count {
                var ok = true
                for k in 0..<(words.count - 1) where !ctx.usable(i + k) || ctx.tokens[i + k].plain != words[k] {
                    ok = false
                }
                let j = i + words.count - 1
                guard ok, ctx.usable(j) else { continue }
                guard let suffix = TokenMatch.suffix(ctx.tokens[j], lastWord, personSuffixes) else { continue }
                return PersonHit(value: name, start: i, end: j, suffixClass: suffixClass(suffix) ?? .bare, rule: "P1")
            }
        }
        return nil
    }

    /// P4 surname, P3 honorific, P2 apostrophe, P5 "ile" — left to right, first accepted wins.
    static func strongRules(_ ctx: ParseContext) -> PersonHit? {
        for i in 0..<ctx.count {
            guard ctx.usable(i) else { continue }
            let token = ctx.tokens[i]
            // P4: "Ahmet Yılmaz'ı"
            if token.isCapitalized && isNameCandidate(ctx, i, requireCapital: true) && ctx.usable(i + 1) {
                let second = ctx.tokens[i + 1]
                if second.isCapitalized && second.hadApostrophe && !second.isAllCaps
                    && !Lexicon.lexiconWords.contains(second.root) && honorific(second) == nil,
                   let cls = suffixClass(second.suffix), cls != .bare {
                    let value = personValue(token.originalRoot + " " + second.originalRoot)
                    return PersonHit(value: value, start: i, end: i + 1, suffixClass: cls, rule: "P4")
                }
            }
            // P3: "Ahmet Bey'den", "ahmet beyi", "Kemal Usta'ya"
            if ctx.usable(i + 1), let title = honorific(ctx.tokens[i + 1]),
               isNameCandidate(ctx, i, requireCapital: !title.strong) {
                let value = personValue(token.original) + " " + title.canonical
                return PersonHit(value: value, start: i, end: i + 1, suffixClass: suffixClass(title.suffix) ?? .bare,
                                 rule: "P3")
            }
            // P2: "Ahmet'i", "Siemens'ten"
            if token.isCapitalized && token.hadApostrophe && !token.isAllCaps && honorific(token) == nil
                && TokenMatch.weekday(token) == nil && TokenMatch.month(token) == nil
                && !Lexicon.lexiconWords.contains(token.root),
               let cls = suffixClass(token.suffix), cls != .bare {
                return PersonHit(value: personValue(token.originalRoot), start: i, end: i, suffixClass: cls, rule: "P2")
            }
            // P5: "Mehmet ile"
            if token.isCapitalized && !token.isSplit && isNameCandidate(ctx, i, requireCapital: true) {
                let next = ctx.usablePlain(i + 1)
                if next == "ile" || next == "ilen" {
                    return PersonHit(value: personValue(token.original), start: i, end: i, suffixClass: .instrumental,
                                     rule: "P5")
                }
            }
        }
        return nil
    }

    /// P7: capitalised subject at index 0 (or 1 after a consumed word) of a waiting verb; G2 rejects plurals and
    /// common nouns ("Sürücüler", "Tedarikçi").
    static func waitingSubject(_ ctx: ParseContext) -> PersonHit? {
        for i in 0...1 where i < ctx.count && ctx.usable(i) {
            // Index 1 only when token 0 is not itself free content ("yarın Veli dönecek").
            if i == 1 && ctx.usable(0) {
                continue
            }
            let token = ctx.tokens[i]
            guard token.isCapitalized, !token.isSplit, !token.isAllCaps,
                  isNameCandidate(ctx, i, requireCapital: true) else { continue }
            let word = token.plain
            if word.hasSuffix("ler") || word.hasSuffix("lar") {
                continue
            }
            var common = false
            for noun in Lexicon.waitingCommonNouns where word.hasPrefix(noun) && word.count - noun.count <= 3 {
                common = true
            }
            if common {
                continue
            }
            return PersonHit(value: personValue(token.original), start: i, end: i, suffixClass: .bare, rule: "P7")
        }
        return nil
    }

    /// P6: capitalised token at index > 0 ending in a person suffix without apostrophe ("Mehmetle"); disabled for
    /// Title-Case dictation (more than half of the tokens capitalised).
    static func noApostropheRule(_ ctx: ParseContext) -> PersonHit? {
        var capitalized = 0
        for token in ctx.tokens where token.isCapitalized {
            capitalized += 1
        }
        guard capitalized * 2 <= ctx.count, ctx.count > 1 else { return nil }
        for i in 1..<ctx.count {
            guard ctx.usable(i) else { continue }
            let token = ctx.tokens[i]
            guard token.isCapitalized, !token.isSplit, !token.isAllCaps else { continue }
            if Lexicon.lexiconWords.contains(token.plain) || TokenMatch.weekday(token) != nil
                || TokenMatch.month(token) != nil {
                continue
            }
            for suffix in Lexicon.personP6Suffixes where token.plain.hasSuffix(suffix) {
                guard token.plain.count - suffix.count >= 3 else { continue }
                let root = String(token.original.dropLast(suffix.count))
                if Lexicon.lexiconWords.contains(TurkishText.fold(root)) {
                    break
                }
                return PersonHit(value: personValue(root), start: i, end: i, suffixClass: suffixClass(suffix) ?? .bare,
                                 rule: "P6")
            }
        }
        return nil
    }
}
