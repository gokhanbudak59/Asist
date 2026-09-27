# 04 — Architecture Contract (single source of truth for v1.0 "Çekirdek", with the v1.1+ backlog in Appendix B)

| Field | Value |
|---|---|
| Project | **Asist** — native iOS voice assistant for an automation manager (all UI/voice text Turkish) |
| Date | 2026-09-27 (Sunday), Europe/Istanbul — revision 2 (critiques 05a + 05b applied, see §12) |
| Status | **Binding.** Supersedes any conflicting detail in 01a / 01b / 01c / 02 / 03 / 05a / 05b / 06 (see §0.3). Critique items not adopted are listed with reasons in §11. |
| Toolchain | iOS deployment target **17.0**, device iPhone 14 Pro Max on iOS 26, CI Xcode **26.x** (macos-26 runner), **Swift language mode 5**, `SWIFT_STRICT_CONCURRENCY = minimal`, XcodeGen 2.46.0 |
| Verification | No local compiler. The only compiler is CI (Linux `swift test` for AsistCore + macOS `xcodebuild`). Every rule below exists to make the **first CI build** succeed. |

## 0. How to use this document

### 0.1 Reading order for an engineer

1. §0.3 decision log (what changed versus the research docs).
2. §2 file tree — find **your work package (WP)** and the files you own.
3. §3 contracts — the exact Swift you code **against**. Never change a signature in §3 on your own; request a change from the orchestrator (WP0).
4. §4 concurrency/error/logging rules and §9 compile-hazard checklist — mandatory before every push.
5. The research doc sections referenced from your WP in §8 (they contain verified API signatures and ready code).
6. §11 (critique items deliberately **not** adopted) and §12 (what changed in revision 2) — read them before arguing with a rule.
7. Appendix B holds the binding design of features deferred to v1.1/v1.2. **Nothing in Appendix B is compiled in v1.0**; no v1.0 file may reference its types.

### 0.2 Normative words

- **MUST / MUST NOT** — a CI or runtime failure is likely otherwise.
- **SHOULD** — default; deviate only with a comment `// DEVIATION(04 §x.y): reason`.
- Code blocks titled `// FILE: <path>` are **exact file contents** (WP0 writes them verbatim first; afterwards the owner listed in §2 maintains them, and any signature change goes through WP0). Blocks titled `// API: <path>` are **signatures the owner must implement exactly** — they are declarations, not compilable text (bodies omitted); WP0 ships a compiling stub with minimal behaviour. **Exception:** `// FILE:` / `// API:` blocks inside Appendix B are written only when that deferred feature's WP starts (never in v1.0).

### 0.3 Decision log (conflict resolution across the research docs and critiques)

| # | Topic | Decision (binding) | Overrides |
|---|---|---|---|
| D1 | Persistence | One JSON file `AppData` in the **app's own** `Application Support/Asist/` (atomic write, `completeUntilFirstUserAuthentication`). No SwiftData/CoreData. **v1.0 has no App Group** (no widget target, D30); v1.1 adds the App Group only for the disposable widget snapshot (Appendix B.4). | 01a/01b open question |
| D2 | App state observation | `@Observable` (Observation framework, iOS 17) for all app-state classes. `ObservableObject`/`@Published` are **not used anywhere**. 01b's `SpeechListener`, `Speaker`, `VolumeButtonTrigger` become plain `@MainActor final class`es reporting through closures; `VoiceCoordinator` is the only observable voice object. | 01b §1.7, §2.1, §3.3, §3.4 |
| D3 | Engine isolation | `ReminderEngine`, `NotificationScheduler` are `@MainActor final class` (not `actor`) with **task-chain serialization** of `reconcile` (01a §5.6 pattern kept). | 01a §5.4, §5.6 |
| D4 | Notification identifiers | Scheme `asist.i.<UUID>.<k>` etc. (§6.1). | 01a `asist.r.*`, 03 `item-<uuid>-n<k>` |
| D5 | Notification actions | **Max 4 actions per category** (03 §3.3). The text-input "Başka zaman" action from 01a is **dropped**. Pre-alerts use their own category `ASIST_PRE` with only "✓ Yaptım", so a pre-alert can never re-anchor the item (05a #13). | 01a §2.3 |
| D6 | Nag policy | Priority-based profiles **Nazik / Israrcı / Bırakmaz** + **Takip** + **Etkinlik** (events: first alert only). Continuity **without any app activity** is guaranteed by (§6.4): the per-item chain window **plus a 3-day day-tail**, a daily repeating **long-tail for high/critical items** (≤ 5, staggered), **recurrence carriers** (repeating triggers), **5 workday briefings** that list overdue titles, a **content-bearing budget sentinel** and a **horizon sentinel**. A global **rate limiter** and a user **mute window** keep it bearable. | 01a §5.2 single policy; 03 §3.4 |
| D7 | Default priority→profile | low→Nazik, normal→Nazik (re-tuned: +10/+30/+90 min, then every 2 h **inside work hours only**), high→Israrcı (hourly inside work hours, **no evening repeats**), critical→Bırakmaz, waiting→Takip, event→Etkinlik. Spoken "acil/acilen/önemli/mutlaka" = **high**; only "çok acil / kritik / hayati / sakın unutma / asla unutma" = **critical** (§3.4.6). User-changeable per priority in Settings; per-item override in detail. | 01a "Israrcı for all"; 02 §7.8 |
| D8 | Budget | 64 total = **14 reserved** (5 briefings, 1 end-of-day, 1 weekly backup reminder, 4 signing (3 warnings + 1 expiry notice), 1 budget sentinel, 1 horizon sentinel, 1 spare for unmanaged test/feedback) + **50 item slots**. (v1.2 location requests will be subtracted from the item slots.) | 01a (60+4), 03 (56+8), rev. 1 (8 reserved) |
| D9 | Background task id | `com.gokhanbudak.asist.refresh` (registered manually in `AppDelegate`). | 01c `…yenile` |
| D10 | Confidence thresholds | `≥ 0.80` auto-save (4 s countdown), `0.60 ..< 0.80` confirm (6 s countdown), `< 0.60` review (no auto-save). | 03 §5.5 (0.55) |
| D11 | Default time for a day without time | **09:00** (`AppSettings.defaultDayTime`). 03 examples showing 09:30 are wrong (05b X7). | 03 §4.11 (09:30) |
| D12 | AlarmKit | **Excluded from v1.x** (research rates the API "medium" compile risk). v2 candidate for Kritik only (Appendix B.5). No `NSAlarmKitUsageDescription`, no `ASIST_ALARMKIT` flag. | 01a D8 |
| D13 | Live Activities / widget "Tamam" button | **Excluded.** Home/lock-screen widgets and the Control Center control are **v1.1** (Appendix B.4). | 01b §4.9, 01c |
| D14 | Deep links | `asist://dinle[?tur=…&proje=<uuid>]`, `asist://yaz`, `asist://bugun`, `asist://kayit/<uuid>[?eylem=yaptim]`, `asist://gunsonu`, `asist://oku`, `asist://ayarlar/tetikleyiciler`. All are handled in v1.0 (Shortcuts can use them); widgets reuse them in v1.1. | 03 `oge` |
| D15 | Smart Mode (Claude API) | **Deferred to v1.1** (Appendix B.2 keeps the binding design: default `claude-opus-5` + `fallbacks: "default"`, options `claude-sonnet-5`, `claude-haiku-4-5`, no date suffixes). The `smartMode*` fields stay in `AppSettings` (forward compatible, unused in v1.0). | brief, 02 §14, 03 |
| D16 | Volume ×2 trigger | Foreground only (01b §3). **Restores the previous volume by default** (setting `restoreVolumeAfterTrigger`, default on). Armed only in `sceneDidBecomeActive` while the app is active (05a #25). | 03 §5.2 "does not restore" |
| D17 | Signing-expiry warnings | Planned by `NagPlanner` (single writer, IDs `asist.sign.<minuteKey>`): **every** date of `SigningExpiryPlanner.warningDates` (48 h / 24 h / 4 h, night-shifted) **plus one "imza doldu" notice at expiry + 1 min**. Planned **only when the embedded profile is readable** (no estimate-based planning, 05a #28). One-shot follow-up nags after `expiry − 5 min` are not planned (05b A1). `SigningMonitor.reload()` runs in every process before the first reconcile (05a #4). | 01c §4.4, rev. 1 (next 2) |
| D18 | Spoken confirmations | The ring/silent switch cannot be read. Confirmations are spoken **only on a private audio route** (headphones, Bluetooth, CarPlay, USB audio) unless `speakConfirmationsOnSpeaker` (default **off**); otherwise toast + haptic. Query answers ("bugün ne var") are always spoken. | 03 §4.11, rev. 1 |
| D19 | Listening timeouts | no-speech 6 s, silence-after-speech 1.8 s (setting 1.2/1.8/2.5/3.5), hard cap 45 s. Speech-activity threshold adapts to the **noise floor measured in the first 300 ms** (05b A6). | 01b 7 s / 55 s |
| D20 | Reminder without any time | Interactive (app): card asks "Ne zaman?" (`noTimeBehavior = .ask`); if the card is closed without answer → +1 h. Headless (Siri/Shortcut): applies `.inOneHour` when behavior is `.ask`. **Also applies to high/critical tasks without a date** ("Acil: Hakan'la konuş", 05b A4/P4). | 02 T9 |
| D21 | Waiting-for (Takip) without date | `dueDate` = +2 **workdays** at **10:00** (settings) with `hasTime = false` (copy then says "n gündür bekliyor", never an invented "Son tarih"). Parser leaves it nil; `ItemFactory` applies it. | 02 open question |
| D22 | Siri voice complete/cancel/snooze | Not in v1: headless path answers "Bunun için Asist'i açman gerekiyor." and queues `PendingAction`. | 03 §5.10 |
| D23 | `BugunIntent` authentication | `.alwaysAllowed` (the default; no code line). | 01b §4.8 |
| D24 | Corpus in tests | Read `docs/design/parser_corpus.json` **and** `docs/design/parser_corpus_extra.json` through `#filePath` (single copy, no SwiftPM resources). Gate rules §3.4.6. | 02 §15, 01c L9 |
| D25 | Info.plist | Only keys for features in v1.0 scope (§7.1). No location key, **no `INAlternativeAppNames`** ("Asistan'e" breaks vowel harmony, 05b F5). `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so backups are visible in the Files app. | 01c §1.2 |
| D26 | Categories vs lock-screen privacy | One category set; it is **re-registered** when `lockScreenShowsContent` changes. No "_PRIVATE" duplicates. | 01a §7.2 |
| D27 | Recurring items | Only the current occurrence nags. Future occurrences are carried by **repeating requests** (daily / weekly per weekday / monthly day 1…28, interval 1) whenever the rule's next fire equals the item's next occurrence (or its current, un-snoozed due); otherwise by one-shot k = 0 of the **next 7 occurrences** (≤ 14 days; the first one beyond 14 days as tier 4). `ReminderEngine` rolls an open recurring item forward to the latest occurrence ≤ now on every reconcile and before every notification action (history `occurrenceMissed`). | 01a §5.2, 03 §3.13, rev. 1 (next 2) |
| D28 | Localization | No `Localizable.strings`/String Catalog. Turkish text literals inline (copy from 03 §7.12 **as amended by §5.5**). Only `App/Resources/tr.lproj/AppShortcuts.strings` exists. Uppercase section titles are literals (`"GECİKENLER"`), never `.uppercased()`. | 03 §7.12 keys are copy only |
| D29 | Time zone | AsistCore functions always take an injected `Calendar`. The app uses `AppTime.calendar` = Gregorian, **device time zone** (`.autoupdatingCurrent`), Monday-first, `en_US_POSIX` locale. Tests use `TurkishParser.defaultCalendar()` (Europe/Istanbul). | — |
| D30 | Staged scope | **v1.0 "Çekirdek"** = one app target (no extension, no App Group, no CoreLocation, no Smart Mode). v1.1 = widgets + Control, Smart Mode, active project, backup to a chosen folder, before-first-unlock journal. v1.2 = location reminders. v2 = AlarmKit (Kritik), Live Activity. Each Sideloadly install of v1.0 consumes **1** App ID. | rev. 1 §1 (29 features, 2 targets) |
| D31 | Events | Items whose title's head noun is an event noun (toplantı, görüşme, randevu, ziyaret, sunum, eğitim, denetim, FAT, SAT, …) and that have a time get `isEvent = true`: first alert + default 15 min pre-alert, **no nag chain**, never overdue, **auto-closed 120 min after start**. Card chip / detail toggle "Etkinlik" overrides. | rev. 1 §1.2 (excluded) |
| D32 | Mute | `AppSettings.muteUntil`: nags inside the window collapse into one at `muteUntil`; first alerts inside it are delivered silently (critical first alerts and signing warnings keep their sound). Today toolbar menu 30 dk / 1 saat / 2 saat / Mesai sonuna kadar. | rev. 1 §1.2 (excluded) |
| D33 | Nothing captured is silent | Voice/keyboard/Siri tasks without a date default to **today, untimed** (`hasTime = false`; card chips Bugün / Yarın / Zamanı belirsiz). The parser's T10 "no cue" note fallback becomes a **task** (`needsReview` when headless). "hemen/şimdi/derhal" = now + 5 min. Spoken lead times ("yarım saat önce hatırlat") become pre-alerts. | 02 T9/T10, rev. 1 row 24 |
| D34 | Headless completeness | Every entry point after which the process may be suspended (App Intent `perform`, notification action `handle`, BG task, `sceneDidEnterBackground`) **awaits** `engine.reconcile` after its last mutation; `requestReconcile` is only for foreground UI bursts. Notification actions additionally replace the acted-on item's pending requests **before** `completionHandler()` (05a #1, #7; 05b B1). | rev. 1 |
| D35 | Data written by a newer build | `AppMeta.writerBuild` = `CFBundleVersion` of the writer (CI sets `CURRENT_PROJECT_VERSION = run_number`). An older build that finds a newer file keeps a copy in `Yedekler` before its first save and shows a red banner (05a #10). The date strategy `.iso8601` (whole seconds) is frozen forever. | — |
| D36 | Parser amendments | 05b gap classes G1–G12 and decisions P1–P6 are adopted as binding amendments to 02 (§3.4.6); the 40 cases of `parser_corpus_extra.json` join the gate. | 02, corpus day-008/009, dp-003, pri-009 |
| D37 | Notification sounds | Two bundled WAVs generated by `Tools/make_sounds.py`: `asist-onemli.wav` (~6 s) and `asist-kritik.wav` (~12 s) for high/critical first alerts and every 3rd nag; everything else `.default`. A missing file silently falls back to the default sound. | rev. 1 §1.2 (excluded) |

---

## 1. Scope

The user value is concentrated in six things: **capture** (voice / Siri / keyboard) with correct dates, **relentless-but-polite reminders that keep going without the app being opened**, the **Today** screen, **done/snooze from the notification**, **data that never disappears**, and a few automation-manager helpers (projects, Takip, checklists, spoken agenda). v1.0 ships exactly that in **one app target**; everything else is staged (D30).

### 1.1 v1.0 "Çekirdek" — in scope

| # | Feature | Source | Notes |
|---|---|---|---|
| 1 | In-app voice capture (SFSpeechRecognizer tr-TR) + listening overlay + confirmation card with auto-save/undo | 01b §1, 03 §4.4–4.5 | noise-floor adaptive silence detection (D19); contextual strings = jargon + projects + frequent people |
| 2 | Rule-based Turkish parser (AsistCore) with 371-case corpus + 40 extra cases gate | 02, §3.4.6 | amendments G1–G12, P1–P6 |
| 3 | Keyboard entry ("Yaz") with live preview | 03 §4.6 | button "Önizle" (05b F2) |
| 4 | Local notifications: profiles, actions, snooze, badge, sentinels, rate limiter, mute window, custom sounds | 01a, 03 §3, §6 | D6, D32, D37 |
| 5 | Durable local storage: atomic writes, prev-file, daily backups (7), corrupt/partial recovery, newer-writer guard, readable `Asist-acik-isler.txt` | §3.6.4 | D35, 05b A1 |
| 6 | Today screen (overdue hero card, emin olamadıklarım, today, takip, upcoming, zamanı belirsiz) + mute menu | 03 §4.3 | |
| 7 | Lists (filters, search, sort) + item detail + edit + "Sesle ertele" | 03 §4.7–4.8, 05b D5 | |
| 8 | Takip (waiting-for) items, "Geldi mi?" notifications, follow-up message via `ShareLink` | 03 §3.4 r4, §4.8 | |
| 9 | Projects with aliases + project notes ("Bu projeye sesli not") | 03 §4.9 | active project = v1.1 |
| 10 | Recurrence (daily / weekdays / weekly set / monthly day / every N months / yearly) with repeating carriers | 02 §9, D27 | |
| 11 | Morning briefing (next 5 workdays, lists overdue titles), end-of-day notification + simple EOD list + "Sonraki iş gününe taşı" | 03 §3.9–3.10 | card-by-card EOD flow = v1.1 |
| 12 | Spoken queries + TTS agenda ("bugün ne var", "neyi unuttum", "Ahmet'le ilgili ne var") | 03 §5.9 | |
| 13 | Voice complete / cancel / snooze / reschedule ("perşembeye kaydır") with fuzzy matching + confirmation | 03 §5.10, G3–G5 | last WP7 item; may slip to v1.1 without blocking release |
| 14 | Siri App Shortcuts: "Asist'e Kaydet" (background), "Asist Dinle", "Bugün Ne Var", "Gecikenler" — all in the app target | 01b §4, 03 §5.11 | |
| 15 | Back Tap guides: **headless** "Asist Hızlı Kayıt" (Dikte Et → Asist'e Kaydet) is guide A; "Asist Dinle" (opens app) is guide A-alt | 01b §4.13, 05b A8 | |
| 16 | Volume-down ×2 (foreground) | 01b §3 | D16 |
| 17 | Settings (work hours, quiet hours, profiles per priority, summaries, triggers, data, status, diagnostics) | 03 §4.11 | profile *parameters* not editable |
| 18 | Onboarding (**3 pages**) + test notification + "Kalıcı" banner-style tip | 03 §4.12, 05b A9/A10 | |
| 19 | JSON export / import (merge / replace, security-scoped) + "Son silinenler" list | 03 §4.11, 05b B8 | |
| 20 | Signing-expiry warnings + expiry notice + banner + Settings row | 01c §4, D17 | |
| 21 | Edge-case banners + Diagnostics screen (pending list, last reconcile, log) | 01a §7.5, 03 §9 | |
| 22 | Pre-alerts: spoken ("yarım saat önce hatırlat", "bir hafta önce") and via detail menu; deadline pre-alerts | 03 §6.1, G10 | category `ASIST_PRE` |
| 23 | Events (toplantı / görüşme / ziyaret / FAT …): first alert + 15 min pre-alert, no nags, auto-close | 05b A2, D31 | |
| 24 | Mute window "Sessize al" | 05b A3, D32 | |
| 25 | Checklist templates FAT / SAT / Devreye alma / Saha ziyareti / Toplantı hazırlığı | 03 Ek A | kept (see §11 R4) |
| 26 | Daily automatic backup in Files (7 kept) + human-readable open-items file | 03, 05b A1 | |

### 1.2 v1.1 (after v1.0 has been used on the device for 1–2 weeks; design in Appendix B)

Widget extension + iOS 18 lock-screen/Control Center "Asist Dinle" control (App Group, 2nd App ID) · Akıllı Mod (Claude API: low-confidence interpretation, e-mail draft, project-notes summary) · active project · card-by-card end-of-day screen · person agenda UI beyond spoken answers · "Sesle düzelt" for titles · weekly backup to a user-chosen folder (security-scoped bookmark) and a "Dosyalar'a kaydet" backup action · before-first-unlock event journal (05b B2) · relative-duration items across time zones (05b B10) · "n'th weekday of month" recurrence (`weekOrdinal`) · dismissal-aware nag pull-forward (05b C1 optional part) · `.ambient` confirmations honouring the silent switch.

### 1.3 v1.2 / v2 backlog

v1.2: location reminders (`UNLocationNotificationTrigger`, Places, Appendix B.3). v2: AlarmKit alarms for Kritik only (iOS 26, availability-gated) · Live Activities / Dynamic Island · batched nag digests · weekly summary · editing nag-profile parameters · duplicate-entry warning · multi-item utterances · EventKit calendar read · Contacts · photo attachments · SpeechAnalyzer (iOS 26) · share extension · Face ID lock · holiday names in parser.

**Impossible with free signing / iOS (never planned):** iCloud, push, critical alerts, time-sensitive entitlement, background volume-button detection.

---

## 2. Repository tree (every v1.0 file, owner work package, responsibility)

Root: `C:\ClaudeProjects\Asist` (git repo root). Paths below are relative to it. **Every directory listed as a source path in `project.yml` must contain at least one `.swift` file** (XcodeGen fails on missing paths; git does not store empty dirs). v1.0 has exactly one source root: `App/`. Files of v1.1+ features are listed in Appendix B and MUST NOT be created in v1.0.

### 2.1 Root, CI, tools, docs

| Path | WP | Responsibility |
|---|---|---|
| `project.yml` | WP0 | XcodeGen spec — final content §7.3 (single target) |
| `.gitignore` | WP0 | verbatim 01c §5 |
| `.gitattributes` | WP0 | verbatim 01c §5 (LF for `.sh/.yml/.swift/.py/.json/.plist/.strings/.md`; add `*.strings text eol=lf`, `*.md text eol=lf`, `*.wav binary`, `*.png binary`) |
| `.github/workflows/ci.yml` | WP0 | verbatim 01c §2.6 (it already passes `CURRENT_PROJECT_VERSION=${{ github.run_number }}`, which D35 relies on) |
| `Scripts/ci/select-xcode.sh` | WP0 | verbatim 01c §2.2 |
| `Scripts/ci/install-xcodegen.sh` | WP0 | verbatim 01c §2.3 |
| `Scripts/ci/package-ipa.sh` | WP0 | **v1.0 variant, exact §7.5** (no extension, no entitlements, App Intents metadata check) |
| `Scripts/ci/error-summary.sh` | WP0 | verbatim 01c §2.7 |
| `Tools/make_app_icon.py` | WP0 | verbatim 01c §1.7 (run locally with Python 3.14; commit the PNG) |
| `Tools/make_sounds.py` | WP0 | exact §7.6: stdlib-only generator of the two notification WAVs (D37), 44.1 kHz mono 16-bit, `asist-onemli.wav` 6 s, `asist-kritik.wav` 12 s; run locally, commit the WAVs |
| `docs/KURULUM.md` | WP11 | Turkish install + weekly re-sign ritual (01c §3.3–3.5 + 05b A1: "Her Pazartesi 08:30 iş bilgisayarında Sideloadly ile yenile", Sideloadly auto-refresh, "yeniledikten sonra Asist'i bir kez aç", check that the Sideloadly log shows bundle id `com.gokhanbudak.asist` — never install a changed id) + first-run checklist (notifications "Kalıcı", Focus, Back Tap) |
| `docs/KULLANIM.md` | WP11 | Turkish user manual: example sentences (03 §5.6–5.8 with D11 09:00), triggers, nag behaviour incl. mute/events, backups and `Asist-acik-isler.txt` |
| `docs/design/*` | — | research + this contract (read-only for WPs, **except** WP1 may edit the corpus cases named in §3.4.6) |

### 2.2 `Packages/AsistCore` (pure Foundation; compiles on Linux and iOS)

AsistCore MUST NOT import SwiftUI, UIKit, UserNotifications, AVFoundation, Speech, CoreLocation, AppIntents, WidgetKit, Combine, Observation, os. Darwin-only Foundation APIs go inside `#if canImport(Darwin)`.

| Path (under `Packages/AsistCore/`) | WP | Responsibility |
|---|---|---|
| `Package.swift` | WP0 | verbatim 01c §1.8 (tools 5.9, iOS 17 / macOS 14, library `AsistCore`, test target `AsistCoreTests`, **no resources**) |
| `Sources/AsistCore/AsistCore.swift` | WP0 | `AsistCoreInfo.version` |
| `Sources/AsistCore/Model/Codable+Lenient.swift` | WP0 | `KeyedDecodingContainer.lenient…`, `LossyDecodableArray` (§3.2.1) |
| `Sources/AsistCore/Model/Enums.swift` | WP0 | `ItemKind, ItemStatus, Priority, PlaceTrigger, CaptureSource, NagProfileKind, BadgeMode, NoTimeBehavior, TTSRate, HistoryEvent, ProjectColor` (§3.2.2) |
| `Sources/AsistCore/Model/ClockTime.swift` | WP0 | `ClockTime` (§3.2.3) |
| `Sources/AsistCore/Model/Recurrence.swift` | WP0 | `Recurrence` (§3.2.4) |
| `Sources/AsistCore/Model/NagProfile.swift` | WP0 | `NagProfile`, `NagProfiles` (§3.2.5) |
| `Sources/AsistCore/Model/Item.swift` | WP0 | `Item`, `ChecklistEntry`, `HistoryEntry` (§3.2.6) |
| `Sources/AsistCore/Model/Item+Logic.swift` | WP0 | anchor/overdue/event/profile helpers (§3.2.7) |
| `Sources/AsistCore/Model/Project.swift` | WP0 | `Project`, `Place` (§3.2.8; `Place` is data-only in v1.0) |
| `Sources/AsistCore/Model/AppSettings.swift` | WP0 | `AppSettings` with all defaults and decode clamps (§3.2.9) |
| `Sources/AsistCore/Model/AppData.swift` | WP0 | `AppData`, `AppMeta`, `MoveRecord`, `UndoToken` (§3.2.10) |
| `Sources/AsistCore/Model/ChecklistTemplates.swift` | WP2 | 5 templates from 03 Ek A (§3.5.6) |
| `Sources/AsistCore/Util/AsistCalendar.swift` | WP0 | calendar factory, ISO weekday, day keys, minute rounding, workdays (§3.3.1) |
| `Sources/AsistCore/Util/StableHash.swift` | WP0 | FNV-1a 64 (§3.3.2) |
| `Sources/AsistCore/Text/TurkishText.swift` | WP0 | locale-free lower/upper/fold/search key/truncate (§3.3.3) |
| `Sources/AsistCore/Text/TurkishDateFormatter.swift` | WP1 | 02 §13 formatter (API §3.4.4) |
| `Sources/AsistCore/Text/TurkishSpeech.swift` | WP2 | spoken numbers, locative suffixes, 12-hour daypart times, TTS/dialog sentences (API §3.5.4) |
| `Sources/AsistCore/Parser/ParserTypes.swift` | WP0 | public parser types, reconciled with Model (§3.4.1) |
| `Sources/AsistCore/Parser/ParserSettings+App.swift` | WP0 | `ParserSettings(settings:projects:places:people:)`, `frequentPeople` (§3.4.2) |
| `Sources/AsistCore/Parser/TurkishParser.swift` | WP1 | `TurkishParser` orchestration (API §3.4.3; WP0 ships stub) |
| `Sources/AsistCore/Parser/Normalizer.swift` | WP1 | 02 §3 |
| `Sources/AsistCore/Parser/Tokenizer.swift` | WP1 | 02 §4 |
| `Sources/AsistCore/Parser/Lexicon.swift` | WP1 | 02 §5, §7.8, §10 tables + §3.4.6 amendments (folded keys, `static let`) |
| `Sources/AsistCore/Parser/TurkishNumbers.swift` | WP1 | 02 §6 |
| `Sources/AsistCore/Parser/Extractors/ProjectPlaceExtractor.swift` | WP1 | 02 §7.2–7.3 |
| `Sources/AsistCore/Parser/Extractors/RecurrenceExtractor.swift` | WP1 | 02 §9.1 + G12 |
| `Sources/AsistCore/Parser/Extractors/DateExtractor.swift` | WP1 | 02 §8.3 inputs + G7/G9 |
| `Sources/AsistCore/Parser/Extractors/TimeExtractor.swift` | WP1 | 02 §6.3 + G1/G7/G11 |
| `Sources/AsistCore/Parser/Extractors/PersonExtractor.swift` | WP1 | 02 §7.9 + G2 |
| `Sources/AsistCore/Parser/Extractors/CueExtractor.swift` | WP1 | 02 §7.1, §7.8, §10 cues + G2–G6 |
| `Sources/AsistCore/Parser/Extractors/LeadTimeExtractor.swift` | WP1 | G10 (`leadTimesMinutes`) |
| `Sources/AsistCore/Parser/DateResolver.swift` | WP1 | 02 §8, §9.3 + P1–P3, G8 corrections |
| `Sources/AsistCore/Parser/Classifier.swift` | WP1 | 02 §10 + G6 ordering |
| `Sources/AsistCore/Parser/TitleBuilder.swift` | WP1 | 02 §11 |
| `Sources/AsistCore/Parser/Confidence.swift` | WP1 | 02 §12 |
| `Sources/AsistCore/Planning/RecurrenceEngine.swift` | WP1 | occurrences (API §3.4.5; WP0 stub) |
| `Sources/AsistCore/Planning/NotificationCatalog.swift` | WP0 | IDs, categories, actions, userInfo keys (§3.5.1) |
| `Sources/AsistCore/Planning/PlannedNotification.swift` | WP0 | `PlannedNotification`, `PlanInput`, `PlanResult` (§3.5.2) |
| `Sources/AsistCore/Planning/NagPlanner.swift` | WP3 | `NagPlanner` (API §3.5.3; WP0 stub) |
| `Sources/AsistCore/Planning/NagChain.swift` | WP3 | chain generation, quiet/work-hour/mute math (internal) |
| `Sources/AsistCore/Planning/PlanPostPass.swift` | WP3 | signing clamp, rate limiter, tiers/budget, sentinels (internal) |
| `Sources/AsistCore/Agenda/AgendaBuilder.swift` | WP2 | sections, spoken answers, briefing/EOD text, open-items text (API §3.5.5) |
| `Sources/AsistCore/Agenda/NotificationCopy.swift` | WP2 | title/subtitle/body of every notification (API §3.5.5) |
| `Sources/AsistCore/Matching/FuzzyMatcher.swift` | WP2 | voice complete/cancel/snooze matching (API §3.5.5) |
| `Sources/AsistCore/Capture/ItemFactory.swift` | WP2 | `ParseResult → CaptureProposal`, defaults, event detection (API §3.5.6) |
| `Sources/AsistCore/Links/DeepLink.swift` | WP0 | `asist://` URLs (§3.5.7) |
| `Sources/AsistCore/Platform/ProvisioningProfile.swift` | WP0 | verbatim 01c §4.1 |
| `Sources/AsistCore/Platform/AppGroupResolver.swift` | WP0 | verbatim 01c §4.2 (tested by `PlatformTests`; unused by the v1.0 app) |
| `Sources/AsistCore/Platform/SigningExpiryPlanner.swift` | WP0 | verbatim 01c §4.3 |
| `Tests/AsistCoreTests/TestSupport.swift` | WP0 | `TestClock` helpers, corpus URLs via `#filePath` (§3.3.4) |
| `Tests/AsistCoreTests/PlatformTests.swift` | WP0 | verbatim 01c §4.5 |
| `Tests/AsistCoreTests/TurkishTextTests.swift` | WP0 | trLower/fold/searchKey cases from 02 §3 |
| `Tests/AsistCoreTests/ModelCodingTests.swift` | WP4 | round trip, forward compatibility (unknown keys/enum values, missing fields, corrupt array element), decode clamps (§3.2.9, §3.2.4) |
| `Tests/AsistCoreTests/CorpusTests.swift` | WP1 | 02 §15 harness over both corpus files (§3.4.6 gate) |
| `Tests/AsistCoreTests/NormalizerTests.swift` | WP1 | 02 §18 |
| `Tests/AsistCoreTests/NumberTests.swift` | WP1 | 02 §18 |
| `Tests/AsistCoreTests/DateResolverTests.swift` | WP1 | 02 §8 tables + P1–P3 |
| `Tests/AsistCoreTests/FormatterTests.swift` | WP1 | 02 §13 examples |
| `Tests/AsistCoreTests/RecurrenceEngineTests.swift` | WP1 | month-end, leap year, interval 2, "her 6 ayda bir" |
| `Tests/AsistCoreTests/ParserPropertyTests.swift` | WP1 | 02 §18 property tests |
| `Tests/AsistCoreTests/NagPlannerTests.swift` | WP3 | §6.4 required tests (chains, continuity, carriers, sentinels, rate limiter, mute, signing clamp, budget, IDs, fingerprints) |
| `Tests/AsistCoreTests/AgendaBuilderTests.swift` | WP2 | sections, spoken text, briefing (overdue titles), EOD candidates (05b B6), open-items text |
| `Tests/AsistCoreTests/TurkishSpeechTests.swift` | WP2 | suffix table 03 §5.12, 12-hour daypart phrases, `dialogSafe` |
| `Tests/AsistCoreTests/FuzzyMatcherTests.swift` | WP2 | 03 §5.8 rows 24–26 |
| `Tests/AsistCoreTests/ItemFactoryTests.swift` | WP2 | D20/D21/D33 defaults, event detection, levels D10 |
| `Tests/AsistCoreTests/DeepLinkTests.swift` | WP8 | URL round trips |

### 2.3 `App/` — target **Asist** (application, the only target). Compilation condition `ASIST_APP`.

| Path | WP | Responsibility |
|---|---|---|
| `App/AsistApp.swift` | WP0 (exact §3.6.1) | `@main struct AsistApp` |
| `App/AppDelegate.swift` | WP0 (exact §3.6.1) | notification delegate, BG registration, `AppEnvironment.bootstrap()` |
| `App/AppEnvironment.swift` | WP0 | composition root singleton (§3.6.2, exact) |
| `App/Support/AsistLog.swift` | WP0 | `os.Logger` + in-memory ring buffer (§3.6.3, exact) |
| `App/Support/Haptics.swift` | WP0 | feedback generators (§3.6.3, exact) |
| `App/Support/AppTime.swift` | WP0 | app calendar (§3.6.3, exact) |
| `App/Store/StoreFiles.swift` | WP4 | file URLs (§3.6.4) |
| `App/Store/DataStore.swift` | WP4 | `@Observable` store incl. `ImportPreview`/`ImportMode` declarations (API §3.6.4) |
| `App/Store/BackupManager.swift` | WP4 | prev-file, daily backups, `Asist-acik-isler.txt`, recovery, newer-writer copy |
| `App/Store/ImportExport.swift` | WP4 | export `Data`, import preview/merge/replace **helpers only** (no type declarations that §3.6.4 puts in DataStore.swift) |
| `App/Notifications/NotificationCoordinator.swift` | WP0 (exact §3.6.5) | `UNUserNotificationCenterDelegate` |
| `App/Notifications/NotificationCategories.swift` | WP0 (exact §3.6.5) | registers categories/actions |
| `App/Notifications/NotificationRequestFactory.swift` | WP5 | `PlannedNotification → UNNotificationRequest` (01a §2.5 adapted, §3.6.5) |
| `App/Notifications/NotificationScheduler.swift` | WP5 | diff-apply, immediate add, delivered cleanup, diagnostics listing |
| `App/Notifications/ReminderEngine.swift` | WP5 | reconcile + action handling (API §3.6.5) |
| `App/Notifications/BackgroundRefresh.swift` | WP0 (exact §3.6.5) | BGAppRefreshTask + `BGCompletion` |
| `App/Notifications/PermissionCenter.swift` | WP5 | permission/settings state + banner computation (API §3.6.6) |
| `App/Voice/VoicePermissions.swift` | WP6 | 01b §1.5 verbatim |
| `App/Voice/AudioSessionConfigurator.swift` | WP6 | 01b §1.6 verbatim |
| `App/Voice/SpeechListener.swift` | WP6 | 01b §1.7 adapted per D2/D19 (API §3.6.7) |
| `App/Voice/Speaker.swift` | WP6 | 01b §2.1 adapted per D2 |
| `App/Voice/VolumeButtonTrigger.swift` | WP6 | 01b §3.3 adapted per D2 |
| `App/Voice/SystemVolumeAnchor.swift` | WP6 | `UIViewRepresentable` from 01b §3.3 |
| `App/Voice/VoiceCoordinator.swift` | WP6 | observable voice state machine (API §3.6.7) |
| `App/Services/ToastCenter.swift` | WP0 | toast + undo (§3.6.8, exact) |
| `App/Services/CaptureDraft.swift` | WP7 | confirmation-card model (API §3.6.8) |
| `App/Services/CaptureService.swift` | WP7 | parse → draft/save, headless capture, voice snooze (API §3.6.8) |
| `App/Services/CommandExecutor.swift` | WP7 | queries, voice complete/cancel/snooze (API §3.6.8) |
| `App/Routing/AppRouter.swift` | WP0 | tabs, paths, sheets, pending actions (§3.6.10, exact) |
| `App/Platform/SigningMonitor.swift` | WP8 | profile expiry, re-sign detection (API §3.6.11) |
| `App/Intents/DinleIntent.swift` | WP0 (exact §3.7) | opens app + starts listening |
| `App/Intents/KaydetIntent.swift` | WP0 (exact §3.7) | headless capture |
| `App/Intents/BugunIntent.swift` | WP0 (exact §3.7) | spoken agenda |
| `App/Intents/GecikenlerIntent.swift` | WP0 (exact §3.7) | spoken overdue list |
| `App/Intents/AsistShortcuts.swift` | WP0 (exact §3.7) | `AppShortcutsProvider` |
| `App/Resources/Assets.xcassets/Contents.json` | WP0 | 01c §1.7 |
| `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | WP0 | 01c §1.7 |
| `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | WP0 | generated by `Tools/make_app_icon.py` |
| `App/Resources/Sounds/asist-onemli.wav`, `asist-kritik.wav` | WP0 | generated by `Tools/make_sounds.py` (copied flat into `Asist.app/`) |
| `App/Resources/tr.lproj/AppShortcuts.strings` | WP0 | identity mapping of every phrase (§3.7) |
| `App/UI/DesignSystem/Tokens.swift` | WP0 | colors, metrics, SF Symbol names (§5.4, exact) |
| `App/UI/Components/ItemRow.swift` | WP9 | row (signature §5.3) |
| `App/UI/Components/Chip.swift` | WP9 | **`Chip`, `ChipRow`, `StatChip`** (only here, 05a #31) |
| `App/UI/Components/PrimaryButton.swift` | WP9 | 56 pt button style |
| `App/UI/Components/MicButton.swift` | WP9 | 88/64 pt mic |
| `App/UI/Components/ToastHost.swift` | WP9 | reads `ToastCenter` |
| `App/UI/Components/BannerView.swift` | WP9 | renders `AppBanner` |
| `App/UI/Components/EmptyStateView.swift` | WP9 | wraps `ContentUnavailableView` |
| `App/UI/Components/PriorityBadge.swift` | WP9 | ÖNEMLİ / KRİTİK badge |
| `App/UI/Components/SectionHeader.swift` | WP9 | uppercase literal header |
| `App/UI/Components/SnoozeOptions.swift` | WP9 | `SnoozeOption` enum + menu content (shared by rows/detail/hero) |
| `App/UI/Components/MuteMenu.swift` | WP9 | "Sessize al" `Menu` + `MuteBanner` (D32) |
| `App/UI/Root/RootView.swift` | WP9 | gates, overlays, sheets, scene phase, URLs (§5.1) |
| `App/UI/Root/MainTabView.swift` | WP9 | 4 tabs, NavigationStacks |
| `App/UI/Root/RouteDestination.swift` | WP9 | `Route → View` switch |
| `App/UI/Root/SheetHost.swift` | WP9 | `SheetRoute → View` switch |
| `App/UI/Today/TodayView.swift` | WP9 | 03 §4.3 |
| `App/UI/Today/TodayHeader.swift` | WP9 | greeting, date, stat chips |
| `App/UI/Today/HeroCard.swift` | WP9 | "Şimdi ilgilen" + "Sesle ertele" |
| `App/UI/Today/BottomCaptureBar.swift` | WP9 | Yaz / Mic / Oku |
| `App/UI/Capture/ListeningOverlay.swift` | WP9 | 03 §5.3 |
| `App/UI/Capture/ConfirmationSheet.swift` | WP9 | 03 §4.5 |
| `App/UI/Capture/ComposeSheet.swift` | WP9 | 03 §4.6 |
| `App/UI/Capture/MatchConfirmationSheet.swift` | WP9 | 03 §5.10 |
| `App/UI/Capture/AgendaAnswerSheet.swift` | WP9 | 03 §5.9 |
| `App/UI/Lists/ListsView.swift` | WP10 | 03 §4.7 |
| `App/UI/Lists/CompletedListView.swift` | WP10 | Tamamlananlar |
| `App/UI/Detail/ItemDetailView.swift` | WP10 | 03 §4.8 |
| `App/UI/Detail/SnoozeGrid.swift` | WP10 | 6 snooze chips + "Sesle ertele" |
| `App/UI/Detail/ChecklistSection.swift` | WP10 | checklist + template menu |
| `App/UI/Detail/HistorySection.swift` | WP10 | history list |
| `App/UI/Detail/DateTimePickerSheet.swift` | WP10 | custom date/time |
| `App/UI/Detail/FollowUpMessageSheet.swift` | WP10 | Takip message + ShareLink |
| `App/UI/Projects/ProjectsView.swift` | WP10 | 03 §4.9 list |
| `App/UI/Projects/ProjectDetailView.swift` | WP10 | İşler / Notlar / Tamamlanan |
| `App/UI/Projects/ProjectEditorSheet.swift` | WP10 | name, color, aliases |
| `App/UI/EndOfDay/EndOfDayView.swift` | WP10 | simple list version of 03 §4.10 |
| `App/UI/Settings/SettingsView.swift` | WP11 | sections list |
| `App/UI/Settings/GeneralSettingsView.swift` | WP11 | |
| `App/UI/Settings/TimeSettingsView.swift` | WP11 | work/quiet hours, dayparts, follow-up time |
| `App/UI/Settings/NagSettingsView.swift` | WP11 | profile per priority + preview timeline |
| `App/UI/Settings/SummarySettingsView.swift` | WP11 | briefing/EOD/backup reminder |
| `App/UI/Settings/TriggerSettingsView.swift` | WP11 | volume trigger + guides list |
| `App/UI/Settings/GuideView.swift` | WP11 | guides A, A-alt, C, E, "Kalıcı bildirim" |
| `App/UI/Settings/DataSettingsView.swift` | WP11 | export/import (security-scoped)/backups |
| `App/UI/Settings/RecentlyDeletedView.swift` | WP11 | "Son silinenler" (05b B8) |
| `App/UI/Settings/AppStatusView.swift` | WP11 | signing, permissions, version, data writer build |
| `App/UI/Settings/DiagnosticsView.swift` | WP11 | pending list, last reconcile, log, test notification |
| `App/UI/Onboarding/OnboardingView.swift` | WP11 | **3 pages** (§5.2) |

### 2.4 Generated (never committed)

`Asist.xcodeproj/`, `Generated/Asist-Info.plist` — produced by `xcodegen generate` in CI. v1.0 generates **no** entitlements file.

---

## 3. Exact Swift contracts

### 3.1 Conventions for all Swift in this project

- Swift 5 language mode. `public` for everything AsistCore exports. **No `Sendable` annotations required** (warnings are acceptable, errors are not).
- Codable models: explicit `CodingKeys`, **custom `init(from:)` that never throws for a missing/garbled field** (uses `lenient`), synthesized `encode(to:)`. Adding a field later = add property with default + add key + one `lenient` line. Never rename/remove a key (only deprecate).
- Enums persisted as raw values have a custom `init(from:)` that maps unknown raw values to a documented fallback case. Because lenient decoding + synthesized encoding silently drops what an older build does not know, the store refuses to *silently* overwrite a file written by a newer build (D35, §3.6.4).
- Numbers decoded from disk or import are **clamped in `init(from:)`** before any use in `Task.sleep`, `DateComponents`, loops or triggers (05a #8, #20).
- Dates persist with `JSONEncoder.DateEncodingStrategy.iso8601` (whole seconds) — **frozen forever**: a fractional-seconds date would fail `lenient` decoding and turn `dueDate` into nil. All planner/reminder instants are whole minutes (`AsistCalendar.floorToMinute/ceilToMinute`).
- No `String(format:)` in AsistCore (Linux/CVarArg pitfalls) — use `AsistCalendar.pad`.
- Subscripts are declared with an explicit `_` label (`subscript(_ kind: NagProfileKind)`) so call sites are unambiguous (`profiles[kind]`).

### 3.2 Model (AsistCore/Model) — exact files

#### 3.2.1

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Codable+Lenient.swift
import Foundation

extension KeyedDecodingContainer {
    /// Missing, null or malformed value → `defaultValue`. Never throws.
    public func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        if let value = try? decodeIfPresent(type, forKey: key) {
            return value
        }
        return defaultValue
    }

    /// Missing, null or malformed value → nil. Never throws.
    public func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        if let value = try? decodeIfPresent(type, forKey: key) {
            return value
        }
        return nil
    }
}

/// Decodes an array, silently dropping elements that fail to decode (one corrupt item never loses the rest).
public struct LossyDecodableArray<Element: Decodable>: Decodable {
    public var elements: [Element]

    public init(elements: [Element]) {
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else if (try? container.decode(SkippedElement.self)) == nil {
                break   // cannot advance: stop instead of looping forever
            }
        }
        elements = result
    }

    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
```

#### 3.2.2

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Enums.swift
import Foundation

public enum ItemKind: String, Codable, CaseIterable, Hashable {
    case reminder, task, note, waiting

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ItemKind(rawValue: raw) ?? .task
    }

    public var label: String {
        switch self {
        case .reminder: return "Hatırlatma"
        case .task: return "Görev"
        case .note: return "Not"
        case .waiting: return "Takip"
        }
    }

    public var pluralLabel: String {
        switch self {
        case .reminder: return "Hatırlatmalar"
        case .task: return "Görevler"
        case .note: return "Notlar"
        case .waiting: return "Takip"
        }
    }
}

public enum ItemStatus: String, Codable, CaseIterable, Hashable {
    case open, done, deleted

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ItemStatus(rawValue: raw) ?? .open
    }
}

public enum Priority: Int, Codable, CaseIterable, Comparable, Hashable {
    case low = 0, normal = 1, high = 2, critical = 3

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(Int.self)) ?? 1
        self = Priority(rawValue: raw) ?? .normal
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Corpus / Smart Mode spelling.
    public var code: String {
        switch self {
        case .low: return "low"
        case .normal: return "normal"
        case .high: return "high"
        case .critical: return "critical"
        }
    }

    public init?(code: String) {
        switch code {
        case "low": self = .low
        case "normal": self = .normal
        case "high": self = .high
        case "critical": self = .critical
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .low: return "Düşük"
        case .normal: return "Normal"
        case .high: return "Önemli"
        case .critical: return "Kritik"
        }
    }
}

public enum PlaceTrigger: String, Codable, CaseIterable, Hashable {
    case onArrive, onLeave

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = PlaceTrigger(rawValue: raw) ?? .onArrive
    }

    public var label: String { self == .onArrive ? "varınca" : "çıkınca" }
}

public enum CaptureSource: String, Codable, CaseIterable, Hashable {
    case voice, keyboard, siri, shortcut, widget, notification, importFile, smartMode, other

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = CaptureSource(rawValue: raw) ?? .other
    }

    /// Used in history text: "27 Eyl 10:14 · sesle oluşturuldu"
    public var historyLabel: String {
        switch self {
        case .voice: return "sesle"
        case .keyboard: return "klavyeyle"
        case .siri: return "Siri ile"
        case .shortcut: return "kestirmeyle"
        case .widget: return "widget'tan"
        case .notification: return "bildirimden"
        case .importFile: return "içe aktarmayla"
        case .smartMode: return "Akıllı Mod ile"
        case .other: return "elle"
        }
    }
}

public enum NagProfileKind: String, Codable, CaseIterable, Hashable {
    case nazik, israrci, birakmaz, takip, etkinlik

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = NagProfileKind(rawValue: raw) ?? .nazik
    }

    public var label: String {
        switch self {
        case .nazik: return "Nazik"
        case .israrci: return "Israrcı"
        case .birakmaz: return "Bırakmaz"
        case .takip: return "Takip"
        case .etkinlik: return "Etkinlik"
        }
    }

    /// Offered in the per-priority pickers and the detail "Israr düzeyi" menu (takip/etkinlik are automatic).
    public static let selectable: [NagProfileKind] = [.nazik, .israrci, .birakmaz]
}

public enum BadgeMode: String, Codable, CaseIterable, Hashable {
    case overdue, overdueAndToday, off

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = BadgeMode(rawValue: raw) ?? .overdue
    }
}

public enum NoTimeBehavior: String, Codable, CaseIterable, Hashable {
    case ask, inOneHour, thisEvening, tomorrowMorning

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = NoTimeBehavior(rawValue: raw) ?? .ask
    }
}

public enum TTSRate: String, Codable, CaseIterable, Hashable {
    case slow, normal, fast

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = TTSRate(rawValue: raw) ?? .normal
    }
}

public enum HistoryEvent: String, Codable, CaseIterable, Hashable {
    case created, edited, rescheduled, snoozed, done, occurrenceDone, occurrenceMissed
    case reopened, deleted, restored, movedEndOfDay, smartMode, locationFired, other

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = HistoryEvent(rawValue: raw) ?? .other
    }
}

public enum ProjectColor: String, Codable, CaseIterable, Hashable {
    case blue, green, orange, red, purple, teal, pink, brown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ProjectColor(rawValue: raw) ?? .blue
    }
}
```

#### 3.2.3

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/ClockTime.swift
import Foundation

public struct ClockTime: Codable, Equatable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(minutesOfDay: Int) {
        let m = ((minutesOfDay % 1440) + 1440) % 1440
        self.hour = m / 60
        self.minute = m % 60
    }

    public var minutesOfDay: Int { hour * 60 + minute }

    /// "08:30"
    public var display: String { AsistCalendar.pad(hour, 2) + ":" + AsistCalendar.pad(minute, 2) }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutesOfDay < rhs.minutesOfDay }

    enum CodingKeys: String, CodingKey { case hour, minute }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hour = min(23, max(0, c.lenient(Int.self, forKey: .hour, default: 9)))
        minute = min(59, max(0, c.lenient(Int.self, forKey: .minute, default: 0)))
    }
}
```

#### 3.2.4

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Recurrence.swift
import Foundation

public struct Recurrence: Codable, Equatable, Hashable {
    public enum Frequency: String, Codable, CaseIterable, Hashable {
        case daily, weekly, monthly, yearly

        public init(from decoder: Decoder) throws {
            let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
            self = Frequency(rawValue: raw) ?? .daily
        }
    }

    public var frequency: Frequency
    /// >= 1 ("iki haftada bir" → weekly, 2)
    public var interval: Int
    /// weekly only; ISO 1 = Pazartesi … 7 = Pazar; sorted, unique, non-empty
    public var weekdays: [Int]?
    /// monthly/yearly: 1…31, or -1 = last day of month
    public var monthDay: Int?
    /// yearly only: 1…12
    public var month: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil, monthDay: Int? = nil, month: Int? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthDay = monthDay
        self.month = month
    }

    enum CodingKeys: String, CodingKey { case frequency, interval, weekdays, monthDay, month }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(Frequency.self, forKey: .frequency, default: .daily)
        interval = min(120, max(1, c.lenient(Int.self, forKey: .interval, default: 1)))
        // Clamps (05a #20): invalid values become nil; RecurrenceEngine treats an unusable rule as "no next occurrence".
        let rawWeekdays = c.lenientOptional([Int].self, forKey: .weekdays) ?? []
        let validWeekdays = Array(Set(rawWeekdays.filter { (1...7).contains($0) })).sorted()
        weekdays = validWeekdays.isEmpty ? nil : validWeekdays
        monthDay = c.lenientOptional(Int.self, forKey: .monthDay).flatMap { (day: Int) -> Int? in
            (day == -1 || (1...31).contains(day)) ? day : nil
        }
        month = c.lenientOptional(Int.self, forKey: .month).flatMap { (value: Int) -> Int? in
            (1...12).contains(value) ? value : nil
        }
    }
}
```

#### 3.2.5

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/NagProfile.swift
import Foundation

/// Semantics: 04 §6.4. All values are minutes except `dailyCap`/`maxPendingFollowUps` (counts).
public struct NagProfile: Codable, Equatable, Hashable {
    /// Follow-ups after the first alert, relative to the anchor.
    public var followUpOffsetsMinutes: [Int]
    /// After the offsets: repeat step inside work hours (nil = jump to next day start).
    public var repeatMinutesWorkHours: Int?
    /// After the offsets: repeat step outside work hours but outside quiet hours (nil = jump to next day start).
    public var repeatMinutesOffHours: Int?
    /// Max notifications of one item per calendar day (first alert included).
    public var dailyCap: Int
    /// Max pending follow-ups (k >= 1) per item in one plan.
    public var maxPendingFollowUps: Int

    public init(followUpOffsetsMinutes: [Int], repeatMinutesWorkHours: Int?, repeatMinutesOffHours: Int?,
                dailyCap: Int, maxPendingFollowUps: Int) {
        self.followUpOffsetsMinutes = followUpOffsetsMinutes
        self.repeatMinutesWorkHours = repeatMinutesWorkHours
        self.repeatMinutesOffHours = repeatMinutesOffHours
        self.dailyCap = dailyCap
        self.maxPendingFollowUps = maxPendingFollowUps
    }

    /// normal/low (05b C1): +10, +30, +90 min, then every 2 h **inside work hours only**; ≤ 6/day.
    public static let nazik = NagProfile(followUpOffsetsMinutes: [10, 30, 90], repeatMinutesWorkHours: 120,
                                         repeatMinutesOffHours: nil, dailyCap: 6, maxPendingFollowUps: 6)
    /// high (05b C4): hourly inside work hours, no evening repeats.
    public static let israrci = NagProfile(followUpOffsetsMinutes: [5, 15, 30, 60], repeatMinutesWorkHours: 60,
                                           repeatMinutesOffHours: nil, dailyCap: 10, maxPendingFollowUps: 8)
    /// critical: offsets respect the 3-minute spacing of the rate limiter (§6.4 step 5).
    public static let birakmaz = NagProfile(followUpOffsetsMinutes: [3, 6, 10, 15], repeatMinutesWorkHours: 15,
                                            repeatMinutesOffHours: 15, dailyCap: 30, maxPendingFollowUps: 10)
    public static let takip = NagProfile(followUpOffsetsMinutes: [], repeatMinutesWorkHours: nil,
                                         repeatMinutesOffHours: nil, dailyCap: 1, maxPendingFollowUps: 4)
    /// Events (D31): first alert only.
    public static let etkinlik = NagProfile(followUpOffsetsMinutes: [], repeatMinutesWorkHours: nil,
                                            repeatMinutesOffHours: nil, dailyCap: 1, maxPendingFollowUps: 0)

    enum CodingKeys: String, CodingKey {
        case followUpOffsetsMinutes, repeatMinutesWorkHours, repeatMinutesOffHours, dailyCap, maxPendingFollowUps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NagProfile.nazik
        let offsets = c.lenient([Int].self, forKey: .followUpOffsetsMinutes, default: d.followUpOffsetsMinutes)
        followUpOffsetsMinutes = Array(Set(offsets.filter { $0 > 0 && $0 <= 1440 })).sorted()
        // A repeat step of 0 would never advance the chain (05a #20): clamp to >= 5 min.
        repeatMinutesWorkHours = c.lenientOptional(Int.self, forKey: .repeatMinutesWorkHours).map { max(5, $0) }
        repeatMinutesOffHours = c.lenientOptional(Int.self, forKey: .repeatMinutesOffHours).map { max(5, $0) }
        dailyCap = min(60, max(1, c.lenient(Int.self, forKey: .dailyCap, default: d.dailyCap)))
        maxPendingFollowUps = min(20, max(0, c.lenient(Int.self, forKey: .maxPendingFollowUps, default: d.maxPendingFollowUps)))
    }
}

/// Code-defined profile table. Not persisted in v1.x (parameters are not user-editable, so a stored copy
/// would freeze today's defaults forever); `AppSettings.nagProfiles` is a computed property returning `NagProfiles()`.
public struct NagProfiles: Codable, Equatable, Hashable {
    public var nazik: NagProfile = .nazik
    public var israrci: NagProfile = .israrci
    public var birakmaz: NagProfile = .birakmaz
    public var takip: NagProfile = .takip
    public var etkinlik: NagProfile = .etkinlik

    public init() {}

    public subscript(_ kind: NagProfileKind) -> NagProfile {
        switch kind {
        case .nazik: return nazik
        case .israrci: return israrci
        case .birakmaz: return birakmaz
        case .takip: return takip
        case .etkinlik: return etkinlik
        }
    }

    enum CodingKeys: String, CodingKey { case nazik, israrci, birakmaz, takip, etkinlik }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nazik = c.lenient(NagProfile.self, forKey: .nazik, default: .nazik)
        israrci = c.lenient(NagProfile.self, forKey: .israrci, default: .israrci)
        birakmaz = c.lenient(NagProfile.self, forKey: .birakmaz, default: .birakmaz)
        takip = c.lenient(NagProfile.self, forKey: .takip, default: .takip)
        etkinlik = c.lenient(NagProfile.self, forKey: .etkinlik, default: .etkinlik)
    }
}
```

#### 3.2.6

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Item.swift
import Foundation

public struct ChecklistEntry: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case id, text, done }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        text = c.lenient(String.self, forKey: .text, default: "")
        done = c.lenient(Bool.self, forKey: .done, default: false)
    }
}

public struct HistoryEntry: Codable, Equatable, Hashable {
    public var date: Date
    public var event: HistoryEvent
    public var detail: String?

    public init(date: Date, event: HistoryEvent, detail: String? = nil) {
        self.date = date
        self.event = event
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey { case date, event, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.lenient(Date.self, forKey: .date, default: Date(timeIntervalSince1970: 0))
        event = c.lenient(HistoryEvent.self, forKey: .event, default: .other)
        detail = c.lenientOptional(String.self, forKey: .detail)
    }
}

/// One user record: Hatırlatma / Görev / Not / Takip.
public struct Item: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    /// Free-text notes (for notes: the note body).
    public var notes: String
    /// The utterance/typed text the item was created from (always shown in detail).
    public var originalText: String?
    public var status: ItemStatus
    public var priority: Priority
    /// Due instant of the current occurrence (whole minute). nil = "zamanı belirsiz".
    public var dueDate: Date?
    /// false when the time part was a default (09:00 / today policy).
    public var hasTime: Bool
    public var recurrence: Recurrence?
    /// Explicit snooze target; when set it is the nag anchor instead of `dueDate`.
    public var snoozedUntil: Date?
    public var snoozeCount: Int
    /// Pre-alerts in minutes before `dueDate` (e.g. 10, 30, 60, 1440, 10080, 43200).
    public var leadTimesMinutes: [Int]
    /// nil = profile by priority from settings (waiting items always use .takip, events .etkinlik).
    public var nagProfile: NagProfileKind?
    /// Meeting/visit/FAT…: first alert + pre-alert only, never overdue, auto-closed 120 min after start (D31).
    public var isEvent: Bool
    public var person: String?
    public var projectID: UUID?
    public var placeID: UUID?
    public var placeTrigger: PlaceTrigger?
    /// Delivery time of the location notification; anchor of the nag chain for place-only items.
    public var locationFiredAt: Date?
    public var tags: [String]
    public var checklist: [ChecklistEntry]
    /// "Emin değilim" flag (low-confidence capture that nobody confirmed; UI section "EMİN OLAMADIKLARIM").
    public var needsReview: Bool
    public var source: CaptureSource
    public var parseConfidence: Double?
    public var smartModeUsed: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var deletedAt: Date?
    public var lastDismissedAt: Date?
    public var completedOccurrences: Int
    /// Newest last; capped at 50 entries by `appendHistory`.
    public var history: [HistoryEntry]

    public init(id: UUID = UUID(),
                kind: ItemKind,
                title: String,
                notes: String = "",
                originalText: String? = nil,
                status: ItemStatus = .open,
                priority: Priority = .normal,
                dueDate: Date? = nil,
                hasTime: Bool = false,
                recurrence: Recurrence? = nil,
                snoozedUntil: Date? = nil,
                snoozeCount: Int = 0,
                leadTimesMinutes: [Int] = [],
                nagProfile: NagProfileKind? = nil,
                isEvent: Bool = false,
                person: String? = nil,
                projectID: UUID? = nil,
                placeID: UUID? = nil,
                placeTrigger: PlaceTrigger? = nil,
                locationFiredAt: Date? = nil,
                tags: [String] = [],
                checklist: [ChecklistEntry] = [],
                needsReview: Bool = false,
                source: CaptureSource = .other,
                parseConfidence: Double? = nil,
                smartModeUsed: Bool = false,
                createdAt: Date,
                updatedAt: Date? = nil,
                completedAt: Date? = nil,
                deletedAt: Date? = nil,
                lastDismissedAt: Date? = nil,
                completedOccurrences: Int = 0,
                history: [HistoryEntry] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.notes = notes
        self.originalText = originalText
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.recurrence = recurrence
        self.snoozedUntil = snoozedUntil
        self.snoozeCount = snoozeCount
        self.leadTimesMinutes = leadTimesMinutes
        self.nagProfile = nagProfile
        self.isEvent = isEvent
        self.person = person
        self.projectID = projectID
        self.placeID = placeID
        self.placeTrigger = placeTrigger
        self.locationFiredAt = locationFiredAt
        self.tags = tags
        self.checklist = checklist
        self.needsReview = needsReview
        self.source = source
        self.parseConfidence = parseConfidence
        self.smartModeUsed = smartModeUsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.lastDismissedAt = lastDismissedAt
        self.completedOccurrences = completedOccurrences
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, notes, originalText, status, priority, dueDate, hasTime, recurrence
        case snoozedUntil, snoozeCount, leadTimesMinutes, nagProfile, isEvent, person, projectID, placeID, placeTrigger
        case locationFiredAt, tags, checklist, needsReview, source, parseConfidence, smartModeUsed
        case createdAt, updatedAt, completedAt, deletedAt, lastDismissedAt, completedOccurrences, history
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = Date(timeIntervalSince1970: 0)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        kind = c.lenient(ItemKind.self, forKey: .kind, default: .task)
        title = c.lenient(String.self, forKey: .title, default: "")
        notes = c.lenient(String.self, forKey: .notes, default: "")
        originalText = c.lenientOptional(String.self, forKey: .originalText)
        status = c.lenient(ItemStatus.self, forKey: .status, default: .open)
        priority = c.lenient(Priority.self, forKey: .priority, default: .normal)
        dueDate = c.lenientOptional(Date.self, forKey: .dueDate)
        hasTime = c.lenient(Bool.self, forKey: .hasTime, default: false)
        recurrence = c.lenientOptional(Recurrence.self, forKey: .recurrence)
        snoozedUntil = c.lenientOptional(Date.self, forKey: .snoozedUntil)
        snoozeCount = max(0, c.lenient(Int.self, forKey: .snoozeCount, default: 0))
        let leads = c.lenient([Int].self, forKey: .leadTimesMinutes, default: [])
        leadTimesMinutes = Array(Set(leads.filter { $0 > 0 && $0 <= 527_040 })).sorted()   // ≤ 366 days
        nagProfile = c.lenientOptional(NagProfileKind.self, forKey: .nagProfile)
        isEvent = c.lenient(Bool.self, forKey: .isEvent, default: false)
        person = c.lenientOptional(String.self, forKey: .person)
        projectID = c.lenientOptional(UUID.self, forKey: .projectID)
        placeID = c.lenientOptional(UUID.self, forKey: .placeID)
        placeTrigger = c.lenientOptional(PlaceTrigger.self, forKey: .placeTrigger)
        locationFiredAt = c.lenientOptional(Date.self, forKey: .locationFiredAt)
        tags = c.lenient([String].self, forKey: .tags, default: [])
        checklist = c.lenientOptional(LossyDecodableArray<ChecklistEntry>.self, forKey: .checklist)?.elements ?? []
        needsReview = c.lenient(Bool.self, forKey: .needsReview, default: false)
        source = c.lenient(CaptureSource.self, forKey: .source, default: .other)
        parseConfidence = c.lenientOptional(Double.self, forKey: .parseConfidence)
        smartModeUsed = c.lenient(Bool.self, forKey: .smartModeUsed, default: false)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: epoch)
        updatedAt = c.lenient(Date.self, forKey: .updatedAt, default: createdAt)
        completedAt = c.lenientOptional(Date.self, forKey: .completedAt)
        deletedAt = c.lenientOptional(Date.self, forKey: .deletedAt)
        lastDismissedAt = c.lenientOptional(Date.self, forKey: .lastDismissedAt)
        completedOccurrences = c.lenient(Int.self, forKey: .completedOccurrences, default: 0)
        history = c.lenientOptional(LossyDecodableArray<HistoryEntry>.self, forKey: .history)?.elements ?? []
    }
}
```

Note: `updatedAt = c.lenient(…, default: createdAt)` reads the already-initialized `createdAt` — legal because `createdAt` is assigned first. `CodingKeys` lists all 33 stored properties.

#### 3.2.7

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Item+Logic.swift
import Foundation

extension Item {
    public var isOpen: Bool { status == .open }
    public var isRecurring: Bool { recurrence != nil }
    /// Items that can ever produce notifications.
    public var isNotifiable: Bool { status == .open && kind != .note }

    /// The nag anchor: explicit snooze, else due date; place-only items use the location delivery time.
    public var anchorDate: Date? {
        if let snoozed = snoozedUntil { return snoozed }
        if let due = dueDate { return due }
        if placeID != nil { return locationFiredAt }
        return nil
    }

    /// Instant at which the item counts as "geciken" (03 §3.1):
    /// notes and events never; waiting → start of the day after the anchor; untimed task → start of the day after;
    /// everything else → the anchor itself.
    public func overdueStart(calendar: Calendar) -> Date? {
        guard kind != .note, !isEvent, let anchor = anchorDate else { return nil }
        let endOfDayRule = (kind == .waiting) || (kind == .task && !hasTime && snoozedUntil == nil)
        if endOfDayRule {
            let start = calendar.startOfDay(for: anchor)
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        return anchor
    }

    public func isOverdue(at now: Date, calendar: Calendar) -> Bool {
        guard isOpen, let start = overdueStart(calendar: calendar) else { return false }
        return start <= now
    }

    /// Anchor lies on `now`'s calendar day and the item is not (yet) overdue.
    public func isDueToday(at now: Date, calendar: Calendar) -> Bool {
        guard isOpen, kind != .note, let anchor = anchorDate else { return false }
        return calendar.isDate(anchor, inSameDayAs: now) && !isOverdue(at: now, calendar: calendar)
    }

    /// Minutes after the anchor at which an event is auto-closed (D31).
    public static let eventDurationMinutes = 120

    /// anchor + eventDurationMinutes for open events; nil otherwise.
    public var eventEnd: Date? {
        guard isEvent, let anchor = anchorDate else { return nil }
        return anchor.addingTimeInterval(TimeInterval(Item.eventDurationMinutes * 60))
    }

    public func profileKind(settings: AppSettings) -> NagProfileKind {
        if kind == .waiting { return .takip }
        if let explicit = nagProfile, explicit != .takip, explicit != .etkinlik { return explicit }
        if isEvent { return .etkinlik }
        return settings.profileKind(for: priority)
    }

    public mutating func appendHistory(_ event: HistoryEvent, at date: Date, detail: String? = nil) {
        history.append(HistoryEntry(date: date, event: event, detail: detail))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }

    /// Resets nag state after the due date was changed by the user (edit/reschedule).
    public mutating func resetNagState() {
        snoozedUntil = nil
        snoozeCount = 0
        lastDismissedAt = nil
        locationFiredAt = nil
    }
}
```

#### 3.2.8

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/Project.swift
import Foundation

public struct Project: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// Spoken aliases ("Kocaeli", "Kocaeli hattı"); fed to the parser as extra project names.
    public var aliases: [String]
    public var color: ProjectColor
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], color: ProjectColor = .blue,
                archived: Bool = false, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.color = color
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Name first, then aliases (non-empty, trimmed).
    public var allNames: [String] {
        ([name] + aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey { case id, name, aliases, color, archived, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = Date(timeIntervalSince1970: 0)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        name = c.lenient(String.self, forKey: .name, default: "Proje")
        aliases = c.lenient([String].self, forKey: .aliases, default: [])
        color = c.lenient(ProjectColor.self, forKey: .color, default: .blue)
        archived = c.lenient(Bool.self, forKey: .archived, default: false)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: epoch)
        updatedAt = c.lenient(Date.self, forKey: .updatedAt, default: createdAt)
    }
}

public struct Place: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var latitude: Double
    public var longitude: Double
    /// 100…1000 m (clamped on decode; geofences are v1.2).
    public var radiusMeters: Double
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], latitude: Double, longitude: Double,
                radiusMeters: Double = 150, createdAt: Date) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.createdAt = createdAt
    }

    public var allNames: [String] {
        ([name] + aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey { case id, name, aliases, latitude, longitude, radiusMeters, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        name = c.lenient(String.self, forKey: .name, default: "Yer")
        aliases = c.lenient([String].self, forKey: .aliases, default: [])
        // Clamps (05a #20). Places are data-only in v1.0 (no UI, no geofence; location reminders are v1.2).
        latitude = min(90, max(-90, c.lenient(Double.self, forKey: .latitude, default: 0)))
        longitude = min(180, max(-180, c.lenient(Double.self, forKey: .longitude, default: 0)))
        radiusMeters = min(1000, max(100, c.lenient(Double.self, forKey: .radiusMeters, default: 150)))
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: Date(timeIntervalSince1970: 0))
    }
}
```

#### 3.2.9

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/AppSettings.swift
import Foundation

/// Every user-changeable setting with its v1 default (03 §4.11, decisions D7/D10/D11/D16/D18–D21/D31/D32).
public struct AppSettings: Codable, Equatable, Hashable {
    // Genel
    public var userName: String = ""                         // hitap: "Günaydın, Gökhan"
    public var speakConfirmations: Bool = true               // D18: on a private route (headphones/BT/car) only
    public var speakConfirmationsOnSpeaker: Bool = false     // D18: also through the loudspeaker
    public var ttsRate: TTSRate = .normal
    public var autoSaveSeconds: Int = 4                      // 0 = kapalı; allowed 0, 3, 4, 6
    public var noTimeBehavior: NoTimeBehavior = .ask
    // Parser time words
    public var defaultDayTime = ClockTime(9, 0)
    public var sabah = ClockTime(9, 0)
    public var ogledenOnce = ClockTime(11, 0)                // "öğleden önce" (G7)
    public var ogle = ClockTime(12, 0)
    public var ogledenSonra = ClockTime(14, 0)
    public var aksamustu = ClockTime(17, 0)
    public var aksam = ClockTime(19, 0)
    public var gece = ClockTime(22, 0)
    public var ambiguousHoursPM: Bool = true                 // 1–6 without qualifier → 13–18
    // Zamanlar
    public var workdays: [Int] = [1, 2, 3, 4, 5]             // ISO weekdays; never empty after decoding
    public var workStart = ClockTime(8, 30)
    public var workEnd = ClockTime(18, 0)
    public var offDayStart = ClockTime(9, 0)                 // "day start" on non-workdays
    public var quietStart = ClockTime(22, 30)
    public var quietEnd = ClockTime(7, 30)
    public var followUpAskTime = ClockTime(16, 0)            // Takip "Geldi mi?" time
    public var waitingDefaultWorkdays: Int = 2               // 1…10
    public var waitingDefaultTime = ClockTime(10, 0)
    // Israr
    public var profileForLow: NagProfileKind = .nazik
    public var profileForNormal: NagProfileKind = .nazik
    public var profileForHigh: NagProfileKind = .israrci
    public var profileForCritical: NagProfileKind = .birakmaz
    public var criticalIgnoresQuietHours: Bool = false
    public var eventDefaultLeadMinutes: Int = 15             // D31; 0 = no default pre-alert for events
    public var badgeMode: BadgeMode = .overdue
    public var lockScreenShowsContent: Bool = true
    // Özetler
    public var briefingEnabled: Bool = true
    public var briefingTime = ClockTime(8, 0)
    public var briefingWorkdaysOnly: Bool = true
    public var briefingWhenEmpty: Bool = false
    public var briefingTapSpeaks: Bool = false
    public var endOfDayEnabled: Bool = true
    public var endOfDayTime = ClockTime(17, 45)
    public var endOfDayWorkdaysOnly: Bool = true
    public var moveSkipsWeekend: Bool = true
    public var backupReminderEnabled: Bool = true
    public var backupReminderWeekday: Int = 7                // ISO: 7 = Pazar; 1…7
    public var backupReminderTime = ClockTime(20, 0)
    // Tetikleyiciler / ses
    public var volumeTriggerEnabled: Bool = true
    public var restoreVolumeAfterTrigger: Bool = true
    public var silenceSeconds: Double = 1.8                  // 1.2 / 1.8 / 2.5 / 3.5 (clamped 0.8…5)
    public var onDeviceRecognitionOnly: Bool = false
    // Akıllı Mod (v1.1; persisted but unused in v1.0)
    public var smartModeEnabled: Bool = false
    public var smartModeModel: String = "claude-opus-5"
    public var smartModeAutoOnLowConfidence: Bool = true
    // Durum
    public var activeProjectID: UUID? = nil                  // v1.0 has no UI that sets it (v1.1)
    public var onboardingCompleted: Bool = false
    /// D32 "Sessize al": nags before this instant collapse to it; first alerts before it are silent.
    public var muteUntil: Date? = nil

    public init() {}

    /// Code-defined profile table (not persisted, see `NagProfiles`).
    public var nagProfiles: NagProfiles { NagProfiles() }

    public func profileKind(for priority: Priority) -> NagProfileKind {
        switch priority {
        case .low: return profileForLow
        case .normal: return profileForNormal
        case .high: return profileForHigh
        case .critical: return profileForCritical
        }
    }

    public func isWorkday(isoWeekday: Int) -> Bool { workdays.contains(isoWeekday) }

    /// Mute is active at `now` and covers `date`.
    public func isMuted(_ date: Date, now: Date) -> Bool {
        guard let until = muteUntil, now < until else { return false }
        return date < until
    }

    enum CodingKeys: String, CodingKey {
        case userName, speakConfirmations, speakConfirmationsOnSpeaker, ttsRate, autoSaveSeconds, noTimeBehavior
        case defaultDayTime, sabah, ogledenOnce, ogle, ogledenSonra, aksamustu, aksam, gece, ambiguousHoursPM
        case workdays, workStart, workEnd, offDayStart, quietStart, quietEnd, followUpAskTime
        case waitingDefaultWorkdays, waitingDefaultTime
        case profileForLow, profileForNormal, profileForHigh, profileForCritical
        case criticalIgnoresQuietHours, eventDefaultLeadMinutes, badgeMode, lockScreenShowsContent
        case briefingEnabled, briefingTime, briefingWorkdaysOnly, briefingWhenEmpty, briefingTapSpeaks
        case endOfDayEnabled, endOfDayTime, endOfDayWorkdaysOnly, moveSkipsWeekend
        case backupReminderEnabled, backupReminderWeekday, backupReminderTime
        case volumeTriggerEnabled, restoreVolumeAfterTrigger, silenceSeconds, onDeviceRecognitionOnly
        case smartModeEnabled, smartModeModel, smartModeAutoOnLowConfidence
        case activeProjectID, onboardingCompleted, muteUntil
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName = c.lenient(String.self, forKey: .userName, default: userName)
        speakConfirmations = c.lenient(Bool.self, forKey: .speakConfirmations, default: speakConfirmations)
        speakConfirmationsOnSpeaker = c.lenient(Bool.self, forKey: .speakConfirmationsOnSpeaker, default: speakConfirmationsOnSpeaker)
        ttsRate = c.lenient(TTSRate.self, forKey: .ttsRate, default: ttsRate)
        let rawAutoSave = c.lenient(Int.self, forKey: .autoSaveSeconds, default: autoSaveSeconds)
        autoSaveSeconds = [0, 3, 4, 6].contains(rawAutoSave) ? rawAutoSave : 4
        noTimeBehavior = c.lenient(NoTimeBehavior.self, forKey: .noTimeBehavior, default: noTimeBehavior)
        defaultDayTime = c.lenient(ClockTime.self, forKey: .defaultDayTime, default: defaultDayTime)
        sabah = c.lenient(ClockTime.self, forKey: .sabah, default: sabah)
        ogledenOnce = c.lenient(ClockTime.self, forKey: .ogledenOnce, default: ogledenOnce)
        ogle = c.lenient(ClockTime.self, forKey: .ogle, default: ogle)
        ogledenSonra = c.lenient(ClockTime.self, forKey: .ogledenSonra, default: ogledenSonra)
        aksamustu = c.lenient(ClockTime.self, forKey: .aksamustu, default: aksamustu)
        aksam = c.lenient(ClockTime.self, forKey: .aksam, default: aksam)
        gece = c.lenient(ClockTime.self, forKey: .gece, default: gece)
        ambiguousHoursPM = c.lenient(Bool.self, forKey: .ambiguousHoursPM, default: ambiguousHoursPM)
        // Never empty, only 1…7 (05a #8: an empty set would hang the nag chain search).
        let rawWorkdays = c.lenient([Int].self, forKey: .workdays, default: workdays)
        let validWorkdays = Array(Set(rawWorkdays.filter { (1...7).contains($0) })).sorted()
        workdays = validWorkdays.isEmpty ? [1, 2, 3, 4, 5] : validWorkdays
        workStart = c.lenient(ClockTime.self, forKey: .workStart, default: workStart)
        workEnd = c.lenient(ClockTime.self, forKey: .workEnd, default: workEnd)
        offDayStart = c.lenient(ClockTime.self, forKey: .offDayStart, default: offDayStart)
        quietStart = c.lenient(ClockTime.self, forKey: .quietStart, default: quietStart)
        quietEnd = c.lenient(ClockTime.self, forKey: .quietEnd, default: quietEnd)
        followUpAskTime = c.lenient(ClockTime.self, forKey: .followUpAskTime, default: followUpAskTime)
        waitingDefaultWorkdays = min(10, max(1, c.lenient(Int.self, forKey: .waitingDefaultWorkdays, default: waitingDefaultWorkdays)))
        waitingDefaultTime = c.lenient(ClockTime.self, forKey: .waitingDefaultTime, default: waitingDefaultTime)
        profileForLow = AppSettings.selectable(c.lenient(NagProfileKind.self, forKey: .profileForLow, default: profileForLow), fallback: .nazik)
        profileForNormal = AppSettings.selectable(c.lenient(NagProfileKind.self, forKey: .profileForNormal, default: profileForNormal), fallback: .nazik)
        profileForHigh = AppSettings.selectable(c.lenient(NagProfileKind.self, forKey: .profileForHigh, default: profileForHigh), fallback: .israrci)
        profileForCritical = AppSettings.selectable(c.lenient(NagProfileKind.self, forKey: .profileForCritical, default: profileForCritical), fallback: .birakmaz)
        criticalIgnoresQuietHours = c.lenient(Bool.self, forKey: .criticalIgnoresQuietHours, default: criticalIgnoresQuietHours)
        eventDefaultLeadMinutes = min(1440, max(0, c.lenient(Int.self, forKey: .eventDefaultLeadMinutes, default: eventDefaultLeadMinutes)))
        badgeMode = c.lenient(BadgeMode.self, forKey: .badgeMode, default: badgeMode)
        lockScreenShowsContent = c.lenient(Bool.self, forKey: .lockScreenShowsContent, default: lockScreenShowsContent)
        briefingEnabled = c.lenient(Bool.self, forKey: .briefingEnabled, default: briefingEnabled)
        briefingTime = c.lenient(ClockTime.self, forKey: .briefingTime, default: briefingTime)
        briefingWorkdaysOnly = c.lenient(Bool.self, forKey: .briefingWorkdaysOnly, default: briefingWorkdaysOnly)
        briefingWhenEmpty = c.lenient(Bool.self, forKey: .briefingWhenEmpty, default: briefingWhenEmpty)
        briefingTapSpeaks = c.lenient(Bool.self, forKey: .briefingTapSpeaks, default: briefingTapSpeaks)
        endOfDayEnabled = c.lenient(Bool.self, forKey: .endOfDayEnabled, default: endOfDayEnabled)
        endOfDayTime = c.lenient(ClockTime.self, forKey: .endOfDayTime, default: endOfDayTime)
        endOfDayWorkdaysOnly = c.lenient(Bool.self, forKey: .endOfDayWorkdaysOnly, default: endOfDayWorkdaysOnly)
        moveSkipsWeekend = c.lenient(Bool.self, forKey: .moveSkipsWeekend, default: moveSkipsWeekend)
        backupReminderEnabled = c.lenient(Bool.self, forKey: .backupReminderEnabled, default: backupReminderEnabled)
        backupReminderWeekday = min(7, max(1, c.lenient(Int.self, forKey: .backupReminderWeekday, default: backupReminderWeekday)))
        backupReminderTime = c.lenient(ClockTime.self, forKey: .backupReminderTime, default: backupReminderTime)
        volumeTriggerEnabled = c.lenient(Bool.self, forKey: .volumeTriggerEnabled, default: volumeTriggerEnabled)
        restoreVolumeAfterTrigger = c.lenient(Bool.self, forKey: .restoreVolumeAfterTrigger, default: restoreVolumeAfterTrigger)
        silenceSeconds = min(5, max(0.8, c.lenient(Double.self, forKey: .silenceSeconds, default: silenceSeconds)))
        onDeviceRecognitionOnly = c.lenient(Bool.self, forKey: .onDeviceRecognitionOnly, default: onDeviceRecognitionOnly)
        smartModeEnabled = c.lenient(Bool.self, forKey: .smartModeEnabled, default: smartModeEnabled)
        smartModeModel = c.lenient(String.self, forKey: .smartModeModel, default: smartModeModel)
        smartModeAutoOnLowConfidence = c.lenient(Bool.self, forKey: .smartModeAutoOnLowConfidence, default: smartModeAutoOnLowConfidence)
        activeProjectID = c.lenientOptional(UUID.self, forKey: .activeProjectID)
        onboardingCompleted = c.lenient(Bool.self, forKey: .onboardingCompleted, default: onboardingCompleted)
        muteUntil = c.lenientOptional(Date.self, forKey: .muteUntil)
    }

    private static func selectable(_ kind: NagProfileKind, fallback: NagProfileKind) -> NagProfileKind {
        NagProfileKind.selectable.contains(kind) ? kind : fallback
    }
}
```

`self.init()` followed by field assignment is legal in a struct `init(from:)` (delegating initializer, then mutation). The synthesized `encode(to:)` uses the `CodingKeys` above — **every stored property must be listed** (a property missing from `CodingKeys` compiles but is silently not persisted); `nagProfiles` is computed and therefore not a key. The key `nagProfiles` written by revision-1 builds is ignored (no build of revision 1 ever shipped). Settings UI rule: the last remaining workday cannot be switched off (05a #8).

#### 3.2.10

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Model/AppData.swift
import Foundation

public struct MoveRecord: Codable, Equatable, Hashable {
    public var movedAt: Date
    /// Copies of the items before "Sonraki iş gününe taşı" (for 24 h undo banner).
    public var before: [Item]

    public init(movedAt: Date, before: [Item]) {
        self.movedAt = movedAt
        self.before = before
    }

    enum CodingKeys: String, CodingKey { case movedAt, before }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        movedAt = c.lenient(Date.self, forKey: .movedAt, default: Date(timeIntervalSince1970: 0))
        before = c.lenientOptional(LossyDecodableArray<Item>.self, forKey: .before)?.elements ?? []
    }
}

public struct AppMeta: Codable, Equatable, Hashable {
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var lastSavedAt: Date? = nil
    public var lastProfileStamp: Double? = nil           // signing profile CreationDate (seconds)
    public var lastReconcileAt: Date? = nil
    public var lastReconcileReason: String? = nil
    public var lastPlannedCount: Int = 0
    public var lastDroppedCount: Int = 0
    public var lastBackgroundRefreshAt: Date? = nil
    public var lastDailyBackupDay: String? = nil          // "yyyyMMdd"
    public var lastEndOfDayMove: MoveRecord? = nil
    public var composeDraft: String? = nil
    public var dismissedBanners: [String: Date] = [:]     // banner id → hidden until (absolute date)
    public var installDate: Date? = nil                   // UI-only signing estimate (05a #28)
    /// CFBundleVersion of the build that last saved this file (D35). 0 = unknown / revision-1 file.
    public var writerBuild: Int = 0

    public init() {}

    enum CodingKeys: String, CodingKey {
        case createdAt, lastSavedAt, lastProfileStamp, lastReconcileAt, lastReconcileReason, lastPlannedCount
        case lastDroppedCount, lastBackgroundRefreshAt, lastDailyBackupDay, lastEndOfDayMove, composeDraft
        case dismissedBanners, installDate, writerBuild
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: createdAt)
        lastSavedAt = c.lenientOptional(Date.self, forKey: .lastSavedAt)
        lastProfileStamp = c.lenientOptional(Double.self, forKey: .lastProfileStamp)
        lastReconcileAt = c.lenientOptional(Date.self, forKey: .lastReconcileAt)
        lastReconcileReason = c.lenientOptional(String.self, forKey: .lastReconcileReason)
        lastPlannedCount = c.lenient(Int.self, forKey: .lastPlannedCount, default: 0)
        lastDroppedCount = c.lenient(Int.self, forKey: .lastDroppedCount, default: 0)
        lastBackgroundRefreshAt = c.lenientOptional(Date.self, forKey: .lastBackgroundRefreshAt)
        lastDailyBackupDay = c.lenientOptional(String.self, forKey: .lastDailyBackupDay)
        lastEndOfDayMove = c.lenientOptional(MoveRecord.self, forKey: .lastEndOfDayMove)
        composeDraft = c.lenientOptional(String.self, forKey: .composeDraft)
        dismissedBanners = c.lenient([String: Date].self, forKey: .dismissedBanners, default: [:])
        installDate = c.lenientOptional(Date.self, forKey: .installDate)
        writerBuild = max(0, c.lenient(Int.self, forKey: .writerBuild, default: 0))
    }
}

/// Root document persisted as `asist-data.json`.
public struct AppData: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [Item]
    public var projects: [Project]
    public var places: [Place]
    public var settings: AppSettings
    public var meta: AppMeta

    public init(schemaVersion: Int = AppData.currentSchemaVersion,
                items: [Item] = [],
                projects: [Project] = [],
                places: [Place] = [],
                settings: AppSettings = AppSettings(),
                meta: AppMeta = AppMeta()) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.projects = projects
        self.places = places
        self.settings = settings
        self.meta = meta
    }

    public static func empty(now: Date) -> AppData {
        var meta = AppMeta()
        meta.createdAt = now
        meta.installDate = now
        return AppData(meta: meta)
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, items, projects, places, settings, meta }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.lenient(Int.self, forKey: .schemaVersion, default: 1)
        items = c.lenientOptional(LossyDecodableArray<Item>.self, forKey: .items)?.elements ?? []
        projects = c.lenientOptional(LossyDecodableArray<Project>.self, forKey: .projects)?.elements ?? []
        places = c.lenientOptional(LossyDecodableArray<Place>.self, forKey: .places)?.elements ?? []
        settings = c.lenient(AppSettings.self, forKey: .settings, default: AppSettings())
        meta = c.lenient(AppMeta.self, forKey: .meta, default: AppMeta())
    }
}

/// Snapshot for "Geri Al": restoring puts `before` back and hard-removes `createdIDs`.
public struct UndoToken: Equatable, Hashable, Identifiable {
    public var id: UUID
    public var label: String
    public var before: [Item]
    public var createdIDs: [UUID]

    public init(id: UUID = UUID(), label: String, before: [Item], createdIDs: [UUID] = []) {
        self.id = id
        self.label = label
        self.before = before
        self.createdIDs = createdIDs
    }
}
```

Schema migration rule: `schemaVersion` stays 1 while changes are additive. A breaking change (v2+) requires a `Migration.swift` in AsistCore mapping v1 → v2 before use; the store keeps `asist-data.v1.json` as a copy before migrating. The `.iso8601` date strategy is never changed (§3.1). Forward compatibility across *builds* (an older IPA reinstalled over newer data) is handled by `AppMeta.writerBuild` (D35, §3.6.4), not by `schemaVersion`.

### 3.3 Utilities (AsistCore) — exact files

#### 3.3.1

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Util/AsistCalendar.swift
import Foundation

public enum AsistCalendar {
    /// Gregorian, Monday-first, POSIX locale. App: device time zone. Tests/parser default: Europe/Istanbul.
    public static func make(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static var istanbul: TimeZone {
        TimeZone(identifier: "Europe/Istanbul") ?? TimeZone(secondsFromGMT: 3 * 3600)!
    }

    /// ISO weekday: 1 = Pazartesi … 7 = Pazar (Foundation `.weekday` is 1 = Sunday).
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        ((calendar.component(.weekday, from: date) + 5) % 7) + 1
    }

    /// ISO 1…7 → Foundation weekday 1 = Sunday … 7 = Saturday (for DateComponents.weekday).
    public static func foundationWeekday(fromISO iso: Int) -> Int {
        iso % 7 + 1
    }

    public static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    /// "yyyyMMdd" in `calendar`'s time zone.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return pad(c.year ?? 0, 4) + pad(c.month ?? 0, 2) + pad(c.day ?? 0, 2)
    }

    /// "yyyyMMddHHmm"
    public static func minuteKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return dayKey(date, calendar: calendar) + pad(c.hour ?? 0, 2) + pad(c.minute ?? 0, 2)
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// `day`'s calendar date at `time` (seconds = 0).
    public static func date(on day: Date, at time: ClockTime, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(time.minutesOfDay * 60))
    }

    public static func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 86_400))
    }

    public static func floorToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    public static func ceilToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.up) * 60)
    }

    /// Start of the day that is `count` workdays after `date`'s day (count >= 1).
    public static func addingWorkdays(_ count: Int, to date: Date, workdays: [Int], calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        var remaining = max(1, count)
        var guardCounter = 0
        while remaining > 0 && guardCounter < 400 {
            day = addingDays(1, to: day, calendar: calendar)
            if workdays.isEmpty || workdays.contains(isoWeekday(day, calendar: calendar)) {
                remaining -= 1
            }
            guardCounter += 1
        }
        return day
    }
}
```

#### 3.3.2

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Util/StableHash.swift
import Foundation

public enum StableHash {
    /// FNV-1a 64-bit, lowercase hex. Stable across launches/platforms (never use hashValue/Hasher for persistence).
    public static func fnv1a64(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
```

#### 3.3.3

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Text/TurkishText.swift
import Foundation

/// Locale-free Turkish casing and folding (identical on Linux and iOS; never uses tr_TR locale data).
public enum TurkishText {
    /// "IŞIK" → "ışık", "İzmir" → "izmir".
    public static func lower(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.precomposedStringWithCanonicalMapping {
            switch ch {
            case "I": out.append("ı")
            case "İ": out.append("i")
            default: out.append(contentsOf: String(ch).lowercased())
            }
        }
        return out
    }

    /// "istanbul" → "İSTANBUL", "ılık" → "ILIK".
    public static func upper(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.precomposedStringWithCanonicalMapping {
            switch ch {
            case "i": out.append("İ")
            case "ı": out.append("I")
            default: out.append(contentsOf: String(ch).uppercased())
            }
        }
        return out
    }

    /// First character upper-cased with Turkish rules, rest unchanged.
    public static func upperFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return upper(String(first)) + String(s.dropFirst())
    }

    /// Lowercase + diacritic fold: ç→c ğ→g ı→i ö→o ş→s ü→u â→a î→i û→u (02 §3.2).
    public static func fold(_ s: String) -> String {
        var out = ""
        for ch in lower(s) {
            switch ch {
            case "ç": out.append("c")
            case "ğ": out.append("g")
            case "ı": out.append("i")
            case "ö": out.append("o")
            case "ş": out.append("s")
            case "ü": out.append("u")
            case "â": out.append("a")
            case "î": out.append("i")
            case "û": out.append("u")
            case "i\u{0307}": out.append("i")
            default: out.append(ch)
            }
        }
        return out
    }

    /// Search/match key: fold, apostrophes removed, punctuation → space, single spaces, trimmed.
    public static func searchKey(_ s: String) -> String {
        var out = ""
        var lastWasSpace = true
        for ch in fold(s) {
            if ch == "'" || ch == "’" || ch == "‘" || ch == "`" || ch == "´" {
                continue
            }
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// Cuts at the last word boundary ≤ `max` characters and appends "…".
    public static func truncated(_ s: String, max: Int) -> String {
        guard s.count > max, max > 1 else { return s }
        let prefix = String(s.prefix(max - 1))
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) > max / 2 {
            return String(prefix[prefix.startIndex..<space]) + "…"
        }
        return prefix + "…"
    }
}
```

#### 3.3.4

```swift
// FILE: Packages/AsistCore/Tests/AsistCoreTests/TestSupport.swift
import Foundation
import XCTest
@testable import AsistCore

enum TestSupport {
    static let calendar: Calendar = TurkishParser.defaultCalendar()

    /// "2026-09-27T10:30" interpreted in `calendar` (Europe/Istanbul). Traps on malformed input (tests only).
    static func date(_ s: String, calendar: Calendar = TestSupport.calendar) -> Date {
        let parts = s.split(separator: "T")
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [0, 0]
        var comps = DateComponents()
        comps.year = d[0]; comps.month = d[1]; comps.day = d[2]
        comps.hour = t[0]; comps.minute = t[1]; comps.second = 0
        return calendar.date(from: comps)!
    }

    /// "yyyy-MM-dd'T'HH:mm" in `calendar`.
    static func format(_ date: Date, calendar: Calendar = TestSupport.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return AsistCalendar.pad(c.year!, 4) + "-" + AsistCalendar.pad(c.month!, 2) + "-" + AsistCalendar.pad(c.day!, 2)
            + "T" + AsistCalendar.pad(c.hour!, 2) + ":" + AsistCalendar.pad(c.minute!, 2)
    }

    /// Repository file `docs/design/parser_corpus.json`, located from this source file (D24).
    static var corpusURL: URL {
        designDirectory.appendingPathComponent("parser_corpus.json")
    }

    /// `docs/design/parser_corpus_extra.json` (05b cases, gate rules §3.4.6).
    static var corpusExtraURL: URL {
        designDirectory.appendingPathComponent("parser_corpus_extra.json")
    }

    private static var designDirectory: URL {
        URL(fileURLWithPath: #filePath)                 // …/Packages/AsistCore/Tests/AsistCoreTests/TestSupport.swift
            .deletingLastPathComponent()                 // AsistCoreTests
            .deletingLastPathComponent()                 // Tests
            .deletingLastPathComponent()                 // AsistCore
            .deletingLastPathComponent()                 // Packages
            .deletingLastPathComponent()                 // repo root
            .appendingPathComponent("docs/design", isDirectory: true)
    }
}
```

### 3.4 Parser and date/text APIs (AsistCore)

#### 3.4.1 Parser public types (02 §1 reconciled)

Changes versus 02 §1: `ItemKind`, `Priority`, `PlaceTrigger`, `Recurrence`, `ClockTime` now live in `Model/` (identical cases/raw values); all parser types get **public memberwise initializers** (tests and the v1.1 Smart Mode validator construct them). Revision 2 adds (05b, §3.4.6): `ParsedItem.leadTimesMinutes` (G10), `ParsedCommand.targetDate` (G3), `ParseFlag.nextWeekAmbiguous` (P2) and `.correctionApplied` (G8), `ParserSettings.ogledenOnce` / `hemenMinutes` (G7/G9). Everything else is exactly 02 §1.

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Parser/ParserTypes.swift
import Foundation

public enum ParsedKind: String, Codable, CaseIterable {
    case reminder, task, note, waiting, command
}

public struct PlaceRef: Equatable, Codable {
    public var name: String            // canonical spelling from ParserSettings.knownPlaces
    public var trigger: PlaceTrigger
    public init(name: String, trigger: PlaceTrigger) { self.name = name; self.trigger = trigger }
}

public enum CommandType: String, Codable {
    case query, complete, cancel, snooze
}

public enum QueryScope: String, Codable {
    case today, tomorrow, thisWeek, nextWeek, date, overdue, waiting, notes, tasks, all
}

public struct ParsedCommand: Equatable {
    public var type: CommandType
    public var scope: QueryScope?
    /// complete/cancel: day filter; snooze: the NEW date/time; query `.date` scope: the day.
    public var date: Date?
    public var queryText: String?
    public var snoozeMinutes: Int?
    public var project: String?
    public var person: String?
    /// snooze only (G3): day filter of the item to move ("cuma günkü toplantıyı pazartesiye ertele" → cuma).
    public var targetDate: Date?
    public init(type: CommandType, scope: QueryScope? = nil, date: Date? = nil, queryText: String? = nil,
                snoozeMinutes: Int? = nil, project: String? = nil, person: String? = nil, targetDate: Date? = nil) {
        self.type = type; self.scope = scope; self.date = date; self.queryText = queryText
        self.snoozeMinutes = snoozeMinutes; self.project = project; self.person = person
        self.targetDate = targetDate
    }
}

public struct ParsedItem: Equatable {
    public var kind: ItemKind
    public var title: String
    public var body: String?
    public var dueDate: Date?
    public var hasTime: Bool
    public var recurrence: Recurrence?
    public var priority: Priority
    public var person: String?
    public var project: String?
    public var place: PlaceRef?
    public var tags: [String]
    /// G10: spoken pre-alerts ("yarım saat önce hatırlat" → [30], "bir hafta önce" → [10080]); sorted, unique.
    public var leadTimesMinutes: [Int]
    public init(kind: ItemKind, title: String, body: String? = nil, dueDate: Date? = nil, hasTime: Bool = false,
                recurrence: Recurrence? = nil, priority: Priority = .normal, person: String? = nil,
                project: String? = nil, place: PlaceRef? = nil, tags: [String] = [], leadTimesMinutes: [Int] = []) {
        self.kind = kind; self.title = title; self.body = body; self.dueDate = dueDate; self.hasTime = hasTime
        self.recurrence = recurrence; self.priority = priority; self.person = person; self.project = project
        self.place = place; self.tags = tags; self.leadTimesMinutes = leadTimesMinutes
    }
}

public enum ParseFlag: String, Codable, Hashable, CaseIterable {
    case ambiguousHourPM, ambiguousHourNearest, ambiguousDotted, rolledToTomorrow, rolledToNextYear
    case defaultTimeApplied, pastDue, conflictingDates, invalidDateTime, needsTime, unsupportedRecurrence
    case multipleItems, unknownPlace, uncertainPerson, negation, titleFallback, vagueDate, noKindCue
    case tooShort, tooLong, unusedNumber, smartModeSuggested
    /// P2: "haftaya salı" said on Saturday/Sunday (2 or 9 days?) — confidence < 0.80, card offers "+7 gün".
    case nextWeekAmbiguous
    /// G8: a self-correction ("3'te hayır 4'te") replaced an earlier value.
    case correctionApplied
}

public struct ParseResult: Equatable {
    public var kind: ParsedKind
    public var item: ParsedItem?
    public var command: ParsedCommand?
    public var confidence: Double
    public var flags: Set<ParseFlag>
    public var understood: String
    public var relativePhrase: String?
    public var originalText: String
    public var normalizedText: String
    public init(kind: ParsedKind, item: ParsedItem?, command: ParsedCommand?, confidence: Double,
                flags: Set<ParseFlag>, understood: String, relativePhrase: String?, originalText: String,
                normalizedText: String) {
        self.kind = kind; self.item = item; self.command = command; self.confidence = confidence
        self.flags = flags; self.understood = understood; self.relativePhrase = relativePhrase
        self.originalText = originalText; self.normalizedText = normalizedText
    }
}

public struct ParserSettings: Equatable {
    public var defaultDayTime = ClockTime(9, 0)
    public var sabah = ClockTime(9, 0)
    public var ogledenOnce = ClockTime(11, 0)
    public var ogle = ClockTime(12, 0)
    public var ogledenSonra = ClockTime(14, 0)
    public var aksamustu = ClockTime(17, 0)
    public var aksam = ClockTime(19, 0)
    public var gece = ClockTime(22, 0)
    public var mesaiBasi = ClockTime(8, 30)
    public var mesaiBitimi = ClockTime(17, 30)
    public var birazdanMinutes = 15
    /// G9: "hemen / şimdi / derhal / acilen" without another time → now + hemenMinutes.
    public var hemenMinutes = 5
    public var belirsizSaatlerOgledenSonra = true
    public var knownProjects: [String] = []
    public var knownPlaces: [String] = []
    public var knownPeople: [String] = []
    public var smartModeThreshold = 0.60
    public var autoSaveThreshold = 0.80
    public init() {}
}
```

#### 3.4.2

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Parser/ParserSettings+App.swift
import Foundation

extension ParserSettings {
    /// App-side construction. Aliases are passed as additional project/place names; the caller maps
    /// the parser's returned name back to an id by folded match over `allNames` (ItemFactory does this).
    /// `people` = `ParserSettings.frequentPeople(in: store.items)` (05b §6.1: fixes lowercase names without apostrophes).
    public init(settings: AppSettings, projects: [Project], places: [Place], people: [String] = []) {
        self.init()
        defaultDayTime = settings.defaultDayTime
        sabah = settings.sabah
        ogledenOnce = settings.ogledenOnce
        ogle = settings.ogle
        ogledenSonra = settings.ogledenSonra
        aksamustu = settings.aksamustu
        aksam = settings.aksam
        gece = settings.gece
        mesaiBasi = settings.workStart
        mesaiBitimi = settings.workEnd
        belirsizSaatlerOgledenSonra = settings.ambiguousHoursPM
        knownProjects = projects.filter { !$0.archived }.flatMap { $0.allNames }
        knownPlaces = places.flatMap { $0.allNames }
        knownPeople = people
    }

    /// Distinct `Item.person` values used at least `minCount` times (folded comparison, first spelling wins),
    /// most frequent first, at most 50. Deleted items are ignored.
    public static func frequentPeople(in items: [Item], minCount: Int = 2) -> [String] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for item in items where item.status != .deleted {
            guard let raw = item.person?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let key = TurkishText.fold(raw)
            counts[key, default: 0] += 1
            if spelling[key] == nil {
                spelling[key] = raw
            }
        }
        let ranked = counts.filter { $0.value >= minCount }.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        return ranked.prefix(50).compactMap { spelling[$0.key] }
    }
}
```

#### 3.4.3 `TurkishParser` (WP1 owns; WP0 ships this stub verbatim)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Parser/TurkishParser.swift
import Foundation

public struct TurkishParser {
    public let settings: ParserSettings
    public let calendar: Calendar

    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = TurkishParser.defaultCalendar()) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Pure: depends only on (text, now, settings, calendar). Never reads Date()/Locale.current/TimeZone.current.
    public func parse(_ text: String, now: Date) -> ParseResult {
        // WP0 STUB — replaced by WP1 (02 §2 pipeline).
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Not" : TurkishText.upperFirst(trimmed)
        let item = ParsedItem(kind: .note, title: title, body: trimmed)
        return ParseResult(kind: .note, item: item, command: nil, confidence: 0.55, flags: [.noKindCue],
                           understood: "Not — " + title, relativePhrase: nil, originalText: text,
                           normalizedText: trimmed)
    }

    public static func defaultCalendar() -> Calendar {
        AsistCalendar.make(timeZone: AsistCalendar.istanbul)
    }
}
```

WP1 MAY add `internal` types/files freely under `Parser/`; the public surface above is frozen. Performance budget 02 §0 (< 5 ms/utterance on device).

#### 3.4.4 `TurkishDateFormatter` (WP1; 02 §13 is the behaviour spec)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Text/TurkishDateFormatter.swift
import Foundation

public enum TurkishDateFormatter {
    public static let months: [String]            // ["Ocak", …, "Aralık"]
    public static let monthsShort: [String]       // ["Oca","Şub","Mar","Nis","May","Haz","Tem","Ağu","Eyl","Eki","Kas","Ara"]
    public static let weekdays: [String]          // ISO 1…7: ["Pazartesi", …, "Pazar"]
    public static let weekdaysShort: [String]     // ["Pzt","Sal","Çar","Per","Cum","Cmt","Paz"]

    /// "09:05"
    public static func hhmm(_ hour: Int, _ minute: Int) -> String
    /// "15:00" of `date` in `calendar`.
    public static func time(_ date: Date, calendar: Calendar) -> String
    /// "Bugün" / "Yarın" / "Dün" / weekday name.
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String
    /// 02 §13 date phrase: "Salı 29 Eylül", "Yarın 1 Ocak 2027".
    public static func datePhrase(_ date: Date, now: Date, calendar: Calendar) -> String
    /// Row/notification label (03 §7.11): "Bugün 15:00", "Yarın 09:00", "Salı 15:00" (2–6 days),
    /// "6 Ekim Salı 15:00" (≥ 7 days or past beyond yesterday). `includeTime: false` drops the time.
    public static func shortDateTime(_ date: Date, now: Date, calendar: Calendar, includeTime: Bool) -> String
    /// 02 §13 relative phrase incl. parentheses: "(2 gün sonra)", "(yarın)", "(geçmiş)".
    public static func relativePhrase(to date: Date, now: Date, calendar: Calendar) -> String
    /// List-row relative text without parentheses (03 §7.12 "Göreli zaman"): "10 dk sonra", "2 saat sonra",
    /// "3 gün sonra", "Şimdi", "5 dk gecikti", "2 saat gecikti", "3 gündür bekliyor".
    public static func relativeShort(to date: Date, now: Date, calendar: Calendar) -> String
    /// "10 dakika", "1 saat", "1 saat 30 dakika", "1 gün", "1 hafta" (for pre-alerts, snooze toasts).
    public static func duration(minutes: Int) -> String
    /// 02 §13 recurrence text: "Her gün", "Hafta içi her gün", "Her Pazartesi ve Perşembe", "Her ayın 1'i", …
    public static func recurrenceText(_ recurrence: Recurrence) -> String
    /// Numeral + possessive suffix table (02 §13): 1 → "1'i", 3 → "3'ü", 20 → "20'si".
    public static func numeralPossessive(_ n: Int) -> String
}
```
WP0 stub: implement `hhmm`, `time`, tables literally; others may return `datePhrase = "d.M"`-style placeholders built only from `AsistCalendar.pad` (compiles, not user-visible quality).

#### 3.4.5 `RecurrenceEngine` (WP1)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Planning/RecurrenceEngine.swift
import Foundation

public enum RecurrenceEngine {
    /// Earliest instant **strictly after** `after` that matches `rule`, at wall-clock `time` in `calendar`.
    /// `anchor` = the item's current occurrence (used for interval > 1: weeks/days/months are counted from it;
    /// nil → counting starts at the first match). monthDay -1 = last day; 29–31 clamp to month length
    /// (03 §9 r36). yearly uses `month`/`monthDay`. Returns nil only for an invalid rule (e.g. weekly with no weekdays).
    public static func nextOccurrence(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                      calendar: Calendar) -> Date?

    /// Up to `count` consecutive occurrences strictly after `after` (planner uses count = 7, D27). Never loops
    /// more than 400 candidate days/months internally (invalid rules return []).
    public static func occurrences(of rule: Recurrence, time: ClockTime, after: Date, anchor: Date?,
                                   count: Int, calendar: Calendar) -> [Date]

    /// Latest occurrence `<= now` that is strictly after `current` (for roll-over of missed occurrences).
    public static func latestOccurrence(of rule: Recurrence, time: ClockTime, after current: Date, upTo now: Date,
                                        calendar: Calendar) -> Date?
}
```
The parser's §9.3 first-occurrence resolution MUST call `nextOccurrence` (one implementation). WP0 stub: daily semantics (`addingDays(1)` at `time`).

#### 3.4.6 Binding amendments to 02 (from 05b §6) and the corpus gate (WP1)

These rules override 02 wherever they conflict. The full lexicon for each rule is the `proposedRule` text of the named cases in `docs/design/parser_corpus_extra.json`.

| Id | Rule (summary) | Cases |
|---|---|---|
| G1 | A number + LOC/DAT suffix directly after an equipment noun (hat/hattı, istasyon, robot, hücre, pano, kat, bant, konveyör, eksen, makine, kabin, no, numara) is part of the noun, never a clock; `N nolu / numaralı / no'lu` consumes the number without `unusedNumber`. | xeq-001…004 |
| G2 | Waiting verbs: final `gelecek` (not followed by hafta/ay/yıl/sene/weekday), `haber verecek`, `bilgi verecek`, `dönüş sağlayacak`, `atacak`, `paylaşacak`, `yükleyecek`, `çıkaracak`, `kesecek`, `ayarlayacak`, `bitirecek`, `bekliyoruz`, `bekleniyor`, `bekleyeceğiz`; a capitalised plural/common noun at index 0 is not a person (P7 restriction). | xwai-001…005 |
| G3 | Reschedule = snooze cues: `kaydır`, `taşı`, `ötele`, `sonraya at/bırak`, DATE+DAT `bırak`, `(bunu/onu/…işini) DATE+DAT al`; weekday + `günkü/günki` fills `ParsedCommand.targetDate`. | xsnz-001…005 |
| G4 | Cancel cues += `iptal oldu`, `iptal edildi`, `yapılmayacak`, two-token `boş ver`. | xcnl-001/002 |
| G5 | Completion accepts -DIk forms wherever -DIm is accepted (`hallettik`, `aldık`); final `geldi / ulaştı / elime geçti / teslim alındı / gitti` = complete (FuzzyMatcher prefers waiting items). | xcmp-001…004 |
| G6 | Query rules run **before** the generic -DIm completion rule: `ne(yi/leri) unuttum / kaçırdım / atladım` = overdue query; `… var mı` = query with the content noun as `queryText`. | xqry-001…003 |
| G7 | Time words: `N gibi / civarı / sularında`; possessive dayparts (`salı sabahı`, `cuma akşamı`); `öğleden önce` = `ogledenOnce` (11:00); `bugün içinde / gün içinde / bugün bir ara` = today policy with `hasTime = false`; `N'den sonra` = clock N; `öğle yemeğinden sonra` = öğle + 60 min; an explicit `bu gece / gece vardiyası` anywhere qualifies a 1–6 clock as night. | xtim-001…007 |
| G8 | Self-corrections: `hayır / yok / pardon / yani / değil de / yok yok` between two values of the same type → the **last** value wins, flag `.correctionApplied`. | xcor-001/002 |
| G9 | `hemen / şimdi / derhal / acilen` with no other time → now + `hemenMinutes` (5); `bu hafta (içinde) / hafta bitmeden` → last workday of this week at default time, flag `.vagueDate`. | xpri-001/002 |
| G10 | `DURATION önce (hatırlat / haber ver / uyar / söyle)` and `DURATION kala` → `ParsedItem.leadTimesMinutes`, phrase removed from the title. | xlead-001/002 |
| G11 | Version context (`4.20'ye güncelle`, `v1.2`, `sürüm`) is never a clock; `son gün / son tarih` is a day-of-month only after `ayın` or a month name; engineering units (V, volt, bar, mm, kW, A, Hz, adet, kg) suppress `unusedNumber`. | xtech-001/002 |
| G12 | `her N ayda bir` = monthly, interval N, first occurrence today + N months at default time; "her ayın ilk pazartesi" (n'th weekday) → `recurrence = nil`, flag `.unsupportedRecurrence`, confidence ≤ 0.59 (review; never silently wrong). | xrec-001/002 |
| C2 | Priority words: `acil, acilen, önemli, mutlaka` → **high**; `çok acil, kritik, hayati, sakın unutma, asla unutma` → **critical**. | pri-* |

Spec decisions (they change existing expectations):

| # | Decision | Corpus effect |
|---|---|---|
| P1 | "haftaya" / "gelecek hafta" **without weekday** = next week's **first workday** at default time. | update day-008, day-009 (xsnz-004) |
| P2 | "haftaya salı" said on Saturday/Sunday keeps 02's value (2 days later) but sets `.nextWeekAmbiguous`: confidence capped at 0.79 and the card offers "+7 gün". | — |
| P3 | A bare weekday equal to today ("salı" on a Tuesday) stays **+7 days** (02; matches the user's "gelecek ilk salı"); the card shows "6 Ekim Salı · 7 gün sonra" and offers a "Bugün" chip when today's time is still ahead. 03 §5.7 is wrong. | — |
| P4 | "Acil: … Hakan'la konuş" (high/critical task without date) → reminder that asks "Ne zaman?" (ItemFactory, D20). | — |
| P5 | "öğlen yemekten sonra" = 13:00 (öğle + 60). | update dp-003 (xtim-006) |
| P6 | "çok acil … hemen ara" = now + 5 min, critical. | update pri-009 (xpri-001) |

Corpus gate (CorpusTests, D24):
1. `parser_corpus.json`: 100 % of cases. WP1 may change **only** the expectations of day-008, day-009, dp-003, pri-009 and the `pri-*` cases whose only trigger word is `acil/acilen/önemli/mutlaka` (critical → high); every changed id is listed in the PR description. WP1 also adds the seven one-liners of 05b §6.3 ("cuma akşamı yedeklemeyi kontrol et", "yarın öğlen arası Hakan'ı ara", "cuma mesai bitimine kadar raporu teslim et", "24 volt beslemeyi yarın 2'de ölç", "Ahmet'e sor sürücüler geldi mi", "sırada ne var", "Mehmet'i ara, sipariş durumunu sor") with expectations derived from G7/G11 and 02.
2. `parser_corpus_extra.json`: same harness; reference now `mon_work` = 2026-09-28T10:10; keys `status`, `gap`, `proposedRule`, `conflictsWith` are ignored; `expected.leadMinutes` is compared with `item.leadTimesMinutes`, `command.targetDate` (`YYYY-MM-DD`) with `command.targetDate`; `settings.hemenMinutes` / `settings.ogledenOnce` are loaded into `ParserSettings`. Gate: 100 % **except** ids listed in `CorpusTests.deferredExtraCases` (at most 6, each with a one-line reason comment); deferred cases are printed as warnings, never silently skipped.
3. The speech recognizer gets `contextualStrings` = 01b §1.8 jargon + project names/aliases + `frequentPeople` (≤ 100 total, `CaptureService.contextualStrings()`).

### 3.5 Planning, agenda, matching, capture, links (AsistCore)

#### 3.5.1 Notification catalog — exact

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Planning/NotificationCatalog.swift
import Foundation

public enum NotificationID {
    public static let prefix = "asist."
    /// Requests the app schedules ad hoc (test, feedback); never touched by the diff-apply.
    public static let unmanagedPrefix = "asist.x."
    /// v1.2 location reminders (Appendix B.3). No v1.0 code creates these ids; the diff-apply never touches them.
    public static let locationPrefix = "asist.loc."

    public static func chain(_ itemID: UUID, _ k: Int) -> String { "asist.i.\(itemID.uuidString).\(k)" }
    public static func preAlert(_ itemID: UUID, minutes: Int) -> String { "asist.i.\(itemID.uuidString).pre.\(minutes)" }
    public static func longTail(_ itemID: UUID) -> String { "asist.i.\(itemID.uuidString).d" }
    public static func occurrence(_ itemID: UUID, minuteKey: String) -> String { "asist.i.\(itemID.uuidString).o.\(minuteKey)" }
    /// Repeating carrier of future occurrences (D27). suffix: "d" (daily), "w1"…"w7" (Foundation weekday), "m" (monthly).
    public static func carrier(_ itemID: UUID, suffix: String) -> String { "asist.i.\(itemID.uuidString).r.\(suffix)" }
    public static func location(_ itemID: UUID) -> String { "asist.loc.\(itemID.uuidString)" }
    public static func briefing(dayKey: String) -> String { "asist.brief.\(dayKey)" }
    public static func endOfDay(dayKey: String) -> String { "asist.eod.\(dayKey)" }
    public static let backup = "asist.backup"
    public static func signing(minuteKey: String) -> String { "asist.sign.\(minuteKey)" }
    /// Budget sentinel: a copy of the earliest dropped item notification (05b B5); carries that item's iid.
    public static let sentinel = "asist.sentinel"
    /// Horizon sentinel: "Asist'i bir kez aç" after the last planned item notification (05a #23, 05b B3).
    public static let horizonSentinel = "asist.sentinel.h"
    public static let test = "asist.x.test"
    public static let movedFeedback = "asist.x.moved"

    /// thread identifier: all notifications of one item stack together.
    public static func thread(_ itemID: UUID) -> String { "asist.i.\(itemID.uuidString)" }
    public static let digestThread = "asist.digest"
    public static let systemThread = "asist.system"

    /// Item UUID for "asist.i.<UUID>…" and "asist.loc.<UUID>"; nil otherwise.
    public static func itemID(from identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "asist", parts[1] == "i" || parts[1] == "loc" else { return nil }
        return UUID(uuidString: String(parts[2]))
    }

    /// Owned by NagPlanner + NotificationScheduler diff-apply.
    public static func isPlannerManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix) && !identifier.hasPrefix(unmanagedPrefix) && !identifier.hasPrefix(locationPrefix)
    }
}

public enum NotificationCategoryID {
    public static let item = "ASIST_ITEM"
    /// Pre-alerts: only "✓ Yaptım" (+ default tap) — a pre-alert can never snooze/re-anchor the item (05a #13).
    public static let preAlert = "ASIST_PRE"
    public static let followUp = "ASIST_FOLLOWUP"
    public static let briefing = "ASIST_BRIEF"
    public static let endOfDay = "ASIST_EOD"
    public static let system = "ASIST_SYSTEM"
}

public enum NotificationActionID {
    // ASIST_ITEM (background, no unlock); ASIST_PRE uses `done` only
    public static let done = "ASIST_DONE"
    public static let snooze10 = "ASIST_SNOOZE_10"
    public static let snooze60 = "ASIST_SNOOZE_60"
    public static let tomorrow = "ASIST_TOMORROW"
    // ASIST_FOLLOWUP
    public static let followUpReceived = "ASIST_FU_RECEIVED"   // background
    public static let followUpTomorrow = "ASIST_FU_TOMORROW"   // background
    public static let followUpTwoDays = "ASIST_FU_2DAYS"       // background
    public static let followUpMessage = "ASIST_FU_MESSAGE"     // .foreground
    // ASIST_BRIEF
    public static let briefingRead = "ASIST_BRIEF_READ"        // .foreground
    // ASIST_EOD
    public static let endOfDayMove = "ASIST_EOD_MOVE"          // background
    public static let endOfDayReview = "ASIST_EOD_REVIEW"      // .foreground
}

/// userInfo keys (values are String or Int only).
public enum NotificationUserInfoKey {
    public static let itemID = "iid"          // UUID string ("" when none)
    public static let attempt = "k"           // Int
    public static let fingerprint = "fp"      // String
    public static let kind = "nk"             // PlannedNotification.Kind rawValue
}
```

#### 3.5.2 Planned notification, plan input/result — exact

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Planning/PlannedNotification.swift
import Foundation

public struct PlannedNotification: Equatable, Hashable {
    public enum Rule: Equatable, Hashable {
        case once
        /// Repeats every day at hour:minute (wall clock, no time zone component).
        case daily(hour: Int, minute: Int)
        /// Foundation weekday (1 = Sunday … 7 = Saturday).
        case weekly(weekday: Int, hour: Int, minute: Int)
        /// Repeats every month on `day` (1…28 only) at hour:minute (recurrence carriers, D27).
        case monthly(day: Int, hour: Int, minute: Int)

        public var stableDescription: String {
            switch self {
            case .once: return "once"
            case .daily(let h, let m): return "daily-\(h):\(m)"
            case .weekly(let w, let h, let m): return "weekly-\(w)-\(h):\(m)"
            case .monthly(let d, let h, let m): return "monthly-\(d)-\(h):\(m)"
            }
        }
    }

    public enum Interruption: String, Equatable, Hashable { case passive, active, timeSensitive }

    public enum Kind: String, Equatable, Hashable {
        case first, nag, preAlert, longTail, occurrence, carrier, briefing, endOfDay, backup, signing, sentinel, horizon
    }

    public var id: String
    public var kind: Kind
    public var itemID: UUID?
    public var attempt: Int
    /// For repeating rules: the first expected fire (sorting/tiering only).
    public var fireDate: Date
    public var rule: Rule
    public var title: String
    public var subtitle: String
    public var body: String
    public var threadID: String
    public var categoryID: String
    /// Projected badge at fire time; nil for repeating rules (leave badge unchanged).
    public var badge: Int?
    public var interruption: Interruption
    public var relevance: Double
    public var playsSound: Bool
    /// Bundled sound file name ("asist-onemli.wav", "asist-kritik.wav"); nil = system default (D37).
    public var soundName: String?
    /// 0 = most important (kept first under budget pressure).
    public var tier: Int
    public var fingerprint: String

    public init(id: String, kind: Kind, itemID: UUID?, attempt: Int, fireDate: Date, rule: Rule,
                title: String, subtitle: String, body: String, threadID: String, categoryID: String,
                badge: Int?, interruption: Interruption, relevance: Double, playsSound: Bool, tier: Int,
                soundName: String? = nil) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.attempt = attempt
        self.fireDate = fireDate
        self.rule = rule
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadID = threadID
        self.categoryID = categoryID
        self.badge = badge
        self.interruption = interruption
        self.relevance = relevance
        self.playsSound = playsSound
        self.soundName = soundName
        self.tier = tier
        self.fingerprint = ""
        self.fingerprint = computeFingerprint()
    }

    /// Everything that affects the system request. Repeating rules ignore fireDate/badge.
    public func computeFingerprint() -> String {
        let repeating = rule != .once
        let time = repeating ? 0 : Int(fireDate.timeIntervalSince1970)
        let badgeText = repeating ? "-" : String(badge ?? -1)
        let raw = [id, String(time), rule.stableDescription, title, subtitle, body, badgeText, categoryID,
                   threadID, interruption.rawValue, playsSound ? "s" : "q", soundName ?? "-"].joined(separator: "|")
        return StableHash.fnv1a64(raw)
    }

    public mutating func refreshFingerprint() {
        fingerprint = computeFingerprint()
    }
}

public struct PlanInput {
    public static let defaultReservedSlots = 14

    public var items: [Item]
    public var projects: [Project]
    public var places: [Place]
    public var settings: AppSettings
    public var now: Date
    public var calendar: Calendar
    /// Profile expiry; nil when the embedded profile is unreadable (then no signing notifications, no clamp).
    public var signingExpiry: Date?
    /// Pending `asist.loc.*` requests (v1.2; always 0 in v1.0).
    public var locationSlotsUsed: Int
    /// false when UNNotificationSettings.timeSensitiveSetting != .enabled → every .timeSensitive becomes .active (05b B7).
    public var allowTimeSensitive: Bool
    public var totalBudget: Int
    public var reservedSlots: Int

    public init(items: [Item], projects: [Project], places: [Place], settings: AppSettings, now: Date,
                calendar: Calendar, signingExpiry: Date?, locationSlotsUsed: Int = 0,
                allowTimeSensitive: Bool = true, totalBudget: Int = 64,
                reservedSlots: Int = PlanInput.defaultReservedSlots) {
        self.items = items
        self.projects = projects
        self.places = places
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.signingExpiry = signingExpiry
        self.locationSlotsUsed = locationSlotsUsed
        self.allowTimeSensitive = allowTimeSensitive
        self.totalBudget = totalBudget
        self.reservedSlots = reservedSlots
    }

    /// Slots available to item notifications (chain, day-tail, pre-alerts, long-tails, occurrences, carriers).
    public var itemBudget: Int { max(0, totalBudget - reservedSlots - locationSlotsUsed) }
}

public struct PlanResult: Equatable {
    /// Item notifications (≤ itemBudget) + reserved ones (≤ reservedSlots). Sorted by (tier, fireDate, id).
    public var notifications: [PlannedNotification]
    /// Budget drops of tiers 0…3 (tier-4 far-future drops and rate-limited nags are not counted).
    public var droppedCount: Int
    public var earliestDroppedDate: Date?
    /// Nags removed by the rate limiter (§6.4 step 5; diagnostics only).
    public var rateLimitedCount: Int
    /// Badge to set now (respecting BadgeMode).
    public var badgeNow: Int
    public var itemBudget: Int

    public init(notifications: [PlannedNotification], droppedCount: Int, earliestDroppedDate: Date?,
                rateLimitedCount: Int, badgeNow: Int, itemBudget: Int) {
        self.notifications = notifications
        self.droppedCount = droppedCount
        self.earliestDroppedDate = earliestDroppedDate
        self.rateLimitedCount = rateLimitedCount
        self.badgeNow = badgeNow
        self.itemBudget = itemBudget
    }
}
```

`self.fingerprint = ""` before calling a method on `self` is required (all stored properties must be initialized before `computeFingerprint()` is callable). A default argument may reference `PlanInput.defaultReservedSlots` (static member of the same type).

#### 3.5.3 `NagPlanner` (WP3; algorithm §6.4)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Planning/NagPlanner.swift
import Foundation

public enum NagPlanner {
    /// Pure. Same input → same output (ids, order, fingerprints). Algorithm §6.4.
    public static func plan(_ input: PlanInput) -> PlanResult

    /// 05b B1: the first `limit` one-shot (`.once`) notifications of `item`, computed exactly as `plan` would for an
    /// input that contains only this item (same ids, content and fingerprints; no reserved slots, no sentinels,
    /// no rate limiter, no budget). Used by ReminderEngine.handle before completionHandler().
    public static func immediateRequests(for item: Item, input: PlanInput, limit: Int) -> [PlannedNotification]

    /// Full chain for an anchor (index = k; element 0 == anchor; `.etkinlik` → [anchor]). Honours quiet hours,
    /// work hours, daily caps and the mute window (`settings.muteUntil`, active only while `now < muteUntil`).
    /// Used by plan(), tests and the Settings preview.
    public static func chain(anchor: Date, profile: NagProfile, profileKind: NagProfileKind, isCritical: Bool,
                             settings: AppSettings, now: Date, calendar: Calendar) -> [Date]

    /// "Yarın sabah": before 05:00 → today's day start; else next day's day start
    /// (workStart on workdays, offDayStart otherwise).
    public static func tomorrowMorning(after now: Date, settings: AppSettings, calendar: Calendar) -> Date

    /// Takip re-ask: `workdays` workdays after `now` at settings.followUpAskTime.
    public static func followUpAsk(after now: Date, workdays: Int, settings: AppSettings, calendar: Calendar) -> Date

    /// "Bu akşam" = today at settings.aksam; nil if now is past 18:30.
    public static func thisEvening(now: Date, settings: AppSettings, calendar: Calendar) -> Date?

    /// "Pazartesi" = next Monday (strictly after today) at day start.
    public static func nextMonday(now: Date, settings: AppSettings, calendar: Calendar) -> Date

    /// Mute preset "Mesai sonuna kadar" (D32): today's workEnd when now is before it on a workday, else now + 2 h
    /// (ceil to minute).
    public static func muteUntilWorkEnd(now: Date, settings: AppSettings, calendar: Calendar) -> Date

    /// Open, non-note, non-event items overdue at `date` (+ due today when mode == .overdueAndToday; 0 when .off).
    public static func badgeCount(items: [Item], at date: Date, settings: AppSettings, calendar: Calendar) -> Int
}
```
WP0 stub: `plan` returns one `.first` notification per open notifiable item with a future anchor (tier 0, no badge, `rateLimitedCount` 0), `immediateRequests` returns `[]`, `chain` returns `[anchor]`, helpers return simple values (`muteUntilWorkEnd` = now + 2 h).

#### 3.5.4 `TurkishSpeech` (WP2; 03 §5.12 is the behaviour spec)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Text/TurkishSpeech.swift
import Foundation

public enum TurkishSpeech {
    /// Honest answer when the data file cannot be read (device not unlocked since reboot) — 05a #3/#26.
    public static let dataUnavailable = "Şu an kayıtlarına erişemiyorum. Telefonun kilidini açıp tekrar dener misin?"
    /// Headless save failed (disk full / write error) — 05a #3.
    public static let saveFailed = "Kaydedemedim; telefonda yer kalmamış olabilir. Asist'i açıp kontrol et."
    /// 0…99 in words: 15 → "on beş", 40 → "kırk".
    public static func numberWords(_ n: Int) -> String
    /// Locative suffix after digits for display, chosen by the spoken last word (03 §5.12):
    /// 1 → "'de", 3 → "'te", 6 → "'da", 10 → "'da", 20 → "'de", 30 → "'da", 40 → "'ta", 50 → "'de".
    public static func locativeSuffix(forNumber n: Int) -> String
    /// Display form: (15, 0) → "15'te", (15, 30) → "15:30'da", (9, 0) → "9'da", (0, 0) → "gece yarısı".
    public static func displayClockLocative(hour: Int, minute: Int) -> String
    /// 24-hour spoken form (kept for tests/diagnostics): (15, 0) → "on beşte", (15, 30) → "on beş otuzda".
    public static func spokenClockLocative(hour: Int, minute: Int) -> String
    /// 12-hour clock with daypart for TTS (05b F12): (15,0) → "öğleden sonra üçte", (9,0) → "sabah dokuzda",
    /// (20,0) → "akşam sekizde", (12,0) → "öğlen on ikide", (15,30) → "öğleden sonra üç buçukta",
    /// (15,15) → "öğleden sonra üç on beşte", (2,0) → "gece ikide", (0,0) → "gece yarısı".
    /// Dayparts: 05:00–11:59 sabah · 12:00–12:59 öğlen · 13:00–17:59 öğleden sonra · 18:00–21:59 akşam · 22:00–04:59 gece.
    public static func spokenTimeOfDay(hour: Int, minute: Int) -> String
    /// "bugün öğleden sonra üçte", "yarın sabah dokuzda", "salı öğleden sonra üç buçukta", "29 Ekim sabah onda"
    /// (weekday names lowercase, month names capitalised, no "saat"). Screens keep the 24-hour clock.
    public static func spokenWhen(_ date: Date, now: Date, calendar: Calendar) -> String
    /// TTS/Siri confirmation after saving (03 §7.12 `tts.saved.*`). `headless` adds the title (Siri path).
    /// Never places a suffix directly after a placeholder (03 §5.12). Result is `dialogSafe`.
    public static func confirmation(for item: Item, projectName: String?, headless: Bool, lowConfidence: Bool,
                                    appliedDefaultTime: Bool, now: Date, calendar: Calendar) -> String
    /// Text safe for `IntentDialog(LocalizedStringResource(stringLiteral:))`: every "%" becomes " yüzde ",
    /// runs of spaces collapse to one, result trimmed (05a #32). Applied to every spoken/dialog string.
    public static func dialogSafe(_ text: String) -> String
}
```
Required outputs (tests, `now` = Sun 2026-09-27 10:30): reminder `"Tamam, salı öğleden sonra üçte hatırlatacağım."`; headless `"Tamam, salı öğleden sonra üçte hatırlatacağım: Teklif konusu."`; task defaulted to today (D33) `"Tamam, görevlere ekledim; bugün içinde hatırlatacağım."`; task explicitly without time ("Zamanı belirsiz") `"Görevlere ekledim."`; task with untimed due Friday `"Tamam, görevlere ekledim; cuma sabah dokuzda hatırlatacağım."`; event `"Tamam, perşembe öğleden sonra ikide; on beş dakika önce haber vereceğim."`; note `"Not aldım."` / `"Arka Cep projesine not aldım."`; waiting `"Tamam, cuma günü takip edeceğim."`; appliedDefaultTime `"Zaman söylemedin; bir saat sonra hatırlatacağım."`; low confidence headless `"“<title>” olarak kaydettim. Emin olmak için Asist'i aç."`; `dialogSafe("%50 indirim teklifi")` = `"yüzde 50 indirim teklifi"`.

#### 3.5.5 Agenda, notification copy, fuzzy matching (WP2)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Agenda/AgendaBuilder.swift
import Foundation

public struct DayGroup: Equatable, Identifiable {
    public var id: String { AsistCalendar.pad(Int(day.timeIntervalSince1970), 12) }
    public var day: Date            // start of day
    public var title: String        // "Yarın", "Salı", "6 Ekim Salı"
    public var items: [Item]
    public init(day: Date, title: String, items: [Item])
}

public struct AgendaSnapshot: Equatable {
    public var overdue: [Item]      // priority desc, then oldest anchor first (hero = first); never events
    public var review: [Item]       // needsReview && open (any kind except note) — section "EMİN OLAMADIKLARIM"
    public var today: [Item]        // due today, not overdue, by anchor (events included); untimed tasks last ("Gün içinde")
    public var followUps: [Item]    // open .waiting items whose anchor is today (not overdue)
    public var upcoming: [DayGroup] // next 7 days after today, max 5 rows total → `upcomingTotal`
    public var upcomingTotal: Int
    public var unscheduled: [Item]  // open task/waiting/reminder without anchor — section "ZAMANI BELİRSİZ"
    public var doneThisWeek: Int    // completedAt in current Monday-first week
    public var overdueCount: Int { overdue.count }
    public init(overdue: [Item], review: [Item], today: [Item], followUps: [Item], upcoming: [DayGroup],
                upcomingTotal: Int, unscheduled: [Item], doneThisWeek: Int)
}

public struct SpokenAnswer: Equatable, Identifiable {
    public var id: String { title + "|" + text }
    public var title: String        // sheet title: "Bugünün ajandası"
    public var text: String         // TTS text (numbers as words, ≤ 5 items then "Diğerleri ekranda."), dialogSafe
    public var itemIDs: [UUID]      // items to list on screen, in spoken order
    public init(title: String, text: String, itemIDs: [UUID])
}

public struct NotificationText: Equatable {
    public var title: String
    public var subtitle: String
    public var body: String
    public init(title: String, subtitle: String, body: String)
}

public enum AgendaBuilder {
    public static func snapshot(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> AgendaSnapshot
    /// Query command (02 §10.5.1 scopes + project/person/queryText filters) → spoken + on-screen answer (03 §5.9).
    public static func answer(to command: ParsedCommand, items: [Item], projects: [Project], now: Date,
                              settings: AppSettings, calendar: Calendar) -> SpokenAnswer
    public static func todaySpoken(items: [Item], projects: [Project], now: Date, settings: AppSettings,
                                   calendar: Calendar) -> SpokenAnswer
    public static func overdueSpoken(items: [Item], now: Date, settings: AppSettings, calendar: Calendar) -> SpokenAnswer
    /// Content projected for the moment the briefing fires (03 §3.9). Body lists up to 3 titles overdue at
    /// `fireDate`: "Geciken: Teklif konusu, Ahmet'i ara +2" (05b B3), then today's count. nil = do not send
    /// (nothing overdue/today and !briefingWhenEmpty).
    public static func briefing(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText?
    /// 03 §3.10. Candidates as `endOfDayCandidates`; later-today timed items are listed separately
    /// ("Bu akşam: 18:00 Ekmek al") and are NOT moved (05b B6). nil = no candidates → do not send.
    public static func endOfDay(items: [Item], at fireDate: Date, settings: AppSettings, calendar: Calendar) -> NotificationText?
    /// Items affected by "Sonraki iş gününe taşı" at `now`: overdue + untimed today + timed today with anchor ≤ now;
    /// open reminder/task/waiting only; excludes notes, events and recurring items (05b B6).
    public static func endOfDayCandidates(items: [Item], now: Date, calendar: Calendar) -> [Item]
    /// Pure move to the next day (the next **workday** when settings.moveSkipsWeekend): timed → same clock time;
    /// untimed → defaultDayTime with hasTime = false; resets nag state; appends history .movedEndOfDay.
    public static func movedToTomorrow(_ item: Item, now: Date, settings: AppSettings, calendar: Calendar) -> Item
    /// Human-readable safety copy written next to the backups (05b A1): header "Asist — açık işler (27 Eylül 2026 10:30)",
    /// then open non-note items sorted by anchor (undated last), one per line:
    /// "Salı 29.09 15:00 · Teklif konusu · Ahmet · Arka Cep", overdue lines prefixed "GECİKEN · ". Plain UTF-8, LF.
    public static func openItemsText(items: [Item], projects: [Project], now: Date, calendar: Calendar) -> String
}
```

```swift
// API: Packages/AsistCore/Sources/AsistCore/Agenda/NotificationCopy.swift
import Foundation

public enum NotificationCopy {
    /// k = 0 (first alert) and k ≥ 1 (nag) of reminder/task items (03 §3.2 table, 01a §7.3, 05b C6/F9/F10):
    /// title = item.title (≤ 60 chars, "…");
    /// subtitle k=0: "<Salı 15:00> · <Proje> · <Önemli/Kritik>";
    /// k≥1: "<N> dakikadır|saattir|gündür bekliyor · <k+1>. hatırlatma" (critical prefix "KRİTİK · ");
    /// snoozeCount ≥ 3 → "<n>. erteleme · başka bir gün mü?";
    /// isLastOfDay (the next planned element of this item is on a later day) → "Bugünlük son hatırlatma · yarın sabah yine".
    /// body line 1 = “<originalText>” (or the first 2 lines of notes); line 2:
    /// k = 0 → "“✓ Yaptım” diyene kadar hatırlatmaya devam edeceğim."; k ≥ 1 → "Sonraki: 15:30";
    /// nextFireDate == nil (nothing planned after this one) → "Asist'i bir kez açarsan hatırlatmaya devam ederim." (05a #2).
    public static func itemContent(item: Item, projectName: String?, attempt: Int, fireDate: Date,
                                   nextFireDate: Date?, isLastOfDay: Bool, calendar: Calendar) -> NotificationText
    /// Events (D31): title = item.title; subtitle "<Perşembe 14:00> · <Proje>"; body = original text (no repeat promise).
    public static func eventContent(item: Item, projectName: String?, calendar: Calendar) -> NotificationText
    /// Waiting items: title "Takip · <person>: <title>" (or "Takip: <title>");
    /// k=0 subtitle: item.hasTime ? "Geldi mi? · Son tarih: <Cuma>" : "Geldi mi? · <n> gündür bekliyor" (05b F8; n from createdAt);
    /// k≥1 "<k+1>. kez soruyorum — geldi mi?".
    public static func followUpContent(item: Item, attempt: Int, fireDate: Date, calendar: Calendar) -> NotificationText
    /// "<30 dakika> sonra: <title>" / "<Salı 15:00> · <Proje>" (category ASIST_PRE).
    public static func preAlertContent(item: Item, projectName: String?, leadMinutes: Int, calendar: Calendar) -> NotificationText
    /// Daily repeating safety net (static text): subtitle "Hâlâ açık · her sabah soracağım" (05b F11).
    public static func longTailContent(item: Item, projectName: String?) -> NotificationText
    /// Repeating carrier of a recurring item (static text): subtitle "<Her gün 09:00> · tekrarlayan".
    public static func recurrenceCarrierContent(item: Item, projectName: String?) -> NotificationText
    public static func backupContent() -> NotificationText        // "Yedek zamanı" / "" / "Kayıtlarının bir yedeğini almak ister misin?"
    /// Body: "İmzanın bitmesine <3 gün> kaldı. Yenilemezsen hatırlatmaların susar. Sideloadly ile yenile, sonra Asist'i bir kez aç." (05b A1)
    public static func signingContent(expiry: Date, fireDate: Date, calendar: Calendar) -> NotificationText
    /// At expiry: title "Asist'in imzası doldu"; body "Sideloadly ile yenile, sonra Asist'i bir kez aç. O zamana kadar “✓ Yaptım” çalışmaz."
    public static func signingExpiredContent() -> NotificationText
    /// Appended as a new body line to the budget sentinel (a copy of the earliest dropped notification, 05b B5/F16):
    /// "+<n> hatırlatma daha — planı tazelemek için Asist'i aç".
    public static func budgetSentinelLine(extraCount: Int) -> String
    /// Horizon sentinel: "Asist'i bir kez aç" / "<n> açık iş var" /
    /// "Hatırlatmaya devam edebilmem için planı tazelemem gerekiyor. Bir kez açman yeter."
    public static func horizonSentinelContent(openCount: Int) -> NotificationText
    public static func testContent() -> NotificationText          // "Deneme: Asist çalışıyor" …
    public static func movedFeedbackContent(count: Int) -> NotificationText     // "<n> iş sonraki iş gününe taşındı. Geri almak için dokun."
}
```

```swift
// API: Packages/AsistCore/Sources/AsistCore/Matching/FuzzyMatcher.swift
import Foundation

public struct FuzzyMatch: Equatable {
    public var itemID: UUID
    public var score: Double        // 0…1
    public init(itemID: UUID, score: Double)
}

public enum MatchDecision: Equatable {
    case single(UUID)               // best ≥ 0.60 and (second < 0.40 or best − second ≥ 0.25)
    case ambiguous([UUID])          // 2–3 candidates ≥ 0.40
    case none
}

public enum FuzzyMatcher {
    /// Tokens: TurkishText.searchKey, apostrophe suffix and common case suffixes stripped
    /// (i ı u ü yi yı yu yü e a ye ya de da te ta den dan ten tan in ın un ün nin nın le la yle yla),
    /// stop words removed (hatırlatma, hatırlatmasını, görev, işi, konusu→konu, bunu, şunu).
    public static func tokens(_ text: String) -> [String]
    /// Token-set similarity over title + person + project name + originalText (title weighted 2×);
    /// prefix match of ≥ 4 letters counts as a hit ("teklif" ~ "teklifi").
    public static func score(query: String, item: Item, projectName: String?) -> Double
    /// Only open, non-deleted items; optional filters narrow the set first (date = same day as anchor;
    /// for snooze commands the caller passes `command.targetDate ?? nil` as `date`). `preferWaiting` (G5 "geldi")
    /// adds +0.15 to waiting items.
    public static func rank(query: String?, person: String?, project: String?, date: Date?, preferWaiting: Bool,
                            items: [Item], projects: [Project], calendar: Calendar) -> [FuzzyMatch]
    public static func decide(_ ranked: [FuzzyMatch]) -> MatchDecision
}
```

#### 3.5.6 Capture factory and checklist templates (WP2)

```swift
// API: Packages/AsistCore/Sources/AsistCore/Capture/ItemFactory.swift
import Foundation

public enum ConfirmationLevel: String, Equatable {
    case autoSave     // confidence ≥ 0.80 → countdown settings.autoSaveSeconds (4 s)
    case confirm      // 0.60 ..< 0.80   → countdown 6 s, uncertain fields marked "?"
    case review       // < 0.60 or pastDue/conflictingDates/needs-time → no auto-save
}

public struct CaptureContext: Equatable {
    public var settings: AppSettings
    public var projects: [Project]
    public var places: [Place]
    public var forcedKind: ItemKind?        // "asist://dinle?tur=not", "Bu projeye sesli not"
    public var forcedProjectID: UUID?       // project detail voice note
    public var interactive: Bool            // true = app UI (card can ask); false = Siri/Shortcut
    public init(settings: AppSettings, projects: [Project], places: [Place], forcedKind: ItemKind? = nil,
                forcedProjectID: UUID? = nil, interactive: Bool)
}

public struct CaptureProposal: Equatable {
    public var item: Item
    public var level: ConfirmationLevel
    /// Reminder without any time and interactive && noTimeBehavior == .ask → card shows "Ne zaman?".
    public var needsTime: Bool
    /// A default time/offset was applied that the user did not say (D20 headless +1 h, D21 waiting default).
    public var appliedDefaultTime: Bool
    /// D33: an undated task was put on today (or tomorrow after workEnd), untimed → card chips Bugün / Yarın / Zamanı belirsiz.
    public var defaultedToToday: Bool
    /// Alternative instants: ambiguous hours (21:00 chosen → [tomorrow 09:00]; 15:00 → [03:00 next]),
    /// `.nextWeekAmbiguous` → [due + 7 days] (P2), bare weekday = today → [today same time if still ahead] (P3).
    public var alternativeTimes: [Date]
    public init(item: Item, level: ConfirmationLevel, needsTime: Bool, appliedDefaultTime: Bool,
                defaultedToToday: Bool, alternativeTimes: [Date])
}

public enum ItemFactory {
    /// Folded event head nouns (possessive -ı/-i/-u/-ü/-sı/-si/-su/-sü accepted): toplanti, gorusme, randevu, ziyaret,
    /// sunum, egitim, denetim, fat, sat, mulakat, ucus, yemek, mac, webinar, kickoff, acilis, toren, fuar, konferans.
    public static let eventNouns: [String]
    /// true when the last content word of `title` — ignoring trailing "var", "var mı", "olacak", "yapılacak",
    /// "başlıyor", "başlayacak" — is an event noun. "ABB ile toplantı var" → true; "toplantı notlarını gönder" → false.
    public static func isEventTitle(_ title: String) -> Bool
    /// nil when result.kind == .command. Rules R1–R12 below.
    public static func proposal(from result: ParseResult, source: CaptureSource, context: CaptureContext,
                                now: Date, calendar: Calendar) -> CaptureProposal?
    public static func level(for result: ParseResult) -> ConfirmationLevel
    /// D20 resolution: .inOneHour → ceilToMinute(now + 60 min); .thisEvening → today aksam (or +1 h if passed);
    /// .tomorrowMorning → NagPlanner.tomorrowMorning; .ask → same as .inOneHour.
    public static func noTimeDefault(_ behavior: NoTimeBehavior, now: Date, settings: AppSettings, calendar: Calendar) -> Date
    /// D21: +waitingDefaultWorkdays workdays at waitingDefaultTime (item.hasTime = false).
    public static func defaultWaitingDue(now: Date, settings: AppSettings, calendar: Calendar) -> Date
}
```

`ItemFactory.proposal` rules (normative, tested in `ItemFactoryTests`):
- **R1 Kind.** `forcedKind ?? parsed.kind`. When `forcedKind == nil`, `parsed.kind == .note` and `flags ∋ .noKindCue` (02 T10 fallback) → `.task` (D33): level at most `.confirm`; headless → `needsReview = true`.
- **R2 Project.** Parser name → `Project` by folded match over `allNames`, else `forcedProjectID`, else `settings.activeProjectID` (never set by v1.0 UI). Unknown project names are **never** auto-created; a "Yeni proje: X" chip may be offered unselected, and never for the stoplist elektrik, pnömatik, hidrolik, mekanik, yazılım, plc, tia, otomasyon, montaj (05b D11).
- **R3 Place (v1.0).** No geofences exist: a parsed `place` is appended to `notes` as "Yer: <Fabrika> (varınca|çıkınca)"; `placeID/placeTrigger` stay nil; the item is scheduled as if no place was said.
- **R4 Copy.** notes = body ?? ""; originalText; parseConfidence; dueDate/hasTime/recurrence/priority/person/tags; `leadTimesMinutes` (G10); source; history `[.created]`.
- **R5 Urgent without date (P4).** priority ≥ high, kind `.task`, no due → kind `.reminder` and R6 applies.
- **R6 Reminder without due (D20).** interactive && `.ask` → `needsTime = true` (level `.review`); otherwise `noTimeDefault` + `appliedDefaultTime = true`.
- **R7 Task without due (D33).** source ∈ {voice, keyboard, siri, shortcut}: `hasTime = false`, `defaultedToToday = true`, and `dueDate` = 02 §8.2a **today policy** (today at `defaultDayTime` if that is ≥ now + 15 min, else now + 30 min rounded up to the next full hour) — or the next day at `defaultDayTime` when `now ≥ workEnd` or the today policy would cross midnight. The anchor therefore never lies before the capture, so the first alert is not reported as "5 saattir bekliyor".
- **R8 Waiting without due (D21).** `defaultWaitingDue`, `hasTime = false`, `appliedDefaultTime = true`.
- **R9 Event (D31).** `hasTime && isEventTitle(title)` and kind ∈ {reminder, task} → `kind = .reminder`, `isEvent = true`; empty `leadTimesMinutes` → `[settings.eventDefaultLeadMinutes]` when > 0.
- **R10 Alternatives.** as documented on `alternativeTimes`.
- **R11 Level.** `level(for:)` (D10); `pastDue`, `conflictingDates`, `needsTime`, `nextWeekAmbiguous` cap the level (review / confirm).
- **R12 needsReview** = `!interactive && (level == .review || R1 fallback applied)`.

```swift
// API: Packages/AsistCore/Sources/AsistCore/Model/ChecklistTemplates.swift
import Foundation

public struct ChecklistTemplate: Equatable, Identifiable {
    public var id: String           // "fat", "sat", "devreye_alma", "saha_ziyareti", "toplanti"
    public var name: String         // "FAT (Fabrika Kabul Testi)", …
    public var entries: [String]    // exact texts from 03 Ek A
}

public enum ChecklistTemplates {
    public static let all: [ChecklistTemplate]
    public static func entries(for template: ChecklistTemplate) -> [ChecklistEntry]   // fresh UUIDs, done = false
}
```

#### 3.5.7 Deep links — exact

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Links/DeepLink.swift
import Foundation

public enum DeepLink: Equatable {
    case listen(kind: ItemKind?, projectID: UUID?)   // asist://dinle?tur=hatirlatma|gorev|not|takip&proje=<uuid>
    case compose                                     // asist://yaz
    case today                                       // asist://bugun
    case item(UUID)                                  // asist://kayit/<uuid>
    case completeItem(UUID)                          // asist://kayit/<uuid>?eylem=yaptim
    case endOfDay                                    // asist://gunsonu
    case readAgenda                                  // asist://oku
    case settingsTriggers                            // asist://ayarlar/tetikleyiciler

    public static let scheme = "asist"

    public var url: URL {
        var c = URLComponents()
        c.scheme = DeepLink.scheme
        switch self {
        case .listen(let kind, let projectID):
            c.host = "dinle"
            var query: [URLQueryItem] = []
            if let kind = kind { query.append(URLQueryItem(name: "tur", value: DeepLink.kindCode(kind))) }
            if let projectID = projectID { query.append(URLQueryItem(name: "proje", value: projectID.uuidString)) }
            if !query.isEmpty { c.queryItems = query }
        case .compose:
            c.host = "yaz"
        case .today:
            c.host = "bugun"
        case .item(let id):
            c.host = "kayit"
            c.path = "/" + id.uuidString
        case .completeItem(let id):
            c.host = "kayit"
            c.path = "/" + id.uuidString
            c.queryItems = [URLQueryItem(name: "eylem", value: "yaptim")]
        case .endOfDay:
            c.host = "gunsonu"
        case .readAgenda:
            c.host = "oku"
        case .settingsTriggers:
            c.host = "ayarlar"
            c.path = "/tetikleyiciler"
        }
        return c.url ?? URL(string: "asist://bugun")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased() else { return nil }
        let items = comps.queryItems ?? []
        func query(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        let pathParts = comps.path.split(separator: "/").map(String.init)
        switch host {
        case "dinle":
            let kind = query("tur").flatMap(DeepLink.kind(fromCode:))
            let project = query("proje").flatMap { UUID(uuidString: $0) }
            self = .listen(kind: kind, projectID: project)
        case "yaz":
            self = .compose
        case "bugun":
            self = .today
        case "kayit":
            guard let first = pathParts.first, let id = UUID(uuidString: first) else { return nil }
            self = query("eylem") == "yaptim" ? .completeItem(id) : .item(id)
        case "gunsonu":
            self = .endOfDay
        case "oku":
            self = .readAgenda
        case "ayarlar":
            self = .settingsTriggers
        default:
            return nil
        }
    }

    public static func kindCode(_ kind: ItemKind) -> String {
        switch kind {
        case .reminder: return "hatirlatma"
        case .task: return "gorev"
        case .note: return "not"
        case .waiting: return "takip"
        }
    }

    public static func kind(fromCode code: String) -> ItemKind? {
        switch code.lowercased() {
        case "hatirlatma": return .reminder
        case "gorev": return .task
        case "not": return .note
        case "takip": return .waiting
        default: return nil
        }
    }
}
```

#### 3.5.8 Widget snapshot — deferred to v1.1

`WidgetSnapshot`, `SnapshotStore` and `WidgetSnapshotBuilder` are **not built in v1.0** (D30). Binding design: **Appendix B.4**. `Platform/AppGroupResolver.swift` stays in v1.0 AsistCore only because the verbatim `PlatformTests` (01c §4.5) test it; no v1.0 app code calls it.

#### 3.5.9 Smart Mode wire types — deferred to v1.1

`AsistCore/SmartMode/*` is **not built in v1.0** (D15/D30). Binding design (doc 06 facts): **Appendix B.2**.

### 3.6 App target contracts

#### 3.6.1 Entry point (WP0 exact)

```swift
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
```

```swift
// FILE: App/AsistApp.swift
import SwiftUI

@main
struct AsistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AsistShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppEnvironment.shared.store)
                .environment(AppEnvironment.shared.router)
                .environment(AppEnvironment.shared.voice)
                .environment(AppEnvironment.shared.engine)
                .environment(AppEnvironment.shared.permissions)
                .environment(AppEnvironment.shared.toasts)
                .environment(AppEnvironment.shared.signing)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .tint(.indigo)
        }
    }
}
```
`App.init()` and `body` are `@MainActor` (the `App` protocol is main-actor isolated in the iOS 17+ SDK), so touching `AppEnvironment.shared` there is legal. `AppEnvironment.shared` is created on first access — by `AppDelegate` (UIKit calls the delegate before SwiftUI evaluates `body`).

#### 3.6.2 Composition root — exact

```swift
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
            AppEnvironment.shared.endFlush()
        }
    }

    func endFlush() {
        guard flushTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(flushTaskID)
        flushTaskID = .invalid
    }
}
```

Notes: the expiration handler of `beginBackgroundTask(withName:expirationHandler:)` is typed `(@MainActor @Sendable () -> Void)?` in the current SDK; `MainActor.assumeIsolated` (iOS 17+) makes the body compile whether or not an SDK version marks the closure `@MainActor`, and it ends the task synchronously as UIKit requires. Never capture and mutate a local `var` inside that closure (it is `@Sendable`). `flushTaskID` is the only background-task identifier in the app.

#### 3.6.3 Support — exact

```swift
// FILE: App/Support/AppTime.swift
import Foundation
import AsistCore

enum AppTime {
    /// Device time zone (wall-clock reminders follow the user when travelling), Monday-first, POSIX locale.
    static var calendar: Calendar { AsistCalendar.make(timeZone: TimeZone.autoupdatingCurrent) }
}
```

```swift
// FILE: App/Support/AsistLog.swift
import Foundation
import os

enum LogCategory: String {
    case app, store, notif, voice, intents, smart, location, widget, ui
}

/// Thread-safe ring buffer shown in Ayarlar > Tanılama (there is no Mac console).
final class LogBuffer: @unchecked Sendable {
    static let shared = LogBuffer()
    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity = 300

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// Callable from any thread/isolation.
enum AsistLog {
    static let subsystem = "com.gokhanbudak.asist"

    static func info(_ message: String, _ category: LogCategory = .app) {
        write(message, category, .info)
    }

    static func error(_ message: String, _ category: LogCategory = .app) {
        write("HATA: " + message, category, .error)
    }

    static func recentLines() -> [String] {
        LogBuffer.shared.snapshot()
    }

    private static func write(_ message: String, _ category: LogCategory, _ level: OSLogType) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.log(level: level, "\(message, privacy: .public)")
        let stamp = Date().formatted(date: .numeric, time: .standard)
        LogBuffer.shared.append(stamp + " [" + category.rawValue + "] " + message)
    }
}
```

```swift
// FILE: App/Support/Haptics.swift
import UIKit

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
```

#### 3.6.4 Persistence (WP4)

```swift
// API: App/Store/StoreFiles.swift
import Foundation

struct StoreFiles {
    let directory: URL          // Application Support/Asist/
    let dataFile: URL           // asist-data.json
    let previousFile: URL       // asist-data.prev.json  (last VERIFIED version before the latest write)
    let backupDirectory: URL    // Documents/Yedekler/   (visible in Files app, D25)
    let openItemsTextFile: URL  // Documents/Yedekler/Asist-acik-isler.txt (05b A1)

    /// Creates directories if needed (never throws; logs).
    static func standard() -> StoreFiles
    /// "asist-data.corrupt-yyyyMMdd-HHmmss.json" next to dataFile.
    func corruptCopyURL(now: Date) -> URL
    /// "asist-yedek-yyyy-MM-dd.json"
    func dailyBackupURL(dayKey: String) -> URL
    /// Documents/Yedekler/asist-data.yeni-surum-<build>.json (D35)
    func newerWriterCopyURL(build: Int) -> URL
}
```

```swift
// API: App/Store/DataStore.swift
import Foundation
import Observation
import AsistCore

enum StoreChange: String {
    case items, settings, projects, places, meta, all
}

enum StoreLoadIssue: Equatable {
    case restoredFromPrevious                 // main file unreadable → prev file used
    case restoredFromBackup(dayKey: String)   // → daily backup used
    case startedEmptyAfterCorruption          // nothing readable; corrupt copy kept
    case partialRecovery(dropped: Int)        // decoded, but n array elements were unreadable; raw copy kept (05a #22)
    case newerWriter(build: Int)              // written by a newer build; copy kept in Yedekler (D35, 05a #10)
}

enum DoneResult: Equatable {
    case completed
    case nextOccurrence(Date)
}

struct ImportPreview: Equatable { let itemCount: Int; let projectCount: Int; let placeCount: Int }
/// merge: items/projects/places by id, newer updatedAt wins; settings and meta unchanged.
/// replace: items, projects, places **and settings** replaced; `meta` stays local except `lastEndOfDayMove = nil` (05a #24).
enum ImportMode { case merge, replace }

@MainActor
@Observable
final class DataStore {
    private(set) var data: AppData                    // observable root
    /// false until a file was actually READ (or confirmed absent). While false: every mutation and save() is a
    /// logged no-op that returns nil / false, and ReminderEngine.reconcile returns early — an unreadable file
    /// (device locked since boot) must never be replaced by an empty document or wipe pending notifications.
    private(set) var isLoaded: Bool = false
    private(set) var loadIssue: StoreLoadIssue?
    private(set) var lastSaveError: String?           // "Kaydedilemedi…" / "Telefonda yer kalmadı…"
    @ObservationIgnored var onChange: (@MainActor (StoreChange) -> Void)?
    let files: StoreFiles

    init(files: StoreFiles)                           // does NOT read disk; never touches AppEnvironment.shared

    /// isLoaded && lastSaveError == nil (05a #3). UI shows "Kaydedildi" only when this is true after a mutation.
    var canPersist: Bool { get }

    // MARK: Load / save
    /// Idempotent until isLoaded. File absent → AppData.empty(now:) (first launch), isLoaded = true.
    /// Read error (I/O, `UIApplication.shared.isProtectedDataAvailable == false`) → stay !isLoaded; retried on
    /// `protectedDataDidBecomeAvailableNotification` and every sceneDidBecomeActive.
    /// Read OK but decode fails → copy to corruptCopyURL, then previousFile → newest daily backup → empty; set loadIssue.
    /// Decode OK → (05a #22) re-parse the same bytes with JSONSerialization and compare the raw element counts of
    /// "items"/"projects"/"places" (and that each is an array) with the decoded counts; mismatch → copy the raw file
    /// to corruptCopyURL **before any save**, loadIssue = .partialRecovery(dropped:).
    /// (D35) meta.writerBuild > currentBuild (CFBundleVersion as Int) → copy the raw file to newerWriterCopyURL before
    /// any save, loadIssue = .newerWriter(build:).
    /// Main file decoded without issue → `mainFileVerified = true` (internal flag).
    /// Purges .deleted items with deletedAt < now − 30 days.
    /// On the transition isLoaded false → true it calls onChange?(.all) (05a #6).
    func load()
    /// Synchronous, atomic JSONEncoder(.iso8601, .sortedKeys) write with
    /// [.atomic, .completeFileProtectionUntilFirstUserAuthentication]; sets meta.writerBuild = current CFBundleVersion.
    /// Before writing: if mainFileVerified, copies the current main file to previousFile via
    /// `Data(contentsOf:)` + `write(to:options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])`
    /// (never `FileManager.copyItem`; never copies an unverified/corrupt file over prev — 05a #21); after the first
    /// successful write of this session mainFileVerified = true.
    /// Once per calendar day writes a daily backup and prunes to the newest 7. After every successful save rewrites
    /// openItemsTextFile with AgendaBuilder.openItemsText (05b A1; failures only logged).
    /// On failure keeps data in memory, sets lastSaveError, retries on the next mutation and on sceneDidEnterBackground.
    func save()

    // MARK: Reads (computed from `data`)
    var items: [Item] { get }                         // all incl. done/deleted
    var settings: AppSettings { get }
    var projects: [Project] { get }
    var places: [Place] { get }
    var meta: AppMeta { get }
    /// status .deleted, deletedAt within 30 days, newest first (05b B8).
    var recentlyDeleted: [Item] { get }
    func item(_ id: UUID) -> Item?
    func project(_ id: UUID?) -> Project?
    func place(_ id: UUID?) -> Place?
    func projectName(for item: Item) -> String?

    // MARK: Item mutations — each: mutate → updatedAt → save() → onChange(.items).
    // Return value nil = nothing changed OR not persisted (!isLoaded, item missing/closed, or save failed) (05a #3).
    @discardableResult func add(_ item: Item) -> UndoToken?
    @discardableResult func update(_ id: UUID, event: HistoryEvent?, _ mutate: (inout Item) -> Void) -> UndoToken?
    /// Non-recurring → status .done, completedAt, history .done. Recurring → dueDate = next occurrence
    /// (RecurrenceEngine, time of current due, after max(now, due)), resetNagState, completedOccurrences += 1,
    /// history .occurrenceDone.
    @discardableResult func markDone(_ id: UUID, at now: Date) -> (DoneResult, UndoToken)?
    @discardableResult func reopen(_ id: UUID, at now: Date) -> UndoToken?
    /// snoozedUntil = target (whole minute), snoozeCount += 1, history .snoozed(detail: target text).
    @discardableResult func snooze(_ id: UUID, until target: Date, at now: Date) -> UndoToken?
    /// status .deleted + deletedAt (soft delete; purge after 30 days).
    @discardableResult func delete(_ id: UUID, at now: Date) -> UndoToken?
    /// status .open, deletedAt nil, history .restored ("Son silinenler › Geri getir").
    @discardableResult func restoreDeleted(_ id: UUID, at now: Date) -> UndoToken?
    /// Applies AgendaBuilder.movedToTomorrow to endOfDayCandidates; stores meta.lastEndOfDayMove.
    @discardableResult func moveOpenItemsToTomorrow(now: Date) -> UndoToken?
    func undo(_ token: UndoToken)                     // restores `before`, hard-removes createdIDs
    func recordDismiss(_ id: UUID, at date: Date)     // lastDismissedAt; onChange(.meta)-level only (no reconcile)
    /// Open recurring items whose next occurrence ≤ now: dueDate = latest occurrence ≤ now, resetNagState,
    /// history .occurrenceMissed. Returns true if anything changed (emits onChange itself).
    @discardableResult func rollOverRecurring(now: Date, calendar: Calendar) -> Bool
    /// D31: open events with `eventEnd ≤ now` → markDone semantics (recurring → next occurrence) with history detail
    /// "otomatik kapandı". Returns true if anything changed (emits onChange itself).
    @discardableResult func closeFinishedEvents(now: Date, calendar: Calendar) -> Bool

    // MARK: Projects / places / settings / meta
    func upsertProject(_ project: Project)            // onChange(.projects)
    func archiveProject(_ id: UUID, archived: Bool)
    func upsertPlace(_ place: Place)                  // onChange(.places) (no v1.0 caller)
    func removePlace(_ id: UUID)                      // also clears placeID on items
    func updateSettings(_ mutate: (inout AppSettings) -> Void)   // onChange(.settings)
    func updateMeta(_ mutate: (inout AppMeta) -> Void)           // onChange(.meta) — never triggers reconcile

    // MARK: Import / export (helpers in ImportExport.swift)
    func exportData() -> Data                         // pretty-printed, sorted keys, iso8601
    func importPreview(_ data: Data) -> ImportPreview?
    /// Writes the current file to today's daily backup copy first (§9 r43), then applies `mode`; onChange(.all).
    func importData(_ data: Data, mode: ImportMode) -> Bool
}
```

Normative store rules:
- **Real changes only (05a #5).** Every mutator compares before/after and calls `save()` and `onChange` **only when `data` actually changed**. `rollOverRecurring` / `closeFinishedEvents` return false and emit nothing when nothing changed. Test: two consecutive reconciles with no input change perform 0 saves.
- **Thread rule.** `DataStore` is touched only on the main actor; background callers hop with `await MainActor.run {}` or `Task { @MainActor in }`.
- **Current build** = `Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0`.
- `recordLocationFired` from revision 1 is removed (location is v1.2).

#### 3.6.5 Notifications (WP5)

```swift
// FILE: App/Notifications/NotificationCoordinator.swift
import Foundation
import UserNotifications
import AsistCore

/// Value copy of a response (no UNNotificationResponse crosses into the main actor).
struct NotificationEvent {
    let actionID: String
    let itemID: UUID?
    let notificationID: String
    /// userInfo "nk" (PlannedNotification.Kind rawValue); "" when missing.
    let kind: String
    let deliveredAt: Date
}

/// NOT @MainActor: UserNotifications calls it on a private queue. Completion-handler variants only.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private override init() {
        super.init()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
        Task { @MainActor in
            AppEnvironment.shared.engine.requestReconcile(reason: "willPresent")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        let rawID = info[NotificationUserInfoKey.itemID] as? String
        let parsedID = rawID.flatMap { UUID(uuidString: $0) }
        let kind = info[NotificationUserInfoKey.kind] as? String ?? ""
        let event = NotificationEvent(actionID: response.actionIdentifier,
                                      itemID: parsedID ?? NotificationID.itemID(from: request.identifier),
                                      notificationID: request.identifier,
                                      kind: kind,
                                      deliveredAt: response.notification.date)
        Task { @MainActor in
            AppEnvironment.shared.bootstrap()
            // handle() persists, replaces this item's pending requests and awaits a full reconcile (D34, §6.3).
            await AppEnvironment.shared.engine.handle(event)
            completionHandler()          // always, exactly once, after handle() returned
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in
            AppEnvironment.shared.router.openRoute(.appStatus, in: .settings)
        }
    }
}
```

```swift
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
```

```swift
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
```

```swift
// API: App/Notifications/NotificationScheduler.swift
import Foundation
import UserNotifications
import AsistCore

@MainActor
final class NotificationScheduler {
    /// 01a §5.4 diff-apply restricted to NotificationID.isPlannerManaged ids: remove managed pending ids not
    /// in `desired`; add desired ids whose pending fingerprint (userInfo "fp") differs or is missing.
    /// Duplicate ids in `desired` → first wins (no Dictionary(uniqueKeysWithValues:)).
    /// `.once` with fireDate <= now is skipped. Returns number of add() calls.
    @discardableResult func apply(_ desired: [PlannedNotification], now: Date, calendar: Calendar) async -> Int
    /// 05b B1 immediate path: adds exactly these requests (same factory, no diff, no removal; `.once` in the past skipped).
    @discardableResult func add(_ notifications: [PlannedNotification], now: Date, calendar: Calendar) async -> Int
    /// Keep only the newest delivered notification per open item thread; remove delivered of closed items.
    func cleanupDelivered(openItemIDs: Set<UUID>) async
    /// Removes delivered + pending of one item (every id containing its UUID, incl. the budget sentinel when its
    /// userInfo iid is this item).
    func removeAll(for itemID: UUID) async
    /// Removes every pending id with prefix "asist." except unmanaged "asist.x." (used by rebuildAll).
    func removeAllManaged() async
    /// Diagnostics: (identifier, next trigger date, title) sorted by date.
    func pendingSummary() async -> [(id: String, date: Date?, title: String)]
    func pendingCount() async -> Int
    /// Ad hoc one-shot (test, moved feedback) with an "asist.x." id; trigger ≥ 2 s.
    func addUnmanaged(id: String, text: NotificationText, after seconds: TimeInterval, categoryID: String,
                      interruption: PlannedNotification.Interruption, itemID: UUID?) async
}
```

`NotificationRequestFactory.make(_ p: PlannedNotification, now: Date, calendar: Calendar) -> UNNotificationRequest` — 01a §2.5 with:
- sound: `p.playsSound ? (p.soundName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default) : nil` (D37; a missing file plays the default sound);
- `content.interruptionLevel` from `p.interruption`, `relevanceScore = p.relevance`, `threadIdentifier`, `categoryIdentifier`, `badge = p.badge.map { NSNumber(value: $0) }`;
- userInfo `[iid, k, fp, nk]` (String/Int only);
- `.once` with `fireDate − now < 60 s` → `UNTimeIntervalNotificationTrigger(timeInterval: max(delta, 2), repeats: false)`, else `UNCalendarNotificationTrigger` with `[.year,.month,.day,.hour,.minute,.second]` from `calendar` (no timeZone component);
- `.daily` → `DateComponents(hour: h, minute: m)` repeats; `.weekly` → `DateComponents(hour: h, minute: m, weekday: w)` repeats (argument order!); `.monthly` → `DateComponents(day: d, hour: h, minute: m)` repeats.

```swift
// API: App/Notifications/ReminderEngine.swift
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

    private(set) var lastReport: Report?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, scheduler: NotificationScheduler, signing: SigningMonitor)

    /// Serialized (task chain, 01a §5.6). Steps:
    /// 0 `guard store.isLoaded` (else log + return — never plan from an unloaded store);
    /// 1 `let ns = await center.notificationSettings()`; not authorized (.authorized/.provisional/.ephemeral) → report,
    ///   return; `allowTimeSensitive = ns.timeSensitiveSetting == .enabled` (05b B7);
    /// 2 store.rollOverRecurring(now:calendar:); store.closeFinishedEvents(now:calendar:) (D31);
    /// 3 plan = NagPlanner.plan(makeInput(now:)) with signingExpiry: signing.expiryDate, allowTimeSensitive;
    /// 4 scheduler.apply(plan.notifications); 5 scheduler.cleanupDelivered(openItemIDs:);
    /// 6 try? await center.setBadgeCount(plan.badgeNow); 7 store.updateMeta(last*); lastReport = …
    /// Every await point re-reads `store` state after resuming (no stale copies across awaits).
    func reconcile(reason: String) async
    /// Fire-and-forget, debounced 300 ms (collapses bursts from **foreground** UI edits only; D34).
    func requestReconcile(reason: String)
    /// scheduler.removeAllManaged() then reconcile (after re-sign / import / "Planı yeniden kur").
    func rebuildAll(reason: String) async
    /// §6.3: rollOver → action mutation → immediate replacement of this item's pending requests → awaits a full
    /// reconcile → returns. The caller calls completionHandler() after this returns.
    func handle(_ event: NotificationEvent) async
    /// PlanInput for `now` from the current store/signing state (also used by the immediate path).
    func makeInput(now: Date, allowTimeSensitive: Bool) -> PlanInput
    /// "Test bildirimi (10 sn)": asist.x.test, category ASIST_ITEM, itemID nil.
    func sendTestNotification() async
}
```

#### 3.6.6 Permissions and banners (WP5)

```swift
// API: App/Notifications/PermissionCenter.swift
import Foundation
import Observation
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
    private(set) var alertsPersistent = false        // UNNotificationSettings.alertStyle == .alert ("Kalıcı")
    private(set) var previewsAlways = true           // showPreviewsSetting == .always
    private(set) var timeSensitiveEnabled = false    // timeSensitiveSetting == .enabled
    private(set) var scheduledSummaryOn = false      // scheduledDeliverySetting == .enabled
    private(set) var microphoneGranted = false       // AVAudioApplication.shared.recordPermission == .granted
    private(set) var speechGranted = false           // SFSpeechRecognizer.authorizationStatus() == .authorized

    func refresh() async
    func requestNotifications() async -> Bool        // [.alert, .sound, .badge, .providesAppNotificationSettings]
    func requestVoice() async -> Bool                // VoicePermissions.requestAll()
    /// Highest-priority banner (03 §9): notif off (red) > data written by newer build (red, not dismissible, D35) >
    /// save failed (red) > data restored / partial recovery (yellow) > signing expired or ≤ 3 days (red/yellow) >
    /// mic/speech off (yellow) > notif previews hidden / scheduled summary on (yellow) > "Kalıcı" banner-style tip
    /// when !alertsPersistent (yellow, dismissible 720 h, action .openGuideBanners, 05b A9) > budget dropped (yellow).
    /// A dismissed banner is hidden while meta.dismissedBanners[id] > now.
    func topBanner(store: DataStore, signing: SigningMonitor, engine: ReminderEngine, now: Date) -> AppBanner?
    static func openNotificationSettings()           // UIApplication.openNotificationSettingsURLString
    static func openAppSettings()                    // UIApplication.openSettingsURLString
}
```
Every `switch` over `UNAuthorizationStatus`, `UNAlertStyle`, `UNShowPreviewsSetting`, `UNNotificationSetting`, `SFSpeechRecognizerAuthorizationStatus` MUST include `@unknown default:`. v1.0 imports CoreLocation nowhere (location is v1.2, Appendix B.3).

#### 3.6.7 Voice (WP6) — 01b code adapted per D2

| 01b type | v1 type | Change |
|---|---|---|
| `SpeechListener: ObservableObject` | `@MainActor final class SpeechListener` | remove `ObservableObject`/`@Published`; add `var onPartial: ((String) -> Void)?`, `var onLevel: ((Float) -> Void)?`; `ListenConfig` defaults `noSpeechTimeout = 6`, `maxDuration = 45`, `silenceAfterSpeech` from settings, `contextualStrings` from `CaptureService.contextualStrings()` (≤ 100); **noise floor (05b A6):** the mean input level of the first 300 ms (before the "listening" haptic) is the floor; speech activity requires level ≥ `max(−24 dBFS, floor + 8 dB)`; energy alone may extend speech activity by at most 1.5 s beyond the last *changed* partial transcript; everything else verbatim (nonisolated static factories, single `finish`). `Task.sleep` durations are computed as `UInt64(max(0, seconds) * 1_000_000_000)` |
| `Speaker: NSObject, ObservableObject` | `@MainActor final class Speaker: NSObject, AVSpeechSynthesizerDelegate` | remove `ObservableObject`/`@Published`; add `var rate: TTSRate`; `speak(_:) async` unchanged; delegate methods stay `nonisolated`; **no `override init`** |
| `VolumeButtonTrigger: ObservableObject` | `@MainActor final class VolumeButtonTrigger` | remove `ObservableObject`; `var onDoublePress: (() -> Void)?`, `var onLowVolumeChanged: ((Bool) -> Void)?` |
| `SystemVolumeAnchor` | same | unchanged; used only as `SystemVolumeAnchor(trigger:).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)` (05a #17) |
| `VoiceCaptureCoordinator` | `VoiceCoordinator` (below) | replaced |
| `VoicePermissions`, `AudioSessionConfigurator` | same | verbatim |

```swift
// API: App/Voice/VoiceCoordinator.swift
import Foundation
import Observation
import UIKit
import AVFoundation
import AsistCore

@MainActor
@Observable
final class VoiceCoordinator {
    enum Phase: Equatable { case idle, preparing, listening, processing, speaking }

    private(set) var phase: Phase = .idle
    private(set) var partialText: String = ""
    private(set) var level: Float = 0
    /// Last user-facing error/info (Turkish, 03 §7.12 listen.*); cleared on next start.
    private(set) var message: String?
    private(set) var volumeTooLow = false
    /// Overlay visible while preparing/listening/processing.
    var isOverlayVisible: Bool { get }
    private(set) var request = ListenRequest()

    let listener = SpeechListener()
    let speaker = Speaker()
    let trigger = VolumeButtonTrigger()

    /// Wires callbacks only; MUST NOT touch AppEnvironment.shared (§4.1 r13). Pattern:
    /// `trigger.onDoublePress = { [weak self] in Haptics.medium(); Task { @MainActor in await self?.startListening() } }`
    /// listener callbacks → partialText / level.
    init()

    /// Stores configuration only (volume trigger enabled, restore volume, silence, on-device, TTS rate).
    /// Never arms the trigger and never touches the audio session — bootstrap() also runs in background launches (05a #25).
    func apply(settings: AppSettings)
    /// Reads AppEnvironment.shared.capture / router lazily at call time. Order:
    /// router.showOnboarding → return (trigger stays disarmed); router.sheet != nil → router.dismissSheet() and
    /// `try? await Task.sleep(nanoseconds: 400_000_000)` (the sheet's onDismiss commits its draft; 05a #18);
    /// permissions missing → message + router.present(.compose) fallback; otherwise disarm trigger, stop TTS,
    /// phase .preparing → listener.listen(contextualStrings: capture.contextualStrings()) → on text: phase .processing
    /// → await capture.handleTranscript(text, source: .voice, request: request) → phase .idle;
    /// re-arm the trigger only if `UIApplication.shared.applicationState == .active`.
    func startListening(_ request: ListenRequest = ListenRequest()) async
    func finishListening()                       // "Bitti"
    /// "Vazgeç": nothing saved; if the partial text has ≥ 2 words → toasts.show("Vazgeçildi", undoTranscript: text) (05b B9).
    func cancelListening()
    /// Waits until finished; phase .speaking meanwhile. Never starts listening while speaking.
    func speak(_ text: String) async
    /// D18: true when settings.speakConfirmations && (speakConfirmationsOnSpeaker || the current route output is
    /// .headphones / .bluetoothA2DP / .bluetoothHFP / .bluetoothLE / .carAudio / .usbAudio).
    func shouldSpeakConfirmation(settings: AppSettings) -> Bool
    func stopSpeaking()
    /// Arms the trigger (if enabled in settings) — the only place besides post-listening re-arm (D16).
    func sceneDidBecomeActive()
    func sceneDidEnterBackground()               // disarm, cancel, stop TTS, deactivate session;
                                                 // partial transcript → capture.saveInterruptedTranscript
}
```
`ListenRequest` is defined in `AppRouter.swift` (§3.6.10).

#### 3.6.8 Capture services (WP7) and toasts (WP0 exact)

```swift
// FILE: App/Services/ToastCenter.swift
import Foundation
import Observation
import AsistCore

@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        let text: String
        let undo: UndoToken?
        /// "Vazgeç" in the listening overlay: "Geri Al" re-opens the confirmation card with this text (05b B9).
        let undoTranscript: String?

        var hasUndo: Bool { undo != nil || undoTranscript != nil }
    }

    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ text: String, undo: UndoToken? = nil, undoTranscript: String? = nil, seconds: Double = 5) {
        let toast = Toast(id: UUID(), text: text, undo: undo, undoTranscript: undoTranscript)
        current = toast
        hideTask?.cancel()
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self = self, !Task.isCancelled, self.current?.id == toast.id else { return }
            self.current = nil
        }
    }

    func performUndo() {
        guard let toast = current else { return }
        current = nil
        if let token = toast.undo {
            AppEnvironment.shared.store.undo(token)
        } else if let transcript = toast.undoTranscript {
            Task { @MainActor in
                await AppEnvironment.shared.capture.handleTranscript(transcript, source: .voice, request: ListenRequest())
            }
        }
        Haptics.selection()
    }

    func dismiss() {
        current = nil
    }
}
```

```swift
// API: App/Services/CaptureDraft.swift
import Foundation
import Observation
import AsistCore

/// Model behind ConfirmationSheet (reference type so chips edit it in place; v1.1 Smart Mode updates it too).
@MainActor
@Observable
final class CaptureDraft: Identifiable {
    nonisolated let id: UUID         // nonisolated: read by SheetRoute.id / Identifiable from any context
    let heardText: String
    let source: CaptureSource
    let parse: ParseResult
    let level: ConfirmationLevel
    var item: Item                   // edited by chips
    var needsTime: Bool
    var alternativeTimes: [Date]
    var appliedDefaultTime: Bool
    /// D33 chips Bugün / Yarın / Zamanı belirsiz are shown.
    var defaultedToToday: Bool
    /// Countdown active; any touch sets false (03 §4.5).
    var autoSaveActive: Bool
    /// Set by commit/discard; prevents double handling on sheet dismissal.
    var isResolved: Bool = false

    init(heardText: String, source: CaptureSource, parse: ParseResult, proposal: CaptureProposal, autoSaveSeconds: Int)
    /// 0 when auto-save must not run (review level, needsTime, VoiceOver running, autoSaveSeconds == 0).
    var countdownSeconds: Int { get }
}
```

```swift
// API: App/Services/CaptureService.swift
import Foundation
import AsistCore

struct CapturePreview: Equatable {
    let understood: String           // parser `understood`
    let level: ConfirmationLevel
    let kind: ItemKind?
}

@MainActor
final class CaptureService {
    private(set) var activeDraft: CaptureDraft?

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter)

    /// Parser for current settings/projects/places + `ParserSettings.frequentPeople(in: store.items)` +
    /// AppTime.calendar (cached; see invalidateParser).
    func parser() -> TurkishParser
    func invalidateParser()
    /// Speech-recognizer vocabulary: 01b §1.8 jargon + project names/aliases + frequent people, ≤ 100 (§3.4.6).
    func contextualStrings() -> [String]

    /// Voice/keyboard entry in the app.
    /// request.snoozeItemID != nil ("Sesle ertele", 05b D5): parse the text; the first of item dueDate / command.date
    /// in the future → store.snooze(id, until:) + toast "Ertelendi · <Perşembe 10:00>" with undo; otherwise toast
    /// "Zamanı anlayamadım. Tekrar dener misin?". Nothing is captured.
    /// Otherwise: command → AppEnvironment.shared.commands.execute(…); item → CaptureDraft → router.present(.confirm(draft)).
    func handleTranscript(_ text: String, source: CaptureSource, request: ListenRequest) async
    /// ComposeSheet "Ekle": level .autoSave → save directly + undo toast; otherwise opens the card.
    func addFromKeyboard(_ text: String, request: ListenRequest) async
    /// Live preview (debounced by the view, 300 ms).
    func preview(_ text: String, request: ListenRequest) -> CapturePreview?
    /// Save: `store.add`; nil or `!store.canPersist` → toast `error.save_failed` ("Kaydedilemedi. Tekrar dene.") and
    /// Haptics.error (05a #3); else toast "Kaydedildi · <Salı 15:00>" with undo, Haptics.success, and the TTS
    /// confirmation when `voice.shouldSpeakConfirmation(settings:)` (D18).
    func commit(_ draft: CaptureDraft)
    /// Explicit "Vazgeç" on the card: nothing saved; toast "Vazgeçildi" with undo that commits the draft.
    func discard(_ draft: CaptureDraft)
    /// Sheet swiped away / app backgrounded / call → commit unresolved active draft (03 principle 3).
    func commitActiveDraftIfNeeded()
    /// Overlay interrupted with partial text → task with needsReview = true (03 §5.3).
    func saveInterruptedTranscript(_ text: String)
    /// Siri / Shortcut. Never opens UI. Exact order (D34, 05a #1/#3):
    /// 1 `if !store.isLoaded { store.load() }`; `guard store.isLoaded else { return TurkishSpeech.dataUnavailable }`;
    /// 2 parse (interactive: false); query → AgendaBuilder answer text; complete/cancel/snooze →
    ///   router.request(.openItem/…) + "Bunun için Asist'i açman gerekiyor." (D22);
    /// 3 item → `ItemFactory.proposal`; `guard store.add(item) != nil, store.canPersist else { return TurkishSpeech.saveFailed }`;
    /// 4 `await AppEnvironment.shared.engine.reconcile(reason: "intent")` — never `requestReconcile`;
    /// 5 return `TurkishSpeech.confirmation(…, headless: true, …)` (already dialogSafe).
    func captureHeadless(text: String, source: CaptureSource) async -> String
    /// asist://kayit/<id>?eylem=yaptim → markDone + undo toast.
    func completeFromLink(_ id: UUID)
}
```

```swift
// API: App/Services/CommandExecutor.swift
import Foundation
import AsistCore

struct MatchProposal: Identifiable {
    let id: UUID
    let command: ParsedCommand
    let candidates: [UUID]           // 1…3
    let decision: MatchDecision
}

@MainActor
final class CommandExecutor {
    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter)
    /// query → AgendaBuilder.answer → router.present(.agenda(answer)) + voice.speak(answer.text) (always spoken, D18);
    /// complete/cancel/snooze → FuzzyMatcher (snooze: date filter = command.targetDate; complete with "geldi" → preferWaiting)
    /// → .single/.ambiguous → router.present(.match(proposal)), speaks "“X” tamamlandı mı?" /
    /// "Birden fazla kayıt buldum, ekrandan seçer misin?"; .none → toast "Buna uyan bir kayıt bulamadım."
    func execute(_ command: ParsedCommand, originalText: String, source: CaptureSource) async
    /// "Oku" button, briefing "Sesli oku", asist://oku.
    func readTodayAgenda() async
    /// User confirmed in MatchConfirmationSheet. Snooze target = command.date ?? now + (snoozeMinutes ?? 60).
    /// Cancel = delete (always confirmed by the sheet). Returns the undo token shown in the toast.
    @discardableResult func apply(_ proposal: MatchProposal, itemID: UUID) -> UndoToken?
}
```

#### 3.6.9 Smart Mode client — deferred to v1.1

`KeychainStore` and `SmartModeClient` are **not built in v1.0** (D15/D30). Binding design: **Appendix B.2**.

#### 3.6.10 Router — exact

```swift
// FILE: App/Routing/AppRouter.swift
import Foundation
import Observation
import AsistCore

enum AppTab: Hashable { case today, lists, projects, settings }

/// backTap = guide A (headless "Asist Hızlı Kayıt"), backTapListen = guide A-alt ("Asist Dinle"), siri = C,
/// focus = E, banners = "Bildirimler ekranda kalsın" (Banner Stili › Kalıcı, 05b A9).
enum GuideKind: String, Hashable, CaseIterable { case backTap, backTapListen, siri, focus, banners }

enum ListFilter: String, Hashable, CaseIterable { case reminders, tasks, notes, followUps, completed }

enum Route: Hashable {
    case item(UUID)
    case project(UUID)
    case endOfDay
    case completed
    case recentlyDeleted
    case guide(GuideKind)
    case appStatus
    case diagnostics
    case generalSettings
    case timeSettings
    case nagSettings
    case summarySettings
    case triggerSettings
    case dataSettings
}

struct ListenRequest: Equatable {
    var kind: ItemKind? = nil
    var projectID: UUID? = nil
    /// Non-nil: the utterance is a new time for this item ("Sesle ertele", 05b D5), never a new capture.
    var snoozeItemID: UUID? = nil

    init(kind: ItemKind? = nil, projectID: UUID? = nil, snoozeItemID: UUID? = nil) {
        self.kind = kind
        self.projectID = projectID
        self.snoozeItemID = snoozeItemID
    }
}

enum DatePickerPurpose: Equatable { case snooze, due }

struct DatePickerRequest: Equatable {
    var itemID: UUID
    var purpose: DatePickerPurpose
}

enum PendingAction: Equatable {
    case listen(ListenRequest)
    case compose
    case readAgenda
    case openItem(UUID)
    case completeItem(UUID)
    case endOfDay
    case today
    case followUpMessage(UUID)
    case settingsTriggers
    case dataSettings
}

enum SheetRoute: Identifiable {
    case compose(ListenRequest)
    case confirm(CaptureDraft)
    case match(MatchProposal)
    case agenda(SpokenAnswer)
    case datePicker(DatePickerRequest)
    case projectEditor(UUID?)
    case followUpMessage(UUID)

    var id: String {
        switch self {
        case .compose: return "compose"
        case .confirm(let draft): return "confirm-" + draft.id.uuidString
        case .match(let proposal): return "match-" + proposal.id.uuidString
        case .agenda(let answer): return "agenda-" + answer.id
        case .datePicker(let request): return "date-" + request.itemID.uuidString
        case .projectEditor(let id): return "project-" + (id?.uuidString ?? "new")
        case .followUpMessage(let id): return "fu-" + id.uuidString
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var todayPath: [Route] = []
    var listsPath: [Route] = []
    var projectsPath: [Route] = []
    var settingsPath: [Route] = []
    var listFilter: ListFilter = .reminders
    var sheet: SheetRoute?
    /// Set true only by AppEnvironment.sceneDidBecomeActive (store loaded && !onboardingCompleted); false by OnboardingView.
    var showOnboarding = false
    private(set) var pending: PendingAction?

    /// Queue an action; RootView consumes it when the scene is active (+350 ms for listening, 01b §1.3).
    func request(_ action: PendingAction) {
        pending = action
    }

    func takePending() -> PendingAction? {
        let action = pending
        pending = nil
        return action
    }

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .listen(let kind, let projectID): request(.listen(ListenRequest(kind: kind, projectID: projectID)))
        case .compose: request(.compose)
        case .today: request(.today)
        case .item(let id): request(.openItem(id))
        case .completeItem(let id): request(.completeItem(id))
        case .endOfDay: request(.endOfDay)
        case .readAgenda: request(.readAgenda)
        case .settingsTriggers: request(.settingsTriggers)
        }
    }

    func openRoute(_ route: Route, in tab: AppTab) {
        sheet = nil
        selectedTab = tab
        switch tab {
        case .today: todayPath = [route]
        case .lists: listsPath = [route]
        case .projects: projectsPath = [route]
        case .settings: settingsPath = [route]
        }
    }

    func openItem(_ id: UUID) {
        openRoute(.item(id), in: .today)
    }

    func showToday() {
        sheet = nil
        selectedTab = .today
        todayPath = []
    }

    func present(_ newSheet: SheetRoute) {
        sheet = newSheet
    }

    func dismissSheet() {
        sheet = nil
    }
}
```

#### 3.6.11 Signing monitor (WP8)

```swift
// API: App/Platform/SigningMonitor.swift
import Foundation
import Observation
import AsistCore

@MainActor
@Observable
final class SigningMonitor {
    private(set) var profile: ProvisioningProfileInfo?
    /// profile?.expirationDate. nil when the embedded profile is unreadable → no signing notifications and no
    /// follow-up clamp are planned (05a #28).
    private(set) var expiryDate: Date?
    /// Reads embedded.mobileprovision (ProvisioningProfileReader); sets profile/expiryDate. No store access, no writes.
    /// Called first in bootstrap() so that every process — including background launches — plans with it (05a #4).
    func reload()
    /// reload() + compares the profile CreationDate stamp with meta.lastProfileStamp; stores the new stamp via
    /// store.updateMeta (only when store.isLoaded). Returns true when the profile changed (re-sign / first launch)
    /// → caller runs engine.rebuildAll. Returns false when !store.isLoaded.
    func refresh(store: DataStore) -> Bool
    /// UI only (AppStatus): installDate + 7 days while that is still in the future, else nil →
    /// "İmza bitişi: bilinmiyor". Shown with "(tahmini)".
    func estimatedExpiry(installDate: Date?, now: Date) -> Date?
}
```

### 3.7 App Intents and Siri phrases (WP0 exact; WP8 owns device verification)

Rules (01b §4.1): intents live in the **app target** (never in AsistCore; v1.0 has no other target); one `AppShortcutsProvider`; every phrase contains `\(.applicationName)` exactly once; no `String` parameter inside phrases; ASCII apostrophe `'` only; phrases must not start with "aç" (Siri's built-in open wins). Dialog text is always built as `IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(text)))` (no string interpolation into `IntentDialog`; `%` is removed, 05a #32). Every file imports `AsistCore` when it names any AsistCore symbol, including implicit member expressions such as `.siri` (05a #15). Naming table (05b A8/F3/F4) — intents, shortcuts, guides and KULLANIM.md use exactly these names:

| Intent | Title (Shortcuts app) | Short title | Siri example |
|---|---|---|---|
| `KaydetIntent` | Asist'e Kaydet | Kaydet | "Asist'e kaydet" |
| `DinleIntent` | Asist Dinle | Dinle | "Asist dinle" |
| `BugunIntent` | Bugün Ne Var | Bugün Ne Var | "Asist bugün ne var" |
| `GecikenlerIntent` | Gecikenler | Gecikenler | "Asist neyi unuttum" |

```swift
// FILE: App/Intents/DinleIntent.swift
import AppIntents

struct DinleIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist Dinle"
    static let description: IntentDescription? = IntentDescription("Asist'i açar ve sesli komut dinlemeye başlar.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.bootstrap()
        AppEnvironment.shared.router.request(.listen(ListenRequest()))
        return .result()
    }
}

@available(*, deprecated)
extension DinleIntent {
    static var openAppWhenRun: Bool { true }
}
```

```swift
// FILE: App/Intents/KaydetIntent.swift
import AppIntents
import AsistCore

struct KaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist'e Kaydet"
    static let description: IntentDescription? = IntentDescription("Söylediğini hatırlatma, görev, not veya takip olarak kaydeder. Uygulama açılmaz.")

    @Parameter(title: "Metin", requestValueDialog: IntentDialog("Ne kaydedeyim?"))
    var metin: String

    static var parameterSummary: some ParameterSummary {
        Summary("Kaydet: \(\.$metin)")
    }

    init() {}

    init(metin: String) {
        self.metin = metin
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: "Boş bir şey kaydedemedim. Tekrar söyler misin?")))
        }
        AppEnvironment.shared.bootstrap()
        // captureHeadless persists AND awaits the reconcile before returning (D34, 05a #1).
        let sentence = await AppEnvironment.shared.capture.captureHeadless(text: text, source: CaptureSource.siri)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(sentence))))
    }
}
```

```swift
// FILE: App/Intents/BugunIntent.swift
import AppIntents
import AsistCore

struct BugunIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugün Ne Var"
    static let description: IntentDescription? = IntentDescription("Bugünkü ve geciken işleri sesli özetler.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        env.bootstrap()
        if !env.store.isLoaded { env.store.load() }
        guard env.store.isLoaded else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dataUnavailable)))
        }
        let answer = AgendaBuilder.todaySpoken(items: env.store.items, projects: env.store.projects, now: Date(),
                                               settings: env.store.settings, calendar: AppTime.calendar)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(answer.text))))
    }
}
```

```swift
// FILE: App/Intents/GecikenlerIntent.swift
import AppIntents
import AsistCore

struct GecikenlerIntent: AppIntent {
    static let title: LocalizedStringResource = "Gecikenler"
    static let description: IntentDescription? = IntentDescription("Geciken işleri sesli okur.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        env.bootstrap()
        if !env.store.isLoaded { env.store.load() }
        guard env.store.isLoaded else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dataUnavailable)))
        }
        let answer = AgendaBuilder.overdueSpoken(items: env.store.items, now: Date(), settings: env.store.settings,
                                                 calendar: AppTime.calendar)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(answer.text))))
    }
}
```

```swift
// FILE: App/Intents/AsistShortcuts.swift
import AppIntents

struct AsistShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KaydetIntent(),
            phrases: [
                "\(.applicationName)'e kaydet",
                "\(.applicationName)'e ekle",
                "\(.applicationName) kaydet",
                "\(.applicationName)'e not al",
                "\(.applicationName) hatırlat"
            ],
            shortTitle: "Kaydet",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: DinleIntent(),
            phrases: [
                "\(.applicationName) dinle",
                "\(.applicationName) beni dinle",
                "\(.applicationName) ile konuş"
            ],
            shortTitle: "Dinle",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: BugunIntent(),
            phrases: [
                "\(.applicationName) bugün ne var",
                "\(.applicationName) bugün neler var",
                "\(.applicationName)'te bugün ne var",
                "\(.applicationName) gündem"
            ],
            shortTitle: "Bugün Ne Var",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: GecikenlerIntent(),
            phrases: [
                "\(.applicationName) gecikenler",
                "\(.applicationName) neyi unuttum"
            ],
            shortTitle: "Gecikenler",
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}
```

`App/Resources/tr.lproj/AppShortcuts.strings` (UTF-8, LF, identity mapping; keys byte-identical to the code with `${applicationName}`):

```
"${applicationName}'e kaydet" = "${applicationName}'e kaydet";
"${applicationName}'e ekle" = "${applicationName}'e ekle";
"${applicationName} kaydet" = "${applicationName} kaydet";
"${applicationName}'e not al" = "${applicationName}'e not al";
"${applicationName} hatırlat" = "${applicationName} hatırlat";
"${applicationName} dinle" = "${applicationName} dinle";
"${applicationName} beni dinle" = "${applicationName} beni dinle";
"${applicationName} ile konuş" = "${applicationName} ile konuş";
"${applicationName} bugün ne var" = "${applicationName} bugün ne var";
"${applicationName} bugün neler var" = "${applicationName} bugün neler var";
"${applicationName}'te bugün ne var" = "${applicationName}'te bugün ne var";
"${applicationName} gündem" = "${applicationName} gündem";
"${applicationName} gecikenler" = "${applicationName} gecikenler";
"${applicationName} neyi unuttum" = "${applicationName} neyi unuttum";
```
CI fallbacks (01b §4.12, 05a #30), in this order, only when the build fails at the App Shortcuts step: (1) delete this `.strings` file (in-code Turkish phrases + development language `tr` remain); (2) set `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING: NO`. Never set `SWIFT_REFLECTION_METADATA_LEVEL` (App Intents metadata extraction needs reflection metadata). `package-ipa.sh` (§7.5) reports missing intents metadata as a CI error annotation.

Back Tap / Shortcuts recipes for users (docs/KURULUM.md, GuideView; 05b A8 — the headless recipe is the primary guide):
- **Guide A — "Asist Hızlı Kayıt" (recommended, app stays closed):** Kestirmeler → yeni kestirme → "Metni Dikte Et" (Dil: Türkçe, Dinlemeyi Durdur: Duraklamadan Sonra) → "Asist'e Kaydet" (Metin = Dikte Edilen Metin) → adı "Asist Hızlı Kayıt" → Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokunma › Çift Dokunma → "Asist Hızlı Kayıt".
- **Guide A-alt — "Asist Dinle" (opens the app and listens):** Arkaya Dokunma › Üç Kez Dokunma → kestirme "Asist Dinle".

### 3.8 Widgets — deferred to v1.1

The widget extension and the iOS 18 Control are **not built in v1.0** (D30). Their binding design (with the 05a #14 `@Sendable` completion fix and the 05a #29 fallback) is in **Appendix B.4**. v1.0 has no `Widgets/` or `Shared/` directory.

---

## 4. Concurrency, error handling, logging

### 4.1 Concurrency rules

1. Build settings: `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`. **Never** add `SWIFT_DEFAULT_ACTOR_ISOLATION`, `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_UPCOMING_FEATURE_*` (incl. `MemberImportVisibility`), `-strict-concurrency=complete`, `SWIFT_REFLECTION_METADATA_LEVEL`, or "Treat warnings as errors".
2. `@MainActor` classes (all app state and services): `AppEnvironment, DataStore, AppRouter, ToastCenter, PermissionCenter, NotificationScheduler, ReminderEngine, SigningMonitor, VoiceCoordinator, SpeechListener, Speaker, VolumeButtonTrigger, CaptureService, CaptureDraft, CommandExecutor`, and the enum `Haptics`.
3. Non-isolated by design: `NotificationCoordinator` (delegate called on a private queue), `AppDelegate` (UIKit makes it main-actor via the protocol), `BackgroundRefresh` (enum) + `BGCompletion` (`@unchecked Sendable`, lock-protected), `AsistLog`/`LogBuffer`, every AsistCore type.
4. **Hop pattern** from a non-isolated callback: copy value-typed data out first, then `Task { @MainActor in … }`. Never `DispatchQueue.main.sync`, never semaphores, never `Task.detached`. The single exception is a UIKit expiration handler that must finish synchronously: `MainActor.assumeIsolated { … }` (§3.6.2).
5. Delegate methods of `@MainActor` NSObject classes (`Speaker`) are declared `nonisolated func` and hop as in rule 4 with `[weak self]` in the inner `Task { @MainActor [weak self] in … }` capture list.
6. Closures handed to audio/speech/KVO frameworks are created in `nonisolated static` factory functions (01b pattern) so they are not inferred `@MainActor`.
7. `ReminderEngine.reconcile` is serialized with a task chain (01a §5.6). No other code writes pending notification requests except `NotificationScheduler` (`apply`, the immediate `add` used by `ReminderEngine.handle`, `removeAll(for:)`, and `addUnmanaged` for `asist.x.*` only).
8. `@Observable` classes: `import Observation`; mutable non-UI stored `var`s are `@ObservationIgnored`; `let` constants get **no** annotation; no `lazy var`; no property wrappers inside (`@AppStorage`, `@Published`, `@State` are forbidden in these classes); no `didSet` on observed properties.
9. Views get observable objects with `@Environment(DataStore.self) private var store` (they are injected once in `AsistApp`). For bindings: `@Bindable var router = router` as the first line inside `body`. Services without observable state (`CaptureService`, `CommandExecutor`, `AppEnvironment`) are reached as `AppEnvironment.shared.x` **inside actions only** (button closures, `.task`, `.onChange`), never while computing `body`.
10. Async work started by views uses `.task { }` / `Task { }` inside actions; nothing blocks the main actor for more than a frame.
11. AsistCore is synchronous and value-typed: no `async`, no actors, no global mutable `var` (lexicons are `static let`). Every AsistCore loop over dates is bounded (chain ≤ 400 elements / 14 days, day search ≤ 14 days, recurrence search ≤ 400 steps).
12. **Headless completeness (D34, 05a #1/#7).** Every entry point after which the process may be suspended — App Intent `perform` (via `captureHeadless`), notification action `handle`, BG task, `sceneDidEnterBackground` — **awaits** `engine.reconcile(reason:)` after its last mutation. `requestReconcile` (debounced 300 ms) is only for foreground UI bursts and never the last step of a headless path.
13. **No re-entrant singleton (05a #11).** No initializer invoked from `AppEnvironment.init` (DataStore, AppRouter, ToastCenter, PermissionCenter, NotificationScheduler, SigningMonitor, ReminderEngine, CaptureService, CommandExecutor, VoiceCoordinator and every object they create) may reference `AppEnvironment.shared`, directly or through a helper it calls synchronously. Cross-service access happens lazily in methods or closures executed after init.

### 4.2 Error handling rules

1. No `try!`, no `fatalError`, no `precondition` in shipping code (tests may use `XCTUnwrap`/force unwrap). Force unwrap allowed only for literal constants (`URL(string: "asist://bugun")!`, `TimeZone(secondsFromGMT: 10800)!`).
2. Every `catch` logs with `AsistLog.error(…, category)`; user-visible failures surface as a toast or banner with 03 §7.12 text as amended in §5.5 (`error.save_failed`, `error.disk_full`…).
3. UserNotifications `add` failures: logged, never thrown to UI; reconcile continues with the next request.
4. Data safety over everything: a failed save keeps the in-memory state, sets `lastSaveError`, retries on next mutation and on `sceneDidEnterBackground`; the UI never says "Kaydedildi" unless `store.canPersist` (05a #3). An unreadable data file is copied to `asist-data.corrupt-*.json` before anything else is written (03 §9 r26); a partially decoded or newer-build file is copied before the first save (§3.6.4).
5. Every `didReceive` path calls `completionHandler()` exactly once, after `engine.handle` returned (which persisted, replaced the item's pending requests and reconciled).
6. Every `switch` on an SDK enum has `@unknown default:`.
7. Speech failures degrade to the keyboard path with a Turkish message; never a blank screen.
8. Every `Task.sleep(nanoseconds:)` argument is `UInt64(max(0, seconds) * 1_000_000_000)` (a negative Double traps in `UInt64`, 05a #20).

### 4.3 Logging

- `AsistLog.info/error(message, category)` → `os.Logger(subsystem: "com.gokhanbudak.asist", category:)` + ring buffer (300 lines) shown and shareable in Diagnostics (`ShareLink(item: lines.joined(separator: "\n"))`).
- Categories: `app, store, notif, voice, intents, smart, location, widget, ui` (the last three unused until v1.1/v1.2).
- MUST log: every reconcile (reason, planned, dropped, rate-limited, added, badge, timeSensitiveAllowed), every notification action (action id, item id, kind, found/not found, persisted yes/no), store load path + issues (incl. writerBuild), save failures, BG refresh start/end, re-sign detection, speech error domain/code.
- MUST NOT log: full utterances, notes content.

---

## 5. User interface

03 is the visual/behavioural spec (wireframes, copy, sizes) **as amended by §5.5**. This section fixes **struct names, inputs, state sources and navigation** so WP9–WP11 can work in parallel.

### 5.1 Navigation structure

```
AsistApp (WindowGroup)
└─ RootView                                  reads: store, router, voice, permissions, toasts; @Environment(\.scenePhase)
   ├─ MainTabView                            TabView(selection: $router.selectedTab), classic .tabItem (03 §4.1)
   │  ├─ NavigationStack(path: $router.todayPath)    TodayView        tab "Bugün"    sun.max.fill
   │  ├─ NavigationStack(path: $router.listsPath)    ListsView        tab "Listeler" list.bullet
   │  ├─ NavigationStack(path: $router.projectsPath) ProjectsView     tab "Projeler" folder.fill
   │  └─ NavigationStack(path: $router.settingsPath) SettingsView     tab "Ayarlar"  gearshape.fill
   │     every stack: .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
   ├─ .overlay: ListeningOverlay   when voice.isOverlayVisible (ZStack overlay; VoiceCoordinator dismisses any sheet
   │                               before listening because a sheet would cover the overlay — 05a #18)
   ├─ .overlay(alignment: .bottom): ToastHost
   ├─ .sheet(item: $router.sheet, onDismiss: { AppEnvironment.shared.capture.commitActiveDraftIfNeeded() }) { SheetHost(route: $0) }
   ├─ .fullScreenCover(isPresented: $router.showOnboarding) { OnboardingView() }   (05a #26 — no custom Binding)
   ├─ .background { SystemVolumeAnchor(trigger: voice.trigger).frame(width: 1, height: 1)
   │                .allowsHitTesting(false).accessibilityHidden(true) }   when settings.volumeTriggerEnabled (05a #17)
   └─ .onOpenURL { router.handle(url: $0) }
```

RootView lifecycle (WP9):
- `.onChange(of: scenePhase, initial: true) { _, phase in … }`: `.active` → `Task { await AppEnvironment.shared.sceneDidBecomeActive(); consumePending() }`; `.background` → `AppEnvironment.shared.sceneDidEnterBackground()`; `.inactive` → nothing.
- `.onChange(of: router.pending) { _, new in if new != nil && scenePhase == .active { consumePending() } }`.
- `consumePending()` executes `router.takePending()`:

| PendingAction | Effect |
|---|---|
| `.listen(req)` | `Task { try? await Task.sleep(nanoseconds: 350_000_000); await voice.startListening(req) }` |
| `.compose` | `router.present(.compose(ListenRequest()))` |
| `.readAgenda` | `Task { await AppEnvironment.shared.commands.readTodayAgenda() }` |
| `.openItem(id)` | `router.openItem(id)` |
| `.completeItem(id)` | `AppEnvironment.shared.capture.completeFromLink(id); router.showToday()` |
| `.endOfDay` | `router.openRoute(.endOfDay, in: .today)` |
| `.today` | `router.showToday()` |
| `.followUpMessage(id)` | `router.present(.followUpMessage(id))` |
| `.settingsTriggers` | `router.openRoute(.triggerSettings, in: .settings)` |
| `.dataSettings` | `router.openRoute(.dataSettings, in: .settings)` |

`RouteDestination(route:)`: `.item(id)` → `ItemDetailView(itemID:)`, `.project(id)` → `ProjectDetailView(projectID:)`, `.endOfDay` → `EndOfDayView()`, `.completed` → `CompletedListView()`, `.recentlyDeleted` → `RecentlyDeletedView()`, `.guide(k)` → `GuideView(kind:)`, `.appStatus` → `AppStatusView()`, `.diagnostics` → `DiagnosticsView()`, `.generalSettings` → `GeneralSettingsView()`, `.timeSettings` → `TimeSettingsView()`, `.nagSettings` → `NagSettingsView()`, `.summarySettings` → `SummarySettingsView()`, `.triggerSettings` → `TriggerSettingsView()`, `.dataSettings` → `DataSettingsView()`.

`SheetHost(route:)`: `.compose(req)` → `ComposeSheet(request:)`, `.confirm(d)` → `ConfirmationSheet(draft:)`, `.match(p)` → `MatchConfirmationSheet(proposal:)`, `.agenda(a)` → `AgendaAnswerSheet(answer:)`, `.datePicker(r)` → `DateTimePickerSheet(request:)`, `.projectEditor(id)` → `ProjectEditorSheet(projectID:)`, `.followUpMessage(id)` → `FollowUpMessageSheet(itemID:)`.

Navigation uses only value-based `NavigationLink(value: Route.x)`; no destination-based links (keeps `path` authoritative).

### 5.2 Screens (struct, file, inputs, state read, key behaviour)

| View | Inputs | Reads | Behaviour (spec) |
|---|---|---|---|
| `TodayView` | — | store, router, voice, permissions, signing, engine | `TimelineView(.everyMinute) { ctx in … }`; `let snap = AgendaBuilder.snapshot(items: store.items, now: ctx.date, settings: store.settings, calendar: AppTime.calendar)` (computed once per minute, never elsewhere in `body`); `List` (`.insetGrouped`) with `TodayHeader`, top `BannerView` (`permissions.topBanner(…)`), `MuteBanner` while `store.settings.muteUntil > now` ("Sessiz: 11:30'a kadar" + × → `muteUntil = nil`), `HeroCard` (first overdue), sections GECİKENLER / EMİN OLAMADIKLARIM / BUGÜN / TAKİP / YAKLAŞAN / ZAMANI BELİRSİZ (n) / "Bu hafta n iş bitti"; `.safeAreaInset(edge: .bottom) { BottomCaptureBar() }`; toolbar: `MuteMenu` (`bell.slash.fill`: 30 dk / 1 saat / 2 saat / Mesai sonuna kadar → `store.updateSettings { $0.muteUntil = … }`, D32) and Gün Sonu (`moon.fill` → `.endOfDay`). Banner actions: `.openNotificationSettings` → `PermissionCenter.openNotificationSettings()`, `.openAppSettings` → `PermissionCenter.openAppSettings()`, `.openAppStatus` → `router.openRoute(.appStatus, in: .settings)`, `.openDiagnostics` → `.diagnostics`, `.openGuideBanners` → `router.openRoute(.guide(.banners), in: .settings)`; dismiss → `store.updateMeta { $0.dismissedBanners[banner.id] = now + banner.hideHours h }`. Empty: `EmptyStateView` 03 §7.10. Undo band for `meta.lastEndOfDayMove` < 24 h. (03 §4.3) |
| `TodayHeader` | `now`, `snapshot`, `userName` | — | date "27 Eylül Pazar", greeting by hour (Günaydın <12, İyi günler <18, İyi akşamlar <22, else İyi geceler) + ", \(name)" if set; 3 `StatChip`s ("2 geciken", "5 bugün", "1 takip") → `router.listFilter` + tab switch |
| `HeroCard` | `item`, `projectName`, `now` | — | 4 buttons 56 pt: ✓ Yaptım / 10 dk / 1 saat / Yarın (→ store.markDone/snooze + undo toast + Haptics) + mic chip "Sesle ertele" → `voice.startListening(ListenRequest(snoozeItemID: item.id))` (05b D5) |
| `BottomCaptureBar` | — | voice, router | Yaz (56) → `.compose`, Mic (88) → `voice.startListening()`, Oku (56) → `commands.readTodayAgenda()` / Durdur while `voice.phase == .speaking`; low-volume hint when `voice.volumeTooLow` (03 listen.vol.hint_zero) |
| `ListeningOverlay` | — | voice | 03 §5.3: phase text, live transcript (≤ 5 lines), level ring (Reduce Motion → bar), Vazgeç / Klavye / Bitti (72 pt); tap background = Bitti; "Vazgeç" → `voice.cancelListening()` (undo toast when ≥ 2 words, 05b B9); snooze mode shows the title "Yeni zamanı söyle" |
| `ConfirmationSheet` | `draft: CaptureDraft` | store (projects), router | 03 §4.5: `@Bindable var draft = draft`; heard text + "Tekrar söyle"; kind icon, editable title, relative date ("6 Ekim Salı · 7 gün sonra" for +7-day weekdays, P3); chip rows Gün/Saat/Öncelik/Tür/Proje/Tekrar/Kişi/**Etkinlik**/**Ön uyarı**; `draft.defaultedToToday` → chips Bugün / Yarın / Zamanı belirsiz (D33); "Ne zaman?" row when `draft.needsTime`; `alternativeTimes` as chips ("+7 gün", "Bugün", 03:00/15:00); "Yeni proje: X" chip never pre-selected (05b D11); buttons Vazgeç / Kaydet with countdown ring (`.task(id: draft.id)` 1 s loop; stops when `!draft.autoSaveActive`); any chip tap sets `autoSaveActive = false`; `presentationDetents([.medium, .large])`; VoiceOver running (`UIAccessibility.isVoiceOverRunning`) → no countdown. No Smart Mode UI in v1.0 |
| `ComposeSheet` | `request: ListenRequest` | store (meta.composeDraft), router | 03 §4.6: `TextField(axis: .vertical)` focused; 300 ms debounced preview via `.task(id: text)`; "Ekle" / "Önizle" (low level, 05b F2); draft saved to `meta.composeDraft` on disappear |
| `MatchConfirmationSheet` | `proposal` | store | single: "“X” tamamlandı mı?" [Evet][Hayır]; ambiguous: "Hangisi?" rows (64 pt); cancel = "silinsin mi?" red; snooze shows "Perşembe 10:00'a ertelensin mi?" |
| `AgendaAnswerSheet` | `answer: SpokenAnswer` | store, voice | title, ItemRows for `answer.itemIDs`, Durdur (56 pt) while speaking |
| `ListsView` | — | store, router | filter `ChipRow` bound to `router.listFilter` (with counts), `.searchable` (TurkishText.searchKey over title/notes/person/project/originalText), sort `Menu` (Zamana / Önceliğe / Eklenme), project filter `Menu`; floating 64 pt mic (bottom-trailing) → `voice.startListening()`; swipe: leading Yaptım (green) — on `needsReview` rows also "Doğru" (clears the flag, 05b D8) —, trailing Ertele (`SnoozeOptions` menu) + Sil (red, undo) (03 §4.7) |
| `CompletedListView` | — | store | last 90 days by completedAt; swipe "Yeniden aç" |
| `ItemDetailView` | `itemID: UUID` | store, router | 03 §4.8; "Kayıt bulunamadı" if missing/deleted; text fields commit on submit/disappear; pickers/toggles commit immediately via `store.update`; sections: title, priority/project badges, ZAMAN (due `DatePicker`, relative text, `SnoozeGrid`, Tekrar menu, Ön uyarı menu [Yok, 10 dk, 15 dk, 30 dk, 1 saat, 1 gün, 1 hafta, 30 gün], Israr düzeyi menu over `NagProfileKind.selectable` + "Otomatik", Etkinlik toggle), Tür/Öncelik/Proje/**Kişi / Firma** (05b F15)/Yer (text only), NOTLAR (TextEditor + "Sesle not ekle"), `ChecklistSection`, ORİJİNAL CÜMLE, `HistorySection`; bottom 56 pt "✓ Yaptım"/"✓ Geldi"; `•••` menu: Çoğalt, Paylaş (`ShareLink`), Sil (`confirmationDialog`) |
| `SnoozeGrid` | `item`, `now` | store, voice | 2×3 chips: 30 dk, 1 saat, Bu akşam (hidden after 18:30), Yarın sabah, Pazartesi, Tarih seç… (`.datePicker`) + full-width "Sesle ertele" (mic, 05b D5); `snoozeCount ≥ 3` → hint "Birkaç kez ertelendi. Başka bir gün mü?" |
| `ChecklistSection` | `item` | store | toggle entries, add entry, template `Menu` (ChecklistTemplates.all) |
| `HistorySection` | `item` | — | "27 Eyl 10:14 · sesle oluşturuldu" lines (newest first) |
| `DateTimePickerSheet` | `request` | store | graphical date + wheel time; purpose snooze → store.snooze; due → store.update(dueDate, hasTime = true, resetNagState) |
| `FollowUpMessageSheet` | `itemID` | store | template 03 `detail.fu_message.template` — greeting "Merhaba <Ad>," only when the person looks like a person (honorific or known person), else "Merhaba," (05b F15); editable; `ShareLink(item: text)`; after share: "Yeniden ne zaman soralım?" (Yarın / 2 gün sonra / Pazartesi) |
| `ProjectsView` | — | store, router | 03 §4.9 list (color stripe, name, counts, last note line); "+" → `.projectEditor(nil)`; archived section |
| `ProjectDetailView` | `projectID` | store, voice | segmented İşler / Notlar / Tamamlanan; 56 pt "Bu projeye sesli not" → `voice.startListening(ListenRequest(kind: .note, projectID: id))`; menu: Düzenle, Arşivle |
| `ProjectEditorSheet` | `projectID: UUID?` | store | name, 8 color swatches, aliases (comma separated) |
| `EndOfDayView` | — | store, router | simple list over `AgendaBuilder.endOfDayCandidates` (per row: ✓ Yaptım / Sonraki iş günü / Sil) + "Bu akşam" read-only group for later-today items; 56 pt "Sonraki iş gününe taşı" → `store.moveOpenItemsToTomorrow` + toast undo (05b B6/F6); card-by-card flow is v1.1 |
| `SettingsView` | — | store, router, signing | sections 03 §4.11 as `NavigationLink(value: Route…)`; Projeler → switches tab; version footer "1.0.0 (build n)" |
| `GeneralSettingsView`, `TimeSettingsView`, `NagSettingsView`, `SummarySettingsView`, `TriggerSettingsView`, `DataSettingsView` | — | store | **settings edit pattern:** `@State private var s = AppSettings()`, `.onAppear { s = store.settings }`, `.onChange(of: store.settings) { _, latest in if latest != s { s = latest } }` (05a #19: never writes back a stale copy), `Form` bound to `$s.field`, `.onChange(of: s) { _, new in if new != store.settings { store.updateSettings { $0 = new } } }` (no custom `Binding(get:set:)`) |
| `GeneralSettingsView` | — | store | hitap, "Onayları sesli söyle (kulaklık/araçta)", "Hoparlörden de söyle" (D18), TTS hızı, otomatik kaydetme, "Zaman söylemezsem" |
| `TimeSettingsView` | — | store | workdays (the last remaining workday toggle is disabled, 05a #8), work/quiet hours, dayparts incl. "Öğleden önce", follow-up time, event pre-alert (Yok / 5 / 10 / 15 / 30 dk) |
| `NagSettingsView` | — | store | profile `Picker` per priority over `NagProfileKind.selectable`; read-only preview line per profile from `NagPlanner.chain(anchor: today 15:00 …, now: now)` formatted "15:00 · 15:10 · …"; "Kritik işler sessiz saatte de ısrar etsin"; badge mode; "Kilit ekranında konuyu göster" |
| `TriggerSettingsView` | — | store, router | volume toggle + footer texts (§5.5 F7), restore-volume toggle, silence picker, on-device toggle; guide links `.guide(.backTap/.backTapListen/.siri/.focus/.banners)`; `SiriTipView(intent: KaydetIntent(), isVisible: $showTip)`; `ShortcutsLink()`; "Kestirmeler'i Aç" `Link(destination: URL(string: "shortcuts://")!)` |
| `GuideView` | `kind` | — | numbered steps (03 §4.13 A, C, E + §3.7 recipes + "Kalıcı": Ayarlar › Bildirimler › Asist › Banner Stili › Kalıcı), SF Symbol per step, note "Menü adları iOS sürümüne göre küçük farklılık gösterebilir." |
| `DataSettingsView` | — | store, toasts | Export: `ShareLink(item: exportFileURL)` (temp file `Asist-yedek-yyyy-MM-dd-HHmm.json`); Import: security-scoped `.fileImporter` (exact pattern below) → preview alert "n kayıt, m proje içe aktarılacak" → Birleştir / Değiştir; list of daily backups (restore from one = import replace); "Son silinenler" → `.recentlyDeleted`; note that backups and `Asist-acik-isler.txt` are in Dosyalar › Bu iPhone'da › Asist › Yedekler |
| `RecentlyDeletedView` | — | store | `store.recentlyDeleted`; swipe "Geri getir" → `store.restoreDeleted` + toast (05b B8) |
| `AppStatusView` | — | signing, permissions, engine, store | İmza bitişi (`signing.expiryDate`, else `estimatedExpiry` + "(tahmini)", else "bilinmiyor"), imza türü, permission rows with "Ayarları Aç", "Banner Stili: Kalıcı" row (`permissions.alertsPersistent`), data writer build, "Yeniden yükleme nasıl yapılır?" → KURULUM summary |
| `DiagnosticsView` | — | engine, store | `engine.lastReport` (incl. rate-limited, time-sensitive allowed), `await scheduler.pendingSummary()` (first 30, "n/64"), last BG refresh, speech on-device support, log lines (`AsistLog.recentLines()`) + `ShareLink`; buttons "Test bildirimi (10 sn)", "Planı yeniden kur" (`engine.rebuildAll`) |
| `OnboardingView` | — | store, permissions, router | **3 pages** (05b A10, `TabView` `.page` style): (1) promise + notification permission (`permissions.requestNotifications()`) + "Kalıcı" banner tip; (2) mic/speech permission (`permissions.requestVoice()`) + live test "1 dakika sonra su içmeyi hatırlat"; (3) quick access: Siri phrase, Back Tap guide A link, `ShortcutsLink()`, one line "İşte Odak kullanıyorsan Asist'i izinli uygulamalara ekle" + guide E link, "Test bildirimi (30 sn)"; "Başla" sets `onboardingCompleted = true` and `router.showOnboarding = false`; "Atla" top-right does the same; restore-from-backup link (03 §9 r25). Work/quiet hours keep their defaults (changeable later in Ayarlar › Zamanlar) |

Security-scoped import (05a #12) — exact pattern in `DataSettingsView.swift` (file imports `UniformTypeIdentifiers`):

```swift
.fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json]) { result in
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

### 5.3 Shared components (WP9 implements; signatures frozen)

```swift
// API (App/UI/Components/*)
struct ItemRow: View {
    let item: Item
    let projectName: String?
    let now: Date
    let onToggleDone: () -> Void          // 44 pt circle (28 pt visual)
    var body: some View                   // stripe 4 pt + kind symbol + title (+ PriorityBadge) + 2nd line
}                                         // (relativeShort · project · person · repeat/event symbol); ≥ 64 pt; a11y actions Yaptım/Ertele/Sil

// Chip.swift declares Chip, ChipRow and StatChip (only there, 05a #31).
struct StatChip: View { let title: String; let color: Color; let action: () -> Void }

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var isUncertain: Bool = false         // dashed border + "?" (03 §7.5)
    let action: () -> Void
}

struct ChipRow<Content: View>: View {     // horizontal ScrollView, 8 pt spacing
    @ViewBuilder let content: () -> Content
}

struct PrimaryButtonStyle: ButtonStyle { var tint: Color = .asistAccent; var filled: Bool = true }  // height ≥ 56

struct MicButton: View { let size: CGFloat; let isActive: Bool; let action: () -> Void }  // a11y "Dinlemeye başla"

struct ToastHost: View {}                 // reads ToastCenter; "Geri Al" when toast.hasUndo → toasts.performUndo()

struct BannerView: View { let banner: AppBanner; let onAction: () -> Void; let onDismiss: (() -> Void)? }

struct EmptyStateView: View { let title: String; let message: String; let systemImage: String }

struct PriorityBadge: View { let priority: Priority }    // high "ÖNEMLİ" orange, critical "KRİTİK" red, else EmptyView

struct SectionHeader: View { let title: String; var count: Int? = nil; var color: Color = .secondary }

// MuteMenu.swift
struct MuteMenu: View {}                  // toolbar Menu (D32); presets via NagPlanner.muteUntilWorkEnd for "Mesai sonuna kadar"
struct MuteBanner: View { let until: Date; let onCancel: () -> Void }   // "Sessiz: 11:30'a kadar" ×

enum SnoozeOption: String, CaseIterable, Identifiable {
    case min10, min30, hour1, hour2, thisEvening, tomorrowMorning, monday, custom
    var id: String { rawValue }
    var title: String                      // "10 dk", "30 dk", "1 saat", "2 saat", "Bu akşam", "Yarın sabah", "Pazartesi", "Tarih seç…"
    /// nil for .custom, and for .thisEvening after 18:30. Uses NagPlanner helpers; results ceil to the minute.
    func target(now: Date, settings: AppSettings, calendar: Calendar) -> Date?
}
```

### 5.4 Design tokens — exact

```swift
// FILE: App/UI/DesignSystem/Tokens.swift
import SwiftUI
import UIKit
import AsistCore

extension Color {
    static let asistOverdue = Color.red
    static let asistToday = Color.orange
    static let asistUpcoming = Color.blue
    static let asistDone = Color.green
    static let asistNote = Color.gray
    static let asistFollowUp = Color.teal
    static let asistReview = Color.yellow
    static let asistAccent = Color.indigo
    static let asistBackground = Color(uiColor: .systemGroupedBackground)
    static let asistCard = Color(uiColor: .secondarySystemGroupedBackground)

    static func project(_ color: ProjectColor) -> Color {
        switch color {
        case .blue: return Color.blue
        case .green: return Color.green
        case .orange: return Color.orange
        case .red: return Color.red
        case .purple: return Color.purple
        case .teal: return Color.teal
        case .pink: return Color.pink
        case .brown: return Color.brown
        }
    }
}

enum Metrics {
    static let micLarge: CGFloat = 88
    static let micFloating: CGFloat = 64
    static let listeningDoneHeight: CGFloat = 72
    static let primaryButtonHeight: CGFloat = 56
    static let chipHeight: CGFloat = 44
    static let chipMinWidth: CGFloat = 64
    static let chipSpacing: CGFloat = 8
    static let rowMinHeight: CGFloat = 64
    static let completionVisual: CGFloat = 28
    static let completionHitArea: CGFloat = 44
    static let cornerRadius: CGFloat = 14
    static let padding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let stripeWidth: CGFloat = 4
}

enum Symbol {
    static let reminder = "bell.fill"
    static let task = "circle"
    static let taskDone = "checkmark.circle.fill"
    static let note = "note.text"
    static let followUp = "hourglass"
    static let recurrence = "repeat"
    static let preAlert = "bell.badge"
    static let place = "location.fill"
    static let project = "folder.fill"
    static let person = "person.fill"
    static let checklist = "checklist"
    static let critical = "flag.fill"
    static let important = "exclamationmark.circle.fill"
    static let overdue = "exclamationmark.triangle.fill"
    static let mic = "mic.fill"
    static let listening = "waveform"
    static let stop = "stop.circle.fill"
    static let keyboard = "keyboard"
    static let speak = "speaker.wave.2.fill"
    static let briefing = "sunrise.fill"
    static let endOfDay = "moon.fill"
    static let snooze = "clock.arrow.circlepath"
    static let mute = "bell.slash.fill"
    static let event = "calendar"
    static let voiceSnooze = "mic.badge.plus"
    static let smartMode = "sparkles"
    static let email = "envelope.fill"
    static let message = "paperplane.fill"
    static let export = "square.and.arrow.up"
    static let importData = "square.and.arrow.down"
    static let backTap = "hand.tap.fill"
    static let review = "questionmark.circle.fill"
    static let tabToday = "sun.max.fill"
    static let tabLists = "list.bullet"
    static let tabProjects = "folder.fill"
    static let tabSettings = "gearshape.fill"
}

extension ItemKind {
    var symbol: String {
        switch self {
        case .reminder: return Symbol.reminder
        case .task: return Symbol.task
        case .note: return Symbol.note
        case .waiting: return Symbol.followUp
        }
    }
}

extension Item {
    /// Row stripe/time color: overdue red, today orange, waiting teal, note gray, else blue.
    func statusColor(now: Date, calendar: Calendar) -> Color {
        if kind == .note { return Color.asistNote }
        if isOverdue(at: now, calendar: calendar) { return Color.asistOverdue }
        if kind == .waiting { return Color.asistFollowUp }
        if isDueToday(at: now, calendar: calendar) { return Color.asistToday }
        return Color.asistUpcoming
    }
}
```

Typography (03 §7.3): only Dynamic Type styles — screen title `.largeTitle`; section header `.footnote.weight(.semibold)`; row title `.body.weight(.medium)` (critical `.semibold`); row subtitle `.subheadline` + `.monospacedDigit()`; card title `.title2.weight(.semibold)`; card time `.title3.weight(.semibold)`; live transcript `.title2`; buttons `.headline`. Section headers are Turkish uppercase **literals** (`"GECİKENLER"`, `"BUGÜN"`, `"YAKLAŞAN"`, `"TAKİP"`, `"EMİN OLAMADIKLARIM"`, `"ZAMANI BELİRSİZ"`, `"NOTLAR"`, `"KONTROL LİSTESİ"`, `"ORİJİNAL CÜMLE"`, `"GEÇMİŞ"`, `"ZAMAN"`, `"BU AKŞAM"`). Reduce Motion: `@Environment(\.accessibilityReduceMotion)` disables pulse/scale. Dark mode automatic (system colors).

### 5.5 Turkish copy amendments (binding over 03 §7.12; 05b §7)

| # | Where | Use | Instead of |
|---|---|---|---|
| F1 | EOD review drop button | "Sil" (red) | "Vazgeç (sil)" |
| F2 | needsReview badge / section / compose button | "Emin değilim" / "EMİN OLAMADIKLARIM" / "Önizle" | "Kontrol et" / "KONTROL EDİLECEK" |
| F3 | `DinleIntent` title | "Asist Dinle" | "Asist'i Dinlet" |
| F4 | `BugunIntent` title and short title | "Bugün Ne Var" | "Bugün Neler Var?" / "Bugün" |
| F5 | `INAlternativeAppNames` | removed | "Asistan" |
| F6 | EOD action and button | "Sonraki iş gününe taşı" | "Hepsini yarına taşı" |
| F7 | `settings.volume_key.footer` | "Ses seviyesi bir anlığına düşer, sonra eski haline döner." — only after device test D-f confirms the restore; otherwise keep 03's text | "Ses seviyesi iki kademe azalır." |
| F8 | follow-up k=0 subtitle | "Geldi mi? · 2 gündür bekliyor"; "Son tarih: …" only when `hasTime` | "Geldi mi? Son tarih: Cuma" always |
| F9 | last-of-day subtitle | "Bugünlük son hatırlatma · yarın sabah yine" | long form |
| F10 | snoozed ≥ 3 subtitle | "3. erteleme · başka bir gün mü?" | "%d. kez ertelendi — …" |
| F11 | long-tail subtitle | "Hâlâ açık · her sabah soracağım" | long form |
| F12 | TTS times | 12-hour + daypart ("salı öğleden sonra üçte"); screens stay 24 h | "salı saat on beşte" |
| F13 | terminology | "geciken" everywhere ("2 geciken", "GECİKENLER") | "gecikmiş" |
| F14 | terminology | "Zamanı belirsiz" everywhere | "Zamansız görev" / "Tarihsiz" |
| F15 | person field label | "Kişi / Firma" | "Kişi" |
| F16 | sentinels | budget sentinel = the dropped item's own alert + "+3 hatırlatma daha — planı tazelemek için Asist'i aç"; horizon sentinel §3.5.5 | generic "Asist'i bir kez aç" |
| C6 | nag body | "Sonraki: 15:30" on nags; the "“✓ Yaptım” diyene kadar…" line only on k = 0 | promise on every nag |

---

## 6. Notifications — identifiers, categories, nag algorithm, budget

### 6.1 Identifier scheme (constants in `NotificationCatalog.swift`)

| Identifier | Kind | Rule | Thread | Category | Managed by |
|---|---|---|---|---|---|
| `asist.i.<UUID>.<k>` | `.first` (k = 0) / `.nag` (k ≥ 1, incl. day-tail) | once | `asist.i.<UUID>` | `ASIST_ITEM` (waiting: `ASIST_FOLLOWUP`) | planner |
| `asist.i.<UUID>.pre.<minutes>` | `.preAlert` | once | `asist.i.<UUID>` | **`ASIST_PRE`** | planner |
| `asist.i.<UUID>.d` | `.longTail` (high/critical only) | daily repeat | `asist.i.<UUID>` | item / follow-up | planner |
| `asist.i.<UUID>.o.<yyyyMMddHHmm>` | `.occurrence` (one-shot future occurrences, D27) | once | `asist.i.<UUID>` | `ASIST_ITEM` / follow-up | planner |
| `asist.i.<UUID>.r.<d\|w1…w7\|m>` | `.carrier` (repeating future occurrences, D27) | daily / weekly / monthly repeat | `asist.i.<UUID>` | `ASIST_ITEM` / follow-up | planner |
| `asist.brief.<yyyyMMdd>` | `.briefing` | once | `asist.digest` | `ASIST_BRIEF` | planner |
| `asist.eod.<yyyyMMdd>` | `.endOfDay` | once | `asist.digest` | `ASIST_EOD` | planner |
| `asist.backup` | `.backup` | weekly repeat | `asist.system` | `ASIST_SYSTEM` | planner |
| `asist.sign.<yyyyMMddHHmm>` | `.signing` (warnings + expiry notice) | once | `asist.system` | `ASIST_SYSTEM` | planner |
| `asist.sentinel` | `.sentinel` (copy of the earliest dropped item notification) | once | that item's thread | that item's category | planner |
| `asist.sentinel.h` | `.horizon` | once | `asist.system` | `ASIST_SYSTEM` | planner |
| `asist.x.test`, `asist.x.moved` | ad hoc | time interval | `asist.system` | `ASIST_ITEM` / `ASIST_SYSTEM` | `NotificationScheduler.addUnmanaged` |
| `asist.loc.<UUID>` | location (v1.2, Appendix B.3) | — | — | — | not created in v1.0 |

`k` is the position in the **full chain computed from the anchor** (never from "now"), so IDs of remaining elements are stable across reconciles (01a §5.3) as long as the anchor and the mute window are unchanged. A new anchor (snooze, edit, occurrence roll-over) or a mute change re-maps `k` — same identifiers are replaced by `add` (same identifier replaces pending).

userInfo on every request: `iid` (item UUID string or ""), `k` (Int), `fp` (fingerprint String), `nk` (`PlannedNotification.Kind.rawValue` or "test"). Values are String/Int only.

### 6.2 Categories and actions (registered by `NotificationCategories.register`, §3.6.5)

| Category | Actions (order = display order) | Options |
|---|---|---|
| `ASIST_ITEM` | `ASIST_DONE` "✓ Yaptım" (bg) · `ASIST_SNOOZE_10` "10 dk" (bg) · `ASIST_SNOOZE_60` "1 saat" (bg) · `ASIST_TOMORROW` "Yarın sabah" (bg) | `.customDismissAction` (+ `.hiddenPreviewsShowTitle/.hiddenPreviewsShowSubtitle` when `lockScreenShowsContent`) |
| `ASIST_PRE` | `ASIST_DONE` "✓ Yaptım" (bg) | same as item |
| `ASIST_FOLLOWUP` | `ASIST_FU_RECEIVED` "✓ Geldi" (bg) · `ASIST_FU_TOMORROW` "Yarın tekrar sor" (bg) · `ASIST_FU_2DAYS` "2 gün sonra" (bg) · `ASIST_FU_MESSAGE` "Mesaj gönder…" (`.foreground`) | same as item |
| `ASIST_BRIEF` | `ASIST_BRIEF_READ` "Sesli oku" (`.foreground`) | show title |
| `ASIST_EOD` | `ASIST_EOD_MOVE` "Sonraki iş gününe taşı" (bg) · `ASIST_EOD_REVIEW` "Gözden geçir" (`.foreground`) | show title |
| `ASIST_SYSTEM` | — | show title |

No action uses `.authenticationRequired` (works on the lock screen; store file protection D1).

### 6.3 Action handling (`ReminderEngine.handle`) — ordering is normative (D34, 05b B1)

`handle(event)` runs these steps in order and returns; the coordinator then calls `completionHandler()`:
1. `if !store.isLoaded { store.load() }`; `guard store.isLoaded` else log "action lost: data unavailable" and return (pending requests untouched; the user can act again later).
2. `store.rollOverRecurring(now:calendar:)` (so an action on a carrier-delivered occurrence acts on that occurrence).
3. Defensive: `event.kind == "preAlert"` with a snooze/tomorrow action → log and skip to step 6.
4. Mutation per table below. If the mutation returned nil (item missing/closed **or not persisted**) → skip step 5.
5. **Immediate replacement before completion (B1):** `await scheduler.removeAll(for: id)` (pending + delivered of this item); then, if the item is still open and notifiable, `await scheduler.add(NagPlanner.immediateRequests(for: item, input: makeInput(now: now, allowTimeSensitive: lastReport?.timeSensitiveAllowed ?? false), limit: 2), now: now, calendar: AppTime.calendar)` (a fresh process has no report yet → `.active`, which the following reconcile corrects).
6. `await reconcile(reason: "action")` (full plan; badges, sentinels, other items).
7. Return.

| actionIdentifier | Item missing / closed | Mutation (step 4) |
|---|---|---|
| `ASIST_DONE`, `ASIST_FU_RECEIVED` | log only | `store.markDone(id, at: now)` (recurring → next occurrence) |
| `ASIST_SNOOZE_10` / `ASIST_SNOOZE_60` | idem | `store.snooze(id, until: ceilToMinute(now + 10/60 min))` |
| `ASIST_TOMORROW` | idem | `store.snooze(id, until: NagPlanner.tomorrowMorning(after: now, …))` |
| `ASIST_FU_TOMORROW` | idem | `store.snooze(id, until: NagPlanner.followUpAsk(after: now, workdays: 1, …))` |
| `ASIST_FU_2DAYS` | idem | `store.snooze(id, until: NagPlanner.followUpAsk(after: now, workdays: 2, …))` |
| `ASIST_FU_MESSAGE` (fg) | open app | `router.request(.followUpMessage(id))` (no mutation) |
| `ASIST_BRIEF_READ` (fg) | — | `router.request(.readAgenda)` |
| `ASIST_EOD_MOVE` | — | `store.moveOpenItemsToTomorrow(now:)`; `scheduler.addUnmanaged(id: NotificationID.movedFeedback, text: NotificationCopy.movedFeedbackContent(count:), after: 2, categoryID: ASIST_SYSTEM, interruption: .passive, itemID: nil)` |
| `ASIST_EOD_REVIEW` (fg) | — | `router.request(.endOfDay)` |
| `UNNotificationDismissActionIdentifier` | — | `store.recordDismiss(id, at: now)`; **chain continues** (dismiss ≠ done) |
| `UNNotificationDefaultActionIdentifier` (body tap) | — | item id → `router.request(.openItem(id))`; `asist.brief.*` → `settings.briefingTapSpeaks ? .readAgenda : .today`; `asist.eod.*` → `.endOfDay`; `asist.backup` → `.dataSettings`; `asist.x.moved`, `asist.sentinel.h`, `asist.sign.*` → `.today` (banner visible there) |

The budget sentinel carries the dropped item's `iid`, so its actions act on that item like any item notification.

### 6.4 Nag chain algorithm (WP3 — normative)

Definitions (all with the injected calendar `C`, `S = input.settings`, `N = input.now`):
- `iso(d)` ISO weekday; `workday(d) = S.workdays.contains(iso(d))` (never empty after decoding, §3.2.9).
- `mod(t)` minute of day. Quiet window `[qs, qe)` with wrap-around when `qs > qe` (default 22:30–07:30): `inQuiet(t) = qs > qe ? (mod ≥ qs || mod < qe) : (mod ≥ qs && mod < qe)`; `quiet(t, c) = inQuiet(t) && !(c && S.criticalIgnoresQuietHours)`.
- `quietExit(t)`: next instant ≥ t with minute-of-day == qe (same day if `mod(t) < qe`, else next day).
- `muted(t) = S.isMuted(t, now: N)` (mute active and `t < S.muteUntil`).
- `inWork(t) = workday(t) && S.workStart ≤ mod(t) < S.workEnd`.
- `dayStart(day)` = `S.workStart` on workdays, `S.offDayStart` otherwise; **for `.takip`** `S.followUpAskTime` and only workdays are eligible.
- `nextDayStart(t)` = `dayStart` of the first eligible day strictly after `t`'s day, searching **at most 14 days**; if none is found every day counts as eligible (cannot happen after §3.2.9 clamps; guards the watchdog, 05a #8).

`chain(anchor A, profile P, kind K, isCritical c)`:
```
if K == .etkinlik: return [A]
result = [A]                                  // k = 0, exactly at A — never shifted (explicit time or snooze)
count[day(A)] = 1; last = A
emit(raw) -> Bool:
    t = raw
    if muted(t): t = ceilToMinute(S.muteUntil)                         // muted nags collapse into one
    if quiet(t, c): t = quietExit(t)
    guard = 0
    while (count[day(t)] >= P.dailyCap || (K == .takip && !workday(t))) && guard < 30:
        t = nextDayStart(t); guard += 1                                // daily cap / takip weekdays
        if quiet(t, c): t = quietExit(t)                               // user quiet hours may cover day start
    if t <= last: return false                                         // merged
    result.append(t); count[day(t)] += 1; last = t; return true
for off in P.followUpOffsetsMinutes: emit(A + off min)                 // phase 1
while result.count < 400 && last < A + 14 days:                        // phase 2
    if inWork(last), let s = P.repeatMinutesWorkHours:
        cand = last + s min
        if !inWork(cand) && P.repeatMinutesOffHours == nil: cand = nextDayStart(last)
    else if !inWork(last), let s = P.repeatMinutesOffHours:
        cand = last + s min
    else:
        cand = nextDayStart(last)
    if !emit(cand) && !emit(nextDayStart(last)): break                 // progress guaranteed / terminates
```
Implementations MAY stop generating once `plan()` has what it needs, provided the produced prefix is identical to the full chain.

Worked examples (tests; `sun` = Sun 2026-09-27; S defaults; no mute):
- **Nazik**, A = Tue 09-29 15:00 → 15:00, 15:10, 15:30, 16:30, Wed 08:30, 10:30, 12:30, 14:30, 16:30, Thu 08:30 … Fri 16:30, Sat 09:00, Sun 09:00, Mon 08:30 … (16:30 + 2 h leaves work hours and off-hours repeat is nil → next day start).
- **Israrcı**, A = Tue 15:00 → 15:00, 15:05, 15:15, 15:30, 16:00, 17:00, Wed 08:30, 09:30 … 17:30 (10 = cap), Thu 08:30 … (18:00 is not inside work hours → no evening nags, 05b C4).
- **Nazik**, A = Tue 20:30 → 20:30, 20:40, 21:00, 22:00, Wed 08:30, 10:30, 12:30, 14:30, 16:30, Thu 08:30 …
- **Bırakmaz**, A = Tue 23:00 (critical, criticalIgnoresQuietHours = false) → 23:00, Wed 07:30 (23:03 quiet → exit; 23:06/23:10/23:15 merged), 07:45, 08:00, 08:15, 08:30, 08:45 … 14:45 (30 = cap), Thu 08:30 …
- **Takip**, A = Fri 10-02 16:00 → 16:00, Mon 10-05 16:00, Tue 16:00 …
- **Etkinlik**, A = Thu 10-01 14:00 → [14:00].
- **Mute**: Nazik, A = Tue 10:00, N = Tue 10:05, muteUntil = Tue 11:30 → 10:00, 11:30 (10:10 and 10:30 collapse into 11:30; 11:30 itself merges), 13:30, 15:30, 17:30, Wed 08:30 …

`plan(input)` steps:
1. **Per-item candidates** — for every item with `isNotifiable`, `anchorDate != nil` and (`placeID == nil || dueDate != nil`): `A = anchorDate`, `K = item.profileKind(S)`, `P = S.nagProfiles[K]`, `c = priority == .critical`, `full = chain(A, P, K, c)`. Recurring items: `N1 = RecurrenceEngine.nextOccurrence(of: rule, time: clock(dueDate), after: dueDate, anchor: dueDate)`; drop chain elements `≥ N1`.
   - a) **First alert**: k = 0 if `A > N + 10 s` → `.first`.
   - b) **Follow-ups**: the first `P.maxPendingFollowUps` chain elements with k ≥ 1 and `> N + 10 s` → `.nag`.
   - c) **Day-tail (05a #2)**: if `K != .etkinlik` and (a) or (b) kept something: let `D` = day of the last kept element; for each of the **next 3 distinct calendar days after `D` that contain chain elements**, the first element of that day (k ≥ 1, `> N + 10 s`) → `.nag`.
   - d) **Pre-alerts**: `dueDate != nil`; for each `L` in `leadTimesMinutes`: `t = dueDate − L min`, `t > N + 60 s` → `.preAlert`, id `preAlert(id, minutes: L)`, category `ASIST_PRE`.
   - e) **Recurrence (D27)**: carrier rules `Rc` for interval 1 — daily → `[.daily(h, m)]`; weekly with weekdays → `[.weekly(foundationWeekday(w), h, m) for w]`; monthly with `monthDay` 1…28 → `[.monthly(monthDay, h, m)]`; otherwise `[]` (h:m = clock time of `dueDate`). `Fc` = earliest next fire strictly after `N` over `Rc` (`Calendar.nextDate(after:matching:matchingPolicy: .nextTime)`). If `Rc` is non-empty and (`Fc == N1` or (`snoozedUntil == nil` and `Fc == dueDate`)) → one `.carrier` per rule (suffix `d` / `w<fw>` / `m`, fireDate = that rule's next fire, content `recurrenceCarrierContent`), and when `Fc == dueDate` the one-shot (a) is removed (the carrier delivers it). Otherwise → `.occurrence` k0s for `RecurrenceEngine.occurrences(of:time:after: dueDate, anchor: dueDate, count: 7, calendar:)`: those `≤ N + 14 d`, plus the first one beyond 14 days (tier 4).
   - f) **Long-tail (05a #2, 05b C3)**: non-recurring, `K != .etkinlik`, `priority ≥ .high`: minute `m` = `S.workStart` (`.takip`: `S.followUpAskTime`); `F` = first instant `> N` at `m`; candidate iff **`F > A`**. Keep at most **5** by (priority desc, A asc, id asc); rank `r` (0…4) → rule `.daily` at `m + 2·r` minutes, fireDate `F + 2·r min`. Then drop that item's `.nag` candidates on days `≥ day(F)` whose minute of day is within ±15 of `m + 2·r` (the repeat covers them).
2. **Signing clamp (05b A1)**: if `signingExpiry = E` is set, drop `.nag` candidates with `fireDate > E − 5 min`. k0s, pre-alerts, occurrences, carriers and long-tails stay (they are the only safety net after a re-sign that is never followed by an app launch).
3. **Attributes** (03 §3.2): normal & low → `.active` 0.5; high → `.timeSensitive` 0.8; critical → `.timeSensitive` 1.0; nags of items overdue at their fire date relevance 1.0; carriers/long-tails/occurrences/pre-alerts follow their item's priority; briefing/EOD `.active` 0.6; backup `.passive` 0.3 no sound; signing `.timeSensitive` 0.9; sentinels `.active` 0.7. `!allowTimeSensitive` → every `.timeSensitive` becomes `.active` (05b B7). **Mute (D32)**: every one-shot with `muted(fireDate)` except critical items' `.first` and `.signing` → `playsSound = false`, `.passive`. **Sounds (D37)**: high → `"asist-onemli.wav"`, critical → `"asist-kritik.wav"` for `.first`, `.occurrence`, `.carrier`, `.longTail` and for `.nag` with `k % 3 == 0`; everything else `soundName = nil`.
4. **Reserved date candidates** (never compete with items): next **5** briefings at `S.briefingTime` (`briefingEnabled`; workdays only when `briefingWorkdaysOnly`; `> N + 60 s`; within 14 days); next 1 end-of-day at `S.endOfDayTime` (`endOfDayEnabled`, workday filter); backup weekly repeat (`.weekly(weekday: foundationWeekday(fromISO: S.backupReminderWeekday), …)`, when `backupReminderEnabled`); signing: every `SigningExpiryPlanner.warningDates(expiration: E, now: N, calendar: C)` + one expiry notice at `ceilToMinute(E + 60 s)` when `> N + 60 s` (only when `E` is set).
5. **Rate limiter (05b C2)** over one-shot sounded notifications: *fixed* = every sounded `.once` candidate that is not `.nag` (k0s, pre-alerts, occurrences, reserved) — never moved or dropped; *movable* = sounded `.nag`, processed in (priority desc, fireDate asc, id asc). A movable nag is accepted at the earliest `t ∈ {fireDate, +1 min, …, +15 min}` such that `|t − a| ≥ 3 min` for every accepted/fixed sounded `a`, and every 60-minute window `[s, s + 60 min)` containing `t` holds ≤ 8 sounded notifications including `t` (check `s ∈ {t} ∪ {a : t − 60 min < a ≤ t}`); a shifted `t` must not be `quiet(t, c)` nor pass the signing clamp. No valid `t` → dropped (`rateLimitedCount`, not `droppedCount`, no sentinel). Silent (muted) and repeating notifications neither count nor move.
6. **Tiers and budget** (lower = kept first): 0 = `.first`/`.preAlert`/`.occurrence` with fireDate ≤ N + 48 h, and `.longTail`; 1 = `.nag` k 1…4 ≤ N + 48 h, and `.carrier`; 2 = `.first`/`.preAlert`/`.occurrence` in (48 h, 14 d]; 3 = other `.nag` (incl. day-tail) ≤ 14 d; 4 = `.first`/`.preAlert`/`.occurrence` in (14 d, 400 d] (farther: not planned). Sort `(tier, fireDate, id)`; keep `input.itemBudget`; `droppedCount` / `earliestDroppedDate` from dropped candidates of tiers 0…3 only.
7. **Item content** (after budget, so "next" refers to what is really pending): per item, sort its kept notifications by fireDate (repeating ones by their first fire); `nextFireDate` = the next kept one (nil if none), `isLastOfDay` = next exists on a later calendar day. `.first`/`.nag`/`.occurrence` → `itemContent` (waiting → `followUpContent`, event `.first` → `eventContent`); `.preAlert` → `preAlertContent`; `.longTail` → `longTailContent`; `.carrier` → `recurrenceCarrierContent`.
8. **Reserved content and sentinels**: briefing → `AgendaBuilder.briefing(at:)` (nil → not planned), EOD → `AgendaBuilder.endOfDay(at:)`, backup → `backupContent`, signing → `signingContent` / `signingExpiredContent`. **Budget sentinel (05b B5)**: if `droppedCount > 0` and `earliestDroppedDate > N + 60 s`: a copy of that dropped notification (title/subtitle and body line 1 computed as in step 7; body line 2 replaced by `budgetSentinelLine(extraCount: droppedCount − 1)`) with id `asist.sentinel`, kind `.sentinel`, the same `iid`/`k`/category/thread, `.active` 0.7 with sound. **Horizon sentinel (05a #23, 05b B3)**: when at least one open notifiable item has an anchor: `H` = latest fireDate among kept `.once` item notifications; `t = H == nil ? dayStart(N + 13 d) : min(H + 60 min, dayStart(N + 13 d))`; `quiet(t)` → `quietExit(t)`; planned when `t > N + 60 s` with `horizonSentinelContent(openCount:)` (open notifiable items with an anchor).
9. **Badge**: every `.once` gets `badge = badgeCount(items, at: fireDate)`; repeating ones `nil`; `badgeNow = badgeCount(items, at: N)`; `BadgeMode.off` → all badges 0 and `badgeNow` 0.
10. **Output** sorted `(tier, fireDate, id)` (reserved notifications carry tier 0); fingerprints computed by the initializer.

`immediateRequests(for:input:limit:)` = steps 1–3 and 7 for that single item (no reserved, no rate limiter, no budget), `.once` only, sorted by fireDate, first `limit`.

Required unit tests (WP3, `NagPlannerTests`):
- the worked examples above (incl. Etkinlik and Mute); `workdays == []` input is impossible after decoding, and `chain` with a hand-built `AppSettings` whose `workdays` is `[]` still terminates;
- **continuity (05a #2)**: Israrcı, A = Tue 15:00, N = Sun 10:00, no further reconcile → kept k0 Tue 15:00, 8 follow-ups (… Wed 10:30), day-tail Thu 08:30, Fri 08:30, Sat 09:00; briefings Mon–Fri 08:00 (Wed–Fri bodies list the item as geciken); horizon sentinel Sat 10:00;
- high item, A = Tue 15:00, N = Tue 10:00 → long-tail present (F = Wed 08:30 > A) and the Wed 08:30 nag is dropped by the ±15 dedupe; normal item → no long-tail; 6 high/critical overdue items → 5 long-tails at 08:30, 08:32 … 08:38;
- recurrence: daily 09:00 open item, N = Tue 10:00 (rolled over to Tue 09:00) → carrier `r.d` present and no `.occurrence`; completed early at 08:00 (dueDate = Wed 09:00) → 7 one-shot occurrences, no carrier; weekly Mon+Thu → carriers `r.w2`, `r.w5`; monthly day 31 → occurrences;
- tiers/budget: > 50 candidates → tier order, `droppedCount` excludes tier 4 and rate-limited; budget sentinel is a copy of the earliest dropped notification with the extra body line and the dropped item's `iid`;
- rate limiter: three high items with A = Tue 15:00 → k1 at 15:05, 15:08, 15:11; no 60-minute window holds more than 8 sounded; k0s never move;
- signing clamp: E = N + 3 h → no `.nag` after E − 5 min, k0s and long-tails kept, 3 warnings + expiry notice present (E within 48 h);
- mute: first alerts inside the window are silent (`playsSound == false`, `.passive`) except critical; nags collapse to `muteUntil`;
- `allowTimeSensitive == false` → no `.timeSensitive` in the output; sounds per D37;
- k-stability when `N` advances past k = 0…2 (remaining IDs unchanged); snooze restarts at k = 0; identical input → identical fingerprints; quiet wrap-around with `qs < qe`; takip skips weekends; events never produce `.nag`, `.longTail` or day-tail;
- `immediateRequests` equals the first `limit` `.once` item notifications of a single-item `plan` (ids + fingerprints).

### 6.5 Budget summary

| Slot group | Max |
|---|---|
| Briefings (next 5, workdays) | 5 |
| End-of-day (next 1) | 1 |
| Weekly backup reminder (repeating) | 1 |
| Signing (3 warnings + expiry notice) | 4 |
| Budget sentinel | 1 |
| Horizon sentinel | 1 |
| Spare (test / moved feedback, unmanaged) | 1 |
| Items (chains, day-tails, pre-alerts, occurrences, carriers, long-tails) | 64 − 14 = **50** |
| Location triggers | v1.2 (will be subtracted from item slots) |

---

## 7. Configuration: Info.plist, entitlements, project.yml, CI

### 7.1 Info.plist (generated by XcodeGen from §7.3)

App keys and reasons: `CFBundleDisplayName/CFBundleName = Asist`; `CFBundleDevelopmentRegion = tr`; `CFBundleLocalizations = [tr]`; version keys = `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` (CI overrides `CURRENT_PROJECT_VERSION` with the run number → monotonic `CFBundleVersion`, D35); `LSRequiresIPhoneOS`; `UILaunchScreen = {}`; `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes = false`; portrait only; `CFBundleURLTypes` scheme `asist`; `UIBackgroundModes = [fetch]`; `BGTaskSchedulerPermittedIdentifiers = [com.gokhanbudak.asist.refresh]`; `NSMicrophoneUsageDescription`; `NSSpeechRecognitionUsageDescription`; `UIFileSharingEnabled = true` + `LSSupportsOpeningDocumentsInPlace = true` (Documents/Yedekler visible in Files); `LSApplicationQueriesSchemes = [shortcuts]`.
**Not present (by decision):** `INAlternativeAppNames` (05b F5), `NSLocationWhenInUseUsageDescription` (location is v1.2), `NSAlarmKitUsageDescription`, `NSSupportsLiveActivities`, calendar/reminders/contacts/camera/Face ID keys, `UIBackgroundModes: audio`, `UIDesignRequiresCompatibility`.

### 7.2 Entitlements and graceful degradation

v1.0 has **no entitlements file** (no App Group, no extension). Nothing depends on the bundle id or a group id at run time (01c §1.9 r6). Free-signing facts that still matter: 7-day profile (D17 warnings), 1 App ID per install, and time-sensitive delivery unavailable → planner downgrades to `.active` (05b B7). The App Group returns in v1.1 with the widget (Appendix B.4).

| Entitlement | v1.0 | Note |
|---|---|---|
| App Group | ✗ | v1.1 (widget snapshot only; the app keeps working without it) |
| time-sensitive, Siri, push, iCloud, AlarmKit, keychain-access-groups | ✗ | never added (free Apple ID) |

### 7.3 `project.yml` — final for v1.0 (WP0 writes verbatim)

```yaml
# Asist — XcodeGen spec (single source of truth). CI: `xcodegen generate --spec project.yml`.
# Asist.xcodeproj and Generated/ are regenerated on every run and are NOT committed.
# v1.0 "Çekirdek": one application target, no extensions, no entitlements (04 §7.3).
name: Asist

options:
  minimumXcodeGenVersion: "2.46.0"
  bundleIdPrefix: com.gokhanbudak.asist
  developmentLanguage: tr
  useBaseInternationalization: false
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    TARGETED_DEVICE_FAMILY: "1"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: NO
    SUPPORTS_MACCATALYST: NO
    SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
    SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""

packages:
  AsistCore:
    path: Packages/AsistCore

targets:
  Asist:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: App
    settings:
      base:
        PRODUCT_NAME: Asist
        PRODUCT_BUNDLE_IDENTIFIER: com.gokhanbudak.asist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ASIST_APP"
        APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING: YES
    info:
      path: Generated/Asist-Info.plist
      properties:
        CFBundleDisplayName: Asist
        CFBundleName: Asist
        CFBundleDevelopmentRegion: tr
        CFBundleLocalizations: [tr]
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIApplicationSupportsIndirectInputEvents: true
        CFBundleURLTypes:
          - CFBundleURLName: com.gokhanbudak.asist
            CFBundleTypeRole: Editor
            CFBundleURLSchemes: [asist]
        UIBackgroundModes:
          - fetch
        BGTaskSchedulerPermittedIdentifiers:
          - com.gokhanbudak.asist.refresh
        UIFileSharingEnabled: true
        LSSupportsOpeningDocumentsInPlace: true
        LSApplicationQueriesSchemes: [shortcuts]
        NSMicrophoneUsageDescription: "Asist, sesli komutlarını dinleyip hatırlatma, görev ve nota dönüştürmek için mikrofonu kullanır. Ses kaydı saklanmaz."
        NSSpeechRecognitionUsageDescription: "Asist, söylediklerini yazıya çevirmek için konuşma tanımayı kullanır."
    dependencies:
      - package: AsistCore
    scheme:
      language: tr
      region: TR
```

Notes: every version value is quoted; `YES/NO` for build settings, `true/false` inside Info.plist properties; `App` MUST exist with ≥ 1 `.swift`; `App/Resources/Sounds/*.wav` are picked up as resources automatically (copied flat into `Asist.app/`); `Package.swift` product name MUST be exactly `AsistCore`; `SWIFT_ACTIVE_COMPILATION_CONDITIONS` keeps `$(inherited)` so Debug keeps `DEBUG`. No `entitlements:` key (XcodeGen then generates none).

### 7.4 CI — final

`.github/workflows/ci.yml` = 01c §2.6 **verbatim** (jobs `core-tests` on `ubuntu-24.04` + `container: swift:6.3-noble` running `swift build --build-tests` then `swift test --skip-build --parallel` in `Packages/AsistCore`; `ios` on `macos-26`: `select-xcode.sh` (newest stable 26.x) → `install-xcodegen.sh` (2.46.0 + SHA-256) → `xcodegen generate` (+ "settings found" guard) → `xcodebuild build -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO … CURRENT_PROJECT_VERSION="${{ github.run_number }}"` piped through `xcbeautify --renderer github-actions` with `shell: bash` (pipefail) → `error-summary.sh` on failure → `package-ipa.sh` (**§7.5 v1.0 variant**) → artifacts `Asist.ipa` (ad-hoc signed) and `Asist-imzasiz.ipa`, both `archive: false`; logs and generated project always uploaded). Both jobs run in parallel (a failing corpus test must not hide iOS compile errors). Scripts `select-xcode.sh`, `install-xcodegen.sh`, `error-summary.sh` = 01c §2.2/§2.3/§2.7 verbatim. Xcode 27 is not used (`XCODE_MAJOR: "26"`). The upload step title "Asist.ipa (entitlement gömülü, ad-hoc)" may stay as is (cosmetic).

App Shortcuts fallbacks (05a #30): §3.7. Release gate for WP merges: `core-tests` green (incl. the corpus gate §3.4.6) **and** `ios` green with **0 errors**; warnings reviewed (deprecations of iOS 26/27 APIs such as `openAppWhenRun` are acceptable); the job summary shows "App Intents metadata: evet".

### 7.5 `Scripts/ci/package-ipa.sh` — v1.0 (WP0 writes verbatim; replaces 01c §2.5)

```bash
#!/usr/bin/env bash
# v1.0 (single target, no extension, no entitlements) — 04 §7.5.
# Asist.app -> two IPAs:
#   Asist.ipa          : ad-hoc signed (no entitlements in v1.0); Sideloadly re-signs it.
#   Asist-imzasiz.ipa  : completely unsigned fallback.
# Usage: package-ipa.sh <.../Release-iphoneos/Asist.app> <output dir>
set -euo pipefail

APP_SRC="$1"
OUT="$2"
APP_NAME="$(basename "$APP_SRC")"                       # Asist.app
EXE_NAME="${APP_NAME%.app}"                             # Asist

fail() { echo "::error::$*"; exit 1; }

# --- Pre-validation ---------------------------------------------------------
[ -d "$APP_SRC" ]                 || fail "Uygulama paketi yok: $APP_SRC"
[ -f "$APP_SRC/$EXE_NAME" ]       || fail "Çalıştırılabilir dosya yok: $APP_SRC/$EXE_NAME"
[ -f "$APP_SRC/Assets.car" ]      || fail "Derlenmiş asset kataloğu (Assets.car) yok"
if [ -d "$APP_SRC/PlugIns" ]; then
  echo "::warning::v1.0'da uzantı beklenmiyordu: $APP_SRC/PlugIns"
fi

PB=/usr/libexec/PlistBuddy
APP_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/Info.plist")
APP_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/Info.plist")
SHORT=$($PB -c 'Print :CFBundleShortVersionString' "$APP_SRC/Info.plist")
ARCHS="$(lipo -archs "$APP_SRC/$EXE_NAME")"
[[ "$ARCHS" == *arm64* ]] || fail "arm64 dilimi yok (bulunan: $ARCHS)"

# App Intents metadata (05a #30): if it is missing, Siri/Shortcuts silently lose Asist's actions.
# Reported as an error annotation but does not stop packaging.
META="$APP_SRC/Metadata.appintents/extract.actionsdata"
INTENTS_OK="evet"
if [ -f "$META" ]; then
  for NAME in KaydetIntent DinleIntent BugunIntent GecikenlerIntent; do
    if ! grep -q "$NAME" "$META"; then
      echo "::error::App Intents metadata içinde $NAME yok"
      INTENTS_OK="hayır"
    fi
  done
else
  echo "::error::App Intents metadata yok: $META"
  INTENTS_OK="hayır"
fi

# Notification sounds (D37): a missing file only falls back to the default sound.
for SND in asist-onemli.wav asist-kritik.wav; do
  if [ ! -f "$APP_SRC/$SND" ]; then
    echo "::warning::Bildirim sesi pakette yok: $SND"
  fi
done

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"

make_ipa() {  # $1 = staging dir (contains Payload/), $2 = ipa path
  rm -f "$2"
  (cd "$1" && zip -qry -X "$2" Payload)
  # `unzip | grep -q` under pipefail can fail with SIGPIPE (141) -> write the listing to a file first.
  unzip -Z1 "$2" > "$WORK/liste.txt"
  grep -q "^Payload/$APP_NAME/$EXE_NAME\$" "$WORK/liste.txt" || fail "IPA içinde çalıştırılabilir yok: $2"
}

# --- 1) Fallback: completely unsigned ----------------------------------------
mkdir -p "$WORK/plain/Payload"
ditto "$APP_SRC" "$WORK/plain/Payload/$APP_NAME"
make_ipa "$WORK/plain" "$OUT/Asist-imzasiz.ipa"

# --- 2) Main: ad-hoc signature (v1.0 embeds no entitlements) -----------------
mkdir -p "$WORK/signed/Payload"
ditto "$APP_SRC" "$WORK/signed/Payload/$APP_NAME"
codesign --force --sign - --timestamp=none "$WORK/signed/Payload/$APP_NAME"
make_ipa "$WORK/signed" "$OUT/Asist.ipa"

# --- Summary -------------------------------------------------------------------
{
  echo "### IPA"
  echo "| Dosya | Boyut | SHA-256 |"
  echo "|---|---|---|"
  for F in "$OUT/Asist.ipa" "$OUT/Asist-imzasiz.ipa"; do
    echo "| $(basename "$F") | $(du -h "$F" | cut -f1) | \`$(shasum -a 256 "$F" | cut -c1-16)…\` |"
  done
  echo ""
  echo "- Bundle ID: \`$APP_ID\`"
  echo "- Sürüm: $SHORT ($APP_VER)"
  echo "- App Intents metadata: $INTENTS_OK"
} >> "$GITHUB_STEP_SUMMARY"
ls -la "$OUT"
```

WP0 runs `bash -n Scripts/ci/package-ipa.sh` before committing (Git Bash on Windows is enough for the syntax check).

### 7.6 `Tools/make_sounds.py` — exact (WP0; run once on Windows, commit the WAVs)

```python
#!/usr/bin/env python3
"""Asist notification sounds (04 §7.6, D37). Run locally: python Tools/make_sounds.py — commit the two WAVs."""
import math
import os
import struct
import wave

RATE = 44100
OUT = os.environ.get("ASIST_SOUNDS_OUT") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Sounds")


def tone(freq, seconds, volume=0.8):
    n = int(RATE * seconds)
    fade = int(RATE * 0.01)
    frames = bytearray()
    for i in range(n):
        env = min(1.0, i / fade, (n - i) / fade)
        sample = int(32767 * volume * env * math.sin(2 * math.pi * freq * i / RATE))
        frames += struct.pack("<h", sample)
    return bytes(frames)


def silence(seconds):
    return b"\x00\x00" * int(RATE * seconds)


def write(name, pattern, total_seconds):
    target = int(RATE * total_seconds) * 2
    data = b""
    while len(data) < target:
        for freq, dur in pattern:
            data += tone(freq, dur) if freq > 0 else silence(dur)
    data = data[:target]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(path, round(len(data) / 2 / RATE, 1), "s")


write("asist-onemli.wav", [(880, 0.18), (0, 0.06), (1320, 0.18), (0, 0.60)], 6)
write("asist-kritik.wav", [(988, 0.15), (0, 0.10), (1480, 0.15), (0, 0.10)], 12)
```
Verified on 2026-09-27 with Python 3.14 on Windows: produces 16-bit mono 44.1 kHz PCM WAVs of 6.0 s and 12.0 s (UNNotificationSound accepts linear-PCM WAV < 30 s).

---

## 8. Work packages (parallel implementation plan, v1.0)

Rules for every WP: touch **only** files you own (§2); never edit a `// FILE:` contract file (request a change from WP0); code against §3 signatures even if the implementation behind them is still a stub; add tests for everything in AsistCore you own; read §4 and §9 before pushing. Merge order is free because WP0 stubs make every combination compile; the orchestrator integrates and runs CI after each merge. Nothing from Appendix B is created in v1.0.

| WP | Name | Owns (files) | Depends on (APIs) | MUST NOT touch | Primary references |
|---|---|---|---|---|---|
| **WP0** | Contracts & skeleton (orchestrator, first) | root files, CI, scripts (incl. §7.5 `package-ipa.sh`), icon + `Tools/make_sounds.py` + the two WAVs, `Package.swift`, every `// FILE:` block in §3/§5.4 (`AsistApp`, `AppDelegate`, `AppEnvironment`, `NotificationCoordinator`, `NotificationCategories`, `BackgroundRefresh`, `AppRouter`, `ToastCenter`, all intents + `AppShortcuts.strings`, model/util/catalog files), a compiling stub for every `// API:` type (minimal behaviour) and for every view named in §5 (`Text("…")` bodies), `App/Resources/Assets.xcassets/*` | — | — | this doc, 01c |
| **WP1** | Turkish parser, formatter, recurrence | `Parser/*` (except `ParserTypes.swift`, `ParserSettings+App.swift`), `Text/TurkishDateFormatter.swift`, `Planning/RecurrenceEngine.swift`, tests Corpus/Normalizer/Number/DateResolver/Formatter/RecurrenceEngine/ParserProperty; the corpus expectation edits allowed by §3.4.6 | Model, `TurkishText`, `AsistCalendar` | app target, other AsistCore dirs | 02 (all), §3.4.6, both corpus files |
| **WP2** | Agenda, copy, speech text, matching, capture factory | `Agenda/*`, `Matching/FuzzyMatcher.swift`, `Capture/ItemFactory.swift`, `Text/TurkishSpeech.swift`, `Model/ChecklistTemplates.swift`, tests AgendaBuilder/TurkishSpeech/FuzzyMatcher/ItemFactory (+ NotificationCopy cases) | Model, formatter API, `NagPlanner.tomorrowMorning/thisEvening` API, `RecurrenceEngine` API | Parser internals, Planning/NagPlanner | 03 §3.2, §3.9–3.10, §5.8–5.12, §7.12 as amended by §5.5, Ek A; 02 §10.5–10.6, §13; §3.5.4–3.5.6 |
| **WP3** | Nag planner | `Planning/NagPlanner.swift`, `Planning/NagChain.swift`, `Planning/PlanPostPass.swift`, `NagPlannerTests.swift` | Model, `NotificationCatalog`, `PlannedNotification`, `NotificationCopy` API, `AgendaBuilder.briefing/endOfDay` API, `RecurrenceEngine` API, `SigningExpiryPlanner` | everything else | §6 (normative), 01a §5, 03 §3.4–3.13 |
| **WP4** | Persistence | `App/Store/*`, `ModelCodingTests.swift` | Model, `AgendaBuilder.movedToTomorrow/endOfDayCandidates/openItemsText`, `RecurrenceEngine` | Model files (request changes via WP0) | §3.6.4, 03 §9 r25–27, 05a #3/#5/#6/#10/#21/#22/#24 |
| **WP5** | Notifications platform | `App/Notifications/*` (except `NotificationCoordinator.swift`, `NotificationCategories.swift`, `BackgroundRefresh.swift` which WP0 writes verbatim — WP5 reviews them) | DataStore API, NagPlanner, NotificationCopy, AppRouter, SigningMonitor API | UI, voice | 01a §2–§5, §7; §3.6.5–3.6.6, §6 |
| **WP6** | Voice | `App/Voice/*` | CaptureService API (`handleTranscript`, `saveInterruptedTranscript`, `contextualStrings`), AppRouter, ToastCenter, AppSettings | UI files | 01b §1–§3; §3.6.7 |
| **WP7** | Capture services | `App/Services/CaptureDraft.swift`, `CaptureService.swift`, `CommandExecutor.swift` | ItemFactory, AgendaBuilder, FuzzyMatcher, TurkishSpeech, DataStore, ReminderEngine.reconcile, VoiceCoordinator.speak/shouldSpeakConfirmation, ToastCenter | UI, notifications | 02 §10, 03 §4.5, §5.5, §5.9–5.10; §3.6.8 (voice complete/cancel/snooze last — may slip to v1.1) |
| **WP8** | Platform: signing + intents verification | `App/Platform/SigningMonitor.swift`, DeepLink tests; device verification of the §3.7 intents and Siri phrases (the intent files themselves are WP0 exact) | AppEnvironment, ProvisioningProfileReader | UI screens | 01b §4, 01c §3–§4; §3.6.11, §3.7 |
| **WP9** | UI shell, Today, capture UI, components | `App/UI/Root/*`, `App/UI/Today/*`, `App/UI/Capture/*`, `App/UI/Components/*` (incl. `MuteMenu.swift`) | all observable objects, CaptureService, CommandExecutor, AgendaBuilder, TurkishDateFormatter, NagPlanner.muteUntilWorkEnd | Lists/Detail/Projects/Settings screens | 03 §4.1–4.6, §5.3, §7; §5 |
| **WP10** | Lists, detail, projects, end of day | `App/UI/Lists/*`, `App/UI/Detail/*`, `App/UI/Projects/*`, `App/UI/EndOfDay/*` | components (§5.3), DataStore, ChecklistTemplates, VoiceCoordinator (Sesle ertele) | Root/Today/Settings | 03 §4.7–4.10, §6.3, Ek A |
| **WP11** | Settings, onboarding, guides, diagnostics, user docs | `App/UI/Settings/*` (incl. `RecentlyDeletedView.swift`), `App/UI/Onboarding/*`, `docs/KURULUM.md`, `docs/KULLANIM.md` | components, PermissionCenter, SigningMonitor, ReminderEngine, NotificationScheduler, NagPlanner.chain | Root/Today/Lists | 03 §4.11–4.13, §5.1–5.2, §9; 01c §3; §3.7 recipes, §5.2 |

Suggested integration order (to see green CI early): WP0 → (WP4, WP1, WP3, WP2 in parallel) → WP5 → WP7 → WP6 → WP8 → WP9 → WP10 → WP11. Each merge must keep CI green; if a WP cannot compile against a stub's behaviour, it adds `// TODO(WPn)` and keeps the stub call.

v1.1+ work packages (Appendix B): WP12 widgets + Control (B.4), WP13 Smart Mode (B.2), WP14 location reminders (B.3, v1.2).

---

## 9. Compile-hazards checklist (read before every push)

**Project / build**
1. No `SWIFT_DEFAULT_ACTOR_ISOLATION`, no upcoming-feature flags (incl. `MemberImportVisibility`), no `SWIFT_REFLECTION_METADATA_LEVEL`, no warnings-as-errors (§4.1 r1).
2. Every source directory in `project.yml` exists and contains ≥ 1 `.swift` file; scripts committed with LF (`.gitattributes`); WAV/PNG committed as binary.
3. One `@main`: `AsistApp` (v1.0 has one target; v1.1 adds `AsistWidgetBundle`, Appendix B.4).
4. `AppShortcutsProvider` and **all** intents live in `App/Intents/` (v1.0). No `Shared/`, no `#if ASIST_WIDGET` code in v1.0.
5. AsistCore imports only Foundation; Darwin-only APIs (`FileManager.containerURL`, `Bundle` Info.plist lookups) inside `#if canImport(Darwin)`; no `os`, no `Combine`, no `NSDataDetector`, no `DateFormatter` for Turkish names, no `String(format:)`, no `/regex/` literals (use `#/…/#` or scanning).
6. Tests never read `Date()`, `TimeZone.current`, `Locale.current`; use `TestSupport.calendar` (Europe/Istanbul, falls back to UTC+3) and the corpora via `#filePath` (§3.3.4).

**Swift / concurrency**
7. `@Observable` needs `import Observation`; `let` properties get no `@ObservationIgnored`; mutable non-UI state (`Task` handles, closures, caches) **must** be `@ObservationIgnored`; no `lazy var` and no property wrappers inside `@Observable` classes.
8. `@MainActor` class + system delegate protocol → `nonisolated func` delegate methods, value copies, `Task { @MainActor [weak self] in … }`; never `override init()` in `@MainActor` NSObject subclasses (create managers in a `start()`).
9. `UNUserNotificationCenterDelegate`: implement only the completion-handler variants with `@escaping @Sendable` spelling; never both async and completion variants of one requirement; call `completionHandler()` on every path.
10. Static stored properties of `@MainActor` classes (`static let shared`) are main-actor isolated: access from non-isolated code only inside `Task { @MainActor in … }` (or `MainActor.assumeIsolated` in a UIKit expiration handler, §3.6.2). `Identifiable` conformance of a `@MainActor` class uses `nonisolated let id: UUID` (see `CaptureDraft`).
11. Closures handed to AVFoundation/Speech/KVO are built in `nonisolated static` factories; nested `Task { @MainActor [weak owner] in }` has its own capture list.
12. `CheckedContinuation` resumed exactly once (single `finish` funnel).
13. `BGTaskScheduler.register` exactly once per id, from `didFinishLaunching`; never combine with SwiftUI `.backgroundTask`; `submit` only (not the iOS 27 `submitTaskRequest`); `setTaskCompleted` only through `BGCompletion` (05a #16).

**SwiftUI (iOS 17 deployment)**
14. `onChange(of:initial:_:)` two-parameter closure `{ old, new in }` (one-parameter form is deprecated in 17).
15. `@Bindable var x = x` inside `body` for bindings to `@Observable` objects from `@Environment(Type.self)`; `.environment(object)` (not `.environmentObject`).
16. `NavigationStack(path:)` with `[Route]` + `.navigationDestination(for: Route.self)`; one destination modifier per stack (placed on the root view of the stack).
17. `.sheet(item:)` needs `Identifiable` (`SheetRoute.id`); present one sheet at a time through `router.sheet`; `.fullScreenCover(isPresented: $router.showOnboarding)`.
18. Ternaries mixing styles: write `cond ? Color.red : Color.secondary` (never `.red : .secondary` into `foregroundStyle`).
19. `TabView` uses `.tabItem { Label(…) }` + `.tag(AppTab.x)` (the `Tab` API is iOS 18+).
20. `ContentUnavailableView`, `LabeledContent`, `ShareLink`, `.fileImporter`, `.sensoryFeedback`, `TimelineView(.everyMinute)`, `.presentationDetents`, `SiriTipView`, `ShortcutsLink` are iOS ≤ 17 → no `#available` needed. v1.0 uses **no** iOS 18+ API.
21. `ForEach` over `Item` works directly (`Identifiable`); over `[UUID]` use `ForEach(ids, id: \.self)`.
22. Settings forms edit a `@State` copy + two `.onChange` (store → copy, copy → store) (§5.2) — no hand-written `Binding(get:set:)` capturing main-actor objects.
23. `Text` with a `String` variable uses the verbatim initializer automatically; `Text("literal \(n)")` is fine (no Localizable.strings exist).

**Frameworks**
24. `UNNotificationAction(identifier:title:options:icon:)` argument order fixed; `UNNotificationCategory(… hiddenPreviewsBodyPlaceholder: String, options:)`.
25. `DateComponents(hour:minute:weekday:)` and `DateComponents(day:hour:minute:)` argument orders follow the memberwise initializer (`…, day, hour, minute, …, weekday`).
26. `UNTimeIntervalNotificationTrigger` interval > 0 (use ≥ 2 s); never `repeats: true` below 60 s.
27. `content.userInfo` values: `String`/`Int` only (no `UUID`, no `Date`).
28. Never `removeAllPendingNotificationRequests()` / `removeAllDeliveredNotifications()`; always by our ids.
29. `setBadgeCount(_:) async throws` (iOS 16+); never `applicationIconBadgeNumber` (deprecated 17).
30. `AVAudioApplication.requestRecordPermission()` (iOS 17), `.allowBluetooth` (not `.allowBluetoothHFP`); `installTap` after `removeTap(onBus: 0)`; guard input format `sampleRate > 0`.
31. `SFSpeechRecognizer(locale:)` is failable and may fall back to another language → check `recognizer.locale.identifier.hasPrefix("tr")`.
32. App Intents: `static let title: LocalizedStringResource`, `static let description: IntentDescription?`, `init() {}` declared when a custom init exists, `openAppWhenRun` only via `@available(*, deprecated) extension`; no `supportedModes`; dialogs via `IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(text)))`; every intent file that names an AsistCore symbol imports `AsistCore` (05a #15).
33. `UNNotificationSound(named: UNNotificationSoundName("asist-kritik.wav"))` — file name with extension, file in the main bundle root.
34. v1.0 imports **no** `CoreLocation`, `WidgetKit`, `Security` (Keychain) — those belong to Appendix B features.
35. `.fileImporter` URLs: `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around the read; `import UniformTypeIdentifiers` for `UTType.json` (05a #12).
36. JSON: store uses `.iso8601` both ways, **never changed** (§3.1); `JSONSerialization` only for the partial-recovery count check (§3.6.4).
37. Files: data writes use `[.atomic, .completeFileProtectionUntilFirstUserAuthentication]`; never `.completeFileProtection` (actions/Siri run while locked); `previousFile` is written with `Data(contentsOf:)` + `write`, never `FileManager.copyItem` (05a #21).
38. `Dictionary(uniqueKeysWithValues:)` is forbidden on notification ids (duplicates trap) — use a loop or `Dictionary(_:uniquingKeysWith:)`.
39. No `hashValue`/`Hasher` for anything persisted or compared across launches — `StableHash.fnv1a64`.
40. Subscripts use an explicit `_` label; each type name is declared in exactly one file (`Chip.swift` owns `StatChip`; `DataStore.swift` owns `ImportPreview`/`ImportMode`) (05a #31, #34).

**Data safety and headless behaviour (runtime, not compile — the most expensive bug class)**
41. Never save or reconcile while `DataStore.isLoaded == false` (device locked since boot / protected data unavailable). A *read* failure is not corruption; only a successful read that fails to decode is. Readers (intents, onboarding gate) check `isLoaded` too (05a #26).
42. Every mutation persists synchronously before returning (no "save later"); the UI says "Kaydedildi" only when `store.canPersist` (05a #3).
43. Import "Değiştir" and restore-from-backup first write the current file to a daily backup copy; "Değiştir" keeps the local `meta` (05a #24).
44. Headless entry points **await** `engine.reconcile` after their last mutation (App Intent via `captureHeadless`, notification `handle`, BG task, `sceneDidEnterBackground`); no headless path relies on `requestReconcile` (05a #1, #7).
45. No `AppEnvironment.shared` inside any service initializer or anything it runs synchronously (05a #11).
46. Store mutators emit `onChange` and `save()` only on a real change; two idle reconciles perform 0 saves (05a #5).
47. All decoded numbers are clamped before use in `Task.sleep`, `DateComponents`, loops or triggers; `UInt64(max(0, s) * 1_000_000_000)` (05a #8, #20).
48. `SigningMonitor.reload()` precedes the first reconcile in every process (05a #4).
49. Notification action order: persist → remove/add this item's requests → reconcile → `completionHandler()` (05b B1).
50. The `beginBackgroundTask` expiration handler never captures and mutates a local `var`; it calls `AppEnvironment.shared.endFlush()` inside `MainActor.assumeIsolated` (05a #7).
51. `%` never reaches an `IntentDialog` (`TurkishSpeech.dialogSafe`, 05a #32).
52. A file written by a newer build is copied to `Yedekler` before the first save (D35, 05a #10).

---

## 10. Device test plan and open items

On-device checks after the first successful install (results go to the Diagnostics log): 01a §9 T1–T11, T13–T15 (T12 AlarmKit dropped; location tests move to v1.2); 01b §9 items 1–10 (item 9 dropped with D13; widget/control items move to v1.1); 03 §10 K1–K23 (widget items v1.1); backups and `Asist-acik-isler.txt` appear in Dosyalar › Bu iPhone'da › Asist › Yedekler. Additional tests from the critiques:

| Id | Test | Expected | Source |
|---|---|---|---|
| D-a | Back Tap → "Asist Hızlı Kayıt" → "yarın 9'da X hatırlat"; never open Asist afterwards | notification fires tomorrow 09:00 | 05a #1 |
| D-b | Create a normal reminder for later today; do not open Asist for 2 days | nags continue on the following days (day-tail) and briefings list it as geciken; horizon sentinel appears after the last one | 05a #2, 05b B3 |
| D-c | Lock-screen "✓ Yaptım" as the last interaction before expiry | Tanılama list still contains the `asist.sign.*` warnings | 05a #4 |
| D-d | "✓ Yaptım" / "10 dk" on a nag while Asist is not running, phone locked | no further nag of the old chain; snoozed alert arrives 10 min later | 05b B1 |
| D-e | Export → delete app → reinstall → import from iCloud Drive and from "Bu iPhone'da" | everything restored | 05a #12, K19 |
| D-f | Volume ×2 with `restoreVolumeAfterTrigger` on | volume returns to the previous level (decides copy F7) | 05b F7, D16 |
| D-g | Notification settings "Banner Stili: Kalıcı" | `permissions.alertsPersistent == true`; tip banner disappears | 05b A9 |
| D-h | Log `timeSensitiveSetting` with free signing | `.notSupported`/`.disabled` → planner emits `.active` (Report shows timeSensitiveAllowed = false) | 05b B7 |
| D-i | Capture in 80 dB background noise (music) | silence detection ends the capture ≤ 3 s after speech | 05b A6 |
| D-j | Focus "İş" on, Asist allowed / not allowed, test notification 30 s | documents which variant delivers (KURULUM guide E) | 05b B11 |
| D-k | Re-sign with the Sideloadly daemon without opening Asist; also let the profile expire once | record whether pending notifications fire after re-sign / after expiry, and whether the next BG refresh rebuilds | 05b A1, 01c open item 4 |
| D-l | Every Siri phrase of §3.7 with Turkish Siri; Shortcuts app shows "Asist'e Kaydet", "Asist Dinle", "Bugün Ne Var", "Gecikenler" | all found | 05b A8, 01b §9 |
| D-m | Install an older IPA over data saved by a newer build | red banner; `asist-data.yeni-surum-<n>.json` exists in Yedekler | D35 |
| D-n | High and critical reminders on the shop floor | custom sounds audible; missing file → default sound | D37 |
| D-o | Pre-alert of a meeting | only "✓ Yaptım"; due-time alert still arrives | 05a #13 |
| D-p | "Perşembe 14'te ABB ile toplantı" | 13:45 pre-alert, 14:00 alert, no nags, item closed at 16:00 | D31 |
| D-q | Mute 30 dk while two items nag | no sound during the window; one nag per item at the end | D32 |
| D-r | Power off/on, do not unlock, Siri "Asist'e kaydet" | honest "kilidini aç" answer; nothing lost after unlock | 05a #3 |

Open product questions — defaults already chosen, ask the user after the first week (05b §10, Turkish as the user will read them):
1. Ücretli Apple Developer (yıllık ~99 $) kabul edilebilir mi? 7 günlük imza riskini kaldırır, zamana duyarlı bildirimleri açar. *(Varsayılan: hayır, ücretsiz imza.)*
2. İş bilgisayarı gün boyu açık ve iPhone aynı Wi-Fi'da mı? (Sideloadly otomatik yenileme) *(Varsayılan: haftalık elle yenileme + otomatik yenileme önerisi.)*
3. İşte Odak / Rahatsız Etme kullanıyor musun? Toplantıda Asist'in susmasını mı, titreşimle devam etmesini mi istersin? *(Varsayılan: "Sessize al" menüsü.)*
4. Toplantı kayıtları: başlangıçta tek bildirim + 15 dk önce yeterli mi? *(Varsayılan: evet, D31.)*
5. "Acil" dediğinde Önemli (saatte bir) mi, Kritik (15 dakikada bir) mi? *(Varsayılan: Önemli; "çok acil" Kritik.)*
6. Pazar günü "haftaya salı" 2 gün sonrası mı, 9 gün sonrası mı? "Haftaya" tek başına = gelecek pazartesi mi? *(Varsayılan: 2 gün + "+7 gün" seçeneği; "haftaya" = gelecek haftanın ilk iş günü.)*
7. Mesai sonrası iş hatırlatmaları evde de gelsin mi? *(Varsayılan: yalnız Kritik ısrar eder.)*
8. Saatsiz söylediğin işler otomatik "Bugün" listesine girsin mi? *(Varsayılan: evet, D33.)*
9. Hitap: "Gökhan" / "Gökhan Bey" / isimsiz? Cumartesi iş günü mü? *(Varsayılan: isimsiz; Pazartesi–Cuma.)*
10. Akıllı Mod (kendi Claude API anahtarın) v1.1'de gerekli mi? *(Varsayılan: v1.1'de, kapalı başlar.)*

Open technical items (cannot be resolved without a device): force-quit + background action (T7); delivery of pending notifications after the 7-day profile expiry and after a daemon re-sign (D-k); Turkish Siri phrase matching without the Siri entitlement (D-l); `alertStyle == .alert` ↔ "Kalıcı" mapping (D-g); iOS 26 behaviour of MPVolumeView volume restore and HUD suppression (D-f); `timeSensitiveSetting` value under free signing (D-h).

---

## 11. Rejected or adjusted critique items

Everything in 05a and 05b not listed here is adopted (see §12).

| # | Critique item | Decision | Reason |
|---|---|---|---|
| R1 | 05b B2 — append-only event journal (unprotected file) for actions/captures before the first unlock | **Deferred to v1.1** | A second persistence path with replay/merge semantics and an unprotected file holding raw utterances, for a rare case (reboot, not yet unlocked). v1.0 answers honestly (`TurkishSpeech.dataUnavailable`), leaves pending requests untouched and never claims "saved" (05a #3) — nothing is silently lost; the user repeats after unlocking. |
| R2 | 05b A1 fix 1 — after expiry drop *every* follow-up incl. long-tails and repeating rules | **Adjusted**: only one-shot `.nag` after `E − 5 min` are dropped | Repeating triggers cannot be cut at a date. With 7-day signing an expiry is always < 7 days away, so dropping repeating rules would disable long-tails and recurrence carriers permanently — contradicting 05a #2/#9 and 05b B4. They cost at most one notification per day per item. |
| R3 | 05b A1 fix 2 — signing warnings as a full Israrcı chain | **Adjusted**: all 3 warning dates + an expiry notice, time-sensitive | A chain would need up to 9 more reserved slots. Four notifications across 48 h plus the red banner, the weekly ritual in KURULUM and Sideloadly auto-refresh cover the risk. |
| R4 | 05b §8 — cut checklist templates from v1.0 | **Rejected** (other cuts adopted) | Pure data + one detail section, no framework or target; directly useful for FAT/SAT/devreye alma; negligible compile risk. |
| R5 | 05b C3 — long-tails only for critical, max 3 | **Adjusted**: high + critical, max 5, staggered 2 min | Önemli is the user's explicit "do not let me forget" signal; ≤ 5 notifications at work start is acceptable; normal items are covered by day-tail, 5 workday briefings and the horizon sentinel. |
| R6 | 05b C1 optional — an explicit dismiss inside work hours pulls the next nag to +20 min | **Deferred to v1.1** | Makes the chain depend on dismissal history (k-stability, testability). The re-tuned Nazik already repeats every 2 h in work hours. |
| R7 | 05b A7 — `.ambient` session so confirmations obey the ring/silent switch | **Deferred to v1.1** | Category switching right after recognition is only verifiable on a device; the private-route rule (D18) already keeps Asist quiet in meetings. |
| R8 | 05b B10 — `Item.isRelative` for minute offsets across time zones | **Deferred to v1.1** | Turkey has no DST; only matters on trips; adds a model field and trigger branch. |
| R9 | 05b D7 "Sesle düzelt" for titles; D9 backup action "Dosyalar'a kaydet" | **Deferred to v1.1** | More UI/API surface, not needed for the core promise; daily backups are already visible in Files. |
| R10 | 05a #9 — plan 7 one-shot occurrences as the fix | **Superseded** by 05b B4 repeating carriers (7 one-shots remain the fallback) | One-shots still stop after ≤ 14 days without app activity; repeating carriers do not. |
| R11 | 05a #31 — CI grep for duplicate `struct` names | **Not added** | The compiler already reports "invalid redeclaration" with file/line; a grep would false-positive on nested types. Ownership is fixed in §2.3 instead. |
| R12 | 05a #14, #27, #29, #33 (TimelineProvider `@Sendable`, location fingerprint, Control fallback, location copy) | **Moved to Appendix B** | The features are not in v1.0; the fixes are applied inside Appendix B so v1.1/v1.2 inherit them. |
| R13 | 05b C5 — sound lengths ~8 s / ~20 s | **Adjusted** to ~6 s / ~12 s | A 20 s sound with Bırakmaz's 15-minute cadence would be unbearable; 12 s still cuts through shop-floor noise (verified by D-n). |
| R14 | 05b A10 — onboarding page asking "İşte Odak kullanıyor musun?" | **Simplified** to one line + guide E link + 30 s test notification | Keeps onboarding at 3 pages without extra state. |
| R15 | 05b §8 — voice complete/cancel/snooze "drop if WP7 slips" | **Kept in v1.0 as last WP7 item**; may slip to v1.1 without blocking the release | Reschedule verbs (G3) are the only 2-tap alternative to the date picker; the parser work is done anyway in WP1. |

---

## 12. Change log from critique (revision 1 → revision 2)

**Scope / structure**
- §1, D30: v1.0 "Çekirdek" = one app target. Widgets + Control, Smart Mode, active project, card-by-card EOD → v1.1; location → v1.2 (Appendix B). Checklist templates kept (§11 R4). Added to v1.0: events, mute, rate limiter, spoken lead times, custom sounds, undated → today, "Sesle ertele", Son silinenler, open-items text file (05b §8).
- §2: new tree (no `Shared/`, no `Widgets/`; `DinleIntent` in `App/Intents/`; new files `MuteMenu.swift`, `RecentlyDeletedView.swift`, `LeadTimeExtractor.swift`, `PlanPostPass.swift`, `Tools/make_sounds.py`, WAVs; `StatChip` owned by `Chip.swift`) (05b §8, 05a #31/#34).
- §7: single-target `project.yml` without entitlements, `INAlternativeAppNames` and location key (YAML parsed); v1.0 `package-ipa.sh` with App Intents metadata check (`bash -n` passed) (05a #30, 05b F5); exact `Tools/make_sounds.py` (§7.6, run-verified). §8: WPs re-cut (WP8 no widgets, WP7 no Smart Mode; intents became WP0 exact files).

**Blockers**
- 05a #1 / D34: `captureHeadless` awaits `engine.reconcile`; §4.1 r12; §9 r44; test D-a.
- 05a #2 / 05b B3: day-tail (next 3 days), long-tail eligibility `F > A`, 5 workday briefings listing overdue titles, horizon sentinel, copy "Asist'i bir kez açarsan…" when nothing follows (§6.4 steps 1c/1f/4/8, §3.5.5); tests; D-b.
- 05b B1: `handle()` order persist → remove/add this item's requests (`NagPlanner.immediateRequests`, `NotificationScheduler.add`) → reconcile → completionHandler (§6.3, §3.5.3, §3.6.5, §9 r49); D-d.
- 05b A1: one-shot nags clamped at expiry − 5 min; 3 warnings + expiry notice with "yenile, sonra bir kez aç" copy; weekly re-sign ritual + bundle-id check in KURULUM; `Asist-acik-isler.txt` (D17, §6.4 step 2/4, §3.6.4, §2.1); adjusted per §11 R2/R3.
- 05b A4: undated tasks → today untimed; T10 fallback → task; high/critical undated → "Ne zaman?"; "hemen" = +5 min (D33, ItemFactory R1/R5/R7, §3.4.6 G9/P4/P6).

**Majors (05a)**
- #3 `add → UndoToken?`, `canPersist`, honest headless messages (`TurkishSpeech.dataUnavailable/saveFailed`), UI "Kaydedildi" only when persisted.
- #4 `SigningMonitor.reload()` first in `bootstrap()`; BG refresh also detects re-sign.
- #5 mutators emit only real changes; `recordLocationFired` removed from v1.0.
- #6 `onChange` assigned before `load()`; `load()` emits `.all` on the false → true transition.
- #7 `sceneDidEnterBackground` begins a background task and awaits reconcile (exact code with `MainActor.assumeIsolated`).
- #8 workdays sanitised in decoding; `nextDayStart` bounded to 14 days; last workday toggle disabled; test.
- #9 superseded by carriers (05b B4, §11 R10).
- #10 `AppMeta.writerBuild`, `.newerWriter` issue + copy + red banner; `.iso8601` frozen (D35).
- #11 re-entrancy rule in `AppEnvironment`, §4.1 r13, §9 r45; VoiceCoordinator init pattern.
- #12 security-scoped `.fileImporter` exact pattern (§5.2).
- #13 `ASIST_PRE` category with only "✓ Yaptım"; defensive ignore in `handle`.

**Minors (05a)**: #15 explicit `import AsistCore` in intents/BackgroundRefresh; #16 `BGCompletion`; #17 `SystemVolumeAnchor` modifiers; #18 dismiss sheet before listening; #19 settings pattern syncs from the store; #20 clamps in `AppSettings`/`Recurrence`/`NagProfile`/`Place`/`Item` + `UInt64(max(0,…))`; #21 prev-file only from a verified main file via `Data` write; #22 partial-recovery count check; #23 horizon sentinel + tier 4 far-future k0s; #24 import replace keeps local meta; #25 `voice.apply` stores only, arming only when active; #26 readers check `isLoaded`, onboarding via `$router.showOnboarding`; #28 no estimate-based planning, "(tahmini)" UI only; #30 metadata check + flexible-matching fallback, no reflection-level setting; #32 `dialogSafe`; #34 `subscript(_:)`, single declaration files. #14/#27/#29/#33 → Appendix B (§11 R12); #31 → §11 R11.

**Product (05b)**
- A2 events (D31, `Item.isEvent`, `NagProfileKind.etkinlik`, `closeFinishedEvents`, event pre-alert default 15 min).
- A3 mute window (D32, `AppSettings.muteUntil`, chain + attribute rules, Today menu/banner).
- A5 / G10 `ParsedItem.leadTimesMinutes` → pre-alerts.
- A6 noise-floor silence detection; A7 private-route confirmations (D18, `speakConfirmationsOnSpeaker`; `.ambient` deferred, §11 R7).
- A8 / F3 / F4 / F5 naming table, "Asist Dinle", "Bugün Ne Var", no alternative app name, headless Back Tap recipe as guide A.
- A9 "Kalıcı" banner tip + guide; A10 3-page onboarding.
- B4 recurrence carriers (`Rule.monthly`, `.carrier`, ids `.r.*`); B5 content-bearing budget sentinel; B6 EOD candidates exclude later-today items; B7 `allowTimeSensitive`; B8 Son silinenler; B9 "Vazgeç" undo with transcript (`ToastCenter.undoTranscript`).
- C1 Nazik re-tuned; C2 "acil" → high + rate limiter (3 min spacing, ≤ 8/hour); C3 long-tails high/critical ≤ 5 staggered; C4 no evening repeats for Israrcı; Bırakmaz offsets 3/6/10/15; C5 custom sounds (D37); C6 promise line only on k = 0.
- D5 "Sesle ertele" (`ListenRequest.snoozeItemID`); D8 swipe "Doğru"; D11 new-project chip never pre-selected + stoplist.
- §6 parser gaps G1–G12, decisions P1–P6, corpus gate incl. `parser_corpus_extra.json` and `deferredExtraCases` (§3.4.6); `contextualStrings` and `frequentPeople` wiring.
- §7 copy F1–F16 (§5.5), F12 12-hour spoken times (`spokenTimeOfDay`).
- X1–X11 contradictions resolved in D11, D16, D18, §3.4.6 P1–P4, §3.7 guides, §6.4 (briefings), D31.
- §10 questions Q1–Q10 recorded with defaults (§10).

**Verified-OK items of 05a §2** required no change and remain as written.

---

## Appendix B — Deferred features (binding design, NOT compiled in v1.0)

Activation rule: a deferred feature is built only by its own WP after v1.0 has been installed and used; the WP first re-applies the listed deltas to §2/§3/§7 of this document (as a revision 3 change log entry), then implements. Until then no v1.0 file may import `WidgetKit`, `CoreLocation` or `Security`, or reference any type below.

### B.1 Summary

| Feature | Release | Section | WP |
|---|---|---|---|
| Akıllı Mod (Claude API) | v1.1 | B.2 | WP13 |
| Location reminders + Places | v1.2 | B.3 | WP14 |
| Home/lock-screen widgets + Control "Asist Dinle" | v1.1 | B.4 | WP12 |
| AlarmKit, Live Activity, calendar, digests | v2 | B.5 | — |

### B.2 Akıllı Mod — Claude API (v1.1, WP13)

Deltas when activated: `AppEnvironment` gains `let smartMode: SmartModeClient` (constructed with `KeychainStore(service: KeychainStore.defaultService)`, no `shared` access in init); `CaptureService.init` gains `smartMode:` and `requestSmartInterpretation(for:)`; `CaptureDraft` regains `smartState`/`smartSuggestion` and the `smartAvailable:` init parameter; views `SmartModeSettingsView`, `EmailDraftSheet`, `ProjectSummarySheet` + route `.smartModeSettings`, sheets `.emailDraft(UUID)`, `.projectSummary(UUID)`; files `AsistCore/SmartMode/*`, `App/SmartMode/*`, `SmartModeTests.swift`. D15 facts stay binding (default `claude-opus-5` + `fallbacks: "default"` + beta header; options `claude-sonnet-5`, `claude-haiku-4-5`; no date suffixes). Open decision for v1.1 (05b §8): the *parse* fallback may default to the fastest model with an 8 s timeout so "3 saniyede yakala" holds; e-mail drafts and summaries keep Opus 5 and 60 s.

#### B.2.1 Smart Mode wire types (AsistCore; facts from doc 06 are binding)

```swift
// API: Packages/AsistCore/Sources/AsistCore/SmartMode/SmartModeWire.swift
import Foundation

public enum SmartModeModelID {
    public static let opus5 = "claude-opus-5"        // default
    public static let sonnet5 = "claude-sonnet-5"
    public static let haiku45 = "claude-haiku-4-5"
    public static let all = [opus5, sonnet5, haiku45]
    /// "Claude Opus 5 (varsayılan, en akıllı)", "Claude Sonnet 5 (dengeli)", "Claude Haiku 4.5 (en hızlı/ucuz)"
    public static func label(_ id: String) -> String
    /// false for Haiku 4.5 (never send output_config.effort to it).
    public static func supportsEffort(_ id: String) -> Bool
    /// true only for claude-opus-5 → body "fallbacks": "default" + header anthropic-beta: server-side-fallback-2026-07-01.
    public static func usesServerFallback(_ id: String) -> Bool
}

/// Structured-output payload for utterance interpretation (schema in SmartModeSchemas.parse).
public struct SmartParseResponse: Codable, Equatable {
    public struct RecurrenceDTO: Codable, Equatable {
        public var freq: String; public var interval: Int; public var weekdays: [Int]?
        public var monthDay: Int?; public var month: Int?
    }
    public struct PlaceDTO: Codable, Equatable { public var name: String; public var trigger: String }
    public struct CommandDTO: Codable, Equatable {
        public var type: String; public var scope: String?; public var date: String?; public var query: String?
    }
    public var kind: String            // reminder|task|note|waiting|command
    public var title: String
    public var due: String?            // "YYYY-MM-DDTHH:mm" local
    public var hasTime: Bool
    public var recurrence: RecurrenceDTO?
    public var priority: String        // low|normal|high|critical
    public var person: String?
    public var project: String?
    public var place: PlaceDTO?
    public var command: CommandDTO?
    public var explanation: String
}

public struct EmailDraft: Codable, Equatable { public var subject: String; public var body: String }
public struct ProjectSummary: Codable, Equatable { public var summary: String; public var actionItems: [String] }

public enum EmailTone: String, CaseIterable { case formal, friendly, short }   // Resmi / Samimi / Kısa

/// Response envelope: concatenate `content` blocks with type == "text" only.
public struct MessagesResponse: Decodable {
    public struct Block: Decodable { public var type: String; public var text: String? }
    public var id: String?
    public var model: String?
    public var stopReason: String?
    public var content: [Block]
    enum CodingKeys: String, CodingKey { case id, model, content; case stopReason = "stop_reason" }
    public var joinedText: String { content.filter { $0.type == "text" }.compactMap { $0.text }.joined() }
}

public struct APIErrorEnvelope: Decodable {
    public struct Detail: Decodable { public var type: String?; public var message: String? }
    public var error: Detail?
}

public enum SmartModeSchemas {
    /// Byte-stable JSON Schema strings (every object has "additionalProperties": false; all properties
    /// required; optionals as anyOf [T, null]; no min/max). parse = 02 §14 fields; email = {subject, body};
    /// summary = {summary, actionItems[]}.
    public static let parse: String
    public static let email: String
    public static let summary: String
}

public enum SmartModePrompts {
    /// Static (cache-stable) system prompts in Turkish. Volatile data (now, projects, utterance) goes only
    /// into the user message.
    public static let parseSystem: String
    public static let emailSystem: String
    public static let summarySystem: String
    /// "Şu an: 2026-09-27T10:30 (Pazar), saat dilimi Europe/Istanbul. Projeler: […]. Yerler: […].
    /// Kurallar: 1–6 arası belirsiz saatler öğleden sonra. Cümle: \"…\""
    public static func parseUserMessage(utterance: String, now: Date, calendar: Calendar, projects: [String],
                                        places: [String], onDeviceHint: String) -> String
}

public enum SmartModeRequestBuilder {
    public static let endpoint = "https://api.anthropic.com/v1/messages"
    public static let anthropicVersion = "2023-06-01"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// JSONSerialization with .sortedKeys: {model, max_tokens, system, messages:[{role:"user",content}],
    /// output_config:{effort?, format:{type:"json_schema", schema}}, fallbacks?:"default"}.
    /// Never sends temperature/top_p/top_k/thinking; never prefills an assistant turn.
    public static func body(model: String, system: String, user: String, schemaJSON: String,
                            effort: String?, maxTokens: Int) throws -> Data
    /// content-type, x-api-key, anthropic-version (+ anthropic-beta for opus-5).
    public static func headers(model: String, apiKey: String) -> [String: String]
}

public enum SmartModeValidator {
    /// 02 §14 validation: enums valid, due parses in `calendar` and is > now, project/place ∈ known lists
    /// (else dropped), title non-empty ≤ 120 chars. `understood` regenerated by TurkishDateFormatter.
    /// nil = reject (keep on-device result).
    public static func parseResult(from response: SmartParseResponse, originalText: String, now: Date,
                                   calendar: Calendar, parserSettings: ParserSettings) -> ParseResult?
}
```

#### B.2.2 Smart Mode client (app)

```swift
// API: App/SmartMode/KeychainStore.swift
import Foundation
import Security

final class KeychainStore {
    static let defaultService = "com.gokhanbudak.asist.smartmode"
    static let apiKeyAccount = "anthropic-api-key"
    init(service: String)
    /// kSecClassGenericPassword, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. No access group (D8 of 01c).
    func read(account: String) -> String?
    func write(_ value: String, account: String) -> Bool       // delete-then-add
    func delete(account: String)
}
```

```swift
// API: App/SmartMode/SmartModeClient.swift
import Foundation
import AsistCore

enum SmartModeError: Error, Equatable {
    case disabled, noKey, invalidKey, rateLimited, overloaded, refusal, truncated
    case badRequest(String), network(String), decoding, rejectedByValidator
    /// Turkish user text (03 smart.*): "API anahtarı geçersiz", "Akıllı Mod'a ulaşılamadı; cihaz içi sonuç kullanıldı." …
    var userMessage: String { get }
}

struct SmartModeConfig: Equatable {
    var enabled: Bool
    var model: String                 // SmartModeModelID.*
}

/// Not actor-isolated; all inputs are values. Callers on the main actor `await` it (never blocks UI).
final class SmartModeClient {
    init(keychain: KeychainStore, session: URLSession = .shared)
    var hasKey: Bool { get }
    func saveKey(_ key: String) -> Bool
    func deleteKey()
    /// 25 s timeout, effort "low" (omitted for Haiku), max_tokens 4096, schema SmartModeSchemas.parse.
    /// Retry policy doc 06: 429 → one retry after retry-after (≤ 5 s); 500/529 → one retry after 1.5 s;
    /// URLError → one retry; 400/401/403/404/413 → no retry. stop_reason "refusal" → .refusal, "max_tokens" → .truncated.
    func interpret(utterance: String, onDeviceHint: String, now: Date, calendar: Calendar,
                   parserSettings: ParserSettings, config: SmartModeConfig) async -> Result<ParseResult, SmartModeError>
    /// 60 s, effort "medium", max_tokens 8000, schema email. Sends only this item's title/notes/person/project.
    func draftEmail(item: Item, projectName: String?, recipient: String, tone: EmailTone,
                    config: SmartModeConfig) async -> Result<EmailDraft, SmartModeError>
    /// 60 s, effort "medium", max_tokens 8000, schema summary. Sends only that project's note texts.
    func summarize(projectName: String, notes: [String], config: SmartModeConfig) async -> Result<ProjectSummary, SmartModeError>
    /// Minimal parse request ("Bağlantıyı test et").
    func testConnection(config: SmartModeConfig) async -> Result<Void, SmartModeError>
}
```

### B.3 Location reminders (v1.2, WP14)

Deltas when activated: `App/Location/LocationService.swift` (below), `PlacesView`/`PlaceEditorSheet`, route `.places`, sheet `.placeEditor(UUID?)`, `NSLocationWhenInUseUsageDescription` ("Asist, “fabrikaya varınca hatırlat” gibi konuma bağlı hatırlatmalar için konumunu kullanır."), `PermissionCenter.locationUsable`, `ReminderEngine.reconcile` step "locationCount = await location.sync(items:places:)" passed as `PlanInput.locationSlotsUsed`, `ItemFactory` R3 maps places to `placeID/placeTrigger` again, `NotificationCopy.locationContent(item:placeName:)` whose body ends with "“✓ Yaptım” demezsen, bir sonraki açılışta hatırlatmaya devam ederim." (05a #33; also in KULLANIM), and `DataStore.recordLocationFired(_:at:)`, which is a **no-op (no save, no onChange) when the item is missing/closed or `locationFiredAt != nil`** (05a #5). Location triggers take ≤ 10 of the item slots. `CLLocationManager` is created on the main thread in `start()`; `CLCircularRegion` radius `max(100, min(1000, maxRadius))`; a geofence is skipped when `CLLocationCoordinate2DIsValid` fails (05a #20).

```swift
// API: App/Location/LocationService.swift
import Foundation
import CoreLocation
import UserNotifications
import AsistCore

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Number of pending asist.loc.* requests after the last sync (≤ 10).
    private(set) var activeCount: Int = 0
    var isUsable: Bool { get }                       // whenInUse/always && accuracyAuthorization == .fullAccuracy

    /// Creates the CLLocationManager (main thread) and sets delegate. No init override.
    func start()
    func requestWhenInUse()
    /// One-shot current coordinate for "Şu anki konumu kaydet" (requestLocation + continuation, 15 s timeout).
    func currentCoordinate() async -> (latitude: Double, longitude: Double)?
    /// Desired set = open notifiable items with placeID, placeTrigger and locationFiredAt == nil (max 10, by createdAt).
    /// Every request carries userInfo fp = StableHash.fnv1a64("\(lat)|\(lon)|\(radius)|\(trigger)|\(title)|\(subtitle)|\(body)");
    /// a pending request whose fp differs is re-added (05a #27). Removes stale asist.loc.* requests, adds missing ones (01a §3 LocationRequestFactory, radius clamp 100…1000,
    /// content NotificationCopy.locationContent, category ASIST_ITEM, userInfo iid). Returns activeCount.
    /// Not usable → removes all asist.loc.* and returns 0.
    func sync(items: [Item], places: [Place]) async -> Int

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)       // → Task{@MainActor} requestReconcile
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
}
```
Delegate callbacks copy `locations.last?.coordinate.latitude/longitude` (Doubles) before hopping to the main actor.

### B.4 Widgets and Control Center control (v1.1, WP12)

Deltas when activated:
- New target `AsistWidgets` (app-extension, bundle id `com.gokhanbudak.asist.widgets`, condition `ASIST_WIDGET`) and `Shared/` compiled into both targets; the App Group entitlement `group.com.gokhanbudak.asist` on both targets; `package-ipa.sh` returns to 01c §2.5 (widget checks, inner-then-outer signing with entitlements) plus the §7.5 metadata check for both `Asist.app` and `PlugIns/AsistWidgets.appex`. Each install then consumes 2 App IDs.
- `DinleIntent` moves to `Shared/Intents/DinleIntent.swift` and wraps its body in `#if ASIST_APP … #endif` (the widget process must not reference `AppEnvironment`).
- `AppEnvironment` gains `let widgets: WidgetSnapshotWriter`; `dataDidChange`, `sceneDidBecomeActive` and `captureHeadless` call `widgets.refresh(...)` after their reconcile; `SigningMonitor` gains `appGroupAvailable` (`SnapshotStore.isAvailable`).
- Control fallback (05a #29): if the device test "Control → app opens → listening starts" fails on iOS 26 (Apple documents `openAppWhenRun` as an error inside extensions), change `DinleIntent` to `OpenIntent` with `@Parameter(title: "Hedef") var target: DinleHedef` where `enum DinleHedef: String, AppEnum { case dinle }` (static `typeDisplayRepresentation` and `caseDisplayRepresentations`), still compiled into both targets, still no `supportedModes`.
- `project.yml` additions:

```yaml
  AsistWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Widgets
      - path: Shared
    settings:
      base:
        PRODUCT_NAME: AsistWidgets
        PRODUCT_BUNDLE_IDENTIFIER: com.gokhanbudak.asist.widgets
        SKIP_INSTALL: YES
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ASIST_WIDGET"
    info:
      path: Generated/AsistWidgets-Info.plist
      properties:
        CFBundleDisplayName: Asist
        CFBundleDevelopmentRegion: tr
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Generated/AsistWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.gokhanbudak.asist
    dependencies:
      - package: AsistCore
```
The app target then adds `- path: Shared` to `sources`, `- target: AsistWidgets` with `embed: true` to `dependencies`, and the same `entitlements:` block (`Generated/Asist.entitlements`).


#### B.4.1 Widget snapshot (AsistCore) — exact for v1.1 (WP12)

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Widget/WidgetSnapshot.swift
import Foundation

public struct WidgetSnapshot: Codable, Equatable {
    public struct Entry: Codable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var anchor: Date?          // shown time
        public var overdueAt: Date?       // Item.overdueStart
        public var hasTime: Bool
        public var kind: ItemKind
        public var priority: Priority

        public init(id: UUID, title: String, anchor: Date?, overdueAt: Date?, hasTime: Bool, kind: ItemKind, priority: Priority) {
            self.id = id
            self.title = title
            self.anchor = anchor
            self.overdueAt = overdueAt
            self.hasTime = hasTime
            self.kind = kind
            self.priority = priority
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var overdueCount: Int          // at generatedAt
    public var todayCount: Int
    public var followUpCount: Int
    /// Open non-note items, overdue first (oldest first), then by anchor, within the next 7 days; max 12.
    public var entries: [Entry]

    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, overdueCount: Int,
                todayCount: Int, followUpCount: Int, entries: [Entry]) {
        self.version = version
        self.generatedAt = generatedAt
        self.overdueCount = overdueCount
        self.todayCount = todayCount
        self.followUpCount = followUpCount
        self.entries = entries
    }

    public static let empty = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), overdueCount: 0,
                                             todayCount: 0, followUpCount: 0, entries: [])

    public static func placeholder(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, overdueCount: 1, todayCount: 2, followUpCount: 1, entries: [
            Entry(id: UUID(), title: "Teklif revizyonunu gönder", anchor: now.addingTimeInterval(3600),
                  overdueAt: now.addingTimeInterval(3600), hasTime: true, kind: .reminder, priority: .high),
            Entry(id: UUID(), title: "Pano FAT tarihini netleştir", anchor: nil, overdueAt: nil,
                  hasTime: false, kind: .task, priority: .normal)
        ])
    }

    /// Overdue count as time passes without the app running.
    public func overdueCount(at date: Date) -> Int {
        let newlyOverdue = entries.filter { entry in
            guard let start = entry.overdueAt else { return false }
            return start > generatedAt && start <= date
        }.count
        return overdueCount + newlyOverdue
    }

    public func isOverdue(_ entry: Entry, at date: Date) -> Bool {
        guard let start = entry.overdueAt else { return false }
        return start <= date
    }

    /// Instants within `horizon` after `from` when some entry becomes overdue (timeline entries).
    public func transitions(after from: Date, horizon: TimeInterval) -> [Date] {
        let limit = from.addingTimeInterval(horizon)
        let dates = entries.compactMap { $0.overdueAt }.filter { $0 > from && $0 <= limit }
        return Array(Set(dates)).sorted()
    }
}
```

```swift
// FILE: Packages/AsistCore/Sources/AsistCore/Widget/SnapshotStore.swift
import Foundation

#if canImport(Darwin)
/// Disposable widget snapshot in the App Group container. Every call is nil/false-safe when the
/// group entitlement is missing (free signing, D1).
public enum SnapshotStore {
    public static let fileName = "widget_snapshot.json"

    private static let containerURL: URL? = SharedContainerLocator.resolve()?.containerURL

    public static var isAvailable: Bool { containerURL != nil }

    public static func fileURL() -> URL? {
        containerURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
#endif
```

```swift
// API: Packages/AsistCore/Sources/AsistCore/Widget/WidgetSnapshotBuilder.swift   (WP8)
public enum WidgetSnapshotBuilder {
    public static func build(items: [Item], now: Date, calendar: Calendar) -> WidgetSnapshot
}
```

#### B.4.2 Widget snapshot writer (app)

```swift
// API: App/Platform/WidgetSnapshotWriter.swift
import Foundation
import WidgetKit
import AsistCore

@MainActor
final class WidgetSnapshotWriter {
    /// WidgetSnapshotBuilder.build → SnapshotStore.write only when content changed (ignoring generatedAt)
    /// → WidgetCenter.shared.reloadAllTimelines(). No-op when the App Group is unavailable.
    /// No-op while !store.isLoaded (never publish an empty snapshot from an unreadable store, 05a #26).
    func refresh(items: [Item], now: Date, calendar: Calendar)
}
```

#### B.4.3 Widget extension and Control — exact for v1.1 (WP12)

Kinds: `AsistListenWidget`, `AsistNextWidget`, `AsistTodayWidget`, control `com.gokhanbudak.asist.control.dinle`. All taps are deep links (D13/D14). No App Intent buttons in widgets. Every widget view MUST apply `.containerBackground(.fill.tertiary, for: .widget)`. `Link` is used only in `systemMedium`.

```swift
// FILE: Widgets/AsistTimelineProvider.swift
import WidgetKit
import AsistCore

struct AsistEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let hasSharedData: Bool
}

struct AsistTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AsistEntry {
        AsistEntry(date: Date(), snapshot: WidgetSnapshot.placeholder(now: Date()), hasSharedData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AsistEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(makeEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AsistEntry>) -> Void) {
        let now = Date()
        let first = makeEntry(at: now)
        var entries = [first]
        for date in first.snapshot.transitions(after: now, horizon: 24 * 3600).prefix(20) {
            entries.append(AsistEntry(date: date, snapshot: first.snapshot, hasSharedData: first.hasSharedData))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func makeEntry(at date: Date) -> AsistEntry {
        let snapshot = SnapshotStore.read()
        return AsistEntry(date: date, snapshot: snapshot ?? WidgetSnapshot.empty, hasSharedData: snapshot != nil)
    }
}
```

```swift
// FILE: Widgets/AsistWidgetBundle.swift
import SwiftUI
import WidgetKit

@main
struct AsistWidgetBundle: WidgetBundle {
    var body: some Widget {
        makeWidgets()
    }

    /// `#available` outside the result builder (SE-0360); Xcode ≥ 16.1 (01b §5.5).
    private func makeWidgets() -> some Widget {
        if #available(iOS 18.0, *) {
            return widgetsWithControl
        }
        return baseWidgets
    }

    @WidgetBundleBuilder
    private var baseWidgets: some Widget {
        ListenWidget()
        NextWidget()
        TodayWidget()
    }

    @available(iOS 18.0, *)
    @WidgetBundleBuilder
    private var widgetsWithControl: some Widget {
        ListenWidget()
        NextWidget()
        TodayWidget()
        DinleControl()
    }
}
```
If CI rejects `makeWidgets()`, replace `body` with the forum-accepted form: `if #available(iOSApplicationExtension 18.0, *) { return widgetsWithControl } else { return baseWidgets }` (01b §5.5 note).

```swift
// FILE: Widgets/DinleControl.swift
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct DinleControl: ControlWidget {
    static let kind = "com.gokhanbudak.asist.control.dinle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: DinleIntent()) {
                Label("Asist Dinle", systemImage: "mic.fill")
            }
        }
        .displayName("Asist Dinle")
        .description("Asist'i açar ve hemen dinlemeye başlar.")
    }
}
```

Widget views (WP8 implements; 01b §5.5 and 03 §8 are the visual spec):

| Widget | Families | Content (entry.date based) | Tap |
|---|---|---|---|
| `ListenWidget` / `ListenWidgetView` | `.systemSmall`, `.accessoryCircular` | mic symbol, "Dinle", `"\(n) geciken"` in red when `snapshot.overdueCount(at:) > 0` | `.widgetURL(DeepLink.listen(kind: nil, projectID: nil).url)` |
| `NextWidget` / `NextWidgetView` | `.systemSmall`, `.accessoryRectangular`, `.accessoryInline` | first entry: title (2 lines) + `Text(anchor, style: .time)`; overdue red; rectangular 2nd line `"2 geciken · 5 bugün"`; inline `"2 geciken · 15:00 Teklif"`; empty → "Planlı iş yok" | `.widgetURL(DeepLink.item(id).url)` or `DeepLink.today.url` |
| `TodayWidget` / `TodayWidgetView` | `.systemMedium` | left column counters (geciken/bugün/takip), right first 3 entries; bottom-right mic `Link` | rows `Link(destination: DeepLink.item(id).url)`, mic `Link(destination: DeepLink.listen(…).url)` |
| any, `hasSharedData == false` | — | mic + "Asist'i açmak için dokun" | `DeepLink.listen(…).url` |

Ternaries with colors MUST name the type: `isOverdue ? Color.red : Color.secondary`.

### B.5 v2 notes

AlarmKit for Kritik items only (iOS 26, `#available`-gated, own usage string), Live Activity for the hero item, calendar read (EventKit) to auto-create event items, digests ("3 iş seni bekliyor") — each needs its own compile-risk review before entering a plan.
