// WP11 — Tetikleyiciler (03 §4.11, §5.1–5.2; 04 §5.2, §3.7 recipes). Volume-key trigger settings, listening
// settings and the setup guides. Settings edit pattern of §9 r22. Revision 4: first row opens WidgetGuideView.
import SwiftUI
import AppIntents
import AsistCore

struct TriggerSettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()
    @State private var showTip = true

    private static let silenceOptions: [Double] = [1.2, 1.8, 2.5, 3.5]

    var body: some View {
        Form {
            Section {
                // Revision 4 (07 §5.10): a view-destination link, so Route (integrator-owned) stays unchanged.
                NavigationLink(destination: WidgetGuideView()) {
                    SettingsRowLabel(title: "Kilit ekranı ve widget'lar",
                                     subtitle: "Asist Dinle düğmesi, Denetim Merkezi, ana ekran",
                                     systemImage: "lock.iphone")
                }
            } header: {
                Text("Tek dokunuşla dinle")
            } footer: {
                Text("iOS 18'de kilit ekranının altına ve Denetim Merkezi'ne “Asist Dinle” düğmesi eklenebilir; uygulama kapalıyken en hızlı yol budur.")
            }

            Section {
                NavigationLink(value: Route.guide(.backTap)) {
                    SettingsRowLabel(title: "Arkaya Dokunma: Asist Hızlı Kayıt",
                                     subtitle: "Önerilen · telefonun arkasına iki kez vur, konuş; Asist açılmadan kaydeder",
                                     systemImage: Symbol.backTap)
                }
                NavigationLink(value: Route.guide(.backTapListen)) {
                    SettingsRowLabel(title: "Arkaya Dokunma: Asist Dinle",
                                     subtitle: "Üç kez vur; Asist açılır ve dinler",
                                     systemImage: Symbol.mic)
                }
                NavigationLink(value: Route.guide(.siri)) {
                    SettingsRowLabel(title: "Siri komutları",
                                     subtitle: "“Asist'e kaydet” — kilitliyken bile",
                                     systemImage: "waveform.circle")
                }
                NavigationLink(value: Route.guide(.focus)) {
                    SettingsRowLabel(title: "Odak ve bildirim ayarları",
                                     subtitle: "İş odağında hatırlatmalar kaybolmasın",
                                     systemImage: "moon.circle")
                }
                NavigationLink(value: Route.guide(.banners)) {
                    SettingsRowLabel(title: "Bildirimler ekranda kalsın",
                                     subtitle: "Banner stili: Kalıcı",
                                     systemImage: "rectangle.topthird.inset.filled")
                }
            } header: {
                Text("Uygulama kapalıyken")
            } footer: {
                Text("iOS, uygulamaların ses tuşlarını arka planda veya kilit ekranında dinlemesine izin vermez. Uygulama kapalıyken en hızlı yollar: kilit ekranındaki “Asist Dinle” düğmesi, yan tuşa basılı tutup “Asist'e kaydet” demek (kilitliyken bile) ve telefonun arkasına dokunmak.")
            }

            Section {
                SiriTipView(intent: KaydetIntent(), isVisible: $showTip)
                ShortcutsLink()
                    .frame(maxWidth: .infinity, alignment: .center)
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Kestirmeler'i Aç", systemImage: "square.2.layers.3d")
                }
            } header: {
                Text("Siri ve Kestirmeler")
            }

            Section {
                Toggle("Ses kısma tuşuyla dinle", isOn: $s.volumeTriggerEnabled)
                Toggle("Ses seviyesini geri getir", isOn: $s.restoreVolumeAfterTrigger)
                    .disabled(!s.volumeTriggerEnabled)
            } header: {
                Text("Ses kısma tuşu (uygulama açıkken)")
            } footer: {
                Text("Uygulama açıkken ses kısma tuşuna 1 saniye içinde iki kez bas. Ses seviyesi iki kademe azalır; “geri getir” açıkken eski seviyeye döndürmeye çalışırım. Ses en düşükteyken çift basış algılanamaz; sesi biraz aç.")
            }

            Section {
                Picker("Sessizlik süresi", selection: $s.silenceSeconds) {
                    ForEach(silenceChoices, id: \.self) { seconds in
                        Text(silenceTitle(seconds)).tag(seconds)
                    }
                }
                Toggle("Yalnız cihaz içi tanıma", isOn: $s.onDeviceRecognitionOnly)
            } header: {
                Text("Dinleme")
            } footer: {
                Text("Sessizlik süresi: konuşman bitince kaydı sonlandırmadan önce ne kadar bekleyeyim. Cihaz içi tanıma açıkken ses internete gönderilmez; telefonda Türkçe model yoksa tanıma çalışmayabilir.")
            }
        }
        .navigationTitle("Tetikleyiciler")
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

    private var silenceChoices: [Double] {
        var options = TriggerSettingsView.silenceOptions
        if !options.contains(s.silenceSeconds) {
            options.append(s.silenceSeconds)
            options.sort()
        }
        return options
    }

    private func silenceTitle(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded())
        let text = String(tenths / 10) + "," + String(tenths % 10) + " sn"
        if tenths == 12 { return text + " (hızlı)" }
        if tenths == 18 { return text + " (normal)" }
        if tenths == 35 { return text + " (yavaş konuşurum)" }
        return text
    }
}
