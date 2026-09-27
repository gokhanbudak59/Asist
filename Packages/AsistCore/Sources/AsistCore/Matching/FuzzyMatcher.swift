// API: Packages/AsistCore/Sources/AsistCore/Matching/FuzzyMatcher.swift
// WP2 (04 §3.5.5; behaviour 03 §5.10, 02 §10.6, G5). Voice complete / cancel / snooze target matching.
import Foundation

public struct FuzzyMatch: Equatable {
    public var itemID: UUID
    public var score: Double        // 0…1

    public init(itemID: UUID, score: Double) {
        self.itemID = itemID
        self.score = score
    }
}

public enum MatchDecision: Equatable {
    case single(UUID)               // best ≥ 0.60 and (second < 0.40 or best − second ≥ 0.25)
    case ambiguous([UUID])          // 2–3 candidates ≥ 0.40
    case none
}

public enum FuzzyMatcher {
    /// Minimum score for an item to be returned by `rank` at all (keeps unrelated items out of "Hangisi?").
    static let minimumRankScore = 0.20

    private static let apostrophes: Set<Character> = ["'", "’", "‘", "`", "´"]

    /// Folded words that never help matching (object words of commands, pronouns, glue words).
    private static let stopWords: Set<String> = [
        "hatirlatma", "hatirlatmasi", "hatirlatmasini", "hatirlatmayi", "hatirlatmalari", "hatirlatmalarini",
        "hatirlatici", "hatirlaticiyi", "hatirlaticisi", "hatirlaticisini",
        "alarm", "alarmi", "alarmini",
        "gorev", "gorevi", "gorevini", "gorevleri", "gorevlerini",
        "is", "isi", "isini", "isleri", "islerini",
        "kayit", "kaydi", "kaydini",
        "not", "notu", "notunu",
        "bunu", "sunu", "onu", "bu", "su", "o", "bunlari", "sunlari", "onlari",
        "ve", "ile", "icin", "bana", "lutfen", "diye", "olan", "hakkinda", "ilgili", "sey", "seyi"
    ]

    /// Folded words mapped to a canonical stem before suffix stripping ("konusu" → "konu").
    private static let canonicalWords: [String: String] = [
        "konusu": "konu", "konusunu": "konu", "konusuna": "konu", "konusunda": "konu",
        "konusuyla": "konu", "konuyu": "konu", "konunun": "konu"
    ]

    /// Folded case suffixes, longest first (i ı u ü yi yı yu yü e a ye ya de da te ta den dan ten tan in ın un ün
    /// nin nın nun nün le la yle yla).
    private static let caseSuffixes: [String] = [
        "yla", "yle", "nin", "nun", "dan", "den", "tan", "ten",
        "yi", "yu", "ya", "ye", "da", "de", "ta", "te", "in", "un", "la", "le",
        "i", "u", "a", "e"
    ]

    /// Honorifics ignored when a person filter is applied ("Ahmet Bey" → "ahmet").
    private static let honorifics: Set<String> = [
        "bey", "hanim", "usta", "hoca", "abi", "agabey", "abla", "sef", "mudur"
    ]

    /// Tokens: TurkishText.searchKey, apostrophe suffix and common case suffixes stripped
    /// (i ı u ü yi yı yu yü e a ye ya de da te ta den dan ten tan in ın un ün nin nın le la yle yla),
    /// stop words removed (hatırlatma, hatırlatmasını, görev, işi, konusu→konu, bunu, şunu).
    public static func tokens(_ text: String) -> [String] {
        return tokenPairs(text).map { (pair: (word: String, token: String)) -> String in pair.token }
    }

    /// `tokens(_:)` with each token paired with the folded word it came from (apostrophe part cut, no suffix
    /// stripping): "Ayşe'ye" → ("ayse", "ayse"), "Ayşeye" → ("ayseye", "ayse"), "Ayşe" → ("ayse", "ays").
    static func tokenPairs(_ text: String) -> [(word: String, token: String)] {
        var result: [(word: String, token: String)] = []
        let rawWords = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
        for rawWord in rawWords {
            var word = String(rawWord)
            var hadApostrophe = false
            if let index = word.firstIndex(where: { apostrophes.contains($0) }) {
                word = String(word[word.startIndex..<index])
                hadApostrophe = true
            }
            let parts = TurkishText.searchKey(word).split(separator: " ")
            for part in parts {
                let folded = String(part)
                if let token = normalizedToken(folded, stripSuffix: !hadApostrophe) {
                    result.append((word: folded, token: token))
                }
            }
        }
        return result
    }

    /// Token-set similarity over title + person + project name + originalText (title weighted 2×);
    /// prefix match of ≥ 4 letters counts as a hit ("teklif" ~ "teklifi").
    public static func score(query: String, item: Item, projectName: String?) -> Double {
        let queryTokens = unique(tokens(query))
        guard !queryTokens.isEmpty else { return 0 }
        var titleSource = tokens(item.title)
        var otherTokens: [String] = []
        if let person = item.person {
            if item.kind == .waiting {
                // Waiting titles drop the person by design (02 §11.4): the person is part of the "title" here.
                titleSource.append(contentsOf: tokens(person))
            } else {
                otherTokens.append(contentsOf: tokens(person))
            }
        }
        let titleTokens = unique(titleSource)
        if let projectName = projectName {
            otherTokens.append(contentsOf: tokens(projectName))
        }
        if let original = item.originalText {
            otherTokens.append(contentsOf: tokens(original))
        }
        otherTokens = unique(otherTokens)

        var total = 0.0
        for token in queryTokens {
            let inTitle = bestMatch(token, in: titleTokens)
            let inOther = bestMatch(token, in: otherTokens) * 0.5
            total += max(inTitle, inOther)
        }
        let coverage = total / Double(queryTokens.count)

        var matchedTitleTokens = 0
        for token in titleTokens where bestMatch(token, in: queryTokens) > 0 {
            matchedTitleTokens += 1
        }
        let titleCoverage = titleTokens.isEmpty ? 0.0 : Double(matchedTitleTokens) / Double(titleTokens.count)

        let value = 0.85 * coverage + 0.15 * titleCoverage
        return min(1.0, max(0.0, value))
    }

    /// Only open, non-deleted items; optional filters narrow the set first (date = same day as anchor;
    /// for snooze commands the caller passes `command.targetDate ?? nil` as `date`). `preferWaiting` (G5 "geldi")
    /// adds +0.15 to waiting items.
    public static func rank(query: String?, person: String?, project: String?, date: Date?, preferWaiting: Bool,
                            items: [Item], projects: [Project], calendar: Calendar) -> [FuzzyMatch] {
        var candidates = items.filter { $0.status == .open && $0.deletedAt == nil }

        if let date = date {
            candidates = candidates.filter { item in
                guard let anchor = item.anchorDate else { return false }
                return calendar.isDate(anchor, inSameDayAs: date)
            }
        }
        let projectFilter = nonEmpty(project)
        if let projectName = projectFilter {
            let ids = projectIDs(named: projectName, in: projects)
            candidates = candidates.filter { item in
                guard let id = item.projectID else { return false }
                return ids.contains(id)
            }
        }
        let personFilter = nonEmpty(person)
        if let personName = personFilter {
            candidates = candidates.filter { personMatches(personName, item: $0) }
        }

        let queryText = query ?? ""
        let hasQuery = !tokens(queryText).isEmpty
        let hasFilter = date != nil || projectFilter != nil || personFilter != nil
        var result: [FuzzyMatch] = []

        if !hasQuery {
            // No usable target words: only filters can point at an item ("yarınki… iptal et" without a noun).
            guard hasFilter, !candidates.isEmpty else { return [] }
            let base = candidates.count == 1 ? 0.70 : 0.50
            for item in candidates {
                var value = base
                if preferWaiting && item.kind == .waiting {
                    value = min(1.0, value + 0.15)
                }
                result.append(FuzzyMatch(itemID: item.id, score: value))
            }
        } else {
            for item in candidates {
                let projectName = name(ofProject: item.projectID, in: projects)
                var value = score(query: queryText, item: item, projectName: projectName)
                if item.kind == .note {
                    value *= 0.8        // notes rarely are the target of "yaptım / ertele"
                }
                if preferWaiting && item.kind == .waiting {
                    value = min(1.0, value + 0.15)
                }
                if value >= minimumRankScore {
                    result.append(FuzzyMatch(itemID: item.id, score: value))
                }
            }
        }
        return sortMatches(result, items: candidates)
    }

    public static func decide(_ ranked: [FuzzyMatch]) -> MatchDecision {
        let sorted = ranked.filter { $0.score > 0 }.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.itemID.uuidString < rhs.itemID.uuidString
        }
        guard let best = sorted.first else { return MatchDecision.none }
        let second = sorted.count > 1 ? sorted[1].score : 0
        if best.score >= 0.60 && (second < 0.40 || best.score - second >= 0.25) {
            return .single(best.itemID)
        }
        var candidates: [UUID] = []
        for match in sorted where match.score >= 0.40 && !candidates.contains(match.itemID) {
            candidates.append(match.itemID)
            if candidates.count == 3 {
                break
            }
        }
        if candidates.count >= 2 {
            return .ambiguous(candidates)
        }
        return MatchDecision.none
    }

    // MARK: - Internal helpers (also used by AgendaBuilder query filters)

    /// true when every name token of `person` (honorifics ignored) appears in the item's person, title or original text.
    static func personMatches(_ person: String, item: Item) -> Bool {
        let wanted = unique(tokens(person).filter { !honorifics.contains($0) })
        guard !wanted.isEmpty else { return true }
        var haystack: [String] = tokens(item.title)
        if let itemPerson = item.person {
            haystack.append(contentsOf: tokens(itemPerson))
        }
        if let original = item.originalText {
            haystack.append(contentsOf: tokens(original))
        }
        for token in wanted where bestMatch(token, in: haystack) == 0 {
            return false
        }
        return true
    }

    /// Ids of projects whose name or alias matches `name` (searchKey comparison).
    static func projectIDs(named name: String, in projects: [Project]) -> Set<UUID> {
        let key = TurkishText.searchKey(name)
        var ids = Set<UUID>()
        guard !key.isEmpty else { return ids }
        for project in projects where project.allNames.contains(where: { TurkishText.searchKey($0) == key }) {
            ids.insert(project.id)
        }
        return ids
    }

    static func name(ofProject id: UUID?, in projects: [Project]) -> String? {
        guard let id = id else { return nil }
        return projects.first(where: { $0.id == id })?.name
    }

    // MARK: - Private helpers

    private static func normalizedToken(_ raw: String, stripSuffix: Bool) -> String? {
        guard !raw.isEmpty else { return nil }
        if stopWords.contains(raw) {
            return nil
        }
        if let canonical = canonicalWords[raw] {
            return canonical
        }
        var token = raw
        let isAlphabetic = token.allSatisfy { $0.isLetter }
        if stripSuffix && isAlphabetic {
            for suffix in caseSuffixes where token.hasSuffix(suffix) && token.count - suffix.count >= 3 {
                token = String(token.dropLast(suffix.count))
                break
            }
        }
        if stopWords.contains(token) {
            return nil
        }
        if isAlphabetic && token.count < 2 {
            return nil
        }
        return token
    }

    /// 1.0 equal · 0.9 the shorter (≥ 3 letters) is a prefix of the longer · 0.8 common prefix ≥ 4 letters that
    /// covers all but the last letter of the shorter ("yedeg" ~ "yedek") · 0 otherwise. Tokens with digits: exact only.
    static func matchQuality(_ a: String, _ b: String) -> Double {
        if a == b {
            return 1.0
        }
        let hasDigit = a.contains(where: { $0.isNumber }) || b.contains(where: { $0.isNumber })
        if hasDigit {
            return 0
        }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        if shorter.count >= 3 && longer.hasPrefix(shorter) {
            return 0.9
        }
        var common = 0
        for (x, y) in zip(shorter, longer) {
            if x != y {
                break
            }
            common += 1
        }
        if common >= 4 && common >= shorter.count - 1 {
            return 0.8
        }
        return 0
    }

    private static func bestMatch(_ token: String, in list: [String]) -> Double {
        var best = 0.0
        for candidate in list {
            let quality = matchQuality(token, candidate)
            if quality > best {
                best = quality
                if best >= 1.0 {
                    break
                }
            }
        }
        return best
    }

    private static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in list where !seen.contains(value) {
            seen.insert(value)
            out.append(value)
        }
        return out
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Score desc, then earlier anchor (undated last), then id — deterministic.
    private static func sortMatches(_ matches: [FuzzyMatch], items: [Item]) -> [FuzzyMatch] {
        var anchors: [UUID: Date] = [:]
        for item in items {
            if let anchor = item.anchorDate {
                anchors[item.id] = anchor
            }
        }
        return matches.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let left = anchors[lhs.itemID] ?? Date.distantFuture
            let right = anchors[rhs.itemID] ?? Date.distantFuture
            if left != right {
                return left < right
            }
            return lhs.itemID.uuidString < rhs.itemID.uuidString
        }
    }
}
