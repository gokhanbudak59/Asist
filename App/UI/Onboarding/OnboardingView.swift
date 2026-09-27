// WP11 — İlk açılış: 3 sayfa (05b A10, 04 §5.2, 03 §4.12 condensed).
// (1) vaat + bildirim izni + "Kalıcı" banner ipucu + yedekten geri yükleme (03 §9 r25),
// (2) mikrofon/konuşma izni + canlı deneme "1 dakika sonra su içmeyi hatırlat",
// (3) hızlı erişim: Siri, Arkaya Dokunma rehberi A, Kestirmeler, Odak satırı + rehber E, test bildirimi (30 sn).
// "Başla" and "Atla" set onboardingCompleted = true and router.showOnboarding = false. Work/quiet hours keep
// their defaults (Ayarlar › Zamanlar). Toasts are covered by this full-screen cover, so results are shown inline.
import SwiftUI
import AppIntents
import AsistCore

struct OnboardingView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PermissionCenter.self) private var permissions

    @State private var page = 0
    @State private var busy = false
    @State private var voiceAsked = false
    @State private var tryResult: String?
    @State private var tryDone = false
    @State private var testMessage: String?
    @State private var importMessage: String?
    @State private var showImporter = false

    private static let lastPage = 2
    private static let trySentence = "1 dakika sonra su içmeyi hatırlat"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage
                        .tag(0)
                    voicePage
                        .tag(1)
                    quickAccessPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                bottomBar
            }
            .background(Color.asistBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Atla") {
                        finish()
                    }
                    .foregroundStyle(Color.secondary)
                }
            }
            .navigationDestination(for: GuideKind.self) { kind in
                GuideView(kind: kind)
            }
            .dataImportFlow(isPresented: $showImporter) { message in
                importMessage = message
            }
            .task {
                await permissions.refresh()
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Page 1 — promise + notifications

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(symbol: "bell.badge.fill", title: "Asist'e hoş geldin")
                Text("Aklına geleni söyle, gerisini ben hatırlarım.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    bullet("Konuşarak kaydet — kalıp ezberlemen gerekmez.", symbol: Symbol.mic)
                    bullet("Uygulama kapalıyken de hatırlatırım.", symbol: "iphone")
                    bullet("“Yaptım” diyene kadar peşini bırakmam — ama seni gece rahatsız etmem.", symbol: Symbol.snooze)
                }

                card {
                    Text("Bildirimler")
                        .font(.headline)
                    Text("Hatırlatmaların zamanında çalması için bildirim izni gerekiyor. Uygulama kapalıyken ve telefon kilitliyken de bildirim gelir.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    notificationControl
                }

                if permissions.notification == .authorized {
                    card {
                        Label("Hatırlatmalar ekranda kalsın", systemImage: "rectangle.topthird.inset.filled")
                            .font(.headline)
                        Text("Ayarlar › Bildirimler › Asist › Banner Stili › Kalıcı seç. Böylece hatırlatma sen dokunana kadar ekranın üstünde kalır.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if permissions.alertsPersistent {
                            Label("Kalıcı seçili", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.asistDone)
                        } else {
                            Button {
                                PermissionCenter.openNotificationSettings()
                            } label: {
                                Label("Bildirim ayarlarını aç", systemImage: "gearshape")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daha önce Asist kullandıysan yedeğini geri yükleyebilirsin.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        importMessage = nil
                        showImporter = true
                    } label: {
                        Label("Yedekten geri yükle", systemImage: Symbol.importData)
                            .font(.subheadline)
                    }
                    .disabled(!store.isLoaded)
                    if let message = importMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Metrics.padding)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var notificationControl: some View {
        switch permissions.notification {
        case .authorized:
            Label("Bildirimler açık", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.asistDone)
        case .denied:
            Text("Bildirimler kapalı — hatırlatmalar çalmaz. Ayarlar'dan açabilirsin.")
                .font(.subheadline)
                .foregroundStyle(Color.asistOverdue)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                PermissionCenter.openNotificationSettings()
            } label: {
                Text("Ayarları Aç")
            }
            .buttonStyle(PrimaryButtonStyle(tint: .asistAccent, filled: false))
        case .notDetermined, .unknown:
            Button {
                requestNotifications()
            } label: {
                Text("Bildirimlere İzin Ver")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    // MARK: Page 2 — microphone / speech + live test

    private var voicePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(symbol: "mic.circle.fill", title: "Mikrofon ve konuşma")
                Text("Söylediklerini yazıya çevirmek için mikrofon ve konuşma tanıma izni istiyorum. Yalnızca sen istediğinde dinlerim; ses kaydı saklanmaz.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                card {
                    voiceControl
                }

                card {
                    Text("Hadi deneyelim")
                        .font(.headline)
                    Text("Şu hatırlatmayı şimdi kurayım: “" + OnboardingView.trySentence + "”")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = tryResult {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.asistDone)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("1 dakika içinde bir bildirim gelecek. Bildirimi basılı tut ve “✓ Yaptım”a dokun — ya da hiçbir şey yapma, birkaç dakika sonra tekrar hatırlatayım.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !tryDone {
                        Button {
                            runTry()
                        } label: {
                            Text("Deneme hatırlatmasını kur")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: .asistAccent, filled: false))
                        .disabled(busy || !notificationsUsable)
                        if !notificationsUsable {
                            Text("Önce ilk sayfada bildirimlere izin ver.")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Text("Sesle denemek için tanıtımdan sonra Bugün ekranındaki mikrofona dokun ve aynı cümleyi söyle.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Metrics.padding)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var voiceControl: some View {
        if permissions.microphoneGranted && permissions.speechGranted {
            Label("Mikrofon ve konuşma tanıma açık", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.asistDone)
        } else if voiceAsked {
            Text("Sorun değil, klavyeyle ve Siri ile kullanabilirsin.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                PermissionCenter.openAppSettings()
            } label: {
                Text("Ayarları Aç")
            }
            .buttonStyle(PrimaryButtonStyle(tint: .asistAccent, filled: false))
        } else {
            Button {
                requestVoice()
            } label: {
                Text("İzin Ver")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private var hoursLine: String {
        let settings = store.settings
        let work = "Mesai " + settings.workStart.display + "–" + settings.workEnd.display
        let quiet = "sessiz saatler " + settings.quietStart.display + "–" + settings.quietEnd.display
        return work + ", " + quiet + ". Ayarlar › Zamanlar'dan değiştirebilirsin."
    }

    private var notificationsUsable: Bool {
        permissions.notification != .denied && permissions.notification != .notDetermined
    }

    // MARK: Page 3 — quick access

    private var quickAccessPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(symbol: "bolt.circle.fill", title: "Hızlı erişim")
                Text("Uygulama açıkken ses kısma tuşuna iki kez bas. Uygulama kapalıyken şu yolları kullan:")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                card {
                    Label("Siri: “Asist'e kaydet” — kilitliyken bile", systemImage: "waveform.circle")
                        .font(.headline)
                    Text("Siri “Ne kaydedeyim?” diye sorar; cümleni söylersin, uygulama açılmadan kaydederim.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: GuideKind.siri) {
                        Label("Siri komutları", systemImage: "chevron.right")
                            .font(.subheadline)
                    }
                }

                card {
                    Label("Telefonun arkasına iki kez dokun", systemImage: Symbol.backTap)
                        .font(.headline)
                    Text("Bir kez kurarsın; sonra arkaya iki kez vurup konuşman yeter, Asist açılmadan kaydeder.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: GuideKind.backTap) {
                        Label("Kurulum adımları", systemImage: "chevron.right")
                            .font(.subheadline)
                    }
                    ShortcutsLink()
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                card {
                    Label("İşte Odak kullanıyorsan Asist'i izinli uygulamalara ekle.", systemImage: "moon.circle")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: GuideKind.focus) {
                        Label("Nasıl yapılır?", systemImage: "chevron.right")
                            .font(.subheadline)
                    }
                    Button {
                        runTestNotification()
                    } label: {
                        Label("Test bildirimi (30 sn)", systemImage: "paperplane")
                            .font(.subheadline)
                    }
                    .disabled(busy)
                    if let message = testMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Kayıtların yalnızca bu telefonda saklanır; uygulamayı kapatmak veya telefonu yeniden başlatmak hiçbir şeyi silmez. Asist'i silersen veriler de silinir; bu yüzden haftada bir yedek almanı hatırlatırım. İmzanın süresi dolmadan seni uyarırım.")
                    Text(hoursLine)
                }
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.padding)
            .padding(.bottom, 40)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack {
            if page < OnboardingView.lastPage {
                Button {
                    withAnimation {
                        page = min(OnboardingView.lastPage, page + 1)
                    }
                } label: {
                    Text("Devam")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    finish()
                } label: {
                    Text("Başla")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.top, 8)
        .padding(.bottom, Metrics.padding)
    }

    // MARK: Building blocks

    private func pageHeader(symbol: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(Color.asistAccent)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func bullet(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.asistAccent)
        }
        .font(.body)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.asistCard, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
    }

    // MARK: Actions

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

    private func requestVoice() {
        busy = true
        Task { @MainActor in
            _ = await permissions.requestVoice()
            await permissions.refresh()
            voiceAsked = true
            busy = false
        }
    }

    /// Real record through the headless capture path (persists and awaits the reconcile, D34). The voice overlay
    /// cannot run here: VoiceCoordinator refuses to listen while onboarding is shown (§3.6.7).
    private func runTry() {
        busy = true
        Task { @MainActor in
            let sentence = await AppEnvironment.shared.capture.captureHeadless(text: OnboardingView.trySentence,
                                                                              source: CaptureSource.keyboard)
            tryResult = sentence
            tryDone = store.canPersist
            busy = false
        }
    }

    private func runTestNotification() {
        busy = true
        Task { @MainActor in
            testMessage = await TestNotificationSender.send(afterSeconds: 30)
            busy = false
        }
    }

    private func finish() {
        store.updateSettings { settings in
            settings.onboardingCompleted = true
        }
        router.showOnboarding = false
    }
}
