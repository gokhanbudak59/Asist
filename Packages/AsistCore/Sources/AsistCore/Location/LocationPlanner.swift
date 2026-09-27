// API: Packages/AsistCore/Sources/AsistCore/Location/LocationPlanner.swift
// Revision 4, F6 (07 §9.2, R4-D7; 04 Appendix B.3 with the 07 deltas). Pure: which items get an
// `asist.loc.<UUID>` geofence request (≤ 10), its content and fingerprint, plus the small text helpers of the
// Konumlar screens. The app (LocationService) turns the specs into UNLocationNotificationTrigger requests.
// "Configured" place = coordinates not exactly (0, 0) — empty slots (Fabrika / Ofis / Ev) keep 0, 0 (no model change).
import Foundation

/// One desired `asist.loc.<UUID>` request (07 §9.2).
public struct LocationRequestSpec: Equatable {
    /// NotificationID.location(itemID)
    public var id: String
    public var itemID: UUID
    public var latitude: Double
    public var longitude: Double
    /// min(1000, max(100, place.radiusMeters))
    public var radiusMeters: Double
    /// trigger == .onArrive
    public var notifyOnEntry: Bool
    /// trigger == .onLeave
    public var notifyOnExit: Bool
    public var text: NotificationText
    /// NotificationCategoryID.item; .followUp for Takip items.
    public var categoryID: String
    /// NotificationID.thread(itemID)
    public var threadID: String
    /// StableHash.fnv1a64 over everything that affects the system request (see `makeFingerprint(…)`).
    public var fingerprint: String

    public init(id: String, itemID: UUID, latitude: Double, longitude: Double, radiusMeters: Double,
                notifyOnEntry: Bool, notifyOnExit: Bool, text: NotificationText, categoryID: String,
                threadID: String) {
        self.id = id
        self.itemID = itemID
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.text = text
        self.categoryID = categoryID
        self.threadID = threadID
        self.fingerprint = LocationRequestSpec.makeFingerprint(id: id, latitude: latitude, longitude: longitude,
                                                               radiusMeters: radiusMeters,
                                                               notifyOnEntry: notifyOnEntry,
                                                               notifyOnExit: notifyOnExit, text: text,
                                                               categoryID: categoryID)
    }

    /// StableHash.fnv1a64([id, String(lat), String(lon), String(radius), entry ? "1" : "0", exit ? "1" : "0",
    /// title, subtitle, body, categoryID].joined(separator: "|"))
    public static func makeFingerprint(id: String, latitude: Double, longitude: Double, radiusMeters: Double,
                                       notifyOnEntry: Bool, notifyOnExit: Bool, text: NotificationText,
                                       categoryID: String) -> String {
        let entryText: String = notifyOnEntry ? "1" : "0"
        let exitText: String = notifyOnExit ? "1" : "0"
        var parts: [String] = [id, String(latitude), String(longitude), String(radiusMeters)]
        parts.append(entryText)
        parts.append(exitText)
        parts.append(text.title)
        parts.append(text.subtitle)
        parts.append(text.body)
        parts.append(categoryID)
        return StableHash.fnv1a64(parts.joined(separator: "|"))
    }
}

public enum LocationPlanner {
    /// iOS allows 20 regions per app; Asist uses at most 10 (they are subtracted from the item budget, R4-D7).
    public static let maxRequests = 10
    /// Yarıçap chips of the place editor (metres).
    public static let radiusChoices: [Double] = [100, 150, 250, 500, 1000]
    /// Empty slots the Konumlar screen seeds once (latitude 0, longitude 0, radius 150).
    public static let seedPlaceNames: [String] = ["Fabrika", "Ofis", "Ev"]
    public static let minRadius: Double = 100
    public static let maxRadius: Double = 1000
    public static let defaultRadius: Double = 150
    /// A saved fix less accurate than this gets the "doğruluk düşük" hint.
    public static let lowAccuracyMeters: Double = 100
    /// Body of every location notification (05a #33; also in KULLANIM).
    public static let notificationBody = "“✓ Yaptım” demezsen, bir sonraki açılışta hatırlatmaya devam ederim."

    // MARK: - Places

    /// Finite, inside ±90 / ±180 and not exactly (0, 0) (the empty-slot marker).
    public static func isConfigured(_ place: Place) -> Bool {
        isUsableFix(latitude: place.latitude, longitude: place.longitude)
    }

    /// 100…1000 m; a non-finite value becomes the 150 m default.
    public static func clampedRadius(_ meters: Double) -> Double {
        guard meters.isFinite else { return defaultRadius }
        return min(maxRadius, max(minRadius, meters))
    }

    /// Configured place whose name or alias equals `name` (TurkishText.searchKey); nil when none.
    public static func configuredPlace(named name: String, in places: [Place]) -> Place? {
        let key = TurkishText.searchKey(name)
        guard !key.isEmpty else { return nil }
        for place in places where LocationPlanner.isConfigured(place) {
            for candidate in place.allNames where TurkishText.searchKey(candidate) == key {
                return place
            }
        }
        return nil
    }

    // MARK: - Requests

    /// Open, notifiable items with placeTrigger != nil, locationFiredAt == nil and a configured place (placeID match);
    /// sorted (priority desc, createdAt asc, id.uuidString asc); first 10.
    public static func candidates(items: [Item], places: [Place], projects: [Project]) -> [LocationRequestSpec] {
        var configured: [UUID: Place] = [:]
        for place in places where LocationPlanner.isConfigured(place) && configured[place.id] == nil {
            configured[place.id] = place
        }
        guard !configured.isEmpty else { return [] }

        var eligible: [EligibleItem] = []
        for item in items where item.isNotifiable && item.locationFiredAt == nil {
            guard let placeID = item.placeID, let trigger = item.placeTrigger,
                  let place = configured[placeID] else { continue }
            eligible.append(EligibleItem(item: item, place: place, trigger: trigger))
        }
        eligible.sort { (lhs: EligibleItem, rhs: EligibleItem) -> Bool in
            LocationPlanner.isOrderedBefore(lhs.item, rhs.item)
        }

        var names: [UUID: String] = [:]
        for project in projects where names[project.id] == nil {
            names[project.id] = project.name
        }

        var result: [LocationRequestSpec] = []
        var seen = Set<UUID>()
        for entry in eligible {
            if result.count >= maxRequests { break }
            if seen.contains(entry.item.id) { continue }
            seen.insert(entry.item.id)
            var projectName: String? = nil
            if let projectID = entry.item.projectID {
                projectName = names[projectID]
            }
            result.append(spec(item: entry.item, place: entry.place, trigger: entry.trigger,
                               projectName: projectName))
        }
        return result
    }

    /// title = item.title ("Hatırlatma" when empty); subtitle = place.name + " · " + trigger.label (+ " · " + project);
    /// body = "“✓ Yaptım” demezsen, bir sonraki açılışta hatırlatmaya devam ederim."
    public static func content(item: Item, place: Place, projectName: String?) -> NotificationText {
        let trigger: PlaceTrigger = item.placeTrigger ?? .onArrive
        let cleanTitle = item.title.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = cleanTitle.isEmpty ? "Hatırlatma" : cleanTitle
        var subtitle: String = placeLabel(name: place.name, trigger: trigger)
        if let project = projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
            subtitle += " · " + project
        }
        return NotificationText(title: title, subtitle: subtitle, body: notificationBody)
    }

    /// Number of open, notifiable items bound to `placeID` (Konumlar row "2 hatırlatma").
    public static func openItemCount(placeID: UUID, items: [Item]) -> Int {
        var count = 0
        for item in items where item.isNotifiable && item.placeID == placeID {
            count += 1
        }
        return count
    }

    // MARK: - Texts (Konumlar / Yer düzenle / capture card)

    /// "Fabrika · varınca" (trimmed name; "Yer" when empty).
    public static func placeLabel(name: String, trigger: PlaceTrigger) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown: String = trimmed.isEmpty ? "Yer" : trimmed
        return shown + " · " + trigger.label
    }

    /// "150 m", "1 km" (whole metres; non-finite → "150 m").
    public static func radiusLabel(_ meters: Double) -> String {
        let value = clampedRadius(meters)
        let whole = Int(value.rounded())
        if whole >= 1000 && whole % 1000 == 0 {
            return String(whole / 1000) + " km"
        }
        return String(whole) + " m"
    }

    /// Settings row subtitle: no configured place → "Fabrika, ofis, ev · henüz kayıtlı yer yok"; else "<n> yer kayıtlı".
    public static func settingsSubtitle(places: [Place]) -> String {
        var configured = 0
        for place in places where LocationPlanner.isConfigured(place) {
            configured += 1
        }
        if configured == 0 {
            return "Fabrika, ofis, ev · henüz kayıtlı yer yok"
        }
        return String(configured) + " yer kayıtlı"
    }

    /// "Diğer adlar" field: comma / semicolon / newline separated, trimmed, empties and duplicates (searchKey)
    /// removed, names equal to `excluding` (the place name) dropped; order kept; at most 10.
    public static func aliases(from text: String, excluding name: String = "") -> [String] {
        let separators: Set<Character> = [",", ";", "\n"]
        var result: [String] = []
        var seen = Set<String>()
        let nameKey = TurkishText.searchKey(name)
        if !nameKey.isEmpty {
            seen.insert(nameKey)
        }
        for raw in text.split(whereSeparator: { separators.contains($0) }) {
            let trimmed = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TurkishText.searchKey(trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count >= 10 { break }
        }
        return result
    }

    /// Inverse of `aliases(from:)` for the text field: "saha, tesis".
    public static func aliasText(_ aliases: [String]) -> String {
        aliases.joined(separator: ", ")
    }

    /// Fixed-point coordinate text without exponent ("40.78061", "-3.00000"); non-finite → "0".
    public static func coordinateText(_ value: Double, decimals: Int = 5) -> String {
        guard value.isFinite else { return "0" }
        let places = min(8, max(0, decimals))
        var scale: Double = 1
        var step = 0
        while step < places {
            scale *= 10
            step += 1
        }
        let scaled = (abs(value) * scale).rounded()
        guard scaled < 1e15 else { return String(value) }
        let total = Int64(scaled)
        let divisor = Int64(scale)
        let whole = total / divisor
        let fraction = total % divisor
        let sign: String = (value < 0 && total != 0) ? "-" : ""
        if places == 0 {
            return sign + String(whole)
        }
        var fractionText = String(fraction)
        while fractionText.count < places {
            fractionText = "0" + fractionText
        }
        return sign + String(whole) + "." + fractionText
    }

    /// Success toast after "Şu anki konumu kaydet": "Konum kaydedildi (±12 m)", plus
    /// " — doğruluk düşük, açık alanda tekrar dene" when the accuracy is worse than 100 m.
    public static func savedText(accuracy: Double) -> String {
        guard accuracy.isFinite && accuracy >= 0 else { return "Konum kaydedildi" }
        let meters = Int(min(100_000, accuracy).rounded())
        var text = "Konum kaydedildi (±" + String(meters) + " m)"
        if accuracy > lowAccuracyMeters {
            text += " — doğruluk düşük, açık alanda tekrar dene"
        }
        return text
    }

    /// A fix that can be stored as a place: finite, inside ±90 / ±180, not exactly (0, 0).
    public static func isUsableFix(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite && longitude.isFinite else { return false }
        guard abs(latitude) <= 90 && abs(longitude) <= 180 else { return false }
        return !(latitude == 0 && longitude == 0)
    }

    // MARK: - Private

    private struct EligibleItem {
        let item: Item
        let place: Place
        let trigger: PlaceTrigger
    }

    private static func isOrderedBefore(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func spec(item: Item, place: Place, trigger: PlaceTrigger, projectName: String?) -> LocationRequestSpec {
        let text = content(item: item, place: place, projectName: projectName)
        let category = item.kind == .waiting ? NotificationCategoryID.followUp : NotificationCategoryID.item
        return LocationRequestSpec(id: NotificationID.location(item.id),
                                   itemID: item.id,
                                   latitude: place.latitude,
                                   longitude: place.longitude,
                                   radiusMeters: clampedRadius(place.radiusMeters),
                                   notifyOnEntry: trigger == .onArrive,
                                   notifyOnExit: trigger == .onLeave,
                                   text: text,
                                   categoryID: category,
                                   threadID: NotificationID.thread(item.id))
    }
}
