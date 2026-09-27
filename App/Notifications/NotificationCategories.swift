// FILE: App/Notifications/NotificationCategories.swift
import Foundation
import UserNotifications
import AsistCore

enum NotificationCategories {
    /// Replaces the full set (call at launch and whenever lockScreenShowsContent changes, D26).
    static func register(showContentOnLockScreen: Bool) {
        var itemOptions: UNNotificationCategoryOptions = [.customDismissAction]
        var plainOptions: UNNotificationCategoryOptions = []
        if showContentOnLockScreen {
            itemOptions.insert(.hiddenPreviewsShowTitle)
            itemOptions.insert(.hiddenPreviewsShowSubtitle)
            plainOptions.insert(.hiddenPreviewsShowTitle)
        }
        let item = UNNotificationCategory(
            identifier: NotificationCategoryID.item,
            actions: [
                action(NotificationActionID.done, "✓ Yaptım", "checkmark.circle.fill"),
                action(NotificationActionID.snooze10, "10 dk", "clock"),
                action(NotificationActionID.snooze60, "1 saat", "clock.arrow.circlepath"),
                action(NotificationActionID.tomorrow, "Yarın sabah", "sunrise")
            ],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "%u Asist hatırlatması",
            options: itemOptions)
        let preAlert = UNNotificationCategory(
            identifier: NotificationCategoryID.preAlert,
            actions: [action(NotificationActionID.done, "✓ Yaptım", "checkmark.circle.fill")],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "%u Asist hatırlatması",
            options: itemOptions)
        let followUp = UNNotificationCategory(
            identifier: NotificationCategoryID.followUp,
            actions: [
                action(NotificationActionID.followUpReceived, "✓ Geldi", "checkmark.circle.fill"),
                action(NotificationActionID.followUpTomorrow, "Yarın tekrar sor", "arrow.uturn.forward"),
                action(NotificationActionID.followUpTwoDays, "2 gün sonra", "calendar"),
                action(NotificationActionID.followUpMessage, "Mesaj gönder…", "paperplane", foreground: true)
            ],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "%u Asist takibi",
            options: itemOptions)
        let briefing = UNNotificationCategory(
            identifier: NotificationCategoryID.briefing,
            actions: [action(NotificationActionID.briefingRead, "Sesli oku", "speaker.wave.2.fill", foreground: true)],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Asist özeti",
            options: plainOptions)
        let endOfDay = UNNotificationCategory(
            identifier: NotificationCategoryID.endOfDay,
            actions: [
                action(NotificationActionID.endOfDayMove, "Sonraki iş gününe taşı", "arrow.right.circle.fill"),
                action(NotificationActionID.endOfDayReview, "Gözden geçir", "list.bullet", foreground: true)
            ],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Asist gün sonu",
            options: plainOptions)
        let system = UNNotificationCategory(
            identifier: NotificationCategoryID.system,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Asist",
            options: plainOptions)
        UNUserNotificationCenter.current().setNotificationCategories([item, preAlert, followUp, briefing, endOfDay, system])
    }

    private static func action(_ id: String, _ title: String, _ symbol: String, foreground: Bool = false) -> UNNotificationAction {
        UNNotificationAction(identifier: id,
                             title: title,
                             options: foreground ? [.foreground] : [],
                             icon: UNNotificationActionIcon(systemImageName: symbol))
    }
}
