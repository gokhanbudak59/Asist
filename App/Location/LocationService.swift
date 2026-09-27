// API: App/Location/LocationService.swift — revision 4, F6 (07 §9.5, §9.6; 04 Appendix B.3 with the 07 deltas).
// The only file that imports CoreLocation (07 §2.2 r59). Owns the `asist.loc.<UUID>` requests
// (UNLocationNotificationTrigger, when-in-use + full accuracy, ≤ 10, never repeating); NotificationScheduler never
// touches them (NotificationID.isPlannerManaged excludes the prefix). Runs its sync only from
// ReminderEngine.reconcileOnce (already serialized). Logs ids and counts only — never titles or coordinates.
import Foundation
import Observation
import CoreLocation
import UserNotifications
import AsistCore

enum LocationAccess: Equatable {
    case notDetermined, denied, restricted, reducedAccuracy, usable

    /// "Henüz sorulmadı", "Kapalı", "Kısıtlı", "Kesin Konum kapalı", "Açık"
    var userText: String {
        switch self {
        case .notDetermined: return "Henüz sorulmadı"
        case .denied: return "Kapalı"
        case .restricted: return "Kısıtlı"
        case .reducedAccuracy: return "Kesin Konum kapalı"
        case .usable: return "Açık"
        }
    }
}

struct LocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    /// metres (horizontalAccuracy)
    let accuracy: Double
}

@MainActor
@Observable
final class LocationService {
    static let shared = LocationService()

    /// userInfo "nk" of the geofence requests.
    static let notificationKind = "location"
    /// One-shot fix timeout ("Şu anki konumu kaydet").
    private static let fixTimeoutNanoseconds: UInt64 = 15_000_000_000

    private(set) var access: LocationAccess = .notDetermined
    /// Pending asist.loc.* requests after the last sync (≤ 10); PlanInput.locationSlotsUsed.
    private(set) var activeCount: Int = 0
    /// true while `currentFix()` waits (editor spinner "Konum alınıyor…").
    private(set) var isLocating: Bool = false

    @ObservationIgnored private var manager: CLLocationManager? = nil
    /// CLLocationManager keeps its delegate weakly → the service owns it.
    @ObservationIgnored private var delegate: LocationDelegate? = nil
    @ObservationIgnored private var fixContinuation: CheckedContinuation<LocationFix?, Never>? = nil
    @ObservationIgnored private var fixTimeout: Task<Void, Never>? = nil
    /// The first sync of every process is always full (stale requests of an earlier process are removed).
    @ObservationIgnored private var didFullSync: Bool = false

    /// Never touches AppEnvironment.shared or CoreLocation (07 R4-D10); the manager is created in `start()`.
    init() {}

    var isUsable: Bool { access == .usable }

    // MARK: - Authorization

    /// Creates CLLocationManager + LocationDelegate once (desiredAccuracy best) and reads the authorization.
    /// Never prompts. Idempotent; safe in headless launches.
    func start() {
        if manager == nil {
            let created = CLLocationManager()
            let handler = LocationDelegate()
            created.desiredAccuracy = kCLLocationAccuracyBest
            created.delegate = handler
            delegate = handler
            manager = created
        }
        _ = refreshAccess()
    }

    /// "Konum iznini ver": asks for when-in-use only while the answer is still open (iOS shows the prompt once).
    func requestWhenInUse() {
        start()
        guard let manager = manager else { return }
        if access == .notDetermined {
            AsistLog.info("Konum izni isteniyor (uygulamayı kullanırken)", .location)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Called by LocationDelegate after the main-actor hop: on a real change the plan is rebuilt (the geofences
    /// are added or removed by the next sync).
    func authorizationChanged() {
        if refreshAccess() {
            AppEnvironment.shared.engine.requestReconcile(reason: "location.auth")
        }
    }

    /// true when `access` changed.
    private func refreshAccess() -> Bool {
        guard let manager = manager else { return false }
        let status = manager.authorizationStatus
        let fullAccuracy = manager.accuracyAuthorization == .fullAccuracy
        let latest = LocationService.mapAccess(status: status, fullAccuracy: fullAccuracy)
        guard latest != access else { return false }
        let previous = access
        access = latest
        AsistLog.info("Konum izni: " + previous.userText + " → " + latest.userText, .location)
        return true
    }

    /// whenInUse/always + full accuracy → usable; reduced → reducedAccuracy; denied/restricted/notDetermined map
    /// directly; anything unknown → denied (an if-chain: no switch over the SDK enum and its deprecated cases).
    private static func mapAccess(status: CLAuthorizationStatus, fullAccuracy: Bool) -> LocationAccess {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            return fullAccuracy ? LocationAccess.usable : LocationAccess.reducedAccuracy
        }
        if status == .notDetermined {
            return .notDetermined
        }
        if status == .restricted {
            return .restricted
        }
        return .denied
    }

    // MARK: - One-shot fix

    /// One-shot fix (requestLocation + CheckedContinuation, single finish funnel, 15 s timeout); nil unless .usable,
    /// on failure, on timeout or while another fix is already being taken.
    func currentFix() async -> LocationFix? {
        start()
        guard isUsable, let manager = manager else { return nil }
        guard fixContinuation == nil else {
            AsistLog.info("Konum zaten alınıyor; ikinci istek yok sayıldı", .location)
            return nil
        }
        isLocating = true
        let fix = await withCheckedContinuation { (continuation: CheckedContinuation<LocationFix?, Never>) in
            self.fixContinuation = continuation
            self.startFixTimeout()
            manager.requestLocation()
        }
        isLocating = false
        if fix == nil {
            AsistLog.info("Konum alınamadı", .location)
        } else {
            AsistLog.info("Konum alındı", .location)
        }
        return fix
    }

    /// Called by LocationDelegate after the main-actor hop: resumes the pending continuation once, cancels the timeout.
    func received(_ fix: LocationFix?) {
        fixTimeout?.cancel()
        fixTimeout = nil
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        continuation.resume(returning: fix)
    }

    private func startFixTimeout() {
        fixTimeout?.cancel()
        let nanos = LocationService.fixTimeoutNanoseconds
        fixTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self = self else { return }
            AsistLog.info("Konum isteği zaman aşımına uğradı", .location)
            self.received(nil)
        }
    }

    // MARK: - Geofence requests

    /// 1) records delivered asist.loc.* notifications (store.recordLocationFired(id, at: notification.date)) and
    ///    removes delivered ones of closed/deleted items;
    /// 2) desired = isUsable ? LocationPlanner.candidates(items:places:projects:) : [];
    /// 3) removes pending asist.loc.* that are not desired; adds desired ones that are missing or whose userInfo "fp"
    ///    differs (same identifier replaces the pending request);
    /// 4) activeCount = pending-and-desired + successfully added; returns it. Logs counts (.location).
    /// Fast path (only after one full sync in this process): no item has a placeID and activeCount == 0 → 0 without
    /// touching UNUserNotificationCenter. Runs only from ReminderEngine.reconcileOnce — never concurrently.
    func sync(store: DataStore) async -> Int {
        start()
        guard store.isLoaded else { return activeCount }
        if didFullSync && activeCount == 0 && !store.items.contains(where: { $0.placeID != nil }) {
            return 0
        }
        let firstSync = !didFullSync
        let center = UNUserNotificationCenter.current()

        // 1: deliveries (a delivered location notification is no longer pending).
        let delivered = await center.deliveredNotifications()
        guard store.isLoaded else { return activeCount }
        var recorded = 0
        var staleDelivered: [String] = []
        for notification in delivered {
            let identifier = notification.request.identifier
            guard identifier.hasPrefix(NotificationID.locationPrefix),
                  let itemID = NotificationID.itemID(from: identifier) else { continue }
            guard let item = store.item(itemID), item.isNotifiable else {
                staleDelivered.append(identifier)
                continue
            }
            if item.placeID != nil && item.locationFiredAt == nil {
                store.recordLocationFired(itemID, at: notification.date)
                if store.item(itemID)?.locationFiredAt != nil {
                    recorded += 1
                    AsistLog.info("Konum bildirimi teslim edildi: öğe=" + itemID.uuidString, .location)
                }
            }
        }
        if !staleDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        }

        // 2: desired set (after the records above: fired items are no longer candidates).
        var wanted: [String: LocationRequestSpec] = [:]
        var order: [String] = []
        if isUsable {
            let desired = LocationPlanner.candidates(items: store.items, places: store.places,
                                                     projects: store.projects)
            for spec in desired where wanted[spec.id] == nil {
                wanted[spec.id] = spec
                order.append(spec.id)
            }
        }

        // 3: diff against the pending asist.loc.* requests.
        let pending = await center.pendingNotificationRequests()
        var pendingIDs = Set<String>()
        var unchanged = Set<String>()
        var toRemove: [String] = []
        for request in pending {
            let identifier = request.identifier
            guard identifier.hasPrefix(NotificationID.locationPrefix) else { continue }
            pendingIDs.insert(identifier)
            guard let spec = wanted[identifier] else {
                toRemove.append(identifier)
                continue
            }
            let fingerprint = request.content.userInfo[NotificationUserInfoKey.fingerprint] as? String
            if fingerprint == spec.fingerprint && request.trigger is UNLocationNotificationTrigger {
                unchanged.insert(identifier)
            }
        }

        var added = 0
        var skipped = 0
        var failed = 0
        var requests: [UNNotificationRequest] = []
        for identifier in order {
            guard !unchanged.contains(identifier), let spec = wanted[identifier] else { continue }
            if let request = LocationService.makeRequest(spec) {
                requests.append(request)
            } else {
                skipped += 1
                if pendingIDs.contains(identifier) {
                    toRemove.append(identifier)            // an outdated request must not stay behind
                }
            }
        }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }
        for request in requests {
            do {
                try await center.add(request)
                added += 1
            } catch {
                failed += 1
                AsistLog.error("Konum bildirimi eklenemedi " + request.identifier + ": " + error.localizedDescription,
                               .location)
            }
        }

        // 4: active slots (never more than the planner's cap).
        let count = min(LocationPlanner.maxRequests, unchanged.count + added)
        if activeCount != count {
            activeCount = count
        }
        didFullSync = true
        if firstSync || recorded > 0 || added > 0 || !toRemove.isEmpty || skipped > 0 || failed > 0 {
            var line = "Konum eşitleme: istenen " + String(order.count)
            line += ", değişmeyen " + String(unchanged.count)
            line += ", eklenen " + String(added)
            line += ", kaldırılan " + String(toRemove.count)
            line += ", atlanan " + String(skipped)
            line += ", hata " + String(failed)
            line += ", teslim " + String(recorded)
            line += ", etkin " + String(count)
            line += ", izin " + access.userText
            AsistLog.info(line, .location)
        }
        return count
    }

    /// Removes the delivered geofence notification of `itemID` (the item's place was changed or re-armed: an old
    /// delivery must not be recorded again by the next sync).
    func forgetDelivered(itemID: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationID.location(itemID)])
    }

    /// UNMutableNotificationContent + CLCircularRegion + UNLocationNotificationTrigger(repeats: false).
    /// nil when the coordinate is invalid (CLLocationCoordinate2DIsValid, 05a #20).
    private static func makeRequest(_ spec: LocationRequestSpec) -> UNNotificationRequest? {
        let coordinate = CLLocationCoordinate2D(latitude: spec.latitude, longitude: spec.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate),
              LocationPlanner.isUsableFix(latitude: spec.latitude, longitude: spec.longitude) else { return nil }
        let radius: CLLocationDistance = LocationPlanner.clampedRadius(spec.radiusMeters)
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: spec.id)
        region.notifyOnEntry = spec.notifyOnEntry
        region.notifyOnExit = spec.notifyOnExit

        let content = UNMutableNotificationContent()
        let title = spec.text.title
        content.title = title.isEmpty ? "Asist" : title
        content.subtitle = spec.text.subtitle
        content.body = spec.text.body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = spec.categoryID
        content.threadIdentifier = spec.threadID
        content.interruptionLevel = .active
        content.relevanceScore = 0.8
        let info: [AnyHashable: Any] = [
            NotificationUserInfoKey.itemID: spec.itemID.uuidString,
            NotificationUserInfoKey.attempt: 0,
            NotificationUserInfoKey.fingerprint: spec.fingerprint,
            NotificationUserInfoKey.kind: LocationService.notificationKind
        ]
        content.userInfo = info
        let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
        return UNNotificationRequest(identifier: spec.id, content: content, trigger: trigger)
    }
}

/// Non-isolated delegate (04 §4.1 r3–r4, 07 §2.2 r58): copies Doubles, hops with
/// Task { @MainActor in LocationService.shared.… }. requestLocation() requires didFailWithError.
final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            LocationService.shared.authorizationChanged()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.last(where: { (location: CLLocation) -> Bool in location.horizontalAccuracy >= 0 })
        guard let location = usable else {
            Task { @MainActor in
                LocationService.shared.received(nil)
            }
            return
        }
        let fix = LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                              accuracy: location.horizontalAccuracy)
        Task { @MainActor in
            LocationService.shared.received(fix)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        Task { @MainActor in
            AsistLog.error("Konum alınamadı (CoreLocation kodu " + String(code) + ")", .location)
            LocationService.shared.received(nil)
        }
    }
}
