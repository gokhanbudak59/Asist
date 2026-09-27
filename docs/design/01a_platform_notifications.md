# 01a — Platform: Notifications, Background Execution, "Nag Until Done", AlarmKit

Project: **Asist** (iOS, SwiftUI, deployment target iOS 17.0, device iPhone 14 Pro Max on iOS 26, Swift language mode 5, minimal strict concurrency).
Author context: research done 2026-09-27 against the live Apple Developer documentation (DocC JSON, i.e. the current SDK), Apple Developer Forums (DTS answers), WWDC25 session 230 and the GitHub runner-image manifests.
Audience: engineers who **cannot run a compiler locally** (Windows only; builds happen on GitHub Actions). Every signature below was copied from the current SDK docs; every behavioral claim carries a tag.

Tag legend:

- `[VERIFIED: url]` — confirmed in Apple docs or an Apple engineer (DTS) forum answer.
- `[VERIFIED-COMMUNITY: url]` — consistent community/forum reports, no Apple statement.
- `[UNVERIFIED: reason]` — plausible, not confirmed; must be tested on the device (see §9 checklist).

---

## 0. Decisions at a glance

| # | Decision | Why |
|---|----------|-----|
| D1 | All reminders are **local notifications** (`UNUserNotificationCenter`). No push. | Free Apple ID cannot use Push (see D6). Local notifications fire with the app closed/killed. |
| D2 | "Nag until done" = **pre-scheduled follow-up chain** per reminder (T, +5m, +15m, +30m, +1h, +2h, +4h, next day 09:00, 14:00, day+2 09:00) that is cancelled only by an explicit **Tamamlandı**. Once the chain is exhausted, one **daily repeating** request per open reminder. | The app may never run between alerts; the chain must already be in the system. |
| D3 | A single idempotent **reconcile** function (pure planner in `AsistCore` + thin iOS adapter) recomputes the whole pending set on: launch, foreground, every notification action, `willPresent`, every data change (incl. App Intents), BG refresh, time-zone/significant-time change. | One code path, testable on Linux CI, self-healing. |
| D4 | Budget: **60 of 64** pending slots for reminders, 4 reserved (morning briefing, sentinel, 2 spare). Priority tiers + soonest-first; a **sentinel** notification fires at the time of the first reminder that did not fit. | The system silently keeps only the soonest 64. |
| D5 | Notification delegate = dedicated **non-isolated `NSObject` singleton**, completion-handler variants, assigned in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` via `@UIApplicationDelegateAdaptor`. | Delegate property is `weak`; must be set before launch completes; avoids MainActor/Swift-6 crash patterns. |
| D6 | **No entitlements** for notifications: no `aps-environment`, **no time-sensitive entitlement** (not available to free Apple ID accounts), no critical alerts. Set `interruptionLevel = .timeSensitive` anyway (silently behaves as `.active` without the entitlement). | Free provisioning (Sideloadly). |
| D7 | Background refresh registered **manually** with `BGTaskScheduler.register` in the AppDelegate — **not** with SwiftUI `.backgroundTask(.appRefresh)`. Treated as a bonus, never relied upon. | Apple DTS recommendation after the iOS 18.4 SwiftUI registration crash; refresh frequency is not guaranteed. |
| D8 | **AlarmKit in v1: YES, but isolated and opt-in** — one file behind `#if ASIST_ALARMKIT && canImport(AlarmKit)` + `@available(iOS 26.0, *)`, alert-only (no countdown, no snooze, no intents), per-reminder toggle "Alarm olarak çal" (default off). | Only way for a free-signed app to break through Silent mode and Focus. Compile risk contained: flip one build flag off if CI fails. |
| D9 | Location reminders via `UNLocationNotificationTrigger` (when-in-use + precise location), max 10 active. | Fires with app closed; no "Always" permission needed. |
| D10 | Category options `.customDismissAction, .hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle`; `threadIdentifier` per reminder; title = the task, subtitle = time/attempt/overdue, body = full original utterance + next nag time. | The reminder must be understandable at a glance, even on a locked phone. |
| D11 | CI: pin **Xcode 26.x** (macos-26 runner default is Xcode 26.6). Do not build with Xcode 27 until AlarmKit overloads are re-checked (§6.6). | iOS 27 SDK adds AlarmKit overloads with defaulted params (possible ambiguity). |

---

## 1. Environment facts that shape the code

- GitHub runner `macos-26` image (2026-08-24): Xcode **26.6 (default)**, 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1. `macos-15` defaults to Xcode 16.4. → Use `macos-26` and select Xcode 26.6 explicitly. [VERIFIED: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md]
- The online docs already show the **iOS 27 SDK** (e.g. `BGTaskScheduler.submit(_:)` "deprecated 27.0", new `submitTaskRequest`, AlarmKit `appEntityIdentifier:` overloads "introduced 27.0"). None of the 27.0 APIs may be used. Deprecations with a version above the deployment target (17.0) do not produce warnings. [VERIFIED: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:)]
- Swift language mode 5 with minimal concurrency checking: Sendable mismatches are warnings, not errors; **dynamic actor-isolation runtime checks are only on in Swift 6 mode** (SE-0423), so the "`__dispatch_queue_assert` crash in notification delegates" reported for Swift 6 does not apply — but do not make the delegate `@MainActor` anyway. [VERIFIED-COMMUNITY: https://developer.apple.com/forums/thread/762217 , https://developer.apple.com/forums/thread/796407]
- **Do not set** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode 26 template default; XcodeGen does not set it). If it were set, every class — including the notification delegate and the BG task handler types — would become MainActor-isolated. Keep it unset (or explicitly `nonisolated`). [UNVERIFIED: XcodeGen default behavior; check generated project.pbxproj in CI log]
- Europe/Istanbul has no DST (permanent UTC+3), so DST gaps only matter when the user travels. Time-zone handling is still implemented (§2.6).

---

## 2. UNUserNotificationCenter (UserNotifications framework)

### 2.1 Authorization

Exact signatures (current SDK):

```swift
func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void)
func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool
func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void)
func notificationSettings() async -> UNNotificationSettings
```
[VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:) , https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)]

`UNAuthorizationOptions`: `.badge`, `.sound`, `.alert`, `.carPlay`, `.criticalAlert`, `.providesAppNotificationSettings`, `.provisional`; deprecated: `.announcement`, `.timeSensitive`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unauthorizationoptions]

Request exactly `[.alert, .sound, .badge, .providesAppNotificationSettings]`.
- Never `.provisional` (delivers quietly to Notification Center only — defeats the purpose).
- Never `.criticalAlert` (requires an Apple-granted entitlement).
- `.providesAppNotificationSettings` adds an "Asist Bildirim Ayarları" link in iOS Settings that calls `userNotificationCenter(_:openSettingsFor:)` (iOS 12+). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/providesappnotificationsettings]

The system prompts only once; later calls return the stored answer. Deep link to the app's notification settings: `UIApplication.openNotificationSettingsURLString` (iOS 16+). [VERIFIED: https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring]

```swift
import UIKit
import UserNotifications

enum NotificationPermission {
    /// Call from a foreground UI action (onboarding button), never at cold start without explanation.
    static func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
        } catch {
            return false
        }
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
```

When switching over `UNAuthorizationStatus` (`.notDetermined, .denied, .authorized, .provisional, .ephemeral`) always add `@unknown default:`.

### 2.2 Delegate: must be set before launch finishes, and it is `weak`

- Declaration: `weak var delegate: (any UNUserNotificationCenterDelegate)? { get set }` → assigning a freshly created object that nobody retains = **no callbacks at all**. Keep a `static let shared`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate]
- "You must assign your delegate object to the `UNUserNotificationCenter` object before your app finishes launching … in `application(_:willFinishLaunchingWithOptions:)` or `application(_:didFinishLaunchingWithOptions:)`." [VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate]
- `UNUserNotificationCenterDelegate` is **not** `@MainActor` (`protocol UNUserNotificationCenterDelegate : NSObjectProtocol`); callbacks arrive on a private background queue. [VERIFIED: same URL; queue name seen in crash logs `com.apple.usernotifications.UNUserNotificationServiceConnection.call-out`, https://developer.apple.com/forums/thread/796407]
- SwiftUI apps get an app delegate through `@UIApplicationDelegateAdaptor` (declare it exactly once, in the `App`). [VERIFIED: https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor]

Exact delegate requirement signatures (current SDK):

```swift
optional func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void)
optional func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
optional func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void)
optional func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async
optional func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?)
```
[VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:didreceive:withcompletionhandler:) , .../usernotificationcenter(_:willpresent:withcompletionhandler:)]

Rules:
1. Implement **either** the completion-handler **or** the async variant of a requirement, never both (same Objective-C selector → redeclaration/ambiguity compile error).
2. We use the completion-handler variants with the `@escaping @Sendable` spelling above (matches Xcode 16+/26 SDK; omitting `@Sendable` only gives a Swift-5-mode warning).
3. Keep the delegate type non-isolated (not the `AppDelegate`, which is implicitly `@MainActor` through `UIApplicationDelegate`).

App entry point:

```swift
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 1) Delegate first. The property is weak: NotificationCoordinator.shared keeps it alive.
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        // 2) Register categories on every launch (the call replaces the full set).
        NotificationCoordinator.shared.registerCategories()
        // 3) BGTask handlers must be registered before launch finishes, exactly once per identifier.
        BackgroundRefresh.register()
        return true
    }
}

@main
struct AsistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView()
            .onChange(of: scenePhase) { _, newPhase in      // iOS 17 two-parameter overload
                switch newPhase {
                case .active:
                    Task { await ReminderEngine.shared.reconcile(reason: "sceneActive") }
                case .background:
                    BackgroundRefresh.schedule()
                default:
                    break
                }
            }
    }
}
```

Note: the app can be launched **in the background** (notification action, BG refresh, App Intent, widget/control). The data store and `ReminderEngine` must therefore be usable without any view having been created (no `@Environment(\.modelContext)`-only persistence).

### 2.3 Categories and actions

Exact initializers:

```swift
// UNNotificationAction
convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [])
convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: UNNotificationActionIcon?)   // iOS 15+
// UNTextInputNotificationAction
convenience init(identifier: String, title: String, options: UNNotificationActionOptions, textInputButtonTitle: String, textInputPlaceholder: String)
convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: UNNotificationActionIcon?, textInputButtonTitle: String, textInputPlaceholder: String)   // iOS 15+
// UNNotificationActionIcon
convenience init(systemImageName: String)   // iOS 15+
// UNNotificationCategory
convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = [])
convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], hiddenPreviewsBodyPlaceholder: String, options: UNNotificationCategoryOptions = [])   // iOS 11+
// UNUserNotificationCenter
func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
```
[VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationaction , https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction , https://developer.apple.com/documentation/usernotifications/unnotificationcategory , https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setnotificationcategories(_:)]

`UNNotificationActionOptions`: `.authenticationRequired`, `.destructive`, `.foreground`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions]

| Option | Behavior |
|---|---|
| `[]` (none) | "When the user selects an action, the system **launches your app in the background** and calls the delegate's `userNotificationCenter(_:didReceive:withCompletionHandler:)`." The app is not shown. [VERIFIED: https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions] |
| `.foreground` | "The system brings the app to the foreground, asking the user to unlock the device as needed." Apple: "Do not use this option simply to bring your app to the foreground." [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/foreground] |
| `.authenticationRequired` | "The system prompts the user to unlock the device. After unlocking, the system notifies your app" (still background). Use only for data encrypted while locked. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired] |
| `.destructive` | Red styling only. [VERIFIED: .../destructive] |

Background launch when the app is **not running** (terminated by the system): works; Apple DTS confirmed apps are relaunched in the background to process a notification response. [VERIFIED: https://developer.apple.com/forums/thread/736576]

Background launch after the user **force-quits** (swipes the app away): Quinn (DTS): force-quit "sets a flag that prevents the app from being launched in the background. That flag gets cleared when the user next launches the app manually." Whether a *user-tapped* background action is exempt is **not documented**. [VERIFIED for the flag: https://developer.apple.com/forums/thread/685525] [UNVERIFIED: exemption for notification actions — community reports are mixed; test item T7 in §9].
→ Design consequence: every background action must be **fail-safe**: if the handler never runs, the already-scheduled follow-ups keep firing (the user gets an extra nag, never a lost reminder). Onboarding tells the user (Turkish): *"Asist'i uygulama değiştiricide yukarı kaydırıp kapatma. Hatırlatmalar yine gelir, ama bildirimdeki düğmeler çalışmayabilir."*

Data protection: actions can arrive while the device is locked. Default file protection for app files is "complete until first user authentication", so writes work after the first unlock since boot. **Do not** enable the Data Protection capability with `NSFileProtectionComplete` for the store. Apple: "users can respond to actions while the device is locked, making files encrypted with certain protection options unavailable." [VERIFIED: https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types]

Display limits: "When the system has unlimited space, the system displays up to 10 actions. When the system has limited space, the system displays at most two actions" (the first two in the array). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationcategory]

Text input: `UNTextInputNotificationAction` shows an editable field (typing or **dictation**); the text arrives as `UNTextInputNotificationResponse.userText`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/untextinputnotificationresponse] → Asist parses it with the AsistCore Turkish parser ("yarın 10'da", "2 saat sonra", "bitti", "iptal").

**`.customDismissAction` / `UNNotificationDismissActionIdentifier`:** "The system delivers this action only if your app configured the notification's category object with the `customDismissAction` option. To trigger this action, the user must **explicitly dismiss** the notification interface … **Ignoring a notification or flicking away a notification banner doesn't trigger this action.**" On iPhone that means "Clear/Temizle" in Notification Center or on the Lock Screen (swipe left → Clear, or clearing the group). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationdismissactionidentifier] Default tap (open app) is `UNNotificationDefaultActionIdentifier` and needs no configuration. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationdefaultactionidentifier]
→ Asist treats Clear as "seen, not done": log `lastDismissedAt`, keep the chain.

Registration code:

```swift
import Foundation
import UserNotifications

enum AsistNotif {
    enum Category {
        static let reminder = "ASIST_REMINDER"
        static let digest   = "ASIST_DIGEST"
    }
    enum Action {
        static let done     = "ASIST_DONE"
        static let snooze10 = "ASIST_SNOOZE_10"
        static let snooze60 = "ASIST_SNOOZE_60"
        static let tomorrow = "ASIST_TOMORROW"
        static let reply    = "ASIST_REPLY"
        static let open     = "ASIST_OPEN"
    }
    enum Key {                       // userInfo keys; values must be plist types (String/Int/...)
        static let reminderID = "rid"
        static let attempt    = "k"
        static let fingerprint = "h"
    }
    static let managedPrefix = "asist."
    /// Every request we own: "asist.r.<UUID>.<k>", "asist.r.<UUID>.d", "asist.l.<UUID>", "asist.b.morning", "asist.s".
    static func belongs(_ identifier: String, to reminderID: UUID) -> Bool {
        identifier.hasPrefix(managedPrefix) && identifier.contains(reminderID.uuidString)
    }
}

/// Not @MainActor on purpose: UserNotifications calls the delegate on a private background queue.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    private override init() { super.init() }

    func registerCategories() {
        let done = UNNotificationAction(identifier: AsistNotif.Action.done,
                                        title: "Tamamlandı",
                                        options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill"))
        let snooze10 = UNNotificationAction(identifier: AsistNotif.Action.snooze10,
                                            title: "10 dk sonra",
                                            options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "clock"))
        let snooze60 = UNNotificationAction(identifier: AsistNotif.Action.snooze60,
                                            title: "1 saat sonra",
                                            options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        let tomorrow = UNNotificationAction(identifier: AsistNotif.Action.tomorrow,
                                            title: "Yarın sabah",
                                            options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        let reply = UNTextInputNotificationAction(identifier: AsistNotif.Action.reply,
                                                  title: "Başka zaman / not…",
                                                  options: [],
                                                  icon: UNNotificationActionIcon(systemImageName: "text.bubble"),
                                                  textInputButtonTitle: "Kaydet",
                                                  textInputPlaceholder: "örn. yarın 10'da · 2 saat sonra · bitti")
        let open = UNNotificationAction(identifier: AsistNotif.Action.open,
                                        title: "Asist'i aç",
                                        options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))

        let reminder = UNNotificationCategory(identifier: AsistNotif.Category.reminder,
                                              actions: [done, snooze10, snooze60, tomorrow, reply],
                                              intentIdentifiers: [],
                                              hiddenPreviewsBodyPlaceholder: "%u Asist hatırlatması",
                                              options: [.customDismissAction, .hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle])
        let digest = UNNotificationCategory(identifier: AsistNotif.Category.digest,
                                            actions: [open],
                                            intentIdentifiers: [],
                                            hiddenPreviewsBodyPlaceholder: "Asist özeti",
                                            options: [.hiddenPreviewsShowTitle])
        UNUserNotificationCenter.current().setNotificationCategories([reminder, digest])
    }

    // MARK: Foreground delivery
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
        Task { await ReminderEngine.shared.reconcile(reason: "willPresent") }
    }

    // MARK: Any interaction: button, body tap, explicit Clear, text reply
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let content = response.notification.request.content
        let reminderID = (content.userInfo[AsistNotif.Key.reminderID] as? String).flatMap { UUID(uuidString: $0) }
        // Copy only Sendable values out of the non-Sendable response before hopping.
        let event = NotificationEvent(actionID: response.actionIdentifier,
                                      reminderID: reminderID,
                                      typedText: (response as? UNTextInputNotificationResponse)?.userText,
                                      notificationID: response.notification.request.identifier,
                                      deliveredAt: response.notification.date)
        Task {
            await ReminderEngine.shared.handle(event)
            completionHandler()            // always call it, after the work is persisted
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in AppRouter.shared.showNotificationSettings = true }
    }
}

struct NotificationEvent: Sendable {
    let actionID: String
    let reminderID: UUID?
    let typedText: String?
    let notificationID: String
    let deliveredAt: Date
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var focusedReminderID: UUID?
    @Published var showNotificationSettings = false
}
```

Action dispatch inside the engine (actor, see §5.6):

```swift
extension ReminderEngine {
    func handle(_ e: NotificationEvent) async {
        let now = Date()
        switch e.actionID {
        case AsistNotif.Action.done:
            if let id = e.reminderID { await markDone(id) }
        case AsistNotif.Action.snooze10:
            if let id = e.reminderID { snooze(id, until: now.addingTimeInterval(10 * 60)) }
        case AsistNotif.Action.snooze60:
            if let id = e.reminderID { snooze(id, until: now.addingTimeInterval(60 * 60)) }
        case AsistNotif.Action.tomorrow:
            if let id = e.reminderID { snooze(id, until: nextActiveMorning(after: now)) }
        case AsistNotif.Action.reply:
            if let id = e.reminderID, let text = e.typedText { applyTypedReply(id, text: text, now: now) }   // AsistCore parser
        case UNNotificationDismissActionIdentifier:
            if let id = e.reminderID { noteDismissed(id, at: now) }                                          // chain continues
        case UNNotificationDefaultActionIdentifier:
            let id = e.reminderID
            await MainActor.run { AppRouter.shared.focusedReminderID = id }
        default:
            break
        }
        await reconcile(reason: "action:\(e.actionID)")
    }

    func markDone(_ id: UUID) async {
        store.setDone(id, at: Date())                               // persistence layer (doc 02)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { AsistNotif.belongs($0, to: id) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications()
            .map { $0.request.identifier }.filter { AsistNotif.belongs($0, to: id) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        #if ASIST_ALARMKIT && canImport(AlarmKit)
        if #available(iOS 26.0, *) { AlarmKitBridge.cancel(reminderID: id) }
        #endif
    }
}
```
(`store`, `snooze`, `nextActiveMorning`, `applyTypedReply`, `noteDismissed` are engine/persistence members defined in the data-model docs; signatures here are indicative.)

### 2.4 Foreground presentation (`willPresent`)

"If your delegate does not implement this method, the system behaves as if you had passed `UNNotificationPresentationOptionNone`" — i.e. **reminders are silently swallowed while the app is open** unless we implement it. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)]
Options: `.badge`, `.banner` (iOS 14+), `.list` (iOS 14+), `.sound`; `.alert` is deprecated → use `[.banner, .list, .sound, .badge]`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationpresentationoptions]

### 2.5 Scheduling, identity, the 64 limit

```swift
convenience init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?)   // UNNotificationRequest
func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)? = nil)
func add(_ request: UNNotificationRequest) async throws
```
[VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:) , https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)]

Identifier semantics (load-bearing for the nag design): [VERIFIED: same init URL]
- unique identifier → new notification;
- identifier equals a **pending** request → the new request **replaces** it;
- identifier equals a **delivered** notification → "the system alerts the user again, replaces the old notification with the new one, and places the new notification at the top of the list."

`trigger: nil` → delivered right away. The center "processes requests serially in the order that the system initiates them" and may be used from any thread → `remove…` followed by `add` is ordered. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter]

**64 limit:** "the system keeps the soonest-firing 64 notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest." [VERIFIED: https://developer.apple.com/documentation/uikit/uilocalnotification (legacy doc)] Apple DTS 2025: "there is a limit of 64 for how many simultaneous notification requests can be active/pending at one time per app. This is a system limit and there is no way around it." [VERIFIED: https://developer.apple.com/forums/thread/811171] A repeating trigger is **one** request but delivers many times. [VERIFIED: https://developer.apple.com/forums/thread/765490]
- Beyond 64: **no error** is thrown by `add` (UNError has no "limit" code: `notificationsNotAllowed, attachment…, notificationInvalidNoDate, notificationInvalidNoContent, contentProviding…, badgeInputInvalid`); the latest-firing requests are silently dropped. [VERIFIED for error codes: https://developer.apple.com/documentation/usernotifications/unerror/code] [UNVERIFIED: exact eviction timing — we never exceed 60 so it does not matter]
- Delivered notifications (in Notification Center) do not count toward the 64. [VERIFIED: https://developer.apple.com/forums/thread/765490]
- Location-trigger requests are ordinary pending requests → assume they count. [UNVERIFIED: not documented; conservative assumption]

**Triggers**

```swift
convenience init(dateMatching dateComponents: DateComponents, repeats: Bool)          // UNCalendarNotificationTrigger
func nextTriggerDate() -> Date?
convenience init(timeInterval: TimeInterval, repeats: Bool)                            // UNTimeIntervalNotificationTrigger
convenience init(region: CLRegion, repeats: Bool)                                      // UNLocationNotificationTrigger
```
[VERIFIED: https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger/init(datematching:repeats:) , https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger/init(timeinterval:repeats:) , https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger/init(region:repeats:)]

| Trigger | Use in Asist | Rules / pitfalls |
|---|---|---|
| `UNCalendarNotificationTrigger` one-shot with `[.year,.month,.day,.hour,.minute,.second]` | Every reminder/follow-up ≥ 60 s in the future | Components from `Calendar.current`; do **not** set `.timeZone` → "floating" local time. |
| `UNCalendarNotificationTrigger` repeating `DateComponents(hour:minute:)` | Long-tail daily nag, morning briefing | Never include `year/month/day` in a repeating trigger. Repeating requests stay until removed. |
| `UNTimeIntervalNotificationTrigger` one-shot | Fire dates < 60 s away ("test in 10 s", near-due snoozes) | `timeInterval` "must be greater than zero"; `0` raises an Objective-C exception (crash). |
| `UNTimeIntervalNotificationTrigger` repeating | Not used | "If this parameter is true, the value in the timeInterval parameter must be 60 seconds or greater." Violations crash with `NSInternalInconsistencyException` ("time interval must be at least 60 if repeating"). [VERIFIED doc; crash VERIFIED-COMMUNITY: http://www.openradar.appspot.com/26935607] Starts counting from the moment it is added, so it cannot start "at T". |
| `UNLocationNotificationTrigger` | Arrival/leave reminders (§3) | `nextTriggerDate` not available. |

Time zones / DST: Apple engineer: "If you do not specify the timeZone component of DateComponents, it will fire when the specified DateComponents match the actual time. If you specify the time zone, then … the trigger will be fixed to the time zone." A developer in the same thread reports the opposite in practice for hour/minute-only triggers. [VERIFIED (Apple statement) + conflicting report: https://developer.apple.com/forums/thread/811265] → Do not rely on either: reconcile on `UIApplication.significantTimeChangeNotification` (posted on midnight, carrier time update, DST change) and `NSNotification.Name.NSSystemTimeZoneDidChange`, and compare each pending `nextTriggerDate()` with the planned date (fingerprint mismatch → re-add). [VERIFIED: https://developer.apple.com/documentation/uikit/uiapplication/significanttimechangenotification]
Past dates: never schedule a one-shot calendar trigger in the past (it would never match and may linger as a pending request). [UNVERIFIED: lingering behavior] The factory converts `fireDate ≤ now+60s` to a time-interval trigger ≥ 2 s.

Request factory (iOS adapter; the `PlannedNotification` type comes from AsistCore, §5.3):

```swift
import Foundation
import UserNotifications
import AsistCore

enum NotificationRequestFactory {
    static func make(_ p: PlannedNotification, now: Date = Date()) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.subtitle = p.subtitle
        content.body = p.body
        content.sound = .default
        content.categoryIdentifier = p.categoryID
        content.threadIdentifier = p.threadID
        content.interruptionLevel = p.interruption.unLevel
        content.relevanceScore = p.relevance
        if let badge = p.badge { content.badge = NSNumber(value: badge) }
        content.userInfo = [AsistNotif.Key.reminderID: p.reminderID?.uuidString ?? "",
                            AsistNotif.Key.attempt: p.attempt,
                            AsistNotif.Key.fingerprint: p.fingerprint]
        return UNNotificationRequest(identifier: p.id, content: content, trigger: trigger(for: p, now: now))
    }

    static func trigger(for p: PlannedNotification, now: Date) -> UNNotificationTrigger {
        switch p.rule {
        case .once:
            let delta = p.fireDate.timeIntervalSince(now)
            if delta < 60 {
                return UNTimeIntervalNotificationTrigger(timeInterval: max(delta, 2), repeats: false)
            }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.fireDate)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        case .daily(let hour, let minute):
            return UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        case .weekly(let weekday, let hour, let minute):
            return UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday), repeats: true)
        }
    }
}

extension PlannedNotification.Interruption {
    var unLevel: UNNotificationInterruptionLevel {
        switch self {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }
}
```
Notes: `DateComponents(hour:minute:weekday:)` uses the memberwise initializer's parameter order (`calendar, timeZone, era, year, month, day, hour, minute, second, nanosecond, weekday, …`) — labels must appear in that order or it will not compile. `content.sound = .default` is valid (`class var default` is back-ticked in the declaration).

### 2.6 Content fields

| Property | Signature / availability | Asist usage |
|---|---|---|
| `title`, `subtitle`, `body` | `var title: String` etc. | See §7. |
| `threadIdentifier` | `var threadIdentifier: String` — "assign the same thread identifier string to all notifications that you want to group together visually." [VERIFIED: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/threadidentifier] | `"asist.r.<UUID>"` → all nags of one reminder stack together. |
| `categoryIdentifier` | `var categoryIdentifier: String` | `ASIST_REMINDER` / `ASIST_DIGEST`. |
| `summaryArgument`, `summaryArgumentCount` | deprecated iOS 15, message "summaryArgument is ignored" [VERIFIED: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/summaryargument] | Do not use. |
| `relevanceScore` | `var relevanceScore: Double` (iOS 15+), 0…1, "The highest score gets featured in the notification summary." [VERIFIED: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/relevancescore] | 1.0 overdue nags, 0.8 first alert, 0.3 briefing. |
| `interruptionLevel` | `var interruptionLevel: UNNotificationInterruptionLevel` (iOS 15+): `.passive`, `.active` (default), `.timeSensitive`, `.critical` [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel] | `.timeSensitive` for reminders, `.passive` for the briefing. Never `.critical`. |
| `badge` | `@NSCopying var badge: NSNumber?` — 0 removes, nil leaves unchanged [VERIFIED: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/badge] | Projected overdue count at fire time (§7.1). |
| `sound` | `var sound: UNNotificationSound?` | `.default`; optional custom nag sound. |
| `userInfo` | `var userInfo: [AnyHashable : Any]` | Only String/Int values (plist types). Putting a `UUID` object there is a runtime failure. [UNVERIFIED: exact failure mode; avoid] |
| `targetContentIdentifier` | iOS 13+ | Not needed (single scene). |
| `filterCriteria` | iOS 16+, Focus filters | Not in v1. |

**Time-sensitive without the entitlement:**
- The "Time Sensitive Notifications" capability is **not available** to free "Apple Developer" (Apple ID) accounts (available to ADP and ADEP only). [VERIFIED by parsing the capability table: https://developer.apple.com/help/account/reference/supported-capabilities-ios] (Same table: App Groups ✓ free, Background Modes ✓ free, Push ✗ free, iCloud ✗ free, Siri ✗ free.)
- Without `com.apple.developer.usernotifications.time-sensitive`, setting `.timeSensitive` does **not crash** and `add` does **not fail**; the notification is delivered like `.active` (does not break through Focus/Scheduled Summary; the per-app "Time Sensitive" switch does not appear in Settings). [VERIFIED-COMMUNITY: https://developer.apple.com/forums/thread/683630 , https://github.com/uzairansaruzi/hermex/issues/771] [UNVERIFIED: Apple has no doc page stating this]
- `.timeSensitive` definition: "presents the notification immediately, lights up the screen, can play a sound, and breaks through system notification controls" (Focus, Notification Summary). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive]
- Therefore: keep `.timeSensitive` in code (free upgrade if the app is ever signed with a paid team), but **do not** add the entitlement to the entitlements file (free-signing profile creation would fail / Sideloadly would have to strip it). Replace the missing capability with user settings (§7.3) and AlarmKit (§6).
- `UNNotificationSettings.timeSensitiveSetting` (iOS 15+) can be shown on the diagnostics screen. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationsettings/timesensitivesetting] [UNVERIFIED: returns `.notSupported` without entitlement]

**Sounds** (`UNNotificationSound`): `class var default`, `convenience init(named: UNNotificationSoundName)`, `class var defaultRingtone` (iOS 15.2+), `ringtoneSoundNamed(_:)` (15.2+), `defaultCritical`/`criticalSoundNamed` (critical-alert entitlement only). Custom files: Linear PCM / IMA4 / µLaw / aLaw in `.aiff`, `.wav` or `.caf`, **< 30 s** (else the default sound plays), looked up in the main bundle or `Library/Sounds`. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationsound]
- v1: `.default`. Optional v1.1: a 6–8 s attention sound `asist_israr.wav` (16-bit PCM, generated with Python's `wave` module on Windows, committed to Resources) used only for attempts ≥ 2: `UNNotificationSound(named: UNNotificationSoundName(rawValue: "asist_israr.wav"))`. CI must verify the file is inside the .ipa. [UNVERIFIED: behavior when the named file is missing — assume silence/default; test]
- Silent switch on: notification sounds do not play (vibration only). Only AlarmKit overrides this (§6).

### 2.7 Managing pending / delivered — exact API table

| Purpose | Completion-handler form | Async form |
|---|---|---|
| Pending list | `getPendingNotificationRequests(completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void)` | `pendingNotificationRequests() async -> [UNNotificationRequest]` |
| Delivered list | `getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void)` | `deliveredNotifications() async -> [UNNotification]` |
| Remove pending | `removePendingNotificationRequests(withIdentifiers identifiers: [String])` (asynchronous, no async variant) | — |
| Remove delivered | `removeDeliveredNotifications(withIdentifiers identifiers: [String])` | — |
| Remove all | `removeAllPendingNotificationRequests()`, `removeAllDeliveredNotifications()` | — (never call: would also kill location/briefing requests; always remove by our IDs) |
| Settings | `getNotificationSettings(completionHandler:)` | `notificationSettings() async -> UNNotificationSettings` |
| Badge | `setBadgeCount(_ newBadgeCount: Int, withCompletionHandler: (@Sendable ((any Error)?) -> Void)? = nil)` iOS 16+ | `setBadgeCount(_ newBadgeCount: Int) async throws` |

[VERIFIED: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:) , .../getdeliverednotifications(completionhandler:) , .../removependingnotificationrequests(withidentifiers:) , .../removedeliverednotifications(withidentifiers:) , .../setbadgecount(_:withcompletionhandler:)]

Other facts: `removePendingNotificationRequests` ignores identifiers of non-repeating requests that already fired. `UNNotification.date` is the delivery date (used to learn that a location reminder fired). `UIApplication.applicationIconBadgeNumber` is **deprecated since iOS 17.0** ("Use -[UNUserNotificationCenter setBadgeCount:withCompletionHandler:] instead") → with target 17.0 it produces a warning; use `setBadgeCount`. [VERIFIED: https://developer.apple.com/documentation/uikit/uiapplication/applicationiconbadgenumber]

### 2.8 Compile-error / crash pitfall list (UserNotifications)

1. Using `.alert` presentation option → deprecation warning; use `.banner` + `.list`.
2. Implementing both async and completion-handler delegate variants → compile error.
3. Delegate object not retained → silently no callbacks (property is `weak`).
4. Delegate assigned in a `View.onAppear` / `task` → background-launched actions are lost. Assign in `didFinishLaunching`.
5. Forgetting to call `completionHandler()` on any path of `didReceive` (e.g. early `return` when `rid` is missing) → system may kill the app; always call it.
6. `UNTimeIntervalNotificationTrigger(timeInterval: 0, …)` or `< 60` with `repeats: true` → `NSInternalInconsistencyException` crash.
7. `Dictionary(uniqueKeysWithValues:)` with duplicate notification IDs → runtime trap. Use `Dictionary(_:uniquingKeysWith:)`.
8. Using `hashValue` / `Hasher` for the stored fingerprint → values change every launch (random seeding) → endless re-adds. Use the FNV-1a function in §5.3.
9. `UNNotificationAction(identifier:title:options:icon:)` — `icon` has no default; pass `nil` or an icon. Parameter order is fixed (`identifier, title, options, icon`).
10. `UNNotificationCategory(... hiddenPreviewsBodyPlaceholder: ...)` expects a non-optional `String` in the 5-argument init.
11. Swift pattern `case UNNotificationDismissActionIdentifier:` works in a `switch` over `String` (expression pattern); Apple's own sample uses it.
12. `DateComponents(hour:minute:weekday:)` — argument order must follow the memberwise init order (`hour, minute, …, weekday`).
13. `interruptionLevel`, `relevanceScore`, `UNNotificationActionIcon` are iOS 15+ — fine with target 17, but do not lower the target below 15 without `#available`.

---

## 3. Location reminders — `UNLocationNotificationTrigger`

- Signature: `convenience init(region: CLRegion, repeats: Bool)`; region type `CLCircularRegion(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String)`, `notifyOnEntry` / `notifyOnExit` (both default `true`). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger , https://developer.apple.com/documentation/corelocation/clcircularregion/init(center:radius:identifier:) , https://developer.apple.com/documentation/corelocation/clregion/notifyonentry]
- Authorization: "your app must have authorization to use Core Location and must have **when-in-use** permissions. (Because the system actually monitors the regions, you don't need to request always permissions for your app)." [VERIFIED: https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger]
- "Allow Once" (temporary when-in-use) "expires when the app is no longer in use" → location reminders silently stop. The UI must ask the user to choose "Uygulamayı Kullanırken İzin Ver". [VERIFIED: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()]
- Approximate location (reduced accuracy): small geofences do not work reliably / region monitoring unavailable → require `accuracyAuthorization == .fullAccuracy`. [VERIFIED-COMMUNITY: https://radar.com/blog/understanding-approximate-location-in-ios-14]
- Info.plist: `NSLocationWhenInUseUsageDescription` (required, or the request call does nothing/crashes). [VERIFIED: requestWhenInUseAuthorization doc above]
- Limits: "The system limits the number of location-based triggers that it schedules at the same time" (number not stated). Core Location's own limit is 20 monitored conditions/regions per app. [VERIFIED: UNLocationNotificationTrigger doc; https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions] [UNVERIFIED: whether UN location triggers share the 20-region pool] → Asist caps active location reminders at **10** and counts them in the 64 budget.
- Timing: boundary crossings are not immediate ("heuristics to ensure that the boundary crossing represents a deliberate event"). Use radius **150–300 m** (clamp to 100…1000 m and ≤ `maximumRegionMonitoringDistance`).
- Location notifications do **not** launch the app. Nagging after arrival: on the next reconcile, `deliveredNotifications()` reveals `asist.l.<UUID>` with its `date` → the engine sets `triggeredAt` and starts a normal time chain from that date (§5).
- `CLCircularRegion` shows "deprecated 27.2" in the future SDK docs; irrelevant for iOS 17 target / Xcode 26. [VERIFIED: https://developer.apple.com/documentation/corelocation/clcircularregion]

```swift
import CoreLocation
import UserNotifications

/// Touch `.shared` first on the main thread (CLLocationManager delivers delegate calls on the thread that created it).
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermission()
    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    var canUseGeofences: Bool {
        let s = manager.authorizationStatus
        return (s == .authorizedWhenInUse || s == .authorizedAlways) && manager.accuracyAuthorization == .fullAccuracy
    }

    var maxRadius: CLLocationDistance { manager.maximumRegionMonitoringDistance }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { await ReminderEngine.shared.reconcile(reason: "locationAuth") }
    }
}

enum LocationRequestFactory {
    static func make(reminderID: UUID, title: String, subtitle: String, body: String,
                     latitude: Double, longitude: Double, radius: Double, onArrival: Bool) -> UNNotificationRequest {
        let upper = max(100, min(1000, LocationPermission.shared.maxRadius))
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                      radius: min(max(radius, 100), upper),
                                      identifier: "asist.l.\(reminderID.uuidString)")
        region.notifyOnEntry = onArrival
        region.notifyOnExit = !onArrival
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.categoryIdentifier = AsistNotif.Category.reminder
        content.threadIdentifier = "asist.r.\(reminderID.uuidString)"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [AsistNotif.Key.reminderID: reminderID.uuidString, AsistNotif.Key.attempt: 0]
        let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
        return UNNotificationRequest(identifier: "asist.l.\(reminderID.uuidString)", content: content, trigger: trigger)
    }
}
```
(`authorizationStatus` and `accuracyAuthorization` are iOS 14+ instance properties; `maximumRegionMonitoringDistance` returns −1 when unsupported — the `max(100, …)` clamp handles it.)

---

## 4. Background refresh — BGTaskScheduler

### 4.1 API (current SDK)

```swift
class var shared: BGTaskScheduler
func register(forTaskWithIdentifier identifier: String, using queue: dispatch_queue_t?, launchHandler: @escaping (BGTask) -> Void) -> Bool
func submit(_ taskRequest: BGTaskRequest) throws                // deprecated 27.0 only; fine for Xcode 26 / target 17
class BGAppRefreshTaskRequest { init(identifier: String) }
var earliestBeginDate: Date? { get set }
// BGTask: var expirationHandler: (() -> Void)?; func setTaskCompleted(success: Bool)
```
[VERIFIED: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:) , .../submit(_:) , .../bgapprefreshtaskrequest , .../bgtaskrequest/earliestbegindate]

Do **not** use `submitTaskRequest(_:completionHandler:)` / `try await submitTaskRequest(_:)` — iOS 27.0+ only. [VERIFIED: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submittaskrequest(_:completionhandler:)]

Hard rules:
- `register` returns `false` if the identifier is not in `BGTaskSchedulerPermittedIdentifiers`. "Registration of all launch handlers must be complete before the end of `applicationDidFinishLaunching(_:)`." "**Register each task identifier only once. The system kills the app on the second registration of the same task identifier.**" [VERIFIED: register doc above]
- Submitting a request whose identifier has no registered handler crashes: "No launch handler registered for task with identifier …". [VERIFIED-COMMUNITY: https://nilcoalescing.com/blog/SchedulingAndHandlingBackgroundAppRefreshInSwiftUI/]
- Max **1 refresh** + 10 processing requests pending; resubmitting replaces the previous request. [VERIFIED: submit doc]
- Adding `BGTaskSchedulerPermittedIdentifiers` disables the legacy `performFetchWithCompletionHandler` API. Background Modes → "Background fetch" (`UIBackgroundModes: fetch`) is required for app refresh. [VERIFIED: https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app]
- Runtime budget: "provides your app **up to 30 seconds** of background runtime"; call `setTaskCompleted(success:)` or the system terminates the app. [VERIFIED: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app]

### 4.2 SwiftUI `.backgroundTask` — documented, but NOT used

Exact API: `nonisolated func backgroundTask<D, R>(_ task: BackgroundTask<D, R>, action: @escaping @Sendable (D) async -> R) -> some Scene where D : Sendable, R : Sendable` (iOS 16+) with `static func appRefresh(_ identifier: String) -> BackgroundTask<Void, Void>`; usage:
```swift
WindowGroup { RootView() }
    .backgroundTask(.appRefresh("com.gokhanbudak.asist.refresh")) { await ReminderEngine.shared.reconcile(reason: "bg") }
```
[VERIFIED: https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:) , https://developer.apple.com/documentation/swiftui/backgroundtask/apprefresh(_:)]
Why not: on iOS 18.4 SwiftUI registered the handler too late when the app was launched in the background (widgets, shortcuts, Control Center) → crash "All launch handlers must be registered before application finishes launching" (fixed in iOS 18.5 b2). Apple DTS recommendation: register in `application(_:didFinishLaunchingWithOptions:)` via `UIApplicationDelegateAdaptor`, "The core issue here comes down to timing issues within SwiftUI's lifecycle". Asist is launched in the background often (actions, App Intents, controls) → follow DTS. **Never combine** the modifier with manual registration for the same ID (double registration kills the app). [VERIFIED: https://developer.apple.com/forums/thread/775182 , https://developer.apple.com/forums/thread/775182?page=2]

### 4.3 Code

```swift
import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    static let taskID = "com.gokhanbudak.asist.refresh"   // must equal Info.plist BGTaskSchedulerPermittedIdentifiers[0]

    /// Call exactly once, from AppDelegate.didFinishLaunching.
    static func register() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task)
        }
        if !ok { AsistLog.error("BGTask register failed: identifier missing from Info.plist?") }
    }

    static func schedule(after seconds: TimeInterval = 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // .unavailable: Background App Refresh off, Low Power Mode, simulator. Not an error for us.
            AsistLog.info("BGTask submit failed: \(error)")
        }
    }

    private static func handle(_ task: BGTask) {
        schedule()                                   // keep one request queued
        let work = Task {
            await ReminderEngine.shared.reconcile(reason: "bgRefresh")
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
```
(`AsistLog` = the app's logger; in Swift 5 minimal mode capturing the non-Sendable `BGTask` in `Task {}` is accepted.)

### 4.4 Realistic expectations and what to do there

- Quinn (DTS): "if you expect that the app refresh mechanism will grant you background execution time, say, every 15 minutes, you'll be disappointed. In fact, there are common scenarios where it won't grant you *any* background execution time at all!" After a force-quit no background launch until the user opens the app again. Low Power Mode and the per-app "Arka Planda Yenile" switch disable it. [VERIFIED: https://developer.apple.com/forums/thread/685525]
- Expect somewhere between 0 and a few runs per day, correlated with how often the user opens Asist. [UNVERIFIED: no official numbers]
- Safe work (≤ 5 s target, hard limit 30 s): reconcile the notification plan, clean delivered notifications, update badge, reload widget timelines, schedule the next refresh. **Not** allowed: Claude API calls, large migrations, anything needing UI.
- The reminder system must be correct with **zero** BG runs — refresh only improves freshness (e.g. converts an exhausted chain to the daily long-tail repeat earlier).

---

## 5. "Nag until done" within the 64-request limit

### 5.1 Principles

1. **Pre-schedule, never chain at runtime.** Each follow-up already exists as its own pending request; the app does not need to run for a nag to fire.
2. **Only "Tamamlandı" stops the nag.** Snooze re-bases the chain; Clear/dismiss/body-tap/alarm-stop never stop it.
3. **Fail loud.** Every failure mode (handler not run, app not opened, budget overflow) degrades to *more* reminders, not fewer.
4. **Idempotent reconcile.** The desired pending set is a pure function of (open reminders, now, policy); applying it twice changes nothing.
5. **Never exceed 60 own requests**, so the system's silent "keep soonest 64" eviction never decides for us.

### 5.2 Default nag policy ("Israrcı" — default)

Relative to the anchor A = max(due date, snoozedUntil) (for location reminders: the delivery date of the location notification):

| # (k) | When | Notes |
|---|---|---|
| 0 | A | Exactly the time the user asked for — never shifted by quiet hours. |
| 1 | A + 5 min | |
| 2 | A + 15 min | |
| 3 | A + 30 min | |
| 4 | A + 1 h | |
| 5 | A + 2 h | |
| 6 | A + 4 h | |
| 7 | next active day 09:00 | |
| 8 | next active day 14:00 | |
| 9 | the day after 09:00 | Last chain element. |
| d | daily 09:00, repeating | Added only when the chain has no future elements left (1 slot, forever until done). |

- Active hours default **08:00–21:00**, every day (configurable; weekend on/off). Follow-ups (k ≥ 1) falling outside are moved to the next active start; duplicates within the same minute are merged.
- Per-reminder cap: 10 pending (+1 daily repeat).
- Alternative profiles in Settings: **Nazik** (A, +15 m, +1 h, next day 09:00, then daily) and **Çok ısrarcı** (A, +2, +5, +10, +15, +30 m, then every 30 min within active hours, capped at 10).
- Optional pre-alert (A − 10 min) for items the parser classified as meetings/calls (off by default).
- User recurrences ("her pazartesi 9'da haftalık rapor") are expanded by AsistCore into the **next occurrence only**; that occurrence is a normal anchor with its own chain. Never use `repeats: true` for user recurrences (a repeating request cannot be individually "done" and cannot nag).

Worked example (today Sun 2026-09-27, Europe/Istanbul): "Salı günü teklif konusunu bana saat 3'te hatırlat" → A = Tue 2026-09-29 15:00. Chain: Tue 15:00, 15:05, 15:15, 15:30, 16:00, 17:00, 19:00, Wed 09:00, Wed 14:00, Thu 09:00. The user taps **Tamamlandı** at 15:07 → the engine removes the 8 remaining pending requests + the 2 delivered ones + the AlarmKit alarm (if any). If the tap handler does not run (see §2.3 force-quit caveat), the user gets the 15:15 nag and can complete it in the app.

A = 20:30 example: 20:30, 20:35, 20:45, (21:00, 21:30, 22:30, 00:30 → shifted to 08:00, merged) 08:00, 09:00, 14:00, day+2 09:00.

### 5.3 Planner (AsistCore, pure Foundation, unit-tested on Linux)

Public types:

```swift
import Foundation

public struct PlannedNotification: Equatable, Sendable {
    public enum Rule: Equatable, Sendable {
        case once
        case daily(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int)
    }
    public enum Interruption: String, Equatable, Sendable { case passive, active, timeSensitive }
    public enum Kind: String, Equatable, Sendable { case reminder, longTail, briefing, sentinel }

    public var id: String            // "asist.r.<UUID>.<k>", "asist.r.<UUID>.d", "asist.b.morning", "asist.s"
    public var kind: Kind
    public var reminderID: UUID?
    public var attempt: Int
    public var fireDate: Date        // for repeating rules: the first expected fire (for sorting only)
    public var rule: Rule
    public var title: String
    public var subtitle: String
    public var body: String
    public var threadID: String
    public var categoryID: String
    public var badge: Int?
    public var interruption: Interruption
    public var relevance: Double
    public var priorityTier: Int     // planner-internal ordering
    public var fingerprint: String   // StableHash over everything that affects the system request
}

public enum StableHash {
    /// FNV-1a 64-bit. Stable across launches and platforms (unlike hashValue/Hasher).
    public static func fnv1a64(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}

public struct NagPolicy: Codable, Equatable, Sendable {
    public var offsetsMinutes: [Int] = [0, 5, 15, 30, 60, 120, 240]
    public var nextDayMinutesOfDay: [Int] = [9 * 60, 14 * 60]
    public var extraDayMinuteOfDay: Int? = 9 * 60     // "the day after" nag; nil = off
    public var activeStartMinute: Int = 8 * 60
    public var activeEndMinute: Int = 21 * 60
    public var maxPendingPerReminder: Int = 10
    public var longTailMinuteOfDay: Int = 9 * 60
    public init() {}
}

public struct PlanResult: Equatable, Sendable {
    public var notifications: [PlannedNotification]   // ≤ budget + reserved
    public var droppedCount: Int
    public var badgeNow: Int
    public var alarms: [AlarmPlan]                     // AlarmKit requests (§6)
}

public struct AlarmPlan: Equatable, Sendable {
    public var reminderID: UUID
    public var fireDate: Date
    public var title: String
}
```

Algorithm `NotificationPlanner.plan(reminders:now:policy:calendar:budget:) -> PlanResult`:

1. For each open reminder with an anchor A (skip done/cancelled; location reminders without `triggeredAt` produce only their location request, handled by the adapter):
   - Build raw times: `A + offsetsMinutes[i]`, next active day at each `nextDayMinutesOfDay`, and the extra day.
   - Shift every k ≥ 1 into active hours; merge equal minutes; sort; assign k = 0,1,2,… **by position in the full chain computed from A** (not from now), so IDs stay stable across reconciles.
   - Drop elements with `fireDate ≤ now + 10 s`. Keep the first `maxPendingPerReminder`.
   - If no chain element is left and the reminder is still open → one `longTail` request `asist.r.<UUID>.d`, rule `.daily(hour: 9, minute: 0)`.
2. Priority tiers (lower = kept first):
   - Tier 0: k = 0 with fireDate ≤ now + 48 h; all long-tail dailies.
   - Tier 1: k = 1…4 whose anchor ≤ now + 48 h (includes overdue items).
   - Tier 2: k = 0 with fireDate in (48 h, 14 days].
   - Tier 3: all other follow-ups.
   - Beyond 14 days: not planned (a later reconcile will pick them up).
3. Sort by `(priorityTier, fireDate)` (tuple `<` works for `(Int, Date)`), keep the first `budget` (default **60**).
4. Reserved (outside the 60): morning briefing (`asist.b.morning`, daily 08:30, `.passive`, only if enabled), sentinel (`asist.s`), 2 spare for immediate test/confirmation notifications.
5. Sentinel: if anything was dropped, add a one-shot at the **earliest dropped fireDate**: title "Asist planını yenilemeli", body "Planlanamayan N hatırlatma var. Asist'i bir kez açman yeterli." — the user is alerted exactly when the first gap would occur.
6. Badge per notification = number of open reminders whose anchor ≤ that notification's fireDate (projected overdue count). `badgeNow` = currently overdue open reminders.
7. Fingerprint = `StableHash.fnv1a64("\(id)|\(Int(fireDate.timeIntervalSince1970))|\(rule)|\(title)|\(subtitle)|\(body)|\(badge ?? -1)|\(categoryID)|\(interruption.rawValue)")`.

Unit tests (Linux CI) must cover: worked examples above; quiet-hour shifting and merging; overdue reminder with partially elapsed chain keeps the same IDs for remaining elements; >60 candidates → correct tiers, sentinel at earliest dropped; snooze re-bases from k = 0; fingerprint stability for identical input.

### 5.4 Applying the plan (iOS adapter)

```swift
import Foundation
import UserNotifications
import AsistCore

actor NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    /// Diff-apply: remove ours that are not desired, add desired ones that are missing or changed.
    func apply(_ desired: [PlannedNotification]) async {
        let now = Date()
        var wanted: [String: PlannedNotification] = [:]
        for p in desired where wanted[p.id] == nil { wanted[p.id] = p }          // no trap on duplicates

        let pending = await center.pendingNotificationRequests()
        var unchanged = Set<String>()
        var toRemove: [String] = []
        for req in pending where req.identifier.hasPrefix(AsistNotif.managedPrefix) {
            if req.identifier.hasPrefix("asist.l.") { continue }                   // location requests managed separately
            guard let want = wanted[req.identifier] else { toRemove.append(req.identifier); continue }
            if (req.content.userInfo[AsistNotif.Key.fingerprint] as? String) == want.fingerprint {
                unchanged.insert(req.identifier)
            }
        }
        if !toRemove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: toRemove) }

        for p in wanted.values where !unchanged.contains(p.id) {
            if p.rule == .once && p.fireDate <= now { continue }
            do {
                try await center.add(NotificationRequestFactory.make(p, now: now))   // same ID replaces the old one
            } catch {
                AsistLog.error("add \(p.id) failed: \(error)")
            }
        }
    }

    /// Keep only the newest delivered notification per open reminder; drop everything of done reminders.
    func cleanupDelivered(openReminderIDs: Set<UUID>) async {
        let delivered = await center.deliveredNotifications()
        var newest: [UUID: (id: String, date: Date)] = [:]
        var toRemove: [String] = []
        for n in delivered where n.request.identifier.hasPrefix("asist.r.") {
            let rid = (n.request.content.userInfo[AsistNotif.Key.reminderID] as? String).flatMap { UUID(uuidString: $0) }
            guard let id = rid, openReminderIDs.contains(id) else {
                toRemove.append(n.request.identifier)
                continue
            }
            if let current = newest[id] {
                if n.date > current.date {
                    toRemove.append(current.id)
                    newest[id] = (n.request.identifier, n.date)
                } else {
                    toRemove.append(n.request.identifier)
                }
            } else {
                newest[id] = (n.request.identifier, n.date)
            }
        }
        if !toRemove.isEmpty { center.removeDeliveredNotifications(withIdentifiers: toRemove) }
    }
}
```
(`p.rule == .once` compiles because `Rule: Equatable`.)

### 5.5 When reconcile runs

| Trigger | Where |
|---|---|
| App launch | `AppDelegate.didFinishLaunching` (after delegate/categories) — also covers background launches |
| Foreground | `scenePhase == .active` |
| Every notification response (done/snooze/reply/clear/tap) | `ReminderEngine.handle` |
| Foreground delivery | `willPresent` |
| Any data change | create/edit/delete/complete in UI, App Intents (Siri "Asist'e kaydet", widgets, Control Center control) — App Intents live in the **main app target** so they run in the app process |
| Time change | `UIApplication.significantTimeChangeNotification`, `.NSSystemTimeZoneDidChange` |
| Background | BG app refresh (bonus) |
| Location authorization change | `locationManagerDidChangeAuthorization` |

Only the **main app process** writes notification requests (single writer). Extensions, if any, only write data and rely on the next app reconcile.

### 5.6 Serializing reconciles (actor re-entrancy pitfall)

Swift actors are **re-entrant**: at every `await` inside `reconcile`, another `reconcile` (e.g. an action handler and a scene-phase change at the same moment) can interleave and apply an older plan after a newer one. Serialize with a task chain; each caller still awaits its own run (so the action handler calls `completionHandler()` only after its change is applied):

```swift
import Foundation
import UserNotifications
import AsistCore

actor ReminderEngine {
    static let shared = ReminderEngine()
    private var tail: Task<Void, Never>?

    func reconcile(reason: String) async {
        let previous = tail
        let run = Task {
            await previous?.value
            await self.reconcileOnce(reason: reason)
        }
        tail = run
        await run.value
    }

    private func reconcileOnce(reason: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }   // UI shows the "Bildirimler kapalı" banner

        let delivered = await center.deliveredNotifications()
        store.recordDeliveries(delivered.map { ($0.request.identifier, $0.date) })   // learns location fires, last attempt shown

        let snapshot = store.openReminderSnapshots()
        let plan = NotificationPlanner.plan(reminders: snapshot, now: Date(), policy: store.nagPolicy,
                                            calendar: .current, budget: 60)
        await NotificationScheduler.shared.apply(plan.notifications)
        await NotificationScheduler.shared.cleanupDelivered(openReminderIDs: Set(snapshot.map(\.id)))
        try? await center.setBadgeCount(plan.badgeNow)

        #if ASIST_ALARMKIT && canImport(AlarmKit)
        if #available(iOS 26.0, *) { await AlarmKitBridge.sync(plan.alarms) }
        #endif
        store.recordReconcile(reason: reason, at: Date(), pendingCount: plan.notifications.count)
    }
}
```
(`store` = persistence facade defined in the data-model doc; location requests are added/removed by a sibling `LocationScheduler` using `LocationRequestFactory`.)

### 5.7 Failure-mode matrix

| Failure | Effect | Mitigation |
|---|---|---|
| Action handler not run (force-quit, crash) | Done/snooze not recorded; chain continues | Fail-loud by design; user completes in-app; onboarding: don't force-quit; test T7 |
| App not opened for > 2 days | Chain exhausted, no long-tail yet | Sentinel only covers budget overflow → last chain element's body says "Asist'i açarsan her sabah hatırlatmaya devam ederim"; morning briefing (repeating) always fires |
| Notifications denied / disabled later | Nothing fires | Onboarding gate; red in-app banner + button to `openNotificationSettingsURLString`; diagnostics screen |
| Focus / Silent mode / Scheduled Summary | Delivered quietly or batched | §7.3 user settings; AlarmKit for important items |
| More than 60 candidates | Lower tiers not scheduled | Tiering + sentinel at the first gap |
| Time-zone travel | Floating times shift | Reconcile on time-zone change; fingerprint compare |
| Sideload certificate expired (7 days) | Local notifications should still fire (system-owned); tapping/actions cannot launch the app | Asist schedules its own "İmzayı yenile" reminder 1 day before `ExpirationDate` read from `embedded.mobileprovision` (distribution doc) [UNVERIFIED: delivery after expiry] |
| Re-sign/reinstall over existing app | Data, permission and pending requests are kept | Deleting the app loses everything (warn in docs) [UNVERIFIED: pending requests survive re-sign; test T10] |
| Device reboot | Pending requests persist (system store) | Reconcile on next launch anyway [UNVERIFIED-COMMON] |

---

## 6. AlarmKit (iOS 26)

### 6.1 Verified API surface

| Symbol | Exact declaration | Availability |
|---|---|---|
| `AlarmManager.shared` | `static let shared: AlarmManager` | 26.0 |
| authorization | `func requestAuthorization() async throws -> AlarmManager.AuthorizationState`; `var authorizationState: AlarmManager.AuthorizationState { get }`; cases `.authorized, .denied, .notDetermined` | 26.0 |
| schedule | `func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata : AlarmMetadata` (`Alarm.id: UUID`) | 26.0 |
| state changes | `func cancel(id: Alarm.ID) throws`, `stop(id:)`, `pause(id:)`, `resume(id:)`, `countdown(id:)` | 26.0 |
| list | `var alarms: [Alarm] { get throws }` — fired-and-stopped one-shots are deleted from the daemon | 26.0 |
| errors | `AlarmManager.AlarmError.maximumLimitReached` (limit value undocumented) | 26.0 |
| configuration | `static func alarm(schedule: Alarm.Schedule? = nil, attributes: AlarmAttributes<Metadata>, stopIntent: (any LiveActivityIntent)? = nil, secondaryIntent: (any LiveActivityIntent)? = nil, sound: AlertConfiguration.AlertSound = .default) -> AlarmManager.AlarmConfiguration<Metadata>` | 26.0 |
| configuration (27) | same plus `appEntityIdentifier: EntityIdentifier? = nil` | **27.0 — do not use** |
| schedule enum | `Alarm.Schedule`: `case fixed(Date)`, `case relative(Alarm.Schedule.Relative)`; `Relative(time: Alarm.Schedule.Relative.Time, repeats: Alarm.Schedule.Relative.Recurrence)`, `.never` / `.weekly([Locale.Weekday])` | 26.0 |
| attributes | `init(presentation: AlarmPresentation, metadata: Metadata?, tintColor: Color)` on `AlarmAttributes<Metadata>` | 26.0 |
| presentation | `init(alert: AlarmPresentation.Alert, countdown: AlarmPresentation.Countdown? = nil, paused: AlarmPresentation.Paused? = nil)` | 26.0 |
| alert (old) | `init(title: LocalizedStringResource, stopButton: AlarmButton, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = nil)` — **deprecated 26.1**: "stopButton is deprecated and will no longer be used" | 26.0 |
| alert (new) | `init(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = nil)` — system provides the stop control | **26.1** |
| secondary behavior | `enum SecondaryButtonBehavior { case countdown, custom }` (there is **no** `.snooze`) | 26.0 |
| button | `init(text: LocalizedStringResource, textColor: Color, systemImageName: String)` | 26.0 |
| metadata | `protocol AlarmMetadata : Decodable, Encodable, Hashable, Sendable` (may be empty) | 26.0 |

[VERIFIED: https://developer.apple.com/documentation/alarmkit/alarmmanager , .../alarmmanager/schedule(id:configuration:) , .../alarmmanager/alarmconfiguration , .../alarmmanager/alarmconfiguration/alarm(schedule:attributes:stopintent:secondaryintent:sound:) , .../alarmpresentation/alert-swift.struct , .../alarmpresentation/alert-swift.struct/init(title:secondarybutton:secondarybuttonbehavior:) , .../alarmpresentation/alert-swift.struct/init(title:stopbutton:secondarybutton:secondarybuttonbehavior:) , .../alarmbutton , .../alarmattributes , .../alarmmetadata , .../alarm/schedule-swift.enum , .../alarmmanager/alarms , .../alarmmanager/alarmerror]

### 6.2 Setup facts

- **Info.plist `NSAlarmKitUsageDescription`** (non-empty) is mandatory: "If the key is missing or its value is an empty string, your app can't schedule alarms with AlarmKit." [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription]
- **No entitlement exists for AlarmKit.** An Apple engineer warned that LLMs invent `com.apple.developer.alarmkit`; adding it breaks provisioning. [VERIFIED: https://developer.apple.com/forums/thread/797950] → works with free provisioning in principle. [UNVERIFIED: on-device with a Sideloadly-signed build; test T12]
- Authorization is requested automatically on the first `schedule` if not determined, or explicitly; "If a person … denies authorization, all attempts to schedule alarms fail." [VERIFIED: https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit , .../requestauthorization()]
- **Widget extension:** "AlarmKit expects a widget extension if an app supports a **countdown** presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert." WWDC25-230: "If your alarm just needs to show an alert, this is all you need to do." → **Alert-only alarms need no widget extension / Live Activity.** Snooze (`.countdown` secondary behavior with `postAlert`) shows a countdown → would require the widget extension → excluded from v1. [VERIFIED: https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit , https://developer.apple.com/videos/play/wwdc2025/230/]
- `NSSupportsLiveActivities = YES`: not documented as required for AlarmKit; some guides add it because `AlarmAttributes` is an `ActivityAttributes`. Harmless Info.plist key → add it. [UNVERIFIED: necessity]
- Behavior: "When it fires, the alert breaks through the silent mode and the current focus." The alert shows the custom title and the app name; Apple positions alarms for scheduled wake-ups/timers and says they are "not a replacement for other prominent notifications, like critical alerts or time-sensitive notifications." [VERIFIED: https://developer.apple.com/videos/play/wwdc2025/230/]
- Known bug: after a device restart (iOS 26.0.1 – 26.1 betas) scheduled alarms showed localization **keys** instead of strings (e.g. `alarm_ui_stop_button`); workaround: use the literal display text as the key. [VERIFIED (forum report + Apple reply "test with 26.1"): https://developer.apple.com/forums/thread/802740] → We pass the Turkish text itself as `LocalizedStringResource`.
- Online misinformation to ignore: `SecondaryButtonBehavior.snooze`, an "AlarmKit capability" in the developer portal (e.g. https://bleepingswift.com/blog/scheduling-alarms-with-alarmkit contains both errors).

### 6.3 Compile-risk assessment

| Risk | Level | Mitigation |
|---|---|---|
| iOS 26-only framework in an iOS 17 target | Low | `#if canImport(AlarmKit)` + `@available(iOS 26.0, *)` on every type; Swift weak-links symbols newer than the target; optional `OTHER_LDFLAGS: -weak_framework AlarmKit` |
| 26.0 → 26.1 API change (`stopButton`) | Medium | Use only the **26.0 initializer** (deprecated, not removed): compiles with every Xcode 26.x and 27 SDK; at runtime ≥ 26.1 the stop button argument is ignored |
| iOS 27 SDK adds defaulted `appEntityIdentifier:` overloads | Medium (only with Xcode 27) | Pin Xcode 26.6 in CI (D11) |
| Generic inference (`Metadata`) | Medium | Spell the generic explicitly: `AlarmAttributes<AsistAlarmMetadata>`, `AlarmManager.AlarmConfiguration<AsistAlarmMetadata>.alarm(...)`; never pass `metadata: nil` without the explicit type |
| `LocalizedStringResource` from a `String` variable | Medium | `LocalizedStringResource(stringLiteral: text)` (a `String` is not implicitly convertible) |
| Missing default arguments in older 26.x SDK | Low | Pass every argument explicitly (`secondaryButton: nil, secondaryButtonBehavior: nil, stopIntent: nil, secondaryIntent: nil, sound: .default`) |
| Whole-file failure in CI | — | Remove `ASIST_ALARMKIT` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS` → the file compiles to nothing; all call sites are behind the same `#if` |

**Recommendation: include in v1** as specified (alert-only, opt-in per reminder, default off, global switch in Settings "Önemli hatırlatmalar alarm gibi çalsın"). The UN nag chain is always scheduled as well: the alarm provides attention (silent mode/Focus), the notification provides content + actions (Tamamlandı/Ertele) and keeps nagging after the alarm is stopped.

### 6.4 Exact code

```swift
// File: Asist/Platform/AlarmKitBridge.swift
#if ASIST_ALARMKIT && canImport(AlarmKit)
import AlarmKit
import ActivityKit      // AlertConfiguration.AlertSound (.default) lives here; explicit import avoids member-visibility surprises
import Foundation
import SwiftUI
import AsistCore

@available(iOS 26.0, *)
struct AsistAlarmMetadata: AlarmMetadata {
    var reminderID: String
}

@available(iOS 26.0, *)
enum AlarmKitBridge {

    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Call from a foreground UI action (the per-reminder "Alarm olarak çal" toggle).
    static func requestAuthorizationIfNeeded() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func schedule(_ plan: AlarmPlan) async throws {
        guard plan.fireDate.timeIntervalSinceNow > 5 else { return }
        let title = LocalizedStringResource(stringLiteral: sanitized(plan.title))
        let stop = AlarmButton(text: "Durdur", textColor: .white, systemImageName: "stop.circle")
        // iOS 26.0 initializer: deprecated in 26.1 (stopButton ignored there) but present in every 26.x/27 SDK.
        let alert = AlarmPresentation.Alert(title: title,
                                            stopButton: stop,
                                            secondaryButton: nil,
                                            secondaryButtonBehavior: nil)
        let presentation = AlarmPresentation(alert: alert, countdown: nil, paused: nil)
        let attributes = AlarmAttributes<AsistAlarmMetadata>(presentation: presentation,
                                                             metadata: AsistAlarmMetadata(reminderID: plan.reminderID.uuidString),
                                                             tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration<AsistAlarmMetadata>.alarm(schedule: .fixed(plan.fireDate),
                                                                                       attributes: attributes,
                                                                                       stopIntent: nil,
                                                                                       secondaryIntent: nil,
                                                                                       sound: .default)
        _ = try await AlarmManager.shared.schedule(id: plan.reminderID, configuration: configuration)
    }

    static func cancel(reminderID: UUID) {
        try? AlarmManager.shared.cancel(id: reminderID)
    }

    /// Make AlarmKit's set equal to the desired set (reminder UUID == alarm ID).
    static func sync(_ desired: [AlarmPlan]) async {
        guard isAuthorized else { return }
        let existing = (try? AlarmManager.shared.alarms) ?? []
        var existingDate: [UUID: Date] = [:]
        for alarm in existing {
            if case .fixed(let date)? = alarm.schedule {
                existingDate[alarm.id] = date
            } else {
                existingDate[alarm.id] = .distantPast
            }
        }
        var wanted: [UUID: AlarmPlan] = [:]
        for p in desired where wanted[p.reminderID] == nil { wanted[p.reminderID] = p }

        for (id, _) in existingDate where wanted[id] == nil {
            try? AlarmManager.shared.cancel(id: id)
        }
        for (id, plan) in wanted {
            if let date = existingDate[id] {
                if abs(date.timeIntervalSince(plan.fireDate)) < 1 { continue }
                try? AlarmManager.shared.cancel(id: id)
            }
            do {
                try await schedule(plan)
            } catch {
                AsistLog.error("AlarmKit schedule failed (\(id)): \(error)")   // e.g. maximumLimitReached → UN chain still covers it
            }
        }
    }

    private static func sanitized(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "%", with: " ")
        return String(oneLine.prefix(60))
    }
}
#endif
```

Planner rule for `alarms`: include a reminder iff `useAlarm == true`, not done, anchor (k = 0 time, i.e. due or snoozed-until) is in the future and ≤ 14 days; at most 10 alarms. Snooze moves the alarm (sync cancels and reschedules). Done → `cancel`.

Alternative after the CI toolchain is confirmed ≥ Xcode 26.1 (optional, not needed): `if #available(iOS 26.1, *) { AlarmPresentation.Alert(title: title) } else { /* 26.0 init */ }`.

---

## 7. Badge, grouping, and making the content impossible to miss

### 7.1 Badge

- Authorization option `.badge`; set with `setBadgeCount(_:) async throws` (iOS 16+) on every reconcile to `badgeNow` (= open reminders whose anchor has passed). Do not use the deprecated `applicationIconBadgeNumber`.
- Each scheduled notification carries `content.badge` = projected overdue count at its fire time (§5.3 step 6), so the badge is correct even if the app never runs.

### 7.2 Grouping and layout

- `threadIdentifier = "asist.r.<UUID>"` → all nags of one topic collapse into one stack; different topics stay separate (no "7 Asist notifications" blob).
- `cleanupDelivered` keeps only the newest delivered notification per open reminder (§5.4), so the stack shows one up-to-date card.
- `.hiddenPreviewsShowTitle` / `.hiddenPreviewsShowSubtitle` (iOS 11+): "Show the notification's title/subtitle, even if the user has disabled notification previews for the app." iPhone's default "Show Previews: When Unlocked" would otherwise hide the reminder text on the Lock Screen. [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationcategoryoptions/hiddenpreviewsshowtitle] [UNVERIFIED-COMMON: default preview setting on Face ID iPhones] Setting in Asist: "Kilit ekranında konuyu göster" (default on; off → use a category variant without these options).
- `hiddenPreviewsBodyPlaceholder` supports only `%u` (count of notifications in the thread). [VERIFIED: https://developer.apple.com/documentation/usernotifications/unnotificationcategory/init(identifier:actions:intentidentifiers:hiddenpreviewsbodyplaceholder:options:)]

### 7.3 Copy templates (Turkish, generated by AsistCore)

| Field | k = 0 | k ≥ 1 | Long tail (daily) |
|---|---|---|---|
| title | The task itself, ≤ 50 chars: `Teklif – ABC Makina` | same | same |
| subtitle | `Salı 15:00` | `3. hatırlatma · 30 dk gecikti` | `Hâlâ açık · 3 gündür bekliyor` |
| body | Original sentence + note: `“Salı günü teklif konusunu bana saat 3'te hatırlat”` + newline + `Bitince “Tamamlandı”ya dokun.` | Note + `Tamamlandı demedikçe hatırlatmaya devam edeceğim. Sonraki: 16:00` | Note + `Her sabah 09:00'da soracağım.` |

Rules: the title never contains only a generic word ("Hatırlatma") — the parser's topic is always the title; the subtitle always carries the *why now* (time, attempt, delay); the body always states the next nag time so the user knows dismissing is not the end. Long-press shows all actions: Tamamlandı · 10 dk sonra · 1 saat sonra · Yarın sabah · Başka zaman/not (dictation).

### 7.4 User-side settings (onboarding checklist, Turkish UI text)

Because the time-sensitive capability is unavailable with a free Apple ID, onboarding shows these steps with a "Ayarları aç" button (`openNotificationSettingsURLString`) and reads back `UNNotificationSettings` to tick them automatically where possible:

1. Bildirimlere izin ver; Kilit Ekranı, Bildirim Merkezi, Afişler açık (`lockScreenSetting`, `notificationCenterSetting`, `alertSetting`).
2. Afiş stili **Kalıcı** (persistent banners stay until handled). `settings.alertStyle == .alert` ("Alerts are displayed in a modal window that must be dismissed explicitly") [VERIFIED: https://developer.apple.com/documentation/usernotifications/unalertstyle/alert] [UNVERIFIED: mapping of the iOS "Kalıcı" banner style to `.alert` — verify on device, test T4].
3. **Planlanmış Özet'e ekleme** — Asist must be "Anında Bildirim" (`scheduledDeliverySetting`).
4. Odak (Focus) modlarında **İzin Verilen Uygulamalar**'a Asist'i ekle (Çalışma, Toplantı, Uyku as desired).
5. Asist'i uygulama değiştiriciden kapatma (§2.3).
6. Önemli işler için "Alarm olarak çal" + AlarmKit izni (iOS 26).

### 7.5 In-app diagnostics screen ("Bildirim Tanılama")

Because there is no Mac/debugger, this screen is the primary verification tool: authorization status, alert style, time-sensitive setting, scheduled-summary setting; pending count `n/64` and the next 15 requests (`nextTriggerDate()`, title, attempt); delivered count; last reconcile (reason, time); last BG refresh run; AlarmKit authorization + alarm count; location authorization + accuracy. Plus a **"Test bildirimi (10 sn)"** button that schedules a real `ASIST_REMINDER` notification with a 10 s interval trigger and `asist.r.<testUUID>.0` id.

---

## 8. Info.plist, entitlements, build settings (project.yml excerpt)

```yaml
targets:
  Asist:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    info:
      path: Asist/Info.plist
      properties:
        UIBackgroundModes: [fetch]
        BGTaskSchedulerPermittedIdentifiers: [com.gokhanbudak.asist.refresh]
        NSAlarmKitUsageDescription: "Önemli hatırlatmaların sessiz modda ve Odak açıkken de çalabilmesi için alarm izni gerekir."
        NSSupportsLiveActivities: true
        NSLocationWhenInUseUsageDescription: "Konuma bağlı hatırlatmalar (örn. 'fabrikaya varınca hatırlat') için konum izni gerekir."
    settings:
      base:
        SWIFT_VERSION: "5.0"
        SWIFT_STRICT_CONCURRENCY: minimal
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ASIST_ALARMKIT"
        OTHER_LDFLAGS: ["$(inherited)", "-weak_framework", "AlarmKit"]   # optional belt-and-braces
```

- No key is needed for local notifications themselves.
- Entitlements for this topic: **none**. Do not add `aps-environment`, `com.apple.developer.usernotifications.time-sensitive`, `com.apple.developer.usernotifications.critical-alerts`, or any "alarmkit" entitlement.
- If `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `base` overrides XcodeGen's Debug preset, `DEBUG` may disappear in Debug builds; irrelevant for the Release IPA (check the generated settings once in the CI log). [UNVERIFIED: XcodeGen merge order]
- CI: `sudo xcode-select -s /Applications/Xcode_26.6.app` on `runs-on: macos-26`.

---

## 9. On-device test checklist (run after every install; results go into the diagnostics log)

| ID | Test | Expected |
|---|---|---|
| T1 | Fresh install → onboarding → allow notifications | Status `.authorized`; categories registered |
| T2 | "Test bildirimi (10 sn)", app in foreground | Banner + sound (willPresent) |
| T3 | Same, app in background, locked phone | Lock-screen card shows title + subtitle even with previews hidden |
| T4 | Set banner style Kalıcı in Settings | Diagnostics shows `alertStyle == .alert` |
| T5 | Long-press → Tamamlandı (app in background) | Remaining chain removed within seconds; diagnostics pending count drops |
| T6 | Same with the app **terminated by the system** (reboot the phone first, do not open Asist) | Action handled (background launch) |
| T7 | Same after **force-quit** from the app switcher | Record result; if not handled, the next nag still fires (fail-loud) |
| T8 | "Başka zaman" → dictate "yarın 10'da" | Chain re-based to tomorrow 10:00 |
| T9 | Notification Center → Clear the card | `UNNotificationDismissActionIdentifier` logged; chain continues |
| T10 | Re-sign with Sideloadly (install over) | Data, permission and pending requests still present |
| T11 | Create 70 reminders due in the next 2 days | Pending = 60 + reserved; sentinel at the first dropped time |
| T12 | AlarmKit: enable "Alarm olarak çal", ringer switch on silent, Focus on | Full-screen alarm with the Turkish title; Stop works; UN notification with actions remains |
| T13 | Location reminder, when-in-use + precise | Fires on arrival with the app closed |
| T14 | Change time zone in Settings (Date & Time) | Reconcile on next foreground; pending dates updated |
| T15 | Leave the phone overnight, Background App Refresh on | Diagnostics shows ≥ 0 BG runs (informational only) |

---

## 10. Open issues (need device tests or product decisions)

1. Force-quit + background notification action (T7) — undocumented.
2. Exact mapping of "Kalıcı" banner style to `UNAlertStyle.alert` (T4).
3. Whether pending requests survive a Sideloadly re-sign and whether they still fire after the 7-day certificate expires.
4. Whether UN location triggers share Core Location's 20-region pool.
5. AlarmKit on a free-signed sideloaded build (T12) and its undocumented alarm-count limit.
6. Product: default active hours (08:00–21:00) and whether weekends nag.

---

## 11. Sources

- Apple docs (UserNotifications): https://developer.apple.com/documentation/usernotifications/unusernotificationcenter , https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types , https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions , https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/foreground , https://developer.apple.com/documentation/usernotifications/unnotificationdismissactionidentifier , https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate , https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate , https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:) , https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger/init(timeinterval:repeats:) , https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger , https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger , https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent , https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel , https://developer.apple.com/documentation/usernotifications/unnotificationsound , https://developer.apple.com/documentation/usernotifications/unnotificationcategory , https://developer.apple.com/documentation/usernotifications/unerror/code
- 64 limit: https://developer.apple.com/documentation/uikit/uilocalnotification , https://developer.apple.com/forums/thread/811171 , https://developer.apple.com/forums/thread/765490
- Capabilities by membership: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Time-sensitive without entitlement: https://developer.apple.com/forums/thread/683630 , https://github.com/uzairansaruzi/hermex/issues/771 , https://developer.apple.com/videos/play/wwdc2021/10091/
- Background launch / force quit: https://developer.apple.com/forums/thread/736576 , https://developer.apple.com/forums/thread/685525 , https://developer.apple.com/forums/thread/808088
- Swift concurrency + delegates: https://developer.apple.com/forums/thread/762217 , https://developer.apple.com/forums/thread/796407
- Background tasks: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler , https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app , https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app , https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:) , https://developer.apple.com/forums/thread/775182
- Time zones: https://developer.apple.com/forums/thread/811265 , https://developer.apple.com/documentation/uikit/uiapplication/significanttimechangenotification
- Location: https://developer.apple.com/documentation/corelocation/clcircularregion , https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions , https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization() , https://radar.com/blog/understanding-approximate-location-in-ios-14
- AlarmKit: https://developer.apple.com/documentation/alarmkit , https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit , https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription , https://developer.apple.com/videos/play/wwdc2025/230/ , https://developer.apple.com/forums/thread/797950 , https://developer.apple.com/forums/thread/802740
- CI toolchain: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
