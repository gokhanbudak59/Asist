# Asist — Kurulum ve Haftalık Yenileme

Bu rehber Asist'i **Windows bilgisayar + Sideloadly + ücretsiz Apple ID** ile iPhone'a kurmayı, her hafta
yenilemeyi ve ilk açılışta yapılacak ayarları anlatır. Mac gerekmez.

> **En önemli üç kural**
> 1. **Asist'i telefondan asla silme.** Silersen bütün kayıtların ve yedek klasörü de silinir.
>    Yenileme ve güncelleme her zaman **üstüne yükleme** ile yapılır.
> 2. **Her zaman aynı Apple ID** ile yükle. Farklı Apple ID = farklı uygulama; kayıtların görünmez.
> 3. **Her pazartesi 08:30'da iş bilgisayarında yenile** (ücretsiz imza 7 gün geçerli). Yeniledikten sonra
>    **Asist'i bir kez aç.**

---

## 1. Gerekenler

| Ne | Not |
|---|---|
| Windows 10/11 bilgisayar | İş bilgisayarı olabilir; haftada bir 5 dakika lazım. |
| iPhone | iOS 17 veya üstü. Kilit ekranı / Denetim Merkezi düğmeleri ve widget'lar için **iOS 18** (senin telefonun iPhone 14 Pro Max, iOS 18.7: destekler). |
| USB kablo | İlk kurulumda şart; sonrası aynı Wi-Fi ile de olur. |
| Apple ID | Ücretsiz hesap yeterli. Şifreni ve iki adımlı doğrulama kodunu **sadece sen** Sideloadly'ye girersin. |
| Asist.ipa | GitHub'daki derlemeden indirilir (bölüm 3). |

Ücretsiz Apple ID sınırları (bilmen yeterli):

- İmza **7 gün** geçerli. Süre dolarsa Asist açılmaz ama **verilerin telefonda kalır**; yenileyince geri gelir.
- Aynı anda en fazla **3** yan yüklenmiş uygulama.
- 7 günde en fazla **10 App ID**. Sürüm 1.1'den itibaren Asist her kurulumda **2** App ID kullanır (uygulama +
  widget uzantısı). Haftalık yenileme aynı kimlikleri kullanır, yeni App ID harcamaz.
  Paket kimliğini değiştirerek deneme yapma — her deneme yeni App ID harcar.
- Zamana duyarlı bildirim yetkisi ücretsiz hesapta olmayabilir; Asist buna bağlı değildir.

---

## 2. Bilgisayarı bir kez hazırla

> **USB girişi olan bilgisayarı kullan.** İlk kurulum kabloyla yapılır. Hangi bilgisayarda kurduysan haftalık
> yenilemeyi de **hep o bilgisayarda ve aynı Apple ID ile** yap (ücretsiz imzayı başka bilgisayara taşımak
> telefondaki imzayı geçersiz kılabilir). Bilgisayarında yalnız USB-C varsa **Lightning–USB-C** kablo da olur.

1. Microsoft Store'dan kurulmuş **iTunes** veya **iCloud** varsa kaldır (Ayarlar › Uygulamalar). Microsoft Store ›
   **Kitaplık**'ta görünüyorlarsa Store sürümüdür.
2. Store **dışı** sürümleri kur:
   - iTunes 64-bit: https://www.apple.com/itunes/download/win64
   - iCloud (web): https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe
3. **Sideloadly 64-bit**'i kur: https://sideloadly.io/SideloadlySetup64.exe
   **Sideloadly ile iTunes aynı bit sürümü olmalı** (64-bit iTunes → 64-bit Sideloadly). 32-bit Sideloadly,
   64-bit iTunes ile "Initializing…" yazıp kapanır.
4. Bilgisayarı **yeniden başlat**. Sideloadly yine açılmazsa: sağ tık › **Yönetici olarak çalıştır**; Windows Güvenliği ›
   Koruma geçmişi'nde engellenmişse izin ver.
5. iPhone'u USB kabloyla bağla. iPhone'da **"Bu Bilgisayara Güvenilsin mi?" → Güven** de ve parolanı gir.
6. (Önerilir) iTunes'ta iPhone simgesi → **Özet** → **"Bu iPhone ile Wi-Fi üzerinden eşzamanla"** kutusunu
   işaretle → **Uygula**. Böylece sonraki yenilemeler kablosuz yapılabilir. (IPA'yı iTunes'a **sürükleme**;
   IPA yalnız Sideloadly'ye verilir.)
7. Bilgisayarda sabit bir klasör aç: **`C:\Asist\`**. İndirdiğin IPA'yı hep buraya koyacaksın.

---

## 3. IPA'yı indir

En kolayı — giriş gerekmez, her zaman en son **testleri geçmiş** sürüm:

**https://github.com/gokhanbudak59/Asist/releases/download/son-surum/Asist.ipa**

Dosyayı **`C:\Asist\Asist.ipa`** olarak kaydet (eskisinin üstüne yaz).

Aynı sayfada (https://github.com/gokhanbudak59/Asist/releases/tag/son-surum) bir de **Asist-imzasiz.ipa** vardır.
Sadece bölüm 8'deki bir kurulum hatası çıkarsa kullan.

---

## 4. Sideloadly ile yükle

1. Sideloadly'yi aç; üstte iPhone'unun seçili olduğunu gör.
2. Sideloadly penceresinin sol üstündeki **IPA** simgesine tıkla ve `C:\Asist\Asist.ipa` dosyasını seç
   (ya da dosyayı Sideloadly penceresine sürükle — iTunes'a değil).
3. **Apple account** kutusuna Apple ID e-postanı yaz. **Her seferinde aynı Apple ID.**
4. **Advanced Options**:
   - **Signing Mode: Apple ID Sideload** (varsayılan).
   - **Bundle ID** ve **App name** değiştirme seçenekleri **kapalı** kalsın.
   - **"Remove app extensions" işaretli OLMASIN** — widget'lar ve kilit ekranı düğmesi uzantıdadır.
     (Yalnız bölüm 8'deki bir hata çıkarsa yedek çözüm olarak işaretlenir.)
5. **Start**'a bas → Apple ID şifreni ve iki adımlı doğrulama kodunu gir → **"Done"** yazısını bekle.
6. **Paket kimliğini kontrol et:** Sideloadly'nin günlük (log) penceresinde paket kimliği (bundle id)
   **`com.gokhanbudak.asist`** olmalı. Başka bir kimlik görürsen (ör. sonuna ek almışsa) **yüklemeyi kullanma**:
   farklı kimlik = ayrı, boş bir Asist demektir; kayıtların eskisinde kalır. Bu durumda Advanced Options'taki
   Bundle ID ayarını düzeltip tekrar yükle.

---

## 5. iPhone'da bir kerelik ayarlar

1. **Geliştirici Modu:** Ayarlar › Gizlilik ve Güvenlik › **Geliştirici Modu** → Aç → **Yeniden Başlat**.
   Açılışta çıkan uyarıda **Aç**'a dokun ve parolanı gir.
   (Anahtar görünmüyorsa önce bölüm 4'ü bitir; telefon bilgisayarla eşleşince görünür.)
2. **Geliştiriciye güven:** Ayarlar › Genel › **VPN ve Aygıt Yönetimi** → Apple ID e-postan →
   **"… Güven"** → **Güven**.
3. **Asist**'i aç. Tanıtım 3 sayfadır:
   - **Bildirimlere İzin Ver** de (Asist'in var olma sebebi bu).
   - **Mikrofon ve konuşma tanımaya İzin Ver** de. **Deneme hatırlatmasını kur**'a dokun: 1 dakika sonra bildirim gelir.
   - Hızlı erişim sayfasında **Test bildirimi (30 sn)**'yi dene.
4. Asist › Ayarlar › **İmza ve izinler**: "İmza bitişi" satırında tarih görünmeli (ör. "2 Ekim 14:32 · 6 gün kaldı").
5. **Konum** ve **Takvim** izinlerini Asist tanıtımda sormaz; ilk kullandığında sorar:
   - Konum: Ayarlar › **Konumlar** › bir yer › **Şu anki konumu kaydet** → **Uygulamayı Kullanırken İzin Ver**.
     **Kesin Konum** açık kalsın (kapalıysa yer hatırlatmaları çalmaz).
   - Takvim: Bugün ekranındaki **"Toplantıların Bugün'de görünsün"** kartı veya Ayarlar › **Takvim** →
     **Tam Erişime İzin Ver**. Asist takvimini yalnız okur, hiçbir şey yazmaz.

---

## 6. İlk gün kontrol listesi

Aşağıdakilerin hepsi bir kez yapılır; toplam ~10 dakika. Her birinin adım adım anlatımı uygulamada da var:
**Asist › Ayarlar › Tetikleyiciler**.

- [ ] **Bildirimler ekranda kalsın:** Ayarlar › Bildirimler › Asist › **Banner Stili** (bazı sürümlerde
      **Afiş Stili**) → **Kalıcı**. Hatırlatma, sen dokunana kadar ekranın üstünde kalır. Alarm olmadan
      unutmamanın en güçlü yolu budur.
- [ ] Aynı ekranda: **Kilitli Ekran, Bildirim Merkezi, Afişler** işaretli; **Sesler** ve **Rozetler** açık;
      **Önizlemeleri Göster: Her Zaman**.
- [ ] **Zamanlanmış Özet** kullanıyorsan Asist özete dahil olmasın (Ayarlar › Bildirimler › Zamanlanmış Özet).
- [ ] **Odak:** Ayarlar › Odak › **İş** (ve kullanıyorsan **Uyku**, **Rahatsız Etme**) › İzin Verilen Bildirimler ›
      Uygulamalar › **Asist**'i ekle. Sonra Odak açıkken Asist › Ayarlar › Tetikleyiciler › Odak rehberindeki
      **Test bildirimi (30 sn)** ile dene.
- [ ] **Kullanılmayan Uygulamaları Kaldır kapalı:** Ayarlar › App Store › **Kullanılmayan Uygulamaları Kaldır** → kapalı.
      (Yan yüklenen Asist kaldırılırsa App Store'dan geri gelmez.)
- [ ] **Arkaya Dokunma → "Asist Hızlı Kayıt"** (uygulama açılmadan sesli kayıt; önerilen):
  1. **Kestirmeler** uygulamasını aç → sağ üstte **+** → **Eylem Ekle**.
  2. Aramaya **Dikte** yaz → **Metni Dikte Et** eylemini ekle. Ayrıntılarından **Dil: Türkçe**,
     **Dinlemeyi Durdur: Duraklamadan Sonra** seç.
  3. Aramaya **Asist** yaz → **Asist'e Kaydet** eylemini ekle; **Metin** alanına dokunup **Dikte Edilen Metin**'i seç.
  4. Kestirmenin adını **Asist Hızlı Kayıt** yap → **Bitti**.
  5. Ayarlar › Erişilebilirlik › Dokunma › **Arkaya Dokunma** › **Çift Dokunma** → **Kestirmeler** bölümünden
     **Asist Hızlı Kayıt**.
  6. Dene: telefonun arkasına iki kez vur, "yarın 9'da tedarikçiyi aramayı hatırlat" de, sus.
     İlk seferde Kestirmeler izin sorarsa **Her Zaman İzin Ver**.
- [ ] (İsteğe bağlı) **Arkaya Dokunma → "Asist Dinle"** (Asist açılıp dinler): Kestirmeler'de tek eylemli
      **Asist Dinle** kestirmesi yap, Arkaya Dokunma › **Üç Dokunma**'ya ata.
- [ ] **Siri:** Ayarlar › Siri › dil **Türkçe**. "Hey Siri, **Asist'e kaydet**" de; Siri "Ne kaydedeyim?" diye
      sorar. Kilitliyken de çalışır.
- [ ] Asist › Ayarlar › **Zamanlar**: mesai (varsayılan 08:30–18:00, Pzt–Cum) ve sessiz saatler (22:30–07:30) sana uyuyor mu?
- [ ] **Kilit ekranına "Asist Dinle" düğmesi** (iOS 18, önerilen): bölüm 10. Uygulama kapalıyken en hızlı yol budur.

> Menü adları iOS sürümüne göre küçük farklılık gösterebilir.

---

## 7. Haftalık yenileme ritüeli (her pazartesi 08:30)

Ücretsiz imza 7 gün geçerlidir. Asist bitişten **48, 24 ve 4 saat önce** bildirim gönderir ve Bugün ekranında
kırmızı/sarı bant gösterir; ama bunu beklemeden **her pazartesi sabahı** yenile:

1. İş bilgisayarında **Sideloadly**'yi aç. iPhone USB ile bağlı ya da aynı Wi-Fi'da olsun.
2. **`C:\Asist\Asist.ipa`**'yı (veya GitHub'daki daha yeni IPA'yı) sürükle.
3. **Aynı Apple ID** → **Start** → şifre / doğrulama kodu → **Done**.
4. Günlükte paket kimliğinin **`com.gokhanbudak.asist`** olduğunu kontrol et.
5. **Asist'i bir kez aç.** Asist yeni imzayı algılar ve bütün hatırlatmaları baştan kurar.
   (iOS, güncelleme sonrası bekleyen bildirimleri uygulama açılana kadar geciktirebiliyor; bir kez açmak bunu çözer.)
6. Ayarlar › İmza ve izinler: yeni bitiş tarihi ~7 gün sonrası olmalı.

**Otomatik yenileme (önerilir):** Sideloadly'de otomatik yenileme (Sideloadly Daemon) açılabilir. Bilgisayar
açık ve iPhone aynı Wi-Fi'da olduğu sürece imzayı kendisi tazeler. Yine de pazartesi kontrolünü alışkanlık yap
ve otomatik yenilemeden sonra da **Asist'i bir kez aç**.

**Yeni sürüm kurmak** yenilemeyle aynı işlemdir: yeni IPA'yı aynı Apple ID ile üstüne yükle. Veriler korunur.

**Güncellemeler telefona kendiliğinden gelir mi?** Hayır. Yan yüklenen uygulamalar kendiliğinden güncellenmez;
Sideloadly'nin otomatik yenilemesi de yalnız imzayı tazeler, yeni sürümü indirmez. Yeni sürüm çıkınca Asist bunu
kendisi söyler: Bugün ekranında mavi **"Yeni sürüm hazır (#N)"** bandı ve Ayarlar › **Güncelleme**. Kurmak için:
yeni Asist.ipa'yı indir → Sideloadly → aynı Apple ID → Start → Asist'i bir kez aç. Asist'i silme; kayıtların korunur.

### İmza süresi dolarsa

- Asist açılmaz; **kayıtların silinmez**. Bölüm 7'deki gibi yenile, sonra Asist'i aç.
- Süre dolmuşken önceden kurulmuş hatırlatmaların çalacağı garanti değildir; "✓ Yaptım" gibi düğmeler çalışmaz.
  Bu yüzden yenilemeyi kaçırma.

---

## 8. Sorun giderme

| Belirti | Çözüm |
|---|---|
| Kurulumda "App Group", "entitlement", "0xe8008016", "invalid entitlements" hatası | Aynı çalıştırmadaki **Asist-imzasiz.ipa** ile yükle. Widget'lar içerik göstermez ama Denetim Merkezi / kilit ekranı düğmeleri ve uygulamanın tamamı çalışır. |
| Sideloadly widget uzantısında (AsistWidgets, "appex", "extension") hata veriyor | Advanced Options › **Remove app extensions** işaretle ve tekrar yükle. Widget'lar ve kilit ekranı düğmesi olmaz; uygulamanın geri kalanı aynen çalışır. |
| "Maximum App ID limit" (sürüm 1.1'den itibaren her kurulum **2 App ID** kullanır) | 7 gün bekle; acilse Sideloadly › Advanced Options › **Remove app extensions** ile yükle (widget ve düğmeler olmaz, gerisi aynı). Paket kimliğini değiştirerek deneme yapma. |
| "maximum number of apps" | Telefondaki başka bir yan yüklenmiş uygulamayı sil (en fazla 3). **Asist'i silme.** |
| Sideloadly iPhone'u görmüyor | iTunes/iCloud Store dışı sürüm mü? Kablo takılı ve "Güven" onayı verildi mi? |
| Profil / imza doğrulama hatası | Bilgisayarın ve iPhone'un saat/tarihinin doğru olduğundan emin ol. |
| Asist açılmıyor ("artık kullanılamıyor") | İmza dolmuş: bölüm 7. Veriler yerinde. |
| Asist açıldı ama kayıtlar yok | Farklı Apple ID veya farklı paket kimliğiyle yüklenmiş olabilir. Doğru Apple ID ile, kimlik `com.gokhanbudak.asist` olacak şekilde tekrar yükle. Gerekirse Ayarlar › Veriler › **İçe aktar** ile son yedeği geri yükle. |
| Bildirim gelmiyor | Ayarlar › İmza ve izinler: bildirim izni "Açık" mı? Odak açık mı? Ayarlar › Tanılama › **Test bildirimi (10 sn)**. |
| Siri "Asist'e kaydet"i bulamıyor | Asist'i bir kez açıp kapat; Siri dili Türkçe mi? Kestirmeler uygulamasında **Asist** altında eylemler görünüyor mu? |
| Widget boş / yalnız "Dinle" ve "Dokun, Asist dinlesin" yazıyor | Asist'i bir kez aç. Hâlâ öyleyse imza veri paylaşımını vermemiştir (Ayarlar › İmza ve izinler › **Widget veri paylaşımı: Kapalı**); düğmeler yine çalışır. |
| Denetim Merkezi / kilit ekranında **Asist** görünmüyor | Yeni sürümü kurduktan sonra Asist'i bir kez aç ve telefonu bir kez kilitleyip aç. "Remove app extensions" işaretliyse düğmeler yoktur. |

---

## 9. Yedekler

- Asist her gün kendiliğinden yedek alır: **Dosyalar › Bu iPhone'da › Asist › Yedekler** (son 7 gün).
  Aynı klasörde okunabilir bir **Asist-acik-isler.txt** listesi de bulunur.
- Pazar 20:00'de "yedeğini bilgisayara al" hatırlatması gelir: Ayarlar › Veriler › **Dışa aktar (JSON)** ile
  dosyayı bilgisayarına, e-postana veya iCloud Drive'a kaydet.
- Telefon değişirse veya Asist bir şekilde silinirse: Asist'i kur, tanıtımdaki **Yedekten geri yükle**'ye
  (veya Ayarlar › Veriler › **İçe aktar**) dokun ve dışa aktardığın dosyayı seç.

---

## 10. Kilit ekranı düğmesi ve widget'lar (bir kez, ~1 dakika)

iOS, uygulama kapalıyken ses tuşlarını hiçbir uygulamaya iletmez; bu yüzden ses kısma tuşu yalnız Asist açıkken
çalışır. Uygulama kapalıyken en hızlı yol **kilit ekranındaki "Asist Dinle" düğmesidir** (iOS 18). Aynı adımlar
uygulamada da var: **Asist › Ayarlar › Tetikleyiciler › Kilit ekranı ve widget'lar**.

**Kilit ekranına "Asist Dinle" düğmesi**

1. Kilit ekranında ekrana basılı tut → **Özelleştir** → **Kilit Ekranı**.
2. Alttaki fener ya da kamera düğmesinin **−** işaretine dokun, sonra boş kalan yerdeki **+** → **Asist** →
   **Asist Dinle**.
3. Sağ üstten **Bitti**'ye dokun.

Artık kilit ekranından tek dokunuşla Asist açılır ve dinler (önce Face ID ister).

**Denetim Merkezi**

1. Ekranın sağ üst köşesinden aşağı kaydır.
2. Sol üstteki **+** → **Denetim Ekle**.
3. **Asist**'i ara → **Asist Dinle** ya da **Asist Yaz**.

**Ana ekran widget'ı**

1. Ana ekranda boş bir yere basılı tut → **Düzenle** → **Widget Ekle**.
2. **Asist**'i seç → **Küçük** ya da **Orta** boyutu ekle.

Geciken, bugün ve takip sayılarını gösterir. Küçüğe dokununca Asist dinler; ortada **Dinle** ve **Yaz** düğmeleri
ile sıradaki üç iş var.

**Kilit ekranı widget'ları**

1. Kilit ekranında basılı tut → **Özelleştir** → **Kilit Ekranı**.
2. Saatin altındaki alana dokun → **Asist** → **Asist Dinle** (yuvarlak) ya da **Sıradaki iş**.

> Widget'lar boş görünüyorsa (yalnız "Dinle" yazıyorsa) Asist'i bir kez aç. Ayarlar › İmza ve izinler ›
> **Widget veri paylaşımı** "Kapalı" ise ücretsiz imza veri paylaşımını vermemiştir: widget'lar yalnız Asist'i açar,
> düğmeler yine çalışır.
