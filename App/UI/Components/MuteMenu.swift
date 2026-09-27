// WP9 (04 §5.3, signatures frozen; D32, 05b A3; 03 §7.12 home.mute.*): "Sessize al" toolbar menu and the Today
// banner "Sessiz: 11:30'a kadar ×". Changing `muteUntil` goes through store.updateSettings → onChange(.settings) →
// reconcile, so nags inside the window collapse to its end and first alerts in it are delivered silently.
import SwiftUI
import AsistCore

struct MuteMenu: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let isMuted = currentMuteEnd(now: Date()) != nil
        Menu {
            Section("Sessize al") {
                Button {
                    mute(minutes: 30)
                } label: {
                    Label("30 dk", systemImage: "clock")
                }
                Button {
                    mute(minutes: 60)
                } label: {
                    Label("1 saat", systemImage: "clock")
                }
                Button {
                    mute(minutes: 120)
                } label: {
                    Label("2 saat", systemImage: "clock")
                }
                Button {
                    muteUntilWorkEnd()
                } label: {
                    Label("Mesai sonuna kadar", systemImage: Symbol.endOfDay)
                }
            }
            if isMuted {
                Button(role: .destructive) {
                    unmute()
                } label: {
                    Label("Sessizi kapat", systemImage: "bell.fill")
                }
            }
        } label: {
            Image(systemName: Symbol.mute)
                .foregroundStyle(isMuted ? Color.asistToday : Color.asistAccent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isMuted ? "Sessiz açık" : "Sessize al")
    }

    private func currentMuteEnd(now: Date) -> Date? {
        guard let until = store.settings.muteUntil, until > now else { return nil }
        return until
    }

    @MainActor
    private func mute(minutes: Int) {
        let until = AsistCalendar.ceilToMinute(Date().addingTimeInterval(TimeInterval(minutes * 60)))
        apply(until)
    }

    @MainActor
    private func muteUntilWorkEnd() {
        let now = Date()
        let until = NagPlanner.muteUntilWorkEnd(now: now, settings: store.settings, calendar: AppTime.calendar)
        // A workEnd that is not in the future would mute nothing; fall back to 2 hours.
        let safe = until > now ? AsistCalendar.ceilToMinute(until) : AsistCalendar.ceilToMinute(now.addingTimeInterval(7200))
        apply(safe)
    }

    @MainActor
    private func apply(_ until: Date) {
        store.updateSettings { settings in
            settings.muteUntil = until
        }
        guard store.settings.muteUntil == until, store.canPersist else {
            toasts.show(store.lastSaveError ?? ItemQuickActions.saveFailedText, seconds: 6)
            Haptics.error()
            return
        }
        toasts.show("Sessiz: " + ClockDative.phrase(until, now: Date(), calendar: AppTime.calendar,
                                                     includeToday: false) + " kadar")
        Haptics.selection()
        AsistLog.info("Sessize alındı", .ui)
    }

    @MainActor
    private func unmute() {
        store.updateSettings { settings in
            settings.muteUntil = nil
        }
        toasts.show("Sessiz kapatıldı")
        Haptics.selection()
    }
}

/// Today banner while muted: "Sessiz: 11:30'a kadar" + × (cancels the window).
struct MuteBanner: View {
    let until: Date
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Image(systemName: Symbol.mute)
                .foregroundStyle(Color.asistToday)
                .accessibilityHidden(true)
            Text("Sessiz: " + ClockDative.phrase(until, now: Date(), calendar: AppTime.calendar, includeToday: false)
                 + " kadar")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Sessizi kapat")
        }
    }
}

/// Display clock + Turkish dative suffix chosen by the last spoken word: "11:30'a", "15:00'e", "12:00'ye",
/// "16:00'ya"; with a day prefix when not today ("Yarın 01:00'e", "Perşembe 10:00'a").
enum ClockDative {
    static func phrase(_ date: Date, now: Date, calendar: Calendar, includeToday: Bool) -> String {
        let clock = clockWithSuffix(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return includeToday ? "Bugün " + clock : clock
        }
        let day = TurkishDateFormatter.shortDateTime(date, now: now, calendar: calendar, includeTime: false)
        return day + " " + clock
    }

    static func clockWithSuffix(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let spoken = minute == 0 ? hour : minute
        return TurkishDateFormatter.hhmm(hour, minute) + suffix(forNumber: spoken)
    }

    /// sıfır→'a bir→'e iki→'ye üç→'e dört→'e beş→'e altı→'ya yedi→'ye sekiz→'e dokuz→'a;
    /// on→'a yirmi→'ye otuz→'a kırk→'a elli→'ye.
    static func suffix(forNumber n: Int) -> String {
        let units: [String] = ["'a", "'e", "'ye", "'e", "'e", "'e", "'ya", "'ye", "'e", "'a"]
        let tens: [String] = ["'a", "'a", "'ye", "'a", "'a", "'ye"]
        let value = Int(n.magnitude % 100)
        if value % 10 != 0 {
            return units[value % 10]
        }
        let ten = value / 10
        if ten < tens.count {
            return tens[ten]
        }
        return "'e"
    }
}
