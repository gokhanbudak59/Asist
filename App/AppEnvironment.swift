// FILE: App/AppEnvironment.swift
import Foundation
import UIKit
import AsistCore

/// Single owner of every long-lived service. Usable headless (notification actions, App Intents, BG refresh):
/// nothing here depends on a view having been created.
///
/// RULE (05a #11, §4.1 r13): no initializer invoked from `init()` below — nor anything those initializers create or
/// call synchronously — may reference `AppEnvironment.shared` (re-entrant `swift_once` traps at launch).
/// Cross-service access happens lazily inside methods or closures that run after init.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let store: DataStore
    let router: AppRouter
    let toasts: ToastCenter
    let permissions: PermissionCenter
    let scheduler: NotificationScheduler
    let signing: SigningMonitor
    let engine: ReminderEngine
    let capture: CaptureService
    let commands: CommandExecutor
    let voice: VoiceCoordinator

    private var bootstrapped = false
    private var observers: [NSObjectProtocol] = []
    private var flushTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        store = DataStore(files: StoreFiles.standard())
        router = AppRouter()
        toasts = ToastCenter()
        permissions = PermissionCenter()
        scheduler = NotificationScheduler()
        signing = SigningMonitor()
        engine = ReminderEngine(store: store, scheduler: scheduler, signing: signing)
        capture = CaptureService(store: store, router: router, toasts: toasts)
        commands = CommandExecutor(store: store, router: router, toasts: toasts)
        voice = VoiceCoordinator()
    }

    /// Idempotent. Called from AppDelegate, App Intents, notification delegate and BG refresh.
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        signing.reload()                                     // before any reconcile in this process (05a #4)
        store.onChange = { change in                         // before load(): a successful load emits .all (05a #6)
            AppEnvironment.shared.dataDidChange(change)
        }
        store.load()
        // Idempotent; also cover the "load failed → defaults" case.
        NotificationCategories.register(showContentOnLockScreen: store.settings.lockScreenShowsContent)
        voice.apply(settings: store.settings)                // stores configuration only; never arms (05a #25)
        observe(UIApplication.significantTimeChangeNotification, reason: "timeChange")
        observe(.NSSystemTimeZoneDidChange, reason: "timeZone")
        observe(UIApplication.protectedDataDidBecomeAvailableNotification, reason: "protectedData")
        engine.requestReconcile(reason: "launch")
        // Revision 4 (07 §9.5, §10.3): read authorization states only — never prompts.
        LocationService.shared.start()
        CalendarService.shared.start()
    }

    private func observe(_ name: Notification.Name, reason: String) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let env = AppEnvironment.shared
                if !env.store.isLoaded { env.store.load() }  // success emits .all → side effects re-applied
                env.engine.requestReconcile(reason: reason)
            }
        }
        observers.append(token)
    }

    /// Every persisted change funnels through here (single place that triggers side effects).
    /// DataStore emits only real changes (05a #5), so this never loops.
    func dataDidChange(_ change: StoreChange) {
        switch change {
        case .meta:
            return
        case .settings, .all:
            NotificationCategories.register(showContentOnLockScreen: store.settings.lockScreenShowsContent)
            voice.apply(settings: store.settings)
            capture.invalidateParser()
        case .projects, .places, .items:
            capture.invalidateParser()                       // projects/aliases and frequent people feed the parser
        }
        engine.requestReconcile(reason: "data." + change.rawValue)
        WidgetSnapshotWriter.shared.refresh(store: store, now: Date())   // 07 R4-D5 (no-op without App Group)
    }

    func sceneDidBecomeActive() async {
        bootstrap()
        if !store.isLoaded { store.load() }
        await permissions.refresh()
        if signing.refresh(store: store) {
            await engine.rebuildAll(reason: "resigned")
        } else {
            await engine.reconcile(reason: "active")
        }
        WidgetSnapshotWriter.shared.refresh(store: store, now: Date())
        CalendarService.shared.refresh(now: Date())
        UpdateChecker.shared.checkIfDue(store: store, now: Date())
        // 05a #26: onboarding only when the data file was really read (a locked-at-boot launch has defaults).
        if store.isLoaded && !store.settings.onboardingCompleted && !router.showOnboarding {
            router.showOnboarding = true
        }
        voice.sceneDidBecomeActive()
    }

    /// 05a #7: the open draft is committed and its notifications are planned before suspension.
    func sceneDidEnterBackground() {
        if flushTaskID == .invalid {
            flushTaskID = UIApplication.shared.beginBackgroundTask(withName: "asist.flush") {
                MainActor.assumeIsolated {
                    AppEnvironment.shared.endFlush()
                }
            }
        }
        capture.commitActiveDraftIfNeeded()
        voice.sceneDidEnterBackground()
        BackgroundRefresh.schedule()
        Task { @MainActor in
            await AppEnvironment.shared.engine.reconcile(reason: "background")
            WidgetSnapshotWriter.shared.refresh(store: AppEnvironment.shared.store, now: Date())
            AppEnvironment.shared.endFlush()
        }
    }

    func endFlush() {
        guard flushTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(flushTaskID)
        flushTaskID = .invalid
    }
}
