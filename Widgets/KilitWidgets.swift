// FILE: Widgets/KilitWidgets.swift
// Revision 4 (07 §5.1, §5.8): lock screen widgets — "Asist Dinle" (accessoryCircular, tap = listen) and
// "Sıradaki iş" (accessoryRectangular: counter line, next entry title, its time). Launcher text without data.
import SwiftUI
import WidgetKit
import AsistCore

struct AsistDinleKilitWidget: Widget {
    let kind = "AsistDinleKilitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AsistTimelineProvider()) { entry in
            DinleKilitView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Asist Dinle")
        .description("Kilit ekranından tek dokunuşla Asist'i açıp dinlet.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AsistSiradakiWidget: Widget {
    let kind = "AsistSiradakiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AsistTimelineProvider()) { entry in
            SiradakiKilitView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sıradaki iş")
        .description("Sıradaki işin ve geciken sayısı.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Mic only: works the same with or without shared data.
struct DinleKilitView: View {
    let entry: AsistEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .semibold))
                .widgetAccentable()
        }
        .widgetURL(WidgetLinks.listen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asist Dinle")
    }
}

struct SiradakiKilitView: View {
    let entry: AsistEntry

    var body: some View {
        if entry.hasSharedData {
            content
        } else {
            launcher
        }
    }

    private var content: some View {
        let snapshot = entry.snapshot
        let first = snapshot.visibleEntries(at: entry.date).first
        let link = first.map { (next: WidgetSnapshot.Entry) -> URL in WidgetLinks.item(next.id) } ?? WidgetLinks.today
        return VStack(alignment: .leading, spacing: 1) {
            Text(SiradakiKilitView.headline(for: entry))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            if let next = first {
                Text(next.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive(snapshot.hideTitlesWhenLocked)
                Text(WidgetClock.whenText(next, snapshot: snapshot, now: entry.date))
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("Planlı iş yok")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(link)
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Asist")
                .font(.headline)
                .widgetAccentable()
            Text("Dokun, dinlesin")
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLinks.listen)
    }

    /// "Asist · 2 geciken" / "Asist · 5 bugün" / "Asist".
    static func headline(for entry: AsistEntry) -> String {
        let counts = WidgetClock.counts(entry)
        if counts.overdue > 0 {
            return "Asist · " + String(counts.overdue) + " geciken"
        }
        if counts.today > 0 {
            return "Asist · " + String(counts.today) + " bugün"
        }
        return "Asist"
    }
}
