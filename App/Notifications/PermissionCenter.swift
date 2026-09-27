// API: App/Notifications/PermissionCenter.swift — WP5 (04 §3.6.6, 03 §9, 05b A9/B7).
// Permission / notification-settings state and the single top banner shown on the Today screen.
import Foundation
import Observation
import UIKit
import UserNotifications
import AVFoundation
import Speech
import AsistCore

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
    private(set) var alertsPersistent = false        // UNNotificationSettings.alertStyle == .alert ("Kalıcı")
    private(set) var previewsAlways = true           // showPreviewsSetting == .always
    private(set) var timeSensitiveEnabled = false    // timeSensitiveSetting == .enabled
    private(set) var scheduledSummaryOn = false      // scheduledDeliverySetting == .enabled
    private(set) var microphoneGranted = false       // AVAudioApplication.shared.recordPermission == .granted
    private(set) var speechGranted = false           // SFSpeechRecognizer.authorizationStatus() == .authorized
    // Additions (not in the frozen API list; used for banners/diagnostics only):
    /// Authorized, but banners/alerts are switched off or the authorization is provisional (quiet delivery).
    private(set) var quietDelivery = false
    /// showPreviewsSetting == .never (title/subtitle are still shown thanks to the category options, D26).
    private(set) var previewsNever = false
    /// Explicitly denied (not merely "not asked yet") — only then is a mic/speech banner shown.
    private(set) var microphoneDenied = false
    private(set) var speechDenied = false

    // MARK: - Refresh / requests

    func refresh() async {
        let ns = await UNUserNotificationCenter.current().notificationSettings()
        let status = ns.authorizationStatus
        var newState: NotificationState = .unknown
        var provisional = false
        switch status {
        case .notDetermined:
            newState = .notDetermined
        case .denied:
            newState = .denied
        case .authorized, .ephemeral:
            newState = .authorized
        case .provisional:
            newState = .authorized
            provisional = true
        @unknown default:
            newState = .unknown
        }
        let persistent = ns.alertStyle == .alert
        let always = ns.showPreviewsSetting == .always
        let never = ns.showPreviewsSetting == .never
        let timeSensitive = ns.timeSensitiveSetting == .enabled
        let summary = ns.scheduledDeliverySetting == .enabled
        let alertsOff = ns.alertSetting == .disabled
        let quiet = newState == .authorized && (provisional || alertsOff)

        let micPermission = AVAudioApplication.shared.recordPermission
        let micGranted = micPermission == .granted
        let micDenied = micPermission == .denied
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechOK = speechStatus == .authorized
        let speechNo = speechStatus == .denied || speechStatus == .restricted

        // Assign only real changes (every set of an observed property invalidates the views reading it).
        if notification != newState { notification = newState }
        if alertsPersistent != persistent { alertsPersistent = persistent }
        if previewsAlways != always { previewsAlways = always }
        if previewsNever != never { previewsNever = never }
        if timeSensitiveEnabled != timeSensitive { timeSensitiveEnabled = timeSensitive }
        if scheduledSummaryOn != summary { scheduledSummaryOn = summary }
        if quietDelivery != quiet { quietDelivery = quiet }
        if microphoneGranted != micGranted { microphoneGranted = micGranted }
        if microphoneDenied != micDenied { microphoneDenied = micDenied }
        if speechGranted != speechOK { speechGranted = speechOK }
        if speechDenied != speechNo { speechDenied = speechNo }
    }

    /// [.alert, .sound, .badge, .providesAppNotificationSettings] (never .provisional / .criticalAlert, 01a §2.1).
    func requestNotifications() async -> Bool {
        var granted = false
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
        } catch {
            AsistLog.error("Bildirim izni istenemedi: \(error.localizedDescription)", .notif)
        }
        await refresh()
        AsistLog.info("Bildirim izni: \(granted ? "verildi" : "verilmedi")", .notif)
        if granted {
            // Plan right away (onboarding may stay on screen; nothing else would trigger a reconcile).
            AppEnvironment.shared.engine.requestReconcile(reason: "permission")
        }
        return granted
    }

    /// Speech first, then microphone: `VoicePermissions.requestAll()` (04 §3.6.6; WP6 owns the requests).
    func requestVoice() async -> Bool {
        let granted = await VoicePermissions.requestAll()
        await refresh()
        let speechText = speechGranted ? "evet" : "hayır"
        let micText = microphoneGranted ? "evet" : "hayır"
        AsistLog.info("Ses izinleri: konuşma " + speechText + ", mikrofon " + micText, .voice)
        return granted
    }

    // MARK: - Banner

    /// Highest-priority banner (03 §9): notif off (red) > data written by newer build (red, not dismissible, D35) >
    /// save failed (red) > data restored / partial recovery (yellow) > signing expired or ≤ 3 days (red/yellow) >
    /// mic/speech off (yellow) > notif previews hidden / scheduled summary on (yellow) > "Kalıcı" banner-style tip
    /// when !alertsPersistent (yellow, dismissible 720 h, action .openGuideBanners, 05b A9) > budget dropped (yellow).
    /// A dismissed banner is hidden while meta.dismissedBanners[id] > now.
    func topBanner(store: DataStore, signing: SigningMonitor, engine: ReminderEngine, now: Date) -> AppBanner? {
        let dismissed = store.meta.dismissedBanners
        for banner in candidates(store: store, signing: signing, engine: engine, now: now) {
            if banner.dismissible, let until = dismissed[banner.id], until > now {
                continue
            }
            return banner
        }
        return nil
    }

    /// All applicable banners in priority order (built lazily enough: at most ~10 cheap checks per minute).
    private func candidates(store: DataStore, signing: SigningMonitor, engine: ReminderEngine, now: Date) -> [AppBanner] {
        var result: [AppBanner] = []

        // 1. Notifications off (red, never dismissible).
        if notification == .denied {
            result.append(AppBanner(id: "notif_off",
                                    text: "Bildirimler kapalı — hatırlatmalar çalmayacak.",
                                    severity: .red, actionTitle: "Ayarları Aç",
                                    action: .openNotificationSettings, dismissible: false, hideHours: 24))
        } else if notification == .notDetermined && store.isLoaded && store.settings.onboardingCompleted {
            result.append(AppBanner(id: "notif_not_asked",
                                    text: "Bildirim izni henüz verilmedi — hatırlatmalar çalamaz.",
                                    severity: .red, actionTitle: "İzin ver",
                                    action: .openAppStatus, dismissible: false, hideHours: 24))
        }

        // 2. Data written by a newer build (D35).
        // 3. Save failed.
        // 4. Data restored / partial recovery.
        if let issue = store.loadIssue, case .newerWriter(let build) = issue {
            result.append(AppBanner(id: "data_newer_writer",
                                    text: "Kayıtlar Asist'in daha yeni bir sürümüyle (yapı \(build)) yazılmış. "
                                        + "Bir kopyası Yedekler klasöründe; güncel sürümü yükle.",
                                    severity: .red, actionTitle: "Ayrıntılar",
                                    action: .openAppStatus, dismissible: false, hideHours: 24))
        }
        if let error = store.lastSaveError {
            let text = error.isEmpty ? "Kaydedilemedi. Kayıtların bellekte duruyor; tekrar denenecek." : error
            result.append(AppBanner(id: "save_failed", text: text, severity: .red, actionTitle: "Tanılama",
                                    action: .openDiagnostics, dismissible: false, hideHours: 24))
        }
        if let issue = store.loadIssue, let restored = PermissionCenter.restoreBanner(issue) {
            result.append(restored)
        }

        // 5. Signing expired or ≤ 3 days (only from the real embedded profile; no estimates, 05a #28).
        if let expiry = signing.expiryDate, let signingBanner = PermissionCenter.signingBanner(expiry: expiry, now: now) {
            result.append(signingBanner)
        }

        // 6. Microphone / speech explicitly denied.
        if microphoneDenied {
            result.append(AppBanner(id: "mic_off",
                                    text: "Mikrofon izni kapalı — sesle kayıt yapılamıyor. Klavyeyi veya Siri'yi kullanabilirsin.",
                                    severity: .yellow, actionTitle: "Ayarları Aç",
                                    action: .openAppSettings, dismissible: false, hideHours: 24))
        } else if speechDenied {
            result.append(AppBanner(id: "speech_off",
                                    text: "Konuşma tanıma izni kapalı — sesle kayıt yapılamıyor. Klavyeyi kullanabilirsin.",
                                    severity: .yellow, actionTitle: "Ayarları Aç",
                                    action: .openAppSettings, dismissible: false, hideHours: 24))
        }

        // 6b. Location (07 §9.9): only when configured-place items still waiting for their geofence exist.
        let places = store.places
        let placeItemCount = store.items.filter { (item: Item) -> Bool in
            guard item.isNotifiable, item.placeTrigger != nil, item.locationFiredAt == nil,
                  let placeID = item.placeID else { return false }
            return places.contains { (place: Place) -> Bool in
                place.id == placeID && LocationPlanner.isConfigured(place)
            }
        }.count
        if placeItemCount > 0 {
            switch LocationService.shared.access {
            case .denied, .restricted, .notDetermined:
                result.append(AppBanner(id: "location_off",
                                        text: "Konum izni kapalı — yere bağlı \(placeItemCount) hatırlatma çalışmıyor.",
                                        severity: .yellow, actionTitle: "Ayarları Aç",
                                        action: .openAppSettings, dismissible: true, hideHours: 24))
            case .reducedAccuracy:
                result.append(AppBanner(id: "location_reduced",
                                        text: "Kesin Konum kapalı — yere bağlı hatırlatmalar çalışmıyor.",
                                        severity: .yellow, actionTitle: "Ayarları Aç",
                                        action: .openAppSettings, dismissible: true, hideHours: 24))
            case .usable:
                break
            }
        }

        // 7. Quiet delivery / scheduled summary / previews hidden.
        if notification == .authorized {
            if quietDelivery {
                result.append(AppBanner(id: "notif_quiet",
                                        text: "Bildirimler sessiz teslim ediliyor; hatırlatmaları kaçırabilirsin.",
                                        severity: .yellow, actionTitle: "Ayarları Aç",
                                        action: .openNotificationSettings, dismissible: false, hideHours: 24))
            }
            if scheduledSummaryOn {
                result.append(AppBanner(id: "notif_summary",
                                        text: "Asist bildirimleri özete alınıyor; anında teslim edilmesi için özetten çıkar.",
                                        severity: .yellow, actionTitle: "Ayarları Aç",
                                        action: .openNotificationSettings, dismissible: true, hideHours: 24))
            }
            // "Önizlemeleri Göster: Kilitli Değilken" is the iPhone default and harmless (the categories keep title
            // and subtitle visible, D26) → only "Hiçbir Zaman" is reported, once a month.
            if previewsNever && !previewsAlways {
                result.append(AppBanner(id: "preview_hidden",
                                        text: "Kilit ekranında bildirim içeriği gizli. İçeriği görmek için önizlemeyi aç.",
                                        severity: .yellow, actionTitle: "Ayarları Aç",
                                        action: .openNotificationSettings, dismissible: true, hideHours: 720))
            }

            // 8. "Kalıcı" banner-style tip (05b A9).
            if !alertsPersistent {
                result.append(AppBanner(id: "tip_persistent",
                                        text: "Hatırlatmalar ekranda kalsın: Ayarlar › Bildirimler › Asist › Banner Stili › Kalıcı",
                                        severity: .yellow, actionTitle: "Nasıl?",
                                        action: .openGuideBanners, dismissible: true, hideHours: 720))
            }
        }

        // 9. Budget: more candidates than the 64-request limit allows.
        if let report = engine.lastReport, report.authorized, report.dropped > 0 {
            result.append(AppBanner(id: "budget",
                                    text: "Çok sayıda hatırlatma var; en yakın \(report.itemBudget) tanesi planlandı. "
                                        + "Uygulamayı ara ara açman yeterli.",
                                    severity: .yellow, actionTitle: nil,
                                    action: .none, dismissible: true, hideHours: 24))
        }
        return result
    }

    private static func restoreBanner(_ issue: StoreLoadIssue) -> AppBanner? {
        switch issue {
        case .restoredFromPrevious:
            return AppBanner(id: "data_restored",
                             text: "Veri dosyası okunamadı; bir önceki kayıttan geri yüklendi.",
                             severity: .yellow, actionTitle: nil, action: .none, dismissible: true, hideHours: 24)
        case .restoredFromBackup(let dayKey):
            return AppBanner(id: "data_restored",
                             text: "Veri dosyası okunamadı; \(displayDay(dayKey)) tarihli yedekten geri yüklendi.",
                             severity: .yellow, actionTitle: nil, action: .none, dismissible: true, hideHours: 24)
        case .startedEmptyAfterCorruption:
            return AppBanner(id: "data_empty_after_corruption",
                             text: "Veri dosyası okunamadı ve yedek bulunamadı. Bozuk dosyanın kopyası saklandı; "
                                + "Ayarlar › Veri'den bir yedeği geri yükleyebilirsin.",
                             severity: .red, actionTitle: "Tanılama", action: .openDiagnostics,
                             dismissible: true, hideHours: 24)
        case .partialRecovery(let dropped):
            return AppBanner(id: "data_partial",
                             text: "Veri dosyasındaki \(dropped) kayıt okunamadı; dosyanın bir kopyası saklandı.",
                             severity: .yellow, actionTitle: "Tanılama", action: .openDiagnostics,
                             dismissible: true, hideHours: 24)
        case .newerWriter:
            return nil          // handled with higher priority above
        }
    }

    private static func signingBanner(expiry: Date, now: Date) -> AppBanner? {
        let remaining = expiry.timeIntervalSince(now)
        if remaining <= 0 {
            return AppBanner(id: "sign_expired",
                             text: "Asist'in imzası doldu. Sideloadly ile yenile, sonra Asist'i bir kez aç.",
                             severity: .red, actionTitle: "Ayrıntılar", action: .openAppStatus,
                             dismissible: false, hideHours: 24)
        }
        guard remaining <= 3 * 24 * 3600 else { return nil }
        let calendar = AppTime.calendar
        let startNow = calendar.startOfDay(for: now)
        let startExpiry = calendar.startOfDay(for: expiry)
        let dayDiff = calendar.dateComponents([.day], from: startNow, to: startExpiry).day ?? 0
        let clockParts = calendar.dateComponents([.hour, .minute], from: expiry)
        let clock = TurkishSpeech.displayClockLocative(hour: clockParts.hour ?? 0, minute: clockParts.minute ?? 0)
        let text: String
        if dayDiff <= 0 {
            text = "İmza bugün \(clock) bitiyor. Bilgisayarda Sideloadly ile yenile, sonra Asist'i bir kez aç."
        } else if dayDiff == 1 {
            text = "İmza yarın \(clock) bitiyor. Bilgisayarda Sideloadly ile yenile, sonra Asist'i bir kez aç."
        } else {
            text = "İmza \(dayDiff) gün sonra bitiyor. Yeniden yükleme zamanı yaklaşıyor."
        }
        let urgent = remaining <= 24 * 3600
        return AppBanner(id: "sign_days_\(max(0, dayDiff))",
                         text: text,
                         severity: urgent ? .red : .yellow,
                         actionTitle: "Ayrıntılar",
                         action: .openAppStatus,
                         dismissible: !urgent,
                         hideHours: 24)
    }

    /// "yyyyMMdd" → "27.09.2026" (unchanged when malformed).
    private static func displayDay(_ dayKey: String) -> String {
        let chars = Array(dayKey)
        guard chars.count == 8 else { return dayKey }
        let year = String(chars[0..<4])
        let month = String(chars[4..<6])
        let day = String(chars[6..<8])
        return day + "." + month + "." + year
    }

    // MARK: - Settings links

    static func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
