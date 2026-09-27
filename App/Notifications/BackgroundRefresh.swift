// FILE: App/Notifications/BackgroundRefresh.swift
import BackgroundTasks
import Foundation
import AsistCore

/// Calls setTaskCompleted exactly once (expiration and normal completion may race, 05a #16).
final class BGCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(_ success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
    }
}

enum BackgroundRefresh {
    /// MUST equal Info.plist BGTaskSchedulerPermittedIdentifiers[0] (D9).
    static let taskID = "com.gokhanbudak.asist.refresh"

    /// Exactly once, from AppDelegate.didFinishLaunching. Never also use SwiftUI .backgroundTask.
    static func register() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task)
        }
        if !ok { AsistLog.error("BGTask kaydı başarısız (Info.plist kimliği?)", .notif) }
    }

    static func schedule(after seconds: TimeInterval = 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AsistLog.info("BGTask submit: \(error.localizedDescription)", .notif)
        }
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let once = BGCompletion(task)
        let work = Task { @MainActor in
            let env = AppEnvironment.shared
            env.bootstrap()
            if !env.store.isLoaded { env.store.load() }
            env.store.updateMeta { meta in
                meta.lastBackgroundRefreshAt = Date()
            }
            // A re-sign by the Sideloadly daemon is detected here too (new profile → rebuild all requests).
            if env.signing.refresh(store: env.store) {
                await env.engine.rebuildAll(reason: "bgRefresh.resigned")
            } else {
                await env.engine.reconcile(reason: "bgRefresh")
            }
            once.finish(true)
        }
        task.expirationHandler = {
            work.cancel()
            once.finish(false)
        }
    }
}
