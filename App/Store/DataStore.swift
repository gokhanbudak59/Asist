// API: App/Store/DataStore.swift (04 §3.6.4) — WP4.
// The single persistent store: one JSON document (`asist-data.json`), synchronous atomic protected writes.
// Data safety rules (the most expensive bug class, §9 r41–r52):
//  • nothing is ever written before the file was actually READ (or confirmed absent) — `isLoaded`;
//  • a read failure (device locked since boot) is never treated as corruption;
//  • unreadable / partially decoded / newer-build files are copied aside before the first save;
//  • mutators persist synchronously and report "not persisted" as nil / false (05a #3);
//  • only real changes are saved and emitted (05a #5).
import Foundation
import Observation
import UIKit
import AsistCore

enum StoreChange: String {
    case items, settings, projects, places, meta, all
}

enum StoreLoadIssue: Equatable {
    case restoredFromPrevious                 // main file unreadable → prev file used
    case restoredFromBackup(dayKey: String)   // → daily backup used
    case startedEmptyAfterCorruption          // nothing readable; corrupt copy kept
    case partialRecovery(dropped: Int)        // decoded, but n array elements were unreadable; raw copy kept (05a #22)
    case newerWriter(build: Int)              // written by a newer build; copy kept in Yedekler (D35, 05a #10)
}

enum DoneResult: Equatable {
    case completed
    case nextOccurrence(Date)
}

struct ImportPreview: Equatable { let itemCount: Int; let projectCount: Int; let placeCount: Int }
/// merge: items/projects/places by id, newer updatedAt wins; settings and meta unchanged.
/// replace: items, projects, places **and settings** replaced; `meta` stays local except `lastEndOfDayMove = nil` (05a #24).
enum ImportMode { case merge, replace }

@MainActor
@Observable
final class DataStore {
    private(set) var data: AppData                    // observable root
    /// false until a file was actually READ (or confirmed absent). While false: every mutation and save() is a
    /// logged no-op that returns nil / false, and ReminderEngine.reconcile returns early — an unreadable file
    /// (device locked since boot) must never be replaced by an empty document or wipe pending notifications.
    private(set) var isLoaded: Bool = false
    private(set) var loadIssue: StoreLoadIssue? = nil
    private(set) var lastSaveError: String? = nil     // "Kaydedilemedi…" / "Telefonda yer kalmadı…"
    @ObservationIgnored var onChange: (@MainActor (StoreChange) -> Void)? = nil
    let files: StoreFiles

    /// The main file was decoded without issue in this session, or written successfully by it (05a #21).
    /// Only then is it copied over `previousFile` before the next write.
    @ObservationIgnored private var mainFileVerified: Bool = false
    /// Diagnostic-only meta fields changed in memory but not yet written (see `updateMeta`).
    @ObservationIgnored private var metaDirty: Bool = false
    /// Safety copies that could not be written yet; the main file is not replaced until they exist.
    @ObservationIgnored private var pendingSafetyCopies: [SafetyCopy] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(files: StoreFiles) {                         // does NOT read disk; never touches AppEnvironment.shared
        self.files = files
        self.data = AppData.empty(now: Date())
        // Retry a failed save / flush diagnostic meta when the app leaves the foreground (§4.2 r4).
        let token = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistPendingChanges(reason: "background")
            }
        }
        observers.append(token)
    }

    /// isLoaded && lastSaveError == nil (05a #3). UI shows "Kaydedildi" only when this is true after a mutation.
    var canPersist: Bool { isLoaded && lastSaveError == nil }

    // MARK: - Load

    /// Idempotent until isLoaded. See 04 §3.6.4 for the full decision table.
    func load() {
        guard !isLoaded else { return }
        let now = Date()
        files.createDirectories()
        let currentBuild = BackupManager.currentBuild()

        let document: AppData
        let sourceBytes: Data
        let path: String
        var issue: StoreLoadIssue? = nil
        var fromMainFile = false

        switch BackupManager.read(files.dataFile) {
        case .unreadable(let reason):
            // 03 §9 r26 / §9 r41: a READ failure is not corruption. Stay unloaded; retried on
            // protectedDataDidBecomeAvailable and on every sceneDidBecomeActive.
            let protectedText: String = UIApplication.shared.isProtectedDataAvailable ? "evet" : "hayır"
            AsistLog.error("Veri dosyası okunamadı, yükleme ertelendi (protectedData=" + protectedText + "): " + reason,
                           .store)
            return
        case .bytes(let mainBytes):
            if let decoded = StoreCoding.decode(mainBytes, source: "ana dosya") {
                document = decoded
                sourceBytes = mainBytes
                path = "ana dosya"
                fromMainFile = true
            } else {
                // Read OK but undecodable: keep the corrupt bytes aside before anything else is written.
                queueSafetyCopy(mainBytes, url: files.corruptCopyURL(now: now), label: "bozuk ana dosya")
                switch recoverFromFallbacks(now: now, strictReads: false) {
                case .found(let recovered):
                    document = recovered.document
                    sourceBytes = recovered.bytes
                    path = recovered.path
                    issue = recovered.issue
                case .unavailable, .nothing:
                    document = AppData.empty(now: now)
                    sourceBytes = Data()
                    path = "boş (bozulma sonrası)"
                    issue = .startedEmptyAfterCorruption
                }
            }
        case .absent:
            // No main file: first launch — unless a previous version or a backup exists (never start empty
            // while recoverable data is on disk).
            switch recoverFromFallbacks(now: now, strictReads: true) {
            case .unavailable:
                AsistLog.error("Yedek dosyaları okunamadı, yükleme ertelendi", .store)
                return
            case .found(let recovered):
                document = recovered.document
                sourceBytes = recovered.bytes
                path = recovered.path + " (ana dosya yok)"
                issue = recovered.issue
            case .nothing:
                document = AppData.empty(now: now)
                sourceBytes = Data()
                path = "ilk açılış"
            }
        }

        // 05a #22: lenient decoding must not hide structural damage.
        var dropped = 0
        if !sourceBytes.isEmpty, let raw = StoreCoding.rawObject(sourceBytes) {
            dropped = StoreCoding.droppedElementCount(raw: raw, decoded: document)
        }
        if dropped > 0 {
            queueSafetyCopy(sourceBytes, url: files.corruptCopyURL(now: now), label: "eksik okunan dosya")
        }

        // D35: a file written by a newer build is copied to Yedekler before the first save.
        var newerBuild: Int? = nil
        if currentBuild > 0 && document.meta.writerBuild > currentBuild {
            queueSafetyCopy(sourceBytes, url: files.newerWriterCopyURL(build: document.meta.writerBuild),
                            label: "yeni sürüm verisi")
            newerBuild = document.meta.writerBuild
        } else if let earlier = BackupManager.newestNewerWriterBuild(files: files, currentBuild: currentBuild) {
            newerBuild = earlier                     // copy taken by an earlier launch of this (older) build
        }

        // One issue is shown; order follows the banner precedence (04 §3.6.6), data loss first.
        if issue != .startedEmptyAfterCorruption {
            if let build = newerBuild {
                issue = .newerWriter(build: build)
            } else if issue == nil && dropped > 0 {
                issue = .partialRecovery(dropped: dropped)
            }
        }

        var working = document
        let purged = purgeExpiredDeleted(&working, now: now)

        data = working
        mainFileVerified = fromMainFile && dropped == 0
        loadIssue = issue
        isLoaded = true
        var line: String = "Veri yüklendi: kaynak=" + path
        line += ", kayıt=" + String(working.items.count)
        line += ", proje=" + String(working.projects.count)
        line += ", şema=" + String(working.schemaVersion)
        line += ", writerBuild=" + String(document.meta.writerBuild)
        line += ", build=" + String(currentBuild)
        line += ", temizlenen=" + String(purged)
        line += ", sorun=" + describeIssue(issue)
        AsistLog.info(line, .store)
        onChange?(.all)                              // 05a #6: side effects re-applied on false → true
    }

    // MARK: - Save

    /// Synchronous, atomic, protected write of the whole document (04 §3.6.4). No-op while !isLoaded.
    func save() {
        guard isLoaded else {
            AsistLog.error("Kaydetme atlandı: veri henüz okunmadı", .store)
            return
        }
        let now = Date()
        files.createDirectories()

        // Safety copies first: the main file is never replaced while one of them is missing.
        if let copyError = flushSafetyCopies() {
            recordSaveFailure(copyError, step: "güvenlik kopyası")
            return
        }

        var document = data
        let build = BackupManager.currentBuild()
        if build > 0 {
            document.meta.writerBuild = build
        }
        document.meta.lastSavedAt = now
        let dayKey = AsistCalendar.dayKey(now, calendar: AppTime.calendar)
        let hasContent = !(document.items.isEmpty && document.projects.isEmpty)
        // An empty document never pushes an older (real) backup out of the 7-day window.
        let wantsDailyBackup = hasContent && !BackupManager.fileExists(files.dailyBackupURL(dayKey: dayKey))
        if wantsDailyBackup {
            document.meta.lastDailyBackupDay = dayKey
        }

        let bytes: Data
        do {
            bytes = try StoreCoding.encode(document, pretty: false)
        } catch {
            recordSaveFailure(error, step: "kodlama")
            return
        }

        if mainFileVerified {
            BackupManager.copyMainToPrevious(files)   // never copies an unverified/corrupt file (05a #21)
        }

        do {
            try BackupManager.write(bytes, to: files.dataFile)
        } catch {
            recordSaveFailure(error, step: "ana dosya")
            return
        }

        data.meta = document.meta
        mainFileVerified = true
        metaDirty = false
        if lastSaveError != nil {
            lastSaveError = nil
            AsistLog.info("Kaydetme yeniden başarılı", .store)
        }

        if wantsDailyBackup {
            BackupManager.writeDailyBackup(bytes, dayKey: dayKey, files: files)
        }
        let text = AgendaBuilder.openItemsText(items: data.items, projects: data.projects, now: now,
                                               calendar: AppTime.calendar)
        BackupManager.writeOpenItemsText(text, files: files)
    }

    // MARK: - Reads (computed from `data`)

    var items: [Item] { data.items }
    var settings: AppSettings { data.settings }
    var projects: [Project] { data.projects }
    var places: [Place] { data.places }
    var meta: AppMeta { data.meta }

    /// status .deleted, deletedAt within 30 days, newest first (05b B8).
    var recentlyDeleted: [Item] {
        let cutoff = Date().addingTimeInterval(-deletedRetentionSeconds)
        let deleted = data.items.filter { item in
            item.status == .deleted && deletionDate(of: item) >= cutoff
        }
        return deleted.sorted { lhs, rhs in
            deletionDate(of: lhs) > deletionDate(of: rhs)
        }
    }

    func item(_ id: UUID) -> Item? {
        data.items.first(where: { $0.id == id })
    }

    func project(_ id: UUID?) -> Project? {
        guard let id = id else { return nil }
        return data.projects.first(where: { $0.id == id })
    }

    func place(_ id: UUID?) -> Place? {
        guard let id = id else { return nil }
        return data.places.first(where: { $0.id == id })
    }

    func projectName(for item: Item) -> String? {
        project(item.projectID)?.name
    }

    // MARK: - Item mutations
    // Each: mutate → updatedAt → save() → onChange(.items). nil = nothing changed OR not persisted
    // (!isLoaded, item missing/closed, or save failed; the change then stays in memory and is retried) (05a #3).

    @discardableResult func add(_ item: Item) -> UndoToken? {
        guard isLoaded else {
            logSkipped("ekleme")
            return nil
        }
        guard !data.items.contains(where: { $0.id == item.id }) else {
            AsistLog.error("Ekleme reddedildi: aynı kimlikli kayıt var", .store)
            return nil
        }
        var newData = data
        newData.items.append(item)
        switch commit(newData, change: .items) {
        case .persisted:
            return UndoToken(label: "Kaydedildi", before: [], createdIDs: [item.id])
        case .unchanged, .notPersisted:
            return nil
        }
    }

    @discardableResult func update(_ id: UUID, event: HistoryEvent?, _ mutate: (inout Item) -> Void) -> UndoToken? {
        let now = Date()
        return replaceItem(id, label: "Değiştirildi", change: .items) { original in
            var copy = original
            mutate(&copy)
            copy.id = original.id
            guard copy != original else { return nil }
            copy.updatedAt = now
            if let event = event {
                copy.appendHistory(event, at: now)
            }
            return copy
        }
    }

    /// Non-recurring → status .done, completedAt, history .done. Recurring → dueDate = next occurrence
    /// (RecurrenceEngine, time of current due, after max(now, due)), resetNagState, completedOccurrences += 1,
    /// history .occurrenceDone.
    @discardableResult func markDone(_ id: UUID, at now: Date) -> (DoneResult, UndoToken)? {
        let calendar = AppTime.calendar
        let fallbackTime = data.settings.defaultDayTime
        var result: DoneResult = .completed
        let token = replaceItem(id, label: "Tamamlandı", change: .items) { original in
            guard original.status == .open else { return nil }
            let done = completedCopy(of: original, now: now, calendar: calendar, fallbackTime: fallbackTime,
                                     detail: nil)
            result = done.result
            return done.item
        }
        guard let undo = token else { return nil }
        return (result, undo)
    }

    @discardableResult func reopen(_ id: UUID, at now: Date) -> UndoToken? {
        replaceItem(id, label: "Yeniden açıldı", change: .items) { original in
            guard original.status == .done else { return nil }
            var copy = original
            copy.status = .open
            copy.completedAt = nil
            copy.updatedAt = now
            copy.appendHistory(.reopened, at: now)
            return copy
        }
    }

    /// snoozedUntil = target (whole minute), snoozeCount += 1, history .snoozed(detail: target text).
    @discardableResult func snooze(_ id: UUID, until target: Date, at now: Date) -> UndoToken? {
        let calendar = AppTime.calendar
        let wholeMinute = AsistCalendar.ceilToMinute(target)
        return replaceItem(id, label: "Ertelendi", change: .items) { original in
            guard original.status == .open else { return nil }
            var copy = original
            copy.snoozedUntil = wholeMinute
            copy.snoozeCount = max(0, original.snoozeCount) + 1
            copy.updatedAt = now
            copy.appendHistory(.snoozed, at: now, detail: historyStamp(wholeMinute, calendar: calendar))
            return copy
        }
    }

    /// status .deleted + deletedAt (soft delete; purge after 30 days).
    @discardableResult func delete(_ id: UUID, at now: Date) -> UndoToken? {
        replaceItem(id, label: "Silindi", change: .items) { original in
            guard original.status != .deleted else { return nil }
            var copy = original
            copy.status = .deleted
            copy.deletedAt = now
            copy.updatedAt = now
            copy.appendHistory(.deleted, at: now)
            return copy
        }
    }

    /// status .open, deletedAt nil, history .restored ("Son silinenler › Geri getir").
    @discardableResult func restoreDeleted(_ id: UUID, at now: Date) -> UndoToken? {
        replaceItem(id, label: "Geri getirildi", change: .items) { original in
            guard original.status == .deleted else { return nil }
            var copy = original
            // DEVIATION(04 §3.6.4): an item that was already completed when it was deleted (completedAt set,
            // not recurring) comes back as .done, not .open — otherwise restoring an old completed item would
            // resurrect it as overdue and start nagging.
            if original.completedAt != nil && original.recurrence == nil {
                copy.status = .done
            } else {
                copy.status = .open
            }
            copy.deletedAt = nil
            copy.updatedAt = now
            copy.appendHistory(.restored, at: now)
            return copy
        }
    }

    /// Applies AgendaBuilder.movedToTomorrow to endOfDayCandidates; stores meta.lastEndOfDayMove.
    @discardableResult func moveOpenItemsToTomorrow(now: Date) -> UndoToken? {
        guard isLoaded else {
            logSkipped("gün sonu taşıma")
            return nil
        }
        let calendar = AppTime.calendar
        let settings = data.settings
        let candidates = AgendaBuilder.endOfDayCandidates(items: data.items, now: now, calendar: calendar)
        guard !candidates.isEmpty else { return nil }
        var newData = data
        var before: [Item] = []
        for candidate in candidates {
            guard let index = newData.items.firstIndex(where: { $0.id == candidate.id }) else { continue }
            let original = newData.items[index]
            guard original.status == .open else { continue }
            var moved = AgendaBuilder.movedToTomorrow(original, now: now, settings: settings, calendar: calendar)
            moved.id = original.id
            guard moved != original else { continue }
            if moved.updatedAt < now {
                moved.updatedAt = now
            }
            newData.items[index] = moved
            before.append(original)
        }
        guard !before.isEmpty else { return nil }
        newData.meta.lastEndOfDayMove = MoveRecord(movedAt: now, before: before)
        switch commit(newData, change: .items) {
        case .persisted:
            AsistLog.info("Gün sonu: " + String(before.count) + " kayıt taşındı", .store)
            return UndoToken(label: String(before.count) + " iş taşındı", before: before)
        case .unchanged, .notPersisted:
            return nil
        }
    }

    /// Restores `before`, hard-removes createdIDs. Undoing the end-of-day move also clears lastEndOfDayMove.
    func undo(_ token: UndoToken) {
        guard isLoaded else {
            logSkipped("geri alma")
            return
        }
        var newData = data
        if !token.createdIDs.isEmpty {
            let created = Set(token.createdIDs)
            newData.items.removeAll { item in created.contains(item.id) }
        }
        for original in token.before {
            if let index = newData.items.firstIndex(where: { $0.id == original.id }) {
                newData.items[index] = original
            } else {
                newData.items.append(original)
            }
        }
        if let move = newData.meta.lastEndOfDayMove, token.createdIDs.isEmpty, !token.before.isEmpty {
            let moveIDs = Set(move.before.map { $0.id })
            let tokenIDs = Set(token.before.map { $0.id })
            if moveIDs == tokenIDs {
                newData.meta.lastEndOfDayMove = nil
            }
        }
        _ = commit(newData, change: .items)
    }

    /// lastDismissedAt; onChange(.meta)-level only (no reconcile).
    func recordDismiss(_ id: UUID, at date: Date) {
        guard isLoaded else {
            logSkipped("bildirim kapatma kaydı")
            return
        }
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        guard data.items[index].status == .open, data.items[index].lastDismissedAt != date else { return }
        var newData = data
        newData.items[index].lastDismissedAt = date
        _ = commit(newData, change: .meta)
    }

    /// Open recurring items whose next occurrence ≤ now: dueDate = latest occurrence ≤ now, resetNagState,
    /// history .occurrenceMissed. Returns true if anything changed (emits onChange itself).
    @discardableResult func rollOverRecurring(now: Date, calendar: Calendar) -> Bool {
        guard isLoaded else { return false }
        var newData = data
        var rolled = 0
        for index in newData.items.indices {
            guard let updated = rolledOverCopy(of: newData.items[index], now: now, calendar: calendar) else { continue }
            newData.items[index] = updated
            rolled += 1
        }
        guard rolled > 0 else { return false }
        AsistLog.info("Tekrarlayan: " + String(rolled) + " kayıt güncel oluşuma taşındı", .store)
        return commit(newData, change: .items) != .unchanged
    }

    /// D31: open events with `eventEnd ≤ now` → markDone semantics (recurring → next occurrence) with history
    /// detail "otomatik kapandı". Returns true if anything changed (emits onChange itself).
    @discardableResult func closeFinishedEvents(now: Date, calendar: Calendar) -> Bool {
        guard isLoaded else { return false }
        let fallbackTime = data.settings.defaultDayTime
        var newData = data
        var closed = 0
        for index in newData.items.indices {
            let item = newData.items[index]
            guard item.status == .open, item.isEvent, let end = item.eventEnd, end <= now else { continue }
            let done = completedCopy(of: item, now: now, calendar: calendar, fallbackTime: fallbackTime,
                                     detail: "otomatik kapandı")
            guard done.item != item else { continue }
            newData.items[index] = done.item
            closed += 1
        }
        guard closed > 0 else { return false }
        AsistLog.info("Etkinlik: " + String(closed) + " kayıt otomatik kapandı", .store)
        return commit(newData, change: .items) != .unchanged
    }

    // MARK: - Projects / places / settings / meta

    func upsertProject(_ project: Project) {
        guard isLoaded else {
            logSkipped("proje kaydı")
            return
        }
        var newData = data
        if let index = newData.projects.firstIndex(where: { $0.id == project.id }) {
            let existing = newData.projects[index]
            var candidate = project
            candidate.updatedAt = existing.updatedAt
            guard candidate != existing else { return }
            candidate.updatedAt = Date()
            newData.projects[index] = candidate
        } else {
            newData.projects.append(project)
        }
        _ = commit(newData, change: .projects)
    }

    func archiveProject(_ id: UUID, archived: Bool) {
        guard isLoaded else {
            logSkipped("proje arşivleme")
            return
        }
        guard let index = data.projects.firstIndex(where: { $0.id == id }),
              data.projects[index].archived != archived else { return }
        var newData = data
        newData.projects[index].archived = archived
        newData.projects[index].updatedAt = Date()
        _ = commit(newData, change: .projects)
    }

    /// onChange(.places) (no v1.0 caller).
    func upsertPlace(_ place: Place) {
        guard isLoaded else {
            logSkipped("yer kaydı")
            return
        }
        var newData = data
        if let index = newData.places.firstIndex(where: { $0.id == place.id }) {
            guard newData.places[index] != place else { return }
            newData.places[index] = place
        } else {
            newData.places.append(place)
        }
        _ = commit(newData, change: .places)
    }

    /// Also clears placeID / placeTrigger on items.
    func removePlace(_ id: UUID) {
        guard isLoaded else {
            logSkipped("yer silme")
            return
        }
        let now = Date()
        var newData = data
        newData.places.removeAll { place in place.id == id }
        for index in newData.items.indices where newData.items[index].placeID == id {
            newData.items[index].placeID = nil
            newData.items[index].placeTrigger = nil
            newData.items[index].updatedAt = now
        }
        _ = commit(newData, change: .places)
    }

    /// onChange(.settings). The result passes the same decode clamps as a file on disk (05a #8, #20).
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        guard isLoaded else {
            logSkipped("ayar değişikliği")
            return
        }
        var copy = data.settings
        mutate(&copy)
        let sanitized = sanitizedSettings(copy)
        guard sanitized != data.settings else { return }
        var newData = data
        newData.settings = sanitized
        _ = commit(newData, change: .settings)
    }

    /// onChange(.meta) — never triggers reconcile. Changes that touch only the reconcile diagnostics
    /// (lastReconcileAt/Reason, lastPlanned/DroppedCount) stay in memory until the next save or backgrounding,
    /// so idle reconciles perform 0 writes (05a #5); everything else is persisted immediately. A pending failed
    /// save is retried here as well.
    func updateMeta(_ mutate: (inout AppMeta) -> Void) {
        guard isLoaded else {
            logSkipped("meta değişikliği")
            return
        }
        var copy = data.meta
        mutate(&copy)
        let before = data.meta
        guard copy != before else { return }
        data.meta = copy
        if isDiagnosticOnlyChange(before: before, after: copy) && lastSaveError == nil && pendingSafetyCopies.isEmpty {
            metaDirty = true
        } else {
            save()
        }
        onChange?(.meta)
    }

    // MARK: - Import / export (helpers in ImportExport.swift)

    /// Pretty-printed, sorted keys, iso8601. Empty Data while !isLoaded (never exports unread defaults).
    func exportData() -> Data {
        guard isLoaded else {
            logSkipped("dışa aktarma")
            return Data()
        }
        var document = data
        let build = BackupManager.currentBuild()
        if build > 0 {
            document.meta.writerBuild = build
        }
        do {
            return try ImportExport.exportBytes(document)
        } catch {
            AsistLog.error("Dışa aktarma kodlanamadı: " + BackupManager.describe(error), .store)
            return Data()
        }
    }

    func importPreview(_ bytes: Data) -> ImportPreview? {
        guard let document = ImportExport.parse(bytes) else { return nil }
        return ImportExport.preview(document)
    }

    /// Writes the current state to a pre-import copy in Yedekler first (§9 r43; the import is refused when that
    /// copy cannot be written), then applies `mode`; onChange(.all). false = rejected or not persisted.
    func importData(_ bytes: Data, mode: ImportMode) -> Bool {
        guard isLoaded else {
            logSkipped("içe aktarma")
            return false
        }
        guard let incoming = ImportExport.parse(bytes) else { return false }
        let now = Date()
        let currentBytes: Data
        do {
            currentBytes = try StoreCoding.encode(data, pretty: true)
        } catch {
            AsistLog.error("İçe aktarma öncesi yedek kodlanamadı: " + BackupManager.describe(error), .store)
            return false
        }
        guard BackupManager.writePreImportCopy(currentBytes, now: now, files: files) else { return false }

        let result: AppData
        switch mode {
        case .merge:
            result = ImportExport.merged(local: data, incoming: incoming)
        case .replace:
            result = ImportExport.replaced(local: data, incoming: incoming)
        }
        let modeText: String = mode == .merge ? "birleştir" : "değiştir"
        var line: String = "İçe aktarma (" + modeText + "): gelen kayıt=" + String(incoming.items.count)
        line += ", sonuç kayıt=" + String(result.items.count)
        line += ", proje=" + String(result.projects.count)
        AsistLog.info(line, .store)
        let previousIssue = loadIssue
        if mode == .replace && !hasNewerWriterIssue {
            loadIssue = nil                            // the user restored a known state deliberately
        }
        guard result != data else { return true }
        let previous = data
        data = result
        save()
        guard lastSaveError == nil else {
            // Not written: undo in memory too, so "verilerin değişmedi" (DataImportFlow / restore) is true and a
            // later retry of save() never writes an import the user was told had failed. save() leaves `data`
            // untouched on failure, so this is exactly the pre-import state.
            data = previous
            loadIssue = previousIssue
            AsistLog.error("İçe aktarma kaydedilemedi; önceki veri korunuyor", .store)
            return false
        }
        onChange?(.all)
        return true
    }

    // MARK: - Private: commit

    private enum CommitOutcome {
        case unchanged, persisted, notPersisted
    }

    /// Replaces `data` when different, saves synchronously, then emits `change` (only real changes, 05a #5).
    private func commit(_ newData: AppData, change: StoreChange) -> CommitOutcome {
        guard newData != data else { return .unchanged }
        data = newData
        save()
        onChange?(change)
        return lastSaveError == nil ? CommitOutcome.persisted : CommitOutcome.notPersisted
    }

    /// Applies `transform` to item `id` (nil from `transform` = refused / nothing to do). Returns an undo token
    /// holding the previous version only when the change was persisted.
    private func replaceItem(_ id: UUID, label: String, change: StoreChange,
                             transform: (Item) -> Item?) -> UndoToken? {
        guard isLoaded else {
            logSkipped(label)
            return nil
        }
        guard let index = data.items.firstIndex(where: { $0.id == id }) else {
            AsistLog.info("Kayıt bulunamadı (" + label + ")", .store)
            return nil
        }
        let original = data.items[index]
        guard var updated = transform(original) else { return nil }
        updated.id = original.id
        guard updated != original else { return nil }
        var newData = data
        newData.items[index] = updated
        switch commit(newData, change: change) {
        case .persisted:
            return UndoToken(label: label, before: [original])
        case .unchanged, .notPersisted:
            return nil
        }
    }

    // MARK: - Private: safety copies, failures, background

    /// Writes the copy now; when that fails it stays queued and blocks the next save until it succeeds.
    private func queueSafetyCopy(_ bytes: Data, url: URL, label: String) {
        guard !bytes.isEmpty else { return }
        let copy = SafetyCopy(bytes: bytes, url: url, label: label)
        if BackupManager.writeSafetyCopy(copy) != nil {
            pendingSafetyCopies.append(copy)
        }
    }

    /// nil = every queued copy exists on disk.
    private func flushSafetyCopies() -> Error? {
        guard !pendingSafetyCopies.isEmpty else { return nil }
        var remaining: [SafetyCopy] = []
        var lastError: Error? = nil
        for copy in pendingSafetyCopies {
            if let error = BackupManager.writeSafetyCopy(copy) {
                remaining.append(copy)
                lastError = error
            }
        }
        pendingSafetyCopies = remaining
        return lastError
    }

    private func recordSaveFailure(_ error: Error, step: String) {
        let message: String = BackupManager.isDiskFull(error) ? diskFullMessage : saveFailedMessage
        var line: String = "Kaydedilemedi (" + step + "): " + BackupManager.describe(error)
        line += " — veri bellekte tutuluyor, tekrar denenecek"
        AsistLog.error(line, .store)
        if lastSaveError != message {
            lastSaveError = message
        }
    }

    /// Retries a failed save, pending safety copies and unsaved diagnostic meta (app entering background).
    private func persistPendingChanges(reason: String) {
        guard isLoaded else { return }
        if !pendingSafetyCopies.isEmpty && lastSaveError == nil && !metaDirty {
            _ = flushSafetyCopies()
            return
        }
        if lastSaveError != nil || metaDirty || !pendingSafetyCopies.isEmpty {
            AsistLog.info("Bekleyen kayıt yazılıyor (" + reason + ")", .store)
            save()
        }
    }

    private var hasNewerWriterIssue: Bool {
        if case .some(.newerWriter(_)) = loadIssue {
            return true
        }
        return false
    }

    private func logSkipped(_ what: String) {
        AsistLog.error("İşlem yapılmadı, veri henüz okunmadı: " + what, .store)
    }

    // MARK: - Private: recovery

    private struct RecoveredDocument {
        let document: AppData
        let bytes: Data
        let issue: StoreLoadIssue
        let path: String
    }

    private enum Recovery {
        case found(RecoveredDocument)
        /// A fallback exists but cannot be read (device locked since boot) — stay unloaded.
        case unavailable
        case nothing
    }

    /// previousFile → backups (newest first). `strictReads`: an unreadable fallback means "try again later"
    /// (used when the main file is absent); otherwise unreadable fallbacks are skipped.
    private func recoverFromFallbacks(now: Date, strictReads: Bool) -> Recovery {
        switch BackupManager.read(files.previousFile) {
        case .absent:
            break
        case .unreadable(let reason):
            AsistLog.error("Önceki sürüm okunamadı: " + reason, .store)
            if strictReads {
                return .unavailable
            }
        case .bytes(let bytes):
            if let decoded = StoreCoding.decode(bytes, source: "önceki sürüm") {
                let recovered = RecoveredDocument(document: decoded, bytes: bytes, issue: .restoredFromPrevious,
                                                  path: "önceki sürüm")
                return .found(recovered)
            }
            queueSafetyCopy(bytes, url: files.corruptCopyURL(now: now), label: "bozuk önceki sürüm")
        }
        for backup in BackupManager.listBackups(files) {
            switch BackupManager.read(backup.url) {
            case .absent:
                continue
            case .unreadable(let reason):
                AsistLog.error("Yedek okunamadı: " + backup.fileName + " " + reason, .store)
                if strictReads {
                    return .unavailable
                }
            case .bytes(let bytes):
                if let decoded = StoreCoding.decode(bytes, source: "yedek " + backup.fileName) {
                    let recovered = RecoveredDocument(document: decoded, bytes: bytes,
                                                      issue: .restoredFromBackup(dayKey: backup.dayKey),
                                                      path: "yedek " + backup.fileName)
                    return .found(recovered)
                }
            }
        }
        return .nothing
    }
}

// MARK: - File-private pure helpers (non-isolated)

private let saveFailedMessage = "Kaydedilemedi. Lütfen tekrar dene."
private let diskFullMessage = "Telefonda yer kalmadı; kayıt yapılamıyor."
private let deletedRetentionSeconds: TimeInterval = 30 * 86_400

private func deletionDate(of item: Item) -> Date {
    item.deletedAt ?? item.updatedAt
}

/// Removes soft-deleted items older than 30 days. Returns the number removed.
private func purgeExpiredDeleted(_ document: inout AppData, now: Date) -> Int {
    let cutoff = now.addingTimeInterval(-deletedRetentionSeconds)
    let countBefore = document.items.count
    document.items.removeAll { item in
        item.status == .deleted && deletionDate(of: item) < cutoff
    }
    return countBefore - document.items.count
}

/// Wall-clock time of the item's current occurrence (fallback when it has no due date).
private func occurrenceTime(of item: Item, calendar: Calendar, fallback: ClockTime) -> ClockTime {
    guard let due = item.dueDate else { return fallback }
    return ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(due, calendar: calendar))
}

/// markDone semantics (§3.6.4): recurring → next occurrence strictly after max(now, due); otherwise done.
private func completedCopy(of item: Item, now: Date, calendar: Calendar, fallbackTime: ClockTime,
                           detail: String?) -> (item: Item, result: DoneResult) {
    var copy = item
    if let rule = item.recurrence {
        let time = occurrenceTime(of: item, calendar: calendar, fallback: fallbackTime)
        let due: Date = item.dueDate ?? now
        let base: Date = max(now, due)
        if let next = RecurrenceEngine.nextOccurrence(of: rule, time: time, after: base, anchor: item.dueDate,
                                                      calendar: calendar), next > now {
            copy.dueDate = next
            copy.resetNagState()
            copy.completedOccurrences = max(0, item.completedOccurrences) + 1
            copy.updatedAt = now
            copy.appendHistory(.occurrenceDone, at: now, detail: detail)
            return (item: copy, result: DoneResult.nextOccurrence(next))
        }
    }
    copy.status = .done
    copy.completedAt = now
    copy.updatedAt = now
    copy.appendHistory(.done, at: now, detail: detail)
    return (item: copy, result: DoneResult.completed)
}

/// Roll-over of a missed recurring occurrence (D27). nil = nothing to do. A snooze never blocks it: a roll-over
/// needs an occurrence N1 with due < N1 ≤ now, so a still-future snooze already reaches past N1 — the planner drops
/// such a snooze alert (chain elements ≥ N1), and keeping the old due date would leave the new occurrence with no
/// nags. resetNagState() clears the stale snooze; the new occurrence is planned from its own due date.
private func rolledOverCopy(of item: Item, now: Date, calendar: Calendar) -> Item? {
    guard item.status == .open, let rule = item.recurrence, let due = item.dueDate, due < now else { return nil }
    let time = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(due, calendar: calendar))
    guard let latest = RecurrenceEngine.latestOccurrence(of: rule, time: time, after: due, upTo: now,
                                                         calendar: calendar),
          latest > due, latest <= now else { return nil }
    var copy = item
    copy.dueDate = latest
    copy.resetNagState()
    copy.updatedAt = now
    copy.appendHistory(.occurrenceMissed, at: now)
    return copy
}

/// Absolute history text "28 Eyl 09:00" (a relative "Yarın" would be wrong when read later).
private func historyStamp(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.month, .day], from: date)
    let monthIndex = min(11, max(0, (parts.month ?? 1) - 1))
    let names = TurkishDateFormatter.monthsShort
    let monthName: String = monthIndex < names.count ? names[monthIndex] : String(monthIndex + 1)
    return String(parts.day ?? 1) + " " + monthName + " " + TurkishDateFormatter.time(date, calendar: calendar)
}

/// Runs settings through the same lenient decoder as the file on disk, so UI edits get the decode clamps
/// (never-empty workdays, ranges). Returns the input unchanged if the round trip fails.
private func sanitizedSettings(_ settings: AppSettings) -> AppSettings {
    do {
        let bytes = try StoreCoding.makeEncoder(pretty: false).encode(settings)
        return try StoreCoding.makeDecoder().decode(AppSettings.self, from: bytes)
    } catch {
        AsistLog.error("Ayar doğrulaması yapılamadı: " + BackupManager.describe(error), .store)
        return settings
    }
}

/// true when only the reconcile diagnostics differ between `before` and `after`.
private func isDiagnosticOnlyChange(before: AppMeta, after: AppMeta) -> Bool {
    var normalized = after
    normalized.lastReconcileAt = before.lastReconcileAt
    normalized.lastReconcileReason = before.lastReconcileReason
    normalized.lastPlannedCount = before.lastPlannedCount
    normalized.lastDroppedCount = before.lastDroppedCount
    return normalized == before
}

private func describeIssue(_ issue: StoreLoadIssue?) -> String {
    guard let issue = issue else { return "yok" }
    switch issue {
    case .restoredFromPrevious:
        return "önceki sürümden geri yüklendi"
    case .restoredFromBackup(let dayKey):
        return "yedekten geri yüklendi (" + dayKey + ")"
    case .startedEmptyAfterCorruption:
        return "okunamadı, boş başlatıldı"
    case .partialRecovery(let dropped):
        return "kısmi kurtarma (" + String(dropped) + " öğe okunamadı)"
    case .newerWriter(let build):
        return "daha yeni sürümün verisi (build " + String(build) + ")"
    }
}
