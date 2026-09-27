// WP13 — Akıllı Mod ayarları (04 Appendix B.2 / revision 3; doc 06). Off by default. Settings edit pattern of
// 04 §5.2 / §9 r22: a @State copy synced both ways with two .onChange handlers. The API key never lives in
// AppSettings (it is not exported or backed up) — only in the Keychain through SmartModeClient.
import SwiftUI
import AsistCore

@MainActor
struct SmartModeSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var s = AppSettings()
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var testing = false
    @State private var testMessage: String? = nil
    @State private var testSucceeded = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Akıllı Mod", isOn: $s.smartModeEnabled)
                    .disabled(!hasKey && !s.smartModeEnabled)
                Toggle("Emin olamadığımda Akıllı Mod'a sor", isOn: $s.smartModeAutoOnLowConfidence)
                    .disabled(!s.smartModeEnabled)
            } footer: {
                Text(enableFooter)
            }

            Section {
                if hasKey {
                    Label("Anahtar bu iPhone'un anahtarlığında kayıtlı", systemImage: "key.fill")
                        .foregroundStyle(Color.green)
                }
                SecureField(keyPlaceholder, text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($keyFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveKey()
                    }
                Button {
                    saveKey()
                } label: {
                    Label("Anahtarı kaydet", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44)
                }
                .disabled(SmartModeClient.cleanedKey(keyDraft).isEmpty)
                if hasKey {
                    Button(role: .destructive) {
                        deleteKey()
                    } label: {
                        Label("Anahtarı sil", systemImage: "trash")
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                Text("API anahtarı")
            } footer: {
                Text("Anahtarı console.anthropic.com › API Keys bölümünden alabilirsin. Yalnızca bu iPhone'un anahtarlığında saklanır; yedeklere, dışa aktarılan dosyaya ve tanılama günlüğüne girmez.")
            }

            Section {
                Picker("Model", selection: $s.smartModeModel) {
                    ForEach(SmartModeModelID.all, id: \.self) { id in
                        Text(SmartModeModelID.label(id))
                            .tag(id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Model")
            } footer: {
                Text("Opus 5 en isabetli yorumu yapar; Haiku 4.5 en hızlı ve en ucuzudur. Siri ile kayıtta Akıllı Mod en çok 8 saniye beklenir, cevap gelmezse cihaz içi sonuç kalır.")
            }

            Section {
                Button {
                    runTest()
                } label: {
                    HStack(spacing: 10) {
                        Label(testButtonTitle, systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if testing {
                            ProgressView()
                        }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(testing || !hasKey)
                if let message = testMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(testSucceeded ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("Kayıtlı anahtar ve seçili modelle küçük bir deneme isteği gönderir (kayıtlarından hiçbir şey gönderilmez).")
            }

            Section {
                Text(privacyText)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Gizlilik")
            }
        }
        .navigationTitle("Akıllı Mod")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            s = store.settings
            hasKey = SmartModeClient.shared.hasKey
            let normalized = SmartModeModelID.normalized(s.smartModeModel)
            if normalized != s.smartModeModel {
                s.smartModeModel = normalized
            }
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

    // MARK: - Texts

    private var keyPlaceholder: String {
        hasKey ? "Yeni anahtarla değiştir" : "sk-ant-…"
    }

    private var testButtonTitle: String {
        testing ? "Deneniyor…" : "Bağlantıyı dene"
    }

    private var enableFooter: String {
        if !hasKey {
            return "Akıllı Mod varsayılan olarak kapalıdır. Açmak için önce aşağıya Anthropic API anahtarını gir."
        }
        return "Açıkken, cihaz içi çözümleme bir cümleden emin olamadığında Claude'a sorarım: kart önce cihaz içi sonuçla açılır, daha iyi bir yorum gelirse kart “Akıllı Mod ile yorumlandı” olarak güncellenir. Takip mesajı taslağı ve proje notu özeti yalnız sen düğmeye bastığında hazırlanır."
    }

    private var privacyText: String {
        "Akıllı Mod kapalıyken hiçbir şey gönderilmez. Açıkken şu veriler Anthropic'e (Claude API) gönderilir: emin olamadığım cümlenin kendisi ve cihaz içi yorumu, o anki tarih-saat ve saat dilimi, varsayılan saat ayarların, proje ve yer adların; “Akıllı taslak”a bastığında o takibin başlığı, kişisi, proje adı, notları ve hitap adın; “Özetle”ye bastığında o projenin adı ve not metinleri. Başka kayıt, konum ya da rehber bilgisi gönderilmez. Kullanım ücreti kendi Anthropic hesabına yansır."
    }

    // MARK: - Actions

    private func saveKey() {
        let key = SmartModeClient.cleanedKey(keyDraft)
        guard !key.isEmpty else { return }
        keyFocused = false
        guard SmartModeClient.shared.saveKey(key) else {
            toasts.show("Anahtar kaydedilemedi. Tekrar dene.", seconds: 6)
            Haptics.error()
            return
        }
        keyDraft = ""
        hasKey = true
        testMessage = nil
        if key.hasPrefix("sk-ant-") {
            toasts.show("API anahtarı kaydedildi")
        } else {
            toasts.show("Kaydedildi; Anthropic anahtarları genelde “sk-ant-” ile başlar.", seconds: 6)
        }
        Haptics.success()
    }

    private func deleteKey() {
        SmartModeClient.shared.deleteKey()
        hasKey = SmartModeClient.shared.hasKey
        testMessage = nil
        if s.smartModeEnabled {
            s.smartModeEnabled = false
        }
        toasts.show("API anahtarı silindi")
        Haptics.selection()
    }

    private func runTest() {
        guard !testing else { return }
        testing = true
        testMessage = nil
        let model = SmartModeModelID.normalized(s.smartModeModel)
        Task { @MainActor in
            let result = await SmartModeClient.shared.testConnection(model: model)
            testing = false
            switch result {
            case .success(let duration):
                testSucceeded = true
                testMessage = "Bağlantı başarılı · " + SmartModeModelID.shortLabel(model) + " · " + duration
                Haptics.success()
            case .failure(let error):
                testSucceeded = false
                testMessage = error.userMessage
                Haptics.warning()
            }
        }
    }
}
