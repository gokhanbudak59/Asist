# 01c — Build, CI ve Mac'siz Sideload Dağıtımı

> Kapsam: XcodeGen proje tanımı, GitHub Actions ile imzasız IPA üretimi, Windows + Sideloadly +
> ücretsiz Apple ID ile kurulum, uygulamanın kendi imza bitiş tarihini okuması ve bu kısıtların
> uygulama mimarisine etkisi.
> Tarih: 2026-09-27 (Pazar), saat dilimi Europe/Istanbul. Hedef cihaz: iPhone 14 Pro Max, iOS 26.
> Deployment target: iOS 17.0. Swift dil modu 5. Yerelde derleyici YOK — tek doğrulama CI'dır.

Güven etiketleri: **[VERIFIED: url]** = birincil kaynakta görüldü (çoğu durumda ham dosya/JSON
indirilip okundu). **[UNVERIFIED: neden]** = çıkarım veya tek kaynaklı; cihazda/CI'da ilk çalıştırmada
doğrulanmalı. Kod blokları iOS 17 SDK+ / Swift 5 modu için yazıldı; derleme tuzakları her bölümde ayrıca listelendi.

---

## 0. Özet kararlar (TL;DR)

| # | Karar | Gerekçe |
|---|---|---|
| D1 | **XcodeGen 2.46.0**, GitHub release zip'inden SHA-256 doğrulamalı kurulur (brew değil). | Sabit sürüm, 2 sn indirme, brew auto-update gecikmesi yok. SHA-256 `4d9e34b6…6806` 2026-09-27'de indirilip hesaplandı. |
| D2 | `project.yml` tek doğruluk kaynağı; `Asist.xcodeproj` ve `Generated/` (Info.plist + entitlements) **git'e girmez**, CI her seferinde üretir. | Windows'ta Xcode yok; elle proje dosyası düzenlemek imkânsız ve hataya açık. |
| D3 | Runner: **`macos-26`** (arm64, standart), Xcode = kurulu **en yeni kararlı 26.x** (bugün 26.6, iOS SDK 26.5). Xcode 27 yalnız önizleme etiketi `xcode-27` üzerinde; kullanılmaz. | `macos-15` varsayılanı Xcode 16.4 (iOS 18 SDK) — iOS 26 API'leri derlenmez. |
| D4 | AsistCore testleri **Linux** (`ubuntu-24.04` + `swift:6.3-noble` konteyneri) üzerinde, 1× dakika maliyetiyle. | macOS dakikası 10× sayılır. Swift 6.3 = Xcode 26.4+ derleyicisi. |
| D5 | Cihaz derlemesi `xcodebuild build -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`, sonra **elle `Payload/` zip** → `.ipa`. | `-exportArchive` imza kimliği ister; ücretsiz/Mac'siz senaryoda kullanılamaz. |
| D6 | CI **iki IPA** üretir: `Asist.ipa` (uygulama+widget ad-hoc imzalı, App Group entitlement'ı imzaya gömülü) ve `Asist-imzasiz.ipa` (yedek). İkisi de `upload-artifact@v7 archive:false` ile **zip'siz** indirilir. | Yeniden imzalayıcılar (AltStore kaynak kodunda doğrulandı) entitlement'ı ikiliden okur; imzasız ikilide hiç entitlement yoktur. Sideloadly davranışı doğrulanamadı → yedek IPA. |
| D7 | **Uygulama App Group'a bağımlı OLMAYACAK.** Ana veri deposu her zaman uygulamanın kendi `Application Support` klasöründe. App Group bulunursa yalnız widget için anlık görüntü (snapshot) yazılır. | Ücretsiz Apple ID App Group'u destekler (Apple tablosu) ama Sideloadly'nin kaydedip kaydetmediği doğrulanamadı; changelog'da "custom entitlements" yalnız ücretli hesap. Veri kaybı riski sıfırlanmalı. |
| D8 | **Time-Sensitive, Siri, Push, iCloud, Communication Notifications entitlement'ları KULLANILMAZ.** | Apple "Supported capabilities (iOS)" tablosunda ücretsiz "Apple Developer" sütununda yoklar. |
| D9 | Kod **bundle-ID'den bağımsız** yazılır (Sideloadly bundle ID'yi "mangle" edebilir; AltStore takım kimliği ekler). App Group kimliği çalışma anında `embedded.mobileprovision` + `ALTAppGroups` üzerinden çözülür. | Kaynaklar §3.2. |
| D10 | Uygulama kendi `embedded.mobileprovision` dosyasından **ExpirationDate** okur; bitişten 48 s / 24 s / 4 s önce (gece saatlerine denk gelirse önceki akşam 21:00) yerel bildirim kurar; Ayarlar'da "İmza bitişi" satırı gösterir. Profil `CreationDate` değişince (yeniden imzalandı) tüm hatırlatıcı bildirimlerini baştan kurar. | 7 günlük ücretsiz imza; güncelleme sonrası bekleyen bildirimlerin uygulama açılana kadar gelmediğine dair Apple forum raporu. |

---

## 1. XcodeGen

### 1.1 Depo düzeni

```
Asist/                                  (C:\ClaudeProjects\Asist)
├─ project.yml                          XcodeGen tanımı (tek kaynak)
├─ .gitignore
├─ .github/workflows/ci.yml             CI (§2.6)
├─ Scripts/ci/select-xcode.sh           Xcode seçimi (§2.2)
├─ Scripts/ci/install-xcodegen.sh       XcodeGen kurulumu (§2.3)
├─ Scripts/ci/package-ipa.sh            IPA paketleme + ad-hoc entitlement imzası (§2.5)
├─ Scripts/ci/error-summary.sh          Derleme hatası özeti (§2.8)
├─ Tools/make_app_icon.py               1024 px ikon üretici (Windows'ta çalışır, §1.7)
├─ App/                                 Uygulama hedefi kaynakları (SwiftUI)
│  └─ Resources/Assets.xcassets/        AppIcon + (isteğe bağlı) AccentColor
├─ Widgets/                             AsistWidgets uzantısı kaynakları (@main WidgetBundle)
├─ Shared/                              (isteğe bağlı) HEM App HEM Widgets'ın derlediği dosyalar
│                                       (App Intents, Live Activity attributes, widget görünümleri)
├─ Packages/AsistCore/                  Yerel SwiftPM paketi — yalnız Foundation, Linux'ta da derlenir
│  ├─ Package.swift
│  ├─ Sources/AsistCore/…
│  └─ Tests/AsistCoreTests/…
├─ Generated/                           XcodeGen ÜRETİR (git'e girmez)
└─ docs/design/…
```

### 1.2 `project.yml` (tam)

Bu dosya Python `yaml.safe_load` ile ayrıştırılarak sözdizimi doğrulandı; anahtarlar XcodeGen
`ProjectSpec.md` ve kaynak koduna karşı kontrol edildi (§1.3). [VERIFIED: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md]

```yaml
# Asist — XcodeGen proje tanımı (tek doğruluk kaynağı).
# Üretim: `xcodegen generate --spec project.yml` (CI'da). Asist.xcodeproj ve Generated/ altı
# (Info.plist + .entitlements) her üretimde YENİDEN YAZILIR; ikisi de git'e EKLENMEZ, elle düzenlenmez.
name: Asist

options:
  minimumXcodeGenVersion: "2.46.0"
  bundleIdPrefix: com.gokhanbudak.asist     # yalnız PRODUCT_BUNDLE_IDENTIFIER verilmeyen hedefler için
  developmentLanguage: tr                   # PBXProject developmentRegion + DEVELOPMENT_LANGUAGE
  useBaseInternationalization: false        # knownRegions = [tr] (+ varsa diğer .lproj/.xcstrings dilleri)
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    TARGETED_DEVICE_FAMILY: "1"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"            # CI komut satırından github.run_number ile ezilir
    GENERATE_INFOPLIST_FILE: NO             # Info.plist'ler aşağıdaki `info:` bloklarından üretilir
    SUPPORTS_MACCATALYST: NO
    SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
    SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""
    # ENABLE_PREVIEWS verilmez: Mac olmadığı için önizleme yok; Debug dylib/önizleme ikilileri IPA'ya karışmasın.

packages:
  AsistCore:
    path: Packages/AsistCore

targets:
  Asist:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: App
      - path: Shared            # App + Widget'ın ORTAK derlediği dosyalar (App Intents, widget görünümleri)
        optional: true
    settings:
      base:
        PRODUCT_NAME: Asist
        PRODUCT_BUNDLE_IDENTIFIER: com.gokhanbudak.asist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: Generated/Asist-Info.plist
      properties:
        CFBundleDisplayName: Asist
        CFBundleName: Asist
        CFBundleDevelopmentRegion: tr
        CFBundleLocalizations: [tr]
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIApplicationSupportsIndirectInputEvents: true
        CFBundleURLTypes:
          - CFBundleURLName: com.gokhanbudak.asist
            CFBundleTypeRole: Editor
            CFBundleURLSchemes: [asist]
        UIBackgroundModes:
          - fetch
          # - audio   # YALNIZ ürün kararı "arka planda sessiz ses oturumu" ise açılır (bkz. §1.5)
        BGTaskSchedulerPermittedIdentifiers:
          - com.gokhanbudak.asist.yenile      # BGAppRefreshTask (tek kimlik = tek handler)
        NSSupportsLiveActivities: true
        LSApplicationQueriesSchemes: [shortcuts]
        NSMicrophoneUsageDescription: "Asist, sesli komutlarınızı dinleyip hatırlatıcı ve nota dönüştürmek için mikrofonu kullanır."
        NSSpeechRecognitionUsageDescription: "Asist, söylediklerinizi yazıya çevirmek için konuşma tanımayı kullanır; mümkün olduğunda işlem cihaz üzerinde yapılır."
        NSCalendarsFullAccessUsageDescription: "Asist, toplantılarınızı görüp hatırlatıcıları takviminizle çakışmayacak şekilde planlamak için takviminize erişir."
        NSCalendarsWriteOnlyAccessUsageDescription: "Asist, sesle söylediğiniz toplantıları takviminize eklemek için yazma izni ister."
        NSRemindersFullAccessUsageDescription: "Asist, isterseniz görevlerinizi Apple Anımsatıcılar ile eşitlemek için erişim ister."
        NSContactsUsageDescription: "Asist, “Ahmet'i ara” gibi komutlarda kişiyi bulmak için rehberinize erişir."
        NSLocationWhenInUseUsageDescription: "Asist, “fabrikaya varınca hatırlat” gibi konum tabanlı hatırlatıcılar için konumunuzu kullanır."
        NSLocationAlwaysAndWhenInUseUsageDescription: "Asist, uygulama kapalıyken de konuma bağlı hatırlatıcıları tetikleyebilmek için arka planda konum izni ister."
        NSFaceIDUsageDescription: "Asist, özel notlarınızı ve API anahtarınızı korumak için Face ID kullanır."
        NSCameraUsageDescription: "Asist, kartvizit ve belge fotoğrafı çekip nota eklemek için kamerayı kullanır."
    entitlements:
      path: Generated/Asist.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.gokhanbudak.asist
        # com.apple.developer.usernotifications.time-sensitive: true
        #   ^ YALNIZ ücretli Apple Developer Program ile açılır. Ücretsiz Apple ID bu yeteneği
        #     desteklemez (Apple "Supported capabilities" tablosu); eklenirse kurulum reddedilebilir.
    dependencies:
      - package: AsistCore
      - target: AsistWidgets
        embed: true
    scheme:
      language: tr
      region: TR

  AsistWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Widgets
      - path: Shared
        optional: true
    settings:
      base:
        PRODUCT_NAME: AsistWidgets
        PRODUCT_BUNDLE_IDENTIFIER: com.gokhanbudak.asist.widgets   # uygulama kimliğiyle ÖNEKLİ olmalı
        SKIP_INSTALL: YES
    info:
      path: Generated/AsistWidgets-Info.plist
      properties:
        CFBundleDisplayName: Asist
        CFBundleDevelopmentRegion: tr
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Generated/AsistWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.gokhanbudak.asist
    dependencies:
      - package: AsistCore
```

> Not: Kullanılmayacak özellik için izin metni (ör. kamera) bırakmak zararsızdır; ama bir API
> kullanılıp metni **eksik** olursa uygulama o API çağrısında sonlandırılır. Ürün kapsamı daralırsa
> anahtar silinebilir; genişlerse önce buraya eklenir.

### 1.3 Satır satır gerekçe ve derleme/çalışma tuzakları

| Konu | Doğrulanan davranış | Tuzak / kural |
|---|---|---|
| `info:` | XcodeGen dosyayı **üretim anında diske yazar** (dizini `mkpath` ile açar) ve `INFOPLIST_FILE`'ı ayarlar. Otomatik anahtarlar: `CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleName=$(PRODUCT_NAME)`, `CFBundleDevelopmentRegion=$(DEVELOPMENT_LANGUAGE)`, `CFBundleExecutable`, `CFBundlePackageType` (app `APPL`, app-extension `XPC!`), **`CFBundleShortVersionString="1.0"` ve `CFBundleVersion="1"` sabit**. Bizim `properties` bunların üstüne yazılır. [VERIFIED: https://github.com/yonaskolb/XcodeGen/blob/master/Sources/XcodeGenKit/InfoPlistGenerator.swift , .../FileWriter.swift] | Sürüm anahtarlarını `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` ile **ezin**; yoksa CI'daki build numarası plist'e yansımaz. App ile widget'ın `CFBundleVersion`/`CFBundleShortVersionString` değerleri **aynı** olmalı (paketleme betiği denetler). |
| `entitlements:` | Dosyayı yazar ve `CODE_SIGN_ENTITLEMENTS`'ı ayarlar; "tüm özellikler verilmelidir". [VERIFIED: ProjectSpec.md "entitlements"] | `$(AppIdentifierPrefix)` içeren değer (ör. `keychain-access-groups`) **koymayın**: ücretsiz imzada ve farklı Apple ID'de takım öneki değişir. |
| `GENERATE_INFOPLIST_FILE: NO` | XcodeGen preset'leri bu ayarı hiç yazmaz (Xcode varsayılanı NO); açıkça NO vermek, ileride birinin `INFOPLIST_KEY_*` eklemesiyle oluşacak birleşik plist sürprizini önler. [VERIFIED: SettingPresets/base.yml, Products/*.yml incelendi] | `YES` yapılırsa Xcode üretilen anahtarları bizim dosyamızla birleştirir; iki kaynak = belirsizlik. |
| `bundleIdPrefix` | Yalnız `PRODUCT_BUNDLE_IDENTIFIER` olmayan hedefe `prefix.HedefAdı` üretir. [VERIFIED: ProjectSpec.md Options] | `com.gokhanbudak` + hedef adı `AsistWidgets` → `com.gokhanbudak.AsistWidgets` olur ve **uygulama kimliğiyle önekli olmaz** → Xcode "Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier" hatası. Bu yüzden iki hedefte de kimlik **açıkça** verildi; prefix yine de `com.gokhanbudak.asist` tutuldu (gelecekte eklenen uzantı otomatik olarak önekli olsun). |
| Sürüm sayıları | YAML'de `17.0`, `5.0` tırnaksız yazılırsa float olur (`17.10` → `17.1`). | **Tüm sürümleri tırnakla.** |
| `YES`/`NO` | YAML 1.1'de bool'dur; XcodeGen `BuildSetting(any:)` bool'u `YES`/`NO` dizesine çevirir. [VERIFIED: Sources/ProjectSpec/Settings.swift] | Info.plist `properties` içinde bool için `true/false` kullanın (plist `<true/>`). |
| `developmentLanguage: tr` + `useBaseInternationalization: false` | XcodeGen `knownRegions`'ı **hesaplar**: `developmentLanguage` ∪ bulunan `.lproj` klasörleri ∪ `.xcstrings` dilleri ∪ (`useBaseInternationalization` true ise) `Base`. Ayrı bir `knownRegions` seçeneği **yoktur**. [VERIFIED: PBXProjGenerator.swift satır ~315–320, SourceGenerator.swift] | Tüm kullanıcı metinleri Türkçe ve tek dil → `knownRegions = [tr]`. `CFBundleLocalizations: [tr]` sistem arayüzünün (paylaşım sayfası, tarih biçimleri) Türkçe gelmesine yardım eder. |
| `scheme:` | XcodeGen **yalnız** `scheme:` verilen hedefe (veya üst düzey `schemes:`) şema üretir. `language`/`region` Target Scheme alanlarıdır. [VERIFIED: ProjectSpec.md "Target Scheme"] | `xcodebuild -scheme Asist` şema yoksa başarısız olur. Widget için ayrı şemaya gerek yok; uygulama şeması bağımlı hedefi de derler. |
| `dependencies: - target: AsistWidgets` | Bağımlılık `app-extension` ise XcodeGen onu **"Embed Foundation Extensions"** kopyalama fazına (`dstSubfolderSpec: .plugins` → `Asist.app/PlugIns/`) koyar; `embed` uygulama hedefi için varsayılan `true`. [VERIFIED: PBXProjGenerator.swift satır ~771, ~1234] | ExtensionKit (`extensionkit-extension`) başka klasöre gider; WidgetKit için `app-extension` doğru tiptir. |
| `packages: AsistCore: path:` | Yerel paket; `- package: AsistCore` ürün adı varsayılan olarak paket anahtarıdır. [VERIFIED: ProjectSpec.md "Local Package", "Package dependency"] | `Package.swift` içindeki `.library(name:)` **birebir** `AsistCore` olmalı. Paket `.static`/otomatik kütüphane → hem app hem widget'a ayrı ayrı statik bağlanır; gömme gerekmez. `.dynamic` yapılırsa gömme gerekir — yapmayın. |
| Paket platformu | — | `Package.swift`'teki `.iOS(.v17)` uygulamanın hedefinden (17.0) **büyük olamaz**; aksi hâlde "requires minimum platform version" hatası. |
| `optional: true` (Shared) | Kaynak yolu yoksa hata vermez. [VERIFIED: ProjectSpec.md TargetSource `optional`] | Diğer tüm `sources` yolları **mevcut olmalı**; yoksa `xcodegen generate` durur. Boş klasör git'e girmez → her klasörde en az bir `.swift` dosyası bulunmalı. |
| `ASSETCATALOG_COMPILER_APPICON_NAME` | iOS `application` preset'i zaten `AppIcon` verir; açık yazmak zararsız. [VERIFIED: SettingPresets/Product_Platform/application_iOS.yml] | — |
| `TARGETED_DEVICE_FAMILY: "1"` | iOS preset'i `1,2` verir; biz ezeriz (yalnız iPhone). [VERIFIED: SettingPresets/Platforms/iOS.yml] | — |
| `SWIFT_VERSION: "5.0"`, `SWIFT_STRICT_CONCURRENCY: minimal` | Swift 5 dil modu; Xcode 26'nın yeni **şablonlarındaki** "Approachable Concurrency / default MainActor isolation" ayarları XcodeGen projesine gelmez. | `SWIFT_DEFAULT_ACTOR_ISOLATION` veya `SWIFT_UPCOMING_FEATURE_*` eklemeyin; eklenirse aynı kod farklı hatalar üretir. |
| `projectFormat` | Varsayılan `xcode16_0` (Xcode 16+ ile açılır). [VERIFIED: ProjectSpec.md] | Runner Xcode 26 → sorun yok. |
| XcodeGen kurulumu | İkili, `SettingPresets`'i `<bin>/../share/xcodegen/` altında arar; bulamazsa **"No "base" settings found"** yazar ve SDKROOT gibi temel ayarlar olmadan proje üretir. [VERIFIED: Sources/XcodeGenKit/SettingsBuilder.swift] | CI adımı bu metni arar ve işi düşürür (§2.6). |

### 1.4 Info.plist anahtarları — neden var, eksikse ne olur

| Anahtar | Neden | Eksikse |
|---|---|---|
| `NSMicrophoneUsageDescription` | `AVAudioSession`/`AVAudioEngine` giriş | Mikrofon erişiminde uygulama sonlanır. "Required if your app uses APIs that access the device's microphone." [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription] |
| `NSSpeechRecognitionUsageDescription` | `SFSpeechRecognizer.requestAuthorization` | Aynı şekilde sonlanır. [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription] |
| `NSCalendarsFullAccessUsageDescription` / `…WriteOnly…` | iOS 17 EventKit tam/yalnız-yazma erişimi | iOS 17 anahtarları; eski `NSCalendarsUsageDescription` iOS 17+ için yetmez. [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription] |
| `NSRemindersFullAccessUsageDescription` | Apple Anımsatıcılar eşitleme (isteğe bağlı özellik) | [VERIFIED: .../nsremindersfullaccessusagedescription] |
| `NSContactsUsageDescription`, `NSLocation…`, `NSFaceIDUsageDescription`, `NSCameraUsageDescription` | İleriki özellikler (kişi, konum hatırlatıcısı, uygulama kilidi, kartvizit) | Kullanılmadıkça etkisiz. |
| `UILaunchScreen: {}` | Storyboard'suz açılış ekranı | Yoksa uygulama **eski ekran boyutu uyumluluk modunda** (siyah bantlı) açılır. [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen] |
| `UIApplicationSceneManifest` | SwiftUI `App` yaşam döngüsü; Xcode şablonunun ürettiği anahtarın karşılığı | — |
| `CFBundleURLTypes` → `asist` | `asist://dinle` derin bağlantısı (widget, Kısayollar, Control Center) | Bağlantı açılmaz. |
| `UIBackgroundModes: [fetch]` + `BGTaskSchedulerPermittedIdentifiers` | `BGAppRefreshTask` ile bildirim planı uzlaştırma | `BGAppRefreshTask` için "Background fetch" gerekir. [VERIFIED: https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app] Listedeki **her kimlik için handler şart**; aynı kimliği iki kez kaydetmek uygulamayı öldürür; kayıt `didFinishLaunching` bitmeden yapılmalı. [VERIFIED: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)] → Listede **tek** kimlik bırakıldı. SwiftUI `.backgroundTask(.appRefresh("…"))` kullanılırsa `BGTaskScheduler.shared.register` **ayrıca çağrılmaz**. |
| `NSSupportsLiveActivities: true` | Dinamik Ada / kilit ekranında "ısrarlı hatırlatıcı" Live Activity | Yoksa `Activity.request` başarısız olur. [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities] Live Activity **App Group gerektirmez** (veri `ContentState` ile geçer) — ücretsiz imzada widget'a dinamik bilgi göstermenin güvenilir yolu budur. |
| `LSApplicationQueriesSchemes: [shortcuts]` | `canOpenURL(shortcuts://)` ile Kısayollar uygulaması kontrolü | Yalnız `canOpenURL` için gerekir; `open` için gerekmez. |
| `UIDesignRequiresCompatibility` | **Eklenmedi.** iOS 26 SDK ile derlenen uygulama Liquid Glass görünümü alır; `YES` eski görünümü zorlar ve iOS 27+ SDK ile derlemede **yok sayılır**. [VERIFIED: https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility] | UI tasarım dokümanı karar verir. |

### 1.5 Arka plan modları kararı

- `fetch`: evet (bildirim uzlaştırma için `BGAppRefreshTask`).
- `processing`: **hayır** — listelenen her kimliğe handler şart; gereksiz yüzey.
- `audio`: **varsayılan kapalı.** Ses-kısma çift basış algılama (outputVolume KVO) yalnız ön planda
  güvenilirdir; arka planda çalışması için sessiz ses oturumunu canlı tutmak gerekir (pil, müzik
  uygulamalarıyla çakışma, kesinti yönetimi). Bu karar tetikleme dokümanına (01a/01b) aittir;
  alınırsa yalnız bu satır açılır — ücretsiz imzada `UIBackgroundModes` bir entitlement değil,
  Info.plist anahtarıdır, imzayı etkilemez.
- `remote-notification`: hayır (push yok).

### 1.6 Entitlement'lar ve ücretsiz imza

Apple'ın resmi tablosu (ham HTML indirilip ayrıştırıldı) — "Apple Developer" sütunu = ücretsiz hesap:
[VERIFIED: https://developer.apple.com/help/account/reference/supported-capabilities-ios]

| Yetenek | Ücretli (ADP) | Ücretsiz | Asist kararı |
|---|---|---|---|
| App groups | ✓ | **✓** | Entitlement'ta var; ama uygulama **olmasına güvenmez** (§3.2). |
| Background modes | ✓ | ✓ | `fetch` (Info.plist). |
| Data protection | ✓ | ✓ | İsteğe bağlı; varsayılan koruma yeterli. |
| Keychain sharing | ✓ | ✓ | **Gerekmez** — varsayılan anahtarlık erişim grubu kullanılır (Claude API anahtarı). |
| HealthKit / HomeKit / Maps / Inter-App Audio / Wireless Accessory | ✓ | ✓ | Kullanılmaz. |
| Time Sensitive Notifications | ✓ | **✗** | **Eklenmez.** `interruptionLevel = .timeSensitive` kodda derlenir; entitlement yokken sistem davranışı → bildirim dokümanı [UNVERIFIED: muhtemelen `.active` gibi davranır]. |
| Siri (`com.apple.developer.siri`) | ✓ | **✗** | Eklenmez. Apple: bu entitlement "shortcut istekleri **dışındaki**" Siri isteklerini işleyen Intents uzantıları için gerekir → App Intents / App Shortcuts için gerekmemeli. [VERIFIED: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri] Ancak bir geliştirici raporu entitlement olmadan Siri'nin App Shortcut'ı sesle çağırmadığını, Kısayollar'da ise çalıştığını söylüyor. [UNVERIFIED: https://github.com/Redth/Maui.Apple.PlatformFeature.Samples/issues/1] → Sesli Siri yolu "en iyi çaba"; birincil tetikleyiciler (Geri Dokunma → Kısayol, Denetim Merkezi, widget, uygulama içi) Siri'ye bağlı değil. **İlk kurulumda cihazda test edilecek.** |
| Push notifications | ✓ | ✗ | Yok; tüm hatırlatıcılar yerel bildirim. |
| iCloud (CloudKit/Documents/KVS) | ✓ | ✗ | Yok; yedek = uygulama içi JSON dışa aktarma (Dosyalar). |
| Communication Notifications, Associated Domains, Sign in with Apple, WeatherKit | ✓ | ✗ | Kullanılmaz. |

Kurallar:
1. Entitlement dosyasında ücretsiz hesabın desteklemediği bir anahtar **bulunmayacak** (kurulumda "invalid entitlements" riski).
2. `aps-environment`, `com.apple.developer.icloud-*`, `keychain-access-groups` **yok**.
3. İmzalayıcı App Group kimliğini değiştirebilir (AltStore `.<TEAMID>` ekler, §3.2) → kimlik çalışma anında çözülür (§4.2).

### 1.7 Asset kataloğu ve tek 1024 px ikon

Xcode 14+ "Single Size" biçimi: tek 1024×1024 görsel; diğer boyutları derleyici üretir.
[VERIFIED: https://useyourloaf.com/blog/xcode-14-single-size-app-icon/]

`App/Resources/Assets.xcassets/Contents.json`
```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
```json
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Kurallar: PNG **1024×1024, RGB, alfa kanalı yok** (alfa varsa köşeler siyah görünebilir). Mac olmadığı
için ikon Windows'ta aşağıdaki **yalnız standart kütüphane** kullanan betikle üretilir (bu betik
2026-09-27'de çalıştırıldı; çıktı 1024×1024 RGB, mavi→petrol degrade üzerinde beyaz mikrofon):

`Tools/make_app_icon.py`
```python
#!/usr/bin/env python3
"""Asist uygulama ikonu (1024x1024, RGB, alfa YOK). Yalnız standart kütüphane.
Kullanım (Windows): python Tools/make_app_icon.py
Çıktı: App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"""
import os, struct, sys, zlib

SIZE = 1024
TOP, BOTTOM, WHITE = (0x0B, 0x3D, 0x91), (0x00, 0x96, 0x88), (0xFF, 0xFF, 0xFF)

def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def inside_capsule(x, y, cx, top, bottom, radius):
    if top <= y <= bottom:
        return abs(x - cx) <= radius
    cy = top if y < top else bottom
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

def pixel(x, y):
    cx = SIZE / 2
    if inside_capsule(x, y, cx, 300, 520, 110):                      # mikrofon gövdesi
        return WHITE
    d2 = (x - cx) ** 2 + (y - 520) ** 2
    if y >= 520 and 150 ** 2 <= d2 <= 190 ** 2:                      # U çatal
        return WHITE
    if 460 <= y < 520 and (abs(x - (cx - 170)) <= 20 or abs(x - (cx + 170)) <= 20):
        return WHITE
    if 710 <= y <= 800 and abs(x - cx) <= 20:                        # ayak
        return WHITE
    if 780 <= y <= 820 and abs(x - cx) <= 120:
        return WHITE
    return mix(TOP, BOTTOM, y / (SIZE - 1))

def png_bytes():
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)       # 8 bit RGB
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png_bytes())
    print("Yazildi:", out)
```

Üretilen PNG **git'e eklenir** (CI Python çalıştırmaz). Koyu/renkli (tinted) ikon varyantları
isteğe bağlıdır; eklenmezse sistem otomatik türetir. `AccentColor` renk seti eklenmedi — eklenirse
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` de verilmeli (yoksa uyarı).

### 1.8 `Packages/AsistCore/Package.swift` ve test hedefi

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsistCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AsistCore", targets: ["AsistCore"])
    ],
    targets: [
        .target(
            name: "AsistCore",
            path: "Sources/AsistCore"
        ),
        .testTarget(
            name: "AsistCoreTests",
            dependencies: ["AsistCore"],
            path: "Tests/AsistCoreTests"
        )
    ]
)
```

- `swift-tools-version: 5.9` → hem Xcode 26 (Swift 6.2/6.3) hem Linux Swift 6.3/6.4 ile derlenir ve paket
  hedefleri **Swift 5 dil modunda** kalır (`swiftLanguageModes` belirtilmez). `.iOS(.v17)` ve `.macOS(.v14)`
  PackageDescription 5.9'da vardır.
- `defaultLocalization` **verilmedi** (paket kaynak içermiyor). Paket ileride `.xcstrings` alırsa eklenir.
- Test çerçevesi: **XCTest** (Linux + macOS'ta aynı; Swift Testing de çalışır ama gereksiz değişken).
- **Xcode içinde ayrı test hedefi yok.** Gerekçe: simülatör testi macOS dakikası harcar ve simülatör
  runtime'ı ister; AsistCore saf Foundation olduğu için `swift test` yeterli. Uygulama katmanı testi
  gerekirse ileride `workflow_dispatch` ile çalışan ayrı bir işe eklenir.
- **AsistCore'a GİRMEYECEKLER:** `SwiftUI`, `UIKit`, `UserNotifications`, `EventKit`, `Speech`, `AVFoundation`,
  `AppIntents`, `WidgetKit`, `ActivityKit`, `SwiftData`, `Combine`, `os.Logger`. Gerekirse `#if canImport(X)` ile
  korunur. App Intents tipleri `Shared/`'a konur (App + Widget ikisi de derler).

### 1.9 Yapılmayacaklar (derleme kıran kalıplar)

1. `Asist.xcodeproj`'yi git'e koyup elle düzenlemek.
2. Widget kodunu `App/` altına koymak (iki `@main` → "multiple @main" hatası).
3. `AppShortcutsProvider`'ı `Shared/` içine koymak (hem app hem uzantıda derlenir); **yalnız `App/`** içinde olmalı. [UNVERIFIED: uzantıda ikinci sağlayıcının davranışı belirsiz; risk alınmaz]
4. Info.plist'te `CFBundleVersion` sabit bırakıp widget ile uygulama arasında farklı değer oluşturmak.
5. Sürüm sayılarını tırnaksız yazmak.
6. Bundle ID'yi kodda sabit kullanmak (`Bundle.main.bundleIdentifier == "com.gokhanbudak.asist"` gibi) — imzalayıcı değiştirebilir.

---

## 2. GitHub Actions

### 2.1 Runner ve Xcode manzarası (Eylül 2026)

| Etiket | Mimari | İşletim sistemi | Xcode | Not |
|---|---|---|---|---|
| **`macos-26`** (=`macos-latest`) | arm64 (standart, ücretsiz dakikayla çalışır) | macOS 26.6.2 | **26.6 (varsayılan)**, 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1 | iOS SDK 26.5 (Xcode 26.5/26.6). Xcbeautify 3.2.1 kurulu. [VERIFIED: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md (image 20260907)] |
| `macos-26-intel` / `-large` | x64 | macOS 26 | aynı | Büyük runner = ücretli, dahil dakika kullanılamaz. |
| `macos-15` | arm64 | macOS 15.7 | 16.4 (varsayılan) + 26.0.1–26.3 | iOS 26 SDK için Xcode 26 seçmek gerekir. [VERIFIED: macos-15-arm64-Readme.md] |
| `macos-14` | — | — | — | Kullanımdan kalkıyor; 2 Kasım'da tamamen desteksiz. [VERIFIED: runner-images README duyuru #13518] |
| `xcode-27` | arm64 | macOS 26 | Xcode 27.0 **beta** | Genel önizleme, kararsız olabilir. [VERIFIED: https://github.com/actions/runner-images/issues/14404] |
| `ubuntu-24.04` | x64 | Ubuntu 24.04.5 | — | Swift 6.4 önceden kurulu, tzdata 2026c. `ubuntu-latest` Kasım 2026'da 26.04'e geçecek → **sabit `ubuntu-24.04`** kullan. [VERIFIED: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md] |

- `macos-latest` Haziran–Temmuz 2026'da `macos-26`'ya taşındı. [VERIFIED: https://github.com/actions/runner-images/issues/14167]
- Kural: "macOS sürümü başına tek ana Xcode sürümü; yeni yama çıkınca önceki yama kaldırılır."
  [VERIFIED: runner-images README "Software and image support"] (Geçiş döneminde `macos-15` hem 16.x hem
  26.x taşıyor.) → **Yol sabitlemek yerine dinamik seçim.**
- Xcode 26.4 Swift 6.3 ile gelir. [VERIFIED (arama sonucu, Apple release notes): https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes] 26.6'nın tam Swift yaması [UNVERIFIED]; CI `swift --version` çıktısını özete yazar.

### 2.2 Xcode seçimi — `Scripts/ci/select-xcode.sh`

Sembolik bağları ve beta/RC adlarını atlar, `XCODE_MAJOR` (varsayılan 26) serisinin **sayısal olarak**
en yenisini seçer (`26.10 > 26.6` doğru sıralanır). macOS'un `/bin/bash` 3.2'siyle uyumlu.
Mantık Git Bash'te sahte `/Applications` ağacıyla sınandı: `""→26.10`, `"26.5"→26.5`, `"26.4"→26.4.1`,
`XCODE_MAJOR=16→16.4`, `"27"→hata`.

```bash
#!/usr/bin/env bash
# Xcode seçimi (macOS runner). macOS'taki /bin/bash 3.2 ile uyumludur.
# Kullanım: select-xcode.sh [istek]
#   istek boş   -> XCODE_MAJOR (varsayılan 26) serisinin en yeni KARARLI sürümü
#   "26.5"      -> 26.5 veya 26.5.x'in en yenisi
#   tam yol     -> /Applications/Xcode_26.5.app
set -euo pipefail

REQ="${1:-}"
PREFIX="${REQ:-${XCODE_MAJOR:-26}}"
PICK=""

case "$REQ" in
  /Applications/*.app) PICK="$REQ" ;;
  *)
    BEST_KEY=""
    for APP in /Applications/Xcode_*.app; do
      [ -d "$APP" ] || continue
      [ -L "$APP" ] && continue                       # Xcode_26.6.0.app gibi symlink'leri atla
      VER="${APP#/Applications/Xcode_}"; VER="${VER%.app}"
      [[ "$VER" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue # beta / RC / "_beta_3" adlarını atla
      [[ "$VER" == "$PREFIX" || "$VER" == "$PREFIX".* ]] || continue
      IFS=. read -r MA MI PA <<< "$VER"
      KEY=$(printf '%03d%03d%03d' "$((10#${MA:-0}))" "$((10#${MI:-0}))" "$((10#${PA:-0}))")
      if [[ -z "$BEST_KEY" || "$KEY" > "$BEST_KEY" ]]; then
        BEST_KEY="$KEY"; PICK="$APP"
      fi
    done
    ;;
esac

if [ -z "$PICK" ] || [ ! -d "$PICK" ]; then
  echo "::error::Uygun Xcode bulunamadı (istek: '$PREFIX'). Kurulu olanlar:"
  ls -d /Applications/Xcode* || true
  exit 1
fi

sudo xcode-select -s "$PICK/Contents/Developer"
echo "DEVELOPER_DIR=$PICK/Contents/Developer" >> "$GITHUB_ENV"
echo "Seçilen: $PICK"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
swift --version
{
  echo "### Derleme ortamı"
  echo "- Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "- iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo "- Swift: $(swift --version 2>&1 | head -n 1)"
} >> "$GITHUB_STEP_SUMMARY"
```

Alternatif: `maxim-lobanov/setup-xcode@v1` (son sürüm v1.7.0, 2026-03-18) `xcode-version: latest-stable`.
[VERIFIED: GitHub releases API] Üçüncü taraf eylem bağımlılığı eklememek için betik tercih edildi.

### 2.3 XcodeGen kurulumu — seçenekler

| Yöntem | Süre | Sabitleme | Karar |
|---|---|---|---|
| `brew install xcodegen` | 30–90 sn (brew auto-update) [UNVERIFIED tahmin] | Hayır (en yeni formül) | Hayır |
| `mint install yonaskolb/xcodegen@2.46.0` | Kaynaktan derler, dakikalar | Evet | Hayır |
| **Release zip + SHA-256** | ~2 sn (4,3 MB) | Evet | **Evet** |

Zip içeriği `xcodegen/bin/xcodegen` (universal: arm64+x86_64, `cafebabe` başlığı görüldü) ve
`xcodegen/share/xcodegen/SettingPresets/…`; yerinde çalıştırılabilir. [VERIFIED: zip indirildi ve
listelendi; release 2.46.0, 2026-07-16 — https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0]

`Scripts/ci/install-xcodegen.sh`
```bash
#!/usr/bin/env bash
# XcodeGen'i sabit sürüm + SHA256 doğrulamasıyla kurar (Homebrew'a bağımlı değil).
set -euo pipefail

VER="${XCODEGEN_VERSION:-2.46.0}"
SHA="${XCODEGEN_SHA256:-4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806}"
DEST="${RUNNER_TEMP:-/tmp}/xcodegen-$VER"
BIN="$DEST/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  curl -fsSL --retry 3 -o "$DEST/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$VER/xcodegen.zip"
  echo "$SHA  $DEST/xcodegen.zip" | shasum -a 256 -c -
  unzip -q -o "$DEST/xcodegen.zip" -d "$DEST"
fi

# İkili, SettingPresets'i <bin>/../share/xcodegen altında bulur; zip bu düzeni korur.
test -d "$DEST/xcodegen/share/xcodegen/SettingPresets" || {
  echo "::error::XcodeGen SettingPresets eksik"; exit 1; }

echo "$DEST/xcodegen/bin" >> "$GITHUB_PATH"
"$BIN" --version
```

Sürüm yükseltme: `XCODEGEN_VERSION` + `XCODEGEN_SHA256` birlikte değiştirilir (`sha256sum xcodegen.zip`).

### 2.4 AsistCore testleri: Linux mı macOS mu?

**Karar: Linux (`ubuntu-24.04` + `container: swift:6.3-noble`).** Konteyner etiketinin varlığı Docker
Hub API'siyle doğrulandı (`6.3-noble`, `6.3.3-noble` → 200). Tam (slim olmayan) Swift imajı `tzdata`
kurar. [VERIFIED: https://github.com/swiftlang/swift-docker/blob/main/6.2/ubuntu/24.04/Dockerfile —
6.3 için aynı şablon varsayıldı, iş "Ortam bilgisi" adımında `/usr/share/zoneinfo/Europe/Istanbul`'u kontrol eder]

Runner'da önceden kurulu Swift 6.4 de kullanılabilir (konteyner çekme süresi olmaz) ama Xcode 26.x'in
Swift 6.3'ünden ileride olduğu için **sürüm eşliği** adına konteyner seçildi.

Linux'ta Foundation: Swift 6'dan beri `Calendar`, `Locale`, `TimeZone`, `Data`, `JSONDecoder`,
`PropertyListDecoder` **swift-foundation** (Swift ile yeniden yazılmış, ICU verisi `FoundationICU` ile gömülü)
tarafından sağlanır; Apple dışı platformlar için uyumluluk resmi olarak "best-effort"tur.
[VERIFIED: https://github.com/swiftlang/swift-foundation]

**Linux/Apple eşlik tuzakları (AsistCore yazarları için bağlayıcı):**

| # | Tuzak | Kural |
|---|---|---|
| L1 | CI'da `TimeZone.current` = UTC, `Locale.current` = POSIX/`en_US_POSIX`, `Calendar.current.firstWeekday` = 1. | Ayrıştırıcı ve planlayıcı **asla** `.current` kullanmaz; `Calendar`, `TimeZone(identifier: "Europe/Istanbul")`, `Locale(identifier: "tr_TR")` ve "şimdi" (`Date`) **enjekte** edilir. `firstWeekday = 2` açıkça atanır. |
| L2 | `tzdata` eksik imajda `TimeZone(identifier:)` `nil` döner. | Tam imaj (`-slim` değil). Bir test `TimeZone(identifier: "Europe/Istanbul")?.secondsFromGMT(for:) == 10800` doğrular. |
| L3 | Türkçe büyük/küçük harf: `"I".lowercased()` → `"i"` (Türkçede `ı` olmalı), `"İ".lowercased()` → `"i̇"` (i + birleşik nokta). ICU sürümleri farklı olabilir. | Metin normalleştirme **kendi tablomuzla** (İ→i, I→ı, sonra gerekirse ı→i katlama) yapılır; `lowercased(with:)`'a güvenilmez. |
| L4 | `DateFormatter`/`Date.FormatStyle` çıktıları (ay/gün adları, "Salı") CLDR/ICU sürümüne bağlı; Apple OS ICU'su ile FoundationICU farklı olabilir. | Ayrıştırma için gün/ay adları **sabit tablodan**; testlerde biçimlenmiş dize karşılaştırılmaz. |
| L5 | Swift 5 dil modunda `/…/` regex literali **derlenmez** (`BareSlashRegexLiterals` gerekir); `#/…/#` her zaman çalışır. [VERIFIED: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0354-regex-literals.md] | `#/…/#`, `try Regex("…")` veya `NSRegularExpression` kullan. |
| L6 | `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, `os.Logger`, `Combine`, `UserNotifications` Linux'ta yok. | `#if canImport(Darwin)` / `#if canImport(os)` ile koru veya uygulama hedefine koy. |
| L7 | `Calendar.nextDate(after:matching:matchingPolicy:)` gibi karmaşık aramalar sürümler arasında kenar durumlarda farklı olabilir. [UNVERIFIED] | Tarih hesabında `date(byAdding:)`, `dateComponents`, `date(from:)`, `date(bySettingHour:minute:second:of:)` gibi basit API'ler tercih edilir; her kural için Linux'ta birim testi. Türkiye 2016'dan beri sabit UTC+3 (yaz saati yok) — yine de TZ verisine güvenmek yerine test. |
| L8 | Linux'ta test keşfi otomatik; `async` XCTest desteklenir. | `XCTestManifests.swift`/`LinuxMain.swift` **yazmayın**. |
| L9 | Testte `Bundle.module` kaynakları için `resources:` gerekir. | Fixture'lar test kodunda satır içi `Data`/dize olarak tutulur. |

İsteğe bağlı eşlik kontrolü: ayda bir `workflow_dispatch` ile macOS'ta da `swift test` (10× maliyet).

### 2.5 Cihaz derlemesi ve IPA paketleme

**Neden `build` + elle Payload, `archive` + `-exportArchive` değil:** `-exportArchive` imzalama kimliği ve
profil ister; bizde yok. `xcodebuild archive … CODE_SIGNING_ALLOWED=NO` da çalışır (uygulama
`Asist.xcarchive/Products/Applications/Asist.app` altında olur) ama sonuç yine elle zip'lenir; `build`
daha basit. Aynı bayrak seti (`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
DEVELOPMENT_TEAM=""`, `-destination generic/platform=iOS`) ile XcodeGen + widget'lı bir projenin
Xcode 27 önizleme runner'ında derlendiği açık kaynak örnek incelendi.
[VERIFIED: https://github.com/JosephLteif/pocket-ledger/blob/main/.github/workflows/ios-build.yml]

**Neden ad-hoc entitlement imzası (D6):** `CODE_SIGNING_ALLOWED=NO` ile ikilide **hiç kod imzası yoktur**,
dolayısıyla gömülü entitlement da yoktur. AltStore, App Group'ları **ikilinin imzasındaki entitlement'lardan**
okuyup kaydeder (`app.entitlements[.appGroups]`) ve ücretsiz hesapta grup kimliğine `"." + team.identifier`
ekler; yeniden imzalarken Info.plist'e `ALTAppGroups` yazar. [VERIFIED:
https://github.com/altstoreio/AltStore/blob/master/AltStore/Operations/FetchProvisioningProfilesOperation.swift
(satır ~328, ~393, ~444) ve .../ResignAppOperation.swift (satır ~126)] Sideloadly'nin aynı şeyi yapıp
yapmadığı doğrulanamadı (§3.2). `codesign --sign -` ile ad-hoc imza + `--entitlements` bu bilgiyi ikiliye
koyar; imzalayıcı zaten kendi imzasıyla değiştirir. Risk: bir imzalayıcı entitlement'ı taşıyıp profilde
karşılığını oluşturmazsa kurulum reddedilir → **`Asist-imzasiz.ipa` yedeği**.

`Scripts/ci/package-ipa.sh`
```bash
#!/usr/bin/env bash
# Asist.app -> iki IPA:
#   Asist.ipa          : uygulama + widget ad-hoc imzalı, entitlement'lar (App Group) imzaya gömülü.
#                        İkili içinden entitlement okuyan yeniden imzalayıcılar (ör. AltStore) App
#                        Group'u buradan öğrenir.
#   Asist-imzasiz.ipa  : hiç imza/entitlement yok. Asist.ipa kurulumda entitlement hatası verirse
#                        bununla kurulur (widget veri paylaşımı olmadan çalışır).
# Kullanım: package-ipa.sh <.../Release-iphoneos/Asist.app> <çıktı klasörü>
set -euo pipefail

APP_SRC="$1"
OUT="$2"
APP_NAME="$(basename "$APP_SRC")"                       # Asist.app
EXE_NAME="${APP_NAME%.app}"                             # Asist
WIDGET_REL="PlugIns/AsistWidgets.appex"
APP_ENT="Generated/Asist.entitlements"
WIDGET_ENT="Generated/AsistWidgets.entitlements"

fail() { echo "::error::$*"; exit 1; }

# --- Ön doğrulama ---------------------------------------------------------
[ -d "$APP_SRC" ]                       || fail "Uygulama paketi yok: $APP_SRC"
[ -f "$APP_SRC/$EXE_NAME" ]             || fail "Çalıştırılabilir dosya yok: $APP_SRC/$EXE_NAME"
[ -d "$APP_SRC/$WIDGET_REL" ]           || fail "Widget uzantısı gömülmemiş: $WIDGET_REL"
[ -f "$APP_SRC/Assets.car" ]            || fail "Derlenmiş asset kataloğu (Assets.car) yok"
[ -f "$APP_ENT" ] && [ -f "$WIDGET_ENT" ] || fail "Entitlement dosyaları yok (xcodegen çalıştı mı?)"

PB=/usr/libexec/PlistBuddy
APP_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/Info.plist")
WID_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/$WIDGET_REL/Info.plist")
APP_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/Info.plist")
WID_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/$WIDGET_REL/Info.plist")
SHORT=$($PB -c 'Print :CFBundleShortVersionString' "$APP_SRC/Info.plist")
case "$WID_ID" in "$APP_ID".*) ;; *) fail "Widget kimliği ($WID_ID) uygulama kimliğiyle ($APP_ID) önekli değil" ;; esac
[ "$APP_VER" = "$WID_VER" ] || fail "CFBundleVersion uyuşmuyor: app=$APP_VER widget=$WID_VER"
ARCHS="$(lipo -archs "$APP_SRC/$EXE_NAME")"
[[ "$ARCHS" == *arm64* ]] || fail "arm64 dilimi yok (bulunan: $ARCHS)"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"

make_ipa() {  # $1 = hazırlık klasörü (içinde Payload/), $2 = ipa yolu
  rm -f "$2"
  (cd "$1" && zip -qry -X "$2" Payload)
  # Not: `unzip | grep -q` pipefail altında SIGPIPE (141) ile sahte hata verebilir -> önce dosyaya yaz.
  unzip -Z1 "$2" > "$WORK/liste.txt"
  grep -q "^Payload/$APP_NAME/$WIDGET_REL/" "$WORK/liste.txt" || fail "IPA içinde widget yok: $2"
}

# --- 1) Yedek: tamamen imzasız ---------------------------------------------
mkdir -p "$WORK/plain/Payload"
ditto "$APP_SRC" "$WORK/plain/Payload/$APP_NAME"
make_ipa "$WORK/plain" "$OUT/Asist-imzasiz.ipa"

# --- 2) Ana: ad-hoc imza + entitlement (önce iç paket, sonra dış paket) ------
mkdir -p "$WORK/signed/Payload"
ditto "$APP_SRC" "$WORK/signed/Payload/$APP_NAME"
S="$WORK/signed/Payload/$APP_NAME"
codesign --force --sign - --timestamp=none --entitlements "$WIDGET_ENT" "$S/$WIDGET_REL"
codesign --force --sign - --timestamp=none --entitlements "$APP_ENT" "$S"
echo "--- Gömülü entitlement'lar (uygulama) ---"
codesign -d --entitlements - "$S" 2>/dev/null || true
make_ipa "$WORK/signed" "$OUT/Asist.ipa"

# --- Özet ---------------------------------------------------------------------
{
  echo "### IPA"
  echo "| Dosya | Boyut | SHA-256 |"
  echo "|---|---|---|"
  for F in "$OUT/Asist.ipa" "$OUT/Asist-imzasiz.ipa"; do
    echo "| $(basename "$F") | $(du -h "$F" | cut -f1) | \`$(shasum -a 256 "$F" | cut -c1-16)…\` |"
  done
  echo ""
  echo "- Bundle ID: \`$APP_ID\` / widget \`$WID_ID\`"
  echo "- Sürüm: $SHORT ($APP_VER)"
} >> "$GITHUB_STEP_SUMMARY"
ls -la "$OUT"
```

Betik `bash -n` ile sözdizimi denetimi geçti. macOS'a özgü araçlar (`ditto`, `codesign`, `PlistBuddy`,
`lipo`, `shasum`) yalnız runner'da çalışır; ilk CI koşusu bunları doğrular. Tuzaklar:
- `set -o pipefail` + `… | grep -q` → SIGPIPE ile sahte hata; betik listeyi önce dosyaya yazar.
- İç paket (appex) **önce**, dış paket (app) **sonra** imzalanır; ters sıra dış imzayı bozar.
- iOS 17+ hedefte Swift runtime OS'tadır; `Frameworks/` klasörü oluşmaz (statik paket). İleride dinamik
  framework eklenirse o da appex'ten önce imzalanmalıdır.

### 2.6 İş akışı — `.github/workflows/ci.yml` (tam)

YAML `yaml.safe_load` ile doğrulandı. `shell: bash` açıkça verildiğinde GitHub
`bash --noprofile --norc -eo pipefail {0}` çalıştırır (belirtilmezse yalnız `bash -e {0}` — **pipefail yok**,
`xcodebuild | xcbeautify` hatası yutulur). [VERIFIED: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax]
`upload-artifact@v7` `archive: false` ile tek dosyayı zip'lemeden yükler; artifact adı dosya adıdır.
[VERIFIED: https://github.com/actions/upload-artifact/blob/main/action.yml] Eylem sürümleri (2026-09-27):
`actions/checkout` v7.0.1, `actions/upload-artifact` v7.0.1, `actions/cache` v6.1.0. [VERIFIED: GitHub releases API]

````yaml
name: Asist CI

on:
  push:
    branches: [main]
    paths-ignore:
      - "docs/**"
      - "**/*.md"
  workflow_dispatch:
    inputs:
      mod:
        description: "ipa = IPA üret | derle = yalnız derleme kontrolü (paket yok)"
        type: choice
        options: [ipa, derle]
        default: ipa
      xcode:
        description: "Xcode seçimi: boş = en yeni 26.x | '26.5' | tam yol"
        type: string
        required: false
        default: ""

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

defaults:
  run:
    shell: bash          # => bash --noprofile --norc -eo pipefail {0}

jobs:
  core-tests:
    name: AsistCore testleri (Linux, Swift 6.3)
    runs-on: ubuntu-24.04
    container: swift:6.3-noble
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7
      - name: Ortam bilgisi
        run: |
          swift --version
          ls /usr/share/zoneinfo/Europe/Istanbul
      - name: swift build + swift test
        working-directory: Packages/AsistCore
        run: |
          swift build --build-tests 2>&1 | tee "$RUNNER_TEMP/swift-build.log"
          swift test --skip-build --parallel 2>&1 | tee "$RUNNER_TEMP/swift-test.log"
      - name: Hata özeti
        if: failure()
        run: |
          {
            echo "## AsistCore hataları"
            echo '```'
            grep -hE "error:|failed|XCTAssert" "$RUNNER_TEMP"/swift-*.log | sort -u | head -80 || true
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

  ios:
    name: iOS derleme + IPA (macOS 26)
    runs-on: macos-26
    timeout-minutes: 40
    env:
      XCODE_MAJOR: "26"
      XCODEGEN_VERSION: "2.46.0"
      XCODEGEN_SHA256: "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
      MOD: ${{ inputs.mod || 'ipa' }}
    steps:
      - uses: actions/checkout@v7

      - name: Xcode seç
        env:
          XCODE_REQ: ${{ inputs.xcode }}
        run: bash Scripts/ci/select-xcode.sh "$XCODE_REQ"

      - name: XcodeGen kur (sabit sürüm + SHA256)
        run: bash Scripts/ci/install-xcodegen.sh

      - name: Xcode projesini üret
        run: |
          xcodegen generate --spec project.yml 2>&1 | tee "$RUNNER_TEMP/xcodegen.log"
          if grep -q "settings found" "$RUNNER_TEMP/xcodegen.log"; then
            echo "::error::XcodeGen SettingPresets bulunamadı; kurulum bozuk."
            exit 1
          fi
          xcodebuild -list -project Asist.xcodeproj

      - name: Derle (iphoneos, imzasız)
        run: |
          CONFIG=Release
          if [ "$MOD" = "derle" ]; then CONFIG=Debug; fi
          FMT="cat"
          if command -v xcbeautify >/dev/null; then FMT="xcbeautify --renderer github-actions"; fi
          echo "CONFIG=$CONFIG" >> "$GITHUB_ENV"
          xcodebuild \
            -project Asist.xcodeproj \
            -scheme Asist \
            -configuration "$CONFIG" \
            -sdk iphoneos \
            -destination "generic/platform=iOS" \
            -derivedDataPath "$RUNNER_TEMP/DD" \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            DEVELOPMENT_TEAM="" \
            CURRENT_PROJECT_VERSION="${{ github.run_number }}" \
            COMPILER_INDEX_STORE_ENABLE=NO \
            build 2>&1 | tee "$RUNNER_TEMP/xcodebuild.log" | $FMT

      - name: Derleme hata özeti
        if: failure()
        run: bash Scripts/ci/error-summary.sh "$RUNNER_TEMP/xcodebuild.log"

      - name: IPA paketle
        if: env.MOD == 'ipa'
        run: |
          bash Scripts/ci/package-ipa.sh \
            "$RUNNER_TEMP/DD/Build/Products/${CONFIG}-iphoneos/Asist.app" \
            "$RUNNER_TEMP/out"

      - name: Yükle — Asist.ipa (entitlement gömülü, ad-hoc)
        if: env.MOD == 'ipa'
        uses: actions/upload-artifact@v7
        with:
          path: ${{ runner.temp }}/out/Asist.ipa
          archive: false
          retention-days: 14
          if-no-files-found: error

      - name: Yükle — Asist-imzasiz.ipa (yedek)
        if: env.MOD == 'ipa'
        uses: actions/upload-artifact@v7
        with:
          path: ${{ runner.temp }}/out/Asist-imzasiz.ipa
          archive: false
          retention-days: 14
          if-no-files-found: error

      - name: Yükle — üretilen Xcode projesi
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: Asist-xcodeproj
          path: |
            Asist.xcodeproj
            Generated
          retention-days: 7
          if-no-files-found: warn

      - name: Yükle — derleme günlükleri
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: derleme-gunlukleri
          path: |
            ${{ runner.temp }}/xcodebuild.log
            ${{ runner.temp }}/xcodegen.log
          retention-days: 7
          if-no-files-found: ignore
````

Notlar:
- `CURRENT_PROJECT_VERSION` komut satırında verildiği için **tüm hedeflere** (app + widget) aynı değer gider → `CFBundleVersion` eşleşir.
- `inputs.xcode` doğrudan `run:` içine gömülmez, `env:` üzerinden geçer (betik enjeksiyonu önlemi).
- `concurrency.cancel-in-progress` art arda push'larda eski macOS işini iptal eder (dakika tasarrufu).
- İki iş **paralel** çalışır (daha hızlı geri bildirim). Maliyet önceliklendirilirse `ios` işine
  `needs: core-tests` eklenir; Linux testi kırılınca macOS dakikası harcanmaz.
- `timeout-minutes: 40` → takılan bir derleme 6 saatlik varsayılan süre boyunca dakika yakmaz.

### 2.7 Hata özeti — `Scripts/ci/error-summary.sh`

````bash
#!/usr/bin/env bash
# xcodebuild günlüğünden derleyici hatalarını çıkarıp iş özetine (Summary) yazar.
# Kullanım: error-summary.sh <xcodebuild.log>
set -uo pipefail
LOG="${1:?log yolu}"
[ -f "$LOG" ] || { echo "Günlük yok: $LOG"; exit 0; }

{
  echo "## Derleme hataları"
  echo '```'
  # Swift/Clang tanıları: /yol/Dosya.swift:12:5: error: ...
  grep -E ":[0-9]+:[0-9]+: (fatal )?error:" "$LOG" | sed -E "s#^.*/(App|Widgets|Shared|Packages)/#\1/#" | sort -u | head -60
  # Konumsuz hatalar (imza, plist, bağlama, eksik dosya)
  grep -E "^(error|fatal error|ld: error|clang: error): " "$LOG" | sort -u | head -20
  echo '```'
  echo "### Başarısız komutlar"
  echo '```'
  grep -A 25 "The following build commands failed:" "$LOG" | head -30
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"

grep -cE ":[0-9]+:[0-9]+: (fatal )?error:" "$LOG" | xargs -I{} echo "Toplam derleyici hatası satırı: {}"
exit 0
````

### 2.8 Derleyici hatalarını görünür kılma (Windows'tan)

1. **Satır içi açıklama:** `xcbeautify --renderer github-actions` hataları commit/Actions arayüzünde
   dosya:satır açıklaması olarak basar (runner'da xcbeautify 3.2.1 kurulu). [VERIFIED: https://github.com/cpisciotta/xcbeautify ; macos-26-arm64-Readme.md]
2. **Summary sekmesi:** `error-summary.sh` hataları yolu kısaltılmış (`App/…`, `Widgets/…`) ve tekilleştirilmiş listeler.
3. **Ham günlük:** `derleme-gunlukleri` artifact'ı (tam `xcodebuild.log`).
4. **Üretilen proje:** `Asist-xcodeproj` artifact'ı — build ayarı/plist şüphesinde incelenir.
5. Yerel yardım: `gh run view --log-failed` (GitHub CLI, Windows'ta çalışır) başarısız adımın günlüğünü terminale döker.

### 2.9 Dakika maliyeti ve önbellek

| Kalem | Değer |
|---|---|
| Özel depo dahil dakika | Free 2 000 / Pro 3 000 dk/ay; depolama 500 MB / 1 GB; önbellek 10 GB/depo. [VERIFIED: https://docs.github.com/en/billing/concepts/product-billing/github-actions] |
| Çarpan | macOS dakikası dahil kotadan **10×** düşer (Linux 1×). [VERIFIED (ikincil, birden çok kaynak): https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions arama özeti; birincil sayfada çarpan metni bulunamadı] |
| Aşım fiyatı | macOS 3/4 çekirdek **$0.062/dk**, Linux 2 çekirdek $0.006/dk. Süre iş başına yukarı yuvarlanır. [VERIFIED: https://docs.github.com/en/billing/reference/actions-runner-pricing] |
| Genel (public) depo | Standart runner **ücretsiz**. [VERIFIED: aynı sayfa] |
| Tahmini iOS işi | 6–10 faturalanan dk → 60–100 dahil dk [UNVERIFIED: tahmin; ilk koşunun "Billable time" değeriyle güncellenecek] |
| Free planda aylık IPA sayısı | ≈ 20–30 derleme (+ Linux testleri ihmal edilebilir) |

Öneriler:
- `paths-ignore` ile yalnız doküman değişikliği macOS'u tetiklemez; `workflow_dispatch` ile elle tetikleme.
- `mod: derle` (Debug, paketleme yok) hızlı "derleniyor mu?" kontrolü; kazanç büyük değil (xcodebuild açılışı
  ve paket derlemesi baskın) [UNVERIFIED].
- **Önbellek kullanılmıyor:** uzak SwiftPM bağımlılığı yok (çözümleme süresi ~0); DerivedData önbelleği mutlak
  yol/zaman damgası nedeniyle güvenilmez ve geri yükleme süresi küçük projede kazancı yer. İleride uzak paket
  eklenirse `actions/cache@v6` ile `~/Library/Caches/org.swift.swiftpm` + `-clonedSourcePackagesDirPath` önbelleklenir.
- Artifact saklama 14/7 gün → Free plandaki 500 MB'ın altında kalır (IPA birkaç MB).
- Kota biterse işler durur; ödeme yöntemi + bütçe (ör. $5) tanımlanabilir ya da depo public yapılabilir
  (depoda sır yok; API anahtarı cihazda Keychain'de).

### 2.10 "Yalnız tip denetimi" seçeneği

- Uygulama katmanı (SwiftUI/UIKit/WidgetKit) **Linux'ta derlenemez**; tip denetimi için macOS şart.
- `swiftc -typecheck` ile elle SDK/hedef/AsistCore modül yolları vermek mümkün ama App Intents metadata,
  asset sembolleri ve widget `@main` ayrımı yüzünden kırılgandır → **önerilmez**.
- Pratik "hızlı" yol: `workflow_dispatch` → `mod: derle` (Debug, `COMPILER_INDEX_STORE_ENABLE=NO`, paketleme ve IPA yüklemesi yok).
- En ucuz erken uyarı: AsistCore Linux işi (1× dakika) — çekirdek mantık hatalarının çoğunu yakalar.

---

## 3. Windows + Sideloadly + ücretsiz Apple ID

### 3.1 Gerçekler ve sınırlar

| Konu | Değer | Güven |
|---|---|---|
| Windows gereksinimi | **Microsoft Store dışı ("web") iTunes ve iCloud**; Store sürümleri kaldırılmalı. | [VERIFIED: https://sideloadly.io/faq ; https://sideloadly.io/] |
| Sideloadly sürümü | v0.60.0; "iOS 7 — 26+" destekler. | [VERIFIED: https://sideloadly.io/] |
| Uygulama ömrü | Ücretsiz hesapta **7 gün**; ücretli hesapta ~1 yıl. | [VERIFIED: https://sideloadly.io/faq] |
| Aktif uygulama sınırı | Ücretsiz hesapla **3** yan yüklenmiş uygulama. | [VERIFIED: https://sideloadly.io/faq] |
| App ID sınırı | **7 günde 10 App ID.** Her uygulama **ve her uzantısı** ayrı App ID tüketir; App ID'ler bir hafta sonra düşer. Sideloadly v0.55+ kalan haftalık App ID sayısını gösterir. | [VERIFIED: https://sideloadly.io/faq ; https://faq.altstore.io/altstore-classic/app-ids ; https://sideloadly.io/changelog] |
| Asist'in tüketimi | Uygulama + widget = **2 App ID / kurulum-haftası**; 3 aktif uygulama sınırında **1 yer** (uzantılar ayrı uygulama sayılmaz). | App ID: VERIFIED (yukarıdaki kural). Uzantının 3'lü sınıra sayılmaması: [UNVERIFIED: çıkarım — AltStore kendi widget uzantısıyla birlikte "AltStore + 2 uygulama" olarak raporlanıyor] |
| Veri korunması | Aynı Apple ID + aynı bundle ID ile üstüne kurulum **yerel veriyi korur**. | [VERIFIED: https://sideloadly.io/faq] |
| Otomatik yenileme | Sideloadly Daemon; bilgisayar açık, cihaz USB ya da aynı Wi-Fi'da (Wi-Fi eşitleme bir kez USB ile kurulur). | [VERIFIED: https://sideloadly.io/faq] |
| Geliştirici Modu | iOS 16+ zorunlu: Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu. Anahtar yalnız cihaz bir bilgisayarla eşleşince görünür; açınca yeniden başlatma + "Aç" onayı + parola. | [VERIFIED: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device ; Türkçe yol: https://teknofix.com.tr/iphone-gelistirici-modu-acma] |
| Profile güven | Ayarlar > Genel > VPN ve Aygıt Yönetimi > (Apple ID e-postası) > Güven. | [VERIFIED (İngilizce yol): Sideloadly FAQ; Türkçe menü adı "VPN ve Aygıt Yönetimi" Apple TR destek metinlerinde geçiyor] |
| İmza modları | Advanced Options → Signing Mode: **Apple ID Sideload (varsayılan)**, Normal Install, Ad-hoc sign; ayrıca .p12. "Remove app extensions", bundle ID/ad değiştirme seçenekleri var. | [VERIFIED (ikincil): arama özeti, https://onejailbreak.com/blog/sideloadly/ ; tam etiket metni UNVERIFIED] |
| Bundle ID "mangling" | Sideloadly bazı iOS sürümlerinde bundle ID'yi değiştirebilir ("will mangle bundleID" günlüğü; anisette seçeneği kapalıysa devre dışı). | [VERIFIED: https://sideloadly.io/changelog (v0.9.2, v0.19.0) ; https://gist.github.com/robonxt/fe91254c8070cfe84c6add1dcc0ead88] |
| Özel entitlement | "Added support for custom app entitlements (**Apple Developer Program only**)" — v0.60.0, Patreon özelliği. | [VERIFIED: https://sideloadly.io/changelog] |

### 3.2 App Group ve entitlement'lar ücretsiz imzada — analiz ve tasarım sonucu

1. **Apple tarafı:** Ücretsiz "Apple Developer" hesabı App Group'u destekler; Time-Sensitive, Siri, Push,
   iCloud desteklenmez. [VERIFIED §1.6]
2. **AltStore tarafı:** Entitlement'ları ikilinin imzasından okur, grubu `group.com.gokhanbudak.asist.<TEAMID>`
   olarak kaydeder, Info.plist'e `ALTAppGroups` yazar, `CFBundleIdentifier`'ı profildeki kimlikle değiştirir.
   [VERIFIED: AltStore kaynak kodu, §2.5]
3. **Sideloadly tarafı:** App Group davranışı **belgelenmemiş**. Changelog'da özel entitlement desteği yalnız
   ücretli hesap için. En olası sonuç: ücretsiz hesapta **App Group yok**. [UNVERIFIED: ilk kurulumda
   Asist > Ayarlar > Sistem Durumu "Paylaşılan alan" satırıyla ölçülecek]
4. **iOS davranışı:** `containerURL(forSecurityApplicationGroupIdentifier:)` iOS'ta **entitlement yoksa `nil`**
   döner (macOS'ta her zaman URL döner). Grup konteyneri, gruptaki tüm uygulamalar silinince silinir.
   [VERIFIED: https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)]

**Tasarıma bağlayıcı sonuçlar:**
- **Ana veri deposu = uygulamanın kendi `Application Support/Asist/` klasörü.** İmza yöntemi değişse
  (App Group var→yok) bile veri kaybolmaz. App Group'a *birincil* veri koymak, grubun bir sonraki
  imzada kaybolması durumunda uygulamanın "boş" açılmasına yol açar — kabul edilemez.
- App Group çözülürse: uygulama widget için küçük bir **salt-okunur anlık görüntü** (JSON) yazar
  (`<grup>/Library/Application Support/WidgetSnapshot.json`).
- App Group yoksa: widget'lar "başlatıcı" moduna düşer (Dinle / Bugün / Yeni not düğmeleri →
  `asist://…` derin bağlantıları, `openAppWhenRun`/`OpenIntent`). **Dinamik bilgi** (aktif ısrarlı hatırlatıcı,
  sonraki iş) **Live Activity** ile gösterilir — App Group gerektirmez.
- Veri yazan App Intent'ler **uygulama sürecinde** çalışmalı (uygulama hedefinde tanımlı, veya uygulamayı
  açan intent). Widget uzantısı süreci App Group olmadan uygulama verisine erişemez.
- Anahtarlık: varsayılan erişim grubu takım önekine bağlıdır. **Aynı Apple ID** ile yeniden imzada Claude API
  anahtarı okunmaya devam eder; farklı Apple ID'de okunamaz → uygulama `errSecItemNotFound`'u "anahtarı
  yeniden girin" olarak ele almalı. [UNVERIFIED: davranış iOS anahtarlık erişim grubu kuralından çıkarım]
- Kodda bundle ID ve grup kimliği **sabit karşılaştırılmaz**; `BGTaskSchedulerPermittedIdentifiers`, bildirim
  kimlikleri, widget `kind` dizeleri ve URL şeması bundle ID'den bağımsızdır (mangling'den etkilenmez).
- Alternatif imzalayıcı: App Group'lu widget verisi şartsa **AltStore Classic (AltServer, Windows)** App Group'u
  ücretsiz hesapta kaydeder (kaynakta doğrulandı); ancak AltStore'un kendisi 3'lü sınırdan 1 yer daha kullanır.

### 3.3 Kullanıcı kılavuzu — ilk kurulum (Türkçe)

> Bu bölüm `docs/KURULUM.md` olarak da depoya konur. Apple ID şifresini ve iki adımlı doğrulama kodunu
> **kullanıcı kendisi** Sideloadly'ye girer.

**A. Bilgisayarı bir kez hazırla (Windows 10)**
1. Microsoft Store'dan kurulmuş **iTunes** veya **iCloud** varsa kaldır.
2. apple.com'dan **Windows (64 bit) iTunes** ve Store dışı **iCloud** kurulum dosyalarını indirip kur
   (Sideloadly sitesindeki "web iTunes / web iCloud" bağlantıları).
3. **Sideloadly**'yi yalnızca resmi siteden (sideloadly.io) indirip kur.
4. iPhone'u USB kabloyla bağla. iPhone'da **"Bu Bilgisayara Güvenilsin mi?" → Güven** ve parolanı gir.
5. (Önerilir) iTunes'ta iPhone simgesi → Özet → **"Bu iPhone ile Wi-Fi üzerinden eşzamanla"** kutusunu işaretle
   → Uygula. Böylece Sideloadly kablosuz yenileme yapabilir.

**B. IPA'yı indir**
6. GitHub → depo → **Actions** → en son **yeşil (✓)** "Asist CI" çalıştırması → sayfanın altındaki
   **Artifacts** → **Asist.ipa**'yı indir (zip değildir, doğrudan .ipa gelir).

**C. Sideloadly ile yükle**
7. Sideloadly'yi aç; üstte iPhone'un seçili olduğunu gör.
8. `Asist.ipa`'yı pencereye sürükle.
9. **Apple account** kutusuna Apple ID e-postanı yaz. Her seferinde **aynı Apple ID**'yi kullan
   (farklı Apple ID = veriler görünmez, API anahtarı yeniden girilir).
10. **Advanced Options**: Signing Mode = **Apple ID Sideload**; **"Remove app extensions" işaretli OLMASIN**
    (widget için); **Bundle ID / App name değiştirme KAPALI** kalsın.
11. **Start** → şifre ve iki adımlı doğrulama kodunu gir → "Done" yazısını bekle.

**D. iPhone'da bir kerelik ayarlar**
12. **Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu** → Aç → **Yeniden Başlat**. Açılışta çıkan uyarıda
    **Aç**'a dokun ve parolanı gir. (Anahtar görünmüyorsa önce 11. adımı tamamla; eşleşme sonrası görünür.)
13. **Ayarlar > Genel > VPN ve Aygıt Yönetimi** → Apple ID e-postan → **"… Güven"** → Güven.
14. **Asist**'i aç; Bildirim, Mikrofon, Konuşma Tanıma izinlerine **İzin Ver** de.
15. Asist > Ayarlar > **Sistem Durumu**: "İmza bitişi" tarihini ve "Paylaşılan alan (widget)" durumunu kontrol et.

**E. Sorun olursa**
- Kurulumda "entitlement", "0xe8008016" veya "invalid entitlements" benzeri bir hata çıkarsa aynı çalıştırmadaki
  **Asist-imzasiz.ipa** dosyasını kullan (tüm özellikler çalışır; yalnız widget uygulama verisini göremeyebilir).
- "Maximum App ID limit" → 7 gün bekle veya Sideloadly'de kalan App ID sayısını kontrol et; Asist her kurulumda 2 App ID harcar. Bundle ID'yi değiştirerek deneme yapma — her deneme yeni App ID harcar.
- "maximum number of apps" → cihazdaki diğer yan yüklenmiş uygulamalardan birini sil (en fazla 3).
- Cihaz görünmüyor → iTunes/iCloud Store dışı sürüm mü, kablo/güven onayı verildi mi kontrol et.
- Profil/imza doğrulama hatası → bilgisayar ve iPhone saat/tarihinin doğru olduğundan emin ol. [VERIFIED: Sideloadly FAQ]

### 3.4 Haftalık yenileme ve güncelleme

- **Her 7 günde bir** (Asist 48 ve 24 saat önce bildirim gönderir): Sideloadly'yi aç → aynı IPA'yı (veya CI'daki
  daha yeni IPA'yı) **aynı Apple ID** ile yükle → **veriler korunur**. [VERIFIED: Sideloadly FAQ]
- Ya da Sideloadly'nin **otomatik yenileme** özelliğini aç (bilgisayar açık, iPhone aynı Wi-Fi'da).
- **Yeniledikten sonra Asist'i bir kez aç.** Apple forumunda, güncelleme sonrası bekleyen yerel bildirimlerin
  uygulama yeniden açılana kadar **teslim edilmediği** raporlanmıştır (Apple mühendisi aksini söylese de).
  [VERIFIED (rapor): https://developer.apple.com/forums/thread/772031] Asist açılışta profil
  `CreationDate` değişimini algılar ve tüm hatırlatıcı bildirimlerini baştan kurar (§4.4).
- **Asist'i asla silme** — silmek tüm yerel veriyi ve (varsa) grup konteynerini siler.
- Yeni sürüm kurmak = yenilemeyle aynı işlem (üstüne kurulum).

### 3.5 İmza süresi dolunca ne olur?

| Soru | Cevap | Güven |
|---|---|---|
| Uygulama açılır mı? | Hayır; profil geçersizken iOS uygulamayı başlatmaz. Veriler cihazda durur. | Profil "ne zaman çalışabilir" ölçütünü `ExpirationDate` ile belirler [VERIFIED: TN3125 https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles]; açılışın tam hata ekranı [UNVERIFIED] |
| Önceden kurulmuş yerel bildirimler çalar mı? | **Bilinmiyor.** Bildirimleri sistem teslim eder (uygulama kodu çalışmaz) ama iOS'un süresi dolmuş profilli uygulamanın bildirimlerini bastırıp bastırmadığına dair birincil kaynak bulunamadı. Çalsalar bile "Tamam/Ertele" eylemleri uygulamayı başlatamayacağı için çalışmaz. | [UNVERIFIED] |
| Yeniden imzada veri? | Aynı Apple ID + aynı bundle ID → korunur. | [VERIFIED: Sideloadly FAQ] |

**Önlem:** Süre dolmasını bir arıza olarak ele al: 48 s / 24 s / 4 s önce uyarı bildirimi (bunlar imza
geçerliyken kurulduğu için bitişten **önce** çalar), Ayarlar'da geri sayım, ve ısrarlı (nag) hatırlatıcı
zincirinin bitiş tarihinden sonrasına düşen kısmı için kullanıcıya "imzayı yenile" uyarısı.

---

## 4. Çalışma anında `embedded.mobileprovision` okuma

Profil, Apple imzalı bir CMS (PKCS#7) zarfı içinde düz XML plist'tir; iOS'ta paket kökünde
`MyApp.app/embedded.mobileprovision` olarak bulunur; her profilin `ExpirationDate` alanı vardır.
[VERIFIED: TN3125] Apple bu biçimin **API olmadığını**, yapının değişebileceğini söyler → kod her alanı
isteğe bağlı ele alır ve okuyamazsa sessizce `nil` döner (özellik yalnız bilgilendirme amaçlı).
Simülatörde, App Store kurulumunda ve imzasız IPA'da dosya yoktur → `nil`.
Uzantıda `Bundle.main` = `.appex` paketidir; her uzantının kendi profili vardır.

### 4.1 `Packages/AsistCore/Sources/AsistCore/Platform/ProvisioningProfile.swift`

Yalnız Foundation; `PropertyListDecoder` ve `Data.range(of:options:in:)` Linux'ta da vardır → Linux CI'da test edilir.
`String(data:encoding:.utf8)` **kullanılmaz** (CMS ikili baytları geçersiz UTF-8 → `nil`); arama bayt düzeyinde yapılır.

```swift
import Foundation

/// Uygulama paketindeki `embedded.mobileprovision` dosyasının özet bilgisi.
/// Biçim Apple'ın resmi API'si değildir (TN3125); tüm alanlar isteğe bağlı ele alınır.
public struct ProvisioningProfileInfo: Equatable, Sendable {
    public var name: String?
    public var teamName: String?
    public var teamIdentifier: String?
    public var creationDate: Date?
    public var expirationDate: Date
    public var appGroups: [String]
    public var getTaskAllow: Bool
    public var provisionsAllDevices: Bool
    public var provisionedDeviceCount: Int

    public init(name: String? = nil,
                teamName: String? = nil,
                teamIdentifier: String? = nil,
                creationDate: Date? = nil,
                expirationDate: Date,
                appGroups: [String] = [],
                getTaskAllow: Bool = false,
                provisionsAllDevices: Bool = false,
                provisionedDeviceCount: Int = 0) {
        self.name = name
        self.teamName = teamName
        self.teamIdentifier = teamIdentifier
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.appGroups = appGroups
        self.getTaskAllow = getTaskAllow
        self.provisionsAllDevices = provisionsAllDevices
        self.provisionedDeviceCount = provisionedDeviceCount
    }

    /// Kalan süre (saniye). Negatifse süre dolmuştur.
    public func remainingSeconds(at now: Date) -> TimeInterval {
        expirationDate.timeIntervalSince(now)
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expirationDate
    }

    /// Ücretsiz Apple ID profilleri 7 gün, ücretli geliştirici profilleri ~1 yıl geçerlidir.
    public var looksLikeFreeAppleID: Bool {
        guard let creationDate = creationDate else { return false }
        return expirationDate.timeIntervalSince(creationDate) <= 8 * 24 * 60 * 60
    }
}

public enum ProvisioningProfileReader {

    /// Paket içindeki profili okur. Simülatör, App Store veya imzasız kurulumda nil döner.
    public static func readEmbedded(in bundle: Bundle = .main) -> ProvisioningProfileInfo? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(profileData: data)
    }

    /// CMS zarfının içindeki XML plist'i bayt aramasıyla çıkarır ve çözer.
    public static func parse(profileData data: Data) -> ProvisioningProfileInfo? {
        guard let plistData = extractPlist(from: data) else { return nil }
        guard let raw = try? PropertyListDecoder().decode(RawProfile.self, from: plistData) else {
            return nil
        }
        return ProvisioningProfileInfo(
            name: raw.name,
            teamName: raw.teamName,
            teamIdentifier: raw.teamIdentifier?.first,
            creationDate: raw.creationDate,
            expirationDate: raw.expirationDate,
            appGroups: raw.entitlements?.appGroups ?? [],
            getTaskAllow: raw.entitlements?.getTaskAllow ?? false,
            provisionsAllDevices: raw.provisionsAllDevices ?? false,
            provisionedDeviceCount: raw.provisionedDevices?.count ?? 0
        )
    }

    /// "<?xml" ile "</plist>" arasını (sonlandırıcı dahil) döndürür.
    public static func extractPlist(from data: Data) -> Data? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker) else { return nil }
        guard let end = data.range(of: endMarker, options: [], in: start.upperBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}

// MARK: - Ham plist modelleri (yalnız ExpirationDate zorunlu; diğerleri hatalı tipte olsa bile yok sayılır)

private struct RawProfile: Decodable {
    var name: String?
    var teamName: String?
    var teamIdentifier: [String]?
    var creationDate: Date?
    var expirationDate: Date
    var provisionsAllDevices: Bool?
    var provisionedDevices: [String]?
    var entitlements: RawEntitlements?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case teamName = "TeamName"
        case teamIdentifier = "TeamIdentifier"
        case creationDate = "CreationDate"
        case expirationDate = "ExpirationDate"
        case provisionsAllDevices = "ProvisionsAllDevices"
        case provisionedDevices = "ProvisionedDevices"
        case entitlements = "Entitlements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expirationDate = try c.decode(Date.self, forKey: .expirationDate)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        teamName = try? c.decodeIfPresent(String.self, forKey: .teamName)
        teamIdentifier = try? c.decodeIfPresent([String].self, forKey: .teamIdentifier)
        creationDate = try? c.decodeIfPresent(Date.self, forKey: .creationDate)
        provisionsAllDevices = try? c.decodeIfPresent(Bool.self, forKey: .provisionsAllDevices)
        provisionedDevices = try? c.decodeIfPresent([String].self, forKey: .provisionedDevices)
        entitlements = try? c.decodeIfPresent(RawEntitlements.self, forKey: .entitlements)
    }
}

private struct RawEntitlements: Decodable {
    var appGroups: [String]?
    var getTaskAllow: Bool?

    enum CodingKeys: String, CodingKey {
        case appGroups = "com.apple.security.application-groups"
        case getTaskAllow = "get-task-allow"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appGroups = try? c.decodeIfPresent([String].self, forKey: .appGroups)
        getTaskAllow = try? c.decodeIfPresent(Bool.self, forKey: .getTaskAllow)
    }
}
```

İmza/derleme notları:
- `func range(of dataToFind: Data, options: Data.SearchOptions = [], in range: Range<Data.Index>? = nil) -> Range<Data.Index>?` ve
  `func subdata(in range: Range<Data.Index>) -> Data` — Foundation `Data`. İndisler `data`'nın kendi indisleridir; dilim gelse bile tutarlı.
- `try? c.decodeIfPresent(…)` Swift 5'te tek katmanlı `Optional`'a düzleşir (SE-0230) → `String?` alanına doğrudan atanır.
- `init(from decoder: Decoder)` Swift 5 modunda `any` gerektirmez.
- `guard let creationDate = creationDate` açık yazıldı (kısaltma `guard let creationDate` da Swift 5.7+ ile geçerli).
- `PropertyListDecoder` XML plist'teki `<date>` değerini doğrudan `Date`'e çözer; DOCTYPE satırı gerçek profillerde vardır ve
  test fixture'ında da bulunur (Linux ayrıştırıcısı reddederse test bunu yakalar → o durumda `<!DOCTYPE … >` bayt aralığı çıkarılır).

### 4.2 App Group çözümleyici — `Packages/AsistCore/Sources/AsistCore/Platform/AppGroupResolver.swift`

```swift
import Foundation

public struct ResolvedAppGroup: Equatable, Sendable {
    public let identifier: String
    public let containerURL: URL

    public init(identifier: String, containerURL: URL) {
        self.identifier = identifier
        self.containerURL = containerURL
    }
}

/// İmzalayıcıların yeniden adlandırdığı App Group kimliklerini de dener
/// (ör. AltStore: "group.com.gokhanbudak.asist.<TEAMID>", Info.plist "ALTAppGroups").
public enum AppGroupResolver {

    public static func candidates(expected: String,
                                  infoPlistGroups: [String],
                                  profileGroups: [String]) -> [String] {
        let base = expected.hasPrefix("group.") ? String(expected.dropFirst(6)) : expected
        let related = (infoPlistGroups + profileGroups).filter { $0.contains(base) }
        var result: [String] = []
        for identifier in [expected] + related where !identifier.isEmpty && !result.contains(identifier) {
            result.append(identifier)
        }
        return result
    }

    /// `containerURL` iOS'ta entitlement yoksa nil döner; ilk nil olmayan aday seçilir.
    public static func resolve(expected: String,
                               infoPlistGroups: [String],
                               profileGroups: [String],
                               containerURL: (String) -> URL?) -> ResolvedAppGroup? {
        for identifier in candidates(expected: expected,
                                     infoPlistGroups: infoPlistGroups,
                                     profileGroups: profileGroups) {
            if let url = containerURL(identifier) {
                return ResolvedAppGroup(identifier: identifier, containerURL: url)
            }
        }
        return nil
    }
}

#if canImport(Darwin)
public enum SharedContainerLocator {
    public static let expectedAppGroup = "group.com.gokhanbudak.asist"

    /// Uygulama ve widget uzantısında aynı şekilde çağrılır (Bundle.main her birinin kendi paketi).
    public static func resolve(bundle: Bundle = .main,
                               fileManager: FileManager = .default) -> ResolvedAppGroup? {
        let infoGroups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let profileGroups = ProvisioningProfileReader.readEmbedded(in: bundle)?.appGroups ?? []
        return AppGroupResolver.resolve(expected: expectedAppGroup,
                                        infoPlistGroups: infoGroups,
                                        profileGroups: profileGroups) { identifier in
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    }
}
#endif
```

- `func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?` — iOS 7+.
  [VERIFIED: Apple doc JSON]
- Kuyruk kapanışı son parametre `containerURL:` ile eşleşir; kapanış kaçmaz (`@escaping` gerekmez).
- `"group."` 6 karakterdir → `dropFirst(6)`.

### 4.3 Uyarı zamanlayıcısı — `Packages/AsistCore/Sources/AsistCore/Platform/SigningExpiryPlanner.swift`

```swift
import Foundation

public enum SigningExpiryPlanner {

    /// Bitişten 48 s, 24 s ve 4 s önce uyarı. 22:00–08:00 arasına düşen uyarı önceki akşam 21:00'e alınır.
    /// Geçmişte kalan veya bitişten sonraya düşen zamanlar atılır; sonuç sıralı ve tekildir.
    public static func warningDates(expiration: Date, now: Date, calendar: Calendar) -> [Date] {
        let offsets: [TimeInterval] = [48 * 3600, 24 * 3600, 4 * 3600]
        var result: [Date] = []
        for offset in offsets {
            let shifted = shiftOutOfNight(expiration.addingTimeInterval(-offset), calendar: calendar)
            guard shifted > now.addingTimeInterval(60), shifted < expiration else { continue }
            if !result.contains(shifted) {
                result.append(shifted)
            }
        }
        return result.sorted()
    }

    public static func shiftOutOfNight(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour >= 22 {
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) ?? date
        }
        if hour < 8 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return date }
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: previousDay) ?? date
        }
        return date
    }

    /// "3 gün", "20 saat", "1 saatten az"
    public static func remainingDescription(from start: Date, to end: Date) -> String {
        let hours = Int(max(0, end.timeIntervalSince(start)) / 3600)
        if hours >= 48 { return "\(hours / 24) gün" }
        if hours >= 1 { return "\(hours) saat" }
        return "1 saatten az"
    }
}
```

`func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date, matchingPolicy: Calendar.MatchingPolicy = .nextTime, repeatedTimePolicy: Calendar.RepeatedTimePolicy = .first, direction: Calendar.SearchDirection = .forward) -> Date?`
ve `func date(byAdding component: Calendar.Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date?` — Foundation `Calendar`.

### 4.4 Uygulama tarafı — `App/Platform/SigningExpiryNotifier.swift`

```swift
import Foundation
import UserNotifications
import AsistCore

enum SigningExpiryNotifier {
    static let identifierPrefix = "asist.sistem.imza."
    private static let lastProfileStampKey = "asist.imza.sonProfilDamgasi"

    /// Uygulama her ön plana geldiğinde çağrılır; idempotenttir.
    /// Dönüş `true` ise profil değişmiştir (yeniden imzalandı / ilk açılış):
    /// çağıran taraf TÜM hatırlatıcı bildirimlerini baştan kurmalıdır.
    @discardableResult
    static func refresh(now: Date = Date()) async -> Bool {
        guard let info = ProvisioningProfileReader.readEmbedded() else { return false }

        let defaults = UserDefaults.standard
        let stamp = (info.creationDate ?? info.expirationDate).timeIntervalSince1970
        let resigned = defaults.double(forKey: lastProfileStampKey) != stamp
        defaults.set(stamp, forKey: lastProfileStampKey)

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map { $0.identifier }.filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let dates = SigningExpiryPlanner.warningDates(expiration: info.expirationDate,
                                                      now: now,
                                                      calendar: Calendar.current)
        for (index, fireDate) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Asist'in imza süresi doluyor"
            content.body = "Kalan süre: \(SigningExpiryPlanner.remainingDescription(from: fireDate, to: info.expirationDate)). "
                + "Bilgisayarda Sideloadly ile aynı Apple ID'yi kullanarak Asist'i yeniden yükleyin; verileriniz korunur."
            content.sound = .default
            let interval = max(1, fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + String(index),
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
        return resigned
    }
}
```

Bağlama (kök görünümde; `onChange(of:initial:_:)` iOS 17 API'si, eski tek parametreli sürüm iOS 17'de
kullanımdan kalktı → uyarı üretmemek için iki parametreli kapanış):

```swift
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainTabView()                                   // asıl arayüz (UI dokümanı)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                Task {
                    let resigned = await SigningExpiryNotifier.refresh()
                    if resigned {
                        // Bildirim dokümanındaki planlayıcı: tüm bekleyen hatırlatıcıları depodan yeniden kurar.
                        await ReminderNotificationScheduler.shared.rebuildAll()
                    }
                }
            }
    }
}
```

Ayarlar > Sistem Durumu satırı:

```swift
import SwiftUI
import AsistCore

struct SigningStatusSection: View {
    private let info = ProvisioningProfileReader.readEmbedded()
    private let sharedGroup = SharedContainerLocator.resolve()   // iOS'ta her zaman derlenir (Darwin)

    var body: some View {
        Section("Sistem Durumu") {
            if let info = info {
                LabeledContent("İmza bitişi") {
                    Text(info.expirationDate, style: .relative)
                        .foregroundStyle(info.remainingSeconds(at: Date()) < 48 * 3600 ? Color.red : Color.secondary)
                }
                LabeledContent("İmza türü", value: info.looksLikeFreeAppleID ? "Ücretsiz Apple ID (7 gün)" : "Geliştirici")
            } else {
                LabeledContent("İmza bitişi", value: "Bilinmiyor")
            }
            LabeledContent("Paylaşılan alan (widget)", value: sharedGroup == nil ? "Yok" : "Etkin")
        }
    }
}
```

Tuzaklar:
- `.foregroundStyle(cond ? .red : .secondary)` **derlenmez** (`Color` ve `HierarchicalShapeStyle` farklı tip) → iki taraf `Color.` ile yazıldı.
- `UNUserNotificationCenter.add(_:) async throws` ve `pendingNotificationRequests() async -> [UNNotificationRequest]` iOS 15+.
- `UNTimeIntervalNotificationTrigger` `timeInterval > 0` ister; `max(1, …)` korur.
- `SharedContainerLocator` AsistCore'da `#if canImport(Darwin)` içindedir; iOS hedeflerinde her zaman görünür, Linux test derlemesinde yoktur (orada kullanılmaz).
- `LabeledContent` iOS 16+, `onChange(of:initial:_:)` iOS 17+ — deployment target 17.0 ile `#available` gerekmez.
- `ReminderNotificationScheduler.shared.rebuildAll()` bildirim dokümanında tanımlanır; ad orada farklıysa burası uyarlanır.

### 4.5 Linux'ta çalışan birim testleri — `Packages/AsistCore/Tests/AsistCoreTests/PlatformTests.swift`

```swift
import XCTest
@testable import AsistCore

final class PlatformTests: XCTestCase {

    private let iso = ISO8601DateFormatter()

    func testParsesProfileWrappedInBinaryEnvelope() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>iOS Team Provisioning Profile: com.gokhanbudak.asist</string>
            <key>TeamName</key><string>Gökhan Budak</string>
            <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
            <key>CreationDate</key><date>2026-09-27T10:00:00Z</date>
            <key>ExpirationDate</key><date>2026-10-04T10:00:00Z</date>
            <key>ProvisionedDevices</key><array><string>00008120-000000000000001E</string></array>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key><string>ABCDE12345.com.gokhanbudak.asist</string>
                <key>com.apple.security.application-groups</key>
                <array><string>group.com.gokhanbudak.asist.ABCDE12345</string></array>
                <key>get-task-allow</key><true/>
            </dict>
        </dict>
        </plist>
        """
        var blob = Data([0x30, 0x82, 0x3F, 0x12, 0x06, 0x09, 0x2A, 0x86, 0x48, 0xFF, 0xFE])  // sahte CMS başı
        blob.append(Data(xml.utf8))
        blob.append(Data([0xA0, 0x82, 0x0D, 0x00, 0xFF, 0x00]))                             // sahte imza kuyruğu

        let info = try XCTUnwrap(ProvisioningProfileReader.parse(profileData: blob))
        XCTAssertEqual(info.expirationDate, iso.date(from: "2026-10-04T10:00:00Z"))
        XCTAssertEqual(info.creationDate, iso.date(from: "2026-09-27T10:00:00Z"))
        XCTAssertEqual(info.teamIdentifier, "ABCDE12345")
        XCTAssertEqual(info.teamName, "Gökhan Budak")
        XCTAssertEqual(info.appGroups, ["group.com.gokhanbudak.asist.ABCDE12345"])
        XCTAssertTrue(info.getTaskAllow)
        XCTAssertEqual(info.provisionedDeviceCount, 1)
        XCTAssertTrue(info.looksLikeFreeAppleID)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ProvisioningProfileReader.parse(profileData: Data([0x00, 0x01, 0x02])))
        XCTAssertNil(ProvisioningProfileReader.parse(profileData: Data("<?xml version=\"1.0\"?><plist>".utf8)))
    }

    func testIstanbulTimeZoneAvailable() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let date = try XCTUnwrap(iso.date(from: "2026-09-27T09:00:00Z"))
        XCTAssertEqual(tz.secondsFromGMT(for: date), 3 * 3600)
    }

    func testWarningsAvoidNightAndPast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let expiration = try XCTUnwrap(iso.date(from: "2026-10-04T07:00:00Z"))   // 10:00 İstanbul
        let now = try XCTUnwrap(iso.date(from: "2026-09-27T07:00:00Z"))
        let dates = SigningExpiryPlanner.warningDates(expiration: expiration, now: now, calendar: calendar)
        // 48 s: 02.10 10:00 | 24 s: 03.10 10:00 | 4 s: 04.10 06:00 -> gece -> 03.10 21:00 (18:00Z)
        let expected = ["2026-10-02T07:00:00Z", "2026-10-03T07:00:00Z", "2026-10-03T18:00:00Z"]
            .compactMap { iso.date(from: $0) }
        XCTAssertEqual(dates, expected)
    }

    func testResolverTriesExpectedThenRenamedGroups() {
        let candidates = AppGroupResolver.candidates(
            expected: "group.com.gokhanbudak.asist",
            infoPlistGroups: ["group.com.gokhanbudak.asist.ABCDE12345"],
            profileGroups: ["group.com.gokhanbudak.asist.ABCDE12345", "group.baska.uygulama"])
        XCTAssertEqual(candidates, ["group.com.gokhanbudak.asist", "group.com.gokhanbudak.asist.ABCDE12345"])

        let resolved = AppGroupResolver.resolve(
            expected: "group.com.gokhanbudak.asist",
            infoPlistGroups: [],
            profileGroups: ["group.com.gokhanbudak.asist.ABCDE12345"]) { identifier in
                identifier.hasSuffix("ABCDE12345") ? URL(fileURLWithPath: "/tmp/grup") : nil
            }
        XCTAssertEqual(resolved?.identifier, "group.com.gokhanbudak.asist.ABCDE12345")

        let none = AppGroupResolver.resolve(expected: "group.com.gokhanbudak.asist",
                                            infoPlistGroups: [], profileGroups: []) { _ in nil }
        XCTAssertNil(none)
    }
}
```

### 4.6 Bu bölümün tuzakları

1. `Bundle.main.path(forResource:ofType:)` yerine `url(forResource:withExtension:)` — ikisi de çalışır; URL tercih.
2. Profilde `ExpirationDate` **profilin** bitişidir; sertifika bitişi ayrıdır (`DeveloperCertificates`) — ücretsiz hesapta bağlayıcı olan profildir (7 gün).
3. Ad-hoc imzalı CI çıktısında profil yoktur; yalnız Sideloadly/AltStore imzasından sonra oluşur.
4. `UserDefaults.double(forKey:)` anahtar yoksa `0` döner → ilk açılışta `resigned = true` (bilinçli: ilk açılışta bildirimler kurulur).
5. Profil okuma ana iş parçacığında birkaç KB dosya okumasıdır; `static let` ile önbelleğe alınabilir ama yeniden imza **uygulama yeniden başlatılmadan** olmaz, bu yüzden her ön plana gelişte okumak da güvenlidir.

---

## 5. Önerilen asgari CI + paketleme tasarımı ve dosya listesi

Akış: `git push main` → (paralel) **Linux**: AsistCore `swift build --build-tests` + `swift test` |
**macOS 26**: Xcode 26.x seç → XcodeGen 2.46.0 (SHA doğrulamalı) → `xcodegen generate` → `xcodebuild build`
(iphoneos, imzasız, Release, `CFBundleVersion = run_number`) → ön doğrulama (widget gömülü, kimlik öneki,
sürüm eşliği, arm64, Assets.car) → `Asist-imzasiz.ipa` + ad-hoc entitlement'lı `Asist.ipa` →
zip'siz artifact → kullanıcı Windows'ta indirir → Sideloadly.

| Dosya | Sahibi | Git'te? | İçerik kaynağı |
|---|---|---|---|
| `project.yml` | bu doküman | ✓ | §1.2 |
| `.gitignore` | bu doküman | ✓ | aşağıda |
| `.gitattributes` | bu doküman | ✓ | aşağıda — **Windows'ta zorunlu** (CRLF'li `.sh` runner'da `$'\r': command not found` verir) |
| `.github/workflows/ci.yml` | bu doküman | ✓ | §2.6 |
| `Scripts/ci/select-xcode.sh` | bu doküman | ✓ | §2.2 |
| `Scripts/ci/install-xcodegen.sh` | bu doküman | ✓ | §2.3 |
| `Scripts/ci/package-ipa.sh` | bu doküman | ✓ | §2.5 |
| `Scripts/ci/error-summary.sh` | bu doküman | ✓ | §2.7 |
| `Tools/make_app_icon.py` | bu doküman | ✓ | §1.7 |
| `App/Resources/Assets.xcassets/Contents.json` | bu doküman | ✓ | §1.7 |
| `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | bu doküman | ✓ | §1.7 |
| `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | `make_app_icon.py` çıktısı | ✓ | §1.7 |
| `App/AsistApp.swift` (+ diğer UI dosyaları) | UI / mimari dokümanları | ✓ | — (iskelet aşağıda) |
| `App/Platform/SigningExpiryNotifier.swift` | bu doküman | ✓ | §4.4 |
| `App/Settings/SigningStatusSection.swift` | bu doküman | ✓ | §4.4 |
| `Widgets/AsistWidgetsBundle.swift` (+ widget'lar, Live Activity UI, Control widget) | widget dokümanı | ✓ | — (iskelet aşağıda) |
| `Shared/…` (App Intents, `ActivityAttributes`) | intent/widget dokümanları | ✓ (isteğe bağlı) | — |
| `Packages/AsistCore/Package.swift` | bu doküman | ✓ | §1.8 |
| `Packages/AsistCore/Sources/AsistCore/Platform/ProvisioningProfile.swift` | bu doküman | ✓ | §4.1 |
| `Packages/AsistCore/Sources/AsistCore/Platform/AppGroupResolver.swift` | bu doküman | ✓ | §4.2 |
| `Packages/AsistCore/Sources/AsistCore/Platform/SigningExpiryPlanner.swift` | bu doküman | ✓ | §4.3 |
| `Packages/AsistCore/Sources/AsistCore/…` (ayrıştırıcı, modeller) | ayrıştırıcı dokümanı | ✓ | — |
| `Packages/AsistCore/Tests/AsistCoreTests/PlatformTests.swift` | bu doküman | ✓ | §4.5 |
| `docs/KURULUM.md` | bu doküman | ✓ | §3.3–3.4 |
| `Asist.xcodeproj/`, `Generated/*.plist`, `Generated/*.entitlements` | XcodeGen | ✗ | CI üretir |

`.gitignore`
```gitignore
# XcodeGen / Xcode üretimleri
Asist.xcodeproj/
Generated/
DerivedData/
build/
xcuserdata/
*.xcworkspace/xcuserdata/
# SwiftPM
Packages/AsistCore/.build/
Packages/AsistCore/.swiftpm/
# Çıktılar
*.ipa
*.xcarchive/
# İşletim sistemi
.DS_Store
Thumbs.db
```

`.gitattributes`
```gitattributes
* text=auto
*.sh     text eol=lf
*.yml    text eol=lf
*.yaml   text eol=lf
*.swift  text eol=lf
*.py     text eol=lf
*.json   text eol=lf
*.plist  text eol=lf
*.png    binary
*.ipa    binary
```
Betikler iş akışında `bash Scripts/ci/….sh` biçiminde çağrılır → Windows'ta `chmod +x` (çalıştırma biti)
ayarlamaya gerek yoktur.

**İlk CI "duman testi" için asgari iskelet** (UI/widget dokümanları gelmeden projenin derlendiğini görmek için;
iOS 17 SDK, Swift 5):

`App/AsistApp.swift`
```swift
import SwiftUI

@main
struct AsistApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Asist")
                .onOpenURL { url in
                    print("Derin bağlantı: \(url.absoluteString)")
                }
        }
    }
}
```

`Widgets/AsistWidgetsBundle.swift`
```swift
import SwiftUI
import WidgetKit

@main
struct AsistWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AsistQuickWidget()
    }
}

struct AsistQuickEntry: TimelineEntry {
    let date: Date
}

struct AsistQuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> AsistQuickEntry {
        AsistQuickEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (AsistQuickEntry) -> Void) {
        completion(AsistQuickEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AsistQuickEntry>) -> Void) {
        completion(Timeline(entries: [AsistQuickEntry(date: Date())], policy: .never))
    }
}

struct AsistQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AsistHizliKayit", provider: AsistQuickProvider()) { _ in
            VStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.title)
                Text("Dinle")
                    .font(.headline)
            }
            .widgetURL(URL(string: "asist://dinle"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Asist — Hızlı Kayıt")
        .description("Dokun, konuş; Asist hatırlatsın.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
```
(`containerBackground(_:for:)` iOS 17'de zorunludur; yoksa widget "arka plan API'sini benimseyin" yer tutucusu gösterir.)

`Packages/AsistCore/Sources/AsistCore/AsistCore.swift` (paket boş kalmasın)
```swift
import Foundation

public enum AsistCoreInfo {
    public static let version = "1.0.0"
}
```

---

## 6. Riskler ve açık sorular

**Riskler**
1. **Sideloadly + ücretsiz hesapta App Group büyük olasılıkla yok** → widget'ta uygulama verisi gösterilemez;
   tasarım Live Activity + başlatıcı widget'a dayanır (§3.2). Doğrulama: ilk kurulumda Sistem Durumu satırı.
2. **Ad-hoc entitlement'lı `Asist.ipa` Sideloadly'de reddedilebilir** (entitlement'ı taşıyıp profilde karşılamazsa) → `Asist-imzasiz.ipa` yedeği.
3. **Süresi dolmuş imzada bekleyen yerel bildirimlerin davranışı bilinmiyor**; ısrarlı hatırlatıcı zinciri 7 günlük pencereye güvenmemeli.
4. **Yeniden imza/güncelleme sonrası bekleyen bildirimler uygulama açılana kadar gelmeyebilir** (Apple forum raporu) → Sideloadly otomatik yenilemesi uygulamayı açmadığı için yenilemeden sonraki ilk açılışa kadar hatırlatıcı kaçabilir. Azaltma: ön plana her gelişte + `BGAppRefreshTask`'ta uzlaştırma; yenileme bildirim metninde "yeniledikten sonra Asist'i bir kez açın".
5. **Siri sesli çağrısı Siri entitlement'ı olmadan çalışmayabilir** (çelişkili kaynaklar) → birincil tetikleyiciler Siri'ye bağlı değil.
6. **Bundle ID mangling**: Sideloadly kimliği değiştirirse ve bir sonraki yenilemede farklı değiştirirse (ör. Apple ID ya da seçenek değişimi) veri "kaybolmuş" görünür (eski kimliğin konteynerinde kalır). Kural: hep aynı Apple ID, seçeneklere dokunma.
7. **Dakika kotası**: Free planda ~20–30 IPA/ay; sık iterasyonda kota biter.
8. **Runner görüntüsü değişimi**: Xcode 26.x yamaları kaldırılır/eklenir; dinamik seçim bunu karşılar, ama Xcode 27'ye geçiş (yeni SDK uyarıları, Swift 6.4) ayrı bir karar olmalı (`XCODE_MAJOR`).
9. Ubuntu `swift:6.3-noble` ile Xcode'un Swift'i arasında yama farkı → nadiren birinde derlenip diğerinde derlenmeyen kod; CI iki tarafı da derlediği için yakalanır.
10. `codesign`, `ditto`, `PlistBuddy` adımları yerelde test edilemedi (Windows); ilk CI koşusunda doğrulanacak.

**Açık sorular**
1. Sideloadly, imzadaki `com.apple.security.application-groups`'u ücretsiz hesapta kaydediyor mu, yeniden adlandırıyor mu? (İlk kurulum testi)
2. Sideloadly bu cihazda (iOS 26) bundle ID'yi değiştiriyor mu? Değiştiriyorsa her yenilemede aynı sonucu veriyor mu?
3. Süresi dolmuş profilde `UNCalendarNotificationTrigger`/`UNTimeIntervalNotificationTrigger` bildirimleri teslim ediliyor mu?
4. App Shortcut'lar ücretsiz imzada (Siri entitlement'sız) Türkçe Siri ile sesle çalışıyor mu?
5. Kullanıcı GitHub Free mi Pro mu? Depo public yapılabilir mi (sınırsız ücretsiz macOS dakikası)?
6. `audio` arka plan modu ürün kararı (ses tuşu algılamayı arka planda sürdürme) — 01a/01b.
7. Otomatik yenileme için bilgisayar sürekli açık kalabilecek mi, yoksa haftalık elle yenileme mi?

---

## 7. Kaynaklar

- XcodeGen ProjectSpec: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- XcodeGen kaynak: https://github.com/yonaskolb/XcodeGen/blob/master/Sources/XcodeGenKit/InfoPlistGenerator.swift · .../PBXProjGenerator.swift · .../SettingsBuilder.swift · .../FileWriter.swift · https://github.com/yonaskolb/XcodeGen/tree/master/SettingPresets · https://github.com/yonaskolb/XcodeGen/blob/master/Sources/ProjectSpec/Settings.swift
- XcodeGen 2.46.0: https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0 · CHANGELOG: https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md
- Runner görüntüleri: https://github.com/actions/runner-images · https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md · https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md · https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md · https://github.com/actions/runner-images/issues/14404 · https://github.com/actions/runner-images/issues/14167 · https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/
- GitHub faturalama: https://docs.github.com/en/billing/reference/actions-runner-pricing · https://docs.github.com/en/billing/concepts/product-billing/github-actions
- İş akışı sözdizimi: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- upload-artifact: https://github.com/actions/upload-artifact/blob/main/action.yml
- xcbeautify: https://github.com/cpisciotta/xcbeautify
- Swift Docker: https://github.com/swiftlang/swift-docker/blob/main/6.2/ubuntu/24.04/Dockerfile · https://hub.docker.com/_/swift
- swift-foundation: https://github.com/swiftlang/swift-foundation
- SE-0354 Regex literalleri: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0354-regex-literals.md
- Apple yetenek tablosu: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Apple `containerURL`: https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
- TN3125 Provisioning Profiles: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
- Developer Mode: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
- BGTaskScheduler: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:) · https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app
- Info.plist anahtarları: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription · .../nsspeechrecognitionusagedescription · .../nscalendarsfullaccessusagedescription · .../nsremindersfullaccessusagedescription · .../uilaunchscreen · .../nssupportsliveactivities · .../uidesignrequirescompatibility · .../bgtaskschedulerpermittedidentifiers
- Siri entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri
- Time Sensitive seviye: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive
- Güncelleme sonrası yerel bildirimler: https://developer.apple.com/forums/thread/772031
- Sideloadly: https://sideloadly.io/ · https://sideloadly.io/faq · https://sideloadly.io/changelog
- AltStore SSS: https://faq.altstore.io/altstore-classic/app-ids · https://faq.altstore.io/altstore-classic/activating-apps
- AltStore kaynak: https://github.com/altstoreio/AltStore/blob/master/AltStore/Operations/FetchProvisioningProfilesOperation.swift · https://github.com/altstoreio/AltStore/blob/master/AltStore/Operations/ResignAppOperation.swift
- Örnek imzasız IPA iş akışı (XcodeGen + widget): https://github.com/JosephLteif/pocket-ledger/blob/main/.github/workflows/ios-build.yml
- Tek boyut ikon: https://useyourloaf.com/blog/xcode-14-single-size-app-icon/
- Siri entitlement anekdotu: https://github.com/Redth/Maui.Apple.PlatformFeature.Samples/issues/1
- Türkçe Geliştirici Modu yolu: https://teknofix.com.tr/iphone-gelistirici-modu-acma
- Sideloadly bundle ID mangling günlüğü: https://gist.github.com/robonxt/fe91254c8070cfe84c6add1dcc0ead88
