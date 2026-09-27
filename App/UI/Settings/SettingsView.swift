// WP11 — Ayarlar ana listesi (03 §4.11, 04 §5.2). Every screen is a value-based NavigationLink(value: Route…).
import SwiftUI
import AsistCore

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SigningMonitor.self) private var signing

    var body: some View {
        let settings = store.settings
        let deletedCount = store.recentlyDeleted.count
        List {
            Section {
                NavigationLink(value: Route.generalSettings) {
                    SettingsRowLabel(title: "Genel", subtitle: generalSubtitle(settings), systemImage: "person.crop.circle")
                }
                NavigationLink(value: Route.timeSettings) {
                    SettingsRowLabel(title: "Zamanlar", subtitle: timeSubtitle(settings), systemImage: "clock")
                }
                NavigationLink(value: Route.nagSettings) {
                    SettingsRowLabel(title: "Hatırlatma ısrarı", subtitle: nagSubtitle(settings), systemImage: Symbol.snooze)
                }
                NavigationLink(value: Route.summarySettings) {
                    SettingsRowLabel(title: "Özetler", subtitle: summarySubtitle(settings), systemImage: Symbol.briefing)
                }
                NavigationLink(value: Route.triggerSettings) {
                    SettingsRowLabel(title: "Tetikleyiciler",
                                     subtitle: "Arkaya Dokunma, Siri, ses kısma tuşu",
                                     systemImage: Symbol.backTap)
                }
                // WP13: destination link (no Route case needed; the stack's value-based destinations are unaffected).
                NavigationLink(destination: SmartModeSettingsView()) {
                    SettingsRowLabel(title: "Akıllı Mod", subtitle: smartSubtitle(settings),
                                     systemImage: Symbol.smartMode)
                }
            }

            Section {
                Button {
                    router.selectedTab = .projects
                } label: {
                    HStack {
                        Label("Projeler", systemImage: Symbol.project)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .foregroundStyle(Color.primary)
            }

            Section {
                NavigationLink(value: Route.dataSettings) {
                    SettingsRowLabel(title: "Veriler ve yedekler",
                                     subtitle: "Dışa aktar, içe aktar, günlük yedekler",
                                     systemImage: Symbol.export)
                }
                NavigationLink(value: Route.recentlyDeleted) {
                    HStack {
                        Label("Son silinenler", systemImage: "trash")
                        Spacer()
                        if deletedCount > 0 {
                            Text(String(deletedCount))
                                .foregroundStyle(Color.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Veri")
            }

            Section {
                NavigationLink(value: Route.appStatus) {
                    HStack {
                        Label("İmza ve izinler", systemImage: "checkmark.seal")
                        Spacer()
                        signingValue(now: Date())
                    }
                }
                NavigationLink(value: Route.diagnostics) {
                    Label("Tanılama", systemImage: "stethoscope")
                }
                Button {
                    router.showOnboarding = true
                } label: {
                    Label("Tanıtımı tekrar göster", systemImage: "sparkles")
                }
                .foregroundStyle(Color.primary)
            } header: {
                Text("Uygulama")
            } footer: {
                Text(SettingsFormat.versionText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ayarlar")
    }

    // MARK: Row summaries

    private func generalSubtitle(_ s: AppSettings) -> String {
        let name = s.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = s.speakConfirmations ? "sesli onay açık" : "sesli onay kapalı"
        if name.isEmpty {
            return "Hitap yok · " + voice
        }
        return "Hitap: " + name + " · " + voice
    }

    private func timeSubtitle(_ s: AppSettings) -> String {
        let work = "Mesai " + s.workStart.display + "–" + s.workEnd.display
        let quiet = "sessiz " + s.quietStart.display + "–" + s.quietEnd.display
        return work + " · " + quiet
    }

    private func nagSubtitle(_ s: AppSettings) -> String {
        let normal = "Normal: " + s.profileForNormal.label
        let high = "Önemli: " + s.profileForHigh.label
        let critical = "Kritik: " + s.profileForCritical.label
        return normal + " · " + high + " · " + critical
    }

    private func smartSubtitle(_ s: AppSettings) -> String {
        if !s.smartModeEnabled {
            return "Kapalı · Claude ile belirsiz cümleleri yorumlama"
        }
        return "Açık · " + SmartModeModelID.shortLabel(s.smartModeModel)
    }

    private func summarySubtitle(_ s: AppSettings) -> String {
        let brief = s.briefingEnabled ? "Brifing " + s.briefingTime.display : "Brifing kapalı"
        let eod = s.endOfDayEnabled ? "gün sonu " + s.endOfDayTime.display : "gün sonu kapalı"
        return brief + " · " + eod
    }

    @ViewBuilder
    private func signingValue(now: Date) -> some View {
        if let expiry = signing.expiryDate {
            let remaining = expiry.timeIntervalSince(now)
            let color: Color = remaining < 24 * 3600 ? Color.red : (remaining < 72 * 3600 ? Color.orange : Color.secondary)
            Text(SettingsFormat.remainingText(until: expiry, now: now))
                .font(.subheadline)
                .foregroundStyle(color)
        } else if let estimate = signing.estimatedExpiry(installDate: store.meta.installDate, now: now) {
            Text(SettingsFormat.remainingText(until: estimate, now: now) + " (tahmini)")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        } else {
            Text("bilinmiyor")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
    }
}

/// Title + one-line summary used by the settings lists.
struct SettingsRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// Deterministic Turkish date/version texts for the settings screens (no DateFormatter, no device locale).
enum SettingsFormat {
    static func monthName(_ month: Int) -> String {
        let names = TurkishDateFormatter.months
        guard month >= 1, month <= names.count else { return String(month) }
        return names[month - 1]
    }

    static func monthShort(_ month: Int) -> String {
        let names = TurkishDateFormatter.monthsShort
        guard month >= 1, month <= names.count else { return String(month) }
        return names[month - 1]
    }

    /// ISO weekday 1 (Pazartesi) … 7 (Pazar).
    static func weekdayName(iso: Int) -> String {
        let names = TurkishDateFormatter.weekdays
        guard iso >= 1, iso <= names.count else { return String(iso) }
        return names[iso - 1]
    }

    static func weekdayShort(iso: Int) -> String {
        let names = TurkishDateFormatter.weekdaysShort
        guard iso >= 1, iso <= names.count else { return String(iso) }
        return names[iso - 1]
    }

    /// "14:32"
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return AsistCalendar.pad(c.hour ?? 0, 2) + ":" + AsistCalendar.pad(c.minute ?? 0, 2)
    }

    /// "2 Ekim 14:32"
    static func dayMonthTime(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month], from: date)
        return String(c.day ?? 1) + " " + monthName(c.month ?? 1) + " " + clock(date, calendar: calendar)
    }

    /// "27 Eylül 2026"
    static func dayMonthYear(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(c.day ?? 1) + " " + monthName(c.month ?? 1) + " " + String(c.year ?? 0)
    }

    /// "27 Eyl 14:32"
    static func shortStamp(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month], from: date)
        return String(c.day ?? 1) + " " + monthShort(c.month ?? 1) + " " + clock(date, calendar: calendar)
    }

    /// "27.09 14:32:05"
    static func logStamp(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .hour, .minute, .second], from: date)
        let day = AsistCalendar.pad(c.day ?? 1, 2) + "." + AsistCalendar.pad(c.month ?? 1, 2)
        let time = AsistCalendar.pad(c.hour ?? 0, 2) + ":" + AsistCalendar.pad(c.minute ?? 0, 2)
            + ":" + AsistCalendar.pad(c.second ?? 0, 2)
        return day + " " + time
    }

    /// "yyyyMMdd" → "27.09.2026"; anything else is returned unchanged.
    static func dayKeyText(_ dayKey: String) -> String {
        let chars = Array(dayKey)
        guard chars.count == 8, chars.allSatisfy({ $0.isNumber }) else { return dayKey }
        let year = String(chars[0..<4])
        let month = String(chars[4..<6])
        let day = String(chars[6..<8])
        return day + "." + month + "." + year
    }

    /// "5 gün kaldı", "7 saat kaldı", "doldu".
    static func remainingText(until date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 {
            return "doldu"
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            return String(max(1, hours)) + " saat kaldı"
        }
        return String(hours / 24) + " gün kaldı"
    }

    static var appVersion: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value ?? "1.0.0"
    }

    /// CFBundleVersion as Int (CI run number); 0 when unknown (same rule as DataStore, 04 §3.6.4).
    static var buildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Int(raw) ?? 0
    }

    /// "Asist 1.0.0 (derleme 42)"
    static var versionText: String {
        "Asist " + appVersion + " (derleme " + String(buildNumber) + ")"
    }
}
