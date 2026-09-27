// API: Packages/AsistCore/Sources/AsistCore/Agenda/NotificationCopy.swift
// WP0 STUB (04 §3.5.5) — WP2 replaces this file with the 03 §3.2 copy table. Static texts are final.
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
                                   nextFireDate: Date?, isLastOfDay: Bool, calendar: Calendar) -> NotificationText {
        // WP0 STUB
        let second: String
        if let next = nextFireDate {
            second = attempt == 0
                ? "“✓ Yaptım” diyene kadar hatırlatmaya devam edeceğim."
                : "Sonraki: " + TurkishDateFormatter.time(next, calendar: calendar)
        } else {
            second = "Asist'i bir kez açarsan hatırlatmaya devam ederim."
        }
        return NotificationText(title: stubTitle(item), subtitle: projectName ?? "",
                                body: stubJoin(stubFirstLine(item), second))
    }

    /// Events (D31): title = item.title; subtitle "<Perşembe 14:00> · <Proje>"; body = original text (no repeat promise).
    public static func eventContent(item: Item, projectName: String?, calendar: Calendar) -> NotificationText {
        // WP0 STUB
        NotificationText(title: stubTitle(item), subtitle: projectName ?? "", body: stubFirstLine(item))
    }

    /// Waiting items: title "Takip · <person>: <title>" (or "Takip: <title>");
    /// k=0 subtitle: item.hasTime ? "Geldi mi? · Son tarih: <Cuma>" : "Geldi mi? · <n> gündür bekliyor" (05b F8; n from createdAt);
    /// k≥1 "<k+1>. kez soruyorum — geldi mi?".
    public static func followUpContent(item: Item, attempt: Int, fireDate: Date, calendar: Calendar) -> NotificationText {
        // WP0 STUB
        let title: String
        if let person = item.person, !person.isEmpty {
            title = "Takip · " + person + ": " + stubTitle(item)
        } else {
            title = "Takip: " + stubTitle(item)
        }
        let subtitle = attempt == 0 ? "Geldi mi?" : String(attempt + 1) + ". kez soruyorum — geldi mi?"
        return NotificationText(title: title, subtitle: subtitle, body: stubFirstLine(item))
    }

    /// "<30 dakika> sonra: <title>" / "<Salı 15:00> · <Proje>" (category ASIST_PRE).
    public static func preAlertContent(item: Item, projectName: String?, leadMinutes: Int, calendar: Calendar) -> NotificationText {
        // WP0 STUB
        NotificationText(title: TurkishDateFormatter.duration(minutes: leadMinutes) + " sonra: " + stubTitle(item),
                         subtitle: projectName ?? "", body: stubFirstLine(item))
    }

    /// Daily repeating safety net (static text): subtitle "Hâlâ açık · her sabah soracağım" (05b F11).
    public static func longTailContent(item: Item, projectName: String?) -> NotificationText {
        NotificationText(title: stubTitle(item), subtitle: "Hâlâ açık · her sabah soracağım", body: stubFirstLine(item))
    }

    /// Repeating carrier of a recurring item (static text): subtitle "<Her gün 09:00> · tekrarlayan".
    public static func recurrenceCarrierContent(item: Item, projectName: String?) -> NotificationText {
        // WP0 STUB
        NotificationText(title: stubTitle(item), subtitle: "tekrarlayan", body: stubFirstLine(item))
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
        "+" + String(extraCount) + " hatırlatma daha — planı tazelemek için Asist'i aç"
    }

    /// Horizon sentinel: "Asist'i bir kez aç" / "<n> açık iş var" /
    /// "Hatırlatmaya devam edebilmem için planı tazelemem gerekiyor. Bir kez açman yeter."
    public static func horizonSentinelContent(openCount: Int) -> NotificationText {
        NotificationText(title: "Asist'i bir kez aç", subtitle: String(openCount) + " açık iş var",
                         body: "Hatırlatmaya devam edebilmem için planı tazelemem gerekiyor. Bir kez açman yeter.")
    }

    public static func testContent() -> NotificationText {
        // WP0 STUB (WP2 finalises the copy)
        NotificationText(title: "Deneme: Asist çalışıyor", subtitle: "", body: "Bildirimler doğru ayarlanmış.")
    }

    public static func movedFeedbackContent(count: Int) -> NotificationText {
        NotificationText(title: "Asist", subtitle: "",
                         body: String(count) + " iş sonraki iş gününe taşındı. Geri almak için dokun.")
    }

    // MARK: - Stub helpers (file-private)

    private static func stubTitle(_ item: Item) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Asist" : TurkishText.truncated(title, max: 60)
    }

    private static func stubFirstLine(_ item: Item) -> String {
        if let original = item.originalText, !original.isEmpty { return "“" + original + "”" }
        return item.notes
    }

    private static func stubJoin(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : first + "\n" + second
    }
}
