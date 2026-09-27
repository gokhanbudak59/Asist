// WP11 — Kurulum rehberleri (03 §4.13; 04 §3.7 recipes, §5.2; 05b A8/A9/B11). Guide A = headless
// "Asist Hızlı Kayıt" (Dikte Et → Asist'e Kaydet), A-alt = "Asist Dinle", C = Siri, E = Odak, "Kalıcı" banners.
import SwiftUI
import AppIntents
import AsistCore

struct GuideView: View {
    let kind: GuideKind

    @Environment(PermissionCenter.self) private var permissions
    @State private var showTip = true
    @State private var testMessage: String?
    @State private var testRunning = false

    struct Step {
        let symbol: String
        let text: String
    }

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (RouteDestination.swift).
    init(kind: GuideKind) {
        self.kind = kind
    }

    var body: some View {
        let steps = GuideView.steps(for: kind)
        let tips = GuideView.tips(for: kind)
        List {
            Section {
                Text(GuideView.intro(for: kind))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(steps.indices, id: \.self) { index in
                    stepRow(number: index + 1, step: steps[index])
                }
            } header: {
                Text("Adımlar")
            }

            actionSection

            if !tips.isEmpty {
                Section {
                    ForEach(tips.indices, id: \.self) { index in
                        Label {
                            Text(GuideView.rich(tips[index]))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(Color.asistToday)
                        }
                    }
                } header: {
                    Text("İpuçları")
                } footer: {
                    Text("Menü adları iOS sürümüne göre küçük farklılık gösterebilir.")
                }
            } else {
                Section {
                    EmptyView()
                } footer: {
                    Text("Menü adları iOS sürümüne göre küçük farklılık gösterebilir.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(GuideView.title(for: kind))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissions.refresh()
        }
    }

    // MARK: Rows

    private func stepRow(number: Int, step: Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.asistAccent)
                    .frame(width: 32, height: 32)
                Text(String(number))
                    .font(.headline)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(GuideView.rich(step.text))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: step.symbol)
                .font(.title3)
                .foregroundStyle(Color.asistAccent)
                .frame(width: 32)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Adım \(number). ") + Text(GuideView.rich(step.text)))
    }

    @ViewBuilder
    private var actionSection: some View {
        switch kind {
        case .backTap, .backTapListen:
            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Kestirmeler'i Aç", systemImage: "square.2.layers.3d")
                        .font(.headline)
                }
                ShortcutsLink()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .siri:
            Section {
                SiriTipView(intent: KaydetIntent(), isVisible: $showTip)
                ShortcutsLink()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .focus:
            Section {
                Button {
                    PermissionCenter.openNotificationSettings()
                } label: {
                    Label("Bildirim ayarlarını aç", systemImage: "bell.badge")
                }
                Button {
                    runTest()
                } label: {
                    Label("Test bildirimi (30 sn)", systemImage: "paperplane")
                }
                .disabled(testRunning)
                if let message = testMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
        case .banners:
            Section {
                HStack {
                    Text("Şu anki stil")
                    Spacer()
                    if permissions.alertsPersistent {
                        Label("Kalıcı", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.asistDone)
                    } else {
                        Text("Geçici")
                            .foregroundStyle(Color.orange)
                    }
                }
                Button {
                    PermissionCenter.openNotificationSettings()
                } label: {
                    Label("Bildirim ayarlarını aç", systemImage: "bell.badge")
                        .font(.headline)
                }
            }
        }
    }

    private func runTest() {
        testRunning = true
        Task { @MainActor in
            let message = await TestNotificationSender.send(afterSeconds: 30)
            testMessage = message
            testRunning = false
        }
    }

    // MARK: Content

    static func rich(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let value = try? AttributedString(markdown: markdown, options: options) {
            return value
        }
        return AttributedString(markdown)
    }

    static func title(for kind: GuideKind) -> String {
        switch kind {
        case .backTap: return "Asist Hızlı Kayıt"
        case .backTapListen: return "Asist Dinle"
        case .siri: return "Siri"
        case .focus: return "Odak ve bildirimler"
        case .banners: return "Kalıcı bildirim"
        }
    }

    static func intro(for kind: GuideKind) -> String {
        switch kind {
        case .backTap:
            return "Telefonun arkasına iki kez vur, cümleni söyle, sus. Asist uygulama açılmadan kaydeder ve üstte kısa bir onay gösterir. Bir kez kurman yeterli (yaklaşık 2 dakika)."
        case .backTapListen:
            return "Telefonun arkasına üç kez vurunca Asist açılır ve hemen dinlemeye başlar. Onay kartını görüp düzeltmek istediğinde bu yolu kullan."
        case .siri:
            return "Siri ile uygulamayı açmadan kayıt ekleyebilir, gündemini dinleyebilirsin. Telefon kilitliyken de çalışır."
        case .focus:
            return "Odak veya Rahatsız Etme açıkken Asist izinli uygulamalarda değilse hatırlatmalar sessizce kaybolur. Bunu bir kez ayarla."
        case .banners:
            return "Normalde bildirim birkaç saniye sonra ekrandan kaybolur. “Kalıcı” seçersen hatırlatma, sen dokunana ya da kaydırana kadar ekranın üstünde kalır. Alarm olmadan unutmamanın en güçlü yolu budur."
        }
    }

    static func steps(for kind: GuideKind) -> [Step] {
        switch kind {
        case .backTap: return backTapSteps
        case .backTapListen: return backTapListenSteps
        case .siri: return siriSteps
        case .focus: return focusSteps
        case .banners: return bannerSteps
        }
    }

    static func tips(for kind: GuideKind) -> [String] {
        switch kind {
        case .backTap: return backTapTips
        case .backTapListen: return backTapListenTips
        case .siri: return siriTips
        case .focus: return focusTips
        case .banners: return bannerTips
        }
    }

    // Guide A — headless "Asist Hızlı Kayıt" (04 §3.7, 01b §4.13 A).
    private static let backTapSteps: [Step] = [
        Step(symbol: "square.2.layers.3d",
             text: "**Kestirmeler** uygulamasını aç (aşağıdaki **Kestirmeler'i Aç** düğmesi)."),
        Step(symbol: "plus.circle",
             text: "Sağ üstteki **+** simgesine, sonra **Eylem Ekle**'ye dokun."),
        Step(symbol: "mic",
             text: "Arama kutusuna **Dikte** yaz ve **Metni Dikte Et** eylemini seç. Eylemin ayrıntılarından **Dil: Türkçe** ve **Dinlemeyi Durdur: Duraklamadan Sonra** seç."),
        Step(symbol: "magnifyingglass",
             text: "Arama kutusuna bu kez **Asist** yaz ve **Asist'e Kaydet** eylemini ekle."),
        Step(symbol: "link",
             text: "**Asist'e Kaydet** eylemindeki **Metin** alanına dokun ve **Dikte Edilen Metin**'i seç."),
        Step(symbol: "pencil",
             text: "Kestirmenin adını **Asist Hızlı Kayıt** yap ve **Bitti**'ye dokun."),
        Step(symbol: "gearshape",
             text: "**Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokunma** yolunu aç."),
        Step(symbol: "hand.tap",
             text: "**Çift Dokunma**'yı seç; listenin **Kestirmeler** bölümünden **Asist Hızlı Kayıt**'ı işaretle."),
        Step(symbol: "checkmark.circle",
             text: "Dene: telefonun arkasına, Apple logosunun yakınına iki kez hızlıca vur ve “yarın 9'da tedarikçiyi aramayı hatırlat” de. Susunca kayıt tamamlanır.")
    ]

    private static let backTapTips: [String] = [
        "İlk denemede Kestirmeler bir izin sorarsa **Her Zaman İzin Ver**'i seç.",
        "Telefonun kilidi açıkken çalışır. Kilitliyken yan tuşa basılı tutup “Asist'e kaydet” de.",
        "Kalın kılıfta algılama zayıflayabilir. Cepte yanlışlıkla tetikleniyorsa **Üç Dokunma**'yı kullan.",
        "Kaydın doğru anlaşıldığını görmek istersen Asist'i açtığında Bugün ekranına bak; emin olamadıklarımı ayrıca gösteririm."
    ]

    // Guide A-alt — "Asist Dinle" (opens the app and listens).
    private static let backTapListenSteps: [Step] = [
        Step(symbol: "square.2.layers.3d",
             text: "**Kestirmeler** uygulamasını aç (aşağıdaki **Kestirmeler'i Aç** düğmesi)."),
        Step(symbol: "plus.circle",
             text: "Sağ üstteki **+** simgesine, sonra **Eylem Ekle**'ye dokun."),
        Step(symbol: "magnifyingglass",
             text: "Arama kutusuna **Asist** yaz ve **Asist Dinle** eylemini seç."),
        Step(symbol: "pencil",
             text: "Kestirmenin adını **Asist Dinle** yap ve **Bitti**'ye dokun."),
        Step(symbol: "gearshape",
             text: "**Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokunma** yolunu aç."),
        Step(symbol: "hand.tap",
             text: "**Üç Dokunma**'yı seç; listenin **Kestirmeler** bölümünden **Asist Dinle**'yi işaretle."),
        Step(symbol: "checkmark.circle",
             text: "Dene: telefonun arkasına üç kez vur; Asist açılır ve dinlemeye başlar.")
    ]

    private static let backTapListenTips: [String] = [
        "Çift dokunmayı **Asist Hızlı Kayıt** için kullan; ikisi birlikte çalışır.",
        "Telefon kilitliyse önce Face ID ile kilit açılır, sonra Asist dinler."
    ]

    // Guide C — Siri.
    private static let siriSteps: [Step] = [
        Step(symbol: "gearshape",
             text: "**Ayarlar › Siri** yolunda dil **Türkçe** olsun; **“Hey Siri”** veya **Siri için yan tuşa bas** açık olsun."),
        Step(symbol: "mic.circle",
             text: "Yan tuşa basılı tut veya “Hey Siri” de, ardından **“Asist'e kaydet”** de."),
        Step(symbol: "text.bubble",
             text: "Siri “Ne kaydedeyim?” diye sorar; cümleni söyle: “Perşembe 14'te ABB ile toplantı, yarım saat önce hatırlat”."),
        Step(symbol: "sun.max",
             text: "**“Asist bugün ne var”**: bugünkü işleri ve gecikenleri okurum."),
        Step(symbol: "exclamationmark.triangle",
             text: "**“Asist neyi unuttum”** veya **“Asist gecikenler”**: geciken işleri okurum."),
        Step(symbol: "waveform",
             text: "**“Asist dinle”**: uygulama açılır ve dinlemeye başlar.")
    ]

    private static let siriTips: [String] = [
        "Diğer söyleyişler: “Asist'e ekle”, “Asist'e not al”, “Asist hatırlat”, “Asist gündem”.",
        "Komutlar Kestirmeler uygulamasında **Asist** başlığı altında da görünür.",
        "Siri komutu tanımazsa Asist'i bir kez açıp kapat, sonra tekrar dene.",
        "Telefon yeniden başladıktan sonra ilk kilit açılışına kadar kayıt yapamam; Siri bunu söyler. Kilidi açıp tekrar söyle.",
        "Tamamlama, silme ve erteleme için Asist'i açman gerekir."
    ]

    // Guide E — Focus and notification settings.
    private static let focusSteps: [Step] = [
        Step(symbol: "moon",
             text: "**Ayarlar › Odak › İş** yolunu aç (kullanıyorsan **Uyku** ve **Rahatsız Etme** için de aynısını yap)."),
        Step(symbol: "app.badge",
             text: "**İzin Verilen Bildirimler › Uygulamalar**'a dokun ve **Asist**'i ekle."),
        Step(symbol: "bell",
             text: "**Ayarlar › Bildirimler › Asist**: **Bildirimlere İzin Ver** açık, **Önizlemeleri Göster: Her Zaman** olsun."),
        Step(symbol: "clock.badge.exclamationmark",
             text: "Aynı ekranda **Zamana Duyarlı Bildirimler** görünüyorsa aç. Görünmüyorsa sorun değil; ücretsiz imzada olmayabilir."),
        Step(symbol: "tray",
             text: "**Ayarlar › Bildirimler › Zamanlanmış Özet** açıksa Asist özete dahil olmasın; hatırlatmalar anında gelsin."),
        Step(symbol: "xmark.bin",
             text: "**Ayarlar › App Store › Kullanılmayan Uygulamaları Kaldır** kapalı olsun. Yan yüklenen Asist kaldırılırsa geri gelmez."),
        Step(symbol: "checkmark.circle",
             text: "Dene: Odağı aç, aşağıdaki **Test bildirimi (30 sn)**'ye dokun ve telefonu kilitle. Bildirim gelmezse 2. adımı kontrol et.")
    ]

    private static let focusTips: [String] = [
        "Toplantıda susmamı istiyorsan Odak yerine Bugün ekranındaki zil simgesinden **Sessize al**'ı kullan; süre bitince tek hatırlatmayla devam ederim."
    ]

    // "Kalıcı" banner style (05b A9).
    private static let bannerSteps: [Step] = [
        Step(symbol: "gearshape",
             text: "Aşağıdaki **Bildirim ayarlarını aç** düğmesine dokun (ya da **Ayarlar › Bildirimler › Asist**)."),
        Step(symbol: "checkmark.circle",
             text: "**Bildirimlere İzin Ver** açık; **Kilitli Ekran**, **Bildirim Merkezi** ve **Afişler** işaretli olsun."),
        Step(symbol: "rectangle.topthird.inset.filled",
             text: "**Afiş Stili**'ni (bazı sürümlerde **Banner Stili**) **Kalıcı** yap."),
        Step(symbol: "speaker.wave.2",
             text: "**Sesler** ve **Rozetler** açık olsun."),
        Step(symbol: "eye",
             text: "**Önizlemeleri Göster**: **Her Zaman**.")
    ]

    private static let bannerTips: [String] = [
        "Kalıcı bildirimi kapatmak için yukarı kaydırman yeterli; hatırlatma yine de “✓ Yaptım” diyene kadar devam eder.",
        "Bildirimi basılı tutunca “✓ Yaptım”, “10 dk”, “1 saat”, “Yarın sabah” seçenekleri çıkar; kilidi açmana gerek yok."
    ]
}

/// "Test bildirimi (30 sn)" for onboarding and guide E (05b B11). Returns a Turkish status line for the UI
/// (toasts are not visible above the onboarding full-screen cover).
enum TestNotificationSender {
    @MainActor
    static func send(afterSeconds seconds: TimeInterval) async -> String {
        let env = AppEnvironment.shared
        await env.permissions.refresh()
        let state = env.permissions.notification
        if state == .denied || state == .notDetermined {
            return "Önce bildirimlere izin ver; izin yoksa test bildirimi gelemez."
        }
        let delay = max(2, seconds)
        let text = NotificationText(title: "Asist test bildirimi",
                                    subtitle: "Bildirimler çalışıyor",
                                    body: "Bunu gördüysen hatırlatmalar da gelecek. Odak açıkken gelmediyse Asist'i izinli uygulamalara ekle.")
        await env.scheduler.addUnmanaged(id: NotificationID.test,
                                         text: text,
                                         after: delay,
                                         categoryID: NotificationCategoryID.system,
                                         interruption: .active,
                                         itemID: nil)
        AsistLog.info("Test bildirimi planlandı: " + String(Int(delay)) + " sn", .notif)
        return String(Int(delay)) + " saniye içinde bir test bildirimi gelecek. İstersen telefonu kilitle."
    }
}
