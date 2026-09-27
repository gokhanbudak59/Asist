// Lexicon — 02 §5, §7.8, §10 tables + 04 §3.4.6 amendments (G1–G12, C2). All keys are FOLDED (02 §3.2).
import Foundation

struct PriorityPhrase {
    let words: [String]
    let level: Priority
    /// false = adjective ("önemli", "öncelikli"): removed only at the edges or before ":" (02 §7.8).
    let alwaysRemove: Bool
    /// "sakın unutma" also acts as the reminder cue.
    let isReminderCue: Bool
}

struct DaypartPhrase {
    let words: [String]
    let slot: DaypartSlot
    let qualifier: DaypartQualifier?
    let explicitToday: Bool
}

enum DaypartSlot: Equatable {
    case sabah, ogledenOnce, ogle, oglePlus60, ogledenSonra, aksamustu, aksam, gece, midnight, mesaiBasi, mesaiBitimi
}

struct ContentCompletion {
    let words: [String]
    /// Verb stem appended to `queryText` ("Ahmet'i aradım" → "ahmet ara").
    let stem: String
}

enum Lexicon {
    // MARK: Suffix classes (02 §5.1, folded)
    static let locative: [String] = ["de", "da", "te", "ta", "nde", "nda"]
    static let dative: [String] = ["e", "a", "ye", "ya", "ne", "na"]
    static let accusative: [String] = ["i", "u", "yi", "yu", "ni", "nu"]
    static let ablative: [String] = ["den", "dan", "ten", "tan", "nden", "ndan"]
    static let genitive: [String] = ["in", "un", "nin", "nun"]
    static let instrumental: [String] = ["le", "la", "yle", "yla"]
    static let possessive3: [String] = ["i", "u", "si", "su"]
    static let possessive3Locative: [String] = ["inde", "inda", "unde", "unda", "sinde", "sinda", "sunde", "sunda",
                                                "nde", "nda"]
    static let possessive3Dative: [String] = ["ine", "una", "sine", "suna", "ina", "une", "sina", "sune"]
    static let ordinal: [String] = ["inci", "nci", "uncu", "ncu"]
    static let ki: [String] = ["ki", "daki", "deki", "taki", "teki", "nki"]
    static let pluralDays: [String] = ["leri", "lari", "lerinde", "larinda", "lerde", "larda"]

    static let caseSuffixes: [String] = joined([[""], locative, dative, accusative, ablative, genitive, instrumental])

    // MARK: Weekdays / months (02 §5.2, §5.3)
    static let weekdays: [(key: String, iso: Int)] = [
        ("pazartesi", 1), ("pztesi", 1), ("pzt", 1), ("sali", 2), ("carsamba", 3), ("carsambe", 3),
        ("persembe", 4), ("persenbe", 4), ("cumartesi", 6), ("cmt", 6), ("cuma", 5), ("pazar", 7)
    ]
    static let weekdaySuffixes: [String] = joined([[""], locative, dative, accusative, ablative, genitive, ki])
    static let months: [(key: String, month: Int)] = [
        ("ocak", 1), ("ocag", 1), ("subat", 2), ("mart", 3), ("nisan", 4), ("mayis", 5), ("haziran", 6),
        ("temmuz", 7), ("agustos", 8), ("eylul", 9), ("ekim", 10), ("kasim", 11), ("aralik", 12), ("aralig", 12)
    ]
    static let monthSuffixes: [String] = joined([[""], locative, dative, ablative, genitive, accusative])
    static let monthStartWords: [String] = ["basi", "basinda", "basina"]
    static let monthMiddleWords: [String] = ["ortasi", "ortasinda", "ortasina"]
    static let monthEndWords: [String] = ["sonu", "sonunda", "sonuna"]
    static let monthAyiWords: [String] = ["ayi", "ayinda", "ayinin"]
    static let dateGlueWords: [String] = ["tarihinde", "tarihli", "tarihine", "tarihe", "tarihinden", "tarihte", "gunu"]
    /// Weekday qualifiers (02 §5.4 last paragraph).
    static let weekdayQualifiers: [String: String] = ["bu": "this", "gelecek": "next", "onumuzdeki": "next",
                                                      "ilk": "next", "haftaya": "nextweek", "gecen": "past"]
    static let ordinalWords: [String: Int] = ["ilk": 1, "birinci": 1, "ikinci": 2, "ucuncu": 3, "dorduncu": 4,
                                              "son": -1, "sonuncu": -1]

    // MARK: Fillers / connectors (02 §5.6, §5.7)
    static let fillers: Set<String> = ["ya", "yaa", "sey", "hani", "yani", "acaba", "bakalim", "eee", "ee", "eh",
                                       "hmm", "hm", "hmmm", "mmm", "ii", "iii", "lutfen", "bana", "beni", "bize",
                                       "bi", "birde", "ayrica", "olsun", "hemen", "simdi", "derhal", "aa"]
    /// Matched on the lowercase (unfolded) form: folded "iste" collides with the verb "iste" (request).
    static let fillersLower: Set<String> = ["işte"]
    static let fillerPhrases: [[String]] = [["rica", "etsem"], ["benim", "icin"], ["bir", "de"], ["tamam", "mi"],
                                            ["olur", "mu"], ["de", "mi"], ["hemen", "simdi"]]
    static let connectors: Set<String> = ["ve", "ile", "ilen", "icin", "diye", "de", "da", "ki", "ama", "fakat",
                                          "ancak", "olarak", "hakkinda", "konusunda", "gibi", "kadar", "veya",
                                          "yada"]
    static let connectorPhrases: [[String]] = [["en", "gec"], ["ya", "da"]]
    static let pronouns: Set<String> = ["bu", "bunu", "su", "sunu", "o", "onu", "sunlari", "bunlari", "soyle"]
    static let hemenWords: Set<String> = ["hemen", "simdi", "derhal", "acilen"]

    // MARK: Priority (02 §7.8 as amended by C2)
    static let priorityExceptions: [[String]] = [
        ["acil", "stop"], ["acil", "stopu"], ["acil", "durdurma"], ["acil", "durus"], ["acil", "durum"],
        ["acil", "durumda"], ["acil", "durumu"], ["acil", "cikis"], ["acil", "servis"], ["acil", "butonu"],
        ["acil", "buton"], ["acil", "aydinlatma"], ["acil", "toplanma"], ["kritik", "yol"], ["kritik", "yolu"],
        ["kritik", "parca"], ["kritik", "parcalar"], ["kritik", "stok"]
    ]
    static let priorityPhrases: [PriorityPhrase] = [
        PriorityPhrase(words: ["onemli", "degil"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["acil", "degil"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["onemsiz"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["acelesi", "yok"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["acele", "yok"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["bos", "vaktimde"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["firsat", "bulursam"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["vakit", "olursa"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["vaktim", "olursa"], level: .low, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["cok", "acil"], level: .critical, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["kritik"], level: .critical, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["hayati"], level: .critical, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["sakin", "ha", "unutma"], level: .critical, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["sakin", "unutma"], level: .critical, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["asla", "unutma"], level: .critical, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["kesinlikle", "unutma"], level: .critical, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["cok", "onemli"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["yuksek", "oncelikli"], level: .high, alwaysRemove: false, isReminderCue: false),
        PriorityPhrase(words: ["unutmamam", "lazim"], level: .high, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["unutmamam", "gerek"], level: .high, alwaysRemove: true, isReminderCue: true),
        PriorityPhrase(words: ["ilk", "is", "olarak"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["ilk", "is", "olsun"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["ilk", "is"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["acil"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["acilen"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["mutlaka"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["kesinlikle"], level: .high, alwaysRemove: true, isReminderCue: false),
        PriorityPhrase(words: ["onemli"], level: .high, alwaysRemove: false, isReminderCue: false),
        PriorityPhrase(words: ["oncelikli"], level: .high, alwaysRemove: false, isReminderCue: false)
    ]

    // MARK: Kind cues (02 §10)
    static let reminderObjectNounPrefixes: [String] = ["hatirlatma", "hatirlatici"]
    static let questionParticles: Set<String> = ["mi", "mu", "misin", "musun", "misiniz", "musunuz", "midir",
                                                 "mudur", "miyim", "muyum"]
    static let reminderPhrases: [[String]] = [
        ["unutmayayim"], ["unutma"], ["unutmayin"], ["unutturma"], ["aklima", "getir"], ["aklima", "sok"],
        ["ikaz", "et"], ["alarm", "kur"], ["alarm", "ayarla"], ["beni", "durt"], ["durt"],
        ["bana", "haber", "ver"], ["bana", "bildir"], ["bana", "soyle"], ["beni", "uyar"]
    ]
    /// Reminder cues only when the indirect object is the user or absent (02 §10.3).
    static let reminderConditional: [[String]] = [["haber", "ver"], ["bildir"], ["soyle"], ["uyar"],
                                                  ["uyarir", "misin"], ["haber", "verir", "misin"]]
    static let noteStrongPhrases: [[String]] = [
        ["not", "olarak", "kaydet"], ["not", "olarak", "ekle"], ["not", "al"], ["not", "et"], ["not", "dus"],
        ["nota", "ekle"], ["notlara", "ekle"], ["not", "tut"], ["notlarima", "ekle"], ["not", "alir", "misin"]
    ]
    static let taskPhrases: [[String]] = [
        ["gorev", "olarak", "ekle"], ["gorev", "olarak", "kaydet"], ["gorev", "ekle"], ["gorevlere", "ekle"],
        ["yapilacaklar", "listesine", "ekle"], ["yapilacaklara", "ekle"], ["listeye", "ekle"], ["listeme", "ekle"],
        ["is", "listesine", "ekle"], ["islere", "ekle"], ["yapilacak", "olarak", "ekle"], ["gorevlerime", "ekle"]
    ]
    static let noteWeakPhrases: [[String]] = [["bunu", "yaz"], ["sunu", "yaz"], ["kenara", "yaz"],
                                              ["aklimda", "olsun"], ["aklinda", "olsun"], ["bilgi", "olarak"],
                                              ["kaydet"]]
    static let taskModality: Set<String> = ["lazim", "gerek", "gerekiyor", "gerekiyordu", "gerekli", "sart",
                                            "gerekecek"]
    static let modalitySuffixes: [String] = ["maliyim", "meliyim", "maliyiz", "meliyiz"]

    // MARK: Waiting-for (02 §10.4 + G2)
    static let waitingBekle: Set<String> = ["bekliyorum", "bekleniyor", "beklemedeyim", "bekleyecegim", "bekliyoruz",
                                            "bekleyecegiz", "beklemedeyiz", "bekliyordum"]
    static let waitingFuture: [[String]] = [
        ["donus", "yapacak"], ["donus", "saglayacak"], ["cevap", "verecek"], ["yanit", "verecek"],
        ["haber", "verecek"], ["bilgi", "verecek"], ["teslim", "edecek"], ["onay", "verecek"],
        ["teklif", "verecek"], ["fiyat", "verecek"], ["geri", "donecek"], ["mail", "atacak"],
        ["geri", "donus", "yapacak"], ["cevap", "yazacak"], ["kontrol", "edecek"],
        ["gonderecek"], ["yollayacak"], ["iletecek"], ["donecek"], ["arayacak"], ["getirecek"], ["hazirlayacak"],
        ["onaylayacak"], ["bakacak"], ["halledecek"], ["yapacak"], ["atacak"], ["paylasacak"], ["yukleyecek"],
        ["cikaracak"], ["kesecek"], ["ayarlayacak"], ["bitirecek"], ["duzeltecek"], ["gelecek"]
    ]
    static let waitingFollow: [[String]] = [
        ["takip", "et"], ["takibe", "al"], ["takipte", "kal"], ["pesine", "dus"], ["donusunu", "bekle"],
        ["cevabini", "bekle"], ["hatirlatmasini", "bekle"], ["takip", "edelim"], ["takibini", "yap"]
    ]
    /// G2: a capitalised common noun / plural at index 0 is not a person (P7 restriction).
    static let waitingCommonNouns: [String] = [
        "tedarikci", "musteri", "firma", "servis", "ekip", "malzeme", "surucu", "numune", "siparis", "parca",
        "kargo", "teklif", "fatura", "rapor", "cizim", "motor", "sensor", "cihaz", "urun", "paket", "evrak",
        "belge", "dosya", "onay", "cevap", "yanit", "odeme", "teslimat", "montaj", "ekipman", "robot", "panel",
        "pano", "kablo", "vana", "valf", "pompa", "filtre", "yedek", "muhendis", "teknisyen", "elektrikci",
        "nakliye", "arac", "kamyon", "tir", "forklift", "mal", "fiyat", "proje", "lisans", "yazilim", "program",
        "dokuman", "katalog", "usta", "operator", "vardiya", "bakimci", "elektrik", "mekanik", "hidrolik",
        "pnomatik", "kalite", "satinalma", "muhasebe", "insan", "personel", "stajyer", "sofor", "kurye",
        "nakliyeci"
    ]

    // MARK: Queries (02 §10.5.1 + G6)
    static let queryPhrases: [[String]] = [
        ["kimden", "ne", "bekliyorum"], ["neler", "yapmam", "lazim"], ["neler", "yapmam", "gerekiyor"],
        ["ne", "yapmam", "lazim"], ["ne", "yapmam", "gerekiyor"], ["programimda", "ne", "var"],
        ["ne", "isim", "var"], ["ne", "var"], ["neler", "var"], ["nelerim", "var"], ["neler", "yapacagim"],
        ["ne", "yapacagim"], ["ne", "bekliyorum"], ["neler", "bekliyorum"], ["programim", "ne"], ["programim"],
        ["ajandami", "oku"], ["ajandam"], ["ajandami"], ["listele"], ["oku"], ["goster"], ["sirala"], ["ozetle"],
        ["say"], ["okur", "musun"], ["soyler", "misin"]
    ]
    static let queryTodayPhrases: [[String]] = [
        ["ne", "var"], ["neler", "var"], ["nelerim", "var"], ["programim", "ne"], ["programim"],
        ["ajandami", "oku"], ["ajandam"], ["ajandami"], ["programimda", "ne", "var"], ["ne", "isim", "var"],
        ["var", "mi"]
    ]
    static let queryWaitingPhrases: [[String]] = [["ne", "bekliyorum"], ["neler", "bekliyorum"],
                                                  ["kimden", "ne", "bekliyorum"]]
    static let queryObjectWords: Set<String> = [
        "hatirlatmalarimi", "hatirlatmalarim", "hatirlaticilarimi", "hatirlaticilarim", "gorevlerimi",
        "yapilacaklari", "notlarimi", "islerimi", "islerim", "gecikenleri", "bekleyenleri", "alarmlarimi",
        "alarmlarim", "programimi", "hatirlatmalari", "isleri", "gorevleri", "notlari"
    ]
    static let queryScopeWords: [String: QueryScope] = [
        "geciken": .overdue, "gecikenler": .overdue, "gecikenleri": .overdue, "gecikmis": .overdue,
        "gecikmisler": .overdue, "gecikmisleri": .overdue, "kacirdiklarim": .overdue, "kacirdiklarimi": .overdue,
        "unuttuklarim": .overdue, "unuttuklarimi": .overdue, "yapmadiklarim": .overdue,
        "yapmadiklarimi": .overdue, "yapilmayanlar": .overdue, "yapilmayanlari": .overdue,
        "bekleyen": .waiting, "bekleyenler": .waiting, "bekleyenleri": .waiting, "kimden": .waiting,
        "notlarim": .notes, "notlarimi": .notes, "notlar": .notes, "notlari": .notes,
        "gorevlerim": .tasks, "gorevlerimi": .tasks, "yapilacaklar": .tasks, "yapilacaklari": .tasks,
        "gorevler": .tasks, "gorevleri": .tasks
    ]
    static let queryGlue: Set<String> = ["ile", "ilgili", "hakkinda", "icin", "sirada", "simdi", "acaba", "peki",
                                         "bakalim", "benim", "bende", "neler", "ne"]
    static let overdueQuestionWords: Set<String> = ["ne", "neyi", "neleri"]
    static let overdueQuestionVerbs: Set<String> = ["unuttum", "kacirdim", "atladim", "unuttuk", "kacirdik",
                                                    "atladik"]

    // MARK: Commands (02 §10.5 + G3–G5)
    static let completePlain: [[String]] = [
        ["tamamlandi", "olarak", "isaretle"], ["yapildi", "olarak", "isaretle"], ["tik", "at"], ["yaptim"],
        ["yapildi"], ["tamamladim"], ["tamamlandi"], ["tamamdir"], ["bitirdim"], ["bitti"], ["hallettim"],
        ["halloldu"], ["hallolmustur"], ["yaptik"], ["tamamladik"], ["bitirdik"], ["hallettik"], ["bitirildi"]
    ]
    static let completeContent: [ContentCompletion] = [
        ContentCompletion(words: ["teslim", "ettim"], stem: "teslim et"),
        ContentCompletion(words: ["teslim", "ettik"], stem: "teslim et"),
        ContentCompletion(words: ["kontrol", "ettim"], stem: "kontrol et"),
        ContentCompletion(words: ["kontrol", "ettik"], stem: "kontrol et"),
        ContentCompletion(words: ["aradim"], stem: "ara"), ContentCompletion(words: ["aradik"], stem: "ara"),
        ContentCompletion(words: ["gonderdim"], stem: "gönder"),
        ContentCompletion(words: ["gonderdik"], stem: "gönder"),
        ContentCompletion(words: ["yolladim"], stem: "yolla"), ContentCompletion(words: ["yolladik"], stem: "yolla"),
        ContentCompletion(words: ["ilettim"], stem: "ilet"), ContentCompletion(words: ["ilettik"], stem: "ilet"),
        ContentCompletion(words: ["konustum"], stem: "konuş"), ContentCompletion(words: ["konustuk"], stem: "konuş"),
        ContentCompletion(words: ["gorustum"], stem: "görüş"), ContentCompletion(words: ["gorustuk"], stem: "görüş"),
        ContentCompletion(words: ["odedim"], stem: "öde"), ContentCompletion(words: ["odedik"], stem: "öde"),
        ContentCompletion(words: ["aldim"], stem: "al"), ContentCompletion(words: ["aldik"], stem: "al"),
        ContentCompletion(words: ["hazirladim"], stem: "hazırla"),
        ContentCompletion(words: ["hazirladik"], stem: "hazırla")
    ]
    static let completeFinal: [[String]] = [["elime", "gecti"], ["teslim", "alindi"], ["geldi"], ["ulasti"],
                                            ["gitti"], ["gonderildi"], ["iletildi"]]
    /// Nouns that look like a past 1sg/1pl verb ("denetim", "eğitim", "otomatik").
    static let genericPastExclusions: Set<String> = [
        "egitim", "denetim", "uretim", "yonetim", "iletim", "isletim", "tuketim", "yetim", "tutum", "lastik",
        "mantik", "koltuk", "matematik", "pnomatik", "aritmetik", "romantik", "semantik", "hermetik", "ritmik",
        "gotik", "kendim", "adim", "otomatik", "kritik", "pratik", "politik", "plastik", "statik", "optik",
        "artik", "butik", "fantastik", "manyetik", "sentetik", "kinetik", "estetik", "teknik", "lojistik",
        "istatistik", "elastik", "akustik", "dikdik"
    ]
    static let cancelPhrases: [[String]] = [
        ["iptal", "eder", "misin"], ["iptal", "et"], ["iptal", "edin"], ["iptal", "oldu"], ["iptal", "edildi"],
        ["iptal"], ["sil", "gitsin"], ["sil"], ["kaldir"], ["vazgec"], ["vazgectim"], ["vazgectik"],
        ["gerek", "yok"], ["gerek", "kalmadi"], ["bosver"], ["bos", "ver"], ["yapilmayacak"], ["siler", "misin"]
    ]
    static let snoozePhrases: [[String]] = [
        ["sonra", "tekrar", "hatirlat"], ["daha", "sonra", "hatirlat"], ["biraz", "sonra", "hatirlat"],
        ["erteler", "misin"], ["sonra", "hatirlat"], ["tekrar", "hatirlat"], ["yeniden", "hatirlat"],
        ["sonraya", "at"], ["sonraya", "birak"], ["ertele"], ["otele"], ["kaydir"]
    ]
    /// G3: DATE+DAT bırak / al / taşı.
    static let snoozeDateVerbs: Set<String> = ["birak", "al", "tasi"]
    static let snoozeAlObjectEndings: [String] = ["isini", "hatirlatmasini", "gorevini", "toplantisini"]
    static let commandObjectWords: Set<String> = [
        "hatirlatma", "hatirlatmayi", "hatirlatmasini", "hatirlatmasi", "hatirlatmalarini", "hatirlatici",
        "hatirlaticiyi", "hatirlaticisini", "hatirlaticisi", "alarm", "alarmi", "alarmini", "gorevi", "gorevini",
        "kaydi", "kaydini"
    ]
    /// Trailing words skipped when looking for the last verb phrase (02 §10.5).
    static let tailSkip: Set<String> = ["lutfen", "ya", "yaa", "sey", "hani", "acaba", "bakalim", "hmm", "eee",
                                        "ee", "onu", "bunu", "sunu", "hemen", "simdi", "artik", "de", "da"]

    // MARK: T9 imperative content verbs (02 §10.6, extended)
    static let imperatives: Set<String> = [
        "ara", "gonder", "yolla", "ilet", "al", "ver", "hazirla", "yaz", "bak", "incele", "oku", "duzelt",
        "guncelle", "onayla", "imzala", "ode", "topla", "planla", "ayarla", "yukle", "indir", "kur", "tak",
        "degistir", "temizle", "bitir", "tamamla", "soyle", "sor", "konus", "gorus", "yedekle", "goster", "yap",
        "kapat", "ac", "gir", "iste", "gotur", "getir", "cikar", "baslat", "kilitle", "sula", "yika", "yikat",
        "ugra", "git", "dene", "hesapla", "cek", "bul", "ogren", "danis", "sat", "kargola", "paketle", "yaptir",
        "baktir", "ilgilen", "hallet", "duzenle", "onar", "olc", "calistir", "durdur", "paylas", "cevapla",
        "yanitla", "doldur", "bosalt", "kes", "uzat", "yenile", "bildir", "dinle", "izle", "ekle", "yazdir",
        "tara", "postala", "gonderin", "arayin", "ayir", "sec", "belirle", "tanimla", "birak", "koy", "yerlestir",
        "tas", "boya", "sil"
    ]
    static let imperativePhrases: [[String]] = [
        ["kontrol", "et"], ["siparis", "et"], ["siparis", "ver"], ["teslim", "et"], ["test", "et"],
        ["haber", "ver"], ["toplanti", "yap"], ["mail", "at"], ["e-posta", "at"], ["eposta", "at"],
        ["mesaj", "at"], ["yedek", "al"], ["rapor", "yaz"], ["teklif", "ver"], ["gozden", "gecir"],
        ["tamir", "et"], ["kalibre", "et"], ["kontrol", "ettir"], ["takip", "et"], ["randevu", "al"],
        ["rezervasyon", "yap"], ["organize", "et"], ["ziyaret", "et"], ["geri", "yukle"], ["yeniden", "baslat"],
        ["dikkat", "et"], ["telefon", "et"], ["mail", "gonder"]
    ]
    static let askVerbs: Set<String> = ["sor", "danis", "ogren", "sorsun", "sorun"]
    /// 02 §12 multipleItems joiners.
    static let multiJoiners: [[String]] = [["ve", "ayrica"], ["sonra", "da"], ["bir", "de"], ["ayrica"]]

    // MARK: Places (02 §7.3)
    static let arriveTriggers: [[String]] = [
        ["varir", "varmaz"], ["varinca"], ["vardigimda"], ["gidince"], ["gittigimde"], ["gelince"], ["geldigimde"],
        ["girince"], ["girdigimde"], ["ulasinca"], ["ulastigimda"], ["vardiginda"], ["gidersem"]
    ]
    static let leaveTriggers: [[String]] = [["cikmadan", "once"], ["cikinca"], ["ciktigimda"], ["cikarken"],
                                            ["ayrilinca"], ["ayrildigimda"], ["ayrilirken"]]

    // MARK: G1 equipment numbers, G11 units and versions
    static let equipmentNouns: Set<String> = [
        "hat", "hatti", "hattin", "istasyon", "istasyonu", "robot", "robotu", "hucre", "hucresi", "pano", "panosu",
        "kat", "kati", "bant", "bandi", "konveyor", "konveyoru", "eksen", "ekseni", "makine", "makinesi", "kabin",
        "kabini", "no", "numara", "numarali", "tezgah", "tezgahi", "motor", "motoru", "servo", "surucu",
        "surucusu", "pres", "presi", "kazan", "hol", "bina", "blok", "depo", "deposu", "oda", "odasi", "salon",
        "kapi", "kapisi", "hucreye", "hatta", "hattina"
    ]
    static let numberNameWords: Set<String> = ["nolu", "numarali", "no", "numara", "numarada", "numaraya"]
    static let unitWords: Set<String> = [
        "v", "volt", "bar", "mm", "cm", "m", "metre", "kw", "kv", "kva", "a", "amper", "ma", "hz", "adet", "kg",
        "gr", "gram", "ton", "lt", "litre", "w", "watt", "derece", "rpm", "ms", "mbar", "psi", "nm", "hp", "ohm",
        "euro", "eur", "tl", "lira", "dolar", "usd", "yuzde", "kisi", "kisilik", "tane", "paket", "koli",
        "palet", "metrekare", "m2", "m3", "inc", "inch", "mikron", "um", "sn", "saniye", "kanal", "eksen", "bit",
        "byte", "mb", "gb", "kb", "mbps", "cc", "ml"
    ]
    static let versionWords: Set<String> = ["firmware", "surum", "surumu", "surume", "versiyon", "versiyonu",
                                            "versiyona", "v", "revizyon", "rev", "guncelleme", "guncellemesi",
                                            "yazilim", "yazilimi"]
    static let versionVerbs: Set<String> = ["guncelle", "yukselt", "guncellendi", "yukle"]

    // MARK: G8 correction markers
    static let correctionMarkers: [[String]] = [["yok", "yok"], ["degil", "de"], ["yok", "hayir"], ["hayir"],
                                                ["yok"], ["pardon"], ["yani"], ["degil"], ["aslinda"]]

    // MARK: Prefix markers (02 §7.1)
    static let notePrefixBlock: Set<String> = ["al", "et", "tut", "dus", "defteri", "defterimi", "defterini",
                                               "almayi", "olarak", "alir", "aldim", "ettim", "etmeyi", "almak",
                                               "etmek"]

    // MARK: Projects (02 §7.2)
    static let projectSuffixes: Set<String> = Set(joined([caseSuffixes, ki, projectExtraSuffixes]))
    static let projectExtraSuffixes: [String] = ["nin", "nun", "na", "ne", "nda", "nde", "ndan", "nden", "yla", "yle",
                                                 "si", "su", "sinde", "sinda", "sine", "sina", "sini", "sinin",
                                                 "siyle", "ndaki", "ndeki", "nu", "ni", "yu", "yi", "nunla", "ninle"]
    static let projectMarkerForms: Set<String> = ["projesi", "projesine", "projesinde", "projesinin", "projesiyle"]

    // MARK: Dayparts (02 §5.5 + G7 + P5)
    static let daypartPhrases: [DaypartPhrase] = [
        DaypartPhrase(words: ["ogleden", "sonra", "ilk", "is"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["ogle", "yemeginden", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["oglen", "yemeginden", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["ogle", "yemekten", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["oglen", "yemekten", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["ogle", "arasindan", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["oglen", "arasindan", "sonra"], slot: .oglePlus60, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["isten", "cikmadan", "once"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["bu", "sabah"], slot: .sabah, qualifier: .am, explicitToday: true),
        DaypartPhrase(words: ["bu", "ogle"], slot: .ogle, qualifier: .noon, explicitToday: true),
        DaypartPhrase(words: ["bu", "oglen"], slot: .ogle, qualifier: .noon, explicitToday: true),
        DaypartPhrase(words: ["bu", "aksamustu"], slot: .aksamustu, qualifier: .pm, explicitToday: true),
        DaypartPhrase(words: ["bu", "aksam"], slot: .aksam, qualifier: .evening, explicitToday: true),
        DaypartPhrase(words: ["bu", "gece"], slot: .gece, qualifier: .night, explicitToday: true),
        DaypartPhrase(words: ["gece", "yarisi"], slot: .midnight, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["gece", "yarisinda"], slot: .midnight, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["gece", "yarisina"], slot: .midnight, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["ogleden", "sonra"], slot: .ogledenSonra, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["ogleden", "sonraya"], slot: .ogledenSonra, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["ogleden", "once"], slot: .ogledenOnce, qualifier: .am, explicitToday: false),
        DaypartPhrase(words: ["ogleye", "kadar"], slot: .ogledenOnce, qualifier: .am, explicitToday: false),
        DaypartPhrase(words: ["ogleden", "evvel"], slot: .ogledenOnce, qualifier: .am, explicitToday: false),
        DaypartPhrase(words: ["ogle", "arasi"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["ogle", "arasinda"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["oglen", "arasi"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["oglen", "arasinda"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["ogle", "yemeginde"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["ogle", "yemegi"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["oglen", "yemeginde"], slot: .ogle, qualifier: .noon, explicitToday: false),
        DaypartPhrase(words: ["aksam", "ustu"], slot: .aksamustu, qualifier: .pm, explicitToday: false),
        DaypartPhrase(words: ["mesai", "basi"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "basinda"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "basina"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesaiye", "baslarken"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["ise", "gelince"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["ise", "gelir", "gelmez"], slot: .mesaiBasi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "bitimi"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "bitiminde"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "bitimine"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "sonu"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "sonunda"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesai", "sonuna"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["is", "cikisi"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["is", "cikisinda"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["isten", "cikarken"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["isten", "cikinca"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false),
        DaypartPhrase(words: ["mesaiden", "sonra"], slot: .mesaiBitimi, qualifier: nil, explicitToday: false)
    ]
    static let daypartSabah: Set<String> = ["sabah", "sabahleyin", "sabaha", "sabahtan", "sabahi", "sabahin",
                                            "sabahinda", "sabahki"]
    static let daypartOgle: Set<String> = ["ogle", "oglen", "ogleyin", "oglene", "ogleye", "oglesi", "ogleni",
                                           "oglenleyin", "ogleki", "oglenki"]
    static let daypartAksamustu: Set<String> = ["aksamustu", "aksamustune", "aksamustunu", "aksamustleri",
                                                "aksamustunde"]
    static let daypartAksam: Set<String> = ["aksam", "aksama", "aksamleyin", "aksamki", "aksami", "aksamin",
                                            "aksaminda"]
    static let daypartGece: Set<String> = ["gece", "geceleyin", "geceye", "gecesi", "gecesinde", "geceki"]
    static let daypartDativeForms: Set<String> = ["sabaha", "aksama", "geceye", "oglene", "ogleye", "aksamustune",
                                                  "bitimine", "sonuna", "basina", "sonraya"]
    /// G7: approximate-time words after a clock ("4 gibi", "10 civarında").
    static let approximateWords: Set<String> = ["gibi", "civari", "civarinda", "sularinda", "sulari",
                                                "raddelerinde", "raddesinde", "dolaylarinda", "civarlarinda"]

    // MARK: Persons (02 §7.9)
    static let honorifics: [(key: String, canonical: String, strong: Bool)] = [
        ("bey", "Bey", true), ("hanim", "Hanım", true), ("usta", "Usta", false), ("hoca", "Hoca", false),
        ("abi", "Abi", false), ("agabey", "Ağabey", false), ("abla", "Abla", false), ("sef", "Şef", false),
        ("mudur", "Müdür", false)
    ]
    static let honorificSuffixes: Set<String> = Set(joined([caseSuffixes, ["yle", "yla", "ne", "na", "nin", "nun"]]))
    static let personP6Suffixes: [String] = ["yle", "yla", "den", "dan", "ten", "tan", "nin", "nun", "in", "un",
                                             "yi", "yu", "ye", "ya", "le", "la", "i", "u", "e", "a"]

    // MARK: Title (02 §11)
    static let s1NounExceptions: Set<String> = ["malzeme", "firma", "sema", "tema", "forma", "klima", "prizma",
                                                "karma", "kama", "yama", "plazma", "sigma", "lama", "dama",
                                                "panorama", "diyagrama", "program", "sistema", "reklama",
                                                "problema", "drama", "gramma", "derme", "erme", "kume", "mama"]
    /// S2 exception list (lowercase, unfolded).
    static let s2Exceptions: Set<String> = ["fırın", "altın", "kalın", "kadın", "düğün", "beyin", "ekin", "akın",
                                            "yakın", "burun"]

    /// Concatenation helper (keeps long `+` chains away from the type checker).
    static func joined(_ groups: [[String]]) -> [String] {
        var result: [String] = []
        for group in groups {
            result.append(contentsOf: group)
        }
        return result
    }

    /// Every word the lexicon gives a meaning to (a person name is never one of these).
    static let lexiconWords: Set<String> = {
        var words = Set<String>()
        for entry in Lexicon.weekdays {
            words.insert(entry.key)
        }
        for entry in Lexicon.months {
            words.insert(entry.key)
        }
        let singles: [Set<String>] = [Lexicon.fillers, Lexicon.connectors, Lexicon.pronouns, Lexicon.taskModality,
                                      Lexicon.waitingBekle, Lexicon.imperatives, Lexicon.askVerbs,
                                      Lexicon.queryObjectWords, Lexicon.commandObjectWords]
        for group in singles {
            words.formUnion(group)
        }
        let phraseGroups: [[[String]]] = [Lexicon.reminderPhrases, Lexicon.noteStrongPhrases, Lexicon.taskPhrases,
                                          Lexicon.noteWeakPhrases, Lexicon.waitingFuture, Lexicon.waitingFollow,
                                          Lexicon.queryPhrases, Lexicon.cancelPhrases, Lexicon.snoozePhrases,
                                          Lexicon.completePlain, Lexicon.completeFinal]
        for group in phraseGroups {
            for phrase in group {
                for word in phrase {
                    words.insert(word)
                }
            }
        }
        for phrase in Lexicon.priorityPhrases {
            for word in phrase.words {
                words.insert(word)
            }
        }
        let extra: [String] = ["bugun", "yarin", "dun", "hafta", "haftaya", "gun", "gunu", "saat", "sabah", "aksam",
                               "gece", "ogle", "oglen", "mesai", "her", "gelecek", "onumuzdeki", "gecen", "ay", "yil",
                               "sene", "bey", "hanim", "allah", "dakika", "bucuk", "ceyrek", "yarim"]
        for word in extra {
            words.insert(word)
        }
        return words
    }()
}
