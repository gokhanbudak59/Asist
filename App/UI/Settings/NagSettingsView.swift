// WP11 — Hatırlatma ısrarı (03 §3.4, §4.11; 04 §5.2, §6.4). Profile per priority + read-only preview timeline
// computed with NagPlanner.chain (the same function the planner uses). Settings edit pattern of §9 r22.
import SwiftUI
import AsistCore

struct NagSettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()

    var body: some View {
        Form {
            Section {
                profilePicker("Düşük", selection: $s.profileForLow)
                profilePicker("Normal", selection: $s.profileForNormal)
                profilePicker("Önemli", selection: $s.profileForHigh)
                profilePicker("Kritik", selection: $s.profileForCritical)
            } header: {
                Text("Önceliğe göre ısrar")
            } footer: {
                Text("“Acil, önemli, mutlaka” dersen kayıt Önemli; “çok acil, kritik, sakın unutma” dersen Kritik olur. Tek bir kaydın ısrarını kayıt detayından değiştirebilirsin.")
            }

            Section {
                ForEach(NagProfileKind.selectable, id: \.self) { kind in
                    previewRow(kind)
                }
            } header: {
                Text("Önizleme: bugün 15:00'e kurulan hatırlatma")
            } footer: {
                Text("“✓ Yaptım” diyene ya da erteleyene kadar böyle devam eder. Takip kayıtları iş günlerinde takip saatinde bir kez sorulur; toplantı gibi etkinlikler yalnız başlangıçta (ve ön uyarıyla) hatırlatılır.")
            }

            Section {
                Toggle("Kritik işler sessiz saatte de ısrar etsin", isOn: $s.criticalIgnoresQuietHours)
            } footer: {
                Text("Kapalıyken gece ısrar etmem; sessiz saat bitince hatırlatırım. Toplantıdaysan Bugün ekranındaki zil simgesinden “Sessize al”ı kullan.")
            }

            Section {
                Picker("Uygulama simgesi rozeti", selection: $s.badgeMode) {
                    Text("Gecikenler").tag(BadgeMode.overdue)
                    Text("Gecikenler + bugün").tag(BadgeMode.overdueAndToday)
                    Text("Kapalı").tag(BadgeMode.off)
                }
                Toggle("Kilit ekranında konuyu göster", isOn: $s.lockScreenShowsContent)
            } header: {
                Text("Bildirim görünümü")
            } footer: {
                Text("Kapalıyken kilit ekranında yalnızca “Asist hatırlatması” yazar; konu kilidi açınca görünür. iPhone'un “Önizlemeleri Göster” ayarı da bunu etkiler.")
            }
        }
        .navigationTitle("Hatırlatma ısrarı")
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

    // MARK: Pickers

    private func profilePicker(_ title: String, selection: Binding<NagProfileKind>) -> some View {
        Picker(title, selection: selection) {
            ForEach(NagProfileKind.selectable, id: \.self) { kind in
                Text(kind.label).tag(kind)
            }
        }
    }

    // MARK: Preview timeline

    private func previewRow(_ kind: NagProfileKind) -> some View {
        let lines = NagSettingsView.previewLines(kind: kind, settings: s, now: Date(), calendar: AppTime.calendar)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(kind.label)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(usedBy(kind))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            Text(NagSettingsView.summary(kind))
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Normal, Düşük" — which priorities currently use this profile.
    private func usedBy(_ kind: NagProfileKind) -> String {
        var names: [String] = []
        if s.profileForLow == kind { names.append("Düşük") }
        if s.profileForNormal == kind { names.append("Normal") }
        if s.profileForHigh == kind { names.append("Önemli") }
        if s.profileForCritical == kind { names.append("Kritik") }
        return names.isEmpty ? "kullanılmıyor" : names.joined(separator: ", ")
    }

    static func summary(_ kind: NagProfileKind) -> String {
        switch kind {
        case .nazik:
            return "+10 dk, +30 dk, +1,5 saat; sonra mesai içinde 2 saatte bir. Günde en fazla 6."
        case .israrci:
            return "+5, +15, +30, +60 dk; sonra mesai içinde saatte bir, akşam tekrar yok. Günde en fazla 10."
        case .birakmaz:
            return "+3, +6, +10, +15 dk; sonra 15 dakikada bir (sessiz saatler hariç). Günde en fazla 30."
        case .takip:
            return "İş günlerinde takip saatinde günde bir kez."
        case .etkinlik:
            return "Yalnız başlangıçta bir kez."
        }
    }

    /// Up to 3 day lines: "Bugün: 15:00 · 15:10 · 15:30 · 16:30", "Yarın: 08:30 · 10:30 · …".
    /// The mute window is ignored (the preview shows the profile, not today's "Sessize al").
    static func previewLines(kind: NagProfileKind, settings: AppSettings, now: Date, calendar: Calendar) -> [String] {
        var clean = settings
        clean.muteUntil = nil
        let anchor = AsistCalendar.date(on: now, at: ClockTime(15, 0), calendar: calendar)
        let chain = NagPlanner.chain(anchor: anchor,
                                     profile: clean.nagProfiles[kind],
                                     profileKind: kind,
                                     isCritical: kind == .birakmaz,
                                     settings: clean,
                                     now: now,
                                     calendar: calendar)
        let anchorDay = calendar.startOfDay(for: anchor)
        var lines: [String] = []
        var currentKey = ""
        var currentTimes: [String] = []
        var currentLabel = ""
        var truncated = false

        func flush() {
            guard !currentTimes.isEmpty else { return }
            var text = currentLabel + ": " + currentTimes.joined(separator: " · ")
            if truncated {
                text += " …"
            }
            lines.append(text)
        }

        for date in chain.prefix(200) {
            let key = AsistCalendar.dayKey(date, calendar: calendar)
            if key != currentKey {
                flush()
                if lines.count >= 3 {
                    currentTimes = []
                    break
                }
                currentKey = key
                currentTimes = []
                truncated = false
                let offset = calendar.dateComponents([.day], from: anchorDay, to: calendar.startOfDay(for: date)).day ?? 0
                currentLabel = dayLabel(offset: offset, date: date, calendar: calendar)
            }
            if currentTimes.count < 8 {
                currentTimes.append(SettingsFormat.clock(date, calendar: calendar))
            } else {
                truncated = true
            }
        }
        flush()
        if lines.isEmpty {
            lines.append("15:00")
        }
        return lines
    }

    private static func dayLabel(offset: Int, date: Date, calendar: Calendar) -> String {
        if offset == 0 { return "Bugün" }
        if offset == 1 { return "Yarın" }
        return SettingsFormat.weekdayName(iso: AsistCalendar.isoWeekday(date, calendar: calendar))
    }
}
