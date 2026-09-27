// API: Packages/AsistCore/Sources/AsistCore/People/PeopleBoard.swift
// Revision 4 (07 §8.2, F5): "Kişiler panosu" — people and firms derived from the records' person field (no new
// model), their open Takip items, open work that names them, recent completions and the combined reminder message.
import Foundation

public struct PersonSummary: Equatable, Identifiable {
    public var id: String { key }
    /// PeopleBoard.key(for: name): searchKey without a leading "sayın" or trailing honorifics ("Ahmet Bey" and
    /// "Ahmet" → "ahmet") — the `Route.person` value.
    public var key: String
    /// Spelling with the most words (keeps the honorific for the greeting), then the most frequent, then the most
    /// recently updated item's spelling.
    public var displayName: String
    /// Open .waiting items with this person, oldest anchor (then createdAt) first.
    public var followUps: [Item]
    /// Of `followUps`, the ones overdue at `now`.
    public var overdueFollowUps: Int
    /// Open, not note, not waiting: person == key, or the title names the person (every name token ≥ 3 characters,
    /// honorifics removed); sorted by anchor (undated last).
    public var openItems: [Item]
    /// status .done, person == key, completedAt ≥ now − 60 days; newest first; ≤ 5.
    public var recentDone: [Item]
    /// max(completedAt ?? updatedAt) over non-deleted items with person == key.
    public var lastActivity: Date?

    public init(key: String, displayName: String, followUps: [Item] = [], overdueFollowUps: Int = 0,
                openItems: [Item] = [], recentDone: [Item] = [], lastActivity: Date? = nil) {
        self.key = key
        self.displayName = displayName
        self.followUps = followUps
        self.overdueFollowUps = overdueFollowUps
        self.openItems = openItems
        self.recentDone = recentDone
        self.lastActivity = lastActivity
    }
}

public enum PeopleBoard {
    /// Folded honorifics: dropped from the end of a person key and ignored when a title is searched for a person's
    /// name ("Ahmet Bey" → "ahmet").
    public static let honorifics: Set<String> = [
        "bey", "hanim", "usta", "hoca", "hocam", "abi", "abim", "agabey", "abla", "sef", "mudur", "efendi",
        "beyefendi", "hanimefendi", "sayin"
    ]
    public static let recentDoneDays = 60
    public static let activeDays = 90
    public static let maxRecentDone = 5

    /// searchKey(trimmed name) without one leading "sayin" and without trailing honorific words, so "Ahmet",
    /// "Ahmet Bey" and "Sayın Ahmet Bey" share "ahmet". Middle words are kept ("Usta Ahmet" → "usta ahmet"); a name
    /// made only of honorifics keeps its full key ("Şef" → "sef").
    public static func key(for name: String) -> String {
        let full = TurkishText.searchKey(name.trimmingCharacters(in: .whitespacesAndNewlines))
        var words = full.split(separator: " ").map { (part: Substring) -> String in String(part) }
        if let first = words.first, first == "sayin" {
            words.removeFirst()
        }
        while let last = words.last, honorifics.contains(last) {
            words.removeLast()
        }
        if words.isEmpty {
            return full
        }
        return words.joined(separator: " ")
    }

    /// Everyone with a non-deleted item whose `person` is non-empty, kept when an open item exists or lastActivity is
    /// within 90 days; sorted (overdueFollowUps desc, followUps.count desc, openItems.count desc, lastActivity desc,
    /// key asc).
    public static func build(items: [Item], now: Date, calendar: Calendar) -> [PersonSummary] {
        let prepared = prepare(items)
        var keys: [String] = []
        var seen = Set<String>()
        for entry in prepared where !entry.personKey.isEmpty {
            if seen.contains(entry.personKey) {
                continue
            }
            seen.insert(entry.personKey)
            keys.append(entry.personKey)
        }
        let activeSince = now.addingTimeInterval(-Double(activeDays) * 86_400)
        var result: [PersonSummary] = []
        for key in keys {
            guard let summary = makeSummary(key: key, prepared: prepared, now: now, calendar: calendar) else { continue }
            var recentlyActive = false
            if let last = summary.lastActivity {
                recentlyActive = last >= activeSince
            }
            if !summary.followUps.isEmpty || !summary.openItems.isEmpty || recentlyActive {
                result.append(summary)
            }
        }
        return result.sorted { (lhs: PersonSummary, rhs: PersonSummary) -> Bool in
            isOrderedBefore(lhs, rhs)
        }
    }

    /// Same computation for one key (nil when no non-deleted item carries it). The key is normalized again, so an
    /// older route such as "ahmet bey" still resolves to "ahmet".
    public static func summary(forKey key: String, items: [Item], now: Date, calendar: Calendar) -> PersonSummary? {
        let normalized = PeopleBoard.key(for: key)
        guard !normalized.isEmpty else { return nil }
        return makeSummary(key: normalized, prepared: prepare(items), now: now, calendar: calendar)
    }

    /// "" when no follow-ups. 1 item: "<greeting> <title> konusunda son durum nedir? Teşekkürler." ≥ 2 items:
    /// "<greeting>\nAşağıdaki konularda son durumu paylaşabilir misiniz?\n• <title> (<n> gündür bekliyorum)\n…\nTeşekkürler."
    /// greeting = "Merhaba <greetingName>," or "Merhaba,". Suffix only when n ≥ 1 (days from createdAt day to now day).
    /// Signature line "\n<userName>" when userName (trimmed) is non-empty.
    public static func reminderMessage(for summary: PersonSummary, greetingName: String?, userName: String,
                                       now: Date, calendar: Calendar) -> String {
        guard let first = summary.followUps.first else { return "" }
        let name = (greetingName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty ? "Merhaba," : "Merhaba " + name + ","
        var text: String
        if summary.followUps.count == 1 {
            let title = cleanTitle(first.title)
            if title.isEmpty {
                text = greeting + " son durum nedir? Teşekkürler."
            } else {
                text = greeting + " " + title + " konusunda son durum nedir? Teşekkürler."
            }
        } else {
            var lines: [String] = [greeting, "Aşağıdaki konularda son durumu paylaşabilir misiniz?"]
            for item in summary.followUps {
                let title = cleanTitle(item.title)
                var line = "• " + (title.isEmpty ? "Başlıksız" : title)
                let days = dayDistance(from: item.createdAt, to: now, calendar: calendar)
                if days >= 1 {
                    line += " (" + String(days) + " gündür bekliyorum)"
                }
                lines.append(line)
            }
            lines.append("Teşekkürler.")
            text = lines.joined(separator: "\n")
        }
        let signature = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !signature.isEmpty {
            text += "\n" + signature
        }
        return text
    }

    // MARK: - Private

    fileprivate struct TitleWord {
        /// Folded title word (apostrophe part cut, no suffix stripping).
        var word: String
        /// Its FuzzyMatcher token.
        var token: String
    }

    fileprivate struct Prepared {
        var item: Item
        /// PeopleBoard.key(for:) of the trimmed person ("" when none).
        var personKey: String
        /// Trimmed person spelling.
        var spelling: String
        /// FuzzyMatcher.tokenPairs(title) — only for open, non-note, non-waiting items (mention candidates).
        var titleWords: [TitleWord]
    }

    private static func prepare(_ items: [Item]) -> [Prepared] {
        var result: [Prepared] = []
        for item in items where item.status != .deleted {
            let spelling = (item.person ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var words: [TitleWord] = []
            if item.isOpen && item.kind != .note && item.kind != .waiting {
                for pair in FuzzyMatcher.tokenPairs(item.title) {
                    words.append(TitleWord(word: pair.word, token: pair.token))
                }
            }
            let personKey = spelling.isEmpty ? "" : PeopleBoard.key(for: spelling)
            result.append(Prepared(item: item, personKey: personKey, spelling: spelling, titleWords: words))
        }
        return result
    }

    private static func makeSummary(key: String, prepared: [Prepared], now: Date,
                                    calendar: Calendar) -> PersonSummary? {
        let nameTokens = mentionTokens(forKey: key)
        let recentSince = now.addingTimeInterval(-Double(recentDoneDays) * 86_400)
        var carriesKey = false
        var spellingCounts: [String: Int] = [:]
        var spellingLatest: [String: Date] = [:]
        var followUps: [Item] = []
        var openItems: [Item] = []
        var done: [Item] = []
        var lastActivity: Date? = nil

        for entry in prepared {
            let item = entry.item
            let ownsKey = entry.personKey == key
            if ownsKey {
                carriesKey = true
                spellingCounts[entry.spelling] = (spellingCounts[entry.spelling] ?? 0) + 1
                if let latest = spellingLatest[entry.spelling] {
                    if item.updatedAt > latest {
                        spellingLatest[entry.spelling] = item.updatedAt
                    }
                } else {
                    spellingLatest[entry.spelling] = item.updatedAt
                }
                let activity = item.completedAt ?? item.updatedAt
                if let current = lastActivity {
                    if activity > current {
                        lastActivity = activity
                    }
                } else {
                    lastActivity = activity
                }
            }
            if item.isOpen {
                if item.kind == .waiting {
                    if ownsKey {
                        followUps.append(item)
                    }
                } else if item.kind != .note {
                    if ownsKey || mentions(entry.titleWords, nameTokens: nameTokens) {
                        openItems.append(item)
                    }
                }
            } else if item.status == .done && ownsKey && item.kind != .note {
                if let completed = item.completedAt, completed >= recentSince {
                    done.append(item)
                }
            }
        }
        guard carriesKey else { return nil }

        // Display spelling: most words ("Ahmet Bey" over "Ahmet", for the greeting), then most frequent, then most
        // recently updated, then alphabetical (deterministic).
        var displayName = ""
        var bestWords = -1
        var bestCount = -1
        var bestLatest = Date.distantPast
        for spelling in spellingCounts.keys.sorted() {
            let words = spelling.split(whereSeparator: { (ch: Character) -> Bool in ch.isWhitespace }).count
            let count = spellingCounts[spelling] ?? 0
            let latest = spellingLatest[spelling] ?? Date.distantPast
            var better = false
            if words != bestWords {
                better = words > bestWords
            } else if count != bestCount {
                better = count > bestCount
            } else {
                better = latest > bestLatest
            }
            if better {
                displayName = spelling
                bestWords = words
                bestCount = count
                bestLatest = latest
            }
        }

        followUps.sort { (lhs: Item, rhs: Item) -> Bool in anchorOrder(lhs, rhs) }
        openItems.sort { (lhs: Item, rhs: Item) -> Bool in anchorOrder(lhs, rhs) }
        done.sort { (lhs: Item, rhs: Item) -> Bool in
            let left = lhs.completedAt ?? Date.distantPast
            let right = rhs.completedAt ?? Date.distantPast
            if left != right {
                return left > right
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var overdue = 0
        for item in followUps where item.isOverdue(at: now, calendar: calendar) {
            overdue += 1
        }
        return PersonSummary(key: key, displayName: displayName, followUps: followUps, overdueFollowUps: overdue,
                             openItems: openItems, recentDone: Array(done.prefix(maxRecentDone)),
                             lastActivity: lastActivity)
    }

    fileprivate struct NameToken {
        /// Folded name word ("ayse").
        var word: String
        /// Its FuzzyMatcher form when different ("ays"); nil otherwise.
        var stripped: String?
    }

    /// Name tokens of `key` that a title must contain: honorifics and words shorter than 3 characters removed.
    private static func mentionTokens(forKey key: String) -> [NameToken] {
        var result: [NameToken] = []
        for part in key.split(separator: " ") {
            let word = String(part)
            if word.count < 3 || honorifics.contains(word) {
                continue
            }
            var stripped: String? = nil
            if let token = FuzzyMatcher.tokens(word).first, token != word {
                stripped = token
            }
            result.append(NameToken(word: word, stripped: stripped))
        }
        return result
    }

    /// Every name token must match a title word: the word's token is the full name ("Ayşe'ye", "Ayşeye" → "ayse"),
    /// or the word's token is the name's stripped form AND the folded word itself starts with the full name
    /// ("Ayşe" → word "ayse", token "ays"). The second rule keeps unrelated words whose token happens to equal the
    /// stripped name out ("emin" for Emine, "gül" for Gülten).
    private static func mentions(_ titleWords: [TitleWord], nameTokens: [NameToken]) -> Bool {
        guard !nameTokens.isEmpty, !titleWords.isEmpty else { return false }
        for name in nameTokens {
            var found = false
            for title in titleWords {
                if title.token == name.word {
                    found = true
                } else if let stripped = name.stripped, title.token == stripped, title.word.hasPrefix(name.word) {
                    found = true
                }
                if found {
                    break
                }
            }
            if !found {
                return false
            }
        }
        return true
    }

    /// Anchor ascending (undated last), then createdAt, then id.
    private static func anchorOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        switch (lhs.anchorDate, rhs.anchorDate) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// overdueFollowUps desc, followUps desc, openItems desc, lastActivity desc (nil last), key asc.
    private static func isOrderedBefore(_ lhs: PersonSummary, _ rhs: PersonSummary) -> Bool {
        if lhs.overdueFollowUps != rhs.overdueFollowUps {
            return lhs.overdueFollowUps > rhs.overdueFollowUps
        }
        if lhs.followUps.count != rhs.followUps.count {
            return lhs.followUps.count > rhs.followUps.count
        }
        if lhs.openItems.count != rhs.openItems.count {
            return lhs.openItems.count > rhs.openItems.count
        }
        switch (lhs.lastActivity, rhs.lastActivity) {
        case let (left?, right?):
            if left != right {
                return left > right
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        return lhs.key < rhs.key
    }

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Calendar days between the two instants' days (b − a).
    private static func dayDistance(from a: Date, to b: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: a)
        let endDay = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }
}
