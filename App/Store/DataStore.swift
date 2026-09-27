// API: App/Store/DataStore.swift
// WP0 STUB (04 §3.6.4) — replaced by WP4. In-memory only: never reads or writes disk. `load()` marks the
// (empty) document as loaded so the skeleton UI is navigable; item mutations are no-ops that return nil.
import Foundation
import Observation
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
    /// false until a file was actually READ (or confirmed absent).
    private(set) var isLoaded: Bool = false
    private(set) var loadIssue: StoreLoadIssue? = nil
    private(set) var lastSaveError: String? = nil     // "Kaydedilemedi…" / "Telefonda yer kalmadı…"
    @ObservationIgnored var onChange: (@MainActor (StoreChange) -> Void)? = nil
    let files: StoreFiles

    init(files: StoreFiles) {                         // does NOT read disk; never touches AppEnvironment.shared
        self.files = files
        self.data = AppData.empty(now: Date())
    }

    /// isLoaded && lastSaveError == nil (05a #3).
    var canPersist: Bool { isLoaded && lastSaveError == nil }

    // MARK: Load / save

    func load() {
        guard !isLoaded else { return }
        // WP0 STUB: no disk access — starts with the empty in-memory document created in init.
        isLoaded = true
        onChange?(.all)
    }

    func save() {
        // WP0 STUB: nothing is written.
    }

    // MARK: Reads (computed from `data`)
    var items: [Item] { data.items }
    var settings: AppSettings { data.settings }
    var projects: [Project] { data.projects }
    var places: [Place] { data.places }
    var meta: AppMeta { data.meta }
    /// status .deleted, deletedAt within 30 days, newest first (05b B8).
    var recentlyDeleted: [Item] { [] }

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

    // MARK: Item mutations (WP0 STUB: no-ops, nil = nothing changed / not persisted)
    @discardableResult func add(_ item: Item) -> UndoToken? { nil }
    @discardableResult func update(_ id: UUID, event: HistoryEvent?, _ mutate: (inout Item) -> Void) -> UndoToken? { nil }
    @discardableResult func markDone(_ id: UUID, at now: Date) -> (DoneResult, UndoToken)? { nil }
    @discardableResult func reopen(_ id: UUID, at now: Date) -> UndoToken? { nil }
    @discardableResult func snooze(_ id: UUID, until target: Date, at now: Date) -> UndoToken? { nil }
    @discardableResult func delete(_ id: UUID, at now: Date) -> UndoToken? { nil }
    @discardableResult func restoreDeleted(_ id: UUID, at now: Date) -> UndoToken? { nil }
    @discardableResult func moveOpenItemsToTomorrow(now: Date) -> UndoToken? { nil }
    func undo(_ token: UndoToken) {}
    func recordDismiss(_ id: UUID, at date: Date) {}
    @discardableResult func rollOverRecurring(now: Date, calendar: Calendar) -> Bool { false }
    @discardableResult func closeFinishedEvents(now: Date, calendar: Calendar) -> Bool { false }

    // MARK: Projects / places / settings / meta
    func upsertProject(_ project: Project) {}
    func archiveProject(_ id: UUID, archived: Bool) {}
    func upsertPlace(_ place: Place) {}
    func removePlace(_ id: UUID) {}

    /// WP0 STUB: applied in memory only (lets onboarding / settings screens work in the skeleton).
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        guard isLoaded else { return }
        var copy = data.settings
        mutate(&copy)
        guard copy != data.settings else { return }
        data.settings = copy
        onChange?(.settings)
    }

    /// WP0 STUB: applied in memory only.
    func updateMeta(_ mutate: (inout AppMeta) -> Void) {
        guard isLoaded else { return }
        var copy = data.meta
        mutate(&copy)
        guard copy != data.meta else { return }
        data.meta = copy
        onChange?(.meta)
    }

    // MARK: Import / export
    func exportData() -> Data { Data() }
    func importPreview(_ data: Data) -> ImportPreview? { nil }
    func importData(_ data: Data, mode: ImportMode) -> Bool { false }
}
