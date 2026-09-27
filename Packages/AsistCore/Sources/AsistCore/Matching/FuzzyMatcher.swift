// API: Packages/AsistCore/Sources/AsistCore/Matching/FuzzyMatcher.swift
// WP0 STUB (04 §3.5.5) — WP2 replaces this file. `decide` follows the documented thresholds; scoring is naive.
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
    /// Tokens: TurkishText.searchKey, apostrophe suffix and common case suffixes stripped
    /// (i ı u ü yi yı yu yü e a ye ya de da te ta den dan ten tan in ın un ün nin nın le la yle yla),
    /// stop words removed (hatırlatma, hatırlatmasını, görev, işi, konusu→konu, bunu, şunu).
    public static func tokens(_ text: String) -> [String] {
        // WP0 STUB: searchKey words only.
        TurkishText.searchKey(text).split(separator: " ").map { String($0) }
    }

    /// Token-set similarity over title + person + project name + originalText (title weighted 2×);
    /// prefix match of ≥ 4 letters counts as a hit ("teklif" ~ "teklifi").
    public static func score(query: String, item: Item, projectName: String?) -> Double {
        // WP0 STUB: share of query tokens found in title/person/project.
        let queryTokens = Set(tokens(query))
        guard !queryTokens.isEmpty else { return 0 }
        let haystack = Set(tokens(item.title + " " + (item.person ?? "") + " " + (projectName ?? "")))
        let hits = queryTokens.intersection(haystack).count
        return Double(hits) / Double(queryTokens.count)
    }

    /// Only open, non-deleted items; optional filters narrow the set first (date = same day as anchor;
    /// for snooze commands the caller passes `command.targetDate ?? nil` as `date`). `preferWaiting` (G5 "geldi")
    /// adds +0.15 to waiting items.
    public static func rank(query: String?, person: String?, project: String?, date: Date?, preferWaiting: Bool,
                            items: [Item], projects: [Project], calendar: Calendar) -> [FuzzyMatch] {
        // WP0 STUB: query text only.
        guard let query = query, !query.isEmpty else { return [] }
        var result: [FuzzyMatch] = []
        for item in items where item.isOpen {
            let projectName = item.projectID.flatMap { id in projects.first(where: { $0.id == id })?.name }
            var value = score(query: query, item: item, projectName: projectName)
            if preferWaiting && item.kind == .waiting {
                value = min(1, value + 0.15)
            }
            if value > 0 {
                result.append(FuzzyMatch(itemID: item.id, score: value))
            }
        }
        return result.sorted { $0.score > $1.score }
    }

    public static func decide(_ ranked: [FuzzyMatch]) -> MatchDecision {
        let sorted = ranked.sorted { $0.score > $1.score }
        guard let best = sorted.first else { return MatchDecision.none }
        let second = sorted.count > 1 ? sorted[1].score : 0
        if best.score >= 0.60 && (second < 0.40 || best.score - second >= 0.25) {
            return .single(best.itemID)
        }
        let candidates = sorted.filter { $0.score >= 0.40 }.prefix(3).map { $0.itemID }
        if candidates.count >= 2 {
            return .ambiguous(Array(candidates))
        }
        return MatchDecision.none
    }
}
