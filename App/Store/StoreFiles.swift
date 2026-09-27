// API: App/Store/StoreFiles.swift
// WP0 STUB (04 §3.6.4) — replaced by WP4. Computes the file URLs only; directory creation is WP4's job.
import Foundation
import AsistCore

struct StoreFiles {
    let directory: URL          // Application Support/Asist/
    let dataFile: URL           // asist-data.json
    let previousFile: URL       // asist-data.prev.json  (last VERIFIED version before the latest write)
    let backupDirectory: URL    // Documents/Yedekler/   (visible in Files app, D25)
    let openItemsTextFile: URL  // Documents/Yedekler/Asist-acik-isler.txt (05b A1)

    /// Creates directories if needed (never throws; logs).
    static func standard() -> StoreFiles {
        let manager = FileManager.default
        let support: URL = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let documents: URL = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = support.appendingPathComponent("Asist", isDirectory: true)
        let backups = documents.appendingPathComponent("Yedekler", isDirectory: true)
        return StoreFiles(directory: directory,
                          dataFile: directory.appendingPathComponent("asist-data.json"),
                          previousFile: directory.appendingPathComponent("asist-data.prev.json"),
                          backupDirectory: backups,
                          openItemsTextFile: backups.appendingPathComponent("Asist-acik-isler.txt"))
    }

    /// "asist-data.corrupt-yyyyMMdd-HHmmss.json" next to dataFile.
    func corruptCopyURL(now: Date) -> URL {
        let calendar = AppTime.calendar
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let day: String = AsistCalendar.dayKey(now, calendar: calendar)
        let hour: String = AsistCalendar.pad(parts.hour ?? 0, 2)
        let minute: String = AsistCalendar.pad(parts.minute ?? 0, 2)
        let second: String = AsistCalendar.pad(parts.second ?? 0, 2)
        let name: String = "asist-data.corrupt-" + day + "-" + hour + minute + second + ".json"
        return directory.appendingPathComponent(name)
    }

    /// "asist-yedek-yyyy-MM-dd.json"
    func dailyBackupURL(dayKey: String) -> URL {
        backupDirectory.appendingPathComponent("asist-yedek-" + dayKey + ".json")
    }

    /// Documents/Yedekler/asist-data.yeni-surum-<build>.json (D35)
    func newerWriterCopyURL(build: Int) -> URL {
        backupDirectory.appendingPathComponent("asist-data.yeni-surum-" + String(build) + ".json")
    }
}
