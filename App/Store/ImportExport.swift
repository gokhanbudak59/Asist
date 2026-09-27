// App/Store/ImportExport.swift (04 §3.6.4) — WP4.
// Pure, non-isolated helpers: the frozen JSON coding of `AppData`, the structural check of 05a #22 and the
// import merge/replace rules. Type declarations that §3.6.4 assigns to DataStore.swift (`ImportPreview`,
// `ImportMode`) are NOT declared here.
import Foundation
import AsistCore

/// The one and only JSON configuration of the store (§3.1, §9 r36): `.iso8601` both ways — frozen forever.
enum StoreCoding {
    static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ document: AppData, pretty: Bool) throws -> Data {
        try makeEncoder(pretty: pretty).encode(document)
    }

    /// nil when the bytes are not a decodable document (invalid JSON, not an object). Logs the reason only
    /// (never the content).
    static func decode(_ bytes: Data, source: String) -> AppData? {
        do {
            return try makeDecoder().decode(AppData.self, from: bytes)
        } catch {
            var line: String = "Çözülemedi (" + source + ", " + String(bytes.count) + " bayt): "
            line += BackupManager.describe(error)
            AsistLog.error(line, .store)
            return nil
        }
    }

    /// Top-level JSON object, or nil (not JSON / not an object). `JSONSerialization` is used only for this check.
    static func rawObject(_ bytes: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: bytes, options: []) else { return nil }
        return object as? [String: Any]
    }

    /// Number of raw "items"/"projects"/"places" elements that did not survive lenient decoding (05a #22).
    /// A present value that is not an array counts with all its entries (at least 1).
    static func droppedElementCount(raw: [String: Any], decoded: AppData) -> Int {
        let itemsDropped = max(0, rawElementCount(raw["items"]) - decoded.items.count)
        let projectsDropped = max(0, rawElementCount(raw["projects"]) - decoded.projects.count)
        let placesDropped = max(0, rawElementCount(raw["places"]) - decoded.places.count)
        return itemsDropped + projectsDropped + placesDropped
    }

    /// A JSON object that carries at least one of Asist's top-level keys (rejects unrelated JSON files on import).
    static func looksLikeAsistDocument(_ raw: [String: Any]) -> Bool {
        let keys: [String] = ["items", "projects", "settings", "meta", "schemaVersion"]
        for key in keys where raw[key] != nil {
            return true
        }
        return false
    }

    private static func rawElementCount(_ value: Any?) -> Int {
        guard let value = value else { return 0 }
        if value is NSNull { return 0 }
        if let array = value as? [Any] { return array.count }
        if let dictionary = value as? [String: Any] { return max(1, dictionary.count) }
        return 1
    }
}

/// Export / import helpers used by `DataStore.exportData / importPreview / importData`.
enum ImportExport {
    /// Pretty-printed, sorted keys, iso8601 (DataSettingsView shares it as `Asist-yedek-….json`).
    static func exportBytes(_ document: AppData) throws -> Data {
        try StoreCoding.encode(document, pretty: true)
    }

    /// nil = not an Asist file (unrelated JSON, invalid JSON). Unknown keys/values decode leniently.
    static func parse(_ bytes: Data) -> AppData? {
        guard let raw = StoreCoding.rawObject(bytes) else {
            AsistLog.error("İçe aktarma: JSON nesnesi değil (" + String(bytes.count) + " bayt)", .store)
            return nil
        }
        guard StoreCoding.looksLikeAsistDocument(raw) else {
            AsistLog.error("İçe aktarma: Asist dosyası değil", .store)
            return nil
        }
        guard let document = StoreCoding.decode(bytes, source: "import") else { return nil }
        let dropped = StoreCoding.droppedElementCount(raw: raw, decoded: document)
        if dropped > 0 {
            AsistLog.error("İçe aktarma: " + String(dropped) + " öğe okunamadı ve atlandı", .store)
        }
        let currentBuild = BackupManager.currentBuild()
        if currentBuild > 0 && document.meta.writerBuild > currentBuild {
            let writer: String = String(document.meta.writerBuild)
            let mine: String = String(currentBuild)
            AsistLog.info("İçe aktarma: dosya daha yeni bir sürümle yazılmış (" + writer + " > " + mine + ")", .store)
        }
        return document
    }

    static func preview(_ document: AppData) -> ImportPreview {
        ImportPreview(itemCount: document.items.count,
                      projectCount: document.projects.count,
                      placeCount: document.places.count)
    }

    /// merge: items/projects/places by id, newer `updatedAt` wins (places have no `updatedAt`: the local copy
    /// wins, new ones are added); settings and meta unchanged.
    static func merged(local: AppData, incoming: AppData) -> AppData {
        var result = local
        result.items = mergeByID(local.items, incoming.items) { candidate, existing in
            candidate.updatedAt > existing.updatedAt
        }
        result.projects = mergeByID(local.projects, incoming.projects) { candidate, existing in
            candidate.updatedAt > existing.updatedAt
        }
        result.places = mergeByID(local.places, incoming.places) { _, _ in
            false
        }
        return result
    }

    /// replace: items, projects, places **and settings** replaced; `meta` stays local except
    /// `lastEndOfDayMove = nil` (05a #24). A completed onboarding is never undone by an older file.
    static func replaced(local: AppData, incoming: AppData) -> AppData {
        var result = local
        result.schemaVersion = AppData.currentSchemaVersion
        result.items = uniqueByID(incoming.items)
        result.projects = uniqueByID(incoming.projects)
        result.places = uniqueByID(incoming.places)
        var settings = incoming.settings
        settings.onboardingCompleted = incoming.settings.onboardingCompleted || local.settings.onboardingCompleted
        result.settings = settings
        result.meta.lastEndOfDayMove = nil
        return result
    }

    // MARK: - Private

    /// Local elements are kept untouched and in order; an incoming element replaces the (first) local one with
    /// the same id when `incomingWins`; unknown ids are appended. Duplicate ids never trap (no
    /// `uniqueKeysWithValues`).
    private static func mergeByID<T: Identifiable>(_ local: [T], _ incoming: [T],
                                                   incomingWins: (T, T) -> Bool) -> [T] {
        var result: [T] = local
        var indexByID: [T.ID: Int] = [:]
        for (index, element) in result.enumerated() where indexByID[element.id] == nil {
            indexByID[element.id] = index
        }
        for element in incoming {
            if let index = indexByID[element.id] {
                if incomingWins(element, result[index]) {
                    result[index] = element
                }
            } else {
                indexByID[element.id] = result.count
                result.append(element)
            }
        }
        return result
    }

    /// First occurrence of every id wins (a hand-edited file may contain duplicates).
    private static func uniqueByID<T: Identifiable>(_ elements: [T]) -> [T] {
        var seen = Set<T.ID>()
        var result: [T] = []
        result.reserveCapacity(elements.count)
        for element in elements where !seen.contains(element.id) {
            seen.insert(element.id)
            result.append(element)
        }
        return result
    }
}
