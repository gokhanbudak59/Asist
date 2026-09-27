// API: App/Notifications/ReminderEngine.swift
// WP0 STUB (04 §3.6.5) — replaced by WP5. Plans nothing; every entry point returns immediately.
import Foundation
import Observation
import UserNotifications
import AsistCore

@MainActor
@Observable
final class ReminderEngine {
    struct Report: Equatable {
        var at: Date
        var reason: String
        var authorized: Bool
        var timeSensitiveAllowed: Bool
        var planned: Int
        var dropped: Int
        var rateLimited: Int
        var itemBudget: Int
        var badge: Int
        var added: Int
    }

    private(set) var lastReport: Report? = nil
    @ObservationIgnored private var tail: Task<Void, Never>? = nil
    @ObservationIgnored private var debounce: Task<Void, Never>? = nil

    private let store: DataStore
    private let scheduler: NotificationScheduler
    private let signing: SigningMonitor

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, scheduler: NotificationScheduler, signing: SigningMonitor) {
        self.store = store
        self.scheduler = scheduler
        self.signing = signing
    }

    /// Serialized reconcile (WP0 STUB: no-op).
    func reconcile(reason: String) async {
        guard store.isLoaded else { return }
    }

    /// Fire-and-forget, debounced 300 ms (WP0 STUB: no-op).
    func requestReconcile(reason: String) {}

    /// scheduler.removeAllManaged() then reconcile (WP0 STUB: no-op).
    func rebuildAll(reason: String) async {}

    /// §6.3 action handling (WP0 STUB: no-op; the caller still calls completionHandler()).
    func handle(_ event: NotificationEvent) async {}

    /// PlanInput for `now` from the current store/signing state.
    func makeInput(now: Date, allowTimeSensitive: Bool) -> PlanInput {
        PlanInput(items: store.items, projects: store.projects, places: store.places, settings: store.settings,
                  now: now, calendar: AppTime.calendar, signingExpiry: signing.expiryDate,
                  allowTimeSensitive: allowTimeSensitive)
    }

    /// "Test bildirimi (10 sn)" (WP0 STUB: no-op).
    func sendTestNotification() async {}
}
