// API: App/UI/Settings/CalendarSettingsView.swift
// Revision 4 — F7 (07 §10.1, §10.5): Ayarlar › Takvim — access status + "Takvime eriş" / "Ayarları Aç",
// "Bugün ekranında göster" and the "Öncesinde hatırlat" lead chips (settings edit pattern §9 r22).
import SwiftUI
import AsistCore

@MainActor
struct CalendarSettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()
    @State private var requesting = false

    init() {}

    var body: some View {
        let access = CalendarService.shared.access
        Form {
            Section {
                HStack(spacing: 10) {
                    Label("Takvim izni", systemImage: "calendar")
                    Spacer(minLength: 8)
                    Text(access.userText)
                        .font(.subheadline)
                        .foregroundStyle(access == .granted ? Color.green : Color.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                if access == .notDetermined {
                    Button {
                        requestAccess()
                    } label: {
                        HStack(spacing: 10) {
                            if requesting {
                                ProgressView()
                                    .tint(Color.white)
                            }
                            Text("Takvime eriş")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Color.teal))
                    .disabled(requesting)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else if access != .granted {
                    Button {
                        PermissionCenter.openAppSettings()
                    } label: {
                        Label("Ayarları Aç", systemImage: "gearshape")
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                Text("Erişim")
            } footer: {
                Text(accessFooter(access))
            }

            Section {
                Toggle("Bugün ekranında göster", isOn: $s.calendarOnToday)
                    .frame(minHeight: 44)
            } footer: {
                Text("Bugünkü toplantıların Bugün ekranında TAKVİM bölümünde görünür; geçmiş olanlar soluk gösterilir.")
            }

            Section {
                ChipRow {
                    ForEach(AppSettings.calendarLeadChoices, id: \.self) { minutes in
                        Chip(title: CalendarSettingsText.leadLabel(minutes),
                             isSelected: s.calendarLeadMinutes == minutes) {
                            s.calendarLeadMinutes = minutes
                        }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Öncesinde hatırlat")
            } footer: {
                Text("Toplantı satırındaki “" + CalendarSettingsText.leadLabel(s.calendarLeadMinutes)
                     + " önce” düğmesi Asist'te bir hatırlatma kurar: toplantıdan bu kadar önce ve başladığında çalar, iki saat sonra kendiliğinden kapanır.")
            }

            Section {
                Label("Asist takvimini yalnız okur; takvimine hiçbir şey eklemez ve değiştirmez. Takvim bilgileri telefondan çıkmaz.",
                      systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Takvim")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            s = store.settings
            CalendarService.shared.refresh(now: Date())
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

    private func accessFooter(_ access: CalendarAccess) -> String {
        switch access {
        case .granted:
            return "Bugünkü toplantıların okunabiliyor."
        case .notDetermined:
            return "“Takvime eriş”e dokununca iPhone izin sorar; “Tam Erişim” seç."
        case .denied:
            return "İzin verilmedi. iPhone Ayarları › Asist › Takvimler › Tam Erişim ile açabilirsin."
        case .restricted:
            return "Takvim erişimi bu telefonda kısıtlanmış (Ekran Süresi veya kurum profili)."
        case .writeOnly:
            return "Asist yalnız okumak ister. iPhone Ayarları › Asist › Takvimler › Tam Erişim seç."
        }
    }

    private func requestAccess() {
        guard !requesting else { return }
        requesting = true
        Task { @MainActor in
            let granted = await CalendarService.shared.requestAccess()
            requesting = false
            if granted {
                Haptics.success()
            }
        }
    }
}

@MainActor
enum CalendarSettingsText {
    /// "Bugün ekranında toplantılar · Açık" / "… · İzin verilmedi" / "Kapalı".
    static func subtitle(settings: AppSettings) -> String {
        guard settings.calendarOnToday else { return "Kapalı" }
        switch CalendarService.shared.access {
        case .granted:
            return "Bugün ekranında toplantılar · Açık"
        case .notDetermined:
            return "Bugün ekranında toplantılar · İzin sorulmadı"
        case .denied, .restricted, .writeOnly:
            return "Bugün ekranında toplantılar · İzin verilmedi"
        }
    }

    /// 5 → "5 dk", 60 → "1 saat", 90 → "90 dk".
    nonisolated static func leadLabel(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m >= 60 && m % 60 == 0 {
            return String(m / 60) + " saat"
        }
        return String(m) + " dk"
    }
}
