// API: App/Store/StoreFiles.swift (04 §3.6.4) — WP4.
// File locations of the persistent store. Pure value type; the only side effect is directory creation in
// `standard()` (never throws, only logs). Never references AppEnvironment.shared (§4.1 r13).
import Foundation
import AsistCore

struct StoreFiles {
    let directory: URL          // Application Support/Asist/
    let dataFile: URL           // asist-data.json
    let previousFile: URL       // asist-data.prev.json  (last VERIFIED version before the latest write)
    let backupDirectory: URL    // Documents/Yedekler/   (visible in Files app, D25)
    let openItemsTextFile: URL  // Documents/Yedekler/Asist-acik-isler.txt (05b A1)

    /// "asist-yedek-" — prefix of daily backups and pre-import copies (both in `backupDirectory`).
    static let backupPrefix = "asist-yedek-"
    /// Suffix of the safety copy written before every import (see `preImportCopyURL(now:)`).
    static let preImportSuffix = "-ice-aktarma-oncesi.json"
    /// Prefix of the D35 copies ("asist-data.yeni-surum-<build>.json").
    static let newerWriterPrefix = "asist-data.yeni-surum-"

    /// Creates directories if needed (never throws; logs).
    static func standard() -> StoreFiles {
        let manager = FileManager.default
        let support: URL = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let documents: URL = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = support.appendingPathComponent("Asist", isDirectory: true)
        let backups = documents.appendingPathComponent("Yedekler", isDirectory: true)
        let files = StoreFiles(directory: directory,
                               dataFile: directory.appendingPathComponent("asist-data.json"),
                               previousFile: directory.appendingPathComponent("asist-data.prev.json"),
                               backupDirectory: backups,
                               openItemsTextFile: backups.appendingPathComponent("Asist-acik-isler.txt"))
        files.createDirectories()
        return files
    }

    /// Idempotent; failures are logged only (the next write reports the real error).
    func createDirectories() {
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [
            FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        let targets: [URL] = [directory, backupDirectory]
        for target in targets {
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: target.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    AsistLog.error("Klasör yolu bir dosya: " + target.lastPathComponent, .store)
                }
                continue
            }
            do {
                try manager.createDirectory(at: target, withIntermediateDirectories: true, attributes: attributes)
            } catch {
                let name: String = target.lastPathComponent
                let reason: String = BackupManager.describe(error)
                AsistLog.error("Klasör oluşturulamadı: " + name + " (" + reason + ")", .store)
            }
        }
    }

    /// "asist-data.corrupt-yyyyMMdd-HHmmss.json" next to dataFile.
    func corruptCopyURL(now: Date) -> URL {
        let name: String = "asist-data.corrupt-" + StoreFiles.timestamp(now) + ".json"
        return directory.appendingPathComponent(name)
    }

    /// "asist-yedek-yyyy-MM-dd.json". Accepts an `AsistCalendar.dayKey` ("yyyyMMdd") or an already dashed day.
    func dailyBackupURL(dayKey: String) -> URL {
        backupDirectory.appendingPathComponent(StoreFiles.backupPrefix + StoreFiles.dashedDay(dayKey) + ".json")
    }

    /// Documents/Yedekler/asist-data.yeni-surum-<build>.json (D35)
    func newerWriterCopyURL(build: Int) -> URL {
        backupDirectory.appendingPathComponent(StoreFiles.newerWriterPrefix + String(build) + ".json")
    }

    /// Documents/Yedekler/asist-yedek-yyyy-MM-dd-HHmmss-ice-aktarma-oncesi.json — the state before an import
    /// (§9 r43). A separate name so that restoring *from* today's daily backup never overwrites that backup.
    func preImportCopyURL(now: Date) -> URL {
        let stamp: String = StoreFiles.timestamp(now)                      // yyyyMMdd-HHmmss
        let day: String = StoreFiles.dashedDay(String(stamp.prefix(8)))
        let time: String = String(stamp.suffix(6))
        let name: String = StoreFiles.backupPrefix + day + "-" + time + StoreFiles.preImportSuffix
        return backupDirectory.appendingPathComponent(name)
    }

    // MARK: - Name helpers

    /// "yyyyMMdd-HHmmss" in the app calendar (device time zone).
    static func timestamp(_ date: Date) -> String {
        let calendar = AppTime.calendar
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let day: String = AsistCalendar.dayKey(date, calendar: calendar)
        let hour: String = AsistCalendar.pad(parts.hour ?? 0, 2)
        let minute: String = AsistCalendar.pad(parts.minute ?? 0, 2)
        let second: String = AsistCalendar.pad(parts.second ?? 0, 2)
        return day + "-" + hour + minute + second
    }

    /// "20260927" → "2026-09-27"; any other input is returned unchanged.
    static func dashedDay(_ dayKey: String) -> String {
        let chars: [Character] = Array(dayKey)
        guard chars.count == 8 else { return dayKey }
        for ch in chars where !(ch.isASCII && ch.isNumber) {
            return dayKey
        }
        let year = String(chars[0..<4])
        let month = String(chars[4..<6])
        let day = String(chars[6..<8])
        return year + "-" + month + "-" + day
    }

    /// "2026-09-27" → "20260927"; nil when the text is not a dashed day.
    static func compactDay(_ dashed: String) -> String? {
        let chars: [Character] = Array(dashed)
        guard chars.count == 10, chars[4] == "-", chars[7] == "-" else { return nil }
        var digits = ""
        for (index, ch) in chars.enumerated() where index != 4 && index != 7 {
            guard ch.isASCII && ch.isNumber else { return nil }
            digits.append(ch)
        }
        return digits
    }

    /// Day key ("yyyyMMdd") of a daily backup file name "asist-yedek-yyyy-MM-dd.json"; nil for any other name.
    static func dayKey(ofDailyBackupName name: String) -> String? {
        guard name.hasPrefix(backupPrefix), name.hasSuffix(".json") else { return nil }
        let core = String(name.dropFirst(backupPrefix.count).dropLast(5))
        return compactDay(core)
    }

    /// Day key ("yyyyMMdd") of a pre-import copy name; nil for any other name.
    static func dayKey(ofPreImportName name: String) -> String? {
        guard name.hasPrefix(backupPrefix), name.hasSuffix(preImportSuffix) else { return nil }
        let core = String(name.dropFirst(backupPrefix.count))
        return compactDay(String(core.prefix(10)))
    }

    /// Writer build of a D35 copy name ("asist-data.yeni-surum-57.json", "asist-data.yeni-surum-57-2.json").
    static func build(ofNewerWriterName name: String) -> Int? {
        guard name.hasPrefix(newerWriterPrefix), name.hasSuffix(".json") else { return nil }
        let core = String(name.dropFirst(newerWriterPrefix.count).dropLast(5))
        let digits = core.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return Int(String(digits))
    }
}
