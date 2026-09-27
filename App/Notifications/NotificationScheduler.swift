// API: App/Notifications/NotificationScheduler.swift — WP5 (04 §3.6.5, 01a §5.4).
// The single writer of pending notification requests (04 §4.1 r7). Every removal is by our own identifiers
// (never removeAll…; 04 §9 r28).
import Foundation
import UserNotifications
import AsistCore

@MainActor
final class NotificationScheduler {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// 01a §5.4 diff-apply restricted to NotificationID.isPlannerManaged ids: remove managed pending ids not
    /// in `desired`; add desired ids whose pending fingerprint (userInfo "fp") differs or is missing.
    /// Duplicate ids in `desired` → first wins (no Dictionary(uniqueKeysWithValues:)).
    /// `.once` with fireDate <= now is skipped. Returns number of add() calls.
    @discardableResult func apply(_ desired: [PlannedNotification], now: Date, calendar: Calendar) async -> Int {
        var wanted: [String: PlannedNotification] = [:]
        var order: [String] = []
        var skippedUnmanaged = 0
        for p in desired {
            guard NotificationID.isPlannerManaged(p.id) else {
                skippedUnmanaged += 1
                continue
            }
            if wanted[p.id] == nil {
                wanted[p.id] = p
                order.append(p.id)
            }
        }
        if skippedUnmanaged > 0 {
            AsistLog.error("apply: yönetilmeyen \(skippedUnmanaged) kimlik atlandı", .notif)
        }

        let pending = await center.pendingNotificationRequests()
        var unchanged = Set<String>()
        var toRemove: [String] = []
        for request in pending {
            let id = request.identifier
            guard NotificationID.isPlannerManaged(id) else { continue }
            guard let want = wanted[id] else {
                toRemove.append(id)
                continue
            }
            let pendingFingerprint = request.content.userInfo[NotificationUserInfoKey.fingerprint] as? String
            if pendingFingerprint == want.fingerprint && NotificationScheduler.triggerMatches(request.trigger, planned: want) {
                unchanged.insert(id)
            }
        }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }

        var addCalls = 0
        var failures = 0
        for id in order {
            guard !unchanged.contains(id), let p = wanted[id] else { continue }
            if case .once = p.rule, p.fireDate <= now { continue }
            addCalls += 1
            // Same identifier replaces the pending request (01a §2.5).
            let request = NotificationRequestFactory.make(p, now: now, calendar: calendar)
            do {
                try await center.add(request)
            } catch {
                failures += 1
                AsistLog.error("Bildirim eklenemedi \(id): \(error.localizedDescription)", .notif)
            }
        }
        if !toRemove.isEmpty || addCalls > 0 {
            AsistLog.info("apply: kaldırılan \(toRemove.count), eklenen \(addCalls), hata \(failures), değişmeyen \(unchanged.count)", .notif)
        }
        return addCalls
    }

    /// 05b B1 immediate path: adds exactly these requests (same factory, no diff, no removal; `.once` in the past skipped).
    @discardableResult func add(_ notifications: [PlannedNotification], now: Date, calendar: Calendar) async -> Int {
        var addCalls = 0
        var seen = Set<String>()
        for p in notifications {
            if seen.contains(p.id) { continue }
            seen.insert(p.id)
            if case .once = p.rule, p.fireDate <= now { continue }
            addCalls += 1
            let request = NotificationRequestFactory.make(p, now: now, calendar: calendar)
            do {
                try await center.add(request)
            } catch {
                AsistLog.error("Anlık bildirim eklenemedi \(p.id): \(error.localizedDescription)", .notif)
            }
        }
        return addCalls
    }

    /// Keep only the newest delivered notification per open item thread; remove delivered of closed items.
    func cleanupDelivered(openItemIDs: Set<UUID>) async {
        let delivered = await center.deliveredNotifications()
        var newestID: [UUID: String] = [:]
        var newestDate: [UUID: Date] = [:]
        var toRemove: [String] = []
        for notification in delivered {
            let request = notification.request
            let id = request.identifier
            guard NotificationID.isPlannerManaged(id) else { continue }
            // Briefings, end-of-day, backup, signing and the horizon sentinel carry no item → left alone.
            guard let itemID = NotificationScheduler.itemID(of: request) else { continue }
            guard openItemIDs.contains(itemID) else {
                toRemove.append(id)
                continue
            }
            let date = notification.date
            if let currentID = newestID[itemID], let currentDate = newestDate[itemID] {
                if date > currentDate {
                    toRemove.append(currentID)
                    newestID[itemID] = id
                    newestDate[itemID] = date
                } else {
                    toRemove.append(id)
                }
            } else {
                newestID[itemID] = id
                newestDate[itemID] = date
            }
        }
        if !toRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: toRemove)
        }
    }

    /// Removes delivered + pending of one item (every id containing its UUID, incl. the budget sentinel when its
    /// userInfo iid is this item).
    func removeAll(for itemID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        var pendingIDs: [String] = []
        for request in pending where NotificationScheduler.belongs(request, to: itemID) {
            pendingIDs.append(request.identifier)
        }
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
        let delivered = await center.deliveredNotifications()
        var deliveredIDs: [String] = []
        for notification in delivered where NotificationScheduler.belongs(notification.request, to: itemID) {
            deliveredIDs.append(notification.request.identifier)
        }
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    /// Removes every pending id with prefix "asist." except unmanaged "asist.x." (used by rebuildAll).
    func removeAllManaged() async {
        let pending = await center.pendingNotificationRequests()
        var ids: [String] = []
        for request in pending where NotificationID.isPlannerManaged(request.identifier) {
            ids.append(request.identifier)
        }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        AsistLog.info("Tüm planlı bildirimler kaldırıldı (\(ids.count))", .notif)
    }

    /// Diagnostics: (identifier, next trigger date, title) sorted by date (undated last).
    func pendingSummary() async -> [(id: String, date: Date?, title: String)] {
        let pending = await center.pendingNotificationRequests()
        var rows: [(id: String, date: Date?, title: String)] = []
        for request in pending {
            let date = NotificationScheduler.nextDate(of: request.trigger)
            rows.append((id: request.identifier, date: date, title: request.content.title))
        }
        rows.sort { lhs, rhs in
            let far = Date.distantFuture
            let l = lhs.date ?? far
            let r = rhs.date ?? far
            if l != r { return l < r }
            return lhs.id < rhs.id
        }
        return rows
    }

    func pendingCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.count
    }

    /// Ad hoc one-shot (test, moved feedback) with an "asist.x." id; trigger ≥ 2 s.
    func addUnmanaged(id: String, text: NotificationText, after seconds: TimeInterval, categoryID: String,
                      interruption: PlannedNotification.Interruption, itemID: UUID?) async {
        guard id.hasPrefix(NotificationID.unmanagedPrefix) else {
            AsistLog.error("addUnmanaged: \(id) 'asist.x.' ile başlamıyor, eklenmedi", .notif)
            return
        }
        let request = NotificationRequestFactory.makeUnmanaged(id: id, text: text, after: seconds,
                                                              categoryID: categoryID, interruption: interruption,
                                                              itemID: itemID)
        do {
            try await center.add(request)
            AsistLog.info("Tek seferlik bildirim eklendi: \(id)", .notif)
        } catch {
            AsistLog.error("Tek seferlik bildirim eklenemedi \(id): \(error.localizedDescription)", .notif)
        }
    }

    // MARK: - Helpers (pure, non-isolated)

    /// Item of a request: userInfo "iid" first (budget sentinel), else parsed from the identifier.
    nonisolated private static func itemID(of request: UNNotificationRequest) -> UUID? {
        if let raw = request.content.userInfo[NotificationUserInfoKey.itemID] as? String,
           let id = UUID(uuidString: raw) {
            return id
        }
        return NotificationID.itemID(from: request.identifier)
    }

    nonisolated private static func belongs(_ request: UNNotificationRequest, to itemID: UUID) -> Bool {
        let id = request.identifier
        guard id.hasPrefix(NotificationID.prefix) else { return false }
        if id.contains(itemID.uuidString) { return true }
        if let raw = request.content.userInfo[NotificationUserInfoKey.itemID] as? String,
           let owner = UUID(uuidString: raw) {
            return owner == itemID
        }
        return false
    }

    nonisolated private static func nextDate(of trigger: UNNotificationTrigger?) -> Date? {
        if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }
        if let intervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
            return intervalTrigger.nextTriggerDate()
        }
        return nil
    }

    /// Guards against floating calendar triggers that no longer match the planned instant (time-zone change,
    /// manual clock change — 01a §2.5): a one-shot calendar trigger whose next date differs from the plan by a
    /// minute or more is re-added even when the fingerprint is unchanged. Time-interval and repeating triggers are
    /// compared by fingerprint only.
    nonisolated private static func triggerMatches(_ trigger: UNNotificationTrigger?, planned: PlannedNotification) -> Bool {
        guard case .once = planned.rule else { return true }
        guard let calendarTrigger = trigger as? UNCalendarNotificationTrigger else { return true }
        if calendarTrigger.repeats { return false }
        guard let next = calendarTrigger.nextTriggerDate() else { return false }
        return abs(next.timeIntervalSince(planned.fireDate)) < 60
    }
}
