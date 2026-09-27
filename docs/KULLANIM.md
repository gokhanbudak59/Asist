# Asist — Kullanım Kılavuzu

Asist, aklına geleni **konuşarak** kaydettiğin ve "✓ Yaptım" diyene kadar **kibarca ama ısrarla** hatırlatan bir
asistandır. Uygulama kapalıyken de, telefon kilitliyken de hatırlatır. Kayıtların yalnızca bu telefonda durur.

Kurulum ve haftalık yenileme için: **KURULUM.md**.

---

## 1. Kayıt yolları (tetikleyiciler)

| Yol | Uygulama kapalıyken | Kilitliyken | Nasıl |
|---|---|---|---|
| **Arkaya Dokunma → "Asist Hızlı Kayıt"** (önerilen) | Evet, Asist açılmaz | Kilit açıkken | Telefonun arkasına iki kez vur, konuş, sus. |
| **Siri: "Asist'e kaydet"** | Evet, Asist açılmaz | **Evet** | Siri "Ne kaydedeyim?" der, cümleni söylersin. |
| **Arkaya Dokunma → "Asist Dinle"** | Asist açılıp dinler | Face ID sonrası | Üç kez vur (kurduysan). |
| **Siri: "Asist dinle"** | Asist açılıp dinler | Face ID sonrası | |
| Uygulamadaki **mikrofon** | — | — | Bugün ekranının altındaki büyük düğme. |
| **Ses kısma tuşuna iki kez bas** | Hayır | Hayır | Yalnız Asist ekrandayken; 1 saniye içinde iki kez. |
| **Yaz** | — | — | Klavyeyle; yazarken ne anladığımı canlı gösteririm. |

iOS, uygulamaların ses tuşlarını arka planda veya kilit ekranında dinlemesine izin vermez. Bu yüzden ses kısma
tuşu yalnız Asist açıkken çalışır. Uygulama kapalıyken en hızlı yollar Arkaya Dokunma ve Siri'dir.

### Arkaya Dokunma kurulumu ("Asist Hızlı Kayıt")

Bir kez yapılır (~2 dakika). Uygulamada da adım adım var: **Ayarlar › Tetikleyiciler › Arkaya Dokunma: Asist Hızlı Kayıt**.

1. **Kestirmeler** uygulamasını aç → sağ üstte **+** → **Eylem Ekle**.
2. Aramaya **Dikte** yaz → **Metni Dikte Et**'i ekle; **Dil: Türkçe**, **Dinlemeyi Durdur: Duraklamadan Sonra**.
3. Aramaya **Asist** yaz → **Asist'e Kaydet**'i ekle; **Metin** alanına **Dikte Edilen Metin**'i koy.
4. Kestirmenin adı: **Asist Hızlı Kayıt** → **Bitti**.
5. Ayarlar › Erişilebilirlik › Dokunma › **Arkaya Dokunma** › **Çift Dokunma** → **Asist Hızlı Kayıt**.

İpuçları: ilk seferde Kestirmeler izin sorarsa **Her Zaman İzin Ver**. Kalın kılıfta algılama zayıflayabilir.
Cepte yanlışlıkla tetikleniyorsa **Üç Dokunma** kullan. "Asist Dinle" kestirmesini ayrıca üç dokunmaya atayabilirsin.

### Siri komutları

| Söyle | Ne olur |
|---|---|
| "Asist'e kaydet" (ya da "Asist'e ekle", "Asist'e not al", "Asist hatırlat", "Asist kaydet") | Siri "Ne kaydedeyim?" diye sorar; kaydederim ve ne anladığımı söylerim. |
| "Asist bugün ne var" (ya da "Asist gündem") | Bugünkü işleri ve gecikenleri okurum. |
| "Asist neyi unuttum" / "Asist gecikenler" | Geciken işleri okurum. |
| "Asist dinle" | Asist açılır ve dinlemeye başlar. |

Siri dili **Türkçe** olmalı. Tamamlama, silme ve erteleme için Asist'i açman gerekir ("Bunun için Asist'i açman
gerekiyor" derim). Telefon yeniden başladıktan sonra **ilk kilit açılışına kadar** kayıt yapamam; Siri bunu
söyler, kilidi açıp tekrar söyle — hiçbir şey sessizce kaybolmaz.

---

## 2. Nasıl konuşmalı? Örnek cümleler

Kalıp ezberlemen gerekmez. Aşağıdaki sonuçlar **27 Eylül 2026 Pazar, 10:00**'da söylenmiş gibi yazılmıştır.

| Söylediğin | Kayıt | Zaman / not |
|---|---|---|
| Salı günü teklif konusunu bana saat 3'te hatırlat | Hatırlatma: Teklif konusu | 29 Eylül Salı 15:00 |
| Yarın sabah Ahmet'i aramayı hatırlat | Hatırlatma: Ahmet'i ara | Yarın 09:00 · Kişi: Ahmet |
| Yarım saat sonra fırını kontrol et | Hatırlatma | 10:30 |
| Akşam 8'de ilacımı içmeyi hatırlat | Hatırlatma | Bugün 20:00 |
| Her pazartesi 9'da haftalık raporu hatırlat | Tekrarlayan hatırlatma | Her pazartesi 09:00 |
| Ayın 15'inde faturayı öde | Görev | 15 Ekim 09:00 |
| Mehmet cuma gününe kadar devreye alma raporunu gönderecek | **Takip** | Cuma 16:00'da "Geldi mi?" |
| Mehmet'ten I/O listesini bekliyorum | **Takip** | Tarih yok → 2 iş günü sonra 10:00'da sorarım |
| Kocaeli projesi için not: robot 2 hücresinde ışık perdesi mesafesi tekrar ölçülecek | **Not** (Kocaeli projesi) | Not hatırlatılmaz |
| Perşembe 14'te ABB ile toplantı var, yarım saat önce hatırlat | **Etkinlik**: ABB ile toplantı | 13:30 ön uyarı, 14:00 hatırlatma |
| 2 hafta sonra kalibrasyon sertifikalarını kontrol et | Görev | 11 Ekim Pazar 09:00 — hafta sonu uyarısı ve "Pazartesiye al" |
| 3'te Ali'yi ara | Hatırlatma | Bugün 15:00 |
| Saat 9'da sunucu yedeğine bak | Hatırlatma | Bugün 21:00 (09:00 geçti) — kartta "yarın 09:00" seçeneği |
| Gece 2'de yedeği kontrol et | Hatırlatma | Gece 02:00 — sessiz saatte olsa da çalar |
| Acil: pano ısınma problemini Hakan'la konuş | **Önemli** hatırlatma | Zaman yok → "Ne zaman?" diye sorarım |
| Çok acil, Hakan'ı hemen ara | **Kritik** | 5 dakika sonra |
| Pazartesi SAT için müşteriyle tarih netleştir, önemli | Önemli görev | Pazartesi 09:00 |
| Bu akşam market alışverişi | Görev | Bugün 19:00 |
| Faturaları kontrol et | Görev | Tarih yok → **bugün, zamanı belirsiz** |
| Her 6 ayda bir yangın tüplerini kontrol ettir | Tekrarlayan görev | 6 ayda bir |

Kurallar kısaca:

- **Gün var, saat yok** → o gün **09:00** (Ayarlar › Zamanlar › "Saat söylenmezse").
- **"sabah / öğle / öğleden sonra / akşamüstü / akşam / gece"** → 09:00 / 12:00 / 14:00 / 17:00 / 19:00 / 22:00.
  "Öğleden önce" 11:00. Hepsi Ayarlar › Zamanlar'dan değişir.
- **Niteleyicisiz "saat 3"** gün söylenmişse öğleden sonra (15:00) sayılır; gün yoksa bugünün en yakın gelecekteki
  eşleşmesi.
- **"haftaya" / "gelecek hafta"** (gün yok) → gelecek haftanın ilk iş günü. **"hemen / şimdi / derhal"** → 5 dakika sonra.
- **Hiç zaman söylemezsen**: görevler **bugün, zamanı belirsiz** olarak kaydedilir (hiçbir şey sessizce kaybolmaz);
  hatırlatmalarda "Ne zaman?" diye sorarım. Siri yolunda cevap veremediğin için 1 saat sonra hatırlatırım.
- **Öncelik:** "acil, acilen, önemli, mutlaka" → **Önemli**. "çok acil, kritik, hayati, sakın unutma, asla unutma"
  → **Kritik**.
- **Ön uyarı:** "yarım saat önce hatırlat", "1 gün önce haber ver", "bir hafta kala".
- **Tekrar:** "her gün", "hafta içi her gün", "her pazartesi", "her salı ve perşembe", "her ayın 1'i",
  "her 6 ayda bir". ("Ayın ilk pazartesi" henüz desteklenmez; kartta kontrol etmeni isterim.)
- **Takip:** "… gönderecek", "… dönecek", "… bekliyorum", "… geldi mi diye sor".
- **Not:** "not al", "not et", "… için not: …".
- Kendini düzeltebilirsin: "yarın 3'te, yok yok 4'te" → 16:00.

### Onay kartı

Uygulamada konuştuktan sonra ne anladığımı bir kartta gösteririm. Eminsem birkaç saniyelik geri sayımdan sonra
kendiliğinden kaydederim (Ayarlar › Genel › Otomatik kaydet); karta dokunursan sayım durur, düzeltip **Kaydet**'e basarsın. Emin olmadığım kayıtlar
Bugün ekranında **EMİN OLAMADIKLARIM** bölümünde durur. Yanlışlıkla "Vazgeç"e bastıysan çıkan **Geri Al** ile
cümle geri gelir.

### Sesle sorgu, tamamlama, erteleme (uygulama açıkken)

| Söyle | Ne olur |
|---|---|
| "Bugün ne var", "yarın ne var", "gecikenler neler", "neyi unuttum" | Listeyi gösteririm ve okurum. |
| "Kimden ne bekliyorum" | Açık takipleri okurum. |
| "Kocaeli projesinde ne var", "Ahmet'le ilgili ne var" | İlgili açık işleri okurum. |
| "Teklif işini yaptım", "hallettim", "gönderdim" | Eşleşen kaydı bulur, "tamamlandı mı?" diye sorarım. |
| "Ahmet'i arama hatırlatmasını iptal et" | Eşleşen kaydı bulur, silmeden önce **her zaman** sorarım. |
| "Teklifi perşembeye ertele", "pazartesiye kaydır" | Saati koruyarak yeni güne taşımayı önerim. |

Bir kaydın detayında veya "Şimdi ilgilen" kartında **Sesle ertele**'ye dokunup sadece yeni zamanı söyleyebilirsin:
"perşembe 10'da".

---

## 3. Hatırlatmalar nasıl davranır?

### Bildirim düğmeleri

Bildirimi basılı tut (veya aşağı çek). Kilidi açmana gerek yok:

| Bildirim | Düğmeler |
|---|---|
| Hatırlatma / görev | **✓ Yaptım** · **10 dk** · **1 saat** · **Yarın sabah** |
| Ön uyarı ("30 dk sonra: …") | **✓ Yaptım** (ertelemek için asıl hatırlatmayı bekle) |
| Takip ("Geldi mi?") | **✓ Geldi** · **Yarın tekrar sor** · **2 gün sonra** · **Mesaj gönder…** |
| Sabah brifingi | **Sesli oku** |
| Gün sonu | **Sonraki iş gününe taşı** · **Gözden geçir** |

- Bildirimi **kaydırıp kapatmak "yaptım" demek değildir**; hatırlatma devam eder.
- **Yarın sabah** = yarın mesai başı (iş günü değilse 09:00). Saat 05:00'ten önce basarsan bugünün sabahı.
- Bildirimin kendisine dokunmak kaydı açar; orada 30 dk, 1 saat, Bu akşam, Yarın sabah, Pazartesi, Tarih seç… ve
  **Sesle ertele** var.
- Aynı kaydın bildirimleri tek yığında toplanır; tamamlayınca eskileri Bildirim Merkezi'nden temizlenir.

### Israr düzeyleri

Varsayılan düzey önceliğe göre seçilir (Ayarlar › Hatırlatma ısrarı'ndan değişir; tek kayıt için kayıt detayındaki
"Israr düzeyi"):

| Düzey | Varsayılan öncelik | Aynı gün | Sonra | Günde en fazla |
|---|---|---|---|---|
| **Nazik** | Düşük, Normal | +10 dk, +30 dk, +1,5 saat | mesai içinde 2 saatte bir; akşam tekrar yok | 6 |
| **Israrcı** | Önemli | +5, +15, +30, +60 dk | mesai içinde saatte bir; akşam tekrar yok | 10 |
| **Bırakmaz** | Kritik | +3, +6, +10, +15 dk | her 15 dakikada bir (sessiz saatler hariç) | 30 |
| **Takip** | Takip kayıtları | "Geldi mi?" | iş günlerinde takip saatinde (16:00) günde bir kez | 1 |
| **Etkinlik** | Toplantı, görüşme, ziyaret, FAT/SAT… | başlangıçta bir kez + 15 dk önce ön uyarı | ısrar yok | — |

Örnek (Normal, salı 15:00): 15:00 · 15:10 · 15:30 · 16:30 → çarşamba 08:30 · 10:30 · 12:30 · 14:30 · 16:30 → …

- Günün son hatırlatmasında "Bugünlük son hatırlatma · yarın sabah yine" yazar. Ertesi gün mesai başında devam eder.
- **Uygulamayı hiç açmasan da** hatırlatma birkaç gün devam eder; Önemli ve Kritik işler için her sabah mesai
  başında "Hâlâ açık · her sabah soracağım" gelir; sabah brifingi gecikenleri listeler. Planın sonuna gelinirse
  "Asist'i bir kez aç" bildirimi gelir — açman yeterli.
- 3. ertelemeden sonra "başka bir gün mü?" diye sorarım.
- Önemli ve Kritik işlerin ilk hatırlatmalarında ayırt edici **Asist sesleri** çalar.
- Aynı anda çok iş varsa bildirimler en az 3 dakika arayla ve saatte en fazla 8 olacak şekilde seyreltilir;
  ilk hatırlatmalar hiçbir zaman kaydırılmaz.

### Sessiz saatler

Varsayılan **22:30–07:30**. Bu aralıkta ısrar etmem; aradaki hatırlatmalar sessiz saat bitince tek bildirime
iner. **İstisnalar:** açıkça o saate kurduğun hatırlatma ("gece 2'de yedeği kontrol et") ve kendi seçtiğin erteleme
yine çalar. Ayarlar › Hatırlatma ısrarı › "Kritik işler sessiz saatte de ısrar etsin" (varsayılan kapalı).

### Sessize al (toplantıdayım)

Bugün ekranının üstündeki **zil** simgesi: **30 dk / 1 saat / 2 saat / Mesai sonuna kadar**.

- Bu süredeki ısrarlar süre bitince **tek** bildirimde toplanır.
- Bu sürede gelen ilk hatırlatmalar **sessiz** gelir (Bildirim Merkezi'nde görünür). Kritik işlerin ilk
  hatırlatması ve imza uyarıları yine sesli çalar.
- Bugün ekranında "Sessiz: 11:30'a kadar" bandı görünür; **×** ile hemen kaldırırsın.

Odak (İş / Rahatsız Etme) kullanıyorsan Asist'i izinli uygulamalara ekle; yoksa Odak açıkken hatırlatmaların hepsi
kaybolur. Toplantıda susmam için Odak yerine **Sessize al**'ı kullan.

### Etkinlikler

"toplantı, görüşme, randevu, ziyaret, sunum, eğitim, denetim, FAT, SAT…" içeren ve saati olan kayıtlar **etkinlik**
olur: başlangıçtan 15 dakika önce ön uyarı (Ayarlar › Zamanlar › Toplantı ön uyarısı), başlangıçta bir hatırlatma,
**ısrar yok**. Etkinlik hiçbir zaman "geciken" olmaz ve başlangıçtan **2 saat sonra kendiliğinden kapanır**.
Kartta veya kayıt detayında "Etkinlik" anahtarıyla değiştirebilirsin.

### Sabah brifingi ve gün sonu

- **Sabah brifingi** (iş günleri 08:00): "Günaydın — bugün 5 iş" + gecikenler. **Sesli oku** ile gündemi okurum.
  Boş günlerde gönderilmez (ayarla açılır).
- **Gün sonu** (iş günleri 17:45): açık kalan işler. **Sonraki iş gününe taşı** saatleri koruyarak taşır (hafta
  sonunu atlar); Asist'te 24 saat boyunca **Geri Al** bandı görünür. Notlar, tekrarlayanlar ve etkinlikler taşınmaz.

### Rozet

Uygulama simgesindeki sayı varsayılan olarak **geciken iş sayısı**dır (Ayarlar › Hatırlatma ısrarı › Rozet:
Gecikenler / Gecikenler + bugün / Kapalı).

### Bant uyarıları

Bugün ekranının üstünde gerektiğinde tek bir bant çıkar: bildirimler kapalı (kırmızı), veri geri yüklendi,
imza bitiyor, mikrofon kapalı, "Kalıcı" banner ipucu gibi. Bantaki düğme doğrudan ilgili ayarı açar.

---

## 4. Ekranlar

- **Bugün:** GECİKENLER (en üstte; en önemlisi "Şimdi ilgilen" kartında) · EMİN OLAMADIKLARIM · BUGÜN · TAKİP ·
  YAKLAŞAN · ZAMANI BELİRSİZ. Altta **Yaz · Mikrofon · Oku**.
- **Listeler:** Hatırlatmalar, Görevler, Notlar, Takip, Tamamlananlar; arama ve sıralama. Sağa kaydır: **Yaptım**;
  sola kaydır: **Ertele**, **Sil** (Geri Al ile).
- **Projeler:** projeye göre işler ve notlar; **Bu projeye sesli not**. Proje adlarına takma ad ekleyebilirsin
  ("Kocaeli hattı" = "KCL").
- **Kayıt detayı:** zaman, tekrar, ön uyarı (Yok, 10 dk … 30 gün), ısrar düzeyi, kişi/firma, notlar, kontrol listesi
  şablonları (FAT, SAT, Devreye alma, Saha ziyareti, Toplantı hazırlığı), orijinal cümle ve geçmiş.
  Takip kayıtlarında **Mesaj gönder** hazır bir hatırlatma mesajı açar (WhatsApp, e-posta, SMS).

---

## 5. Veriler ve yedekler

- Kayıtların **yalnızca bu telefonda** saklanır; her değişiklik anında diske yazılır. Uygulamayı kapatmak veya
  telefonu yeniden başlatmak hiçbir şey silmez.
- **Günlük otomatik yedek:** Dosyalar › **Bu iPhone'da › Asist › Yedekler** (son 7 gün,
  `asist-yedek-YYYY-AA-GG.json`).
- **Asist-acik-isler.txt:** aynı klasörde, açık işlerinin **okunabilir** listesi. Asist açılmasa bile (ör. imza
  dolduysa) Dosyalar uygulamasından okuyabilirsin.
- **Dışa aktar:** Ayarlar › Veriler › **Dışa aktar (JSON)** → paylaşım sayfasından bilgisayarına, e-postana,
  iCloud Drive'a. Her pazar 20:00'de hatırlatırım (Ayarlar › Özetler › Yedek).
- **İçe aktar:** Ayarlar › Veriler › **İçe aktar…** → dosyayı seç → "124 kayıt, 6 proje içe aktarılacak" →
  - **Birleştir:** mevcut kayıtların korunur; aynı kayıtta daha yeni olan kalır; ayarların değişmez.
  - **Değiştir:** kayıtlar ve ayarlar yedektekiyle değiştirilir. Önce şu anki verinin bir kopyası Yedekler
    klasörüne alınır.
- **Günlük yedeğe dön:** Ayarlar › Veriler › Günlük yedekler → bir güne dokun → **Geri yükle**.
- **Son silinenler:** Ayarlar › Veriler › **Son silinenler** — silinen kayıtlar 30 gün durur; sağa kaydırıp
  **Geri getir**.
- **Asist'i silersen** telefondaki bütün veriler ve Yedekler klasörü de silinir. Haftalık dışa aktarmayı
  bu yüzden ihmal etme.

---

## 6. Ayarlar özeti

| Bölüm | İçerik |
|---|---|
| Genel | Hitap, sesli onay (yalnız kulaklık/araçta; "Hoparlörden de söyle"), konuşma hızı, otomatik kaydetme, zaman söylenmezse ne yapılacağı |
| Zamanlar | İş günleri, mesai, tatil günü sabahı, sessiz saatler, günün bölümleri, takip saatleri, toplantı ön uyarısı |
| Hatırlatma ısrarı | Önceliğe göre ısrar düzeyi ve önizleme, kritikte sessiz saat, rozet, kilit ekranında konu |
| Özetler | Sabah brifingi, gün sonu, haftalık yedek hatırlatması |
| Tetikleyiciler | Ses kısma tuşu, sessizlik süresi, cihaz içi tanıma, kurulum rehberleri |
| Veriler | Dışa/içe aktar, günlük yedekler, son silinenler |
| İmza ve izinler | İmza bitişi, bildirim/mikrofon izinleri, Banner Stili, veri dosyası durumu |
| Tanılama | Son planlama, bekleyen bildirimler (n/64), günlük, **Test bildirimi (10 sn)**, **Planı yeniden kur** |

**Sesli onaylar** yalnızca kulaklık, Bluetooth veya araç bağlıyken söylenir (toplantıda hoparlörden konuşmam);
diğer durumlarda ekranda "Kaydedildi" gösterir, hafifçe titreşirim. "Bugün ne var" gibi sorulara cevabı her zaman
okurum.

---

## 7. Bilmende fayda var

- iOS bir uygulama için en fazla **64** bekleyen bildirim tutar. Asist en yakın ve en önemli olanları planlar;
  sığmayanlar için "planı tazelemek için Asist'i aç" bildirimi gönderir. Asist'i günde bir kez açman her şeyi tazeler.
- İmza bitmeden **48, 24 ve 4 saat önce** uyarırım. Her pazartesi yenile (KURULUM.md bölüm 7), sonra Asist'i bir
  kez aç.
- **Ayarlar › Tanılama** ekranı, bir sorun olduğunda paylaşabileceğin bir günlük içerir;
  günlükte söylediğin cümleler ve not içerikleri bulunmaz.
