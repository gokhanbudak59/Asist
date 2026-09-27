// App/Notifications/NotificationRequestFactory.swift — WP5 (04 §3.6.5, 01a §2.5 adapted).
// PlannedNotification (AsistCore) → UNNotificationRequest. The only place that builds UserNotifications content.
import Foundation
import UserNotifications
import AsistCore

enum NotificationRequestFactory {
    /// Value of userInfo "nk" for ad hoc (`asist.x.*`) requests (04 §6.1).
    static let unmanagedKind = "test"

    /// 01a §2.5 with the §3.6.5 amendments (custom sounds, interruption level, relevance, badge, userInfo, triggers).
    static func make(_ p: PlannedNotification, now: Date, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let title = p.title
        let body = p.body
        // An empty title AND body is rejected by the system (notificationInvalidNoContent) — never let that happen.
        content.title = (title.isEmpty && body.isEmpty) ? "Asist" : title
        content.subtitle = p.subtitle
        content.body = body
        content.sound = sound(playsSound: p.playsSound, soundName: p.soundName)
        content.categoryIdentifier = p.categoryID
        content.threadIdentifier = p.threadID
        content.interruptionLevel = interruptionLevel(p.interruption)
        content.relevanceScore = min(1.0, max(0.0, p.relevance))
        if let badge = p.badge {
            content.badge = NSNumber(value: max(0, badge))
        }
        let itemText: String = p.itemID?.uuidString ?? ""
        let info: [AnyHashable: Any] = [
            NotificationUserInfoKey.itemID: itemText,
            NotificationUserInfoKey.attempt: p.attempt,
            NotificationUserInfoKey.fingerprint: p.fingerprint,
            NotificationUserInfoKey.kind: p.kind.rawValue
        ]
        content.userInfo = info
        let trigger = makeTrigger(for: p, now: now, calendar: calendar)
        return UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)
    }

    /// Ad hoc one-shot (test notification, "moved" feedback): time-interval trigger ≥ 2 s, never repeating.
    static func makeUnmanaged(id: String, text: NotificationText, after seconds: TimeInterval, categoryID: String,
                              interruption: PlannedNotification.Interruption, itemID: UUID?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = (text.title.isEmpty && text.body.isEmpty) ? "Asist" : text.title
        content.subtitle = text.subtitle
        content.body = text.body
        // Passive feedback (e.g. "3 iş taşındı") is silent; the test notification must be heard.
        content.sound = interruption == .passive ? nil : UNNotificationSound.default
        content.categoryIdentifier = categoryID
        if let itemID = itemID {
            content.threadIdentifier = NotificationID.thread(itemID)
        } else {
            content.threadIdentifier = NotificationID.systemThread
        }
        content.interruptionLevel = interruptionLevel(interruption)
        content.relevanceScore = 0.5
        let itemText: String = itemID?.uuidString ?? ""
        let info: [AnyHashable: Any] = [
            NotificationUserInfoKey.itemID: itemText,
            NotificationUserInfoKey.attempt: 0,
            NotificationUserInfoKey.fingerprint: "",
            NotificationUserInfoKey.kind: unmanagedKind
        ]
        content.userInfo = info
        let interval: TimeInterval = seconds.isFinite ? max(2, seconds) : 2
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// `.once` < 60 s away → time interval (≥ 2 s, never 0 — 0 raises an ObjC exception); otherwise a floating
    /// calendar trigger (no time zone component). Repeating rules never contain year/month/day (except `.monthly` day).
    static func makeTrigger(for p: PlannedNotification, now: Date, calendar: Calendar) -> UNNotificationTrigger {
        switch p.rule {
        case .once:
            let delta = p.fireDate.timeIntervalSince(now)
            if !delta.isFinite || delta < 60 {
                let interval: TimeInterval = delta.isFinite ? max(delta, 2) : 2
                return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            }
            let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            let comps = calendar.dateComponents(components, from: p.fireDate)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        case .daily(let hour, let minute):
            let comps = DateComponents(hour: clampHour(hour), minute: clampMinute(minute))
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        case .weekly(let weekday, let hour, let minute):
            // Memberwise order: hour, minute, …, weekday (04 §9 r25).
            let comps = DateComponents(hour: clampHour(hour), minute: clampMinute(minute), weekday: clampWeekday(weekday))
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        case .monthly(let day, let hour, let minute):
            let comps = DateComponents(day: clampMonthDay(day), hour: clampHour(hour), minute: clampMinute(minute))
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        }
    }

    static func interruptionLevel(_ interruption: PlannedNotification.Interruption) -> UNNotificationInterruptionLevel {
        switch interruption {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }

    /// D37: bundled WAV for high/critical; a missing file falls back to the default sound explicitly.
    static func sound(playsSound: Bool, soundName: String?) -> UNNotificationSound? {
        guard playsSound else { return nil }
        guard let name = soundName, !name.isEmpty else { return UNNotificationSound.default }
        guard Bundle.main.url(forResource: name, withExtension: nil) != nil else {
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
    }

    // MARK: - Clamps (planner output is trusted, but a bad component would make the trigger never fire)

    private static func clampHour(_ value: Int) -> Int { min(23, max(0, value)) }
    private static func clampMinute(_ value: Int) -> Int { min(59, max(0, value)) }
    private static func clampWeekday(_ value: Int) -> Int { min(7, max(1, value)) }
    private static func clampMonthDay(_ value: Int) -> Int { min(28, max(1, value)) }
}
