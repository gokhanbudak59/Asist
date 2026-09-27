// WP11 — Özetler: sabah brifingi, gün sonu, haftalık yedek hatırlatması (03 §3.9–3.10, §4.11; 04 §5.2).
// Settings edit pattern of §9 r22.
import SwiftUI
import AsistCore

struct SummarySettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()

    var body: some View {
        Form {
            Section {
                Toggle("Sabah brifingi", isOn: $s.briefingEnabled)
                Group {
                    SettingsClockRow(title: "Saat", time: $s.briefingTime)
                    Toggle("Yalnız iş günleri", isOn: $s.briefingWorkdaysOnly)
                    Toggle("Boş günlerde de gönder", isOn: $s.briefingWhenEmpty)
                    Toggle("Dokununca sesli oku", isOn: $s.briefingTapSpeaks)
                }
                .disabled(!s.briefingEnabled)
            } header: {
                Text("Sabah brifingi")
            } footer: {
                Text("Güne başlarken bugünkü işleri ve gecikenleri tek bildirimde özetlerim. Bildirimdeki “Sesli oku” her zaman okur.")
            }

            Section {
                Toggle("Gün sonu hatırlatması", isOn: $s.endOfDayEnabled)
                Group {
                    SettingsClockRow(title: "Saat", time: $s.endOfDayTime)
                    Toggle("Yalnız iş günleri", isOn: $s.endOfDayWorkdaysOnly)
                }
                .disabled(!s.endOfDayEnabled)
                Toggle("Taşırken hafta sonunu atla", isOn: $s.moveSkipsWeekend)
            } header: {
                Text("Gün sonu")
            } footer: {
                Text("Açık kalan işleri sorar; “Sonraki iş gününe taşı” ile saatleri korunarak taşınır. Hafta sonunu atlama açıkken cuma akşamı taşınan işler pazartesiye gider.")
            }

            Section {
                Toggle("Haftalık yedek hatırlatması", isOn: $s.backupReminderEnabled)
                Group {
                    Picker("Gün", selection: $s.backupReminderWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(SettingsFormat.weekdayName(iso: day)).tag(day)
                        }
                    }
                    SettingsClockRow(title: "Saat", time: $s.backupReminderTime)
                }
                .disabled(!s.backupReminderEnabled)
            } header: {
                Text("Yedek")
            } footer: {
                Text("Asist her gün kendiliğinden yedek alır (Dosyalar › Bu iPhone'da › Asist › Yedekler). Haftada bir bu klasörü bilgisayarına veya iCloud Drive'a kopyalaman için hatırlatırım; telefon kaybolursa veriler böyle kurtarılır.")
            }
        }
        .navigationTitle("Özetler")
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
}
