# 05a — Adversarial review of 04_architecture_contract.md (compile, platform, runtime, data safety)

| Field | Value |
|---|---|
| Reviewed | `04_architecture_contract.md` (4 790 lines, all `// FILE:` and `// API:` blocks, §0–§10), cross-checked against `01a_platform_notifications.md`, `01b_platform_voice_intents.md`, `01c_platform_build_deploy.md`, `06_claude_api_facts.md` |
| Date | 2026-09-27 |
| Method | Line-by-line desk compile (Swift 5 mode, `SWIFT_STRICT_CONCURRENCY=minimal`, Xcode 26 SDK, deployment 17.0; Linux Swift 6.3 for AsistCore), SDK signatures re-checked against Apple DocC JSON (`developer.apple.com/tutorials/data/documentation/...json`), swift-foundation / swift-corelibs-foundation sources, SE-0360 text |
| Severity scale | **BLOCKER** = must change the contract before WPs start (core promise or first CI build breaks). **MAJOR** = must be fixed before the first device install (silent functional failure, crash, or data loss in a realistic scenario). **MINOR** = hardening, warnings, low-probability edge cases |

## 0. Verdict

- **Compile risk of the exact (`// FILE:`) code is low.** I found no hard compile error in §3.2–§3.8 / §5.4 / §7.3. Every doubtful SDK signature I could check matches the current SDK (list in §2). The remaining compile items are warnings or fragility (#14, #15, #34).
- **The real risk is behavioural**: several headless/background paths (Siri/Back Tap capture, backgrounding, background launches) end before the notification plan is applied, the nag algorithm silently stops nagging when the app is not reopened, and a few store semantics can report "saved" when nothing was persisted.
- Totals: **2 BLOCKER (#1–#2), 11 MAJOR (#3–#13), 21 MINOR (#14–#34).**

---

## 1. Findings

### 1 — BLOCKER — Headless capture returns before its notifications exist (Siri / Back Tap reminder may never fire)

- **Location:** §3.6.8 `CaptureService.captureHeadless` (l. 3564–3567); §3.7 `KaydetIntent.perform` (l. 3900–3909); §3.6.2 `AppEnvironment.dataDidChange` (l. 2819–2834); §3.6.5 `ReminderEngine.requestReconcile` "fire-and-forget, debounced 300 ms" (l. 3301–3302).
- **Problem:** `captureHeadless → store.add → onChange(.items) → dataDidChange → engine.requestReconcile` schedules the reconcile on a 300 ms debounced `Task`. `perform()` then returns the dialog immediately. The intent runs in a background-launched app process; once `perform` returns, iOS may suspend the process before the debounced task runs or before its `await center.add(...)` calls finish. The item is persisted but **no `UNNotificationRequest` exists** until the next app activity. This is the primary "app closed" capture path (Back Tap → Dikte → Asist'e Kaydet, "Hey Siri, Asist'e kaydet"). Notification actions (`handle`) and BG refresh already await `reconcile`; intents do not.
- **Fix (contract text):**
  - §3.6.8 `captureHeadless`: add to the doc comment: *"After the store mutation it MUST `await AppEnvironment.shared.engine.reconcile(reason: "intent")` (not `requestReconcile`) and call `widgets.refresh(...)` before returning the sentence."*
  - §4.1 add rule 12: *"Every entry point after which the process may be suspended — App Intent `perform`, notification action `handle`, BG task, `sceneDidEnterBackground` — awaits `engine.reconcile(reason:)` after its last mutation. `requestReconcile` is only for foreground UI bursts."*
  - §9 add: *"42b. No headless path relies on `requestReconcile`."*

### 2 — BLOCKER — "Nag until done" silently ends when the app is not reopened

- **Location:** §6.4 `plan(input)` step 1, bullets "Future elements … first `P.maxPendingFollowUps` follow-ups" and "Long-tail: item overdue at `now`" (l. 4520, 4523); §6.4 profile defaults in §3.2.5 (`maxPendingFollowUps` 5 / 8 / 10); `NotificationCopy.itemContent` "`isLastOfDay` → … yarın sabah brifingde tekrar göreceksin" (l. 2230).
- **Problem:** A plan keeps only the first `maxPendingFollowUps` follow-ups, and the daily long-tail is added **only for items already overdue at the time of the plan**. If the last reconcile ran before the anchor (the normal case: the item is created, then the user never reopens the app), the pending set ends after the capped follow-ups and **nothing is scheduled afterwards**:
  - Israrcı, A = Tue 15:00 (planned Sunday): last nag Tue 22:00, then silence.
  - Bırakmaz (critical): 10 follow-ups ≈ 2 hours, then silence.
  - Nazik: last nag Thu 08:30, then silence.
  The briefing only covers users who read it. This is the user's stated failure mode ("alarm çaldığında kapatıyorum, sonra unutuyorum"), and the BG refresh the design relies on here is explicitly "a bonus, never relied upon" (01a §4.4). The copy "yarın sabah … tekrar göreceksin" becomes false.
- **Fix (replace the two bullets in §6.4 step 1):**
  - *Long-tail (non-recurring, anchor A):* rule `R = .daily(hour:minute:)` of `S.workStart` (`.takip` → `S.followUpAskTime`). Let `F` = the first fire of R strictly after `now`. It is a **candidate whenever `F > A`**, not only when the item is overdue. A repeating trigger can then never fire before the anchor. Keep at most 10 (priority desc, oldest anchor) — unchanged.
  - *Day-tail:* after the first `P.maxPendingFollowUps` follow-ups, also keep the **first chain element of each of the next 3 calendar days** after the last kept element (tier 3, dropped first under budget pressure, counted in `droppedCount` → sentinel). This covers far-future anchors until a later reconcile can add the long-tail.
  - *Copy:* if neither a long-tail nor a day-tail follows the last planned element, its body is *"Asist'i bir kez açarsan her sabah hatırlatmaya devam ederim."* and `isLastOfDay` text must not promise tomorrow.
  - Add unit tests (§6.4 required tests): "Israrcı, A = Tue 15:00, planned Sun 10:00, no further reconcile → Wed 07:30, Thu …, Fri … exist"; "A = today 15:00 planned 10:00 → long-tail present".

### 3 — MAJOR — Store mutators report success when nothing was persisted

- **Location:** §3.6.4 `DataStore` doc "While false: every mutation and save() is a logged no-op" (l. 2986–2989); `@discardableResult func add(_ item: Item) -> UndoToken` (l. 3022, **non-optional**); `save()` "On failure keeps data in memory, sets lastSaveError" (l. 3004–3007); §3.6.8 `captureHeadless`, `commit`.
- **Problem:** While `!isLoaded` (I/O error, protected data unavailable) or after a failed save (disk full), `add` still returns an `UndoToken`. `captureHeadless` then speaks "Tamam, … hatırlatacağım" and the UI shows "Kaydedildi". In a headless process that is then suspended or killed, the in-memory item is lost. The user was told it was saved.
- **Fix:**
  ```swift
  // DataStore API
  /// false while !isLoaded or while the last save failed (data only in memory).
  var canPersist: Bool { get }
  @discardableResult func add(_ item: Item) -> UndoToken?   // nil = NOT persisted (nothing changed in memory either when !isLoaded)
  ```
  `captureHeadless`:
  ```swift
  if !store.isLoaded { store.load() }
  guard store.isLoaded else { return "Şu an kayıtlarına erişemiyorum. Telefonun kilidini açıp tekrar dener misin?" }
  guard store.add(item) != nil, store.lastSaveError == nil else { return "Kaydedemedim; telefonda yer kalmamış olabilir. Asist'i açıp kontrol et." }
  await engine.reconcile(reason: "intent")          // finding #1
  ```
  `CaptureService.commit` shows `error.save_failed` instead of "Kaydedildi" when `add` returns nil or `lastSaveError != nil`. Apply the same rule to `markDone`/`snooze`/`delete`, which already return optionals: document that `nil` also means "not persisted".

### 4 — MAJOR — Background reconciles delete the signing-expiry warnings

- **Location:** §3.6.2 `bootstrap()` (l. 2790–2805) never calls `signing.refresh`; `sceneDidBecomeActive` does (l. 2840); §3.6.5 reconcile step 5 `signingExpiry: signing.expiryDate` (l. 3297); diff-apply removes managed ids that are not desired (§3.6.5 l. 3241–3243).
- **Problem:** In a process that was launched in the background (notification action, Siri intent, BG refresh, control), `SigningMonitor.expiryDate` is still nil. `NagPlanner` then plans no `asist.sign.*`, and `NotificationScheduler.apply` **removes the pending warnings**. Realistic scenario: the user's last interaction before expiry is a "✓ Yaptım" on the lock screen → no 48 h / 24 h re-sign warning → the app expires unannounced (7-day free profile).
- **Fix:** split `SigningMonitor` into
  ```swift
  func reload()                         // reads embedded.mobileprovision, sets profile/expiryDate/isEstimated/appGroupAvailable; no store writes
  func refresh(store: DataStore) -> Bool // reload() + stamp compare/persist (unchanged semantics)
  ```
  Call `signing.reload()` in `bootstrap()` before the first `requestReconcile`. Contract rule: *"reconcile never runs with an unloaded SigningMonitor."*

### 5 — MAJOR — Reconcile feedback loop through unconditional `onChange`

- **Location:** §3.6.4 `recordLocationFired` "locationFiredAt if nil; history .locationFired; onChange(.items)" (l. 3037); §3.6.5 reconcile step 2 (l. 3294) and step 7 `cleanupDelivered` "keep only the newest delivered notification per open item thread" (l. 3246); §3.6.2 `dataDidChange` → `requestReconcile`.
- **Problem:** A delivered `asist.loc.<id>` stays in Notification Center (it is the newest notification of its thread and is kept by cleanup). Every reconcile calls `recordLocationFired` for it again. If the implementation emits `onChange(.items)` unconditionally (the doc is ambiguous), each reconcile schedules another reconcile 300 ms later. The result is an endless loop: CPU/battery drain, repeated file writes, notification churn. The same hazard applies to any mutator called from reconcile.
- **Fix (normative sentence in §3.6.4):** *"Every mutator compares before/after and emits `onChange` and `save()` only when `data` actually changed. `recordLocationFired` is a no-op (no save, no onChange) when the item is missing or closed, or when `locationFiredAt != nil`. `rollOverRecurring` already returns `false` when nothing changed."* Add a unit/integration check: two consecutive reconciles with no input change perform 0 saves.

### 6 — MAJOR — A deferred load does not re-apply settings side effects (parser without projects, wrong categories/voice/widget)

- **Location:** §3.6.2 `bootstrap()` calls `store.load()` **before** assigning `store.onChange` (l. 2793–2796); the retry paths `observe(... protectedData ...)` (l. 2811) and `sceneDidBecomeActive` (l. 2838) only call `load()` + reconcile.
- **Problem:** When the first `load()` fails (the app was launched in the background before first unlock and the process survived) and a later retry succeeds, nothing re-runs `NotificationCategories.register`, `voice.apply`, `capture.invalidateParser()` or `widgets.refresh`. If `CaptureService` built its cached parser meanwhile, it has **no projects, places or aliases**. Project detection then fails, and the user's volume-trigger, TTS and lock-screen settings are ignored until the next settings change or relaunch.
- **Fix:** §3.6.4 `load()` doc: *"On the transition `isLoaded false → true`, `load()` calls `onChange?(.all)`."* In `bootstrap()`, assign `store.onChange` **before** `store.load()`. Keep the explicit register/apply lines, because they are idempotent and cover the "load failed" case with defaults.

### 7 — MAJOR — Backgrounding commits the open draft, but its reconcile can be cut off by suspension

- **Location:** §3.6.2 `sceneDidEnterBackground()` (l. 2849–2853); §3.6.8 `commitActiveDraftIfNeeded` (l. 3559–3560).
- **Problem:** A typical flow: the user speaks → the card counts down → the user locks the phone. `commitActiveDraftIfNeeded` saves, and the reconcile is debounced by 300 ms. The app gets only a few seconds before suspension, and no background task is requested. The reminder confirmed at that moment may have no notification until the next launch.
- **Fix (replace the body of `sceneDidEnterBackground` in the exact file):**
  ```swift
  private var flushTaskID: UIBackgroundTaskIdentifier = .invalid

  func sceneDidEnterBackground() {
      if flushTaskID == .invalid {
          // handler type is (@MainActor @Sendable () -> Void)? in the current SDK
          flushTaskID = UIApplication.shared.beginBackgroundTask(withName: "asist.flush") {
              AppEnvironment.shared.endFlush()
          }
      }
      capture.commitActiveDraftIfNeeded()
      voice.sceneDidEnterBackground()
      BackgroundRefresh.schedule()
      Task { @MainActor in
          await AppEnvironment.shared.engine.reconcile(reason: "background")
          AppEnvironment.shared.endFlush()
      }
  }

  func endFlush() {
      guard flushTaskID != .invalid else { return }
      UIApplication.shared.endBackgroundTask(flushTaskID)
      flushTaskID = .invalid
  }
  ```
  (Do not capture a local `var` in the expiration handler: it is `@Sendable`, and mutating a captured var there is a compile error even in Swift 5 mode.)

### 8 — MAJOR — Infinite loop (main-thread hang) in the nag chain when no eligible day exists

- **Location:** §6.4 definitions `dayStart`/`nextDayStart` (l. 4491–4492), `emit` (l. 4501–4502); §3.2.9 `AppSettings.workdays` (l. 1131) decoded with `lenient` and no validation (l. 1219).
- **Problem:** For `.takip`, "non-workdays skipped". If `S.workdays` is empty, or contains only invalid values (0, 8, …) from an import, a corrupt file or a UI allowing all days off, `nextDayStart` never finds an eligible day. The same happens in `emit` (`if K == .takip && !workday(t): t = nextDayStart(t)`). The planner is called synchronously on the main actor in every reconcile, including the launch reconcile → UI freeze → watchdog kill (`0x8badf00d`) on every launch.
- **Fix:**
  - §6.4: *"`nextDayStart` searches at most 14 days ahead; if no eligible day is found it treats every day as eligible (same fallback as `AsistCalendar.addingWorkdays`)."*
  - §3.2.9 `init(from:)`:
    ```swift
    let wd = Array(Set(c.lenient([Int].self, forKey: .workdays, default: workdays).filter { (1...7).contains($0) })).sorted()
    workdays = wd.isEmpty ? [1, 2, 3, 4, 5] : wd
    ```
  - Settings UI: the last remaining workday cannot be switched off.
  - Add a test: takip + `workdays == []` terminates.

### 9 — MAJOR — Recurring reminders stop after ~3 occurrences without app activity

- **Location:** D27 (l. 57); §6.4 step 1 "Recurring: `occurrences(after: A, count: 2)`" (l. 4522).
- **Problem:** Only the current occurrence plus the k = 0 of the next 2 occurrences are pending. A daily "her gün 9'da …" reminder therefore fires on 3 days and then stops if the user does not open Asist. Free-signing re-sign through the Sideloadly daemon does **not** open the app, so this is a realistic scenario.
- **Fix:** plan `RecurrenceEngine.occurrences(... count: 7 ...)` truncated to the 14-day horizon. Occurrences ≤ now + 48 h get tier 0, others tier 3; the budget and sentinel stay unchanged. Optional v1.1: for `daily`/`weekly` rules with interval 1, use one repeating `.daily`/`.weekly` safety-net request per rule and weekday instead of one-shot occurrences (dedupe same minute, as with the long-tail).

### 10 — MAJOR — Forward-compatibility data loss when an older build runs on newer data

- **Location:** §3.1 conventions (unknown enum raw → fallback; synthesized `encode` writes only known keys) (l. 335–336); §3.2.2 enum fallbacks (e.g. `ItemStatus` unknown → `.open`, `ItemKind` unknown → `.task`); schema rule (l. 1391); 01c §3.4 (the user reinstalls "aynı IPA'yı (veya CI'daki daha yeni IPA'yı)").
- **Problem:** Lenient decoding plus synthesized re-encoding means that any field or enum value added by build N+1 is **silently rewritten or dropped on the first save by build N**. For example, a future status "archived" is decoded as `.open`, the item resurrects and starts nagging, and it is saved as "open". Reinstalling an older IPA from Windows is a realistic mistake because the weekly re-sign reuses an IPA file. The `schemaVersion` rule only covers breaking changes made on purpose.
- **Fix:**
  - `AppMeta`: add `public var writerBuild: Int = 0` (+ CodingKey + `lenient` line). `DataStore.save()` sets it to `Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0`; CI sets `CURRENT_PROJECT_VERSION = run_number`, which is monotonic.
  - `load()`: if `decoded.meta.writerBuild > currentBuild`, copy the file to `Documents/Yedekler/asist-data.yeni-surum-<writerBuild>.json` **before the first save** and set `loadIssue = .newerWriter(build:)`, which shows a red, non-dismissible banner: *"Bu veriler daha yeni bir Asist sürümüyle kaydedildi. Güncel IPA'yı yükle."*
  - Also add to the schema rule: *"never change the `.iso8601` date strategy (a fractional-seconds date fails `lenient` decoding → dueDate becomes nil)."*

### 11 — MAJOR — `AppEnvironment.shared` re-entrancy can crash at launch

- **Location:** §3.6.2 `private init()` (l. 2773–2787) constructs 13 services; `VoiceCoordinator.init()` "wires `trigger.onDoublePress → … startListening()`" (l. 3428), and `startListening` needs `capture` and `router`; `ToastCenter.performUndo` already reaches through `AppEnvironment.shared` (l. 3481).
- **Problem:** `static let shared` is initialized with `swift_once`. If **any** service initializer, or code it runs synchronously, touches `AppEnvironment.shared` (for example `VoiceCoordinator.init` resolving `AppEnvironment.shared.capture` eagerly, or `DataStore.init` logging through an env-dependent helper), the lazy initializer re-enters itself. libdispatch then traps ("dispatch_once called recursively") or deadlocks on the first launch. No rule forbids it, and WP6/WP7 implementers will be tempted.
- **Fix:** add to §3.6.2 and §9: *"No initializer invoked from `AppEnvironment.init` (DataStore, AppRouter, ToastCenter, PermissionCenter, NotificationScheduler, LocationService, SigningMonitor, WidgetSnapshotWriter, ReminderEngine, SmartModeClient, KeychainStore, CaptureService, CommandExecutor, VoiceCoordinator and the objects they create) may reference `AppEnvironment.shared`. Cross-service access happens lazily inside methods or closures executed after init."* For example: `trigger.onDoublePress = { [weak self] in Haptics.medium(); Task { @MainActor in await self?.startListening() } }`, with `startListening` reading `AppEnvironment.shared.capture` at call time.

### 12 — MAJOR — Import and restore from Files silently fail (security-scoped URLs)

- **Location:** §5.2 `DataSettingsView` "`.fileImporter(allowedContentTypes: [.json])` → preview … → Birleştir / Değiştir" (l. 4265); §3.6.4 `importPreview(_:)`/`importData(_:mode:)`.
- **Problem:** URLs returned by `.fileImporter` for iCloud Drive, "On My iPhone › Downloads", external providers and similar locations are **security-scoped**. `Data(contentsOf:)` without `startAccessingSecurityScopedResource()` fails with a permission error. As a result, restore-from-export (K19 "delete app → reinstall → import") does not work, which is the only disaster-recovery path.
- **Fix (§5.2 note, exact pattern):**
  ```swift
  .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
      guard case .success(let url) = result else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      guard let data = try? Data(contentsOf: url) else {
          toasts.show("Dosya okunamadı.")
          return
      }
      pendingImportData = data           // preview + merge/replace operate on the in-memory Data
  }
  ```
  Add `import UniformTypeIdentifiers` to the file (`.json` is `UTType.json`).

### 13 — MAJOR — Actions on a pre-alert re-anchor the item and delete the real due-time alert

- **Location:** §6.1 row `asist.i.<UUID>.pre.<minutes>` → category `ASIST_ITEM` (l. 4440); §6.3 `ASIST_SNOOZE_10/60`, `ASIST_TOMORROW` → `store.snooze` (l. 4472–4473); `Item.anchorDate` prefers `snoozedUntil` (§3.2.7).
- **Problem:** A "30 dakika sonra: Toplantı" pre-alert shows "10 dk / 1 saat / Yarın sabah". Tapping "Yarın sabah" sets `snoozedUntil = tomorrow 08:30`, so the anchor moves and **the 15:00 due-time alert and its chain are removed**. Tapping "10 dk" makes the item overdue before its due time. The user meant "remind me about the prep", not "move the meeting".
- **Fix:** add `NotificationCategoryID.preAlert = "ASIST_PRE"` with a single action `ASIST_DONE "✓ Yaptım"` (plus the default tap), and register it in `NotificationCategories.register` (same options as `item`). §6.1: pre-alerts use `ASIST_PRE`. §6.3 defensive rule: snooze or tomorrow actions from a request whose `nk == "preAlert"` are ignored (log only).

### 14 — MINOR — `TimelineProvider` completions do not match the SDK spelling

- **Location:** §3.8 `AsistTimelineProvider.getSnapshot` / `getTimeline` (l. 4052, 4060).
- **Problem:** The current SDK declares `@preconcurrency func getSnapshot(in context: Self.Context, completion: @escaping @Sendable (Self.Entry) -> Void)` and the same for `getTimeline`. The contract omits `@Sendable`. Because the requirement is `@preconcurrency`, this is only a Sendable-mismatch warning, but the implementation should match exactly.
- **Fix:** `completion: @escaping @Sendable (AsistEntry) -> Void` and `completion: @escaping @Sendable (Timeline<AsistEntry>) -> Void`.

### 15 — MINOR — Missing explicit imports (fragile, compile today)

- **Location:** §3.7 `KaydetIntent.swift` imports only `AppIntents` but passes `.siri` (`CaptureSource`) (l. 3881, 3907); §3.6.5 `BackgroundRefresh.swift` mutates `AppMeta` through `updateMeta` without `import AsistCore` (l. 3192, 3221); §5.2 `DataSettingsView` uses `.json` (`UTType`).
- **Problem:** These compile today because member lookup through a known type does not require the defining module to be imported in the file. They break as soon as anyone enables `MemberImportVisibility` (SE-0444) or refactors the call site to name the type.
- **Fix:** add `import AsistCore` to both files, and `import UniformTypeIdentifiers` to `DataSettingsView.swift`.

### 16 — MINOR — `BackgroundRefresh` can call `setTaskCompleted` twice

- **Location:** §3.6.5 `BackgroundRefresh.handle` (l. 3217–3229).
- **Problem:** After expiration, `work.cancel()` does not stop `reconcile`, which is not cancellation-aware. It may still reach `task.setTaskCompleted(success: true)` after the expiration handler already called `setTaskCompleted(success: false)`.
- **Fix:**
  ```swift
  final class BGCompletion: @unchecked Sendable {
      private let lock = NSLock(); private var done = false; private let task: BGTask
      init(_ task: BGTask) { self.task = task }
      func finish(_ ok: Bool) {
          lock.lock(); defer { lock.unlock() }
          guard !done else { return }
          done = true
          task.setTaskCompleted(success: ok)
      }
  }
  ```
  `handle` creates `let once = BGCompletion(task)`; the work Task calls `once.finish(true)` and the expiration handler calls `work.cancel(); once.finish(false)`.

### 17 — MINOR — `SystemVolumeAnchor` lost the sizing and accessibility modifiers from 01b

- **Location:** §5.1 tree "`.background { SystemVolumeAnchor(trigger: voice.trigger) 1×1 pt }`" (l. 4204); 01b §4.11 had `.frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)`.
- **Problem:** A `UIViewRepresentable` in `.background` is sized to the whole RootView. That gives a full-screen `MPVolumeView` at alpha 0.01, which VoiceOver can focus.
- **Fix:** make the modifiers normative: `SystemVolumeAnchor(trigger: voice.trigger).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)`.

### 18 — MINOR — The listening overlay is invisible while a sheet or cover is presented

- **Location:** §5.1 "`.overlay: ListeningOverlay` … ZStack overlay, not a cover" (l. 4200); volume ×2 and the `.listen` pending action can fire while `router.sheet != nil` or while onboarding is shown.
- **Problem:** `.overlay` on RootView sits **below** any UIKit-presented sheet or `fullScreenCover`. The mic then records with no visible UI and no "Bitti"/"Vazgeç" controls.
- **Fix:** at the start of `VoiceCoordinator.startListening`:
  ```swift
  if router.sheet != nil {
      router.dismissSheet()
      try? await Task.sleep(nanoseconds: 400_000_000)
  }
  ```
  The sheet's `onDismiss` commits the draft. Keep the trigger disarmed while `router.showOnboarding`.

### 19 — MINOR — The settings edit pattern overwrites concurrent changes

- **Location:** §5.2 "settings edit pattern … `store.updateSettings { $0 = new }`" (l. 4259).
- **Problem:** `TabView` and `NavigationStack` keep settings screens alive. If `activeProjectID` (set from Projeler) or `onboardingCompleted` changes elsewhere, the stale `@State s` copy later writes the old value back.
- **Fix:** add to the pattern: `.onChange(of: store.settings) { _, latest in if latest != s { s = latest } }`. This does not ping-pong, because the write-back is guarded by `new != store.settings`.

### 20 — MINOR — Decoded or imported numeric settings are not range-checked (possible traps)

- **Location:** §3.2.9 `AppSettings.init(from:)` (l. 1203–1257); §3.2.8 `Place.init(from:)`; §3.2.4 `Recurrence`.
- **Problem:** `silenceSeconds` and `autoSaveSeconds` feed `Task.sleep(nanoseconds: UInt64(x * 1e9))`, where `UInt64` of a negative value **traps**. `backupReminderWeekday` outside 1…7 feeds `DateComponents(weekday:)`. `latitude`/`longitude` outside the valid range feed `CLCircularRegion`. A bad import is enough.
- **Fix:** clamp in `init(from:)`:
  - `silenceSeconds = min(5, max(0.8, …))`
  - `autoSaveSeconds ∈ {0, 3, 4, 6}`, else 4
  - `waitingDefaultWorkdays = min(10, max(1, …))`
  - `backupReminderWeekday = min(7, max(1, …))`
  - `Recurrence.monthDay ∈ {-1} ∪ 1…31`, `month ∈ 1…12`, `weekdays` filtered to 1…7
  - `Place`: if `CLLocationCoordinate2DIsValid` fails, skip the geofence in `LocationService` (AsistCore: `abs(lat) ≤ 90 && abs(lon) ≤ 180`, else 0/0 plus a flag)
  - Also clamp every `UInt64(seconds * 1e9)` call site with `max(0, …)`.

### 21 — MINOR — `previousFile` handling can fail or preserve the wrong version

- **Location:** §3.6.4 `save()` "before writing copies the current file to previousFile" (l. 3004–3006).
- **Problem:**
  1. `FileManager.copyItem(at:to:)` throws if the destination exists, so a naive implementation never updates `prev`.
  2. After `restoredFromPrevious`, the first save copies the **corrupt** main file over the only good `prev`.
- **Fix:** *"copy via `Data(contentsOf: dataFile)` + `write(to: previousFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])`, and only if the main file decoded successfully in this session (`mainFileVerified` flag); never copy an unverified file over `prev`."*

### 22 — MINOR — Lenient top-level decoding hides structural corruption

- **Location:** §3.2.10 `AppData.init(from:)` (l. 1364–1372); §3.2.1 `LossyDecodableArray`.
- **Problem:** If `"items"` exists but is not an array, `lenientOptional` returns nil and the store continues with `items = []`. Dropped array elements vanish the same way. The decode "succeeds", so `load()` takes no corrupt copy, and the next save persists the loss. Daily backups roll the damage in within 7 days.
- **Fix:** in `DataStore.load()`, after a successful decode, parse the same bytes with `JSONSerialization` and compare the raw element counts of `items`, `projects` and `places` with the decoded counts (and check the array type). On mismatch, write `corruptCopyURL` **before** the first save and set `loadIssue = .partialRecovery(dropped: n)` (banner "n kayıt okunamadı; ham dosya saklandı").

### 23 — MINOR — Items beyond the 14-day horizon have no safety net

- **Location:** §6.4 step 2 "Beyond 14 d: not planned (not 'dropped')" (l. 4524).
- **Problem:** A due date 3 weeks out gets no request until some later reconcile. The sentinel only covers budget drops.
- **Fix:** add to the reserved set (use the existing spare slot or the sentinel slot, since sentinel ids are unique): if any open item's k = 0 lies beyond the horizon, schedule `asist.sentinel.h` at `now + 13 d` (workStart), with text "Asist'i bir kez aç — ileri tarihli hatırlatmaların planlanacak."

### 24 — MINOR — Import "Değiştir" replaces the device-local `meta`

- **Location:** §3.6.4 `ImportMode` "replace: whole AppData (settings kept? → replaced)" (l. 3057).
- **Problem:** Replacing `meta` imports another install's `lastProfileStamp` (spurious or missed rebuild), `installDate` (wrong signing estimate), `lastDailyBackupDay` and `dismissedBanners`.
- **Fix:** *"replace = items, projects, places, settings; `meta` is kept local except `lastEndOfDayMove = nil`."* Also resolve the "settings kept? → replaced" ambiguity explicitly.

### 25 — MINOR — `voice.apply(settings:)` must not touch the audio session in background launches

- **Location:** §3.6.2 `bootstrap()` → `voice.apply(settings:)` (l. 2798); §3.6.7 `apply` "volume trigger on/off" (l. 3430).
- **Problem:** `bootstrap()` also runs for Siri, notification-action and BG launches. If `apply` arms the trigger, it activates a `.playback` session in the background, which fails or interferes with Siri's audio.
- **Fix:** *"`apply` only stores configuration; arming happens exclusively in `sceneDidBecomeActive()` and after listening when `UIApplication.shared.applicationState == .active`."*

### 26 — MINOR — Readers must respect `isLoaded`

- **Location:** §3.6.2 `bootstrap()` / `dataDidChange` → `widgets.refresh(items: store.items …)` (l. 2804, 2833); §3.7 `BugunIntent`/`GecikenlerIntent` (l. 3926–3930, 3948–3952); §5.1 onboarding gate.
- **Problem:** With `!isLoaded`, `store.items` is empty. The widget would publish an empty snapshot, Siri would answer "bugün iş yok", and onboarding would appear because the default is `onboardingCompleted == false`.
- **Fix:**
  - `WidgetSnapshotWriter.refresh` is a no-op when `!store.isLoaded`.
  - Both intents answer *"Şu an kayıtlarına erişemiyorum. Telefonun kilidini açıp tekrar dener misin?"* when `!isLoaded`.
  - The onboarding cover uses `$router.showOnboarding`, set in `sceneDidBecomeActive` only when `store.isLoaded && !store.settings.onboardingCompleted`. This also removes the unspecified "onboarding binding", which would otherwise need a forbidden `Binding(get:set:)` (§4.1 r9, §9 r22).

### 27 — MINOR — `LocationService.sync` cannot detect changed geofences

- **Location:** §3.6.6 `sync(items:places:)` "Removes stale asist.loc.* requests, adds missing ones" (l. 3378–3382).
- **Problem:** Without a fingerprint, editing a place's coordinates or radius, the item title or the trigger (arrive/leave) leaves the old pending request in place.
- **Fix:** put `fp = StableHash.fnv1a64("\(lat)|\(lon)|\(radius)|\(trigger)|\(title)|\(subtitle)|\(body)")` in `userInfo` and re-add on mismatch, exactly like `NotificationScheduler.apply`.

### 28 — MINOR — The signing-expiry estimate is wrong after the first re-sign when the profile is unreadable

- **Location:** §3.6.11 `expiryDate = profile?.expirationDate ?? (meta.installDate + 7 days)` (l. 3825).
- **Problem:** Without a readable profile no re-sign is detected, so after day 7 the estimate lies in the past forever. The result is a permanent "expired" banner and no warnings.
- **Fix:** when `profile == nil`, set `expiryDate = nil` for **planning** (no warnings) and show "İmza bitişi: bilinmiyor" in AppStatus. Keep the estimate only as UI text marked "(tahmini)" while `now < installDate + 7 d`.

### 29 — MINOR — The Control Center "Dinle" path depends on deprecated `openAppWhenRun` inside an extension; prepare the documented fallback

- **Location:** §3.7 `DinleIntent` (l. 3854–3877); §3.8 `DinleControl` (l. 4116–4134).
- **Evidence:** Apple's `openAppWhenRun` page (deprecated 26.0) says *"Setting this property to `true` generates an error if the app intent runs in an app extension"*, and recommends the deprecated-extension pattern "for app intents you run inside your app". Apple's controls article documents `OpenIntent` with target membership in both targets as the way to open the app from a control. The contract's approach (both targets + `openAppWhenRun`) matches community-verified iOS 18 behaviour, but it is not the documented one on iOS 26.
- **Fix:** keep the design, and add to §10 a device test "Control → app opens → listening starts", with a pre-written fallback: make `DinleIntent: OpenIntent` with `@Parameter(title: "Hedef") var target: DinleHedef` (`enum DinleHedef: String, AppEnum { case dinle }` with static representations), still compiled into both targets, and still no `supportedModes`.

### 30 — MINOR — CI cannot see silent Siri/Shortcuts breakage; add assertions and a flexible-matching fallback

- **Location:** §7.4 CI (l. 4696–4700); §7.3 `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING: YES` (l. 4616).
- **Problem:** If App Intents metadata is not extracted (for example `SWIFT_REFLECTION_METADATA_LEVEL = none`, or intents that became unreachable), the build still succeeds, and "Asist'e Kaydet" then disappears from Shortcuts and Back Tap. Flexible matching runs an NL-training step per known region (`tr`); if that step rejects `tr`, the contract only offers "delete AppShortcuts.strings".
- **Fix:**
  - `package-ipa.sh` pre-validation fails the job unless `Asist.app/Metadata.appintents/extract.actionsdata` and `Asist.app/PlugIns/AsistWidgets.appex/Metadata.appintents/extract.actionsdata` exist and the first contains `KaydetIntent` and `DinleIntent`.
  - Never set `SWIFT_REFLECTION_METADATA_LEVEL`.
  - Second CI fallback: `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING: NO` if the App Shortcuts NL-training/SSU step fails.

### 31 — MINOR — Ownership gaps that cause duplicate definitions in parallel work

- **Location:** §5.3 `struct StatChip` (l. 4282) has no file in §2.3; `TodayHeader` (WP9) and `Chip.swift` (WP9) could both define it.
- **Fix:** §2.3: *"`App/UI/Components/Chip.swift` defines `Chip`, `ChipRow`, `StatChip`."* Add a CI grep for duplicate `struct <Name>` across `App/` in `error-summary.sh`.

### 32 — MINOR — Intent dialogs built from runtime text are treated as localization keys

- **Location:** §3.7 rule "Dialog text is always built as `IntentDialog(LocalizedStringResource(stringLiteral: text))`" (l. 3851).
- **Problem:** The runtime sentence becomes a lookup key and format string. User titles containing `%` (for example "%50 indirim teklifi") may be mangled when the system resolves the resource.
- **Fix:** in `TurkishSpeech.confirmation`/`AgendaBuilder` spoken texts (which are only for speech or dialog), replace `%` with `" yüzde "` before returning. Add this rule to §3.5.4.

### 33 — MINOR — Location reminders start nagging only after the next app activity

- **Location:** §3.2.7 `anchorDate` → `locationFiredAt`; §6.3 "location notification any action → recordLocationFired"; 01a §3 "Location notifications do not launch the app".
- **Problem:** If the user neither interacts with the location notification nor opens Asist, no chain ever starts. An explicit "Temizle" works through `.customDismissAction`; a flicked-away banner does not.
- **Fix:** document the limitation in the `NotificationCopy.locationContent` body: *"“✓ Yaptım” demezsen, bir sonraki açılışta hatırlatmaya devam ederim."* and in KULLANIM.md. The BG refresh is already the only automatic catch-up; no code change is needed beyond the copy.

### 34 — MINOR — Clarity traps for implementers (compile errors waiting to happen)

- `NagProfiles.subscript(kind:)` (l. 720) has **no external label**, so it is called as `profiles[kind]`; `profiles[kind: x]` does not compile. Rename it to `subscript(_ kind: NagProfileKind)` to make that obvious.
- `DataStore` and the other `@Observable` roots: every access to `store.items` in a view observes the whole `data`. `updateMeta` runs in every reconcile, so Today, Lists and Projects re-render after each reconcile. This is not a bug, but WP9/WP10 should avoid heavy work in `body`: `AgendaBuilder.snapshot` is already recomputed once a minute inside `TimelineView`.
- §3.6.4 `ImportPreview` and `ImportMode` are declared in `DataStore.swift`, while §2.3 says the helpers live in `ImportExport.swift`. Keep the declarations in one file only, `DataStore.swift`, to avoid redeclaration errors.

---

## 2. Verified OK — no change needed (checked against current SDK docs and toolchain sources)

| Item in contract | Verified fact |
|---|---|
| `NotificationCoordinator` delegate signatures (§3.6.5) | SDK: `optional func userNotificationCenter(_:didReceive:withCompletionHandler: @escaping @Sendable () -> Void)` and `…willPresent…(@escaping @Sendable (UNNotificationPresentationOptions) -> Void)` — exact match; protocol is not `@MainActor` |
| `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)` | `launchHandler: @escaping (BGTask) -> Void` (not Sendable); `BGTask.expirationHandler: (() -> Void)?` |
| `NotificationCenter.addObserver(forName:object:queue:using:)` | block is `@escaping @Sendable (Notification) -> Void`, so the closures in `AppEnvironment.observe` and 01b are not MainActor-inferred (correct) |
| `UNNotificationCategory(… hiddenPreviewsBodyPlaceholder:options:)` | exists (iOS 11); docs: "`%u` as a placeholder for the number of messages with the same thread identifier", so `"%u Asist hatırlatması"` is correct |
| `setBadgeCount(_:) async throws` | iOS 16+ |
| `AVAudioApplication.shared.recordPermission` | iOS 17.0, type `AVAudioApplication.recordPermission` |
| `UIApplication.protectedDataDidBecomeAvailableNotification` | `nonisolated class let` (usable from any context) |
| `AppIntent.openAppWhenRun` | deprecated 26.0; Apple doc shows exactly the `@available(*, deprecated) extension X { static var openAppWhenRun: Bool { true } }` pattern |
| `AppIntent.authenticationPolicy` default | doc: "The default value of this property is `.alwaysAllowed`… including when the device is locked", so D23 needs no code line |
| `IntentDialog.init(_ string: LocalizedStringResource)` | exists (iOS 16) |
| `AppShortcut(intent:phrases:shortTitle:systemImageName:)` | non-optional overload exists; a newer optional-parameter overload also exists, but literal arguments resolve to the non-optional one |
| `StaticControlConfiguration(kind:content:)`, `ControlWidgetButton(action:label:)` | iOS 18.0, exact labels |
| `View.environment(_ object: T?) where T: AnyObject & Observable` | iOS 17.0 (used in `AsistApp`) |
| `ShortcutsLink()` | `init(action: @escaping () -> Void = {})`, so the no-argument form compiles |
| `WidgetBundle` iOS 17/18 helper | SE-0360 conditions hold for `makeWidgets()` (top-level `if #available`, no prior return, branch returns, unconditional fallback return). The current `WidgetBundleBuilder` also has `buildLimitedAvailability` and `buildOptional`, so the in-builder `if #available(iOS 18.0, *) { DinleControl() }` is a valid alternative on Xcode ≥ 16.1 |
| `TimelineProvider` requirements | `@preconcurrency … completion: @escaping @Sendable` — omission is a warning only (see #14) |
| `LossyDecodableArray` skip logic | swift-foundation `UnkeyedContainer.decode` advances **only after** a successful unwrap, so a failed `Element` decode followed by `SkippedElement` skips exactly one element (no silent skip of the next valid item) |
| `TurkishText.lower/upper` on Linux | `precomposedStringWithCanonicalMapping` exists in swift-corelibs-foundation `NSStringAPI.swift` |
| `Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication` | exists (iOS 5) |
| `UIApplication.beginBackgroundTask(withName:expirationHandler:)` | handler `(@MainActor @Sendable () -> Void)?`, used in the fix for #7 |
| Codable models (§3.2) | `CodingKeys` complete for `Item` (32/32), `AppSettings`, `AppMeta` (13/13); custom `init(from:)` plus synthesized `encode(to:)` is valid; reading `createdAt` inside `init(from:)` after assigning it is legal for structs; `self.init()` delegation in struct decoders is legal |
| Class `AppEnvironment.init` reading `store` before all lets are set | legal for a root class (per-property definite initialization) |
| `CaptureDraft` `nonisolated let id: UUID` in a `@MainActor @Observable` class | allowed (Sendable `let`); satisfies `Identifiable` from the nonisolated `SheetRoute.id` |
| XcodeGen spec | keys valid for 2.46 (`minimumXcodeGenVersion`, local `packages.path`, target `scheme.language/region`, `info`/`entitlements` generation with default `CFBundleIdentifier`/`CFBundleExecutable`/`CFBundlePackageType`); `Shared` path shared by two targets is supported |
| Info.plist | every privacy-sensitive API used in v1 has its usage string (mic, speech, when-in-use location); `UIBackgroundModes: fetch` + matching `BGTaskSchedulerPermittedIdentifiers`; no paid-only entitlement |

---

## 3. Additions to §9 (compile-hazard checklist) and §10 (device tests)

§9 new items:

- **44.** Headless entry points await `engine.reconcile` (#1, #7).
- **45.** No `AppEnvironment.shared` inside any service initializer (#11).
- **46.** Mutators emit `onChange` only on a real change (#5).
- **47.** `.fileImporter` URLs: start and stop security-scoped access (#12).
- **48.** All decoded numbers clamped before use in `Task.sleep`, `DateComponents` or `CLCircularRegion` (#20).
- **49.** `SigningMonitor.reload()` precedes the first reconcile in every process (#4).

§10 new device tests:

- **D-a** "Back Tap → Asist Hızlı Kayıt → 'yarın 9'da X hatırlat' with Asist never opened afterwards → notification fires" (#1).
- **D-b** "Create a reminder for later today, then do not open Asist for 2 days → nags continue each morning" (#2).
- **D-c** "Lock screen '✓ Yaptım' as the last interaction before expiry → signing warnings still pending (Tanılama list)" (#4).
- **D-d** "Control Center 'Asist Dinle' → app opens and listens" (#29).
- **D-e** "Export → delete → reinstall → import from iCloud Drive" (#12).

---

## Sources

- Apple DocC JSON (current SDK), fetched 2026-09-27: `usernotifications/unusernotificationcenterdelegate/*`, `usernotifications/unnotificationcategory/*`, `backgroundtasks/bgtaskscheduler/register(...)`, `backgroundtasks/bgtask/*`, `foundation/notificationcenter/addobserver(...)`, `appintents/appintent/openappwhenrun`, `appintents/appintent/authenticationpolicy`, `appintents/intentdialog/init(_:)`, `appintents/appshortcut`, `appintents/shortcutslink/init(action:)`, `widgetkit/timelineprovider/*`, `widgetkit/staticcontrolconfiguration/init(kind:content:)`, `widgetkit/controlwidgetbutton`, `widgetkit/creating-controls-to-perform-actions-across-the-system`, `swiftui/widgetbundlebuilder`, `swiftui/view/environment(_:)`, `avfaudio/avaudioapplication/recordpermission-swift.property`, `uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:)`, `uikit/uiapplication/protecteddatadidbecomeavailablenotification`.
- [SE-0360 Opaque result types with limited availability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0360-opaque-result-types-with-availability.md)
- [Apple Forums 759670 — WidgetBundle with ControlWidget on iOS 17](https://developer.apple.com/forums/thread/759670), [762688 — WidgetBundleBuilder #available crash fixed in Xcode 16.1 b3](https://developer.apple.com/forums/thread/762688)
- [Apple Forums 759794 — ControlConfigurationIntent / openAppWhenRun target membership](https://developer.apple.com/forums/thread/759794), [onmyway133 — open app from Control Widget](https://onmyway133.com/posts/how-to-open-app-with-control-widget-on-ios-18/)
- swift-foundation `Sources/FoundationEssentials/JSON/JSONDecoder.swift` (`UnkeyedContainer.decode`); swift-corelibs-foundation `Sources/Foundation/NSStringAPI.swift`.
- [Apple Forums 786405 — Extract App Intents Metadata / SwiftConstValues](https://developer.apple.com/forums/thread/786405); [fk-encore PR 1271 — App Intents metadata and SWIFT_REFLECTION_METADATA_LEVEL](https://github.com/as19git67/fk-encore/pull/1271)
