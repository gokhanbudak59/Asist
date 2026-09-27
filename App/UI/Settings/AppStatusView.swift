// WP11 — Uygulama durumu: imza bitişi (D17, 05a #28), bildirim/ses izinleri (03 §9), "Banner Stili: Kalıcı"
// (05b A9), veri dosyası ve yazan derleme (D35). 04 §5.2. Revision 4: widget veri paylaşımı (07 §5.10).
import SwiftUI
import AsistCore

struct AppStatusView: View {
    @Environment(SigningMonitor.self) private var signing
    @Environment(PermissionCenter.self) private var permissions
    @Environment(ReminderEngine.self) private var engine
    @Environment(DataStore.self) private var store

    @State private var showHowTo = false
    @State private var busy = false

    var body: some View {
        let now = Date()
        let calendar = AppTime.calendar
        List {
            signingSection(now: now, calendar: calendar)
            notificationSection
            voiceSection
            widgetSection(calendar: calendar)
            dataSection(calendar: calendar)
            Section {
                LabeledContent("Sürüm", value: SettingsFormat.appVersion)
                LabeledContent("Derleme", value: String(SettingsFormat.buildNumber))
            } header: {
                Text("Uygulama")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("İmza ve izinler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissions.refresh()
        }
        .refreshable {
            // `.refreshable` has no inherited actor context: only an awaited call into the main actor here.
            await refreshPermissions()
        }
    }

    @MainActor
    private func refreshPermissions() async {
        await permissions.refresh()
    }

    // MARK: Signing

    @ViewBuilder
    private func signingSection(now: Date, calendar: Calendar) -> some View {
        Section {
            HStack {
                Text("İmza bitişi")
                Spacer()
                signingValue(now: now, calendar: calendar)
            }
            LabeledContent("İmza türü", value: signingKind)
            DisclosureGroup("Yeniden yükleme nasıl yapılır?", isExpanded: $showHowTo) {
                ForEach(AppStatusView.howToSteps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(index + 1) + ".")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(AppStatusView.howToSteps[index])
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("İmza")
        } footer: {
            Text("Ücretsiz Apple ID ile imza 7 gün geçerlidir. Bitmeden 48, 24 ve 4 saat önce bildirim gönderirim. Süre dolarsa Asist açılmaz ama verilerin telefonda kalır; aynı Apple ID ile üstüne yükleyince her şey geri gelir.")
        }
    }

    @ViewBuilder
    private func signingValue(now: Date, calendar: Calendar) -> some View {
        if let expiry = signing.expiryDate {
            let remaining = expiry.timeIntervalSince(now)
            let color: Color = remaining < 24 * 3600 ? Color.red : (remaining < 72 * 3600 ? Color.orange : Color.secondary)
            Text(SettingsFormat.dayMonthTime(expiry, calendar: calendar) + " · " + SettingsFormat.remainingText(until: expiry, now: now))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        } else if let estimate = signing.estimatedExpiry(installDate: store.meta.installDate, now: now) {
            Text(SettingsFormat.dayMonthTime(estimate, calendar: calendar) + " (tahmini)")
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.trailing)
        } else {
            Text("bilinmiyor")
                .foregroundStyle(Color.secondary)
        }
    }

    private var signingKind: String {
        guard let profile = signing.profile else { return "okunamadı" }
        if profile.looksLikeFreeAppleID {
            return "Ücretsiz Apple ID (7 gün)"
        }
        return "Geliştirici hesabı"
    }

    /// Short KURULUM.md summary (01c §3.4, 05b A1).
    static let howToSteps: [String] = [
        "İş bilgisayarında Sideloadly'yi aç; iPhone'u USB kabloyla veya aynı Wi-Fi ağıyla bağla.",
        "Aynı Asist.ipa dosyasını (ya da GitHub'daki daha yenisini) her zamanki Apple ID ile yükle. Asist'i telefondan silme; veriler korunur.",
        "Sideloadly günlüğünde paket kimliğinin com.gokhanbudak.asist olduğunu kontrol et. Farklıysa yükleme yapma.",
        "Yükleme bitince Asist'i bir kez aç; hatırlatmalar yeniden kurulur.",
        "Öneri: her pazartesi 08:30'da yenile ya da Sideloadly'de otomatik yenilemeyi aç."
    ]

    // MARK: Notifications

    @ViewBuilder
    private var notificationSection: some View {
        Section {
            HStack {
                Text("Bildirim izni")
                Spacer()
                notificationStateText
            }
            NavigationLink(value: Route.guide(.banners)) {
                HStack {
                    Text("Banner Stili")
                    Spacer()
                    if permissions.alertsPersistent {
                        Text("Kalıcı").foregroundStyle(Color.asistDone)
                    } else {
                        Text("Geçici").foregroundStyle(Color.orange)
                    }
                }
            }
            LabeledContent("Önizlemeleri Göster", value: permissions.previewsAlways ? "Her Zaman" : "Kısıtlı")
            LabeledContent("Zamana duyarlı", value: permissions.timeSensitiveEnabled ? "Açık" : "Kapalı")
            LabeledContent("Zamanlanmış özet", value: permissions.scheduledSummaryOn ? "Asist özette" : "Kapalı")
            if permissions.notification == .notDetermined {
                Button {
                    requestNotifications()
                } label: {
                    Label("Bildirimlere İzin Ver", systemImage: "bell.badge")
                }
                .disabled(busy)
            }
            Button {
                PermissionCenter.openNotificationSettings()
            } label: {
                Label("Ayarları Aç", systemImage: "gearshape")
            }
        } header: {
            Text("Bildirimler")
        } footer: {
            Text(notificationFooter)
        }
    }

    @ViewBuilder
    private var notificationStateText: some View {
        switch permissions.notification {
        case .authorized:
            Text("Açık").foregroundStyle(Color.asistDone)
        case .denied:
            Text("Kapalı").foregroundStyle(Color.red)
        case .notDetermined:
            Text("Sorulmadı").foregroundStyle(Color.orange)
        case .unknown:
            Text("Bilinmiyor").foregroundStyle(Color.secondary)
        }
    }

    private var notificationFooter: String {
        var lines: [String] = []
        if permissions.notification == .denied {
            lines.append("Bildirimler kapalı — hatırlatmalar çalmayacak. Ayarlar'dan aç.")
        }
        if !permissions.alertsPersistent {
            lines.append("“Kalıcı” banner stili, hatırlatmayı sen dokunana kadar ekranda tutar.")
        }
        if !permissions.timeSensitiveEnabled {
            lines.append("Zamana duyarlı bildirimler kapalı; Odak modunda önemli işler gecikebilir.")
        }
        if permissions.scheduledSummaryOn {
            lines.append("Asist bildirimleri özete alınıyor; anında teslim edilmesi için özetten çıkar.")
        }
        if let report = engine.lastReport {
            lines.append("Son planlamada zamana duyarlı gönderim: " + (report.timeSensitiveAllowed ? "açık." : "kapalı."))
        }
        return lines.joined(separator: "\n")
    }

    private func requestNotifications() {
        busy = true
        Task { @MainActor in
            let granted = await permissions.requestNotifications()
            await permissions.refresh()
            if granted {
                await AppEnvironment.shared.engine.reconcile(reason: "permission")
            }
            busy = false
        }
    }

    // MARK: Voice

    @ViewBuilder
    private var voiceSection: some View {
        Section {
            LabeledContent("Mikrofon", value: permissions.microphoneGranted ? "İzin var" : "İzin yok")
            LabeledContent("Konuşma tanıma", value: permissions.speechGranted ? "İzin var" : "İzin yok")
            if !permissions.microphoneGranted || !permissions.speechGranted {
                Button {
                    requestVoice()
                } label: {
                    Label("İzin iste", systemImage: Symbol.mic)
                }
                .disabled(busy)
                Button {
                    PermissionCenter.openAppSettings()
                } label: {
                    Label("Ayarları Aç", systemImage: "gearshape")
                }
            }
        } header: {
            Text("Ses")
        } footer: {
            Text("Mikrofon izni yoksa klavyeyle ve Siri ile (“Asist'e kaydet”) kayıt yapabilirsin.")
        }
    }

    private func requestVoice() {
        busy = true
        Task { @MainActor in
            _ = await permissions.requestVoice()
            await permissions.refresh()
            busy = false
        }
    }

    // MARK: Widgets (revision 4, 07 §5.10)

    @ViewBuilder
    private func widgetSection(calendar: Calendar) -> some View {
        let writer = WidgetSnapshotWriter.shared
        let available = writer.isAvailable
        let sharingValue: String = available ? "Açık" : "Kapalı"
        let lastWrite: String = writer.lastWriteAt.map { SettingsFormat.shortStamp($0, calendar: calendar) } ?? "—"
        Section {
            HStack {
                Text("Widget veri paylaşımı")
                Spacer()
                Text(sharingValue)
                    .foregroundStyle(available ? Color.asistDone : Color.orange)
            }
            LabeledContent("Son güncelleme", value: available ? lastWrite : "—")
            NavigationLink(destination: WidgetGuideView()) {
                Label("Kilit ekranı ve widget'lar", systemImage: "lock.iphone")
            }
        } header: {
            Text("Widget'lar")
        } footer: {
            Text(WidgetGuideView.statusText(available: available) + "\n" + WidgetGuideView.volumeKeyNote)
        }
    }

    // MARK: Data

    @ViewBuilder
    private func dataSection(calendar: Calendar) -> some View {
        let meta = store.meta
        let build = SettingsFormat.buildNumber
        Section {
            LabeledContent("Veri dosyası", value: store.isLoaded ? "okundu" : "henüz okunamadı")
            if let issue = store.loadIssue {
                Label(AppStatusView.loadIssueText(issue), systemImage: Symbol.overdue)
                    .font(.subheadline)
                    .foregroundStyle(Color.orange)
            }
            if let error = store.lastSaveError {
                Label(error, systemImage: Symbol.overdue)
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }
            LabeledContent("Son kayıt", value: meta.lastSavedAt.map { SettingsFormat.shortStamp($0, calendar: calendar) } ?? "—")
            LabeledContent("Dosyayı yazan derleme", value: meta.writerBuild > 0 ? String(meta.writerBuild) : "bilinmiyor")
            LabeledContent("Bu derleme", value: build > 0 ? String(build) : "bilinmiyor")
            if let install = meta.installDate {
                LabeledContent("İlk kurulum", value: SettingsFormat.dayMonthYear(install, calendar: calendar))
            }
            if build > 0 && meta.writerBuild > build {
                Label("Veriler daha yeni bir Asist sürümüyle yazılmış. Daha yeni IPA'yı yükle; bir kopyası Yedekler klasöründe.",
                      systemImage: Symbol.overdue)
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }
        } header: {
            Text("Veri")
        } footer: {
            Text(store.isLoaded
                 ? "Kayıtların yalnızca bu telefonda saklanır; her değişiklik anında diske yazılır."
                 : "Telefon yeniden başladıktan sonra ilk kilit açılışına kadar veriler okunamaz; kilidi açınca kendiliğinden okunur.")
        }
    }

    static func loadIssueText(_ issue: StoreLoadIssue) -> String {
        switch issue {
        case .restoredFromPrevious:
            return "Veri dosyası okunamadı; bir önceki sağlam sürümden açıldı."
        case .restoredFromBackup(let dayKey):
            return "Veri dosyası okunamadı; " + SettingsFormat.dayKeyText(dayKey) + " tarihli yedekten geri yüklendi."
        case .startedEmptyAfterCorruption:
            return "Veri dosyası okunamadı ve yedek bulunamadı; boş başlandı. Bozuk dosyanın kopyası saklandı."
        case .partialRecovery(let dropped):
            return String(dropped) + " kayıt okunamadı; ham dosyanın kopyası saklandı."
        case .newerWriter(let build):
            return "Veriler daha yeni bir sürümle (derleme " + String(build) + ") yazılmış; kopyası Yedekler klasöründe."
        }
    }
}
