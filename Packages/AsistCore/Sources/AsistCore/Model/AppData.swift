// FILE: Packages/AsistCore/Sources/AsistCore/Model/AppData.swift
import Foundation

public struct MoveRecord: Codable, Equatable, Hashable {
    public var movedAt: Date
    /// Copies of the items before "Sonraki iş gününe taşı" (for 24 h undo banner).
    public var before: [Item]

    public init(movedAt: Date, before: [Item]) {
        self.movedAt = movedAt
        self.before = before
    }

    enum CodingKeys: String, CodingKey { case movedAt, before }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        movedAt = c.lenient(Date.self, forKey: .movedAt, default: Date(timeIntervalSince1970: 0))
        before = c.lenientOptional(LossyDecodableArray<Item>.self, forKey: .before)?.elements ?? []
    }
}

public struct AppMeta: Codable, Equatable, Hashable {
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var lastSavedAt: Date? = nil
    public var lastProfileStamp: Double? = nil           // signing profile CreationDate (seconds)
    public var lastReconcileAt: Date? = nil
    public var lastReconcileReason: String? = nil
    public var lastPlannedCount: Int = 0
    public var lastDroppedCount: Int = 0
    public var lastBackgroundRefreshAt: Date? = nil
    public var lastDailyBackupDay: String? = nil          // "yyyyMMdd"
    public var lastEndOfDayMove: MoveRecord? = nil
    public var composeDraft: String? = nil
    public var dismissedBanners: [String: Date] = [:]     // banner id → hidden until (absolute date)
    public var installDate: Date? = nil                   // UI-only signing estimate (05a #28)
    /// CFBundleVersion of the build that last saved this file (D35). 0 = unknown / revision-1 file.
    public var writerBuild: Int = 0

    public init() {}

    enum CodingKeys: String, CodingKey {
        case createdAt, lastSavedAt, lastProfileStamp, lastReconcileAt, lastReconcileReason, lastPlannedCount
        case lastDroppedCount, lastBackgroundRefreshAt, lastDailyBackupDay, lastEndOfDayMove, composeDraft
        case dismissedBanners, installDate, writerBuild
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: createdAt)
        lastSavedAt = c.lenientOptional(Date.self, forKey: .lastSavedAt)
        lastProfileStamp = c.lenientOptional(Double.self, forKey: .lastProfileStamp)
        lastReconcileAt = c.lenientOptional(Date.self, forKey: .lastReconcileAt)
        lastReconcileReason = c.lenientOptional(String.self, forKey: .lastReconcileReason)
        lastPlannedCount = c.lenient(Int.self, forKey: .lastPlannedCount, default: 0)
        lastDroppedCount = c.lenient(Int.self, forKey: .lastDroppedCount, default: 0)
        lastBackgroundRefreshAt = c.lenientOptional(Date.self, forKey: .lastBackgroundRefreshAt)
        lastDailyBackupDay = c.lenientOptional(String.self, forKey: .lastDailyBackupDay)
        lastEndOfDayMove = c.lenientOptional(MoveRecord.self, forKey: .lastEndOfDayMove)
        composeDraft = c.lenientOptional(String.self, forKey: .composeDraft)
        dismissedBanners = c.lenient([String: Date].self, forKey: .dismissedBanners, default: [:])
        installDate = c.lenientOptional(Date.self, forKey: .installDate)
        writerBuild = max(0, c.lenient(Int.self, forKey: .writerBuild, default: 0))
    }
}

/// Root document persisted as `asist-data.json`.
public struct AppData: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [Item]
    public var projects: [Project]
    public var places: [Place]
    public var settings: AppSettings
    public var meta: AppMeta

    public init(schemaVersion: Int = AppData.currentSchemaVersion,
                items: [Item] = [],
                projects: [Project] = [],
                places: [Place] = [],
                settings: AppSettings = AppSettings(),
                meta: AppMeta = AppMeta()) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.projects = projects
        self.places = places
        self.settings = settings
        self.meta = meta
    }

    public static func empty(now: Date) -> AppData {
        var meta = AppMeta()
        meta.createdAt = now
        meta.installDate = now
        return AppData(meta: meta)
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, items, projects, places, settings, meta }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.lenient(Int.self, forKey: .schemaVersion, default: 1)
        items = c.lenientOptional(LossyDecodableArray<Item>.self, forKey: .items)?.elements ?? []
        projects = c.lenientOptional(LossyDecodableArray<Project>.self, forKey: .projects)?.elements ?? []
        places = c.lenientOptional(LossyDecodableArray<Place>.self, forKey: .places)?.elements ?? []
        settings = c.lenient(AppSettings.self, forKey: .settings, default: AppSettings())
        meta = c.lenient(AppMeta.self, forKey: .meta, default: AppMeta())
    }
}

/// Snapshot for "Geri Al": restoring puts `before` back and hard-removes `createdIDs`.
public struct UndoToken: Equatable, Hashable, Identifiable {
    public var id: UUID
    public var label: String
    public var before: [Item]
    public var createdIDs: [UUID]

    public init(id: UUID = UUID(), label: String, before: [Item], createdIDs: [UUID] = []) {
        self.id = id
        self.label = label
        self.before = before
        self.createdIDs = createdIDs
    }
}
