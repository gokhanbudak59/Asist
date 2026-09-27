// App/Store/BackupManager.swift (04 §3.6.4, 03 §9 r25–27, 05a #10/#21/#22, 05b A1) — WP4.
// Non-isolated file operations of the store: protected atomic writes, prev-file copy, daily backups (7 kept),
// pre-import copies, corrupt/partial/newer-writer safety copies and `Asist-acik-isler.txt`.
// Rules: every write uses [.atomic, .completeFileProtectionUntilFirstUserAuthentication] (§9 r37);
// never `FileManager.copyItem`; a safety copy never overwrites an existing file (unique names);
// a READ failure is reported as `.unreadable`, never as corruption (§9 r41).
import Foundation
import AsistCore

/// Result of reading one store file.
enum FileReadResult {
    case absent
    /// I/O error — typically protected data unavailable (device not unlocked since boot). NOT corruption.
    case unreadable(String)
    case bytes(Data)
}

/// A backup file in Documents/Yedekler (daily backup or pre-import copy), newest first in listings.
struct StoredBackup: Identifiable, Equatable {
    let url: URL
    /// "yyyyMMdd"
    let dayKey: String
    /// true = the state saved right before an import (§9 r43), false = daily backup.
    let isPreImport: Bool

    var id: String { url.lastPathComponent }
    var fileName: String { url.lastPathComponent }
}

/// Raw bytes that must exist on disk before the next save may replace the main file (05a #22, D35, 03 §9 r26).
struct SafetyCopy {
    let bytes: Data
    let url: URL
    let label: String
}

enum BackupManager {
    static let dailyBackupsToKeep = 7
    static let preImportCopiesToKeep = 5
    static let protectedWrite: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    /// CFBundleVersion as Int (CI sets it to the run number, D35). 0 = unknown.
    static func currentBuild() -> Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Primitive file access

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func read(_ url: URL) -> FileReadResult {
        guard fileExists(url) else { return .absent }
        do {
            let bytes = try Data(contentsOf: url)
            return .bytes(bytes)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError) {
                return .absent
            }
            return .unreadable(describe(error))
        }
    }

    static func write(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: protectedWrite)
    }

    /// `url` itself when free, else "<name>-2.json", "<name>-3.json", … (an existing copy is never overwritten).
    static func uniqueURL(for url: URL) -> URL {
        guard fileExists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix: String = ext.isEmpty ? "" : "." + ext
        var candidate = url
        for counter in 2...99 {
            candidate = folder.appendingPathComponent(base + "-" + String(counter) + suffix)
            if !fileExists(candidate) {
                return candidate
            }
        }
        return candidate
    }

    // MARK: - Safety copies (corrupt / partial / newer writer)

    /// Writes `copy` under a unique name. Returns nil on success, the error otherwise (caller keeps it queued).
    static func writeSafetyCopy(_ copy: SafetyCopy) -> Error? {
        let target = uniqueURL(for: copy.url)
        do {
            try write(copy.bytes, to: target)
            AsistLog.info("Güvenlik kopyası yazıldı (" + copy.label + "): " + target.lastPathComponent, .store)
            return nil
        } catch {
            AsistLog.error("Güvenlik kopyası yazılamadı (" + copy.label + "): " + describe(error), .store)
            return error
        }
    }

    // MARK: - Previous file (05a #21)

    /// Copies the current main file to `previousFile` with `Data` + protected atomic write (never `copyItem`).
    /// The caller only calls this when the main file was verified in this session. Failures are logged only.
    @discardableResult
    static func copyMainToPrevious(_ files: StoreFiles) -> Bool {
        switch read(files.dataFile) {
        case .absent:
            return true
        case .unreadable(let reason):
            AsistLog.error("Önceki sürüm kopyası alınamadı (okuma): " + reason, .store)
            return false
        case .bytes(let bytes):
            do {
                try write(bytes, to: files.previousFile)
                return true
            } catch {
                AsistLog.error("Önceki sürüm kopyası yazılamadı: " + describe(error), .store)
                return false
            }
        }
    }

    // MARK: - Backups

    /// Daily backups and pre-import copies in Documents/Yedekler, newest first (by the date in the name).
    static func listBackups(_ files: StoreFiles) -> [StoredBackup] {
        let manager = FileManager.default
        let urls: [URL]
        do {
            urls = try manager.contentsOfDirectory(at: files.backupDirectory, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])
        } catch {
            if fileExists(files.backupDirectory) {
                AsistLog.error("Yedek klasörü listelenemedi: " + describe(error), .store)
            }
            return []
        }
        var result: [StoredBackup] = []
        for url in urls {
            let name = url.lastPathComponent
            if let day = StoreFiles.dayKey(ofDailyBackupName: name) {
                result.append(StoredBackup(url: url, dayKey: day, isPreImport: false))
            } else if let day = StoreFiles.dayKey(ofPreImportName: name) {
                result.append(StoredBackup(url: url, dayKey: day, isPreImport: true))
            }
        }
        result.sort { lhs, rhs in lhs.fileName > rhs.fileName }
        return result
    }

    /// Writes the daily backup for `dayKey` (same bytes as the main file) and prunes old copies.
    @discardableResult
    static func writeDailyBackup(_ bytes: Data, dayKey: String, files: StoreFiles) -> Bool {
        let url = files.dailyBackupURL(dayKey: dayKey)
        do {
            try write(bytes, to: url)
            AsistLog.info("Günlük yedek yazıldı: " + url.lastPathComponent, .store)
        } catch {
            AsistLog.error("Günlük yedek yazılamadı: " + describe(error), .store)
            return false
        }
        pruneBackups(files)
        return true
    }

    /// Writes the state before an import (§9 r43). false = not written → the import must not proceed.
    static func writePreImportCopy(_ bytes: Data, now: Date, files: StoreFiles) -> Bool {
        files.createDirectories()
        let url = uniqueURL(for: files.preImportCopyURL(now: now))
        do {
            try write(bytes, to: url)
            AsistLog.info("İçe aktarma öncesi yedek yazıldı: " + url.lastPathComponent, .store)
        } catch {
            AsistLog.error("İçe aktarma öncesi yedek yazılamadı: " + describe(error), .store)
            return false
        }
        pruneBackups(files)
        return true
    }

    /// Keeps the newest 7 daily backups and the newest 5 pre-import copies; other files are never touched.
    static func pruneBackups(_ files: StoreFiles) {
        let all = listBackups(files)
        let daily = all.filter { backup in !backup.isPreImport }
        let preImport = all.filter { backup in backup.isPreImport }
        var obsolete: [StoredBackup] = []
        if daily.count > dailyBackupsToKeep {
            obsolete.append(contentsOf: daily[dailyBackupsToKeep...])
        }
        if preImport.count > preImportCopiesToKeep {
            obsolete.append(contentsOf: preImport[preImportCopiesToKeep...])
        }
        for backup in obsolete {
            do {
                try FileManager.default.removeItem(at: backup.url)
                AsistLog.info("Eski yedek silindi: " + backup.fileName, .store)
            } catch {
                AsistLog.error("Eski yedek silinemedi: " + backup.fileName + " " + describe(error), .store)
            }
        }
    }

    /// Highest writer build among the D35 copies that is newer than `currentBuild` (keeps the red banner visible
    /// while an older build keeps running after the copy was taken). nil = none / build unknown.
    static func newestNewerWriterBuild(files: StoreFiles, currentBuild: Int) -> Int? {
        guard currentBuild > 0 else { return nil }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: files.backupDirectory,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            return nil
        }
        var best: Int? = nil
        for url in urls {
            guard let build = StoreFiles.build(ofNewerWriterName: url.lastPathComponent), build > currentBuild else {
                continue
            }
            if let current = best {
                best = max(current, build)
            } else {
                best = build
            }
        }
        return best
    }

    // MARK: - Human-readable open items (05b A1)

    static func writeOpenItemsText(_ text: String, files: StoreFiles) {
        let bytes = Data(text.utf8)
        do {
            try write(bytes, to: files.openItemsTextFile)
        } catch {
            AsistLog.error("Açık işler dosyası yazılamadı: " + describe(error), .store)
        }
    }

    // MARK: - Errors

    /// NSFileWriteOutOfSpaceError or ENOSPC (also as the underlying error).
    static func isDiskFull(_ error: Error) -> Bool {
        let ns = error as NSError
        if isDiskFullError(ns) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDiskFullError(underlying)
        }
        return false
    }

    /// "NSCocoaErrorDomain 257" — domain and code only (never paths or content).
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return ns.domain + " " + String(ns.code)
    }

    private static func isDiskFullError(_ ns: NSError) -> Bool {
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXErrorCode.ENOSPC.rawValue) {
            return true
        }
        return false
    }
}

// MARK: - Store conveniences for Ayarlar › Veri (WP11)

extension DataStore {
    /// Daily backups and pre-import copies in Documents/Yedekler, newest first.
    func availableBackups() -> [StoredBackup] {
        BackupManager.listBackups(files)
    }

    /// "Yedekten geri yükle" = import `.replace` from that file (the current state is saved first, §9 r43).
    /// false = file unreadable, not an Asist file, or not persisted.
    func restore(from backup: StoredBackup) -> Bool {
        switch BackupManager.read(backup.url) {
        case .absent:
            AsistLog.error("Geri yükleme: yedek bulunamadı " + backup.fileName, .store)
            return false
        case .unreadable(let reason):
            AsistLog.error("Geri yükleme: yedek okunamadı " + backup.fileName + " " + reason, .store)
            return false
        case .bytes(let bytes):
            return importData(bytes, mode: .replace)
        }
    }
}
