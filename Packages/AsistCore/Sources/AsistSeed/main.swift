// CI-only executable (simulator smoke test, .github/workflows/ci.yml job `simulator`).
// Builds a realistic Asist document for a busy Turkish automation manager by running Turkish sentences through
// TurkishParser + ItemFactory (the app's own capture path), then writes it exactly like DataStore.save():
// JSONEncoder, `.iso8601` dates, `[.sortedKeys]`, file name `asist-data.json` (App/Store/ImportExport.swift
// `StoreCoding`, App/Store/StoreFiles.swift). The app reads it from
// <data container>/Library/Application Support/Asist/asist-data.json.
//
// Usage:
//   swift run AsistSeed --now 2026-09-27T06:41:00Z --out <dir>/asist-data.json \
//       [--tz Europe/Istanbul] [--pretty-copy <path>] [--ids <path>]
//   --now          the simulator's current time (ISO 8601); every item is placed relative to it
//   --tz           IANA time zone of the simulator (default: this machine's zone = the simulator's zone)
//   --pretty-copy  also write a pretty-printed copy (for humans; the app accepts both)
//   --ids          write "DETAY_ID=<uuid>" (item for the detail screenshot) and counts as key=value lines
// Exit codes: 0 ok, 1 write/verification failure, 2 usage error.
//
// Pure Foundation + AsistCore: it must also build on Linux (core-tests job runs `swift build --build-tests`).
import Foundation
import AsistCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Scenario

/// State the user would have produced after the capture (ticking, snoozing, the "Zamanı belirsiz" chip …).
enum SeedAdjustment {
    case complete(minutesAgo: Int)
    case snooze(minutesFromNow: Int, count: Int)
    case checklist(templateID: String, doneCount: Int)
    case clearDue
    case needsReview
    case detailTarget
}

struct SeedEntry {
    let text: String
    /// Capture time = now − minutesAgo. It is the parse reference, exactly like a capture made back then.
    let minutesAgo: Int
    let source: CaptureSource
    /// true = in-app capture (card can ask); false = Siri / Shortcut (headless, may be flagged "Emin değilim").
    let interactive: Bool
    let adjustments: [SeedAdjustment]

    init(_ text: String, minutesAgo: Int, source: CaptureSource = .voice, interactive: Bool = true,
         adjustments: [SeedAdjustment] = []) {
        self.text = text
        self.minutesAgo = minutesAgo
        self.source = source
        self.interactive = interactive
        self.adjustments = adjustments
    }
}

enum SeedScenario {
    /// Relative offsets keep the screens realistic at any time of day (the simulator clock is the CI clock).
    static let entries: [SeedEntry] = [
        // GECİKENLER — kritik, kişi (hero card): "hemen" = +5 min, said 95 min ago → 90 min overdue.
        SeedEntry("çok acil Ahmet Bey'i hemen ara", minutesAgo: 95),
        // GECİKENLER — önemli, proje Hat 3: due 1 h ago.
        SeedEntry("önemli: 3 saat sonra Hat 3 servo parametrelerini yedekle", minutesAgo: 240, source: .keyboard),
        // BUGÜN — was overdue, snoozed twice, next nag in 25 min (proje Arka Cep).
        SeedEntry("yarım saat sonra arka cep hattında pnömatik kaçağı kontrol et", minutesAgo: 100,
                  adjustments: [.snooze(minutesFromNow: 25, count: 2)]),
        // BUGÜN — kişi, in ~2 hours.
        SeedEntry("2 saat sonra Mehmet Bey'i ara", minutesAgo: 10),
        // BUGÜN — etkinlik (toplantı → isEvent, 15 min pre-alert), proje Kaynak Robotu.
        SeedEntry("4 saat sonra Kaynak Robotu bakım toplantısı", minutesAgo: 20),
        // Tekrarlayan — every day 08:00.
        SeedEntry("her gün saat 8'de günlük üretim raporunu kontrol et", minutesAgo: 2),
        // TAKİP — kişi, asked yesterday "yarın takip et" → today at the follow-up ask time.
        SeedEntry("Ayşe Hanım'dan fiyat listesini bekliyorum yarın takip et", minutesAgo: 1_440),
        // Takip — kişi, deadline Friday 15:00.
        SeedEntry("Burak'tan cuma 3'e kadar test sonuçlarını bekliyorum", minutesAgo: 30),
        // Notlar — proje Hat 3 / Arka Cep.
        SeedEntry("not al Hat 3 robot hücresinde kapı sensörü gevşek", minutesAgo: 1_560),
        SeedEntry("not et Arka Cep müşterisi ekim sonunda kabul istiyor", minutesAgo: 3_000),
        // Görev — saatli, kişi + proje.
        SeedEntry("görev: yarın 3'te Ahmet'le Hat 3 bütçesini konuş", minutesAgo: 5, source: .keyboard),
        // Görev — saatsiz, bugün (D33 today policy).
        SeedEntry("görev ekle Hat 3 HMI ekranlarını güncelle", minutesAgo: 3),
        // ZAMANI BELİRSİZ — the user tapped "Zamanı belirsiz" on the card.
        SeedEntry("yapılacaklara ekle PLC lisanslarını yenile", minutesAgo: 1_800, source: .keyboard,
                  adjustments: [.clearDue]),
        // Görev + FAT kontrol listesi (3/7 done) — the item detail screenshot.
        SeedEntry("görev: cuma günü Arka Cep FAT hazırlığını tamamla", minutesAgo: 240,
                  adjustments: [.checklist(templateID: "fat", doneCount: 3), .detailTarget]),
        // YAKLAŞAN — kritik etkinlik tomorrow 08:00.
        SeedEntry("sakın unutma yarın 8'de tedarikçi denetimi var", minutesAgo: 15),
        // YAKLAŞAN — önemli, tomorrow 10:00.
        SeedEntry("önemli: yarın 10'da bütçe onayı", minutesAgo: 60, source: .keyboard),
        // Tamamlanan (Bu hafta n iş bitti).
        SeedEntry("1 saat sonra Kaynak Robotu torç temizliğini kontrol et", minutesAgo: 300,
                  adjustments: [.complete(minutesAgo: 200)]),
        // EMİN OLAMADIKLARIM — headless Siri capture nobody confirmed yet.
        SeedEntry("Arka Cep sevkiyat evrakları", minutesAgo: 45, source: .siri, interactive: false,
                  adjustments: [.needsReview])
    ]

    /// Projects with spoken aliases (fed to the parser like the app does).
    static func projects(now: Date) -> [Project] {
        let created = SeedBuilder.minutesBefore(now, 21 * 1_440)
        return [
            Project(id: SeedBuilder.seedUUID(group: 2, 1), name: "Arka Cep", aliases: ["Arka Cep Ağzı Kapama"],
                    color: .blue, createdAt: created),
            Project(id: SeedBuilder.seedUUID(group: 2, 2), name: "Hat 3", aliases: ["Üçüncü hat"],
                    color: .orange, createdAt: created),
            Project(id: SeedBuilder.seedUUID(group: 2, 3), name: "Kaynak Robotu", aliases: ["Kaynak hücresi"],
                    color: .purple, createdAt: created)
        ]
    }
}

// MARK: - Builder

struct SeedResult {
    var data: AppData
    var detailID: UUID?
    var report: [String]
}

enum SeedBuilder {
    static func build(now: Date, calendar: Calendar) -> SeedResult {
        var settings = AppSettings()
        settings.userName = "Gökhan"
        settings.onboardingCompleted = true

        let projects = SeedScenario.projects(now: now)
        let parserSettings = ParserSettings(settings: settings, projects: projects, places: [])
        let parser = TurkishParser(settings: parserSettings, calendar: calendar)

        var items: [Item] = []
        var report: [String] = []
        var detailID: UUID? = nil
        for (offset, entry) in SeedScenario.entries.enumerated() {
            let number = offset + 1
            let reference = minutesBefore(now, entry.minutesAgo)
            let result = parser.parse(entry.text, now: reference)
            let context = CaptureContext(settings: settings, projects: projects, places: [],
                                         interactive: entry.interactive)
            guard let proposal = ItemFactory.proposal(from: result, source: entry.source, context: context,
                                                      now: reference, calendar: calendar) else {
                report.append(label(number) + " KOMUT olarak anlaşıldı, kayıt oluşmadı: " + entry.text)
                continue
            }
            var item = proposal.item
            item.id = seedUUID(group: 1, number)
            for adjustment in entry.adjustments {
                apply(adjustment, to: &item, number: number, now: now, calendar: calendar)
                if case .detailTarget = adjustment {
                    detailID = item.id
                }
            }
            items.append(item)
            report.append(describe(number, entry: entry, item: item, result: result, level: proposal.level,
                                   projects: projects, calendar: calendar))
        }

        var meta = AppMeta()
        meta.createdAt = minutesBefore(now, 21 * 1_440)
        meta.installDate = minutesBefore(now, 2 * 1_440)
        meta.lastSavedAt = now
        meta.writerBuild = 0                      // "unknown" — never newer than the running build (D35)

        let data = AppData(schemaVersion: AppData.currentSchemaVersion, items: items, projects: projects,
                           places: [], settings: settings, meta: meta)

        let snapshot = AgendaBuilder.snapshot(items: items, now: now, settings: settings, calendar: calendar)
        var line = "Bugün ekranı: geciken=" + String(snapshot.overdue.count)
        line += ", emin olamadıklarım=" + String(snapshot.review.count)
        line += ", bugün=" + String(snapshot.today.count)
        line += ", takip=" + String(snapshot.followUps.count)
        line += ", yaklaşan=" + String(snapshot.upcomingTotal)
        line += ", zamanı belirsiz=" + String(snapshot.unscheduled.count)
        line += ", bu hafta biten=" + String(snapshot.doneThisWeek)
        report.append(line)

        return SeedResult(data: data, detailID: detailID ?? items.first?.id, report: report)
    }

    /// Deterministic ids ("5EED0001-0000-4000-8000-000000000007"), stable across runs for screenshot links.
    static func seedUUID(group: Int, _ index: Int) -> UUID {
        let text = "5EED" + AsistCalendar.pad(group, 4) + "-0000-4000-8000-" + AsistCalendar.pad(index, 12)
        return UUID(uuidString: text) ?? UUID()
    }

    /// Whole minute `minutes` before `now` (store instants are whole minutes, 04 §3.1).
    static func minutesBefore(_ now: Date, _ minutes: Int) -> Date {
        AsistCalendar.floorToMinute(now.addingTimeInterval(-60.0 * Double(max(0, minutes))))
    }

    static func apply(_ adjustment: SeedAdjustment, to item: inout Item, number: Int, now: Date,
                      calendar: Calendar) {
        switch adjustment {
        case .complete(let minutesAgo):
            // DataStore.markDone semantics for a non-recurring item.
            let at = max(minutesBefore(now, minutesAgo), item.createdAt)
            item.status = .done
            item.completedAt = at
            item.updatedAt = at
            item.appendHistory(.done, at: at)
        case .snooze(let minutesFromNow, let count):
            // DataStore.snooze semantics: whole-minute target, snoozeCount, history detail "28 Eyl 09:00".
            let times = max(1, count)
            let target = AsistCalendar.ceilToMinute(now.addingTimeInterval(60.0 * Double(max(1, minutesFromNow))))
            var stamps: [Date] = []
            for step in 0..<times {
                stamps.append(max(item.createdAt, minutesBefore(now, 15 * (times - step))))
            }
            for (index, at) in stamps.enumerated() {
                let chosen: Date = index + 1 < stamps.count ? stamps[index + 1] : target
                item.appendHistory(.snoozed, at: at, detail: historyStamp(chosen, calendar: calendar))
            }
            item.snoozedUntil = target
            item.snoozeCount = times
            item.updatedAt = stamps.last ?? now
        case .checklist(let templateID, let doneCount):
            guard let template = ChecklistTemplates.template(id: templateID) else { return }
            var entries = ChecklistTemplates.entries(for: template)
            for index in entries.indices {
                entries[index].id = seedUUID(group: 3, number * 100 + index + 1)
                entries[index].done = index < doneCount
            }
            item.checklist = entries
            let at = max(item.createdAt, minutesBefore(now, 30))
            item.appendHistory(.edited, at: at, detail: "Kontrol listesi: " + template.name)
            if item.updatedAt < at {
                item.updatedAt = at
            }
        case .clearDue:
            item.dueDate = nil
            item.hasTime = false
            item.isEvent = false
            item.snoozedUntil = nil
            item.leadTimesMinutes = []
        case .needsReview:
            item.needsReview = true
        case .detailTarget:
            break
        }
    }

    /// Same text as DataStore's history stamp ("28 Eyl 09:00").
    static func historyStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let monthIndex = min(11, max(0, (parts.month ?? 1) - 1))
        let names = TurkishDateFormatter.monthsShort
        let monthName: String = monthIndex < names.count ? names[monthIndex] : String(monthIndex + 1)
        return String(parts.day ?? 1) + " " + monthName + " " + TurkishDateFormatter.time(date, calendar: calendar)
    }

    // MARK: Report

    static func label(_ number: Int) -> String {
        "[" + AsistCalendar.pad(number, 2) + "]"
    }

    /// "2026-09-27 14:05" in `calendar`'s time zone, "-" for nil.
    static func stamp(_ date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "-" }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = AsistCalendar.pad(c.year ?? 0, 4) + "-" + AsistCalendar.pad(c.month ?? 0, 2) + "-"
            + AsistCalendar.pad(c.day ?? 0, 2)
        return day + " " + AsistCalendar.pad(c.hour ?? 0, 2) + ":" + AsistCalendar.pad(c.minute ?? 0, 2)
    }

    static func describe(_ number: Int, entry: SeedEntry, item: Item, result: ParseResult, level: ConfirmationLevel,
                         projects: [Project], calendar: Calendar) -> String {
        let projectName: String = projects.first(where: { $0.id == item.projectID })?.name ?? "-"
        let kindText: String = item.kind.rawValue + (item.isEvent ? "/etkinlik" : "")
        let dueText: String = stamp(item.dueDate, calendar: calendar) + (item.hasTime ? "" : " (saatsiz)")
        let confidence: Int = result.confidence.isFinite ? Int((result.confidence * 100).rounded()) : -1
        let flags: String = result.flags.map { $0.rawValue }.sorted().joined(separator: ",")
        var parts: [String] = [label(number), kindText, "başlık=" + item.title, "vade=" + dueText]
        if let snoozed = item.snoozedUntil {
            parts.append("ertelendi=" + stamp(snoozed, calendar: calendar))
        }
        parts.append("öncelik=" + item.priority.code)
        parts.append("kişi=" + (item.person ?? "-"))
        parts.append("proje=" + projectName)
        parts.append("tekrar=" + (item.recurrence?.frequency.rawValue ?? "-"))
        parts.append("durum=" + item.status.rawValue + (item.needsReview ? "/emin-degil" : ""))
        if !item.checklist.isEmpty {
            let done = item.checklist.filter { $0.done }.count
            parts.append("liste=" + String(done) + "/" + String(item.checklist.count))
        }
        parts.append("güven=%" + String(confidence))
        parts.append("düzey=" + level.rawValue)
        parts.append("bayrak=" + (flags.isEmpty ? "-" : flags))
        parts.append("söz=\"" + entry.text + "\"")
        return parts.joined(separator: " | ")
    }
}

// MARK: - Writer (mirrors App/Store/ImportExport.swift `StoreCoding` — frozen, 04 §3.1 / §9 r36)

enum SeedWriter {
    static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func write(_ bytes: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true, attributes: nil)
        try bytes.write(to: url, options: [.atomic])
    }

    /// The checks DataStore.load() applies before trusting a file: it decodes, lenient decoding dropped no array
    /// element (05a #22 partial-recovery check), it is not a newer writer (D35) and onboarding is done.
    static func verify(_ bytes: Data, expected: AppData) -> (errors: [String], warnings: [String]) {
        var errors: [String] = []
        var warnings: [String] = []
        let decoded: AppData
        do {
            decoded = try makeDecoder().decode(AppData.self, from: bytes)
        } catch {
            errors.append("belge çözülemedi: " + String(describing: error))
            return (errors: errors, warnings: warnings)
        }
        if decoded.items.count != expected.items.count {
            errors.append("kayıt sayısı " + String(expected.items.count) + " → " + String(decoded.items.count))
        }
        if decoded.projects.count != expected.projects.count {
            errors.append("proje sayısı " + String(expected.projects.count) + " → " + String(decoded.projects.count))
        }
        if let object = try? JSONSerialization.jsonObject(with: bytes, options: []),
           let raw = object as? [String: Any] {
            let rawItems: Int = (raw["items"] as? [Any])?.count ?? -1
            let rawProjects: Int = (raw["projects"] as? [Any])?.count ?? -1
            if rawItems != decoded.items.count || rawProjects != decoded.projects.count {
                errors.append("ham JSON ile çözülen belge farklı (uygulama 'kısmi kurtarma' sayar)")
            }
        } else {
            errors.append("en üst düzey JSON nesnesi değil")
        }
        if decoded.meta.writerBuild != 0 {
            errors.append("writerBuild 0 değil: " + String(decoded.meta.writerBuild))
        }
        if !decoded.settings.onboardingCompleted {
            errors.append("settings.onboardingCompleted false")
        }
        if decoded != expected {
            warnings.append("çözülen belge üretilenle birebir aynı değil (lenient decode değer düzeltti)")
        }
        return (errors: errors, warnings: warnings)
    }
}

// MARK: - Command line

enum SeedCommand {
    static let usage = "Kullanım: AsistSeed --now <ISO 8601, ör. 2026-09-27T06:41:00Z> --out <asist-data.json> "
        + "[--tz <IANA saat dilimi>] [--pretty-copy <yol>] [--ids <yol>]"

    static func run(_ arguments: [String]) -> Int32 {
        let known: Set<String> = ["--now", "--out", "--tz", "--pretty-copy", "--ids"]
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            if key == "-h" || key == "--help" {
                print(usage)
                return 0
            }
            guard known.contains(key) else {
                printError("Bilinmeyen argüman: " + key)
                printError(usage)
                return 2
            }
            guard index + 1 < arguments.count else {
                printError("Değer eksik: " + key)
                return 2
            }
            options[key] = arguments[index + 1]
            index += 2
        }

        guard let outPath = options["--out"], !outPath.isEmpty else {
            printError("--out gerekli")
            printError(usage)
            return 2
        }
        let now: Date
        if let text = options["--now"] {
            guard let parsed = parseISO8601(text) else {
                printError("--now okunamadı (ISO 8601 bekleniyor, ör. 2026-09-27T06:41:00Z): " + text)
                return 2
            }
            now = AsistCalendar.floorToMinute(parsed)
        } else {
            now = AsistCalendar.floorToMinute(Date())
            printError("UYARI: --now verilmedi; bu makinenin saati kullanılıyor")
        }
        let timeZone: TimeZone
        if let name = options["--tz"] {
            guard let zone = TimeZone(identifier: name) else {
                printError("Bilinmeyen saat dilimi: " + name)
                return 2
            }
            timeZone = zone
        } else {
            timeZone = TimeZone.current
        }
        let calendar = AsistCalendar.make(timeZone: timeZone)

        let seed = SeedBuilder.build(now: now, calendar: calendar)
        print("AsistSeed: now=" + SeedBuilder.stamp(now, calendar: calendar) + " tz=" + timeZone.identifier
              + " kayıt=" + String(seed.data.items.count) + " proje=" + String(seed.data.projects.count))
        for line in seed.report {
            print(line)
        }

        let bytes: Data
        let prettyBytes: Data
        do {
            bytes = try SeedWriter.makeEncoder(pretty: false).encode(seed.data)
            prettyBytes = try SeedWriter.makeEncoder(pretty: true).encode(seed.data)
        } catch {
            printError("HATA: kodlanamadı: " + String(describing: error))
            return 1
        }

        let check = SeedWriter.verify(bytes, expected: seed.data)
        for warning in check.warnings {
            printError("UYARI: " + warning)
        }
        if !check.errors.isEmpty {
            for problem in check.errors {
                printError("HATA: " + problem)
            }
            return 1
        }

        let detailText: String = seed.detailID?.uuidString ?? ""
        var idsText = "DETAY_ID=" + detailText + "\n"
        idsText += "KAYIT_SAYISI=" + String(seed.data.items.count) + "\n"
        idsText += "PROJE_SAYISI=" + String(seed.data.projects.count) + "\n"
        do {
            try SeedWriter.write(bytes, to: outPath)
            if let prettyPath = options["--pretty-copy"], !prettyPath.isEmpty {
                try SeedWriter.write(prettyBytes, to: prettyPath)
            }
            if let idsPath = options["--ids"], !idsPath.isEmpty {
                try SeedWriter.write(Data(idsText.utf8), to: idsPath)
            }
        } catch {
            printError("HATA: yazılamadı: " + String(describing: error))
            return 1
        }
        print("DETAY_ID=" + detailText)
        print("Yazıldı: " + outPath + " (" + String(bytes.count) + " bayt)")
        return 0
    }

    /// Parsed with the app's own date strategy (JSONDecoder `.iso8601`), so any accepted value is one the app
    /// would also read.
    static func parseISO8601(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\""), !trimmed.contains("\\") else { return nil }
        let json = "[\"" + trimmed + "\"]"
        guard let dates = try? SeedWriter.makeDecoder().decode([Date].self, from: Data(json.utf8)) else { return nil }
        return dates.first
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

let seedExitCode: Int32 = SeedCommand.run(ProcessInfo.processInfo.arguments)
exit(seedExitCode)
