// Known projects (02 §7.2) and known places + trigger (02 §7.3).
import Foundation

enum ProjectPlaceExtractor {
    /// Folded word tokens of a configured name ("Hat 3" → ["hat", "3"]).
    static func words(of name: String) -> [String] {
        return Tokenizer.tokenize(Normalizer.normalize(name)).tokens.map { $0.plain }
    }

    // MARK: Projects

    static func extractProjects(_ ctx: inout ParseContext) {
        var matches: [(name: String, start: Int, end: Int)] = []
        for name in ctx.settings.knownProjects {
            let nameWords = words(of: name)
            guard let lastWord = nameWords.last else { continue }
            var hasDigit = false
            for word in nameWords where word.contains(where: { Normalizer.isDigit($0) }) {
                hasDigit = true
            }
            let single = nameWords.count == 1
            let lastOffset = nameWords.count - 1
            for i in 0..<ctx.count {
                var ok = true
                for k in 0..<lastOffset {
                    let j = i + k
                    if !ctx.free(j) || ctx.tokens[j].plain != nameWords[k] {
                        ok = false
                        break
                    }
                }
                let j = i + lastOffset
                guard ok, ctx.free(j) else { continue }
                let token = ctx.tokens[j]
                var good = false
                if token.plain == lastWord {
                    good = true
                } else if token.isSplit && token.root == lastWord {
                    good = true
                } else if !single || hasDigit,
                          let rest = TurkishNumbers.remainder(token.plain, afterPrefix: lastWord),
                          Lexicon.projectSuffixes.contains(rest) {
                    good = true
                }
                if good {
                    matches.append((name, i, j))
                }
            }
        }
        guard !matches.isEmpty else { return }
        // Several different projects → the longest name wins (tie: earliest).
        let sorted = matches.sorted { lhs, rhs in
            lhs.name.count != rhs.name.count ? lhs.name.count > rhs.name.count : lhs.start < rhs.start
        }
        let chosen = sorted[0]
        ctx.project = chosen.name
        let a = chosen.start
        let b = chosen.end
        let next = ctx.plain(b + 1)
        let afterNext = ctx.plain(b + 2)
        // Explicit markers: "X projesine ekle", "X projesi için", "X projesinde", "proje X" (consumed, not in title).
        if next == "projesine" && afterNext == "ekle" {
            ctx.consume(a, b + 2)
            ctx.explicitTaskPhrase = true
            ctx.verbCue = true
            return
        }
        if next == "projesi" && afterNext == "icin" {
            ctx.consume(a, b + 2)
            return
        }
        if next == "projesinde" {
            ctx.consume(a, b + 1)
            return
        }
        if a > 0 && ctx.plain(a - 1) == "proje" && ctx.free(a - 1) {
            ctx.consume(a - 1, b)
            return
        }
        // Natural mention: stays in the title, protected from number/date/person readings ("Hat 3'te").
        for k in a...b {
            ctx.protected[k] = true
            ctx.projectToken[k] = true
        }
    }

    // MARK: Places

    static let arriveSuffixes: [String] = Lexicon.joined([[""], Lexicon.dative, Lexicon.locative])
    static let leaveSuffixes: [String] = Lexicon.joined([[""], Lexicon.ablative])

    static func extractPlaces(_ ctx: inout ParseContext) {
        for name in ctx.settings.knownPlaces {
            let nameWords = words(of: name)
            guard let lastWord = nameWords.last else { continue }
            let lastOffset = nameWords.count - 1
            for i in 0..<ctx.count {
                var ok = true
                for k in 0..<lastOffset where !ctx.usable(i + k) || ctx.tokens[i + k].plain != nameWords[k] {
                    ok = false
                }
                let j = i + lastOffset
                guard ok, ctx.usable(j) else { continue }
                let token = ctx.tokens[j]
                if TokenMatch.suffix(token, lastWord, arriveSuffixes) != nil {
                    let e = ctx.matchAny(j + 1, Lexicon.arriveTriggers)
                    if e >= 0 {
                        ctx.place = PlaceRef(name: name, trigger: .onArrive)
                        ctx.consume(i, e)
                        return
                    }
                }
                if TokenMatch.suffix(token, lastWord, leaveSuffixes) != nil {
                    let e = ctx.matchAny(j + 1, Lexicon.leaveTriggers)
                    if e >= 0 {
                        ctx.place = PlaceRef(name: name, trigger: .onLeave)
                        ctx.consume(i, e)
                        return
                    }
                }
            }
        }
        // Unknown place: a trigger verb after a DAT/ABL/LOC noun ("markete gidince") → flag, tokens stay (02 §7.3).
        let triggers = Lexicon.arriveTriggers + Lexicon.leaveTriggers
        let endings: [String] = ["e", "a", "ye", "ya", "den", "dan", "ten", "tan", "de", "da"]
        guard ctx.count >= 2 else { return }
        for i in 1..<ctx.count {
            guard ctx.matchAny(i, triggers) >= 0, ctx.usable(i - 1) else { continue }
            let previous = ctx.tokens[i - 1]
            let word = previous.plain
            // "işe gelince" / "işten çıkınca" are dayparts (§5.5).
            if previous.root == "is" || word == "ise" || word == "isten" || word == "isyerine" || word == "isyerinden" {
                continue
            }
            if endings.contains(where: { word.hasSuffix($0) }) {
                ctx.flags.insert(.unknownPlace)
                return
            }
        }
    }
}
