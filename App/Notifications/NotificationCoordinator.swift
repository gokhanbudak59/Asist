// FILE: App/Notifications/NotificationCoordinator.swift
import Foundation
import UserNotifications
import AsistCore

/// Value copy of a response (no UNNotificationResponse crosses into the main actor).
struct NotificationEvent {
    let actionID: String
    let itemID: UUID?
    let notificationID: String
    /// userInfo "nk" (PlannedNotification.Kind rawValue); "" when missing.
    let kind: String
    let deliveredAt: Date
}

/// NOT @MainActor: UserNotifications calls it on a private queue. Completion-handler variants only.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private override init() {
        super.init()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
        let identifier = notification.request.identifier
        let deliveredAt = notification.date
        Task { @MainActor in
            // 07 §9.6: a geofence notification shown in the foreground starts the item's nag chain.
            if identifier.hasPrefix(NotificationID.locationPrefix), let itemID = NotificationID.itemID(from: identifier) {
                AppEnvironment.shared.store.recordLocationFired(itemID, at: deliveredAt)
            }
            AppEnvironment.shared.engine.requestReconcile(reason: "willPresent")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        let rawID = info[NotificationUserInfoKey.itemID] as? String
        let parsedID = rawID.flatMap { UUID(uuidString: $0) }
        let kind = info[NotificationUserInfoKey.kind] as? String ?? ""
        let event = NotificationEvent(actionID: response.actionIdentifier,
                                      itemID: parsedID ?? NotificationID.itemID(from: request.identifier),
                                      notificationID: request.identifier,
                                      kind: kind,
                                      deliveredAt: response.notification.date)
        Task { @MainActor in
            AppEnvironment.shared.bootstrap()
            // handle() persists, replaces this item's pending requests and awaits a full reconcile (D34, §6.3).
            await AppEnvironment.shared.engine.handle(event)
            completionHandler()          // always, exactly once, after handle() returned
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in
            AppEnvironment.shared.router.openRoute(.appStatus, in: .settings)
        }
    }
}
