// FILE: Packages/AsistCore/Sources/AsistCore/Parser/ParserSettings+App.swift
import Foundation

extension ParserSettings {
    /// App-side construction. Aliases are passed as additional project/place names; the caller maps
    /// the parser's returned name back to an id by folded match over `allNames` (ItemFactory does this).
    /// `people` = `ParserSettings.frequentPeople(in: store.items)` (05b §6.1: fixes lowercase names without apostrophes).
    public init(settings: AppSettings, projects: [Project], places: [Place], people: [String] = []) {
        self.init()
        defaultDayTime = settings.defaultDayTime
        sabah = settings.sabah
        ogledenOnce = settings.ogledenOnce
        ogle = settings.ogle
        ogledenSonra = settings.ogledenSonra
        aksamustu = settings.aksamustu
        aksam = settings.aksam
        gece = settings.gece
        mesaiBasi = settings.workStart
        mesaiBitimi = settings.workEnd
        belirsizSaatlerOgledenSonra = settings.ambiguousHoursPM
        knownProjects = projects.filter { !$0.archived }.flatMap { $0.allNames }
        knownPlaces = places.flatMap { $0.allNames }
        knownPeople = people
    }

    /// Distinct `Item.person` values used at least `minCount` times (folded comparison, first spelling wins),
    /// most frequent first, at most 50. Deleted items are ignored.
    public static func frequentPeople(in items: [Item], minCount: Int = 2) -> [String] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for item in items where item.status != .deleted {
            guard let raw = item.person?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let key = TurkishText.fold(raw)
            counts[key, default: 0] += 1
            if spelling[key] == nil {
                spelling[key] = raw
            }
        }
        let ranked = counts.filter { $0.value >= minCount }.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        return ranked.prefix(50).compactMap { spelling[$0.key] }
    }
}
