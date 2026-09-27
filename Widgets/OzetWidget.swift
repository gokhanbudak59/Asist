// FILE: Widgets/OzetWidget.swift
// Revision 4 (07 §5.1, §5.8): home screen widget "Asist" — small (counters, tap = listen) and medium (counters,
// "Dinle" / "Yaz" buttons, next three entries). Launcher layouts when the App Group snapshot is missing.
import SwiftUI
import WidgetKit
import AsistCore

struct AsistOzetWidget: Widget {
    let kind = "AsistOzetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AsistTimelineProvider()) { entry in
            OzetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Asist")
        .description("Geciken, bugün ve takip sayıları. Dokun, Asist dinlesin.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct OzetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AsistEntry

    /// Explicit: private environment storage must not narrow the memberwise initializer.
    init(entry: AsistEntry) {
        self.entry = entry
    }

    var body: some View {
        switch family {
        case .systemMedium:
            if entry.hasSharedData {
                medium
            } else {
                launcherMedium
            }
        default:
            if entry.hasSharedData {
                small
            } else {
                launcherSmall
            }
        }
    }

    // MARK: Small

    private var small: some View {
        let counts = WidgetClock.counts(entry)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(Color.indigo)
                Text("Asist")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            OzetCounterLine(count: counts.overdue, label: "geciken",
                            color: counts.overdue > 0 ? Color.red : Color.secondary)
            OzetCounterLine(count: counts.today, label: "bugün",
                            color: counts.today > 0 ? Color.primary : Color.secondary)
            OzetCounterLine(count: counts.followUp, label: "takip",
                            color: counts.followUp > 0 ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
            Text("Dokun, dinlesin")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLinks.listen)
    }

    private var launcherSmall: some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.indigo)
            Text("Dinle")
                .font(.title3.weight(.bold))
            Text("Dokun, Asist dinlesin")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetLinks.listen)
        .accessibilityElement(children: .combine)
    }

    // MARK: Medium

    private var medium: some View {
        let counts = WidgetClock.counts(entry)
        let rows = Array(entry.snapshot.visibleEntries(at: entry.date).prefix(3))
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                OzetCounterLine(count: counts.overdue, label: "geciken",
                                color: counts.overdue > 0 ? Color.red : Color.secondary)
                OzetCounterLine(count: counts.today, label: "bugün",
                                color: counts.today > 0 ? Color.primary : Color.secondary)
                OzetCounterLine(count: counts.followUp, label: "takip",
                                color: counts.followUp > 0 ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Link(destination: WidgetLinks.listen) {
                        OzetActionLabel(title: "Dinle", systemImage: "mic.fill")
                    }
                    Link(destination: WidgetLinks.compose) {
                        OzetActionLabel(title: "Yaz", systemImage: "square.and.pencil")
                    }
                }
            }
            .frame(width: 136, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 6) {
                if rows.isEmpty {
                    Spacer(minLength: 0)
                    Text("Planlı iş yok")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(rows) { row in
                        Link(destination: WidgetLinks.item(row.id)) {
                            OzetEntryRow(entry: row, snapshot: entry.snapshot, now: entry.date)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(WidgetLinks.today)
    }

    private var launcherMedium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(Color.indigo)
                Text("Asist")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Link(destination: WidgetLinks.listen) {
                    OzetLauncherTile(title: "Dinle", systemImage: "mic.fill")
                }
                Link(destination: WidgetLinks.compose) {
                    OzetLauncherTile(title: "Yaz", systemImage: "square.and.pencil")
                }
                Link(destination: WidgetLinks.today) {
                    OzetLauncherTile(title: "Bugün", systemImage: "sun.max.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLinks.listen)
    }
}

/// "3 geciken" — number large, label small; one accessibility element.
struct OzetCounterLine: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(count))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// One of the medium widget's "Dinle" / "Yaz" buttons (≥ 44 pt high).
struct OzetActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Launcher-mode tile of the medium widget.
struct OzetLauncherTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.indigo)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Medium widget row: title (1 line) + time or red "gecikti".
struct OzetEntryRow: View {
    let entry: WidgetSnapshot.Entry
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let overdue = snapshot.isOverdue(entry, at: now)
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .privacySensitive(snapshot.hideTitlesWhenLocked)
            Text(WidgetClock.whenText(entry, snapshot: snapshot, now: now))
                .font(.caption)
                .foregroundStyle(overdue ? Color.red : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
