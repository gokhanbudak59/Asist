// FILE: Widgets/AsistTimelineProvider.swift
import Foundation
import WidgetKit
import AsistCore

struct AsistEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// false → no App Group or no snapshot yet: launcher mode (every tap still opens Asist).
    let hasSharedData: Bool
}

struct AsistTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AsistEntry {
        let now = Date()
        return AsistEntry(date: now, snapshot: WidgetSnapshot.placeholder(now: now), hasSharedData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AsistEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(AsistTimelineProvider.currentEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AsistEntry>) -> Void) {
        let now = Date()
        let first = AsistTimelineProvider.currentEntry(at: now)
        var entries: [AsistEntry] = [first]
        for date in first.snapshot.timelineDates(after: now, calendar: WidgetClock.calendar, limit: 20) {
            entries.append(AsistEntry(date: date, snapshot: first.snapshot, hasSharedData: first.hasSharedData))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    static func currentEntry(at date: Date) -> AsistEntry {
        let snapshot = SnapshotStore.read()
        return AsistEntry(date: date, snapshot: snapshot ?? WidgetSnapshot.empty, hasSharedData: snapshot != nil)
    }
}
