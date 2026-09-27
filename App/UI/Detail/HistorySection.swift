// WP10 — Kayıt geçmişi (03 §4.8, §7.12 history.*).
import SwiftUI
import AsistCore

/// "27 Eyl 10:14 · sesle oluşturuldu" lines, newest first. Shows the newest 8, then "Tümünü göster (n)".
@MainActor
struct HistorySection: View {
    let item: Item

    @State private var showAll = false

    private static let collapsedCount = 8

    /// Explicit: private @State storage must not narrow the memberwise initializer's access level.
    init(item: Item) {
        self.item = item
    }

    var body: some View {
        let entries: [HistoryEntry] = Array(item.history.reversed())
        let visible: [HistoryEntry] = showAll ? entries : Array(entries.prefix(HistorySection.collapsedCount))
        let calendar = AppTime.calendar
        let now = Date()
        return Section {
            if entries.isEmpty {
                Text("Henüz geçmiş yok.")
                    .foregroundStyle(Color.secondary)
            }
            ForEach(0..<visible.count, id: \.self) { index in
                Text(HistorySection.line(visible[index], item: item, now: now, calendar: calendar))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            if !showAll && entries.count > HistorySection.collapsedCount {
                Button("Tümünü göster (\(entries.count))") {
                    showAll = true
                }
            }
        } header: {
            SectionHeader(title: "GEÇMİŞ")
        }
    }

    /// "27 Eyl 10:14" (year added when it differs from the current year).
    static func stamp(_ date: Date, now: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let month = comps.month ?? 1
        let names = TurkishDateFormatter.monthsShort
        let monthName = (month >= 1 && month <= names.count) ? names[month - 1] : ""
        var text = String(comps.day ?? 1) + " " + monthName
        if let year = comps.year, year != calendar.component(.year, from: now) {
            text += " " + String(year)
        }
        return text + " " + TurkishDateFormatter.time(date, calendar: calendar)
    }

    static func line(_ entry: HistoryEntry, item: Item, now: Date, calendar: Calendar) -> String {
        stamp(entry.date, now: now, calendar: calendar) + " · " + describe(entry, item: item)
    }

    static func describe(_ entry: HistoryEntry, item: Item) -> String {
        let detail = entry.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base: String
        switch entry.event {
        case .created:
            base = item.source.historyLabel + " oluşturuldu"
        case .edited:
            base = "düzenlendi"
        case .rescheduled:
            return detail.isEmpty ? "zamanı değiştirildi" : "zamanı değiştirildi → " + detail
        case .snoozed:
            return detail.isEmpty ? "ertelendi" : "ertelendi → " + detail
        case .done:
            base = "tamamlandı"
        case .occurrenceDone:
            base = "bu seferlik tamamlandı"
        case .occurrenceMissed:
            base = "kaçırılan tekrar sıradakine geçti"
        case .reopened:
            base = "yeniden açıldı"
        case .deleted:
            base = "silindi"
        case .restored:
            base = "geri getirildi"
        case .movedEndOfDay:
            base = "gün sonunda sonraki iş gününe taşındı"
        case .smartMode:
            base = "Akıllı Mod ile düzenlendi"
        case .locationFired:
            base = "konum hatırlatması çaldı"
        case .other:
            return detail.isEmpty ? "değişiklik" : detail
        }
        if detail.isEmpty { return base }
        if detail == "otomatik kapandı" { return detail }
        return base + " (" + detail + ")"
    }
}
