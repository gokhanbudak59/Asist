// WP11 — Zamanlar (03 §4.11 "Zamanlar" + parser time words, 04 §5.2). Settings edit pattern of §9 r22.
import SwiftUI
import AsistCore

struct TimeSettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()

    private static let leadOptions: [Int] = [0, 5, 10, 15, 30]

    var body: some View {
        Form {
            Section {
                ForEach(1...7, id: \.self) { day in
                    workdayRow(day)
                }
            } header: {
                Text("İş günleri")
            } footer: {
                Text("Mesai başı, brifing, gün sonu ve takip soruları iş günlerine göre çalışır. En az bir iş günü seçili kalmalı.")
            }

            Section {
                SettingsClockRow(title: "Mesai başı", time: $s.workStart)
                SettingsClockRow(title: "Mesai bitişi", time: $s.workEnd)
                SettingsClockRow(title: "Tatil günü sabahı", time: $s.offDayStart)
                if s.workEnd <= s.workStart {
                    Label("Mesai bitişi başlangıçtan sonra olmalı.", systemImage: Symbol.overdue)
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
            } header: {
                Text("Mesai")
            } footer: {
                Text("“Yarın sabah” ertelemesi ve önceki günlerden kalan işler iş günlerinde mesai başında, diğer günlerde “tatil günü sabahı” saatinde hatırlatılır.")
            }

            Section {
                SettingsClockRow(title: "Başlangıç", time: $s.quietStart)
                SettingsClockRow(title: "Bitiş", time: $s.quietEnd)
            } header: {
                Text("Sessiz saatler")
            } footer: {
                Text("Bu saatlerde ısrar etmem; aradaki hatırlatmalar sessiz saat bitince tek bildirim olur. Açıkça o saate kurduğun hatırlatma ve kendi seçtiğin erteleme yine çalar.")
            }

            Section {
                SettingsClockRow(title: "Saat söylenmezse", time: $s.defaultDayTime)
                SettingsClockRow(title: "Sabah", time: $s.sabah)
                SettingsClockRow(title: "Öğleden önce", time: $s.ogledenOnce)
                SettingsClockRow(title: "Öğle", time: $s.ogle)
                SettingsClockRow(title: "Öğleden sonra", time: $s.ogledenSonra)
                SettingsClockRow(title: "Akşamüstü", time: $s.aksamustu)
                SettingsClockRow(title: "Akşam", time: $s.aksam)
                SettingsClockRow(title: "Gece", time: $s.gece)
                Toggle("“Saat 3” = 15:00 (1–6 arası öğleden sonra)", isOn: $s.ambiguousHoursPM)
            } header: {
                Text("Günün bölümleri")
            } footer: {
                Text("“Yarın akşam” veya “salı sabahı” gibi saatsiz ifadeler bu saatlere kurulur. Gün söyleyip saat söylemezsen “Saat söylenmezse” saati kullanılır.")
            }

            Section {
                SettingsClockRow(title: "Takip soru saati", time: $s.followUpAskTime)
                Stepper(value: $s.waitingDefaultWorkdays, in: 1...10) {
                    LabeledContent("Tarihsiz takip", value: String(s.waitingDefaultWorkdays) + " iş günü sonra")
                }
                SettingsClockRow(title: "Tarihsiz takipte sorma saati", time: $s.waitingDefaultTime)
            } header: {
                Text("Takip")
            } footer: {
                Text("“Mehmet raporu gönderecek” gibi kayıtlarda son tarih varsa o gün takip saatinde, yoksa belirtilen iş günü sonra “Geldi mi?” diye sorarım.")
            }

            Section {
                Picker("Toplantı ön uyarısı", selection: $s.eventDefaultLeadMinutes) {
                    ForEach(leadChoices, id: \.self) { minutes in
                        Text(leadTitle(minutes)).tag(minutes)
                    }
                }
            } header: {
                Text("Etkinlikler")
            } footer: {
                Text("Toplantı, görüşme, ziyaret, FAT/SAT gibi kayıtlar başlangıçta bir kez ve bu süre önce hatırlatılır; ısrar etmem. Başlangıçtan 2 saat sonra kendiliğinden kapanır.")
            }
        }
        .navigationTitle("Zamanlar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            s = store.settings
        }
        .onChange(of: store.settings) { _, latest in
            if latest != s {
                s = latest
            }
        }
        .onChange(of: s) { _, new in
            if new != store.settings {
                store.updateSettings { $0 = new }
            }
        }
    }

    // MARK: Workdays (buttons instead of Binding(get:set:) toggles, §9 r22)

    @ViewBuilder
    private func workdayRow(_ day: Int) -> some View {
        let selected = s.workdays.contains(day)
        let isLast = selected && s.workdays.count <= 1
        Button {
            toggleWorkday(day)
        } label: {
            HStack {
                Text(SettingsFormat.weekdayName(iso: day))
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.asistAccent)
                        .font(.body.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isLast)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func toggleWorkday(_ day: Int) {
        var days = s.workdays
        if let index = days.firstIndex(of: day) {
            guard days.count > 1 else { return }       // 05a #8: never empty
            days.remove(at: index)
        } else {
            days.append(day)
        }
        s.workdays = Array(Set(days.filter { (1...7).contains($0) })).sorted()
    }

    // MARK: Event lead time

    private var leadChoices: [Int] {
        var options = TimeSettingsView.leadOptions
        if !options.contains(s.eventDefaultLeadMinutes) {
            options.append(s.eventDefaultLeadMinutes)
            options.sort()
        }
        return options
    }

    private func leadTitle(_ minutes: Int) -> String {
        if minutes <= 0 {
            return "Yok"
        }
        if minutes % 60 == 0 {
            return String(minutes / 60) + " saat"
        }
        return String(minutes) + " dk"
    }
}

/// Hour/minute picker bound to a `ClockTime`. Keeps its own `Date` state synced both ways with two .onChange
/// handlers (no Binding(get:set:), §9 r22).
struct SettingsClockRow: View {
    let title: String
    @Binding var time: ClockTime
    @State private var date: Date

    init(title: String, time: Binding<ClockTime>) {
        self.title = title
        self._time = time
        self._date = State(initialValue: SettingsClockRow.date(for: time.wrappedValue))
    }

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
            .onAppear {
                let expected = SettingsClockRow.date(for: time)
                if SettingsClockRow.clockTime(from: date) != time {
                    date = expected
                }
            }
            .onChange(of: time) { _, newTime in
                if SettingsClockRow.clockTime(from: date) != newTime {
                    date = SettingsClockRow.date(for: newTime)
                }
            }
            .onChange(of: date) { _, newDate in
                let picked = SettingsClockRow.clockTime(from: newDate)
                if picked != time {
                    time = picked
                }
            }
    }

    static func date(for time: ClockTime) -> Date {
        AsistCalendar.date(on: Date(), at: time, calendar: AppTime.calendar)
    }

    static func clockTime(from date: Date) -> ClockTime {
        let c = AppTime.calendar.dateComponents([.hour, .minute], from: date)
        let hour = min(23, max(0, c.hour ?? 0))
        let minute = min(59, max(0, c.minute ?? 0))
        return ClockTime(hour, minute)
    }
}
