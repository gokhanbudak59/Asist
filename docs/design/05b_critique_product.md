# 05b — Adversarial Product Critique (user-centred review of 02 / 03 / 04)

| Field | Value |
|---|---|
| Reviewed | `04_architecture_contract.md` (binding), `03_ux_product_spec.md`, `02_parser_spec.md`, `parser_corpus.json` (371 cases); spot checks in 01a/01b/01c/06 |
| Reviewer stance | "I am Gökhan": automation manager, forgetful, overloaded, dismisses alarms when busy, will not memorise phrases, has no Mac, re-signs with Sideloadly every 7 days |
| Date | 2026-09-27 (Sunday), Europe/Istanbul |
| Companion file | `docs/design/parser_corpus_extra.json` — 40 proposed parser cases (same format, `status: "proposed"`) |
| Severity scale | **BLOCKER** = the product silently fails its core promise or the user abandons in week 1 · **HIGH** = frequent, visible failure or trust loss · **MEDIUM** = recurring friction / edge loss · **LOW** = polish |

Overall verdict: the architecture is careful about *compiling* and about *not corrupting data*, but it under-protects the one promise the user actually asked for — **"nothing I said is forgotten, and it keeps reminding me until I say done"**. Several paths deliver a reminder zero times (undated items, notes-by-default, recurring items after 2 occurrences, anything after the 7-day profile expiry, "yarım saat önce hatırlat"), and several paths make the app so noisy in meetings that he will turn notifications off (no mute in v1, meetings nag during the meeting, "acil" = every 15 minutes, 10 long-tails at 08:30). At the same time v1 scope is far too large for a first-ever CI compile. Both problems are fixable with small, mostly pure-function changes.

---

## 1. Fix list before any WP starts coding (ordered)

| # | Item | Sev | Cost | Where |
|---|---|---|---|---|
| 1 | Notification action ordering: remove the item's pending requests (and add the new k0 for snoozes) **before** `completionHandler()` (B1) | BLOCKER | S | 04 §6.3, §3.6.5 `ReminderEngine.handle` |
| 2 | Clamp nags at the signing expiry + weekly re-sign ritual + human-readable daily export (A1) | BLOCKER | S | 04 §6.4 step 4, WP8/WP4 |
| 3 | Nothing captured stays undated/silent: undated tasks default to "Bugün (saatsiz)", T10 fallback = task not note, "hemen" = +5 min, critical/high undated → "Ne zaman?" (A4) | BLOCKER | S | 02 §10.1, `ItemFactory`, corpus pri-009 |
| 4 | Parse spoken lead times ("yarım saat önce hatırlat") into `leadTimesMinutes` (A5, G10) | HIGH | S | 02 §6.4/§1, `ParsedItem` |
| 5 | Keep "Sessize al" (mute window) in v1 — it is a quiet-window input to the pure planner, not a UI feature (A3) | HIGH | S | 04 §1.2, `AppSettings`, §6.4 |
| 6 | Event items (toplantı/görüşme/FAT…) get no nag chain and auto-close 2 h after start (A2) | HIGH | S | 04 §1.2, `NagProfileKind`, `rollOverRecurring` step |
| 7 | Recurring items use repeating triggers (daily/weekly/monthly ≤ 28) instead of "next 2 occurrences" (B4) | HIGH | M | 04 D27, §6.4 |
| 8 | Chain horizon: long-tail eligibility, 5 workday briefings that list overdue titles, content-bearing sentinel (B3, B5, C3) | HIGH | M | 04 §6.4 steps 1–4 |
| 9 | Global rate limiter + "acil" → Önemli, only "çok acil/kritik" → Kritik (C2) | HIGH | S | 02 §7.8, `NagPlanner` |
| 10 | Normal-priority profile too weak; Israrcı too loud in the evening (C1, C4) | HIGH | S | 04 §3.2.5 constants |
| 11 | Parser gap classes G1–G8 (equipment numbers, waiting verbs, reschedule verbs, "neyi unuttum" misread as completion, self-corrections) (§6) | HIGH | M | 02 §5–§10 + `parser_corpus_extra.json` |
| 12 | Cut v1.0 to the core (no widget extension, no location, no Smart Mode, no checklists/e-mail/summary, EOD screen later) (§8) | HIGH | — | 04 §1.1, §2, §7.3 |

---

## 2. Week-1 abandonment risks (A)

### A1 — BLOCKER — The 7-day free signature silently breaks everything once a week
**What happens.** (a) After expiry the app cannot launch, so every notification action ("✓ Yaptım", "10 dk") does nothing while already-scheduled nags keep firing — the user taps "Yaptım" and is nagged again, the worst possible trust breaker. (b) 01c (open item 4) reports that pending notifications may not fire after a re-sign until the app is opened; Sideloadly's auto-refresh never opens the app. (c) Sideloadly can "mangle" the bundle ID (01c D9); a mangled re-install is a *different* app container = "all my data is gone". (d) The weekly re-sign is a chore he will skip in exactly the busy weeks the app is meant for.
**Fixes.**
1. `NagPlanner.plan`: when `signingExpiry != nil`, drop every **follow-up** (k ≥ 1, long-tails, repeating rules) whose fire date is after `signingExpiry − 5 min`; keep k = 0 first alerts (informational even if actions fail); the existing T-3 h `.signing` warning gets the body "Yenilemezsen hatırlatmaların susar; yeniledikten sonra Asist'i bir kez aç". Test: plan with expiry in 3 h has no k ≥ 1 after it.
2. Re-sign ritual: make the signing warnings (T-72 h / T-24 h / T-3 h) use the **Israrcı** chain (they are the most important notifications in the app) and put a fixed weekly slot in onboarding page "Verilerin güvende": "Her Pazartesi 08:30 iş bilgisayarında Sideloadly ile yenile". Recommend Sideloadly Daemon auto-refresh on the always-on work PC (01c, Sideloadly facts table, "Otomatik yenileme") *plus* the in-app instruction "Yeniledikten sonra Asist'i bir kez aç" in every signing notification body.
3. Human-readable safety copy: on every save-day, write `Documents/Yedekler/Asist-acik-isler.txt` (open items: date · time · title · person/project) next to the JSON backup. It is readable in the Files app even when the app is expired or before re-import. ~40 lines of code in `BackupManager`.
4. KURULUM.md: step "Sideloadly günlüğünde bundle ID `com.gokhanbudak.asist` görünmeli; farklıysa YÜKLEME" + "Remove app extensions yalnızca App ID sınırı dolduğunda" (see §8: v1.0 has no extension, so each install costs 1 App ID).
5. Open question Q1 ($99 Developer Program) — the single largest reliability upgrade (1-year signing, time-sensitive entitlement, App Groups without hacks).

### A2 — HIGH — Meetings nag *during* the meeting
Event auto-close is excluded from v1 (04 §1.2), but "Perşembe 14'te ABB ile toplantı" is one of the most common things he will say. Result: 14:00 alert, then (Nazik) 14:10 and 14:30 buzzes while he sits with the customer, and after the meeting the item turns red in GECİKENLER, inflates the badge, becomes a long-tail and appears in tomorrow's briefing as "gecikmiş". He will start ignoring red.
**Fix (cheap, pure):** `ItemFactory` marks an item as an event when `hasTime` and the title contains an event noun (`toplantı, görüşme, randevu, ziyaret, sunum, eğitim, denetim, FAT, SAT, devreye alma toplantısı, uçuş, yemek, maç`). Add `NagProfileKind.etkinlik` (offsets `[]`, cap 1, maxPending 0; lenient decoding already maps unknown raw values). Default pre-alert 15 min for events (overridable by G10 lead parsing). In `ReminderEngine.reconcile` step 3 (next to `rollOverRecurring`) auto-complete events 120 min after start (`status = .done`, history `.done` with detail "otomatik kapandı"). Detail screen keeps a "Etkinlik değil" toggle.

### A3 — HIGH — No way to silence Asist in a meeting, while onboarding tells him to whitelist Asist in Focus
03 rehber E asks him to add Asist to the "İş" Focus allowed apps (required because time-sensitive is unavailable with free signing). "Sessize al" and digests are cut from v1 (04 §1.2). In a 2-hour customer meeting with 4 open Önemli items the phone buzzes ~12 times; the natural reaction is Settings → Notifications → Asist → off, after which nothing ever reaches him again.
**Fix:** keep only the planner part of "Sessize al" in v1: `AppSettings.muteUntil: Date?` (lenient, default nil); `NagPlanner` treats `[now, muteUntil)` as an extra quiet window for k ≥ 1 (k = 0 of Kritik still rings), collapsing the muted nags into one notification at `muteUntil` (same quiet-exit logic that already exists). UI: a `Menu` on the Today toolbar (30 dk / 1 saat / 2 saat / Mesai sonuna kadar) + banner "Sessiz: 11:30'a kadar ×". No new target, no new API.

### A4 — BLOCKER — Things he says can be saved in a form that never reminds him
Silent by design today:
* **Undated tasks** (T9: "Ahmet'i ara", "teklifi gönder", tsk-007/008) land in "Zamanı belirsiz" and only surface at the end-of-day screen after 3 days. For a user who says things *because* he is about to forget them, this is a black hole.
* **T10 fallback = note.** Bare noun phrases ("Hat 3 enkoder kablosu", "Ahmet teklif") become notes; notes never notify, never go overdue, never appear in the briefing.
* **Critical undated.** Corpus pri-009 "çok acil Ahmet Bey'i hemen ara" expects an undated critical *task* — zero notifications for the most urgent sentence he can say. 03 §5.8 #14 ("Acil: … Hakan'la konuş") expects "Ne zaman?", but 02 produces a T9 task with no due.
**Fixes:** (1) `ItemFactory`: task without due from voice/Siri → `dueDate = today @ defaultDayTime, hasTime = false` (appears in BUGÜN "Gün içinde", no daytime nag, overdue at midnight → next day's briefing/long-tail, included in EOD). Card chip row shows `[Bugün] (Yarın) (Zamansız)` so "Zamansız" is an explicit choice. (2) 02 §10.1: T10a/T10b produce **task** (with `needsReview`), not note — notes require an explicit note cue. (3) priority ≥ high and no time → treat as reminder with `needsTime` (interactive asks; headless +1 h). (4) G9: `hemen/şimdi/derhal` → now + 5 min (see xpri-001; update pri-009).

### A5 — HIGH — "Yarım saat önce hatırlat" is silently ignored
04 §1.1 row 24 says pre-alerts are set in the detail screen only; 02 does not extract them. The user will *say* it (03 §5.8 #9 is literally this sentence). Outcome: title "ABB ile toplantı var yarım saat önce", no 13:30 alert, and he walks into the meeting unprepared believing Asist would warn him.
**Fix:** 02 G10 (§6): `DURATION önce (hatırlat|haber ver|uyar|söyle)` / `DURATION kala` → `ParsedItem.leadTimesMinutes: [Int]` (new field, default `[]`), consumed from the title; `ItemFactory` copies it; planner already supports it. Corpus xlead-001/002.

### A6 — MEDIUM — On the shop floor the listening overlay never stops
01b §1.4 step 3 refreshes `lastSpeechActivityAt` whenever input level ≥ −24 dBFS. Factory background noise is routinely above that, so silence detection never fires and every capture runs to the 45 s cap (or needs a tap on "Bitti" with gloves).
**Fix:** measure a noise floor during the first 300 ms (before the haptic "listening" cue) and use `max(0.6, floor + 0.15)` as the threshold; energy may extend speech activity by at most 1.5 s beyond the last *changed partial*. Add a device test "fabrika gürültüsü (müzik 80 dB)".

### A7 — MEDIUM — Asist speaks confirmations aloud in meetings
D18 declares "Sessiz modda sus" unimplementable and defaults `speakConfirmations = true`. Speaking under the `.ambient` (or `.soloAmbient`) session category **is** silenced by the Ring/Silent switch (AVAudioSession documentation), so the original 03 setting is implementable for confirmations while query answers keep `.playback`. Also default: speak confirmations only when the audio route is headphones/Bluetooth/CarPlay (`AVAudioSession.currentRoute.outputs`), otherwise toast + haptic. Verify on device (switch session category after the recogniser stops: deactivate → setCategory → activate, 01b rule).

### A8 — MEDIUM — Siri/Shortcuts naming will make the setup guides fail
* `DinleIntent.title = "Asist'i Dinlet"` ("make Asist play/listen" — reads like "play Asist"), while 03 guide A step 4 tells him to pick **"Asist Dinle"** in Shortcuts and the Control is displayed as "Asist Dinle". He will search "Asist Dinle" and not find it.
* `INAlternativeAppNames = Asistan` is substituted into `${applicationName}'e kaydet` → "Asistan'e kaydet" (wrong vowel harmony) — either drop the alternative name or accept that only "Asist" phrases are reliable.
* 03 guide A (Back Tap → "Asist Dinle", opens the app) contradicts 04 §3.7's KURULUM recipe (Back Tap → "Metni Dikte Et" → "Asist'e Kaydet", headless). The headless recipe is the better one (no app launch, one utterance); make it guide A and keep "Asist Dinle" as guide A-alt.
**Fix:** intent title "Asist Dinle"; one naming table shared by intents, control, guides and KULLANIM.md; Day-1 device test of every Siri phrase with Turkish Siri (01b §9).

### A9 — MEDIUM — The strongest free anti-forget setting is not requested: persistent banners
iOS "Banner Stili: Kalıcı" keeps each Asist banner on screen until he acts on it. That is the closest thing to an alarm available without AlarmKit/critical alerts, costs zero code, and `PermissionCenter.alertsPersistent` is already read. **Fix:** onboarding page 2 tip + a one-time yellow banner "Hatırlatmalar ekranda kalsın: Ayarlar › Bildirimler › Asist › Banner Stili › Kalıcı" (dismissible 30 days).

### A10 — LOW — Onboarding is 7 pages
A user with no time will tap "Atla" through permissions. Reduce to 3: (1) promise + notification permission (+ Kalıcı tip), (2) mic/speech permission + live test "1 dakika sonra su içmeyi hatırlat", (3) quick access (Siri phrase + Back Tap shortcut link) with "Sonra" — work hours keep defaults and are offered later as a banner.

---

## 3. Silent-loss audit (B)

Checklist requested by the orchestrator:

| Path | Verdict | Item |
|---|---|---|
| 64-limit eviction | Tiering is sound, but dropped first alerts depend on a generic sentinel the user will ignore | B5 |
| Recurrence not re-armed | **Loss** after 2 future occurrences without an app launch | B4 |
| Snooze while app killed | Background action runs, but the old chain is removed / new k0 added only in the post-completion reconcile | B1 |
| Done-marking from notification not persisted | Same ordering bug; plus `isLoaded == false` makes the mutation a no-op | B1, B2 |
| Phone reboot | OK (pending requests survive); before-first-unlock actions/Siri captures are no-ops | B2 |
| Time change | OK for wall-clock items; minute-offset items ≥ 60 s drift with a time-zone change | B10 |
| Free-provisioning expiry | **Loss + uncancellable nags** | A1 |
| Items that never had a notification | **Loss by design** (undated, notes, critical undated, spoken lead times) | A4, A5 |
| Chain window runs out without interaction | **Loss** after `maxPendingFollowUps` unless overdue at a reconcile | B3 |

### B1 — BLOCKER — "✓ Yaptım" / snooze may not stop the old nags
04 §6.3 + hazard 42 only guarantee that `completionHandler()` runs *after the store write*. For "✓ Yaptım" the `scheduler.removeAll(for:)` call has no ordering relative to the completion handler, and for every snooze action the old chain is replaced and the new one scheduled only by the following (debounced, serialized) `reconcile`. iOS may suspend the background-launched app right after the completion handler, so the item is *done in the file* while its k = 1…8 requests are still pending — he taps "Yaptım" at 15:05 and gets "15:15 · 3. hatırlatma". For snoozes it is worse: the old chain stays **and** the new one may never be scheduled → the snoozed reminder is lost.
**Fix (normative text for §6.3):** inside `handle()` and before `completionHandler()`: (1) persist; (2) `await scheduler.removeAll(for: itemID)` (pending + delivered); (3) for `SNOOZE_10/60/TOMORROW/FU_*`: build `NagPlanner.chain(anchor: newTarget…)` and add the first 2 elements with their standard ids/content via `NotificationScheduler.apply` restricted to that item; (4) call `completionHandler()`; (5) `requestReconcile`. Unit-testable split: a pure `NagPlanner.immediateRequests(for item:, settings:, now:)`.

### B2 — HIGH — `isLoaded == false` turns actions and Siri captures into silent no-ops
04 §3.6.4 correctly refuses to write while the data file is unreadable, but `handle()` and `captureHeadless()` then do nothing — and Siri still answers "Tamam, …hatırlatacağım".
**Fix:** `App/Store/EventJournal.swift`: append-only JSON-lines file created with `FileProtectionType.none`, holding `{type: action|capture, actionID, itemID, text?, at}`; `DataStore.load()` replays and truncates it after the first successful read. `captureHeadless` when `!isLoaded`: journal the text and answer honestly "Kaydettim; telefonun kilidini açınca listeye eklenecek." (Privacy note: raw utterance is unprotected until the next unlock — acceptable vs. losing it; document in KULLANIM.)

### B3 — HIGH — The nag window only moves when he touches the app
The planner keeps k = 0 + `maxPendingFollowUps` (Nazik 5, Israrcı 8). It is re-planned only on app launch, a notification *action*, an explicit *dismiss* (custom dismiss), or an unreliable `BGAppRefreshTask`. A banner that simply times out into Notification Center wakes nothing. Long-tails are created only for items overdue **at plan time**, and only 2 briefings are planned. So: an item planned on Monday for Tuesday 15:00 that he ignores gets ≈ 6–9 alerts until Wednesday morning, then **nothing, forever**, until he happens to open the app.
**Fixes:** (1) long-tail eligibility = `overdueStart ≤ first fire of the daily rule` (not `≤ now`) — correct because a repeating daily trigger starts at the next `workStart`; (2) plan the next **5 workday briefings** (content projected per fire date — the planner already computes projected overdue sets for badges) and list up to 3 overdue titles in the body ("Geciken: Teklif konusu, Ahmet'i ara +2"): the briefing becomes the long tail for everything; (3) always plan a **horizon sentinel** 1 h after the last planned item notification: "Asist'i bir kez aç — 4 açık iş var, hatırlatmaya devam edebilmem için". Reserved slots: 5 briefings + 1 EOD + 1 backup + 2 signing + 1 sentinel + 1 spare = 11 (was 8); compensated by C3 (long-tails drop from ≤ 10 to ≤ 3).

### B4 — HIGH — Recurring reminders stop after two occurrences
D27 schedules k = 0 of the next 2 occurrences as one-shots. "Her gün 9'da ilacımı iç" therefore stops on day 3 if he only glances at banners; "her pazartesi haftalık rapor" stops after two Mondays. Nothing tells him.
**Fix:** for rules representable by a repeating `UNCalendarNotificationTrigger` — daily; weekly (one request per weekday); monthly with `monthDay` 1…28 — plan **one repeating request per rule** (`PlannedNotification.Rule.daily/.weekly` already exist; add `.monthly(day:hour:minute:)`), used as the carrier of every k = 0; the current occurrence's follow-ups stay one-shots. Early completion (done before today's fire) → replace the repeating request with one-shots for the next 2 occurrences until the next reconcile after the skipped fire time (a repeating trigger cannot skip one fire). Interval > 1, monthDay 29–31/−1, yearly → one-shots for the next 4 occurrences.

### B5 — HIGH — Budget overflow is announced by a notification nobody acts on
The sentinel is a generic "Asist'i bir kez aç" at `earliestDroppedDate`, only when something was dropped. If he ignores it (he will), the dropped first alert never rings.
**Fix:** the sentinel **is** the earliest dropped item's own k = 0 notification (title, subtitle, `ASIST_ITEM` category with its 4 actions, `iid` = that item) with the body line "+3 hatırlatma daha — planı tazelemek için Asist'i aç". Any action on it wakes the app and re-plans.

### B6 — MEDIUM — "Hepsini yarına taşı" at 17:45 moves reminders that have not happened yet
`endOfDayCandidates` = today's open items + overdue. "İş çıkışı ekmek al" resolves to 18:00 (`mesaiBitimi = workEnd = 18:00`), so the 17:45 action moves it to tomorrow 18:00 before it ever rang.
**Fix:** candidates = overdue + untimed today + timed today with anchor ≤ fire time; list later-today items separately in the EOD body ("Bu akşam: 18:00 Ekmek al").

### B7 — MEDIUM — Time-sensitive level without the entitlement
All Önemli/Kritik requests use `.timeSensitive`. Behaviour without the entitlement is unverified (03 says "expected to downgrade"). **Fix:** `PermissionCenter` exposes `timeSensitiveSetting`; when it is `.notSupported`, the planner input sets `allowTimeSensitive = false` and emits `.active`. Device test T1 must log both variants.

### B8 — MEDIUM — Deleted items are unrecoverable after 5 seconds
Soft-deleted items live 30 days in the file but "Son silinenler" UI is cut, and the EOD button "Vazgeç (sil)" invites mis-taps (F1). **Fix:** a plain filtered list in Ayarlar › Veri › Son silinenler with swipe "Geri getir" (≈ 60 lines, WP10/11).

### B9 — MEDIUM — "Vazgeç" in the listening overlay discards the transcript without undo
Principle 3 ("Silme her zaman Geri Al ile geri alınabilir") is violated for the most frequent mis-tap target (top-left, next to the Dynamic Island). **Fix:** if partial text ≥ 2 words, show toast "Vazgeçildi — Geri Al" whose undo opens the confirmation card with that text.

### B10 — LOW — Minute-offset reminders drift across time zones
03 §3.14 promises absolute durations for "10 dk sonra"; 04 §3.6.5 uses time-interval triggers only for < 60 s. Add `Item.isRelative` (set when the due came from a minute-granularity offset) → time-interval trigger for k = 0. Low priority (Turkey has no DST; matters on FAT/SAT trips).

### B11 — MEDIUM — Focus modes swallow everything
Without time-sensitive delivery, any Focus without Asist in its allowed list silences all nags; iOS offers no API to detect this. **Fix:** onboarding page 3 asks "İş yerinde Odak/Rahatsız Etme kullanıyor musun?" → guide E + "Test bildirimi 30 sn" to verify while Focus is on; combine with A3 so that allowing Asist in Focus is not a punishment.

---

## 4. Nag calibration — too weak and too loud (C)

### C1 — HIGH (too weak) — Normal priority = Nazik gives up after two hours
Almost everything he dictates is "normal" (nobody says "önemli" every time). Nazik: +10, +30, +2 h, then one alert per day at 08:30. A call due at 10:00 is last mentioned at 12:00; by next morning the reason (e.g. "before the supplier closes today") has passed. Dismissal is also not a signal (04 §6.3: "chain continues" but nothing changes).
**Fix:** new default for `normal`: offsets `[10, 30, 90]`, repeat every **120 min inside work hours**, none outside (`repeatMinutesOffHours = nil` → next day start), `dailyCap 6`, `maxPendingFollowUps 6`. Optional (behind a setting, default on): an explicit dismiss inside work hours pulls the next nag forward to +20 min when the planned one is > 30 min away — "kapattın ama yapmadın".

### C2 — HIGH (too loud) — "acil" means Bırakmaz: every 15 minutes, 30 times a day
Turkish managers say "acil" for half of their requests. 02 §7.8 maps `acil/acilen` → critical → Bırakmaz (+2, +5, +10, +15, then every 15 min, cap 30/day). Three "acil" items = a buzz every 5 minutes. No global limiter exists (digests cut).
**Fixes:** (1) 02 §7.8: `acil, acilen, önemli, mutlaka` → **high**; only `çok acil, kritik, hayati, sakın unutma, asla unutma` → critical. (2) `NagPlanner` post-pass (pure, testable): among sounded k ≥ 1 notifications keep ≥ 3 min spacing (shift later, max +15 min, else drop the lower-priority one) and ≤ 8 per rolling hour (drop lowest priority, highest k first); k = 0 is never moved. Update corpus pri-* expectations accordingly.

### C3 — HIGH (too loud) — 08:30 notification storm, weekends included
Up to 10 per-item long-tails are daily repeating requests at `workStart` — all at the same minute, every day including Saturday and Sunday (a daily trigger cannot skip weekends), right after the 08:00 briefing.
**Fix:** long-tails only for **critical** items (max 3, staggered +2 min each); everything else is covered by the 5 planned workday briefings that list overdue titles (B3). Frees ~7 slots for B3's extra reserved ones.

### C4 — MEDIUM (too loud) — Israrcı keeps going at home
Israrcı repeats every 2 h off-hours until 22:30 (worked example: 18:00, 20:00, 22:00). Work items at dinner will get Asist muted. **Fix:** `israrci.repeatMinutesOffHours = nil` (next day start); only Bırakmaz continues in the evening. Q7 asks the user.

### C5 — MEDIUM (too weak) — The notification sound is inaudible on the shop floor
The default tri-tone is ~1 s. Custom sounds are cut (04 §1.2) although they are near-zero compile risk. **Fix (v1):** `Tools/make_sounds.py` (Python on Windows) generates two WAVs (Önemli ~8 s, Kritik ~20 s, both < 30 s) into `App/Resources/Sounds/`; `content.sound = UNNotificationSound(named: UNNotificationSoundName("asist-kritik.wav"))` for high/critical k = 0 and every 3rd nag; normal keeps `.default`.

### C6 — LOW — Every notification body repeats "“✓ Yaptım” diyene kadar hatırlatmaya devam edeceğim."
Show it only on k = 0; on nags show "Sonraki: 15:30" (already specified) and the original sentence.

---

## 5. Flow audit — more than 2 taps or typing (D)

| # | Flow | Today | Verdict | Fix |
|---|---|---|---|---|
| D1 | Capture, phone locked | Side button → "Asist'e kaydet" → Siri asks → sentence (0 taps, 2 turns) | OK | — |
| D2 | Capture, unlocked, app closed | Back Tap ×2 → dictate (0 taps after setup) | OK if the headless recipe is the default guide (A8) | Guide A = "Metni Dikte Et → Asist'e Kaydet" |
| D3 | Capture in app | volume ×2 / mic → speak → 4 s auto-save | OK | — |
| D4 | Done from lock screen | long-press → "✓ Yaptım" (2) | OK | Kalıcı banners (A9) |
| D5 | Snooze to a specific time ("perşembe sabah") | tap notification → detail → Tarih seç… → date → time → Kaydet (5–6 taps) | **FAIL** | "Sesle ertele" chip (mic) in `SnoozeGrid` and `HeroCard`: tap → say "perşembe 10'da" → parsed with the snooze parser → toast with undo (2 taps) |
| D6 | Reschedule by voice | "teklifi perşembeye kaydır / yarına al / pazartesiye taşı" not understood | **FAIL** | G3 (§6) |
| D7 | Fix a misheard title | detail → tap title → keyboard | **FAIL (typing)** | mic accessory "Sesle düzelt" on the title field (re-uses listener, replaces title only) |
| D8 | Resolve "Kontrol edilecek" items | open each → edit (3+ per item) | MEDIUM | row swipe: "Doğru" (clears flag) / "Tekrar söyle" |
| D9 | Weekly backup | notification → app → Ayarlar → Veri → Dışa aktar → share sheet → destination (6+) | **FAIL** | backup notification action "Dosyalar'a kaydet" (foreground) opens `.fileExporter` directly; v1.1: auto-write to a user-chosen folder (iCloud Drive via document picker + security-scoped bookmark, no iCloud entitlement needed — verify on device) |
| D10 | Re-sign every 7 days | Windows PC + Sideloadly | **FAIL by nature** | A1 |
| D11 | New project from speech | "Yeni proje: X" chip pre-selected and auto-saved in 4 s | MEDIUM (creates junk) | chip unselected by default; stoplist for document-type "projeleri" (elektrik, pnömatik, hidrolik, mekanik, yazılım, PLC, TIA, otomasyon, montaj) — see xwai-005 |
| D12 | Onboarding | 7 pages, ~12 taps + 3 system dialogs | MEDIUM | 3 pages (A10) |
| D13 | Smart Mode key / Places | typing / physically being there | n/a | cut from v1.0 (§8) |

---

## 6. Parser gaps (E)

### 6.1 Gap classes and rule proposals (all have cases in `parser_corpus_extra.json`)

| Id | Gap | Why it matters for this user | Proposed rule (summary; full text in each case's `proposedRule`) |
|---|---|---|---|
| G1 | **Numbered equipment + locative** read as a clock: "Hat 2'de", "İstasyon 5'te", "Pano 2'de", "3 nolu" | Every sentence about lines, stations, robots, cells, panels, floors — his daily vocabulary. "Hat 2'de …yarın" silently becomes tomorrow **14:00** | N+LOC/DAT directly after an equipment noun (hat/hattı, istasyon, robot, hücre, pano, kat, bant, konveyör, eksen, makine, kabin, no, numara) is part of the noun; `nolu/numaralı` consumes the number without `unusedNumber` |
| G2 | **Waiting verbs**: final `gelecek`, `haber verecek`, `atacak`, `paylaşacak`, 1pl `bekliyoruz`; P7 turns dictation-capitalised "Sürücüler/Tedarikçi" into persons | Supplier/team follow-up is his #1 forgotten item type (03 §6.1 #8) | extend verb list; `gelecek` is a verb when it is the last token; P7 at index 0 rejects plurals and a common-noun list |
| G3 | **Reschedule verbs**: kaydır, taşı, bırak, sonraya at, "(bunu) yarına al"; snooze cannot carry both the target day and the new day | Voice rescheduling is the only 2-tap alternative to D5 | add cues; `al` is snooze only with pronoun/"işini…" object + DAT date; new `ParsedCommand.targetDate` |
| G4 | **Cancel**: "boş ver" (2 tokens), "iptal oldu/edildi" | Meetings get cancelled daily | add |
| G5 | **Complete**: 1pl past (-DIk: hallettik, aldık), "geldi" (waiting received), "gitti" | A team lead reports in "we"; 03 §5.6 already promises "geldi" | add; `geldi/ulaştı/elime geçti` prefer waiting items |
| G6 | **Queries misread as completions**: "neyi unuttum", "neyi kaçırdım" hit the generic `-DIm` completion rule; "… var mı" not a query | "Neyi unuttum" is literally the Siri phrase of GecikenlerIntent and a query in 03 §5.6 — spoken in-app it would try to complete an item called "neyi" | query rules run before the generic `-DIm` completion; `var mı` = query |
| G7 | **Time words**: "4 gibi", "salı sabahı / cuma akşamı", "öğleden önce", "bugün/gün içinde", "10'dan sonra", "öğle yemeğinden sonra", non-adjacent "bu gece … 3'te", "öğlen arası", "mesai bitimine kadar" | Colloquial approximate times are how busy people speak | clock with `gibi/civarı`; possessive dayparts; new `ogledenOnce` 11:00; N+ABL sonra; `öğle yemeğinden sonra` = öğle + 60; utterance-level NIGHT qualifier |
| G8 | **Self-corrections**: "3'te hayır 4'te", "yarın değil öbür gün" | Dictation captures corrections verbatim; today the *rejected* value wins | correction markers (hayır, yok, pardon, değil de, yok yok) → last value of the same type wins |
| G9 | **Urgency/deadline words**: "hemen", "bu hafta" as an item deadline | pri-009 produces an undated critical task | `hemen` → +5 min; `bu hafta (içinde)` → last workday of this week, `vagueDate` |
| G10 | **Lead times**: "yarım saat önce hatırlat", "bir hafta önce hatırlat", "10 dakika kala" | See A5 | new `ParsedItem.leadTimesMinutes` |
| G11 | **Technical numbers/nouns**: version "4.20'ye" read as 16:20; "son günü" read as last day of the month; engineering units trigger `unusedNumber` | Firmware/licence/deadline sentences are daily | version context guard; `son gün/son tarih` are day-of-month only after "ayın"/month; units (V, volt, bar, mm, kW, A, Hz, adet, kg) suppress `unusedNumber` |
| G12 | **Recurrence**: "her 6 ayda bir" missing; "her ayın ilk pazartesi" unrepresentable (risk of silently becoming "monthly on the 1st") | Periodic maintenance and monthly management meetings | `N ayda bir` → monthly interval N (first = today + N months); nth-weekday → `unsupportedRecurrence` + review in v1, `weekOrdinal` in v1.1 |

Also: feed `SFSpeechRecognitionRequest.contextualStrings` (01b §1.8 already lists the jargon) with **project names/aliases and learned person names** — 04 never wires this; and fill `ParserSettings.knownPeople` from the distinct `Item.person` values used ≥ 2 times (fixes lowercase names without apostrophes, 02 limitation 6).

### 6.2 Spec decisions that must be taken explicitly (they change existing corpus cases)

| # | Topic | 02 / corpus today | 03 / user expectation | Recommendation |
|---|---|---|---|---|
| P1 | "haftaya" / "gelecek hafta" **without weekday** | +7 days (day-008 → Sunday 4 Oct) | 03 §5.7: next week's Monday | Next week's first workday at default time (xsnz-004); a work item on a Sunday is useless |
| P2 | "haftaya salı" said on **Sat/Sun** | next calendar week → 2 days later (limitation 19) | many speakers mean 9 days (the "bu salı" is 2 days) | keep 02's value but add alternative chip "+7 gün" and drop confidence below auto-save on weekends (Q6) |
| P3 | "salı" said on a Tuesday morning | +7 days (limitation 18, wd-013) | 03 §5.7 says "today if not passed" | keep 02 (matches the user's "gelecek ilk salı"); card must show "6 Ekim Salı · 7 gün sonra" and offer chip "Bugün"; fix 03 §5.7 |
| P4 | "Acil: … Hakan'la konuş" | T9 undated task | 03 §5.8 #14: reminder + "Ne zaman?" | 03 wins (A4 fix 3) |
| P5 | "öğlen yemekten sonra ilacını al" (dp-003) | 12:00, "Yemekten sonra" left in title | after lunch | 13:00 (xtim-006); update dp-003 |
| P6 | "çok acil … hemen ara" (pri-009) | undated critical task | immediate | now + 5 min (xpri-001) |

### 6.3 The 40 proposed cases (`docs/design/parser_corpus_extra.json`)

Reference nows as in the main corpus plus **`mon_work` = Monday 2026-09-28 10:10**. Settings as in the main corpus plus proposed `hemenMinutes = 5`, `ogledenOnce = 11:00`. Case-level keys `status`, `gap`, `proposedRule`, `conflictsWith` are ignored by the §15 harness; new expected keys `leadMinutes` and `command.targetDate` require the proposed API fields.

| Id | now | Utterance | Expected |
|---|---|---|---|
| xeq-001 | sun | Hat 2'de konveyör hızını yarın ayarla | reminder "Hat 2'de konveyör hızını ayarla" · 28 Eyl 09:00 |
| xeq-002 | sun | İstasyon 5'te hava kaçağı var, cuma bakılsın | reminder "İstasyon 5'te hava kaçağı var bakılsın" · 2 Eki 09:00 |
| xeq-003 | mon_work | Pano 2'de klemens gevşek, yarın sabah baktır | reminder "Pano 2'de klemens gevşek baktır" · 29 Eyl 09:00 |
| xeq-004 | sun | 3 nolu robotun programını cuma yedekle | reminder "3 nolu robotun programını yedekle" · 2 Eki 09:00, conf ≥ 0.85 |
| xwai-001 | mon_work | Sürücüler perşembe gelecek | waiting "Sürücüler" · 1 Eki 09:00 · person null |
| xwai-002 | mon_work | Ahmet yarın haber verecek | waiting "Dönüş bekleniyor" · 29 Eyl 09:00 · Ahmet |
| xwai-003 | sun | Siemens'ten teklif bekliyoruz | waiting "Teklif" · Siemens |
| xwai-004 | mon_work | Mehmet test raporunu akşama kadar atacak | waiting "Test raporu" · 28 Eyl 19:00 · Mehmet |
| xwai-005 | sun | Elektrik projesini Hakan Bey paylaşacak | waiting "Elektrik projesi" · Hakan Bey · no project |
| xsnz-001 | sun | Teklif toplantısını perşembeye kaydır | snooze "teklif toplantısı" → 1 Eki 09:00 |
| xsnz-002 | sun | bunu yarına al | snooze (last item) → 28 Eyl 09:00 |
| xsnz-003 | sun | raporu pazartesiye taşı | snooze "raporu" → 28 Eyl 09:00 |
| xsnz-004 | fri_late | Kalibrasyon işini haftaya bırak | snooze "kalibrasyon işi" → 5 Eki 09:00 (P1) |
| xsnz-005 | sun | cuma günkü toplantıyı pazartesiye ertele | snooze "toplantı", targetDate 2 Eki → 28 Eyl 09:00 |
| xcnl-001 | sun | Hat 3 toplantısı iptal oldu | cancel "hat 3 toplantısı" · project Hat 3 |
| xcnl-002 | sun | boş ver onu | cancel (last item) |
| xcmp-001 | sun | sipariş formunu hallettik | complete "sipariş formu" |
| xcmp-002 | sun | PLC yedeğini aldık | complete "plc yedeği al" |
| xcmp-003 | sun | Mehmet'ten çizimler geldi | complete "mehmet çizimler" · Mehmet |
| xcmp-004 | sun | teklif gitti | complete "teklif" |
| xqry-001 | sun | neyi unuttum | query overdue (not a completion!) |
| xqry-002 | mon_work | bugün neyi kaçırdım | query overdue |
| xqry-003 | sun | yarın toplantım var mı | query tomorrow |
| xtim-001 | sun | yarın 4 gibi Ahmet'i ara | reminder "Ahmet'i ara" · 28 Eyl 16:00 |
| xtim-002 | sun | Salı sabahı Ahmet'le kalite toplantısı | reminder "Ahmet'le kalite toplantısı" · 29 Eyl 09:00 |
| xtim-003 | mon_work | öğleden önce sipariş formunu imzala | reminder "Sipariş formunu imzala" · 28 Eyl 11:00 |
| xtim-004 | mon_work | bugün içinde teklif revizyonunu gönder | reminder "Teklif revizyonunu gönder" · 28 Eyl 11:00 (today policy) |
| xtim-005 | sun | yarın 10'dan sonra Ahmet'i ara | reminder "Ahmet'i ara" · 28 Eyl 10:00 |
| xtim-006 | mon_work | öğle yemeğinden sonra Ahmet'i ara | reminder "Ahmet'i ara" · 28 Eyl 13:00 (P5) |
| xtim-007 | sun | bu gece vardiyada saat 3'te fırın sıcaklığını kontrol et | reminder "Vardiyada fırın sıcaklığını kontrol et" · 28 Eyl 03:00 |
| xcor-001 | sun | yarın 3'te hayır 4'te Ahmet'i ara | reminder "Ahmet'i ara" · 28 Eyl 16:00 |
| xcor-002 | sun | yarın değil öbür gün Hat 3 raporunu gönder | reminder "Hat 3 raporunu gönder" · 29 Eyl 09:00 |
| xpri-001 | sun | çok acil Ahmet Bey'i hemen ara | reminder "Ahmet Bey'i ara" · 27 Eyl 10:35 · critical (P6) |
| xpri-002 | mon_work | acil değil ama bu hafta Profinet adreslerini kontrol et | reminder "Profinet adreslerini kontrol et" · 2 Eki 09:00 · low |
| xlead-001 | sun | Perşembe 14'te ABB ile toplantı var, yarım saat önce hatırlat | reminder "ABB ile toplantı var" · 1 Eki 14:00 · lead [30] |
| xlead-002 | sun | 15 Ekim'de TIA Portal lisansı bitiyor, bir hafta önce hatırlat | reminder "TIA Portal lisansı bitiyor" · 15 Eki 09:00 · lead [10080] |
| xtech-001 | sun | Sürücü firmware'ini 4.20'ye güncelle | task, no due (not 16:20) |
| xtech-002 | sun | Teklifin son günü cuma | reminder "Teklifin son günü" · 2 Eki 09:00 (not 30 Eyl) |
| xrec-001 | sun | her 6 ayda bir kompresör filtrelerini değiştir | monthly ×6 day 27 · first 27 Mar 2027 09:00 |
| xrec-002 | sun | her ayın ilk pazartesi yönetim toplantısı | recurrence null, 5 Eki 09:00, conf ≤ 0.59 (review, never silently wrong) |

Further one-liners worth adding with the same rules (not in the JSON to keep it at 40): "cuma akşamı yedeklemeyi kontrol et" (G7), "yarın öğlen arası Hakan'ı ara" (G7), "cuma mesai bitimine kadar raporu teslim et" (G7), "24 volt beslemeyi yarın 2'de ölç" (G11 units), "Ahmet'e sor sürücüler geldi mi" (task, not note), "sırada ne var" (query today), "Mehmet'i ara, sipariş durumunu sor" (comma must not raise `multipleItems`).

---

## 7. Turkish copy (F)

| # | Where | Current | Problem | Proposed |
|---|---|---|---|---|
| F1 | 03 §4.10 `review.drop` | "Vazgeç (sil)" | "Vazgeç" means *cancel this dialog* everywhere else; here it deletes the item | "Sil" (red) — or "Gerek kalmadı" |
| F2 | `review.flag`, section "Kontrol edilecek", `compose.check` | "Kontrol et" | Collides with the most common task verb ("pano kontrol et") shown in the same row | badge "Emin değilim", section "EMİN OLAMADIKLARIM", compose button "Önizle" |
| F3 | `DinleIntent.title` | "Asist'i Dinlet" | reads "play Asist"; guides say "Asist Dinle" | "Asist Dinle" everywhere (A8) |
| F4 | `BugunIntent.title` / shortcut | "Bugün Neler Var?" / "Bugün" / 03 "Bugün Ne Var" | three names for one action | "Bugün Ne Var" |
| F5 | `INAlternativeAppNames` | "Asistan" | "${applicationName}'e" → "Asistan'e" | remove |
| F6 | EOD action | "Hepsini yarına taşı" | on Friday the move goes to Monday (`moveSkipsWeekend`), static action titles cannot change | "Sonraki iş gününe taşı" |
| F7 | `settings.volume_key.footer` | "Ses seviyesi iki kademe azalır." | contradicts D16 (volume restored) | "Ses seviyesi bir anlığına düşer, sonra eski haline döner." (only if restore verified on device; else keep) |
| F8 | `notif.fu.sub` | "Geldi mi? Son tarih: Cuma" | shown for default +2-workday follow-ups where he never said a deadline | "Geldi mi? · 2 gündür bekliyor"; "Son tarih" only for spoken deadlines |
| F9 | `notif.sub.last_today` | "Bugünlük son hatırlatma — yarın sabah brifingde tekrar göreceksin" | ~70 chars; lock-screen subtitle truncates ~40 | "Bugünlük son hatırlatma · yarın sabah yine" |
| F10 | `notif.sub.snoozed_many` | "%d. kez ertelendi — bugün olmayacaksa yeni gün seç" | too long, imperative | "%d. erteleme · başka bir gün mü?" |
| F11 | long-tail subtitle | "Hâlâ açık — “✓ Yaptım” diyene kadar her sabah soracağım" | truncates | "Hâlâ açık · her sabah soracağım" |
| F12 | TTS `spokenWhen` | "salı saat on beşte" | correct but military-sounding; he said "saat 3'te" | "salı öğleden sonra üçte", "yarın akşam sekizde", "yarın sabah dokuzda" (12-hour + daypart, unambiguous); screen stays 24 h |
| F13 | terminology | "Gecikenler" / "gecikmiş" / "Gecikmiş" | three forms across screen, briefing, 02 headers | "Geciken" everywhere ("2 geciken") |
| F14 | terminology | "Zamanı belirsiz" / "Zamansız görev" / "Tarihsiz" | three terms for one state | "Zamanı belirsiz" everywhere |
| F15 | label "Kişi" | person field also holds companies (Siemens, 02 limitation 6) | follow-up template becomes "Merhaba Siemens," | label "Kişi / Firma"; template greeting omits the name unless a person honorific/known person |
| F16 | sentinel | "Asist'i bir kez aç" / "Yaklaşan hatırlatmaları planlayabilmem için…" | generic, technical, ignorable | carries the item (B5): "<başlık> — +3 hatırlatma daha; planı tazelemek için Asist'i aç" |

---

## 8. Scope — too big for a first-ever compile (S)

The contract lists 29 in-scope features across 2 targets, well over 100 Swift files, 12 work packages, a widget extension with an App Group, CoreLocation geofencing, a Claude API client with structured outputs, and a 7-page onboarding — with no local compiler. Every compile error costs a macOS CI round-trip. More importantly, the **user value is concentrated in 6 things**: capture (voice/Siri/keyboard), correct dates, relentless-but-polite reminders, Today, done/snooze from the notification, data that never disappears.

### v1.0 "Çekirdek" (ship, install, live with it for 1–2 weeks)
Keep: AsistCore (parser + corpus, formatter, recurrence, NagPlanner **with the §1 fixes**, AgendaBuilder, NotificationCopy, ItemFactory, TurkishSpeech, DeepLink, model); DataStore + backups (+ A1 text export, B2 journal); notifications (scheduler, engine, categories, coordinator, BG refresh); PermissionCenter (notifications/mic/speech only); voice (listener, speaker, volume ×2 — the user's explicit request, even if foreground-only); CaptureService without Smart Mode; CommandExecutor (queries; complete/snooze by voice last in the order, drop if WP7 slips); Router; screens: Today, ListeningOverlay, ConfirmationSheet, ComposeSheet, AgendaAnswerSheet, Lists (+search), ItemDetail (no checklist/e-mail), Settings (Genel/Zamanlar/Israr/Özetler/Tetikleyiciler/Veri/Uygulama/Tanılama), Onboarding (3 pages); intents Kaydet/Dinle/Bugün/Gecikenler (all in the **app target**); SigningMonitor; projects as data + parser + a minimal Projeler list/editor (name + aliases).
Add (cheap, high value, low compile risk): mute window (A3), event profile + auto-close (A2), rate limiter (C2), lead-time parsing (A5), custom sounds (C5), undated → today (A4), "Sesle ertele" (D5), Son silinenler list (B8).

### v1.1 (after the core is validated on the device)
Widget extension + iOS 18 lock-screen/Control Center "Asist Dinle" control (best physical trigger on a 14 Pro Max, but the riskiest free-signing piece: 2nd App ID per install, App Group registration, extension signing); EOD card-by-card screen (v1.0: notification actions + Today filter); voice complete/cancel/snooze with fuzzy matching if not already in; checklist templates; person agenda UI; active project; auto-backup to a user-chosen folder; Smart Mode (parse fallback with the **fastest** model and ≤ 8 s timeout — a 25 s Opus round-trip contradicts "3 saniyede yakala"; Opus stays the default for e-mail drafts/summaries).

### v1.2 / v2
Location reminders (he never asked; permission friction; 10-slot budget), e-mail drafts, project summaries, AlarmKit for Kritik only (iOS 26, availability-gated — the real answer to "alarm", but only after the core is stable), Live Activity, calendar read.

Structural simplifications that fall out of the cut: one target only (no `Widgets/`, no `Shared/` — `DinleIntent` moves to `App/Intents/`), no App Group entitlement, no `SnapshotStore`/`WidgetSnapshotBuilder`, no `LocationService`/`NSLocationWhenInUseUsageDescription`, no `SmartMode*`/`KeychainStore`. WP8 shrinks to intents + signing, WP5 loses location, WP7 loses Smart Mode, WP10/WP11 lose ~9 views. Each Sideloadly install then consumes **1** App ID instead of 2.

---

## 9. Cross-document contradictions to resolve in 04 (X)

| # | Contradiction | Resolve as |
|---|---|---|
| X1 | 03 §5.7 "salı" on Tuesday = today; 02 + corpus wd-013 = +7 | 02 (P3); fix 03 text + card chip |
| X2 | 03 §5.7 "haftaya" alone = next Monday; 02 = +7 days | next week's first workday (P1); update day-008/009 |
| X3 | 03 guide A (Back Tap → Asist Dinle) vs 04 §3.7 recipe (Dikte Et → Asist'e Kaydet) | headless recipe primary (A8) |
| X4 | 03 §5.8 #14 reminder + "Ne zaman?" vs 02 T9 task | 03 (A4) |
| X5 | 03 §5.2 "volume does not come back" vs D16 restore | D16; fix copy F7 |
| X6 | 03 §4.11 "Sessiz modda sus" vs D18 "not implementable" | implementable via `.ambient` (A7) |
| X7 | 03 examples use 09:30 default (5.8 #6, #10) vs D11 09:00 | 09:00; fix 03 table and KULLANIM.md examples |
| X8 | Corpus `mesaiBitimi 17:30` vs app `workEnd 18:00` vs EOD 17:45 | fine for tests, but EOD candidates must exclude later-today items (B6) |
| X9 | 03 §3.9 "only the next 2 briefings" | 5 workday briefings (B3) |
| X10 | 03 treats events as P1 auto-close; 04 excludes it, yet 03 §5.8 #9/#27 are events | v1 event profile (A2) |
| X11 | 03 §3.14 "relative items use absolute duration" vs 04 §3.6.5 (only < 60 s) | B10 |

---

## 10. Open questions for the user (Q)

1. **Ücretli Apple Developer (yıllık ~99 $)** kabul edilebilir mi? 7 günlük imza riskini (A1) tamamen kaldırır, zamana duyarlı bildirimleri açar.
2. İş bilgisayarı gün boyu açık ve iPhone aynı Wi-Fi'da mı? (Sideloadly otomatik yenileme)
3. İşte Odak / Rahatsız Etme kullanıyor musun? Toplantıda Asist'in susmasını mı, titreşimle devam etmesini mi istersin?
4. Toplantı kayıtları: başlangıçta tek bildirim + 15 dk önce yeterli mi (ısrar yok)?
5. "Acil" dediğinde her 15 dakikada bir mi (Kritik), yoksa 5/15/30/60 dk + saatte bir mi (Önemli)?
6. Pazar günü "haftaya salı" dersen 2 gün sonrası mı, 9 gün sonrası mı? "Haftaya" tek başına = gelecek pazartesi mi?
7. Mesai sonrası (18:00–22:30) iş hatırlatmaları evde de gelsin mi?
8. Saatsiz söylediğin işler otomatik "Bugün" listesine girsin mi (gün içinde çalmadan, akşam gün sonunda sorulur)?
9. Hitap: "Gökhan" / "Gökhan Bey" / isimsiz? Cumartesi iş günü mü?
10. Akıllı Mod (kendi Claude API anahtarın) v1.1'de gerekli mi, yoksa tamamen çıkarılsın mı?
