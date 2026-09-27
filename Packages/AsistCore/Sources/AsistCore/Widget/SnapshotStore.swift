// FILE: Packages/AsistCore/Sources/AsistCore/Widget/SnapshotStore.swift
import Foundation

#if canImport(Darwin)
/// Widget snapshot file in the App Group container. Every call is nil/false-safe when the group entitlement is
/// missing (free signing, R4-D4).
public enum SnapshotStore {
    public static let fileName = "widget_snapshot.json"

    private static let containerURL: URL? = SharedContainerLocator.resolve()?.containerURL

    public static var isAvailable: Bool { containerURL != nil }

    public static func fileURL() -> URL? {
        containerURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
#endif
