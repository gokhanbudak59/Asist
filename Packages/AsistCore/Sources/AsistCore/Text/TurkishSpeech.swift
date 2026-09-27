// API: Packages/AsistCore/Sources/AsistCore/Text/TurkishSpeech.swift
// WP0 STUB (04 §3.5.4) — WP2 replaces this file (03 §5.12 behaviour spec). Numbers, suffixes, clock phrases and
// dialogSafe are usable; `confirmation` is simplified.
import Foundation

public enum TurkishSpeech {
    /// Honest answer when the data file cannot be read (device not unlocked since reboot) — 05a #3/#26.
    public static let dataUnavailable = "Şu an kayıtlarına erişemiyorum. Telefonun kilidini açıp tekrar dener misin?"
    /// Headless save failed (disk full / write error) — 05a #3.
    public static let saveFailed = "Kaydedemedim; telefonda yer kalmamış olabilir. Asist'i açıp kontrol et."

    /// 0…99 in words: 15 → "on beş", 40 → "kırk".
    public static func numberWords(_ n: Int) -> String {
        let units = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
        let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
        guard n >= 0, n <= 99 else { return String(n) }
        if n < 10 { return units[n] }
        let unit = n % 10
        return unit == 0 ? tens[n / 10] : tens[n / 10] + " " + units[unit]
    }

    /// Locative suffix after digits for display, chosen by the spoken last word (03 §5.12):
    /// 1 → "'de", 3 → "'te", 6 → "'da", 10 → "'da", 20 → "'de", 30 → "'da", 40 → "'ta", 50 → "'de".
    public static func locativeSuffix(forNumber n: Int) -> String {
        // sıfır bir iki üç dört beş altı yedi sekiz dokuz
        let unitSuffixes = ["'da", "'de", "'de", "'te", "'te", "'te", "'da", "'de", "'de", "'da"]
        // – on yirmi otuz kırk elli altmış yetmiş seksen doksan
        let tenSuffixes = ["", "'da", "'de", "'da", "'ta", "'de", "'ta", "'te", "'de", "'da"]
        let a = Int(n.magnitude % 1000)
        if a % 10 != 0 { return unitSuffixes[a % 10] }
        if a == 0 { return n == 0 ? "'da" : "'de" }     // sıfır / bin
        if a % 100 != 0 { return tenSuffixes[(a / 10) % 10] }
        return "'de"                                     // yüz
    }

    /// Display form: (15, 0) → "15'te", (15, 30) → "15:30'da", (9, 0) → "9'da", (0, 0) → "gece yarısı".
    public static func displayClockLocative(hour: Int, minute: Int) -> String {
        if hour == 0 && minute == 0 { return "gece yarısı" }
        if minute == 0 { return String(hour) + locativeSuffix(forNumber: hour) }
        return String(hour) + ":" + AsistCalendar.pad(minute, 2) + locativeSuffix(forNumber: minute)
    }

    /// 24-hour spoken form (kept for tests/diagnostics): (15, 0) → "on beşte", (15, 30) → "on beş otuzda".
    public static func spokenClockLocative(hour: Int, minute: Int) -> String {
        if hour == 0 && minute == 0 { return "gece yarısı" }
        if minute == 0 { return numberWords(hour) + stubBareSuffix(hour) }
        return numberWords(hour) + " " + numberWords(minute) + stubBareSuffix(minute)
    }

    /// 12-hour clock with daypart for TTS (05b F12): (15,0) → "öğleden sonra üçte", (9,0) → "sabah dokuzda",
    /// (20,0) → "akşam sekizde", (12,0) → "öğlen on ikide", (15,30) → "öğleden sonra üç buçukta",
    /// (15,15) → "öğleden sonra üç on beşte", (2,0) → "gece ikide", (0,0) → "gece yarısı".
    /// Dayparts: 05:00–11:59 sabah · 12:00–12:59 öğlen · 13:00–17:59 öğleden sonra · 18:00–21:59 akşam · 22:00–04:59 gece.
    public static func spokenTimeOfDay(hour: Int, minute: Int) -> String {
        if hour == 0 && minute == 0 { return "gece yarısı" }
        let part: String
        switch hour {
        case 5...11: part = "sabah"
        case 12: part = "öğlen"
        case 13...17: part = "öğleden sonra"
        case 18...21: part = "akşam"
        default: part = "gece"
        }
        var h12 = hour % 12
        if h12 == 0 { h12 = 12 }
        let clock: String
        if minute == 0 {
            clock = numberWords(h12) + stubBareSuffix(h12)
        } else if minute == 30 {
            clock = numberWords(h12) + " buçukta"
        } else {
            clock = numberWords(h12) + " " + numberWords(minute) + stubBareSuffix(minute)
        }
        return part + " " + clock
    }

    /// "bugün öğleden sonra üçte", "yarın sabah dokuzda", "salı öğleden sonra üç buçukta", "29 Ekim sabah onda"
    /// (weekday names lowercase, month names capitalised, no "saat"). Screens keep the 24-hour clock.
    public static func spokenWhen(_ date: Date, now: Date, calendar: Calendar) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        let dayText: String
        if offset == 0 {
            dayText = "bugün"
        } else if offset == 1 {
            dayText = "yarın"
        } else if offset >= 2 && offset <= 6 {
            let iso = AsistCalendar.isoWeekday(date, calendar: calendar)
            dayText = TurkishText.lower(TurkishDateFormatter.weekdays[min(6, max(0, iso - 1))])
        } else {
            let c = calendar.dateComponents([.month, .day], from: date)
            let month = TurkishDateFormatter.months[min(11, max(0, (c.month ?? 1) - 1))]
            dayText = String(c.day ?? 1) + " " + month
        }
        let t = calendar.dateComponents([.hour, .minute], from: date)
        return dayText + " " + spokenTimeOfDay(hour: t.hour ?? 0, minute: t.minute ?? 0)
    }

    /// TTS/Siri confirmation after saving (03 §7.12 `tts.saved.*`). `headless` adds the title (Siri path).
    /// Never places a suffix directly after a placeholder (03 §5.12). Result is `dialogSafe`.
    public static func confirmation(for item: Item, projectName: String?, headless: Bool, lowConfidence: Bool,
                                    appliedDefaultTime: Bool, now: Date, calendar: Calendar) -> String {
        // WP0 STUB: simplified sentences.
        if headless && lowConfidence {
            return dialogSafe("“" + item.title + "” olarak kaydettim. Emin olmak için Asist'i aç.")
        }
        let text: String
        switch item.kind {
        case .note:
            if let projectName = projectName, !projectName.isEmpty {
                text = projectName + " projesine not aldım."
            } else {
                text = "Not aldım."
            }
        case .waiting:
            text = "Tamam, takip edeceğim."
        case .reminder, .task:
            if appliedDefaultTime {
                text = "Zaman söylemedin; bir saat sonra hatırlatacağım."
            } else if let due = item.anchorDate {
                let base = "Tamam, " + spokenWhen(due, now: now, calendar: calendar) + " hatırlatacağım"
                text = headless ? base + ": " + item.title + "." : base + "."
            } else {
                text = "Görevlere ekledim."
            }
        }
        return dialogSafe(text)
    }

    /// Text safe for `IntentDialog(LocalizedStringResource(stringLiteral:))`: every "%" becomes " yüzde ",
    /// runs of spaces collapse to one, result trimmed (05a #32). Applied to every spoken/dialog string.
    public static func dialogSafe(_ text: String) -> String {
        let replaced = text.replacingOccurrences(of: "%", with: " yüzde ")
        var out = ""
        var lastWasSpace = false
        for ch in replaced {
            if ch == " " {
                if !lastWasSpace { out.append(ch) }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Stub helpers (file-private)

    /// Locative suffix without the apostrophe ("te", "da") for spoken words.
    private static func stubBareSuffix(_ n: Int) -> String {
        String(locativeSuffix(forNumber: n).dropFirst())
    }
}
