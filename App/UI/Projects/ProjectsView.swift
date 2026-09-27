// WP10 — Projeler listesi (03 §4.9, 04 §5.2).
import SwiftUI
import AsistCore

/// Per-project counters for rows and headers (03 §4.9 "4 açık · 1 geciken · 2 takip").
struct ProjectStats {
    var open = 0
    var overdue = 0
    var followUps = 0
    var lastNote: String? = nil
    var lastNoteDate: Date? = nil
    var lastActivity: Date = Date(timeIntervalSince1970: 0)

    var countsText: String {
        String(open) + " açık · " + String(overdue) + " geciken · " + String(followUps) + " takip"
    }

    static func compute(items: [Item], now: Date, calendar: Calendar) -> [UUID: ProjectStats] {
        var result: [UUID: ProjectStats] = [:]
        for item in items where item.status != .deleted {
            guard let projectID = item.projectID else { continue }
            var stats = result[projectID] ?? ProjectStats()
            if item.updatedAt > stats.lastActivity {
                stats.lastActivity = item.updatedAt
            }
            if item.isOpen {
                if item.kind == .note {
                    let isNewer: Bool
                    if let current = stats.lastNoteDate {
                        isNewer = item.createdAt > current
                    } else {
                        isNewer = true
                    }
                    if isNewer {
                        stats.lastNoteDate = item.createdAt
                        stats.lastNote = item.title
                    }
                } else {
                    stats.open += 1
                    if item.kind == .waiting {
                        stats.followUps += 1
                    }
                    if item.isOverdue(at: now, calendar: calendar) {
                        stats.overdue += 1
                    }
                }
            }
            result[projectID] = stats
        }
        return result
    }
}

@MainActor
struct ProjectsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle("Projeler")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.push(.weeklyReport)
                } label: {
                    Image(systemName: "doc.text")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Haftalık rapor")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.projectEditor(nil))
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Yeni Proje")
            }
        }
    }

    private func content(now: Date) -> some View {
        let stats = ProjectStats.compute(items: store.items, now: now, calendar: AppTime.calendar)
        let active = sortedActive(stats: stats)
        let archived = store.projects.filter { $0.archived }.sorted { lhs, rhs in
            TurkishText.searchKey(lhs.name) < TurkishText.searchKey(rhs.name)
        }
        return List {
            if store.projects.isEmpty {
                Section {
                    VStack(spacing: Metrics.cardSpacing) {
                        EmptyStateView(title: "Henüz proje yok",
                                       message: "Söylediklerinde proje adı geçince eklemeyi önereceğim.",
                                       systemImage: Symbol.project)
                        Button {
                            router.present(.projectEditor(nil))
                        } label: {
                            Label("Yeni Proje", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { project in
                        projectLink(project, stats: stats[project.id] ?? ProjectStats())
                    }
                }
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { project in
                        projectLink(project, stats: stats[project.id] ?? ProjectStats())
                    }
                } header: {
                    SectionHeader(title: "ARŞİV", count: archived.count)
                } footer: {
                    Text("Arşivdeki projeler sesle tanımada kullanılmaz; kayıtları durur.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Projects with overdue items first, then the most recent activity (03 §4.9).
    private func sortedActive(stats: [UUID: ProjectStats]) -> [Project] {
        let active = store.projects.filter { !$0.archived }
        return active.sorted { lhs, rhs in
            let left = stats[lhs.id] ?? ProjectStats()
            let right = stats[rhs.id] ?? ProjectStats()
            let leftOverdue = left.overdue > 0
            let rightOverdue = right.overdue > 0
            if leftOverdue != rightOverdue { return leftOverdue }
            let leftActivity = max(left.lastActivity, lhs.updatedAt)
            let rightActivity = max(right.lastActivity, rhs.updatedAt)
            if leftActivity != rightActivity { return leftActivity > rightActivity }
            return TurkishText.searchKey(lhs.name) < TurkishText.searchKey(rhs.name)
        }
    }

    private func projectLink(_ project: Project, stats: ProjectStats) -> some View {
        NavigationLink(value: Route.project(project.id)) {
            ProjectRowContent(project: project, stats: stats)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleArchive(project)
            } label: {
                if project.archived {
                    Label("Arşivden çıkar", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Arşivle", systemImage: "archivebox")
                }
            }
            .tint(Color.asistNote)
            Button {
                router.present(.projectEditor(project.id))
            } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            .tint(Color.asistAccent)
        }
    }

    private func toggleArchive(_ project: Project) {
        let target = !project.archived
        store.archiveProject(project.id, archived: target)
        if store.canPersist {
            toasts.show(target ? "Proje arşivlendi" : "Proje arşivden çıkarıldı")
            Haptics.selection()
        } else {
            DetailItemActions.reportNil("arşiv", store: store, toasts: toasts)
        }
    }
}

/// Row: color stripe + name + counts + first line of the latest note.
struct ProjectRowContent: View {
    let project: Project
    let stats: ProjectStats

    var body: some View {
        HStack(spacing: Metrics.cardSpacing) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.project(project.color))
                .frame(width: Metrics.stripeWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if stats.overdue > 0 {
                        Image(systemName: Symbol.overdue)
                            .foregroundStyle(Color.asistOverdue)
                            .font(.caption)
                    }
                    Text(stats.countsText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(stats.overdue > 0 ? Color.asistOverdue : Color.secondary)
                }
                if let note = stats.lastNote, !note.isEmpty {
                    Label(note, systemImage: Symbol.note)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}
