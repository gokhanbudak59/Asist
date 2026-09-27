# 02 — Turkish Natural-Language Understanding Engine (AsistCore Parser) — Specification

Status: design baseline v1 · Date: 2026-09-27 · Owner: AsistCore
Companion test corpus: `docs/design/parser_corpus.json` (see §15).

This is the most correctness-critical component of Asist. A wrong date silently destroys the user's trust
("it said Tuesday, it fired Wednesday"). Every rule below is deterministic and testable; where Turkish is
genuinely ambiguous the spec picks ONE answer, documents it, and lowers the confidence so the UI asks.

---

## 0. Scope, goals, non-goals

**Input:** one utterance, a `String` as produced by Apple Turkish dictation (`SFSpeechRecognizer(locale: tr-TR)`)
or typed by the user. Typical dictation traits the parser MUST tolerate:

| Trait | Examples |
|---|---|
| First letter capitalised, optional trailing period | `Yarın 3'te Ahmet'i ara.` |
| Numbers as digits with apostrophe suffix | `3'te`, `15'te`, `saat 15'te`, `9'da`, `ayın 15'inde` |
| Clock with colon or dot, with or without suffix | `15:30`, `15:30'da`, `15.30`, `15.30'da`, `15.00'te` |
| Numbers as words | `üçte`, `on beşte`, `üç buçukta`, `üçü çeyrek geçe`, `dörde çeyrek var` |
| Missing / odd apostrophes | `3te`, `3 te`, `Ahmeti`, `Ahmet’i` (U+2019), `Ahmet´i`, `salı'ya` |
| No punctuation, run-on sentences, fillers | `şey yarın ya Ahmet'i ara bir de teklifi gönder` |
| Odd casing | `YARIN`, `İstanbul`, `ISTANBUL`, `Salı Günü` |
| Typed input without Turkish letters | `carsamba`, `persembe`, `hatirlat` |

**Output:** a `ParseResult` (§1) describing either an item to create (reminder / task / note / waiting-for)
or a command (query agenda / complete / cancel / snooze), with a resolved `dueDate`, recurrence, priority,
person, project, place trigger, a clean Turkish title, a confidence in `0...1`, flags explaining every
ambiguity, and a Turkish "understood" confirmation string.

**Hard constraints**

1. Pure Swift + Foundation only. No `NaturalLanguage`, no `NSLinguisticTagger`, no `DateFormatter` for
   Turkish names, no `NSDataDetector` (not available / not identical on Linux). Must compile and pass the
   same tests on Linux (swift-corelibs-foundation) and iOS 17+.
2. Deterministic: `parse(text, now)` depends only on `text`, `now`, `ParserSettings`, and the injected `Calendar`.
   Never read `Date()`, `Locale.current`, or `TimeZone.current` inside the parser.
3. Swift language mode 5, no Swift 6 strict-concurrency requirements (value types only, no global mutable state;
   lexicon tables are `static let` constants).
4. Hand-written scanners on `[Character]`/token arrays. `NSRegularExpression` is allowed only where noted
   (it exists on Linux) but is not needed; prefer explicit character scanning — it is faster, portable and
   debuggable.
5. Performance: < 5 ms per utterance on iPhone 14 Pro Max; < 50 ms on CI Linux. No allocations in hot loops
   beyond the token array.

**Non-goals (v1):** multi-item splitting (one utterance → one item; multiple detected → flag + low confidence),
holiday calendars (bayram, kandil), relative references to other items ("toplantıdan sonra"), past-event
logging, English input.

---

## 1. Public API (exact Swift types — `AsistCore/Sources/AsistCore/Parser/ParserTypes.swift`)

```swift
import Foundation

public enum ItemKind: String, Codable, CaseIterable {
    case reminder, task, note, waiting
}

public enum ParsedKind: String, Codable, CaseIterable {
    case reminder, task, note, waiting, command
}

public enum Priority: Int, Codable, CaseIterable, Comparable {
    case low = 0, normal = 1, high = 2, critical = 3
    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    /// JSON/corpus spelling
    public var code: String {
        switch self { case .low: return "low"; case .normal: return "normal"; case .high: return "high"; case .critical: return "critical" }
    }
}

public enum PlaceTrigger: String, Codable {
    case onArrive, onLeave
}

public struct PlaceRef: Equatable, Codable {
    public var name: String            // canonical spelling from ParserSettings.knownPlaces
    public var trigger: PlaceTrigger
    public init(name: String, trigger: PlaceTrigger) { self.name = name; self.trigger = trigger }
}

public struct Recurrence: Equatable, Codable {
    public enum Frequency: String, Codable { case daily, weekly, monthly, yearly }
    public var frequency: Frequency
    public var interval: Int           // >= 1 ("iki haftada bir" -> weekly, 2)
    public var weekdays: [Int]?        // weekly only; ISO 1 = Pazartesi ... 7 = Pazar; sorted, unique, non-empty
    public var monthDay: Int?          // monthly/yearly; 1...31, or -1 = "ayın son günü"
    public var month: Int?             // yearly only; 1...12
    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil, monthDay: Int? = nil, month: Int? = nil) {
        self.frequency = frequency; self.interval = interval; self.weekdays = weekdays
        self.monthDay = monthDay; self.month = month
    }
}

public enum CommandType: String, Codable {
    case query, complete, cancel, snooze
}

public enum QueryScope: String, Codable {
    case today, tomorrow, thisWeek, nextWeek, date, overdue, waiting, notes, tasks, all
}

public struct ParsedCommand: Equatable {
    public var type: CommandType
    public var scope: QueryScope?      // .query only
    public var date: Date?             // query .date scope: start of that day; complete/cancel: optional day filter
                                       // (start of day); snooze: the NEW due date (absolute)
    public var queryText: String?      // complete/cancel/snooze target, normalised per §10.6; nil = "the last
                                       // fired / currently shown item"
    public var snoozeMinutes: Int?     // snooze by duration ("10 dakika ertele"); date is also filled (= now + minutes)
    public var project: String?        // filter / target hint (canonical known project)
    public var person: String?         // filter / target hint ("Ahmet")
    public init(type: CommandType, scope: QueryScope? = nil, date: Date? = nil, queryText: String? = nil,
                snoozeMinutes: Int? = nil, project: String? = nil, person: String? = nil) {
        self.type = type; self.scope = scope; self.date = date; self.queryText = queryText
        self.snoozeMinutes = snoozeMinutes; self.project = project; self.person = person
    }
}

public struct ParsedItem: Equatable {
    public var kind: ItemKind
    public var title: String           // never empty (§11.6)
    public var body: String?           // notes: full cleaned text; others: nil
    public var dueDate: Date?          // absolute instant, seconds = 0
    public var hasTime: Bool           // false when the time part is a default (09:00 / "today" policy)
    public var recurrence: Recurrence?
    public var priority: Priority
    public var person: String?         // "Ahmet", "Ahmet Bey", "Ayşe Hanım", "Ahmet Yılmaz"
    public var project: String?        // canonical spelling from knownProjects
    public var place: PlaceRef?
    public var tags: [String]          // e.g. ["fikir"]; free for app use
}

public enum ParseFlag: String, Codable, Hashable, CaseIterable {
    case ambiguousHourPM            // 1–6 without qualifier interpreted as 13–18
    case ambiguousHourNearest       // 7–11 without day/qualifier, nearest future chosen
    case ambiguousDotted            // "15.10" read as date (or time) by heuristic
    case rolledToTomorrow           // time without day already passed today -> tomorrow
    case rolledToNextYear           // day+month already passed this year -> next year
    case defaultTimeApplied         // day without time -> settings.defaultDayTime (or today policy)
    case pastDue                    // explicit date/time in the past (e.g. "bugün 3'te" at 19:40, "dün")
    case conflictingDates           // two incompatible day expressions ("yarın salı" on a Sunday)
    case invalidDateTime            // "saat 25", "ayın 32'si", "31 şubat"
    case needsTime                  // reminder cue but no date/time and no place
    case unsupportedRecurrence      // "her saat", "her dakika"
    case multipleItems              // two action verbs / "ve ayrıca" — only the first item is represented
    case unknownPlace               // "markete gidince" with no matching known place
    case uncertainPerson            // person inferred without apostrophe / honorific / contact list
    case negation                   // "bana hatırlatma", "unutabilirim değil" ...
    case titleFallback              // title fell back to original text
    case vagueDate                  // "gelecek hafta", "ekimde", "ertesi gün"
    case noKindCue                  // no explicit cue; kind decided by weak rule
    case tooShort                   // < 2 content tokens
    case tooLong                    // > 40 tokens
    case unusedNumber               // a bare number stayed in the title ("3 teklif hazırla" — missing "saat"?)
    case smartModeSuggested         // confidence < settings.smartModeThreshold
}

public struct ParseResult: Equatable {
    public var kind: ParsedKind
    public var item: ParsedItem?          // nil iff kind == .command
    public var command: ParsedCommand?    // non-nil iff kind == .command
    public var confidence: Double         // 0...1, rounded to 2 decimals
    public var flags: Set<ParseFlag>
    public var understood: String         // e.g. "Salı 29 Eylül, 15:00 — Teklif konusu"
    public var relativePhrase: String?    // e.g. "(2 gün sonra)"; nil when no dueDate
    public var originalText: String
    public var normalizedText: String     // after §3 (useful for logs / Smart Mode prompt)
}

public struct ClockTime: Equatable, Codable {
    public var hour: Int, minute: Int
    public init(_ hour: Int, _ minute: Int) { self.hour = hour; self.minute = minute }
}

public struct ParserSettings: Equatable {
    public var defaultDayTime = ClockTime(9, 0)      // day given, no time
    public var sabah = ClockTime(9, 0)
    public var ogle = ClockTime(12, 0)               // öğle / öğlen / öğle arası
    public var ogledenSonra = ClockTime(14, 0)
    public var aksamustu = ClockTime(17, 0)
    public var aksam = ClockTime(19, 0)
    public var gece = ClockTime(22, 0)
    public var mesaiBasi = ClockTime(8, 30)
    public var mesaiBitimi = ClockTime(17, 30)       // mesai bitimi / mesai sonu / iş çıkışı
    public var birazdanMinutes = 15
    public var belirsizSaatlerOgledenSonra = true    // 1–6 without qualifier -> 13–18
    public var knownProjects: [String] = []          // e.g. ["Arka Cep", "Hat 3", "Kaynak Robotu", "Bakım"]
    public var knownPlaces: [String] = []            // e.g. ["Fabrika", "Ev", "Ofis"]
    public var knownPeople: [String] = []            // optional contact names ("Ahmet", "Ayşe Hanım")
    public var smartModeThreshold = 0.60             // below: suggest Akıllı Mod / manual edit
    public var autoSaveThreshold = 0.80              // at/above: save directly with Undo toast
    public init() {}
}

public struct TurkishParser {
    public let settings: ParserSettings
    public let calendar: Calendar
    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = TurkishParser.defaultCalendar()) {
        self.settings = settings; self.calendar = calendar
    }
    public func parse(_ text: String, now: Date) -> ParseResult { /* §2 pipeline */ fatalError("spec") }

    public static func defaultCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        // Turkey is fixed UTC+3 since 2016 (no DST). The fallback keeps Linux CI working without tzdata.
        c.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? TimeZone(secondsFromGMT: 3 * 3600)!
        c.firstWeekday = 2                 // Monday-first weeks in Turkey
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "en_US_POSIX")   // never rely on tr_TR locale data
        return c
    }
}
```

Notes on the types

* `ParsedKind.command` exists only in `ParseResult.kind`; persisted items use `ItemKind`.
* ISO weekday conversion (never use `.weekOfYear`; compute weeks manually):
  `iso = ((calendar.component(.weekday, from: d) + 5) % 7) + 1` (Foundation `.weekday` is 1 = Sunday regardless of `firstWeekday`).
* Start of the Monday-first week of a date `d`: `startOfDay(d) - (iso(d) - 1) days` (via `calendar.date(byAdding: .day, ...)`).
* All produced `Date`s have `second == 0`. Minute-granularity relative offsets are applied to `now` truncated to the minute.
* `confidence` is rounded with `(x * 100).rounded() / 100`.
* The app decides UX from confidence: `>= autoSaveThreshold` → save + Undo toast; `smartModeThreshold ..< autoSaveThreshold`
  → confirmation sheet with editable chips; `< smartModeThreshold` → sheet opened in edit mode, and if Akıllı Mod
  is enabled the utterance is sent to the LLM (§14) first.

---

## 2. Pipeline overview

```
text
 └─ §3 normalize            (NFC, apostrophes, whitespace, Turkish lowercase, fold table)
     └─ §4 tokenize         (tokens with root/suffix/number split, original ranges)
         └─ §7 extract      (fixed order; each extractor CONSUMES token spans)
             1. prefix markers           ("not:", "görev:", "fikir:")
             2. known projects           (protect "Hat 3" before numbers are read)
             3. known places + trigger   ("fabrikaya varınca")
             4. recurrence               ("her pazartesi ve perşembe")
             5. relative offsets         ("10 dakika sonra", "3 gün sonra", "birazdan")
             6. dates                    (bugün/yarın/weekday/"15 ekim"/"ayın 15'i"/"ay sonu"...)
             7. times                    (clock, dayparts, buçuk/çeyrek, "3'te")
             8. priority                 ("acil", "sakın unutma")
             9. persons                  ("Ahmet'i", "Ahmet Bey'den", "Mehmet'le", "... ile")
            10. cue words                (reminder/task/note/waiting/command verbs, fillers)
         └─ §10 classify            (tiered, template-free)
         └─ §8/§9 resolve           (date/time/recurrence -> Date using now + Calendar)
         └─ §11 title / queryText   (remaining tokens, suffix repair, capitalisation)
         └─ §12 confidence          (kind certainty − penalties)
         └─ §13 understood + relative phrase
```

Every extractor marks the token indices it consumed (`consumed: [Bool]`) and records an `ExtractedSpan`
(`kind`, `tokenRange`, `value`) for debugging. Later extractors never re-read consumed tokens. The title is
built from the tokens nobody consumed (§11). This single rule is what makes titles clean.

Internal (non-public) types recommended:

```swift
struct Token {
    var original: String      // exact surface form from the normalised text (casing kept)
    var lower: String         // Turkish-lowercased
    var folded: String        // lower + diacritic fold (ç->c, ğ->g, ı->i, ö->o, ş->s, ü->u, â->a, î->i, û->u)
    var root: String          // folded part before the apostrophe (or whole token)
    var suffix: String        // folded part after the apostrophe ("" if none)
    var hadApostrophe: Bool
    var number: NumberValue?  // digits / clock / date-like numeric (§6)
    var isCapitalized: Bool   // first Character is uppercase in `original`
    var trailingPunct: Character?  // separator that followed the token (":" "," ";" "!" "?"), used by §7.1 and §11.3
    var index: Int
}
enum NumberValue { case integer(Int), clock(Int, Int), dotted(Int, Int), slashDate(Int, Int, Int?), dottedDate(Int, Int, Int) }
```

---

## 3. Normalization (`Normalizer.swift`)

Applied in this exact order; the output is `normalizedText` and the input of tokenization.

1. **Unicode NFC:** `text.precomposedStringWithCanonicalMapping` (available on Linux). Dictation may emit
   `i` + U+0307; NFC folds it.
2. **Apostrophe unification:** replace `’ ‘ ´ ` ʼ ′ ＇` (U+2019, U+2018, U+00B4, U+0060, U+02BC, U+2032, U+FF07) with ASCII `'`.
3. **Whitespace:** replace tabs/newlines/NBSP (U+00A0, U+202F) with a space; collapse runs; trim.
4. **Detached suffix join:** `3 'te` → `3'te` (space before an apostrophe is removed). A standalone suffix token
   directly after a number (`3 te`, `15 de`, `9 da`, `15:30 da`, `10 a`) is joined as `3'te` — set = {`te ta de da e a ye ya i ı u ü yi yı yu yü inde ında unda ünde nde nda`}.
   Exception: `de`/`da` after a number is joined only if the number is ≤ 24 or looks like a clock
   (`yarın 2 de gelsin` → still joined; this is the documented cost, see §16).
5. **Trailing punctuation:** strip final `. ! ? …` and trailing commas. Internal `, ; ! ?` become token
   separators (§4). A `.` is a separator only when it is NOT between two digits.
6. **Keep original casing** in `normalizedText`; lowercase forms are stored per token.

### 3.1 Turkish lowercase (deterministic, locale-free)

```swift
static func trLower(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "I": out.append("ı")
        case "İ": out.append("i")
        default: out.append(contentsOf: String(ch).lowercased())   // non-locale lowercased()
        }
    }
    return out
}
static func trUpperFirst(_ s: String) -> String   // "i"->"İ", "ı"->"I", else uppercased()
```

Do NOT call `lowercased(with: Locale(identifier: "tr_TR"))` as the primary path: Linux ICU data availability
differs. (It may be used in a debug assertion on Apple platforms only.) Dictation sometimes writes `ISTANBUL` or `IZMIR`
with dotless capitals meaning `i`; this is irrelevant for matching because all lexicon lookups use the
**folded** form (3.2), where `ı` and `i` both become `i`.

### 3.2 Fold table (diacritic-insensitive keys)

| from | ç | ğ | ı | ö | ş | ü | â | î | û | i̇ (i+U+0307) |
|---|---|---|---|---|---|---|---|---|---|---|
| to   | c | g | i | o | s | u | a | i | u | i |

`folded = fold(trLower(original))`. **All lexicon tables are stored and matched in folded form.** Titles are
always taken from `original` (never from folded text), so diacritics survive into the UI.

Folding creates a few collisions that matter; they are resolved by token context, not by the fold:
`ogle` (öğle) vs nothing; `sali` (salı) vs nothing; `on` (ten) vs `ön` (front) — `ön` is not in any lexicon,
so a folded `on` token is only treated as a number when it participates in a number phrase (§6).

---

## 4. Tokenization (`Tokenizer.swift`)

1. Split on spaces and on separators `, ; ! ? ( ) " «»`, on `.` and `:` when NOT between two digits (`15:30`, `15.30`
   stay one token; `Not:` → token `Not` with `trailingPunct = ":"`). `/` is kept inside tokens. `-` is kept inside tokens only between letters (`e-posta`); otherwise a separator.
2. For each token compute `original`, `lower`, `folded`.
3. **Apostrophe split:** if the token contains `'`, `root` = folded text before the first `'`, `suffix` = folded
   text after it, `hadApostrophe = true`. `PLC'yi` → root `plc`, suffix `yi`.
4. **Digit–letter split (no apostrophe):** `3te`, `15te`, `15:30da`, `9a`, `15inde` → treated exactly as if
   written `3'te`, `15'te`, `15:30'da`, `9'a`, `15'inde` (root = numeric part, suffix = letters,
   `hadApostrophe = false`).
5. **Numeric shapes** (on `root`):
   * `^\d{1,2}:\d{2}$` → `.clock(h, m)` (always a time; `24:00` → `.clock(0,0)` + next day).
   * `^\d{1,2}\.\d{2}$` → `.dotted(a, b)` (time or date, decided in §8.6).
   * `^\d{1,2}\.\d{1,2}\.\d{2,4}$` → `.dottedDate(d, m, y)` (2-digit year → 2000+y).
   * `^\d{1,2}/\d{1,2}(/\d{2,4})?$` → `.slashDate(d, m, y?)` (always a date, day first).
   * `^\d+$` → `.integer(n)`.
   * `^\d+[.,]5$` in a duration context (`1,5 saat`, `1.5 saat`) → 1 h 30 min.
6. **Capitalisation** (`isCapitalized`) uses `original.first!.isUppercase`. Token 0 is always capitalised by
   dictation, so person rules treat index 0 specially (§7.9).

---

## 5. Lexicons (`Lexicon.swift`, all keys in folded form)

Longest match wins everywhere (multi-token phrases before single tokens; `pazartesi` before `pazar`,
`cumartesi` before `cuma`). A lexicon entry matches a token when `root` equals the key and the `suffix`
(apostrophe or not) belongs to the entry's allowed suffix class; for tokens without apostrophe the scanner
tries `key + allowedSuffix` for every allowed suffix.

### 5.1 Suffix classes (folded)

| class | members (folded) | examples |
|---|---|---|
| `LOC` locative | `de da te ta nde nda` | salıda, 3'te, ekimde |
| `DAT` dative | `e a ye ya ne na` | salıya, cumaya, 3'e, dörde (see softening) |
| `ACC` accusative | `i u yi yu ni nu` (ı→i, ü→u after folding) | 3'ü, salıyı |
| `ABL` ablative | `den dan ten tan nden ndan` | salıdan, Ahmet'ten |
| `GEN` genitive | `in un nin nun` | Ahmet'in, salının |
| `INS` instrumental | `le la yle yla` | Ahmet'le, Mehmet'la(typo) |
| `POSS3` 3rd-person possessive | `i u si su` | 15'i, 3'ü, 20'si |
| `POSS3LOC` | `inde unda sinde sunda nde nda` | 15'inde, birinde, 20'sinde, 30'unda |
| `PLURAL-DAYS` | `leri lari` (+ `LOC`/nothing) | salıları, cumaları, pazartesileri |
| `KI` | `ki` (after LOC: `yarınki`, `salıki`?, `cumaki`) | yarınki toplantı |

Consonant softening handled by explicit alternate keys: `dort→dord` (`dörde`, `dördü`), `aralik→aralig` (`aralığa`),
`ocak→ocag`, `buçuk→bucug` (`buçuğa`), `yarim` has none.

### 5.2 Weekdays (ISO numbers)

| ISO | canonical | folded keys |
|---|---|---|
| 1 | Pazartesi | `pazartesi`, `pztesi`, `pzt` |
| 2 | Salı | `sali` |
| 3 | Çarşamba | `carsamba`, `carsambe`(dictation typo) |
| 4 | Perşembe | `persembe`, `persenbe` |
| 5 | Cuma | `cuma` |
| 6 | Cumartesi | `cumartesi`, `cmt` |
| 7 | Pazar | `pazar` |

Allowed suffixes: none, `LOC`, `DAT`, `ABL`, `ACC`, `GEN`, `KI` (after LOC), `PLURAL-DAYS` (→ recurrence §9),
`gunu` / `gunleri` as the next token (`salı günü`, `salı günleri`). `pazar` has a second meaning (market):
it is a weekday only if (a) followed by `günü`, (b) preceded by a qualifier (`bu`, `gelecek`, `önümüzdeki`,
`haftaya`, `her`), (c) IMMEDIATELY followed by a time/daypart phrase (`pazar 10'da`, `pazar sabah`, `pazar akşamı`), or (d) in suffix forms `pazara`/`pazardan` **not**
followed by a place-trigger verb (§7.3). Otherwise it stays in the title and flags nothing.

### 5.3 Months

| # | canonical | folded keys (+ softened) |
|---|---|---|
| 1 | Ocak | `ocak`, `ocag` |
| 2 | Şubat | `subat` |
| 3 | Mart | `mart` |
| 4 | Nisan | `nisan` |
| 5 | Mayıs | `mayis` |
| 6 | Haziran | `haziran` |
| 7 | Temmuz | `temmuz` |
| 8 | Ağustos | `agustos` |
| 9 | Eylül | `eylul` |
| 10 | Ekim | `ekim` |
| 11 | Kasım | `kasim` |
| 12 | Aralık | `aralik`, `aralig` |

A month word is a date component only when: preceded by a day number (digits or number words, optional ordinal
suffix), OR followed by `basi/basinda/ortasi/ortasinda/sonu/sonunda/ayi/ayinda/ayinin`, OR carries a `LOC`/`DAT`
suffix itself (`ekimde`, `kasıma`) → month-only date (`vagueDate`, day = 1). Bare `ocak`, `ekim`, `aralık`,
`nisan` without these contexts are ordinary words (stove, sowing, gap, engagement).

### 5.4 Day words

| key(s) | meaning |
|---|---|
| `bugun`, `bu gun` | today |
| `yarin` | +1 day (suffixes: `yarina`, `yarinki`, `yarindan` — but `yarindan sonra` = +2) |
| `obur gun`, `obur gune`, `oburgun`, `yarindan sonra` | +2 days |
| `ertesi gun` | +1 day, `vagueDate` |
| `haftaya bugun` | +7 days |
| `dun`, `evvelsi gun` | −1 / −2 days → `pastDue` |
| `hafta sonu`, `hafta sonunda`, `haftasonu` | next Saturday (§8.3) |
| `hafta basi`, `hafta basinda`, `haftaya basinda`, `haftanin basinda` | next Monday strictly after today |
| `hafta ortasi`, `hafta ortasinda` | next Wednesday strictly after today, `vagueDate` |
| `ay sonu`, `ay sonunda`, `ayin sonunda`, `ayin son gunu` | last day of current month |
| `ay basi`, `ay basinda`, `ayin basinda`, `gelecek ay basi` | 1st of next month |
| `ay ortasi`, `ayin ortasinda` | 15th (this month if not passed, else next) |
| `yil sonu`, `sene sonu` | 31 Dec this year |
| `yilbasi`, `yilbasinda` | 1 Jan next year |
| `gelecek hafta`, `onumuzdeki hafta`, `haftaya` (alone) | +7 days, `vagueDate` only for `gelecek/önümüzdeki hafta` |
| `gelecek ay`, `onumuzdeki ay`, `seneye`, `gelecek yil` | +1 month / +1 year, `vagueDate` |

Weekday qualifiers (token before weekday): `bu` → THIS, `gelecek`/`onumuzdeki`/`ilk`(+weekday) → NEXT,
`haftaya`/`gelecek hafta`/`onumuzdeki hafta` → NEXTWEEK, `her` → recurrence, `gecen` → past (`pastDue`).

### 5.5 Dayparts (resolve to settings)

| folded keys | ClockTime | hour-qualifier behaviour (§8.5) |
|---|---|---|
| `sabah`, `sabahleyin`, `sabaha`, `sabahtan`, `bu sabah` | `sabah` | AM |
| `ogle`, `oglen`, `ogleyin`, `ogle arasi`, `ogle arasinda`, `oglene`, `ogleye`, `ogle yemeginde` | `ogle` | NOON |
| `ogleden sonra`, `ogleden sonraya` | `ogledenSonra` | PM |
| `aksamustu`, `aksam ustu`, `aksamustune` | `aksamustu` | PM |
| `aksam`, `aksama`, `aksamleyin`, `aksamki`, `bu aksam` | `aksam` | PM |
| `gece`, `geceleyin`, `geceye`, `bu gece` | `gece` | NIGHT |
| `gece yarisi`, `gece yarisinda`, `geceyarisi` | 00:00 of the next day | — |
| `bu sabah`, `bu ogle(n)`, `bu aksam`, `bu gece`, `bu aksamustu` | the daypart AND D = today (explicit) | past → `pastDue`, never rolled |
| `mesai basi`, `mesai basinda`, `mesaiye baslarken`, `ise gelince`* | `mesaiBasi` | — |
| `mesai bitimi`, `mesai bitiminde`, `mesai sonu`, `mesai sonunda`, `is cikisi`, `is cikisinda`, `isten cikarken`, `isten cikinca`, `isten cikmadan once` | `mesaiBitimi` | — |

\* `ise gelince` is a time (not a place) because "İş" is not a known place by default; if the user adds a
place named "İş", place matching (§7.3) runs first and wins.

### 5.6 Fillers (always consumed, never in titles)

`ya, yaa, şey, sey, hani, işte, yani, acaba, bakalım, eee, ee, hmm, ıı, lütfen, lutfen, rica etsem, bana,
beni, bize, benim için, bi, bir de (as two tokens), birde (only when not a time §6.3), ayrıca (flags
multipleItems if followed by a second verb), tamam mı, olur mu, olsun, de mi, hemen (if not "hemen şimdi"), şimdi (alone)`.

`bana` and `beni` are consumed because they are the indirect object of the reminder verb
("bana hatırlat", "beni uyar"). `Ahmet'e` is NOT a filler (person, §7.9).

### 5.7 Connector words (trimmed at title edges only, §11.3)

`ve, ile, ilen, için, diye, de, da, ki, ama, fakat, ancak, olarak, hakkında, konusunda(only at edges), gibi, kadar, en geç`.

---

## 6. Numbers (`TurkishNumbers.swift`)

### 6.1 Cardinal words (folded stems → value)

| units | | tens | |
|---|---|---|---|
| `bir` 1 | `alti` 6 | `on` 10 | `altmis` 60 |
| `iki` 2 | `yedi` 7 | `yirmi` 20 | `yetmis` 70 |
| `uc` 3 | `sekiz` 8 | `otuz` 30 | `seksen` 80 |
| `dort` / `dord` 4 | `dokuz` 9 | `kirk` 40 | `doksan` 90 |
| `bes` 5 | | `elli` 50 | `yuz` 100 |

Composition: `[tens] [unit]` in one or two tokens (`on beş`, `onbeş`, `yirmi üç`, `yirmiüç`) → sum; `yüz` alone = 100
(`yüz yirmi` = 120; values > 199 are not needed and are rejected). The **suffix attaches to the last word**
(`on beşte` = 15 + LOC, `yirmi birinde` = 21 + POSS3LOC). The scanner consumes at most two word-tokens (plus
`yüz`), and checks the last one against `stem + suffix`:

* allowed after number words: none, `LOC` (`üçte`, `beşte`, `dörtte`, `altıda`, `onda`, `on ikide`),
  `DAT` (`üçe`, `dörde`, `beşe`, `altıya`, `ona`*), `ACC` (`üçü`, `dördü`, `beşi`, `altıyı`, `onu`*),
  `POSS3`/`POSS3LOC` (`birinde`, `ikisinde`, `on beşinde`, `yirmisinde`, `otuzunda`), ordinal
  `inci/nci/uncu/ncu` (`birinci`, `ikinci`, `üçüncü`, `dördüncü`, `onuncu`).
* \* `ona` ("to him") and `onu` ("him") are numbers ONLY inside a clock phrase (`saat ona`, `ona çeyrek var`,
  `onu çeyrek geçe`, `saat onu on geçe`) or before a unit word (`on dakika`, `on gün`). Same for `bir`
  (article "a"): `bir` is the number 1 only when followed by a unit (`bir saat sonra`, `bir hafta`), in a clock
  phrase (`saat birde`, `saat bir buçukta`), or as a day of month (`ayın biri/birinde`, `bir ekim`). The token pair
  `bir de` (two tokens) is always the filler "also".

### 6.2 Ordinals and day-of-month

* Digits: `15'i`, `15'inde`, `15'ine kadar`, `1'i`, `1'inde`, `2'si`, `20'sinde`, `30'u`, `30'unda`, `3'ü`,
  `3'ünde`, `15.` (dotted ordinal before a month: `15. ekim`), `15'inci`.
* Words: `birinde`, `biri`, `ikisinde`, `on beşinde`, `yirmi beşinde`, `otuzunda`, `otuz birinde`.
* `ilk` (+ `günü`/`gününde`) = 1; `son gün`/`son günü`/`son gününde` = −1 (last day).
* Validity: day-of-month 1...31; values outside → `invalidDateTime`, the expression is ignored for dating.

### 6.3 Clock phrases (hour H in 0...24, minute M)

Grammar (tokens, folded; `SAAT` = optional `saat`; `N` = digits or number words; suffix shown after `+`):

| pattern | value | examples |
|---|---|---|
| `SAAT N:MM(+LOC/DAT)` | H:MM | `15:30'da`, `saat 9:45'te`, `9:05e` |
| `SAAT N.MM(+LOC/DAT)` | H:MM (dotted rule §8.6) | `15.30'da`, `saat 15.00` |
| `SAAT N(+LOC/DAT)` | H:00 | `saat 3`, `3'te`, `saat 15'te`, `üçte`, `on beşte`, `3te` |
| `SAAT N N` (both numbers, 2nd 0...59, `saat` REQUIRED or 2nd ends in LOC) | H:MM | `saat on beş otuz`, `on beş otuzda`, `saat 15 30'da`, `dokuz kırk beşte` |
| `SAAT N buçuk(+LOC/DAT)` / `N buçukta` | H:30 | `üç buçukta`, `3 buçukta`, `saat 3 buçuk`, `bir buçuğa` |
| `SAAT yarim(+LOC)` / `saat yarımda` | 12:30 (`yarım` alone as time needs `saat`) | `saat yarımda` |
| `N+ACC ceyrek gece` | H:15 | `üçü çeyrek geçe`, `3'ü çeyrek geçe`, `dokuzu çeyrek geçe` |
| `N+ACC M gece` | H:M | `üçü on geçe`, `beşi yirmi beş geçe`, `4'ü 10 geçe` |
| `N+DAT ceyrek var/kala` | (H−1):45 | `üçe çeyrek var`, `dörde çeyrek kala`, `3'e çeyrek kala` |
| `N+DAT M var/kala` | (H−1):(60−M) | `beşe on var` → 4:50 (→16:50 by §8.5), `ona yirmi kala` → 9:40 |
| `gece yarisi` | 00:00 next day | |
| `ogle(n) 12` / `ogle(n)` alone | 12:00 | |

* A bare integer WITHOUT `saat` and WITHOUT a LOC/DAT suffix is NOT a time (`3 teklif hazırla` → not a time;
  `saat 3 teklif` → time). Exception: `DAYPART N` (`sabah 9`, `akşam 8`, `gece 2`) is a time even without suffix.
* A number followed by a unit word (`dakika, dk, dak, saat, gün, hafta, ay, yıl, sene`) is a duration, not a
  clock (`3 saat sonra`). `saat` directly FOLLOWING a number means duration; `saat` PRECEDING means clock.
* Minute must be 0...59, hour 0...24 (24 → 00:00 next day); otherwise `invalidDateTime` and the phrase is left in the title.
* `civarı, civarında, gibi, sularında, suları, raddelerinde` after a clock phrase are consumed (no flag; time kept).
* Word-hour `bir`: `saat birde`, `birde` right after a day word or daypart (`yarın birde`, `öğlen birde`) = 1;
  otherwise `birde` is treated as the filler "bir de".

### 6.4 Durations (relative offsets)

`N UNIT (sonra|sonraya|içinde|içerisinde)` or `N UNIT+DAT` (`10 dakikaya`, `2 saate`) or `N UNIT+DAN sonra`.

| unit keys | granularity |
|---|---|
| `dakika, dakikaya, dk, dak, dakka`(dictation) | minute |
| `saat, saate, sa` (only in duration position) | minute (×60) |
| `gun, gune` | day |
| `hafta, haftaya` | day (×7) |
| `ay, aya` | month |
| `yil, yila, sene, seneye` | year |

Amount forms: digits, number words, `yarım` (0.5; `yarım saat` = 30 min, `yarım gün` = rejected), `çeyrek saat` (15 min),
`N buçuk UNIT` (N + 0.5 → `bir buçuk saat` = 90 min, `iki buçuk saat` = 150 min), `1,5 saat` / `1.5 saat`,
compound `1 saat 20 dakika sonra`, `bir saat yirmi dakika sonra`. Plural-free: Turkish never pluralises after numbers.

Special: `birazdan`, `az sonra`, `biraz sonra`, `kısa süre sonra` → + `birazdanMinutes`;
`hemen`/`şimdi` alone → not a duration (filler); `bir saat içinde` = +60 min.

---

## 7. Entity extraction (fixed order; each step consumes tokens)

### 7.1 Prefix markers (only at token 0, with or without `:`)

| prefix (folded) | effect |
|---|---|
| `not`, `not:`, `nota`, `not al:` | kind = note (tier T0), rest is verbatim content |
| `fikir`, `fikir:` | kind = note, tag `fikir` |
| `gorev`, `gorev:`, `yapilacak`, `yapilacak:`, `is:` | kind = task (T0), rest parsed normally |
| `bekliyorum:` | kind = waiting (T0) |

A prefix counts only if token 0 is followed by `:` or `,` (`Not: …`, `Görev, …`). Exception: `not` and `fikir`
also count without punctuation when the utterance has ≥ 3 tokens and token 1 is not one of `al, et, tut, düş, defteri,
defterimi, defterini, almayı` (`not almayı unutma`, `not defterimi al` are NOT prefixes). `görev`, `yapılacak`, `iş`,
`bekliyorum` ALWAYS need the punctuation (`iş güvenliği eğitimi…` is not a task prefix).

### 7.2 Known projects (runs BEFORE any number/date extraction)

* Match every `settings.knownProjects` name as a token sequence on folded roots, case/diacritic-insensitive,
  longest name first. Multi-word names must match contiguous tokens (`arka cep`, `hat 3`, `kaynak robotu`).
* The **last** token of the match may carry a suffix: with apostrophe always (`Hat 3'te`, `Arka Cep'in`); without
  apostrophe only for multi-word names or names containing a digit (`Arka Cepte`, `Kaynak Robotunun`).
  **Single-word dictionary-like names** (e.g. `Bakım`) match only the bare token, the apostrophe form, or when
  followed by `projesi/projesine/projesinde/projesinin/projesiyle` (`bakım` ✔, `Bakım'a` ✔, `bakımı` ✘, `bakımını` ✘).
* `Hat 3'te` — the `'te` belongs to the project (locative "at Line 3"); it is NOT a time. This is why
  projects run first.
* Also accepted as explicit markers (consumed, removed from title): `X projesine ekle`, `X projesi için`,
  `proje X`, `X projesinde` → project = X, and the words `projesine/projesi için/ekle` are consumed.
  The project name itself stays in the title when it appears in natural text (`Hat 3 PLC yedeğini almak`)
  and is removed only when introduced by these explicit markers.
* Several different projects matched → choose the longest name (tie: earliest); others stay as plain text.
* Output: canonical spelling from settings.

### 7.3 Known places + trigger (location reminders)

Pattern: `PLACE(+DAT|+LOC) TRIGGER_ARRIVE` or `PLACE(+ABL) TRIGGER_LEAVE`.

| trigger | folded verb forms |
|---|---|
| onArrive | `varinca, vardigimda, varir varmaz, gidince, gittigimde, gelince, geldigimde, girince, girdigimde, ulasinca, ulastigimda` |
| onLeave | `cikinca, ciktigimda, cikarken, ayrilinca, ayrildigimda, ayrilirken, cikmadan once`* |

\* `çıkmadan önce` is approximated by onLeave (documented limitation).

PLACE is matched against `knownPlaces` (folded, suffix-tolerant: `fabrikaya`, `fabrikada`, `fabrikadan`,
`eve`, `evde`, `evden`, `ofise`, `ofisten`, `Fabrika'ya`). Buffer letters: after a vowel-final name the DAT
suffix is `ya/ye`, after consonant `a/e`; accept all forms regardless of harmony (dictation errors).

* Match → `place = PlaceRef(name: canonical, trigger)`, place+trigger tokens consumed, `dueDate = nil`
  unless an explicit date/time is also present (then both are kept; the app treats it as "whichever comes first").
* PLACE not in knownPlaces but a trigger verb is present with a DAT/ABL noun before it (`markete gidince`) →
  `place = nil`, flag `unknownPlace`, tokens stay in the title (`Markete gidince süt al`).
* `işe gelince` / `işten çıkınca` → dayparts (§5.5), unless "İş" is a known place.

### 7.4 Recurrence → §9. 7.5 Relative offsets → §6.4 / §8.2. 7.6 Dates → §8.3–8.4. 7.7 Times → §6.3 / §8.5.

### 7.8 Priority (`Priority`)

| priority | phrases (folded) | removal from title |
|---|---|---|
| critical | `cok acil, acil, acilen, kritik, hayati, cok onemli, sakin unutma, sakin ha unutma, asla unutma, kesinlikle unutma` | always removed |
| high | `onemli, mutlaka, kesinlikle, oncelikli, yuksek oncelikli, ilk is (+ olarak / olsun), unutmamam lazim`* | adverbs (`mutlaka, kesinlikle, ilk iş`) always; adjectives (`önemli, öncelikli`) only when first/last remaining token or followed by `:` |
| low | `onemli degil, acil degil, onemsiz, acelesi yok, acele yok, bos vaktimde, firsat bulursam, vakit olursa` | always removed |

\* `unutmamam lazım` is also a reminder cue (§10.3).

**Technical-term exceptions** (never priority, never removed): `acil stop, acil durdurma, acil duruş, acil durum, acil çıkış, acil servis, acil butonu, acil aydınlatma, acil toplanma, kritik yol, kritik parça, kritik stok`.
Highest level wins when several appear, except that the negated forms `önemli değil / acil değil` are matched first (longest match) and yield low. `sakın unutma` also acts as the reminder cue.

### 7.9 Persons

Candidates are evaluated left to right; the first accepted person wins (others remain text). A person is never
a token already consumed (project/place/day/month) and never an ALL-CAPS token of length ≥ 2 (`PLC'yi`, `SAP'ye`,
`ABB'den` are brands/acronyms → not persons). Weekday/month names, `Allah`, `Bey`, `Hanım` alone are excluded.

| rule | condition | person value | confidence effect |
|---|---|---|---|
| P1 contact list | folded root (suffix-tolerant) matches `knownPeople` | canonical contact | none |
| P2 apostrophe | capitalised token with apostrophe + suffix in `ACC DAT ABL GEN INS LOC` | root in original casing (`Ahmet'i` → `Ahmet`) | none |
| P3 honorific | token(s) followed by `Bey, Hanım, Hanim, Usta, Hoca, Abi, Ağabey, Abla, Şef, Müdür` (honorific may carry the suffix: `Bey'den`, `Hanım'a`, `Beye`). Strong honorifics `Bey/Hanım` accept a lowercase name (`ahmet beyi`); weak ones (`Usta, Hoca, Abi, Ağabey, Abla, Şef, Müdür`) require a capitalised name (`güvenlik müdürüyle` is NOT a person). The name token must not be a number word, filler or lexicon word | `Ahmet Bey`, `Ayşe Hanım`, `Kemal Usta` | none |
| P4 surname | two consecutive capitalised tokens, the second satisfying P2 (`Ahmet Yılmaz'ı`) | `Ahmet Yılmaz` | none |
| P5 `ile` | capitalised token followed by `ile/ilen` (`Mehmet ile görüş`) | `Mehmet` | none |
| P6 no apostrophe | (disabled when more than half of the tokens are capitalised — Title-Case dictation) capitalised token at index > 0, not in any lexicon, ending in a person suffix (`Ahmeti, Ahmete, Mehmetle, Ayşeden, Aliyi`) with remaining root ≥ 3 letters | root | flag `uncertainPerson` (−0.05) |
| P7 subject of waiting verb | capitalised token at index 0 or 1 followed later by a 3rd-person future waiting verb (§10.4) | token | none |

Suffix stripping for P6 tries the longest suffix first: `yle yla den dan ten tan nin nun in un yi yu ye ya le la i u e a`.
Index-0 tokens qualify only via P1–P5 and P7 (dictation capitalises the first word of every sentence).
Person tokens are NOT consumed: they stay in the title (`Ahmet'i aramak`), except for waiting-for (§11.4).
The person VALUE is normalised: suffix removed, each word first-letter upper-cased with `trUpperFirst`, honorific in
canonical spelling (`ahmet beyi` → `Ahmet Bey`, `AYŞE HANIM'A` is all-caps → not a person).

### 7.10 Cue words → §10.

---

## 8. Date / time resolution (`DateResolver.swift`)

Notation: `now` = reference instant truncated to the minute; `today` = `startOfDay(now)`; `iso(d)` = ISO weekday
(1 = Pzt … 7 = Paz); `weekStart(d)` = Monday 00:00 of `d`'s Monday-first week; `+N` = `calendar.date(byAdding: .day, value: N, to:)`.
All arithmetic uses the injected `Calendar`; never add raw seconds for day/month/year offsets.

### 8.1 Components collected by the extractors

* **D** — day expression (zero or more; §8.4 merges them).
* **T** — time expression: either a clock `(h, m, leadingZero, qualifier)` with `qualifier ∈ {none, AM, NOON, PM, EVENING, NIGHT}`,
  or a daypart default (§5.5).
* **O** — relative offset: minute-granularity (`10 dakika sonra`, `2 saat sonra`, `birazdan`) or calendar-granularity
  (`3 gün sonra`, `bir hafta sonra`, `bir ay sonra`, `seneye`).
* **R** — recurrence (§9).

### 8.2 Combination (first matching rule wins)

1. **R present** → first occurrence per §9.3 (T/D feed into it).
2. **O minute-granularity** → `due = now + O`, `hasTime = true`. If D or T is also present → flag `conflictingDates`, O wins.
3. **O calendar-granularity** → `date = today + O` (`.day`, `.month`, `.year` components); then time as in rule 4.
4. **D present** → `date = D`. Time: if T → §8.5 with `daySpecified = true`; else `defaultDayTime`,
   `hasTime = false`, flag `defaultTimeApplied`. If `date == today` and no T → **today policy** (8.2a).
   If the final instant is `< now` → flag `pastDue` (never silently moved when the user named the day).
5. **T only** → §8.5 with `daySpecified = false`; candidate today; if `candidate <= now` → `+1 day`, flag `rolledToTomorrow`
   (not raised for NIGHT 00:00–06:59, see §8.5).
6. Nothing → `dueDate = nil`, `hasTime = false`.

**8.2a Today policy** (a day-only expression that lands on today: `bugün`, `ay sonu` on the last day, `bu salı` on a Tuesday, `15 ekim` on 15 Oct):
if `today + defaultDayTime >= now + 15 min` → use `defaultDayTime`; else `t = now + 30 min` rounded **up** to the next
full hour (unchanged if already `:00`); if `t` falls on the next day → `t = now + 30 min`. `hasTime = false`, flag `defaultTimeApplied`.
Examples: 10:30 → 11:00 · 19:40 → 21:00 · 23:10 → 23:40 · 06:05 → 09:00 · 16:00 → 17:00.

### 8.3 Day expressions

| expression | resolution | flags |
|---|---|---|
| `bugün` | today | — |
| `yarın` (`yarına`, `yarınki`) | today + 1 | — |
| `öbür gün`, `yarından sonra` | today + 2 | — |
| `ertesi gün` | today + 1 | `vagueDate` |
| `dün` / `evvelsi gün` | today − 1 / − 2 | `pastDue` |
| weekday W, no qualifier (incl. `gelecek W`, `önümüzdeki W`, `ilk W`) | `delta = (W − iso(today) + 7) % 7`; `delta == 0 → 7` — **strictly after today** (the user's "gelecek ilk salı") | — |
| `bu W` | `delta = (W − iso(today) + 7) % 7` (0 allowed → today) | — |
| `haftaya W`, `gelecek hafta W`, `önümüzdeki hafta W` | `weekStart(today) + 7 + (W − 1)` (W of the NEXT calendar week) | — |
| `geçen W` | most recent W strictly before today: `today − ((iso(today) − W + 7) % 7)`, 0 → 7 | `pastDue` |
| `haftaya` alone, `haftaya bugün` | today + 7 | — |
| `gelecek hafta`, `önümüzdeki hafta` alone | today + 7 | `vagueDate` |
| `hafta sonu` | `delta = (6 − iso + 7) % 7`; if `iso == 7` → 6 (Saturday; today if today is Saturday) | — |
| `hafta başı`, `haftaya başında` | next Monday strictly after today | — |
| `hafta ortası` | next Wednesday strictly after today | `vagueDate` |
| `ay sonu` | last day of the current month (may be today) | — |
| `ay başı` | 1st of next month | — |
| `ay ortası` | 15th of this month if `>= today`, else 15th of next month | — |
| `ayın N'i` / `ayın N'inde` / `ayın biri` | day N of this month if `>= today`, else day N of next month; N larger than the month length → clamp to the last day (+`vagueDate`); N ∉ 1...31 → `invalidDateTime` | — |
| `N AY` (`15 ekim`, `15 Ekim'de`, `on beş ekimde`, `15. ekim`), also `AY+GEN N+POSS3(LOC)` (`ekimin 15'i`, `ekimin on beşinde`) | this year; if `< today` → next year; impossible (`şubatın 31'i`) → `invalidDateTime`, left in title | `rolledToNextYear` when rolled |
| `N AY YYYY` / `dd.mm.yyyy` / `dd/mm/yyyy` | exact; impossible date (31 şubat) → `invalidDateTime`, ignored | — |
| `dd/mm`, dotted `a.b` read as date (§8.6) | like `N AY` | — |
| `AY başı / başında` | 1st of that month (this year; next year if `< today`) | — |
| `AY ortası` | 15th of that month | — |
| `AY sonu / sonunda` | last day of that month (roll year if the last day `< today`) | — |
| `AY+LOC` alone (`ekimde`, `kasımda`) | 1st of that month (this year / next year); current month → today | `vagueDate` |
| `yıl sonu`, `sene sonu` | 31 Dec this year | — |
| `yılbaşı` | 1 Jan next year | — |
| `gelecek ay`, `önümüzdeki ay` alone | today + 1 month (clamped) | `vagueDate` |
| `seneye`, `gelecek yıl` alone | today + 1 year | `vagueDate` |
| deadline wrappers `D+DAT kadar`, `en geç D`, `D'ye kadar`, `D'den önce`* | same as D (wrapper consumed) | — |

\* `D'den önce` is approximated as D (limitation §16).

### 8.4 Multiple day expressions

* Resolve each; identical dates merge silently (`yarın salı` when tomorrow is Tuesday; `29 eylül salı`).
* Different dates → keep the FIRST, flag `conflictingDates`.
* A qualifier + weekday (`gelecek hafta salı`) or `ayın` + number is ONE expression, not two.

### 8.5 Hour resolution

Input: clock `(h, m)`, `qualifier`, `leadingZero` (text started with `0`, e.g. `09:30`, `08.00`), `daySpecified`
(true if D, R, or calendar O is present), `explicitToday` (D came from `bugün`/`bu …` and equals today).

**With a qualifier** (the qualifier is the daypart word adjacent to the clock phrase, before or after it: `sabah 9`, `9'da sabah`, `akşam saat 8'de`):

| qualifier | h = 1…5 | h = 6 | h = 7…11 | h = 12 | h = 0 or 13…23 |
|---|---|---|---|---|---|
| AM (`sabah`) | h | 6 | h | 12 | literal |
| NOON (`öğle/öğlen`) | h + 12 | 18 | h | 12 | literal |
| PM (`öğleden sonra`, `akşamüstü`) | h + 12 | 18 | h + 12 | 12 | literal |
| EVENING (`akşam`) | h + 12 | 18 | h + 12 | 00:00 next day | literal |
| NIGHT (`gece`) | h on the **next day** of the reference day | 06:00 next day | h + 12 | 00:00 next day | literal |

For NIGHT/EVENING "next day" hours with no D, the candidate is the nearest future among `today h` and `tomorrow h`
(no `rolledToTomorrow`). With D: `D + 1` at h (`yarın gece 2'de` → day-after-tomorrow 02:00).

**Without a qualifier:**

| hour | rule | flag |
|---|---|---|
| `leadingZero` (`09:30`, `08.00`) | literal | — |
| 0, 13…23 | literal (24 → 00:00 next day) | — |
| 12 | 12:00 | — |
| 1…6 | `belirsizSaatlerOgledenSonra` ? h + 12 : treat as 7…11 | `ambiguousHourPM` |
| 7…11, `daySpecified && !explicitToday` | h (AM) | — |
| 7…11, otherwise | nearest future among `today h`, `today h+12`; if both passed: no day → `tomorrow h` (`rolledToTomorrow`), explicit today → `today h+12` + `pastDue` | `ambiguousHourNearest` |

Minutes stay as spoken (`3:30` → 15:30, `üç buçukta` → 15:30, `üçe çeyrek var` → 14:45: the clock phrase is
computed first as 2:45, then 2 → 14 by the 1…6 rule).

### 8.6 Dotted `a.b` without year

1. TIME if: preceded by `saat` or a daypart; or the token has a LOC/DAT suffix (`15.30'da`, `15.10'da`, `9.45te`);
   or `b > 12`; or `b == 0`. Requires `a <= 24 && b <= 59`, else `invalidDateTime`.
2. Otherwise (`b` in 1…12, `a` in 1…31): DATE (day a, month b). If another explicit time exists in the utterance or the
   next token is `tarihinde/tarihli/tarihine/tarihe/günü` → no flag; else flag `ambiguousDotted`.
3. Otherwise TIME if valid, else ignored.

### 8.7 Worked examples (`now` = Sun 2026-09-27 10:30 unless stated)

| utterance fragment | due | notes |
|---|---|---|
| `salı günü … saat 3'te` | 2026-09-29 15:00 | weekday strict-after, 1–6 → PM |
| `salı 9'da` | 2026-09-29 09:00 | day specified → AM |
| `bu salı` | 2026-09-29 09:00 | default time |
| `haftaya salı` | 2026-09-29 09:00 | next calendar week = 28 Sep – 4 Oct |
| `pazar` (today is Sunday) | 2026-10-04 09:00 | same weekday → +7 |
| `bu pazar` | 2026-09-27 11:00 | today policy |
| `3'te` | 2026-09-27 15:00 | |
| `8'de` | 2026-09-27 20:00 | 08:00 passed → nearest future 20:00 |
| `11'de` | 2026-09-27 11:00 | |
| `sabah 9'da` | 2026-09-28 09:00 | rolled to tomorrow |
| `akşam 8` | 2026-09-27 20:00 | |
| `gece 2'de` | 2026-09-28 02:00 | NIGHT, nearest future |
| `yarın gece 12'de` | 2026-09-29 00:00 | D + 1 |
| `hafta sonu` | 2026-10-03 09:00 | |
| `ay sonu` | 2026-09-30 09:00 | |
| `ayın 15'inde` | 2026-10-15 09:00 | 15 Sep passed |
| `20 eylül` | 2027-09-20 09:00 | rolled to next year |
| `10 dakika sonra` | 2026-09-27 10:40 | |
| `bir buçuk saat sonra` | 2026-09-27 12:00 | |
| `3 gün sonra` | 2026-09-30 09:00 | calendar offset + default time |
| `birazdan` | 2026-09-27 10:45 | +15 min |
| `akşama` | 2026-09-27 19:00 | |
| `mesai bitiminde` | 2026-09-27 17:30 | |
| now = Tue 09:15: `salı` | 2026-10-06 09:00 | same weekday → next week |
| now = Tue 09:15: `bu salı 3'te` | 2026-09-29 15:00 | |
| now = Tue 09:15: `9'da` | 2026-09-29 21:00 | nearest future |
| now = Tue 19:40: `3'te` | 2026-09-30 15:00 | rolled to tomorrow |
| now = Tue 19:40: `bugün 3'te` | 2026-09-29 15:00 | `pastDue` → low confidence |
| now = Thu 2026-12-31 16:00: `haftaya cuma` | 2027-01-08 09:00 | week 28 Dec–3 Jan → next week 4–10 Jan |
| now = Thu 2026-12-31 16:00: `ay sonu` | 2026-12-31 17:00 | today policy |

---

## 9. Recurrence (`RecurrenceParser.swift`)

### 9.1 Patterns (folded; `W` = weekday word, `N` = number)

| phrase | Recurrence | default time |
|---|---|---|
| `her gün`, `hergün`, `günde bir`, `her gün düzenli` | daily ×1 | T or `defaultDayTime` |
| `her sabah` / `her öğlen` / `her akşam` / `her gece` | daily ×1 | the daypart |
| `her N günde bir`, `N günde bir`, `iki günde bir` | daily ×N | T or default |
| `hafta içi (her gün)`, `hafta içleri`, `iş günleri`, `her iş günü`, `her hafta içi` | weekly ×1 `[1,2,3,4,5]` | T or default |
| `her hafta sonu`, `hafta sonları` | weekly ×1 `[6,7]` | T or default |
| `her W`, `W+PLURAL-DAYS` (`pazartesileri`, `salıları`), `W günleri` | weekly ×1 `[W]` | T or default |
| `her W (ve|,) W2 (ve W3)`, `W ve W2 günleri`, `pazartesi ve perşembeleri` | weekly ×1 sorted `[W, W2 …]` | T or default |
| `her hafta` (+ optional W) | weekly ×1 `[W]` or `[iso(today)]` | T or default |
| `iki haftada bir`, `2 haftada bir`, `her iki haftada bir`, `on beş günde bir` (+ optional W) | weekly ×2 `[W]` or `[iso(today)]` | T or default |
| `her ay`, `ayda bir` (+ optional `N'inde`) | monthly ×1, `monthDay = N` or `day(today)` | T or default |
| `her ayın N'i / N'inde / birinde / ilk günü / başında` | monthly ×1, `monthDay = N` (başında = 1) | T or default |
| `her ayın son günü`, `her ay sonu`, `her ay sonunda` | monthly ×1, `monthDay = -1` | T or default |
| `her yıl`, `her sene`, `yılda bir`, `senede bir` (+ `N AY`) | yearly ×1, `month`/`monthDay` from the date or today | T or default |
| `doğum günü`, `doğumgünü`, `yıl dönümü`, `yıldönümü` + an explicit `N AY` date, no `her yıl` | yearly ×1 (auto) | T or default |
| `her saat`, `saatte bir`, `her yarım saatte`, `her dakika`, `her N dakikada bir` | **unsupported** → `recurrence = nil`, flag `unsupportedRecurrence` | — |

A weekday-set phrase overrides a daily phrase in the same utterance: `hafta içi her sabah` → weekly `[1…5]` at `sabah`;
`her hafta sonu akşam` → weekly `[6,7]` at `aksam`. Weekday lists accept `ve`, `,`, `ile` separators. Recurrence phrases count as "day specified" for §8.5
(`her gün 8'de` → 08:00; `her pazartesi 3'te` → 15:00).

### 9.2 Validation

`interval` 1…12 (daily 1…30); larger → clamp and flag `vagueDate`. `monthDay` 1…31 or −1; 29–31 in short
months fire on the last day (app scheduling concern, recorded here for consistency).

### 9.3 First occurrence (`dueDate` of a recurring item)

The earliest instant **strictly after `now`** that matches the rule, with the resolved time of day
(explicit T, daypart, or `defaultDayTime`). **Today is allowed** if the time is still ahead (this differs from the
single-weekday rule on purpose: "her salı 10'da" said on Tuesday 09:15 must fire today at 10:00).
* weekly ×2 anchors on the first matching weekday found by this search.
* monthly `monthDay = N`: this month if the instant is ahead, else next month (clamped to month length); `-1` = last day.
* yearly: this year's `month/monthDay` if ahead, else next year.
* An explicit D in the same utterance (`her pazartesi, 5 ekim'den itibaren`) sets the search start to D (limitation: `itibaren/başlayarak` are consumed).

---

## 10. Kind classification (template-free, tiered)

The classifier looks at **cue phrases** found anywhere in the utterance (verb forms are matched by folded
prefix + allowed ending, so `hatırlat, hatırlatır mısın, hatırlatsana, hatırlatabilir misin, hatırlatın,
hatırlatıver, hatırlar mısın` all hit the stem `hatirla`). The first tier that fires decides the kind; the
tier also gives the **kind certainty** used by §12.

### 10.1 Tiers

| tier | fires when | kind | certainty |
|---|---|---|---|
| T0 | prefix marker §7.1 | note / task / waiting | 1.00 |
| T1 | command cue at utterance end (§10.5) or query phrase (§10.5.1) | command | 1.00 (0.85 generic) |
| T2 | strong note phrase: `not al, not et, not düş, nota ekle, notlara ekle, not olarak kaydet, not olarak ekle, not tut` | note | 1.00 |
| T3 | explicit task phrase: `görev ekle, görev olarak ekle/kaydet, görevlere ekle, yapılacaklara ekle, yapılacaklar listesine ekle, listeye ekle, listeme ekle, iş listesine ekle, işlere ekle, yapılacak olarak ekle` | task | 1.00 |
| T4 | waiting cue (§10.4) | waiting | 0.95 |
| T5 | reminder cue (§10.3) | reminder | 1.00 |
| T6 | task modality: `lazım, gerek, gerekiyor, gerekli, şart, -mAlIyIm/-mAlIyız, yapmam gereken, halletmem lazım` | task | 0.90 |
| T7 | weak note cue: `kaydet, bunu yaz, şunu yaz, kenara yaz, aklımda olsun, aklında olsun, bilgi:, bilgi olarak` **and no date/time/offset/recurrence** | note | 0.85 |
| T8 | any resolved date/time/offset/recurrence or place trigger | reminder | 0.90 |
| T9 | utterance ends with an imperative content verb (§10.6 list) | task | 0.80 |
| T10a | ≥ 8 content tokens, no cue | note | 0.70 |
| T10b | anything else | note | 0.55 |

### 10.2 Tier interplay

* Notes from T0 (`not:`/`fikir:`), T2 and T7 are **verbatim**: dates/times inside a note are NOT extracted and NOT removed; `dueDate = nil`.
  (A note like "not al: yarın toplantı 3'te" keeps the text intact.) Priority is still extracted.
* T3/T4/T6 items still get a `dueDate` when the utterance contains one (tasks and waiting-for items with a due
  are notified exactly like reminders).
* A reminder cue inside a command utterance (`… hatırlatmasını iptal et`) is NOT a reminder cue: the noun forms
  `hatırlatma, hatırlatmayı, hatırlatmasını, hatırlatıcı(yı/sını), alarmı, alarmını` are **object words** of commands.
* `hatırlatma kur/ekle/oluştur`, `alarm kur`, `alarm ayarla` are reminder cues (T5).
* Negation: `bana hatırlatma` / `hatırlatma` as the LAST token with no command verb → reminder, flag `negation` (−0.40).

### 10.3 Reminder cues (T5)

`hatırlat*` (stem `hatirla`, excluding object nouns above), `unutma`, `unutmayayım`, `unutmamam lazım`, `unutturma`,
`aklıma getir`, `aklıma sok`, `uyar` / `uyarır mısın` / `beni uyar`, `ikaz et`, `alarm kur`, `alarm ayarla`,
`alarm`(+time), `bana haber ver`, `bana bildir`, `bana söyle`, `dürt`, `beni dürt`.
`haber ver / bildir / söyle / uyar` count as reminder cues only when their indirect object is the user (`bana`, `beni`, or none).
With a person dative (`Ahmet'e haber ver`, `Ayşe'ye söyle`) they are content verbs (→ T9 task unless another cue exists).

### 10.4 Waiting-for cues (T4) and person

* `X+ABL … bekliyorum / bekleniyor / beklemedeyim / bekleyeceğim` (`Ahmet'ten teklif bekliyorum`) → person = X.
* `bekliyorum` without ablative person → waiting, person via §7.9 if any.
* 3rd-person future verbs at utterance end (with or without a detected person; the subject becomes the person via P7 when capitalised):
  `gönderecek, yollayacak, iletecek, dönecek, dönüş yapacak, cevap verecek, yanıt verecek, arayacak, getirecek,
  hazırlayacak, teslim edecek, onaylayacak, bakacak, halledecek, yapacak`. (`gelecek` is excluded — it is also "next".)
* `takip et`, `takibe al`, `takipte kal`, `peşine düş`, `dönüşünü bekle`, `cevabını bekle`, `hatırlatmasını bekle`* → waiting.
* Waiting items without date get `dueDate = nil`; the app applies its own follow-up default (outside the parser).

\* rare; listed for completeness.

### 10.5 Commands (T1)

A command is recognised when its **cue is the last verb phrase** of the utterance (after dropping fillers,
priority words and trailing `lütfen`). Anything before it is the target (`queryText`, §10.6) and may contain
a day expression that becomes `command.date` (day filter).

| type | cues (folded forms) | certainty |
|---|---|---|
| complete | `yaptım, yapıldı, tamamladım, tamamlandı, tamamdır, tamam (last token, ≥ 2 tokens before), bitirdim, bitti, hallettim, halloldu, hallolmuştur, tamamlandı olarak işaretle, yapıldı olarak işaretle, tik at, işaretle (after "yapıldı/tamamlandı")` | 1.00 |
| complete (content verbs, stem kept) | `aradım(ara), gönderdim(gönder), yolladım(yolla), ilettim(ilet), konuştum(konuş), görüştüm(görüş), ödedim(öde), aldım(al), teslim ettim(teslim et), bitirdim(bitir), hazırladım(hazırla), kontrol ettim(kontrol et)` | 0.90 |
| complete (generic past 1sg `-DIm` at the end, none of the above) | stem kept | 0.85 |
| cancel | `iptal et, iptal, sil, kaldır, vazgeç, vazgeçtim, gerek yok, gerek kalmadı, unut (bare imperative, last token), boşver, sil gitsin` | 1.00 |
| snooze | `ertele, erteler misin, ötele, sonra hatırlat, tekrar hatırlat, yeniden hatırlat, sonra tekrar hatırlat, daha sonra hatırlat, biraz sonra hatırlat` | 1.00 |

Snooze details: a duration (`10 dakika ertele`, `yarım saat ertele`, `bir saat sonra hatırlat`) → `snoozeMinutes`
and `date = now + minutes`; a day/time (`yarına ertele`, `akşama ertele`, `cumaya ertele`, `yarın 3'e ertele`) →
`date` resolved by §8 (with `daySpecified` rules); nothing → both nil (the app applies its nag interval). `birazdan
hatırlat` without other content → snooze with `birazdanMinutes`.

#### 10.5.1 Queries

Fires when the utterance contains a query phrase and **no content to create** (only scope words, fillers,
object words and the phrase itself):

* phrases: `ne var, neler var, nelerim var, ne işim var, programım (ne), programımda ne var, ajandam, ajandamı oku,
  neler yapacağım, ne yapacağım, neler yapmam lazım, neler yapmam gerekiyor, kimden ne bekliyorum, ne bekliyorum,
  neler bekliyorum, listele, oku, göster, say (as last token), sırala, özetle` (+ object words
  `hatırlatmalarımı, hatırlatıcılarımı, görevlerimi, yapılacakları, notlarımı, işlerimi, gecikenleri, bekleyenleri, alarmlarımı`).
* scope: `bugün` → today · `yarın` → tomorrow · `bu hafta` → thisWeek · `gelecek/önümüzdeki hafta`, `haftaya` → nextWeek ·
  a single day (`salı`, `15 ekim`, `cuma günü`) → `.date` with `command.date = startOfDay` (resolved by §8.3) ·
  `geciken(ler|leri)`, `gecikmiş`, `kaçırdıklarım`, `unuttuklarım`, `yapmadıklarım`, `yapılmayanlar` → overdue ·
  `bekleyen(ler|leri)`, `ne bekliyorum`, `kimden …` → waiting · `notlarım` → notes · `görevlerim`, `yapılacaklar` → tasks ·
  no scope and phrase is `ne var` / `neler var` / `programım` / `ajandam` → today · otherwise → all.
* Query glue words consumed with filters: `ile ilgili`, `hakkında`, `için`, `-le ilgili` (`Arka Cep'le ilgili`).
* A known project (§7.2) or person (§7.9) inside a query is a filter: it is stored in `ParsedCommand.project` /
  `ParsedCommand.person` and its tokens do not count as "content to create" (`Arka Cep'le ilgili neler var` →
  query, scope all, project Arka Cep; `Ahmet'ten ne bekliyorum` → query, scope waiting, person Ahmet).
  The same two fields are filled for complete/cancel/snooze targets when present.

### 10.6 Target text (`queryText`) and imperative verb list

`queryText` = the tokens before the command cue that are not consumed by date/filler/object-word extraction,
each token converted with: Turkish lowercase → apostrophe suffix removed (`ahmet'i` → `ahmet`, `plc'yi` → `plc`)
→ title suffix repair rules S1–S4 (§11.2) applied to the **last** token → joined by single spaces; for content-verb
completions the verb stem is appended (`Ahmet'i aradım` → `ahmet ara`). Empty or pronoun-only (`bunu`, `şunu`) → `nil`.
Project and person tokens stay in `queryText` for complete/cancel/snooze (they help matching) and are ALSO reported in
`command.project` / `command.person`. Object words (`hatırlatmasını`, `görevini`, …) and day expressions are removed
(the day goes to `command.date`). Examples: `teklif konusunu tamamladım` → `teklif konusu`; `Hat 3 yedeğini aldım` →
`hat 3 yedeği al`; `yarınki toplantıyı iptal et` → `toplantı` + date filter.

Imperative content verbs for T9 (folded, last token, plus two-word forms): `ara, gönder, yolla, ilet, al, ver, hazırla,
yaz, bak, kontrol et, incele, oku(if not query), düzelt, güncelle, onayla, imzala, öde, topla, planla, ayarla, sipariş et,
sipariş ver, teslim et, test et, yükle, indir, kur, tak, değiştir, temizle, bitir, tamamla, söyle, haber ver, sor, konuş, görüş,
toplantı yap, mail at, e-posta at, mesaj at, yedek al, yedekle, rapor yaz, teklif ver`.

---

## 11. Title extraction (`TitleBuilder.swift`)

### 11.1 Consumed (removed) material

Everything an extractor consumed: date/time/offset/recurrence phrases **including their glue words**
(`saat`, `günü`, `günleri`, `tarihinde`, `tarihli`, `civarı`, `civarında`, `gibi`(after a clock), `sularında`,
`kadar`/`en geç`/`itibaren` in deadline wrappers), removable priority words (§7.8), fillers (§5.6), all cue
phrases (reminder verbs, kind phrases, command verbs + object words), place phrase + trigger verb, explicit project
markers (§7.2), and for **waiting-for** items the waiting verb and the source person phrase (`Ahmet'ten`, P7 subject).
Persons and naturally mentioned projects are NOT removed for other kinds.

### 11.2 Suffix repair (LAST remaining token only, first matching rule, never for notes)

**When:** S1 and S5 always apply. S2–S4 apply only if the utterance contained a consumed **verb cue** (reminder cue,
task/note phrase, waiting verb, command verb — before or after the token): then the last token was the object of the
removed verb (`… toplantısını hatırlat`, `hatırlat bana … teklif sunumunu` → repaired). Pure noun-phrase utterances
without any verb cue are never repaired (`perşembe 3'te performans görüşmeleri` keeps its natural compound form).

| rule | condition (on lowercase form; check root length ≥ 2 before the suffix) | result | examples |
|---|---|---|---|
| S1 | ends with `mayı / meyi / masını / mesini` | `mak / mek` | `aramayı → aramak`, `göndermeyi → göndermek`, `almayı → almak`, `içmesini → içmek` |
| S2 | ends with vowel V + `n` + V (same vowel: `ını, ini, unu, ünü`), removing `nV` leaves a word that ends in a vowel with ≥ 2 letters before it; not in the exception list `fırın, altın, kalın, kadın, düğün, beyin, ekin, akın, yakın, burun` | drop `nV` | `konusunu → konusu`, `raporunu → raporu`, `planını → planı`, `yedeğini → yedeği`, `işini → işi`, `gününü → günü`, apostrophe tokens: `PLC'sini → PLC'si` |
| S3 | ends with `leri / ları`, length ≥ 6, no apostrophe | drop final vowel | `çizimleri → çizimler`, `raporları → raporlar` |
| S4 | ends with vowel + `yı / yi / yu / yü`, no apostrophe | drop `yV` | `toplantıyı → toplantı`, `arabayı → araba`, `dişçiyi → dişçi` |
| S5 (modality) | token directly before a consumed `lazım/gerek/gerekiyor(du)/gerekli/şart` ends with `mam/mem`, or the token itself ends with `malıyım/meliyim/malıyız/meliyiz` (the modality suffix is the cue) | `mak / mek` | `yazmam lazım → yazmak`, `hazırlamam gerekiyor → hazırlamak`, `yapmalıyım → yapmak` |

`günü` (1 letter before) and `Ahmet'i` (apostrophe, not S2 shape) are left alone. Only the last token is repaired
because only it was the object of a removed verb; inner tokens keep their grammatical form (`Teklifi göndermek`).

### 11.3 Edge trimming

Repeatedly strip connector words (§5.7) and stray punctuation at the **start and end** of the remaining sequence.
`Ahmet'i ara diye` → `Ahmet'i ara`. `ve teklif` → `teklif`.

### 11.4 Kind-specific rules

* **waiting:** title = remaining object phrase (`Ahmet'ten teklif bekliyorum` → `Teklif`;
  `Mehmet cuma günü çizimleri gönderecek` → `Çizimler`). If empty → `"<person>'dan dönüş"`-style strings are NOT
  generated (suffix harmony risk); use `Dönüş bekleniyor`.
* **note (T0/T2/T7):** `body` = normalized text minus the prefix/note phrase, minus fillers and priority words at the
  **edges** only, minus edge pronouns `bunu, şunu, şöyle, şunları`; internal text verbatim (dates untouched).
  `title` = body cut at the last word boundary ≤ 60 characters, with `…` appended when cut.
* **task via T9:** the imperative verb stays (`Ahmet'i ara`).
* **alarm:** empty title + cue `alarm` → `Alarm` (no `titleFallback` flag).

### 11.5 Capitalisation

First character with `trUpperFirst` (`i → İ`, `ı → I`), the rest exactly as spoken (keeps `PLC`, `Hat 3`, `Ahmet`).
Multiple spaces collapsed.

### 11.6 Never empty

If the result is empty, consists only of pronouns (`bu, bunu, şu, şunu, o, onu`), or has fewer than 2 letters →
title = normalized original text (trailing punctuation removed, first letter upper-cased), flag `titleFallback`.

---

## 12. Confidence (`Confidence.swift`)

`confidence = clamp(certainty(tier) − Σ penalty(flag), 0, 1)`, rounded to 2 decimals. Each flag counts once.

| flag | penalty | | flag | penalty |
|---|---|---|---|---|
| ambiguousHourPM | 0.05 | | needsTime | 0.15 |
| ambiguousHourNearest | 0.10 | | unsupportedRecurrence | 0.40 |
| ambiguousDotted | 0.15 | | multipleItems | 0.25 |
| rolledToTomorrow | 0.05 | | unknownPlace | 0.25 |
| rolledToNextYear | 0.05 | | uncertainPerson | 0.05 |
| defaultTimeApplied | 0.00 | | negation | 0.40 |
| pastDue | 0.45 | | titleFallback | 0.40 |
| conflictingDates | 0.35 | | vagueDate | 0.10 |
| invalidDateTime | 0.30 | | tooShort (< 2 tokens) | 0.20 |
| unusedNumber | 0.10 | | tooLong (> 40 tokens) | 0.10 |

`needsTime` is raised for kind reminder (T5) with no date/time/offset/recurrence/place. `titleFallback`, `tooShort` and
`unusedNumber` are never raised for commands; `unusedNumber` is never raised for notes (verbatim text). `multipleItems` is raised when two content verbs are joined by `ve ayrıca / bir de / sonra da / ayrıca`
or two different reminder/task cues appear with different content.

**Thresholds** (settings): `>= 0.80` auto-save with Undo · `0.60 ..< 0.80` confirmation sheet · `< 0.60` edit mode,
flag `smartModeSuggested`, and Akıllı Mod (if enabled) is consulted before showing the sheet.

---

## 13. Understood text, relative phrase, Turkish date formatter (`TurkishDateFormatter.swift`)

Locale-independent, identical on Linux and iOS. Tables:

```swift
static let months = ["Ocak","Şubat","Mart","Nisan","Mayıs","Haziran","Temmuz","Ağustos","Eylül","Ekim","Kasım","Aralık"]
static let weekdays = ["Pazartesi","Salı","Çarşamba","Perşembe","Cuma","Cumartesi","Pazar"]      // ISO 1...7
static let weekdaysShort = ["Pzt","Sal","Çar","Per","Cum","Cmt","Paz"]
static func hhmm(_ h: Int, _ m: Int) -> String   // zero-padded manually: (h < 10 ? "0" : "") + String(h) + ":" + ...
```

**Day label** of a date relative to `now`: day diff 0 → `Bugün`, 1 → `Yarın`, −1 → `Dün`, otherwise the weekday name.
**Date phrase** = `<label> <d> <Month>` + ` <yyyy>` when the year differs from `now`'s year. Examples:
`Bugün 27 Eylül`, `Yarın 28 Eylül`, `Salı 29 Eylül`, `Yarın 1 Ocak 2027`.

**understood** (items):
`<date phrase>, <HH:mm> — <title>` · then optional segments joined with ` · `: recurrence text, `Acil` (critical) / `Önemli` (high) /
`Düşük öncelik` (low), `Kişi: <person>`, `Proje: <project>`.
* no due: `<Kind> — <title>` with Kind = `Hatırlatma` / `Görev` / `Not` / `Bekleniyor` (waiting with person:
  `Bekleniyor (<person>) — <title>`).
* place: `Konum: <place> (varınca|çıkınca) — <title>`.
* examples: `Salı 29 Eylül, 15:00 — Teklif konusu` · `Pazartesi 28 Eylül, 08:00 — Günlük rapor · Her gün` ·
  `Konum: Fabrika (varınca) — Hat 3 sensörüne bakmak`.

**understood** (commands): query → `Bugünün ajandası`, `Yarının ajandası`, `Bu haftanın ajandası`, `Gelecek haftanın ajandası`,
`<date phrase> ajandası`, `Gecikmiş işler`, `Beklenenler`, `Notlar`, `Görevler`, `Tüm açık işler`; complete → `Tamamlanacak: <queryText or "son hatırlatma">`;
cancel → `İptal edilecek: …`; snooze → `Ertelenecek: … → <date phrase>, <HH:mm>`.

**Recurrence text:** `Her gün`, `Her 3 günde bir`, `Hafta içi her gün`, `Her hafta sonu`, `Her Pazartesi`,
`Her Pazartesi ve Perşembe`, `Her Pazartesi, Çarşamba ve Cuma`, `2 haftada bir Cuma`, `Her ayın 1'i`, `Her ayın son günü`,
`Her yıl 3 Mart`.

**Numeral suffix table** (for `Her ayın N'i` etc.; by last non-zero digit, tens when the unit is 0):
units `1 'i, 2 'si, 3 'ü, 4 'ü, 5 'i, 6 'sı, 7 'si, 8 'i, 9 'u`; tens `10 'u, 20 'si, 30 'u`.
(`1'i, 2'si, 3'ü, 10'u, 15'i, 16'sı, 20'si, 23'ü, 30'u, 31'i`)

**relativePhrase** (`m` = whole minutes from now to due, `d` = calendar-day difference):
`m < 0` → `(geçmiş)`; `m == 0` → `(şimdi)`; `m < 60` → `(m dakika sonra)`; `d == 0` or `m < 720` → `(H saat sonra)` or
`(H saat M dakika sonra)`; `d == 1` → `(yarın)`; `d < 14` → `(d gün sonra)`; `d < 60` → `(yaklaşık w hafta sonra)`, `w = (d + 3) / 7`;
else `(yaklaşık n ay sonra)`, `n = max(2, Int((Double(d) / 30.44).rounded()))`.
Examples from Sun 10:30: 10:40 → `(10 dakika sonra)`; 12:00 → `(1 saat 30 dakika sonra)`; 20:00 → `(9 saat 30 dakika sonra)`;
Mon 02:00 → `(yarın)` (m = 930 ≥ 720 and d = 1); Mon 09:00 → `(yarın)`; Tue 15:00 → `(2 gün sonra)`; 15 Oct → `(yaklaşık 3 hafta sonra)`.

**List section headers** (used by the app with the same formatter): `Gecikmiş`, `Bugün`, `Yarın`, `Bu Hafta`, `Gelecek Hafta`,
`Daha Sonra`, `Tarihsiz`, `Konuma Bağlı`, `Bekleniyor`.

---

## 14. Akıllı Mod (LLM) fallback contract

Off by default; used only when the user enabled it and stored an API key (Keychain). The rule-based result is
always computed first and shown if the network fails (timeout 8 s).

* **When:** `confidence < smartModeThreshold`, or the user taps "Akıllı Mod ile yeniden anla".
* **Request content:** the original utterance, `now` as local ISO (`2026-09-27T10:30`, `Europe/Istanbul`, weekday name),
  the parser's JSON result + flags as a hint, the settings defaults (dayparts, 1–6 → PM policy), known projects,
  places, people. Never send other items or notes.
* **Required response:** a single JSON object `{ "kind": "reminder|task|note|waiting|command", "title": String,
  "due": "YYYY-MM-DDTHH:mm" | null, "hasTime": Bool, "recurrence": {freq, interval, weekdays, monthDay, month} | null,
  "priority": "low|normal|high|critical", "person": String|null, "project": String|null,
  "place": {"name", "trigger"}|null, "command": {type, scope, date, query}|null, "explanation": String }`.
* **Validation before use:** JSON decodes; enums valid; `due` parses in the parser calendar and is `> now`
  (or the user said a past day); project/place ∈ known lists (else dropped); title non-empty and ≤ 120 chars.
  Any failure → keep the rule-based result. The LLM result is always shown in the confirmation sheet (never auto-saved),
  with `understood` regenerated by §13 from the validated fields (never the LLM's own wording).

---

## 15. Test corpus (`docs/design/parser_corpus.json`) and harness rules

File shape:

```json
{
  "version": 1,
  "timeZone": "Europe/Istanbul",
  "referenceNows": { "sun": "2026-09-27T10:30", "tue_morning": "2026-09-29T09:15", ... },
  "settings": { "defaultDayTime": "09:00", "sabah": "09:00", ..., "knownProjects": [...], "knownPlaces": [...] },
  "cases": [
    { "id": "wd-001", "now": "sun", "input": "Salı günü teklif konusunu bana saat 3'te hatırlat",
      "tags": ["weekday", "pm-rule", "user-example"],
      "expected": { "kind": "reminder", "title": "Teklif konusu", "due": "2026-09-29T15:00",
                    "recurrence": null, "priority": "normal", "person": null, "project": null,
                    "place": null, "command": null, "minConfidence": 0.85 } }
  ]
}
```

Harness (`AsistCoreTests/CorpusTests.swift`, runs on Linux and macOS CI):

1. Load the JSON from the test bundle (`Bundle.module` resource; copy of `docs/design/parser_corpus.json`, a CI step
   verifies both files are byte-identical).
2. Build `ParserSettings` from `settings`; calendar = `TurkishParser.defaultCalendar()`; parse `now` strings as local time
   in that calendar (`DateComponents` → `calendar.date(from:)`; no `DateFormatter`).
3. For every case compare:
   * `kind` — `ParseResult.kind.rawValue`.
   * `title` — exact string equality with `item.title` when not null (skip when null or kind = command).
   * `due` — `item.dueDate` (or `command.date` for snooze) formatted `yyyy-MM-dd'T'HH:mm` in the parser calendar; `null` means must be nil.
     For query/complete/cancel commands `due` is always null and the date filter is checked inside `command.date`.
   * `recurrence` — `{freq, interval, weekdays, monthDay, month}`; missing keys = null.
   * `priority`, `person`, `project` — exact (person/project are read from `item` or, for commands, from `command`).
   * `place` — `{name, trigger}` or null.
   * `command` — `{type, scope?, date? ("YYYY-MM-DD"), query?, snoozeMinutes?}`; only the keys present in the expectation are compared
     (`"query": null` present = `queryText` must be nil); `query` is compared after Turkish lowercasing and whitespace collapsing.
   * `settings` times are `"HH:mm"` strings → `ClockTime`.
   * `minConfidence` — `confidence >= minConfidence`; optional `maxConfidence` — `confidence <= maxConfidence`
     (used for the low-confidence cases, all `maxConfidence: 0.59`).
4. Report every failing field per case; the test fails if any case fails. A per-tag summary is printed so regressions are localisable.

Corpus settings used for all cases: default day time 09:00, sabah 09:00, öğlen 12:00, öğleden sonra 14:00,
akşamüstü 17:00, akşam 19:00, gece 22:00, mesai başı 08:30, mesai bitimi 17:30, birazdan +15 min, 1–6 → PM;
projects `Arka Cep, Hat 3, Kaynak Robotu, Bakım`; places `Fabrika, Ev, Ofis`; knownPeople empty.

Changing any rule in this spec requires updating the affected corpus cases in the same commit.

**Corpus v1 content:** 371 cases (reminder 267, task 30, note 15, waiting 13, command 46), 19 of them low-confidence
(`maxConfidence: 0.59`). Reference nows: `sun` 293 cases, `dec31` 18, `month_end` 13, `fri_late` 13, `mon_early` 12,
`tue_morning` 11, `tue_evening` 11. Id prefixes: `wd-` weekdays/clock, `rel-` offsets, `dp-` dayparts, `day-` day words,
`abs-` absolute dates, `rec-` recurrence, `pri-` priority, `per-` persons, `prj-` projects, `pla-` places, `tsk-` tasks,
`not-` notes, `wai-` waiting-for, `qry-`/`cmp-`/`cnl-`/`snz-` commands, `dic-` dictation robustness, `low-` low confidence.
Every case carries `tags` naming the rule it pins (e.g. `pm-rule`, `same-weekday-plus7`, `today-policy`, `S2`).
Extra top-level keys: `referenceNowWeekdays` (sanity aid), `settings`, `fieldNotes`. Expected dates were generated by a
script implementing §8/§9 and cross-checked (first-occurrence weekday ∈ recurrence weekdays, monthDay match, all dues in
the future except low-confidence past cases).

---

## 16. Known limitations (v1, documented behaviour — not bugs)

1. **One item per utterance.** "Ahmet'i ara bir de raporu gönder" produces one item (first verb phrase) and flag `multipleItems`.
2. **`bir de` / `birde`, `ona` / `onu`, `de` after numbers:** resolved by context rules (§6.1, §3 step 4); rare misreads remain
   ("yarın 2 de gelsin" → 14:00).
3. **Hour ambiguity is policy, not understanding:** 1–6 → PM can be wrong for early-shift workers ("5'te kalk" means 05:00);
   the user can turn `belirsizSaatlerOgledenSonra` off; the confirmation shows the resolved hour.
4. **`gelecek salı` = the next upcoming Tuesday** (not "Tuesday of next week"); `haftaya salı` = next calendar week.
   Some speakers use them the other way round.
5. **Dotted `15.10`** is a heuristic (§8.6).
6. **Person detection depends on capitalisation/apostrophes** from dictation. Lowercase names without apostrophe are only found via
   `knownPeople`. Company names with apostrophes (`Siemens'ten`) are reported as persons.
7. **Suffix repair covers 5 patterns** on the last token only; irregular stems (`burnunu`, `oğlunu`) and the exception list may still
   produce slightly unnatural titles, and S3 can wrongly shorten a compound noun at the end of a verb-bearing utterance
   (`hatırlat yarın performans görüşmeleri` → `Performans görüşmeler`).
8. **No morphological analyser:** verb cues are matched by stems/lists; unseen verb forms fall to weak tiers.
9. **Relative references** ("toplantıdan sonra", "Ahmet gelince", "yağmur yağarsa") are not resolved; they stay in the title.
10. **Holidays** (Ramazan/Kurban Bayramı, kandiller, 29 Ekim etc. by name) are not resolved, except `yılbaşı`.
11. **`D'den önce`, `çıkmadan önce`** are approximated as `D` / onLeave.
12. **Hourly/minutely recurrence** is rejected (iOS pending-notification limit of 64 and battery); the user is told why.
13. **Seconds** are not supported ("30 saniye sonra" → treated as 1 minute).
14. **`pazar` / `ekim` / `ocak` / `aralık` / `mart`** homonyms are handled by context rules only.
15. **Past tense 1sg at the end** is read as a completion command; "bugün Ahmet'le konuştum, teklifi bekliyor" style diary
    sentences can be misread (moderate confidence; user confirms).
16. **Notes are verbatim**: "not al yarın 3'te toplantı" does NOT create a timed reminder by design.
17. **A command verb at the very end wins**: "yarın Ahmet'e haber ver toplantı iptal" is read as a cancel command
    (target "toplantı"), not as a task. The confirmation shows "İptal edilecek: …" and the user can correct it.
18. **Same weekday means next week** even early in the morning (`pazartesi 9'da` said Monday 06:05 → next Monday); use
    `bugün` or `bu pazartesi` for today. This follows the user's explicit "gelecek ilk salı" requirement.
19. **`haftaya salı` said on a Sunday** is two days later (next calendar week starts tomorrow).

---

## 17. Utterances that MUST produce low confidence (< 0.60)

All of these are in the corpus with `maxConfidence: 0.59` (ids `low-001` … `low-018`, `pla-007`). The arithmetic follows §12.

| utterance (now = sun unless noted) | kind / tier | computation | ≈ conf |
|---|---|---|---|
| `toplantı` | note T10b 0.55 | − tooShort 0.20 | 0.35 |
| `şey`, `hmm şey ya` | note T10b 0.55 | − titleFallback 0.40 (− tooShort) | 0.00–0.15 |
| `bana hatırlatma` | reminder T5 1.00 | − negation 0.40 − needsTime 0.15 − titleFallback 0.40 | 0.05 |
| `bunu hatırlat` | reminder T5 1.00 | − needsTime 0.15 − titleFallback 0.40 (pronoun-only title) | 0.45 |
| `hatırlat` | reminder T5 1.00 | − needsTime − titleFallback − tooShort | 0.25 |
| `yarın` | reminder T8 0.90 | − tooShort − titleFallback | 0.30 |
| `yarın salı Ahmet'le toplantı` | reminder T8 0.90 | − conflictingDates 0.35 (yarın = Pazartesi) | 0.55 |
| `her saat su içmeyi hatırlat` | reminder T5 1.00 | − unsupportedRecurrence 0.40 − needsTime 0.15 | 0.45 |
| `her dakika kontrol et` | task T9 0.80 | − unsupportedRecurrence 0.40 | 0.40 |
| `saat 25'te toplantı` | note T10b 0.55 | − invalidDateTime 0.30 | 0.25 |
| `ayın 32'sinde fatura öde` | task T9 0.80 | − invalidDateTime 0.30 | 0.50 |
| `şubatın 31'inde fatura` | note T10b 0.55 | − invalidDateTime 0.30 | 0.25 |
| (tue_evening) `bugün 3'te teklifi gönder` | reminder T8 0.90 | − ambiguousHourPM 0.05 − pastDue 0.45 | 0.40 |
| (tue_evening) `bu sabah 9'da kalibrasyonu yap` | reminder T8 0.90 | − pastDue 0.45 | 0.45 |
| `dün Ahmet'i aramam gerekiyordu` | task T6 0.90 | − pastDue 0.45 | 0.45 |
| `geçen salı ne oldu` | reminder T8 0.90 | − pastDue 0.45 | 0.45 |
| `Ahmet'i ara ve ayrıca raporu gönder bir de teklifi hazırla` | task T9 0.80 | − multipleItems 0.25 | 0.55 |
| `markete gidince süt al` | task T9 0.80 | − unknownPlace 0.25 | 0.55 |

Borderline (0.60–0.79, confirmation sheet, not Smart Mode): `15.10 kalibrasyon raporu` (0.75, ambiguousDotted),
`3 teklif hazırla` (0.70, unusedNumber), `gelecek hafta müşteri ziyareti planla` (0.80 → auto-save; vague but harmless),
long free text without cue (T10a 0.70).

---|---|
| `toplantı` | single token, no cue (T10b 0.55 − tooShort) |
| `şey` | filler only → title fallback |
| `bana hatırlatma` | negation + needsTime + title fallback |
| `bunu hatırlat` | pronoun-only title + needsTime |
| `yarın salı Ahmet'le toplantı` | yarın = Pazartesi ≠ salı → conflictingDates |
| `her saat su içmeyi hatırlat` | unsupported recurrence |
| `saat 25'te toplantı` | invalid time |
| `ayın 32'sinde fatura öde` | invalid day of month |
| (tue_evening) `bugün 3'te teklifi gönder` | explicit today, 15:00 already passed → pastDue |
| `dün Ahmet'i aramam gerekiyordu` | past date |
| `markete gidince süt al` | unknown place |
| `Ahmet'i ara ve ayrıca raporu gönder bir de teklifi hazırla` | multiple items |
| `geçen salı ne oldu` | past weekday |
| `hatırlat` | cue only, no content, no time |
| `15.10 da 3'te` | invalid mixture: dotted + clock, title empty |

---

## 18. Implementation layout and test plan

```
AsistCore/                       (SwiftPM, swift-tools-version 5.9, platforms iOS 17 / macOS 13; builds on Linux)
  Sources/AsistCore/Parser/
    ParserTypes.swift            §1
    Normalizer.swift             §3
    Tokenizer.swift              §4
    Lexicon.swift                §5, §7.8, §10 cue tables (static let, folded keys)
    TurkishNumbers.swift         §6
    Extractors/ProjectPlace.swift, Recurrence.swift, DateExpr.swift, TimeExpr.swift, Person.swift, Cues.swift
    DateResolver.swift           §8, §9.3
    Classifier.swift             §10
    TitleBuilder.swift           §11
    Confidence.swift             §12
    TurkishDateFormatter.swift   §13
    TurkishParser.swift          orchestration §2
  Tests/AsistCoreTests/
    CorpusTests.swift            §15 (data-driven, parser_corpus.json)
    NormalizerTests.swift        trLower ("IŞIK"→"ışık", "İzmir"→"izmir"), fold, apostrophes, NFC
    NumberTests.swift            every cardinal 1…99 as words, suffixed forms, ordinals, buçuk/çeyrek
    DateResolverTests.swift      each row of §8.3/§8.5 tables for all 7 reference nows
    FormatterTests.swift         §13 examples, numeral suffix table 1…31
    PropertyTests.swift          for 500 generated (weekday, qualifier, hour) combos: due > now unless pastDue flagged;
                                 due minute == spoken minute; title never empty
```

CI (GitHub Actions): `swift test` on `ubuntu-latest` (fast, catches Linux Foundation differences) and on the macOS runner before the
Xcode build. The corpus test is the release gate: 100 % of cases must pass.
