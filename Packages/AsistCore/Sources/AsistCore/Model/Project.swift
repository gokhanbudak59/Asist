// FILE: Packages/AsistCore/Sources/AsistCore/Model/Project.swift
import Foundation

public struct Project: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// Spoken aliases ("Kocaeli", "Kocaeli hattı"); fed to the parser as extra project names.
    public var aliases: [String]
    public var color: ProjectColor
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], color: ProjectColor = .blue,
                archived: Bool = false, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.color = color
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Name first, then aliases (non-empty, trimmed).
    public var allNames: [String] {
        ([name] + aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey { case id, name, aliases, color, archived, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = Date(timeIntervalSince1970: 0)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        name = c.lenient(String.self, forKey: .name, default: "Proje")
        aliases = c.lenient([String].self, forKey: .aliases, default: [])
        color = c.lenient(ProjectColor.self, forKey: .color, default: .blue)
        archived = c.lenient(Bool.self, forKey: .archived, default: false)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: epoch)
        updatedAt = c.lenient(Date.self, forKey: .updatedAt, default: createdAt)
    }
}

public struct Place: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var latitude: Double
    public var longitude: Double
    /// 100…1000 m (clamped on decode; geofences are v1.2).
    public var radiusMeters: Double
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], latitude: Double, longitude: Double,
                radiusMeters: Double = 150, createdAt: Date) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.createdAt = createdAt
    }

    public var allNames: [String] {
        ([name] + aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey { case id, name, aliases, latitude, longitude, radiusMeters, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        name = c.lenient(String.self, forKey: .name, default: "Yer")
        aliases = c.lenient([String].self, forKey: .aliases, default: [])
        // Clamps (05a #20). Places are data-only in v1.0 (no UI, no geofence; location reminders are v1.2).
        latitude = min(90, max(-90, c.lenient(Double.self, forKey: .latitude, default: 0)))
        longitude = min(180, max(-180, c.lenient(Double.self, forKey: .longitude, default: 0)))
        radiusMeters = min(1000, max(100, c.lenient(Double.self, forKey: .radiusMeters, default: 150)))
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: Date(timeIntervalSince1970: 0))
    }
}
