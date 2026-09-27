// Revision 4 (07 §5.9, R4-D5): writes the widget snapshot into the App Group container after every data change
// (called only from AppEnvironment: dataDidChange, scene active, scene background). Synchronous by design — ≤ 12
// entries, one small file. Without the App Group entitlement (free signing may strip it) this is a logged no-op and
// the widgets stay in launcher mode; the Control Center / Lock Screen buttons never need the group.
import Foundation
import WidgetKit
import AsistCore

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// Last successful write in this process (AppStatusView "Son güncelleme").
    private(set) var lastWriteAt: Date?

    private var lastWritten: WidgetSnapshot?
    private var availabilityLogged = false
    private var failureLogged = false
    private var writeCount = 0

    init() {}

    /// SnapshotStore.isAvailable (App Group container resolved).
    var isAvailable: Bool { SnapshotStore.isAvailable }

    /// No-op while !store.isLoaded (never publish defaults, 05a #26) or when unavailable (logged once, .widget).
    /// Builds WidgetSnapshotBuilder.build(items: store.items, settings: store.settings, now: now,
    /// calendar: AppTime.calendar); skips when equivalent to the last written snapshot (equal apart from
    /// generatedAt, same day); otherwise SnapshotStore.write → WidgetCenter.shared.reloadAllTimelines().
    func refresh(store: DataStore, now: Date) {
        guard store.isLoaded else { return }
        let available = SnapshotStore.isAvailable
        if !availabilityLogged {
            availabilityLogged = true
            if available {
                AsistLog.info("Widget veri paylaşımı açık (App Group bulundu).", .widget)
            } else {
                AsistLog.info("Widget veri paylaşımı kapalı (App Group yok); widget'lar yalnız Asist'i açar.", .widget)
            }
        }
        guard available else { return }

        let calendar = AppTime.calendar
        let snapshot = WidgetSnapshotBuilder.build(items: store.items, settings: store.settings, now: now,
                                                   calendar: calendar)
        if let previous = lastWritten, WidgetSnapshotBuilder.isEquivalent(previous, snapshot, calendar: calendar) {
            return
        }
        guard SnapshotStore.write(snapshot) else {
            if !failureLogged {
                failureLogged = true
                AsistLog.error("Widget verisi yazılamadı.", .widget)
            }
            return
        }
        lastWritten = snapshot
        lastWriteAt = now
        writeCount += 1
        if writeCount == 1 || writeCount % 25 == 0 {
            AsistLog.info("Widget verisi yazıldı (" + String(writeCount) + ". kez, " + String(snapshot.entries.count)
                          + " satır).", .widget)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
