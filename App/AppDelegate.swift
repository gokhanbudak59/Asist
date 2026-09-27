// FILE: App/AppDelegate.swift
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 1) Delegate first (weak property; the singleton keeps it alive). Covers background launches from actions.
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        // 2) BG handler must be registered before launch finishes, exactly once.
        BackgroundRefresh.register()
        // 3) Load data, register categories, first reconcile. Idempotent.
        AppEnvironment.shared.bootstrap()
        return true
    }
}
