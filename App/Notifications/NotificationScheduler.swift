// API: App/Notifications/NotificationScheduler.swift
// WP0 STUB (04 §3.6.5) — replaced by WP5. Schedules nothing and never touches pending requests.
import Foundation
import UserNotifications
import AsistCore

@MainActor
final class NotificationScheduler {
    /// 01a §5.4 diff-apply restricted to NotificationID.isPlannerManaged ids. Returns number of add() calls.
    @discardableResult func apply(_ desired: [PlannedNotification], now: Date, calendar: Calendar) async -> Int {
        0
    }

    /// 05b B1 immediate path: adds exactly these requests (same factory, no diff, no removal).
    @discardableResult func add(_ notifications: [PlannedNotification], now: Date, calendar: Calendar) async -> Int {
        0
    }

    /// Keep only the newest delivered notification per open item thread; remove delivered of closed items.
    func cleanupDelivered(openItemIDs: Set<UUID>) async {}

    /// Removes delivered + pending of one item.
    func removeAll(for itemID: UUID) async {}

    /// Removes every pending id with prefix "asist." except unmanaged "asist.x." (used by rebuildAll).
    func removeAllManaged() async {}

    /// Diagnostics: (identifier, next trigger date, title) sorted by date.
    func pendingSummary() async -> [(id: String, date: Date?, title: String)] {
        []
    }

    func pendingCount() async -> Int {
        0
    }

    /// Ad hoc one-shot (test, moved feedback) with an "asist.x." id; trigger ≥ 2 s.
    func addUnmanaged(id: String, text: NotificationText, after seconds: TimeInterval, categoryID: String,
                      interruption: PlannedNotification.Interruption, itemID: UUID?) async {}
}
