// API: Packages/AsistCore/Sources/AsistCore/Agenda/NotificationCopy.swift
// WP2 (04 §3.5.5; copy table 03 §3.2 as amended by 04 §5.5 C6/F8–F11/F16; 01a §7.3).
// Content is static once scheduled, so every relative word is computed against the fire date.
import Foundation

public enum NotificationCopy {
    /// Title limit (03 §9 r38): longer titles are cut at a word boundary with "…".
    static let titleLimit = 60
    /// One body line of the user's own words is kept short enough for the lock screen.
    static let bodyLineLimit = 150

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
                                   nextFireDate: Date?, isLastOfDay: Bool, calendar: Calendar) -> NotificationText {
        let k = max(0, attempt)
        let subtitle: String
        if isLastOfDay && nextFireDate != nil {
            subtitle = "Bugünlük son hatırlatma · yarın sabah yine"
        } else if item.snoozeCount >= 3 {
            subtitle = String(item.snoozeCount) + ". erteleme · başka bir gün mü?"
        } else if k == 0 {
            subtitle = firstSubtitle(item: item, projectName: projectName, fireDate: fireDate, calendar: calendar)
        } else {
            subtitle = nagSubtitle(item: item, attempt: k, fireDate: fireDate, calendar: calendar)
        }

        let second: String
        if let next = nextFireDate {
            if k == 0 {
                second = "“✓ Yaptım” diyene kadar hatırlatmaya devam edeceğim."
            } else {
                second = "Sonraki: " + nextLabel(next, fireDate: fireDate, calendar: calendar)
            }
        } else {
            second = "Asist'i bir kez açarsan hatırlatmaya devam ederim."
        }
        return NotificationText(title: displayTitle(item), subtitle: subtitle,
                                body: joinLines(firstBodyLine(item), second))
    }

    /// Events (D31): title = item.title; subtitle "<Perşembe 14:00> · <Proje>"; body = original text (no repeat promise).
    public static func eventContent(item: Item, projectName: String?, calendar: Calendar) -> NotificationText {
        var parts: [String] = []
        if let start = item.anchorDate {
            parts.append(weekdayTime(start, includeTime: true, calendar: calendar))
        }
        if let project = nonEmpty(projectName) {
            parts.append(project)
        }
        return NotificationText(title: displayTitle(item), subtitle: parts.joined(separator: " · "),
                                body: firstBodyLine(item))
    }

    /// Waiting items: title "Takip · <person>: <title>" (or "Takip: <title>");
    /// k=0 subtitle: item.hasTime ? "Geldi mi? · Son tarih: <Cuma>" : "Geldi mi? · <n> gündür bekliyor" (05b F8; n from createdAt);
    /// k≥1 "<k+1>. kez soruyorum — geldi mi?".
    public static func followUpContent(item: Item, attempt: Int, fireDate: Date, calendar: Calendar) -> NotificationText {
        let k = max(0, attempt)
        let topic = TurkishText.truncated(cleanTitle(item), max: 45)
        let title: String
        if let person = nonEmpty(item.person) {
            title = "Takip · " + TurkishText.truncated(person, max: 25) + ": " + topic
        } else {
            title = "Takip: " + topic
        }
        let subtitle: String
        if k >= 1 {
            subtitle = String(k + 1) + ". kez soruyorum — geldi mi?"
        } else if item.hasTime, let due = item.dueDate {
            subtitle = "Geldi mi? · Son tarih: "
                + TurkishDateFormatter.shortDateTime(due, now: fireDate, calendar: calendar, includeTime: false)
        } else {
            let days = TurkishSpeech.dayOffset(from: item.createdAt, to: fireDate, calendar: calendar)
            subtitle = days >= 1 ? "Geldi mi? · " + String(days) + " gündür bekliyor" : "Geldi mi?"
        }
        return NotificationText(title: title, subtitle: subtitle, body: firstBodyLine(item))
    }

    /// "<30 dakika> sonra: <title>" / "<Salı 15:00> · <Proje>" (category ASIST_PRE).
    public static func preAlertContent(item: Item, projectName: String?, leadMinutes: Int, calendar: Calendar) -> NotificationText {
        let prefix = TurkishDateFormatter.duration(minutes: max(1, leadMinutes)) + " sonra: "
        let room = max(20, titleLimit - prefix.count)
        let title = prefix + TurkishText.truncated(cleanTitle(item), max: room)
        var parts: [String] = []
        if let due = item.dueDate {
            parts.append(weekdayTime(due, includeTime: item.hasTime || item.isEvent, calendar: calendar))
        }
        if let project = nonEmpty(projectName) {
            parts.append(project)
        }
        return NotificationText(title: title, subtitle: parts.joined(separator: " · "), body: firstBodyLine(item))
    }

    /// Daily repeating safety net (static text): subtitle "Hâlâ açık · her sabah soracağım" (05b F11); a waiting
    /// (Takip) item's long-tail fires at settings.followUpAskTime (default 16:00), not in the morning, so its subtitle
    /// is "Hâlâ gelmedi · her gün soracağım".
    public static func longTailContent(item: Item, projectName: String?) -> NotificationText {
        let isWaiting = item.kind == .waiting
        let title = isWaiting ? followUpTitle(item) : displayTitle(item)
        let subtitle = isWaiting ? "Hâlâ gelmedi · her gün soracağım" : "Hâlâ açık · her sabah soracağım"
        return NotificationText(title: title, subtitle: subtitle, body: firstBodyLine(item))
    }

    /// Repeating carrier of a recurring item (static text): subtitle "<Her gün 09:00> · tekrarlayan".
    /// WP0-FIX: D29 — the clock time is read in the injected calendar (the planner passes its plan calendar); the
    /// former two-argument form read the device time zone and has been removed.
    public static func recurrenceCarrierContent(item: Item, projectName: String?, calendar: Calendar) -> NotificationText {
        var parts: [String] = []
        if let rule = item.recurrence {
            var text = TurkishDateFormatter.recurrenceText(rule)
            if let due = item.dueDate {
                text += " " + TurkishDateFormatter.time(due, calendar: calendar)
            }
            parts.append(text)
        }
        parts.append("tekrarlayan")
        if let project = nonEmpty(projectName) {
            parts.append(project)
        }
        let title = item.kind == .waiting ? followUpTitle(item) : displayTitle(item)
        return NotificationText(title: title, subtitle: parts.joined(separator: " · "), body: firstBodyLine(item))
    }

    public static func backupContent() -> NotificationText {
        NotificationText(title: "Yedek zamanı", subtitle: "", body: "Kayıtlarının bir yedeğini almak ister misin?")
    }

    /// Body: "İmzanın bitmesine <3 gün> kaldı. Yenilemezsen hatırlatmaların susar. Sideloadly ile yenile, sonra Asist'i bir kez aç." (05b A1)
    public static func signingContent(expiry: Date, fireDate: Date, calendar: Calendar) -> NotificationText {
        let remaining = SigningExpiryPlanner.remainingDescription(from: fireDate, to: expiry)
        return NotificationText(title: "Asist'in imzası bitiyor", subtitle: "",
                                body: "İmzanın bitmesine " + remaining + " kaldı. Yenilemezsen hatırlatmaların susar. "
                                    + "Sideloadly ile yenile, sonra Asist'i bir kez aç.")
    }

    /// At expiry: title "Asist'in imzası doldu"; body "Sideloadly ile yenile, sonra Asist'i bir kez aç. O zamana kadar “✓ Yaptım” çalışmaz."
    public static func signingExpiredContent() -> NotificationText {
        NotificationText(title: "Asist'in imzası doldu", subtitle: "",
                         body: "Sideloadly ile yenile, sonra Asist'i bir kez aç. O zamana kadar “✓ Yaptım” çalışmaz.")
    }

    /// Appended as a new body line to the budget sentinel (a copy of the earliest dropped notification, 05b B5/F16):
    /// "+<n> hatırlatma daha — planı tazelemek için Asist'i aç".
    public static func budgetSentinelLine(extraCount: Int) -> String {
        if extraCount <= 0 {
            return "Planı tazelemek için Asist'i bir kez aç"
        }
        return "+" + String(extraCount) + " hatırlatma daha — planı tazelemek için Asist'i aç"
    }

    /// Horizon sentinel: "Asist'i bir kez aç" / "<n> açık iş var" /
    /// "Hatırlatmaya devam edebilmem için planı tazelemem gerekiyor. Bir kez açman yeter."
    public static func horizonSentinelContent(openCount: Int) -> NotificationText {
        let subtitle = openCount > 0 ? String(openCount) + " açık iş var" : ""
        return NotificationText(title: "Asist'i bir kez aç", subtitle: subtitle,
                                body: "Hatırlatmaya devam edebilmem için planı tazelemem gerekiyor. Bir kez açman yeter.")
    }

    /// Diagnostics / onboarding test (category ASIST_ITEM so the actions can be tried).
    public static func testContent() -> NotificationText {
        NotificationText(title: "Deneme: Asist çalışıyor", subtitle: "Bildirimler doğru ayarlanmış",
                         body: "Bildirimi basılı tut ve “✓ Yaptım” düğmesine dokun.")
    }

    public static func movedFeedbackContent(count: Int) -> NotificationText {
        NotificationText(title: "Gün sonu", subtitle: "",
                         body: String(max(0, count)) + " iş sonraki iş gününe taşındı. Geri almak için dokun.")
    }

    // MARK: - Internal helpers (also used by AgendaBuilder)

    /// Trimmed title; the kind label when empty.
    static func cleanTitle(_ item: Item) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.kind.label : title
    }

    /// "Salı 15:00" / "Salı" — weekday name of `date` plus its clock time.
    static func weekdayTime(_ date: Date, includeTime: Bool, calendar: Calendar) -> String {
        let day = TurkishSpeech.weekdayName(date, calendar: calendar)
        return includeTime ? day + " " + TurkishDateFormatter.time(date, calendar: calendar) : day
    }

    // MARK: - Private helpers

    private static func displayTitle(_ item: Item) -> String {
        TurkishText.truncated(cleanTitle(item), max: titleLimit)
    }

    private static func followUpTitle(_ item: Item) -> String {
        let topic = TurkishText.truncated(cleanTitle(item), max: 45)
        if let person = nonEmpty(item.person) {
            return "Takip · " + TurkishText.truncated(person, max: 25) + ": " + topic
        }
        return "Takip: " + topic
    }

    private static func firstSubtitle(item: Item, projectName: String?, fireDate: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        let timed = item.hasTime || item.snoozedUntil != nil
        parts.append(weekdayTime(fireDate, includeTime: timed, calendar: calendar))
        if let project = nonEmpty(projectName) {
            parts.append(project)
        }
        if item.priority >= .high {
            parts.append(item.priority.label)
        }
        return parts.joined(separator: " · ")
    }

    private static func nagSubtitle(item: Item, attempt: Int, fireDate: Date, calendar: Calendar) -> String {
        let ordinal = String(attempt + 1) + ". hatırlatma"
        var waited: String? = nil
        if let anchor = item.anchorDate {
            let endOfDayRule = item.kind == .task && !item.hasTime && item.snoozedUntil == nil
            if endOfDayRule {
                let days = TurkishSpeech.dayOffset(from: anchor, to: fireDate, calendar: calendar)
                waited = days >= 1 ? String(days) + " gündür bekliyor" : "Gün içinde"
            } else {
                let minutes = Int(fireDate.timeIntervalSince(anchor) / 60)
                if minutes >= 1440 {
                    let days = max(1, TurkishSpeech.dayOffset(from: anchor, to: fireDate, calendar: calendar))
                    waited = String(days) + " gündür bekliyor"
                } else if minutes >= 60 {
                    waited = String(minutes / 60) + " saattir bekliyor"
                } else if minutes >= 1 {
                    waited = String(minutes) + " dakikadır bekliyor"
                }
            }
        }
        var text = waited.map { $0 + " · " + ordinal } ?? ordinal
        if item.priority == .critical {
            text = "KRİTİK · " + text
        }
        return text
    }

    /// "15:30" when on the fire date's day, else "Yarın 08:30" / "Salı 08:30" / "6 Ekim Salı 08:30".
    private static func nextLabel(_ next: Date, fireDate: Date, calendar: Calendar) -> String {
        if calendar.isDate(next, inSameDayAs: fireDate) {
            return TurkishDateFormatter.time(next, calendar: calendar)
        }
        return TurkishDateFormatter.shortDateTime(next, now: fireDate, calendar: calendar, includeTime: true)
    }

    /// “<originalText>” or the first two non-empty lines of the notes; "" when neither exists.
    private static func firstBodyLine(_ item: Item) -> String {
        if let original = nonEmpty(item.originalText) {
            let singleLine = original.replacingOccurrences(of: "\n", with: " ")
            return "“" + TurkishText.truncated(singleLine, max: bodyLineLimit) + "”"
        }
        let lines = item.notes
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let firstTwo = lines.prefix(2).map { TurkishText.truncated($0, max: bodyLineLimit) }
        return firstTwo.joined(separator: "\n")
    }

    private static func joinLines(_ first: String, _ second: String) -> String {
        if first.isEmpty {
            return second
        }
        if second.isEmpty {
            return first
        }
        return first + "\n" + second
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
