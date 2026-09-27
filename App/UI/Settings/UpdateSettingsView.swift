// API: App/UI/Settings/UpdateSettingsView.swift
// Revision 4 — F3 (07 §6.1, §6.4): Ayarlar › Güncelleme. Installed vs. published build, "Şimdi kontrol et",
// the automatic-check toggle (settings edit pattern §9 r22) and the Sideloadly update steps with the IPA link.
import SwiftUI
import UIKit
import AsistCore

struct UpdateSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var s = AppSettings()

    init() {}

    var body: some View {
        let checker = UpdateChecker.shared
        let checking = checker.isChecking
        let meta = store.meta
        let calendar = AppTime.calendar
        let status = UpdateSettingsText.statusLine(state: checker.state, meta: meta)
        Form {
            Section {
                LabeledContent("Yüklü") {
                    Text(SettingsFormat.appVersion + " (derleme " + String(SettingsFormat.buildNumber) + ")")
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Son yayınlanan") {
                        Text(UpdateSettingsText.publishedText(meta: meta, calendar: calendar))
                            .monospacedDigit()
                    }
                    if let notes = meta.latestBuildNotes, !notes.isEmpty, meta.latestBuildSeen > 0 {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                HStack(spacing: 10) {
                    if checking {
                        ProgressView()
                    } else {
                        Image(systemName: status.systemImage)
                            .foregroundStyle(status.color)
                            .accessibilityHidden(true)
                    }
                    Text(checking ? "Kontrol ediliyor…" : status.text)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(checking ? Color.secondary : status.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                if let last = meta.lastUpdateCheckAt {
                    Text("Son kontrol: " + SettingsFormat.dayMonthTime(last, calendar: calendar))
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            } header: {
                Text("Sürüm")
            }

            Section {
                Button {
                    runCheck()
                } label: {
                    HStack(spacing: 10) {
                        if checking {
                            ProgressView()
                                .tint(Color.white)
                        }
                        Text(checking ? "Kontrol ediliyor…" : "Şimdi kontrol et")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(checking || !store.isLoaded)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Otomatik kontrol et (12 saatte bir)", isOn: $s.updateCheckEnabled)
                    .frame(minHeight: 44)
            } footer: {
                Text("Açıkken Asist, uygulama açıldığında en fazla 12 saatte bir yeni sürüm olup olmadığına bakar ve varsa Bugün ekranında haber verir.")
            }

            Section {
                stepRow(1, "Bilgisayarda yeni **Asist.ipa** dosyasını indir:")
                Text(verbatim: UpdateManifest.ipaURLString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    copyLink()
                } label: {
                    Label("Bağlantıyı kopyala", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }
                if let ipaURL = URL(string: UpdateManifest.ipaURLString) {
                    ShareLink(item: ipaURL, subject: Text("Asist yeni sürüm"),
                              message: Text("Bilgisayarda indir, Sideloadly ile aynı Apple ID ile yükle.")) {
                        Label("Bağlantıyı gönder (e-posta, WhatsApp…)", systemImage: "paperplane")
                            .frame(minHeight: 44)
                    }
                }
                stepRow(2, "**Sideloadly**'yi aç, Asist.ipa'yı pencereye sürükle.")
                stepRow(3, "**Aynı Apple ID** ile **Start**'a bas. Farklı Apple ID ile kayıtların görünmez.")
                stepRow(4, "**Asist'i silme**: üstüne yükle, kayıtların korunur.")
                stepRow(5, "Kurulum bitince **Asist'i bir kez aç**; hatırlatmalar yeniden kurulur.")
                stepRow(6, "Kurulum hata verirse aynı sayfadaki **Asist-imzasiz.ipa** dosyasını dene.")
                if let pageURL = URL(string: UpdateManifest.releasePageURLString) {
                    Link(destination: pageURL) {
                        Label("Sürüm sayfasını aç (GitHub)", systemImage: "safari")
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                Text("Nasıl güncellenir?")
            } footer: {
                Text("Kontrol yalnızca GitHub'daki sürüm dosyasını okur; kayıtların veya kişisel bilgilerin gönderilmez. Telefondaki uygulama kendiliğinden güncellenmez; yeni sürümü Sideloadly ile yüklemen gerekir.")
            }
        }
        .navigationTitle("Güncelleme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            s = store.settings
            UpdateChecker.shared.checkIfDue(store: store, now: Date())
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

    /// Numbered instruction row; `text` is a literal with **bold** markdown.
    private func stepRow(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(number))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.asistAccent)
                .frame(width: 26, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    @MainActor
    private func runCheck() {
        let store = self.store
        Task { @MainActor in
            let checker = UpdateChecker.shared
            await checker.checkNow(store: store)
            switch checker.state {
            case .finished:
                Haptics.success()
            case .failed:
                Haptics.error()
            case .idle, .checking:
                break
            }
        }
    }

    @MainActor
    private func copyLink() {
        UIPasteboard.general.string = UpdateManifest.ipaURLString
        toasts.show("Bağlantı kopyalandı")
        Haptics.selection()
    }
}

/// Texts shared by the Settings row (integrator §11.10), this screen and the Bugün band.
enum UpdateSettingsText {
    /// Status line of the SÜRÜM section.
    struct StatusLine {
        let text: String
        let systemImage: String
        let color: Color
    }

    /// "Yeni: #61" when available; else "Güncel" when lastUpdateCheckAt != nil; else "Kapalı" when disabled; else "—".
    static func value(meta: AppMeta, settings: AppSettings) -> String {
        if isAvailable(meta: meta) {
            return "Yeni: #" + String(meta.latestBuildSeen)
        }
        if meta.lastUpdateCheckAt != nil {
            return "Güncel"
        }
        if !settings.updateCheckEnabled {
            return "Kapalı"
        }
        return "—"
    }

    /// UpdatePolicy.isUpdateAvailable(meta.latestBuildSeen, SettingsFormat.buildNumber).
    static func isAvailable(meta: AppMeta) -> Bool {
        UpdatePolicy.isUpdateAvailable(latestBuild: meta.latestBuildSeen, installedBuild: SettingsFormat.buildNumber)
    }

    /// "derleme 61 · 27 Eylül 14:32" / "derleme 61" / "Henüz bilinmiyor".
    static func publishedText(meta: AppMeta, calendar: Calendar) -> String {
        guard meta.latestBuildSeen > 0 else { return "Henüz bilinmiyor" }
        var text = "derleme " + String(meta.latestBuildSeen)
        if let date = meta.latestBuildDate {
            text += " · " + SettingsFormat.dayMonthTime(date, calendar: calendar)
        }
        return text
    }

    /// Failure of this session first, then the persisted result.
    static func statusLine(state: UpdateCheckState, meta: AppMeta) -> StatusLine {
        if case .failed(let message) = state {
            return StatusLine(text: "Kontrol edilemedi: " + message, systemImage: "wifi.exclamationmark",
                              color: Color.red)
        }
        if isAvailable(meta: meta) {
            return StatusLine(text: "Yeni sürüm hazır", systemImage: "arrow.down.circle.fill", color: Color.orange)
        }
        if meta.lastUpdateCheckAt != nil {
            return StatusLine(text: "Güncel", systemImage: "checkmark.circle.fill", color: Color.green)
        }
        return StatusLine(text: "Henüz kontrol edilmedi", systemImage: "questionmark.circle", color: Color.secondary)
    }
}
