// API: App/Notifications/PermissionCenter.swift
// WP0 STUB (04 §3.6.6) — replaced by WP5. Never requests permissions; no banner is computed.
import Foundation
import Observation
import UIKit
import UserNotifications
import AVFoundation
import Speech

enum BannerSeverity: Equatable { case red, yellow }
enum BannerAction: Equatable {
    case openNotificationSettings, openAppSettings, openAppStatus, openDiagnostics, openGuideBanners, none
}

struct AppBanner: Identifiable, Equatable {
    let id: String              // stable key, also used for dismissal in meta.dismissedBanners (id → hidden until)
    let text: String            // 03 §7.12 banner.* texts (as amended in §5.5)
    let severity: BannerSeverity
    let actionTitle: String?    // "Ayarları Aç"
    let action: BannerAction
    let dismissible: Bool       // permission/data problems are not dismissible
    let hideHours: Int          // dismissal duration (24 default; "Kalıcı" tip 720)
}

@MainActor
@Observable
final class PermissionCenter {
    enum NotificationState: Equatable { case unknown, notDetermined, denied, authorized }
    private(set) var notification: NotificationState = .unknown
    private(set) var alertsPersistent = false
    private(set) var previewsAlways = true
    private(set) var timeSensitiveEnabled = false
    private(set) var scheduledSummaryOn = false
    private(set) var microphoneGranted = false
    private(set) var speechGranted = false

    func refresh() async {}

    func requestNotifications() async -> Bool {
        false
    }

    func requestVoice() async -> Bool {
        false
    }

    /// Highest-priority banner (WP0 STUB: none).
    func topBanner(store: DataStore, signing: SigningMonitor, engine: ReminderEngine, now: Date) -> AppBanner? {
        nil
    }

    static func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
