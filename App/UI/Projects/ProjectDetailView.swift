// WP10 — Proje detayı (03 §4.9): İşler / Notlar / Tamamlanan + "Bu projeye sesli not".
// WP13: "Özetle" (Akıllı Mod) on the Notlar tab when Smart Mode is on and a key is stored.
import SwiftUI
import UIKit
import AsistCore

@MainActor
struct ProjectDetailView: View {
    let projectID: UUID

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(VoiceCoordinator.self) private var voice

    private enum ProjectTab: String, CaseIterable {
        case items, notes, done

        var title: String {
            switch self {
            case .items: return "İşler"
            case .notes: return "Notlar"
            case .done: return "Tamamlanan"
            }
        }
    }

    private struct TabData {
        var overdue: [Item] = []
        var open: [Item] = []
        var followUps: [Item] = []
        var notes: [Item] = []
        var done: [Item] = []
    }

    @State private var tab: ProjectTab = .items
    /// WP13 "Özetle".
    @State private var smartReady = false
    @State private var summaryBusy = false
    @State private var summaryOutcome: SmartSummaryOutcome? = nil
    @State private var summaryError: String? = nil

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (RouteDestination.swift).
    init(projectID: UUID) {
        self.projectID = projectID
    }

    var body: some View {
        Group {
            if let project = store.project(projectID) {
                TimelineView(.everyMinute) { context in
                    detail(project, now: context.date)
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
            } else {
                EmptyStateView(title: "Proje bulunamadı",
                               message: "Bu proje silinmiş ya da artık mevcut değil.",
                               systemImage: Symbol.project)
            }
        }
        .navigationTitle(store.project(projectID)?.name ?? "Proje")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSmartReady()
        }
        .onChange(of: store.settings.smartModeEnabled) { _, _ in
            refreshSmartReady()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let project = store.project(projectID) {
                    menu(project)
                }
            }
        }
    }

    // MARK: - Layout

    private func detail(_ project: Project, now: Date) -> some View {
        let calendar = AppTime.calendar
        let data = collect(now: now, calendar: calendar)
        let stats = ProjectStats.compute(items: store.items, now: now, calendar: calendar)[projectID] ?? ProjectStats()
        return List {
            Section {
                header(project, stats: stats)
                Picker("Görünüm", selection: $tab) {
                    ForEach(ProjectTab.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
            switch tab {
            case .items:
                itemsSections(data, now: now)
            case .notes:
                notesSection(data, now: now)
            case .done:
                doneSection(data, now: now)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func header(_ project: Project, stats: ProjectStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.project(project.color))
                    .frame(width: 14, height: 14)
                Text(project.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
            }
            Text(stats.countsText)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(stats.overdue > 0 ? Color.asistOverdue : Color.secondary)
            if !project.aliases.isEmpty {
                Text("Takma adlar: " + project.aliases.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if project.archived {
                Label("Arşivde", systemImage: "archivebox")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func itemsSections(_ data: TabData, now: Date) -> some View {
        if data.overdue.isEmpty && data.open.isEmpty && data.followUps.isEmpty {
            Section {
                EmptyStateView(title: "Açık iş yok", message: "Bu projede bekleyen bir iş görünmüyor.",
                               systemImage: Symbol.taskDone)
            }
            .listRowBackground(Color.clear)
        }
        if !data.overdue.isEmpty {
            Section {
                ForEach(data.overdue) { item in
                    ListItemLink(item: item, projectName: nil, now: now)
                }
            } header: {
                SectionHeader(title: "GECİKENLER", count: data.overdue.count, color: Color.asistOverdue)
            }
        }
        if !data.open.isEmpty {
            Section {
                ForEach(data.open) { item in
                    ListItemLink(item: item, projectName: nil, now: now)
                }
            } header: {
                SectionHeader(title: "AÇIK İŞLER", count: data.open.count)
            }
        }
        if !data.followUps.isEmpty {
            Section {
                ForEach(data.followUps) { item in
                    ListItemLink(item: item, projectName: nil, now: now)
                }
            } header: {
                SectionHeader(title: "TAKİP", count: data.followUps.count, color: Color.asistFollowUp)
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ data: TabData, now: Date) -> some View {
        if data.notes.isEmpty {
            Section {
                EmptyStateView(title: "Henüz not yok", message: "Aşağıdaki düğmeyle bu projeye sesli not ekleyebilirsin.",
                               systemImage: Symbol.note)
            }
            .listRowBackground(Color.clear)
        } else {
            if smartReady {
                smartSummarySection(notes: data.notes)
            }
            Section {
                ForEach(data.notes) { item in
                    NavigationLink(value: Route.item(item.id)) {
                        noteRow(item, now: now)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            DetailItemActions.delete(item.id, store: store, toasts: toasts)
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            } header: {
                SectionHeader(title: "NOTLAR", count: data.notes.count)
            }
        }
    }

    @ViewBuilder
    private func doneSection(_ data: TabData, now: Date) -> some View {
        if data.done.isEmpty {
            Section {
                EmptyStateView(title: "Tamamlanan iş yok", message: "Bu projede bitirdiğin işler burada görünür.",
                               systemImage: Symbol.taskDone)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(data.done) { item in
                    ListItemLink(item: item, projectName: nil, now: now)
                }
            } header: {
                SectionHeader(title: "TAMAMLANAN", count: data.done.count)
            }
        }
    }

    // MARK: - Akıllı Mod summary (WP13)

    private func smartSummarySection(notes: [Item]) -> some View {
        Section {
            Button {
                summarize(notes)
            } label: {
                HStack(spacing: 10) {
                    Label(summaryButtonTitle, systemImage: Symbol.smartMode)
                    Spacer()
                    if summaryBusy {
                        ProgressView()
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(summaryBusy)
            if let outcome = summaryOutcome {
                summaryRows(outcome)
            }
            if let message = summaryError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader(title: "AKILLI ÖZET")
        } footer: {
            Text("“Özetle” bu projenin not metinlerini Anthropic'e gönderir.")
        }
    }

    @ViewBuilder
    private func summaryRows(_ outcome: SmartSummaryOutcome) -> some View {
        if !outcome.summary.summary.isEmpty {
            Text(outcome.summary.summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        ForEach(Array(outcome.summary.actionItems.enumerated()), id: \.offset) { entry in
            Label(entry.element, systemImage: "checkmark.circle")
                .font(.subheadline)
        }
        if outcome.usedNotes < outcome.totalNotes {
            Text(summaryCoverageText(outcome))
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
        Button {
            copySummary(outcome)
        } label: {
            Label("Özeti kopyala", systemImage: "doc.on.doc")
                .frame(minHeight: 44)
        }
    }

    private var summaryButtonTitle: String {
        if summaryBusy {
            return "Özetleniyor…"
        }
        return summaryOutcome == nil ? "Özetle" : "Yeniden özetle"
    }

    private func summaryCoverageText(_ outcome: SmartSummaryOutcome) -> String {
        "En yeni " + String(outcome.usedNotes) + " not özetlendi (toplam " + String(outcome.totalNotes) + ")."
    }

    private func noteRow(_ item: Item, now: Date) -> some View {
        let preview = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = TurkishDateFormatter.shortDateTime(item.createdAt, now: now, calendar: AppTime.calendar,
                                                      includeTime: true)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body.weight(.medium))
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
            }
            Text(date)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Button {
                startVoiceNote()
            } label: {
                Label("Bu projeye sesli not", systemImage: Symbol.mic)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                router.present(.compose(ListenRequest(kind: .note, projectID: projectID)))
            } label: {
                Image(systemName: Symbol.keyboard)
                    .font(.title3)
                    .frame(width: Metrics.primaryButtonHeight, height: Metrics.primaryButtonHeight)
                    .background(Color.asistAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yazarak not ekle")
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func menu(_ project: Project) -> some View {
        Menu {
            Button {
                router.present(.projectEditor(project.id))
            } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            Button {
                toggleArchive(project)
            } label: {
                if project.archived {
                    Label("Arşivden çıkar", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Arşivle", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Proje işlemleri")
    }

    // MARK: - Data

    private func collect(now: Date, calendar: Calendar) -> TabData {
        var data = TabData()
        for item in store.items where item.projectID == projectID {
            switch item.status {
            case .deleted:
                continue
            case .done:
                data.done.append(item)
            case .open:
                if item.kind == .note {
                    data.notes.append(item)
                } else if item.isOverdue(at: now, calendar: calendar) {
                    data.overdue.append(item)
                } else if item.kind == .waiting {
                    data.followUps.append(item)
                } else {
                    data.open.append(item)
                }
            }
        }
        data.overdue.sort(by: ListItemSearch.priorityOrder)
        data.open.sort(by: ListItemSearch.timeOrder)
        data.followUps.sort(by: ListItemSearch.timeOrder)
        data.notes.sort { lhs, rhs in lhs.createdAt > rhs.createdAt }
        data.done.sort { lhs, rhs in
            (lhs.completedAt ?? lhs.updatedAt) > (rhs.completedAt ?? rhs.updatedAt)
        }
        return data
    }

    // MARK: - Actions

    private func refreshSmartReady() {
        smartReady = SmartModeClient.shared.isReady(store.settings)
    }

    /// WP13: sends only this project's name and note texts (newest first, dated) — never other data.
    private func summarize(_ notes: [Item]) {
        guard !summaryBusy, let project = store.project(projectID) else { return }
        summaryBusy = true
        summaryError = nil
        let settings = store.settings
        let calendar = AppTime.calendar
        var texts: [String] = []
        for note in notes {
            let body = note.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = body.isEmpty ? note.title : body
            texts.append(SettingsFormat.dayMonthYear(note.createdAt, calendar: calendar) + ": " + text)
        }
        let name = project.name
        Task { @MainActor in
            let result = await SmartModeClient.shared.summarize(notes: texts, project: name, settings: settings)
            summaryBusy = false
            switch result {
            case .success(let outcome):
                summaryOutcome = outcome
                Haptics.success()
            case .failure(let error):
                summaryError = error.userMessage
                Haptics.warning()
            }
        }
    }

    private func copySummary(_ outcome: SmartSummaryOutcome) {
        var lines: [String] = []
        if !outcome.summary.summary.isEmpty {
            lines.append(outcome.summary.summary)
        }
        for action in outcome.summary.actionItems {
            lines.append("• " + action)
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        toasts.show("Özet kopyalandı")
        Haptics.selection()
    }

    private func startVoiceNote() {
        let request = ListenRequest(kind: .note, projectID: projectID)
        Task {
            await voice.startListening(request)
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
