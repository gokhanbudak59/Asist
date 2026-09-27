// API: Packages/AsistCore/Sources/AsistCore/Text/TurkishSpeech.swift
// WP2 (04 §3.5.4; behaviour spec 03 §5.12 as amended by 04 §5.5 F12).
// Spoken numbers, locative suffixes, 12-hour daypart times and the TTS/Siri sentences said after a save.
// Rule (03 §5.12): a suffix never follows a placeholder directly — every "number + suffix" is produced here.
import Foundation

public enum TurkishSpeech {
    /// Honest answer when the data file cannot be read (device not unlocked since reboot) — 05a #3/#26.
    public static let dataUnavailable = "Şu an kayıtlarına erişemiyorum. Telefonun kilidini açıp tekrar dener misin?"
    /// Headless save failed (disk full / write error) — 05a #3.
    public static let saveFailed = "Kaydedemedim; telefonda yer kalmamış olabilir. Asist'i açıp kontrol et."

    private static let unitWords: [String] = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tenWords: [String] = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]

    // MARK: - Numbers

    /// 0…99 in words: 15 → "on beş", 40 → "kırk". Also 100…999 999 ("yüz iki", "iki bin yirmi altı");
    /// negative or larger values fall back to digits.
    public static func numberWords(_ n: Int) -> String {
        if n < 0 || n >= 1_000_000 {
            return String(n)
        }
        if n < 10 {
            return unitWords[n]
        }
        if n < 100 {
            let unit = n % 10
            let ten = tenWords[n / 10]
            return unit == 0 ? ten : ten + " " + unitWords[unit]
        }
        if n < 1000 {
            let hundreds = n / 100
            let rest = n % 100
            let head = hundreds == 1 ? "yüz" : unitWords[hundreds] + " yüz"
            return rest == 0 ? head : head + " " + numberWords(rest)
        }
        let thousands = n / 1000
        let rest = n % 1000
        let head = thousands == 1 ? "bin" : numberWords(thousands) + " bin"
        return rest == 0 ? head : head + " " + numberWords(rest)
    }

    /// Locative suffix after digits for display, chosen by the spoken last word (03 §5.12):
    /// 1 → "'de", 3 → "'te", 6 → "'da", 10 → "'da", 20 → "'de", 30 → "'da", 40 → "'ta", 50 → "'de".
    public static func locativeSuffix(forNumber n: Int) -> String {
        // sıfır bir iki üç dört beş altı yedi sekiz dokuz
        let unitSuffixes = ["'da", "'de", "'de", "'te", "'te", "'te", "'da", "'de", "'de", "'da"]
        // – on yirmi otuz kırk elli altmış yetmiş seksen doksan
        let tenSuffixes = ["", "'da", "'de", "'da", "'ta", "'de", "'ta", "'te", "'de", "'da"]
        let a = Int(n.magnitude % 1000)
        if a % 10 != 0 {
            return unitSuffixes[a % 10]
        }
        if a == 0 {
            return n == 0 ? "'da" : "'de"      // sıfır / bin
        }
        if a % 100 != 0 {
            return tenSuffixes[(a / 10) % 10]
        }
        return "'de"                           // yüz
    }

    /// Display form: (15, 0) → "15'te", (15, 30) → "15:30'da", (9, 0) → "9'da", (0, 0) → "gece yarısı".
    public static func displayClockLocative(hour: Int, minute: Int) -> String {
        let h = clampHour(hour)
        let m = clampMinute(minute)
        if h == 0 && m == 0 {
            return "gece yarısı"
        }
        if m == 0 {
            return String(h) + locativeSuffix(forNumber: h)
        }
        return String(h) + ":" + AsistCalendar.pad(m, 2) + locativeSuffix(forNumber: m)
    }

    /// 24-hour spoken form (kept for tests/diagnostics): (15, 0) → "on beşte", (15, 30) → "on beş otuzda".
    public static func spokenClockLocative(hour: Int, minute: Int) -> String {
        let h = clampHour(hour)
        let m = clampMinute(minute)
        if h == 0 && m == 0 {
            return "gece yarısı"
        }
        if m == 0 {
            return numberWords(h) + bareLocative(h)
        }
        return numberWords(h) + " " + minuteWords(m) + bareLocative(m)
    }

    /// 12-hour clock with daypart for TTS (05b F12): (15,0) → "öğleden sonra üçte", (9,0) → "sabah dokuzda",
    /// (20,0) → "akşam sekizde", (12,0) → "öğlen on ikide", (15,30) → "öğleden sonra üç buçukta",
    /// (15,15) → "öğleden sonra üç on beşte", (2,0) → "gece ikide", (0,0) → "gece yarısı".
    /// Dayparts: 05:00–11:59 sabah · 12:00–12:59 öğlen · 13:00–17:59 öğleden sonra · 18:00–21:59 akşam · 22:00–04:59 gece.
    public static func spokenTimeOfDay(hour: Int, minute: Int) -> String {
        let h = clampHour(hour)
        let m = clampMinute(minute)
        if h == 0 && m == 0 {
            return "gece yarısı"
        }
        let part: String
        switch h {
        case 5...11: part = "sabah"
        case 12: part = "öğlen"
        case 13...17: part = "öğleden sonra"
        case 18...21: part = "akşam"
        default: part = "gece"
        }
        var h12 = h % 12
        if h12 == 0 {
            h12 = 12
        }
        let clock: String
        if m == 0 {
            clock = numberWords(h12) + bareLocative(h12)
        } else if m == 30 {
            clock = numberWords(h12) + " buçukta"
        } else {
            clock = numberWords(h12) + " " + minuteWords(m) + bareLocative(m)
        }
        return part + " " + clock
    }

    /// Spoken day word without time: "bugün", "yarın", "dün", "salı" (2–6 days ahead), "29 Ekim" (else; with the
    /// year when it differs from `now`'s year).
    public static func spokenDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let offset = dayOffset(from: now, to: date, calendar: calendar)
        if offset == 0 {
            return "bugün"
        }
        if offset == 1 {
            return "yarın"
        }
        if offset == -1 {
            return "dün"
        }
        if offset >= 2 && offset <= 6 {
            return TurkishText.lower(weekdayName(date, calendar: calendar))
        }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let month = TurkishDateFormatter.months[min(11, max(0, (c.month ?? 1) - 1))]
        var text = String(c.day ?? 1) + " " + month
        if let year = c.year, year != calendar.component(.year, from: now) {
            text += " " + String(year)
        }
        return text
    }

    /// "bugün öğleden sonra üçte", "yarın sabah dokuzda", "salı öğleden sonra üç buçukta", "29 Ekim sabah onda"
    /// (weekday names lowercase, month names capitalised, no "saat"). Screens keep the 24-hour clock.
    public static func spokenWhen(_ date: Date, now: Date, calendar: Calendar) -> String {
        let t = calendar.dateComponents([.hour, .minute], from: date)
        return spokenDay(date, now: now, calendar: calendar) + " "
            + spokenTimeOfDay(hour: t.hour ?? 0, minute: t.minute ?? 0)
    }

    /// Spoken duration for lead times and snoozes: 15 → "on beş dakika", 30 → "yarım saat", 60 → "bir saat",
    /// 90 → "bir buçuk saat", 1440 → "bir gün", 10080 → "bir hafta", 1500 → "bir gün bir saat".
    public static func spokenDuration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m == 0 {
            return "sıfır dakika"
        }
        if m == 30 {
            return "yarım saat"
        }
        if m == 90 {
            return "bir buçuk saat"
        }
        if m < 60 {
            return numberWords(m) + " dakika"
        }
        if m % 10080 == 0 {
            return numberWords(m / 10080) + " hafta"
        }
        let days = m / 1440
        let hours = (m % 1440) / 60
        let rest = m % 60
        var parts: [String] = []
        if days > 0 {
            parts.append(numberWords(days) + " gün")
        }
        if hours > 0 {
            parts.append(numberWords(hours) + " saat")
        }
        if rest > 0 {
            parts.append(numberWords(rest) + " dakika")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Confirmation after saving

    /// TTS/Siri confirmation after saving (03 §7.12 `tts.saved.*`). `headless` adds the title (Siri path).
    /// Never places a suffix directly after a placeholder (03 §5.12). Result is `dialogSafe`.
    public static func confirmation(for item: Item, projectName: String?, headless: Bool, lowConfidence: Bool,
                                    appliedDefaultTime: Bool, now: Date, calendar: Calendar) -> String {
        let title = spokenTitle(item)
        if headless && lowConfidence {
            return dialogSafe("“" + title + "” olarak kaydettim. Emin olmak için Asist'i aç.")
        }
        let tail = headless ? ": " + title + "." : "."
        let text: String
        switch item.kind {
        case .note:
            text = noteSentence(projectName: projectName, title: title, headless: headless)
        case .waiting:
            text = waitingSentence(item, tail: tail, now: now, calendar: calendar)
        case .reminder, .task:
            text = reminderOrTaskSentence(item, title: title, tail: tail, headless: headless,
                                          appliedDefaultTime: appliedDefaultTime, now: now, calendar: calendar)
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
            let isSpace = ch == " " || ch == "\n" || ch == "\t" || ch == "\r" || ch == "\u{00A0}"
            if isSpace {
                if !lastWasSpace {
                    out.append(" ")
                }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internal helpers (also used by AgendaBuilder)

    /// "her gün", "hafta içi her gün", "her hafta sonu", "her pazartesi", "her pazartesi ve perşembe",
    /// "her pazartesi, çarşamba ve cuma" for interval-1 daily/weekly rules; nil otherwise (monthly, yearly, interval > 1).
    static func spokenRecurrence(_ recurrence: Recurrence?) -> String? {
        guard let rule = recurrence, rule.interval == 1 else { return nil }
        switch rule.frequency {
        case .daily:
            return "her gün"
        case .weekly:
            let days = Array(Set((rule.weekdays ?? []).filter { (1...7).contains($0) })).sorted()
            if days.isEmpty {
                return nil
            }
            if days == [1, 2, 3, 4, 5] {
                return "hafta içi her gün"
            }
            if days == [6, 7] {
                return "her hafta sonu"
            }
            let names = days.map { TurkishText.lower(TurkishDateFormatter.weekdays[$0 - 1]) }
            return "her " + joinedWithVe(names)
        case .monthly, .yearly:
            return nil
        }
    }

    /// "a", "a ve b", "a, b ve c".
    static func joinedWithVe(_ parts: [String]) -> String {
        if parts.count <= 1 {
            return parts.first ?? ""
        }
        let head = parts.dropLast().joined(separator: ", ")
        return head + " ve " + (parts.last ?? "")
    }

    /// Calendar-day difference `date` − `now` (start of day to start of day).
    static func dayOffset(from now: Date, to date: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Capitalised weekday name ("Salı") of `date`.
    static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let iso = AsistCalendar.isoWeekday(date, calendar: calendar)
        return TurkishDateFormatter.weekdays[min(6, max(0, iso - 1))]
    }

    // MARK: - Private helpers

    private static func clampHour(_ hour: Int) -> Int { min(23, max(0, hour)) }

    private static func clampMinute(_ minute: Int) -> Int { min(59, max(0, minute)) }

    /// Minutes as spoken on a digital clock: 5 → "sıfır beş", 15 → "on beş".
    private static func minuteWords(_ minute: Int) -> String {
        if minute > 0 && minute < 10 {
            return "sıfır " + unitWords[minute]
        }
        return numberWords(minute)
    }

    /// Locative suffix without the apostrophe ("te", "da") for spoken words.
    private static func bareLocative(_ n: Int) -> String {
        String(locativeSuffix(forNumber: n).dropFirst())
    }

    private static func spokenTitle(_ item: Item) -> String {
        var title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.hasSuffix(".") {
            title.removeLast()
        }
        if title.isEmpty {
            return item.kind.label
        }
        return title
    }

    private static func noteSentence(projectName: String?, title: String, headless: Bool) -> String {
        let project = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = project.isEmpty ? "Not aldım" : project + " projesine not aldım"
        return headless ? base + ": " + title + "." : base + "."
    }

    private static func waitingSentence(_ item: Item, tail: String, now: Date, calendar: Calendar) -> String {
        guard let due = item.anchorDate else {
            return "Tamam, takip edeceğim" + tail
        }
        let offset = dayOffset(from: now, to: due, calendar: calendar)
        let day = spokenDay(due, now: now, calendar: calendar)
        let dayText = (offset >= -1 && offset <= 1) ? day : day + " günü"
        return "Tamam, " + dayText + " takip edeceğim" + tail
    }

    private static func reminderOrTaskSentence(_ item: Item, title: String, tail: String, headless: Bool,
                                               appliedDefaultTime: Bool, now: Date, calendar: Calendar) -> String {
        if appliedDefaultTime, let due = item.anchorDate {
            let expected = now.addingTimeInterval(3600)
            if abs(due.timeIntervalSince(expected)) <= 120 {
                return "Zaman söylemedin; bir saat sonra hatırlatacağım."
            }
            return "Zaman söylemedin; " + spokenWhen(due, now: now, calendar: calendar) + " hatırlatacağım."
        }
        if item.isEvent, let start = item.anchorDate {
            let when = spokenWhen(start, now: now, calendar: calendar)
            let leads = Array(Set(item.leadTimesMinutes.filter { $0 > 0 })).sorted(by: >)
            if leads.isEmpty {
                return "Tamam, " + when + " haber vereceğim" + tail
            }
            let leadText = joinedWithVe(leads.map { spokenDuration(minutes: $0) })
            return "Tamam, " + when + "; " + leadText + " önce haber vereceğim" + tail
        }
        if item.kind == .task {
            guard let due = item.anchorDate else {
                return headless ? "Görevlere ekledim: " + title + "." : "Görevlere ekledim."
            }
            let untimedToday = !item.hasTime && item.snoozedUntil == nil && calendar.isDate(due, inSameDayAs: now)
            let whenText = untimedToday ? "bugün içinde" : whenPhrase(item, due: due, now: now, calendar: calendar)
            return "Tamam, görevlere ekledim; " + whenText + " hatırlatacağım" + tail
        }
        guard let due = item.anchorDate else {
            return "Tamam, kaydettim" + tail
        }
        return "Tamam, " + whenPhrase(item, due: due, now: now, calendar: calendar) + " hatırlatacağım" + tail
    }

    /// Recurring interval-1 daily/weekly rule → "her pazartesi sabah dokuzda"; otherwise `spokenWhen(due)`.
    private static func whenPhrase(_ item: Item, due: Date, now: Date, calendar: Calendar) -> String {
        if item.snoozedUntil == nil, let recurring = spokenRecurrence(item.recurrence) {
            let t = calendar.dateComponents([.hour, .minute], from: due)
            return recurring + " " + spokenTimeOfDay(hour: t.hour ?? 0, minute: t.minute ?? 0)
        }
        return spokenWhen(due, now: now, calendar: calendar)
    }
}
