// WP11 — Genel ayarlar (03 §4.11 "Genel", D18). Settings edit pattern of 04 §5.2 / §9 r22:
// a @State copy synced both ways with two .onChange handlers; no hand-written Binding(get:set:).
import SwiftUI
import AsistCore

struct GeneralSettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var s = AppSettings()
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Adın (boş bırakabilirsin)", text: $nameDraft)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        commitName()
                    }
            } header: {
                Text("Hitap")
            } footer: {
                Text("Bugün ekranında “Günaydın, Gökhan” gibi selamlarda kullanılır.")
            }

            Section {
                Toggle("Onayları sesli söyle (kulaklık / araçta)", isOn: $s.speakConfirmations)
                Toggle("Hoparlörden de söyle", isOn: $s.speakConfirmationsOnSpeaker)
                    .disabled(!s.speakConfirmations)
                Picker("Konuşma hızı", selection: $s.ttsRate) {
                    Text("Yavaş").tag(TTSRate.slow)
                    Text("Normal").tag(TTSRate.normal)
                    Text("Hızlı").tag(TTSRate.fast)
                }
            } header: {
                Text("Sesli onay")
            } footer: {
                Text("Kayıt onayları yalnızca kulaklık, Bluetooth veya araç bağlıyken sesli söylenir; toplantıda telefon hoparlörü susar. “Hoparlörden de söyle” açıksa her zaman söylerim. “Bugün ne var” gibi sorulara verdiğim cevaplar her zaman okunur.")
            }

            Section {
                Picker("Otomatik kaydet", selection: $s.autoSaveSeconds) {
                    Text("Kapalı").tag(0)
                    Text("8 sn").tag(8)
                    Text("12 sn").tag(12)
                    Text("20 sn").tag(20)
                    Text("30 sn").tag(30)
                }
                Picker("Zaman hiç söylenmezse", selection: $s.noTimeBehavior) {
                    Text("Sor").tag(NoTimeBehavior.ask)
                    Text("1 saat sonra").tag(NoTimeBehavior.inOneHour)
                    Text("Bu akşam").tag(NoTimeBehavior.thisEvening)
                    Text("Yarın sabah").tag(NoTimeBehavior.tomorrowMorning)
                }
            } header: {
                Text("Onay kartı")
            } footer: {
                Text("Emin olduğum kayıtları kartta geri sayımdan sonra kendiliğinden kaydederim; karta dokunursan sayım durur. Hatırlatmada zaman yoksa “Sor” seçiliyken kart cevapsız kapanırsa 1 saat sonra hatırlatırım; Siri ile kayıtta da 1 saat sonra.")
            }
        }
        .navigationTitle("Genel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            s = store.settings
            nameDraft = store.settings.userName
        }
        .onChange(of: store.settings) { _, latest in
            if latest != s {
                s = latest
            }
            if !nameFocused && nameDraft != latest.userName {
                nameDraft = latest.userName
            }
        }
        .onChange(of: s) { _, new in
            if new != store.settings {
                store.updateSettings { $0 = new }
            }
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused {
                commitName()
            }
        }
        .onDisappear {
            commitName()
        }
    }

    /// Text is committed on submit / focus loss / disappear, not per keystroke (one save + one reconcile).
    private func commitName() {
        let trimmed = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard store.isLoaded, trimmed != store.settings.userName else { return }
        store.updateSettings { $0.userName = trimmed }
    }
}
