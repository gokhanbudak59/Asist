// API: App/Notifications/ReminderEngine.swift — WP5 (04 §3.6.5, §6.3, 01a §5.6).
// Plans (NagPlanner) and applies (NotificationScheduler) the notification set; handles notification actions.
import Foundation
import Observation
import UserNotifications
import AsistCore

@MainActor
@Observable
final class ReminderEngine {
    struct Report: Equatable {
        var at: Date
        var reason: String
        var authorized: Bool
        var timeSensitiveAllowed: Bool
        var planned: Int
        var dropped: Int
        var rateLimited: Int
        var itemBudget: Int
        var badge: Int
        var added: Int
    }

    /// Work items of the serialized chain (value payloads only — nothing non-Sendable crosses into the Task).
    private enum Job {
        case reconcile(String)
        case rebuild(String)
    }

    private(set) var lastReport: Report? = nil
    @ObservationIgnored private var tail: Task<Void, Never>? = nil
    @ObservationIgnored private var debounce: Task<Void, Never>? = nil
    /// Reasons collected while a debounced request waits (diagnostics only).
    @ObservationIgnored private var pendingReasons: [String] = []

    private let store: DataStore
    private let scheduler: NotificationScheduler
    private let signing: SigningMonitor

    /// Meta (lastReconcile*) is written at most every 15 minutes unless the counts change (05a #5: idle reconciles
    /// must not rewrite the data file every time).
    private static let metaRefreshInterval: TimeInterval = 15 * 60

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, scheduler: NotificationScheduler, signing: SigningMonitor) {
        self.store = store
        self.scheduler = scheduler
        self.signing = signing
    }

    // MARK: - Reconcile

    /// Serialized (task chain, 01a §5.6). Each caller awaits its own run, so a caller that awaits `reconcile`
    /// knows the plan that includes its mutation has been applied (D34).
    func reconcile(reason: String) async {
        await enqueue(.reconcile(reason))
    }

    /// Fire-and-forget, debounced 300 ms (collapses bursts from **foreground** UI edits only; D34).
    func requestReconcile(reason: String) {
        if !pendingReasons.contains(reason) && pendingReasons.count < 8 {
            pendingReasons.append(reason)
        }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self = self else { return }
            let joined = self.pendingReasons.isEmpty ? reason : self.pendingReasons.joined(separator: "+")
            self.pendingReasons = []
            self.debounce = nil
            await self.reconcile(reason: joined)
        }
    }

    /// scheduler.removeAllManaged() then reconcile (after re-sign / import / "Planı yeniden kur").
    func rebuildAll(reason: String) async {
        await enqueue(.rebuild(reason))
    }

    private func enqueue(_ job: Job) async {
        let previous = tail
        let run = Task { @MainActor [weak self] in
            await previous?.value
            guard let self = self else { return }
            await self.perform(job)
        }
        tail = run
        await run.value
    }

    private func perform(_ job: Job) async {
        switch job {
        case .reconcile(let reason):
            await reconcileOnce(reason: reason)
        case .rebuild(let reason):
            // Never wipe pending requests while the data file is unreadable (nothing could re-plan them).
            guard store.isLoaded else {
                AsistLog.info("Yeniden kurma atlandı (\(reason)): veri henüz okunamadı", .notif)
                return
            }
            await scheduler.removeAllManaged()
            await reconcileOnce(reason: "rebuild." + reason)
        }
    }

    /// 04 §3.6.5 steps 0–7. Every await point re-reads `store` afterwards (no stale copies across awaits).
    private func reconcileOnce(reason: String) async {
        // 0: never plan from an unloaded store (device locked since boot) — pending requests stay untouched.
        guard store.isLoaded else {
            AsistLog.info("reconcile(\(reason)) atlandı: veri henüz okunamadı", .notif)
            return
        }
        let calendar = AppTime.calendar
        let center = UNUserNotificationCenter.current()

        // 1: permission + time-sensitive availability (05b B7).
        let ns = await center.notificationSettings()
        let authorized = ReminderEngine.isAuthorized(ns.authorizationStatus)
        let allowTimeSensitive = ns.timeSensitiveSetting == .enabled

        // 2: roll recurring items forward, auto-close finished events (D27, D31).
        // DEVIATION(04 §3.6.5 step 1): runs also when notifications are not authorized — this is data
        // maintenance the Today screen depends on, independent of permission.
        guard store.isLoaded else { return }
        let now = Date()
        store.rollOverRecurring(now: now, calendar: calendar)
        store.closeFinishedEvents(now: now, calendar: calendar)

        guard authorized else {
            let report = Report(at: now, reason: reason, authorized: false, timeSensitiveAllowed: allowTimeSensitive,
                                planned: 0, dropped: 0, rateLimited: 0, itemBudget: 0, badge: 0, added: 0)
            lastReport = report
            AsistLog.info("reconcile \(reason): bildirim izni yok, planlama yapılmadı", .notif)
            return
        }

        // 3: plan. Pending one-shot dates let the planner keep nags the rate limiter already shifted.
        let pendingDates = await scheduler.pendingOneShotDates()
        guard store.isLoaded else { return }
        var input = makeInput(now: now, allowTimeSensitive: allowTimeSensitive)
        input.pendingNagDates = pendingDates
        let plan = NagPlanner.plan(input)

        // 4: diff-apply (near-due one-shots of open items and reserved notifications survive the planner margins).
        let added = await scheduler.apply(plan.notifications, now: now, calendar: calendar,
                                          protectedItemIDs: nearDueProtectedItemIDs(now: now))

        // 5: delivered cleanup (store re-read after the await).
        await scheduler.cleanupDelivered(openItemIDs: openItemIDs(),
                                         lastOccurrenceDone: lastOccurrenceDoneByItem(now: now))

        // 6: badge.
        do {
            try await center.setBadgeCount(plan.badgeNow)
        } catch {
            AsistLog.error("Rozet ayarlanamadı: \(error.localizedDescription)", .notif)
        }

        // 7: report + meta.
        let report = Report(at: now, reason: reason, authorized: true, timeSensitiveAllowed: allowTimeSensitive,
                            planned: plan.notifications.count, dropped: plan.droppedCount,
                            rateLimited: plan.rateLimitedCount, itemBudget: plan.itemBudget,
                            badge: plan.badgeNow, added: added)
        lastReport = report
        writeMeta(report)
        let tsText = report.timeSensitiveAllowed ? "evet" : "hayır"
        let counts = "planlanan \(report.planned), düşen \(report.dropped), hız sınırı \(report.rateLimited)"
        let effects = "eklenen \(report.added), rozet \(report.badge), zamana duyarlı \(tsText)"
        AsistLog.info("reconcile \(reason): \(counts), \(effects)", .notif)
    }

    private func writeMeta(_ report: Report) {
        guard store.isLoaded else { return }
        let meta = store.meta
        var stale = true
        if let last = meta.lastReconcileAt {
            stale = report.at.timeIntervalSince(last) >= ReminderEngine.metaRefreshInterval || report.at < last
        }
        let countsChanged = meta.lastPlannedCount != report.planned || meta.lastDroppedCount != report.dropped
        guard stale || countsChanged else { return }
        let at = report.at
        let reason = report.reason
        let planned = report.planned
        let dropped = report.dropped
        store.updateMeta { m in
            m.lastReconcileAt = at
            m.lastReconcileReason = reason
            m.lastPlannedCount = planned
            m.lastDroppedCount = dropped
        }
    }

    private func openItemIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        for item in store.items where item.isNotifiable {
            ids.insert(item.id)
        }
        return ids
    }

    /// Items whose pending one-shots firing within NotificationStaleness.nearDueProtection the diff-apply keeps.
    private func nearDueProtectedItemIDs(now: Date) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in store.items where NotificationStaleness.protectsNearDue(item, now: now) {
            ids.insert(item.id)
        }
        return ids
    }

    /// Open recurring item → date of its last completed occurrence (future-dated entries from a clock change are
    /// skipped). Delivered notifications not newer than it are stale and get removed.
    private func lastOccurrenceDoneByItem(now: Date) -> [UUID: Date] {
        let latestAllowed = now.addingTimeInterval(NotificationStaleness.futureSkew)
        var map: [UUID: Date] = [:]
        for item in store.items where item.isNotifiable {
            if let done = NotificationStaleness.lastOccurrenceDone(of: item), done <= latestAllowed {
                map[item.id] = done
            }
        }
        return map
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Actions (04 §6.3 — ordering is normative)

    /// §6.3: rollOver → action mutation → immediate replacement of this item's pending requests → awaits a full
    /// reconcile → returns. The caller calls completionHandler() after this returns.
    func handle(_ event: NotificationEvent) async {
        let calendar = AppTime.calendar
        let now = Date()
        let action = event.actionID
        let itemText = event.itemID?.uuidString ?? "-"
        let kindText = event.kind.isEmpty ? "-" : event.kind

        // 1: data must be readable; otherwise the action is lost but nothing is destroyed.
        if !store.isLoaded { store.load() }
        guard store.isLoaded else {
            AsistLog.error("Eylem kayboldu (veri okunamıyor): \(action) öğe=\(itemText) tür=\(kindText)", .notif)
            return
        }

        // 2: an action on a carrier-delivered occurrence acts on that occurrence.
        store.rollOverRecurring(now: now, calendar: calendar)

        // 3: a pre-alert can never snooze / re-anchor the item (05a #13).
        let isPreAlert = event.kind == PlannedNotification.Kind.preAlert.rawValue
        if isPreAlert && ReminderEngine.isRescheduleAction(action) {
            AsistLog.error("Ön uyarıda erteleme eylemi yok sayıldı: \(action) öğe=\(itemText)", .notif)
            await reconcile(reason: "action")
            return
        }

        // 4: mutation.
        let changedItemID = await applyAction(event, now: now, calendar: calendar)

        // 5: immediate replacement before completion (05b B1).
        if let id = changedItemID {
            await scheduler.removeAll(for: id)
            if let item = store.item(id), item.isNotifiable {
                let immediateNow = Date()
                let allowTS = lastReport?.timeSensitiveAllowed ?? false
                let input = makeInput(now: immediateNow, allowTimeSensitive: allowTS)
                let immediate = NagPlanner.immediateRequests(for: item, input: input, limit: 2)
                let count = await scheduler.add(immediate, now: immediateNow, calendar: calendar)
                AsistLog.info("Anlık yenileme: öğe=\(id.uuidString) eklenen \(count)", .notif)
            }
        }

        // 6: full plan (badges, sentinels, other items).
        await reconcile(reason: "action")
    }

    /// Step 4. Returns the id of the item whose persisted state changed (nil = nothing persisted for an item).
    private func applyAction(_ event: NotificationEvent, now: Date, calendar: Calendar) async -> UUID? {
        let action = event.actionID
        let itemText = event.itemID?.uuidString ?? "-"
        let kindText = event.kind.isEmpty ? "-" : event.kind
        let settings = store.settings

        // DEVIATION(04 §6.3): an action from a notification of a recurring occurrence that the user has already
        // completed (e.g. in the app, after this nag was delivered) must not complete / snooze the *next*
        // occurrence. Nothing is mutated; returning the id lets step 5 clear the stale delivered notification and
        // re-add this item's pending requests.
        if ReminderEngine.isOccurrenceAction(action), let id = event.itemID, let item = store.item(id),
           NotificationStaleness.isCompletedOccurrence(item, deliveredAt: event.deliveredAt, now: now) {
            AsistLog.info("Bayat bildirim eylemi yok sayıldı: \(action) öğe=\(id.uuidString) (oluşum zaten tamamlanmış)", .notif)
            logAction(action, itemText, kindText, found: true, persisted: false)
            return id
        }

        switch action {
        case NotificationActionID.done, NotificationActionID.followUpReceived:
            guard let id = event.itemID else {
                logAction(action, itemText, kindText, found: false, persisted: false)
                return nil
            }
            if let result = store.markDone(id, at: now) {
                switch result.0 {
                case .completed:
                    AsistLog.info("Tamamlandı: öğe=\(id.uuidString)", .notif)
                case .nextOccurrence:
                    AsistLog.info("Tekrarlayan öğe sonraki oluşuma geçti: öğe=\(id.uuidString)", .notif)
                }
                logAction(action, itemText, kindText, found: true, persisted: true)
                return id
            }
            logAction(action, itemText, kindText, found: store.item(id) != nil, persisted: false)
            return nil

        case NotificationActionID.snooze10:
            let target = AsistCalendar.ceilToMinute(now.addingTimeInterval(10 * 60))
            return snooze(event, until: target, now: now)

        case NotificationActionID.snooze60:
            let target = AsistCalendar.ceilToMinute(now.addingTimeInterval(60 * 60))
            return snooze(event, until: target, now: now)

        case NotificationActionID.tomorrow:
            let target = NagPlanner.tomorrowMorning(after: now, settings: settings, calendar: calendar)
            return snooze(event, until: target, now: now)

        case NotificationActionID.followUpTomorrow:
            let target = NagPlanner.followUpAsk(after: now, workdays: 1, settings: settings, calendar: calendar)
            return snooze(event, until: target, now: now)

        case NotificationActionID.followUpTwoDays:
            let target = NagPlanner.followUpAsk(after: now, workdays: 2, settings: settings, calendar: calendar)
            return snooze(event, until: target, now: now)

        case NotificationActionID.followUpMessage:
            let router = AppEnvironment.shared.router
            if let id = event.itemID, let item = store.item(id), item.isOpen {
                router.request(.followUpMessage(id))
                logAction(action, itemText, kindText, found: true, persisted: false)
            } else {
                router.request(.today)
                logAction(action, itemText, kindText, found: false, persisted: false)
            }
            return nil

        case NotificationActionID.briefingRead:
            AppEnvironment.shared.router.request(.readAgenda)
            logAction(action, itemText, kindText, found: true, persisted: false)
            return nil

        case NotificationActionID.endOfDayMove:
            // DEVIATION(04 §6 ASIST_EOD_MOVE): an end-of-day notification from an earlier day (still in
            // Notification Center) must not move *today's* tasks — the move is computed from the tap time. Nothing
            // is moved; the review screen is left pending and a passive notice says so.
            if NotificationStaleness.isStaleEndOfDay(deliveredAt: event.deliveredAt, now: now, calendar: calendar) {
                AsistLog.info("Gün sonu taşıma yok sayıldı: bildirim önceki bir güne ait", .notif)
                AppEnvironment.shared.router.request(.endOfDay)
                await scheduler.addUnmanaged(id: ReminderEngine.staleEndOfDayFeedbackID,
                                             text: ReminderEngine.staleEndOfDayFeedbackText, after: 2,
                                             categoryID: NotificationCategoryID.system, interruption: .passive,
                                             itemID: nil)
                logAction(action, itemText, kindText, found: true, persisted: false)
                return nil
            }
            await moveEndOfDay(now: now)
            logAction(action, itemText, kindText, found: true, persisted: true)
            return nil

        case NotificationActionID.endOfDayReview:
            AppEnvironment.shared.router.request(.endOfDay)
            logAction(action, itemText, kindText, found: true, persisted: false)
            return nil

        case UNNotificationDismissActionIdentifier:
            // "Temizle" = seen, not done: the chain continues.
            if let id = event.itemID {
                let found = store.item(id) != nil
                if found { store.recordDismiss(id, at: now) }
                logAction(action, itemText, kindText, found: found, persisted: found)
            } else {
                logAction(action, itemText, kindText, found: false, persisted: false)
            }
            return nil

        case UNNotificationDefaultActionIdentifier:
            let pendingAction = bodyTapDestination(event)
            AppEnvironment.shared.router.request(pendingAction)
            logAction(action, itemText, kindText, found: event.itemID != nil, persisted: false)
            return nil

        default:
            AsistLog.error("Bilinmeyen bildirim eylemi: \(action) öğe=\(itemText)", .notif)
            return nil
        }
    }

    private func snooze(_ event: NotificationEvent, until target: Date, now: Date) -> UUID? {
        let itemText = event.itemID?.uuidString ?? "-"
        let kindText = event.kind.isEmpty ? "-" : event.kind
        guard let id = event.itemID else {
            logAction(event.actionID, itemText, kindText, found: false, persisted: false)
            return nil
        }
        if store.snooze(id, until: target, at: now) != nil {
            logAction(event.actionID, itemText, kindText, found: true, persisted: true)
            return id
        }
        logAction(event.actionID, itemText, kindText, found: store.item(id) != nil, persisted: false)
        return nil
    }

    private func moveEndOfDay(now: Date) async {
        guard let token = store.moveOpenItemsToTomorrow(now: now) else {
            AsistLog.info("Gün sonu taşıma: taşınacak iş yok ya da kaydedilemedi", .notif)
            return
        }
        let count = token.before.count
        AsistLog.info("Gün sonu taşıma: \(count) iş taşındı", .notif)
        guard count > 0 else { return }
        let text = NotificationCopy.movedFeedbackContent(count: count)
        await scheduler.addUnmanaged(id: NotificationID.movedFeedback, text: text, after: 2,
                                     categoryID: NotificationCategoryID.system, interruption: .passive,
                                     itemID: nil)
    }

    /// 04 §6.3 body-tap table.
    private func bodyTapDestination(_ event: NotificationEvent) -> PendingAction {
        let id = event.notificationID
        if id.hasPrefix(NotificationID.briefing(dayKey: "")) {
            return store.settings.briefingTapSpeaks ? PendingAction.readAgenda : PendingAction.today
        }
        if id.hasPrefix(NotificationID.endOfDay(dayKey: "")) {
            return PendingAction.endOfDay
        }
        if id == NotificationID.backup {
            return PendingAction.dataSettings
        }
        if id == ReminderEngine.staleEndOfDayFeedbackID {
            return PendingAction.endOfDay
        }
        if id == NotificationID.movedFeedback || id == NotificationID.horizonSentinel
            || id.hasPrefix(NotificationID.signing(minuteKey: "")) {
            return PendingAction.today
        }
        if let itemID = event.itemID, let item = store.item(itemID), item.status != .deleted {
            return PendingAction.openItem(itemID)
        }
        return PendingAction.today
    }

    /// Actions that complete or re-anchor the item's current occurrence (subject to the stale-occurrence check).
    private static func isOccurrenceAction(_ action: String) -> Bool {
        return action == NotificationActionID.done
            || action == NotificationActionID.followUpReceived
            || isRescheduleAction(action)
    }

    /// Passive notice after a stale end-of-day action (unmanaged id; body tap opens the end-of-day review).
    private static let staleEndOfDayFeedbackID = NotificationID.unmanagedPrefix + "eodstale"
    private static var staleEndOfDayFeedbackText: NotificationText {
        NotificationText(title: "Gün sonu", subtitle: "",
                         body: "Bu gün sonu bildirimi önceki bir güne aitti; hiçbir iş taşınmadı. Gözden geçirmek için dokun.")
    }

    private static func isRescheduleAction(_ action: String) -> Bool {
        return action == NotificationActionID.snooze10
            || action == NotificationActionID.snooze60
            || action == NotificationActionID.tomorrow
            || action == NotificationActionID.followUpTomorrow
            || action == NotificationActionID.followUpTwoDays
    }

    private func logAction(_ action: String, _ itemText: String, _ kindText: String, found: Bool, persisted: Bool) {
        let foundText = found ? "evet" : "hayır"
        let persistedText = persisted ? "evet" : "hayır"
        AsistLog.info("Eylem \(action) öğe=\(itemText) tür=\(kindText) bulundu=\(foundText) kaydedildi=\(persistedText)", .notif)
    }

    // MARK: - Input / test

    /// PlanInput for `now` from the current store/signing state (also used by the immediate path).
    func makeInput(now: Date, allowTimeSensitive: Bool) -> PlanInput {
        PlanInput(items: store.items, projects: store.projects, places: store.places, settings: store.settings,
                  now: now, calendar: AppTime.calendar, signingExpiry: signing.expiryDate,
                  locationSlotsUsed: 0, allowTimeSensitive: allowTimeSensitive)
    }

    /// "Test bildirimi (10 sn)": asist.x.test, category ASIST_ITEM, itemID nil.
    func sendTestNotification() async {
        await sendTestNotification(after: 10)
    }

    /// Same with a custom delay (onboarding / guide E use 30 s so the phone can be locked first; WP11 request).
    func sendTestNotification(after seconds: TimeInterval) async {
        let delay: TimeInterval = seconds.isFinite ? min(3600, max(2, seconds)) : 10
        await scheduler.addUnmanaged(id: NotificationID.test, text: NotificationCopy.testContent(), after: delay,
                                     categoryID: NotificationCategoryID.item, interruption: .active, itemID: nil)
    }
}
