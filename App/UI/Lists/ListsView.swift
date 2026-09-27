// WP10 — Listeler (03 §4.7, 04 §5.2).
import SwiftUI
import AsistCore

/// Search helper of the list screens: Turkish case- and diacritic-insensitive token match over title, notes,
/// person, project name and the original sentence ("ozet" → "Özet", "IZMIR" → "İzmir"; 03 §4.7).
enum ListItemSearch {
    static func key(_ query: String) -> String {
        TurkishText.searchKey(query)
    }

    static func matches(_ item: Item, key: String, projectName: String?) -> Bool {
        guard !key.isEmpty else { return true }
        var parts: [String] = [item.title, item.notes]
        if let person = item.person { parts.append(person) }
        if let projectName = projectName { parts.append(projectName) }
        if let original = item.originalText { parts.append(original) }
        let haystack = TurkishText.searchKey(parts.joined(separator: " "))
        for token in key.split(separator: " ") {
            if !haystack.contains(String(token)) { return false }
        }
        return true
    }

    static func projectNames(_ projects: [Project]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for project in projects {
            result[project.id] = project.name
        }
        return result
    }

    /// Anchor ascending, undated last; ties by creation.
    static func timeOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        switch (lhs.anchorDate, rhs.anchorDate) {
        case let (left?, right?):
            if left != right { return left < right }
            return lhs.createdAt < rhs.createdAt
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.createdAt > rhs.createdAt
        }
    }

    static func priorityOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return timeOrder(lhs, rhs)
    }
}

/// One navigable list row (value-based `NavigationLink`, 04 §5.1) with the 03 §4.7 swipe actions:
/// leading Yaptım (+ "Doğru" on "Emin değilim" rows, 05b D8) or Yeniden aç; trailing Sil (+ Ertele).
@MainActor
struct ListItemLink: View {
    let item: Item
    let projectName: String?
    let now: Date
    var onSnooze: ((Item) -> Void)? = nil

    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    /// Explicit: private @Environment storage must not narrow the memberwise initializer's access level
    /// (CompletedListView, EndOfDayView and ProjectDetailView construct it too).
    init(item: Item, projectName: String?, now: Date, onSnooze: ((Item) -> Void)? = nil) {
        self.item = item
        self.projectName = projectName
        self.now = now
        self.onSnooze = onSnooze
    }

    var body: some View {
        NavigationLink(value: Route.item(item.id)) {
            ItemRow(item: item, projectName: projectName, now: now) {
                toggleDone()
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            leadingActions
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            trailingActions
        }
    }

    @ViewBuilder
    private var leadingActions: some View {
        if item.status == .done {
            Button {
                DetailItemActions.reopen(item.id, store: store, toasts: toasts)
            } label: {
                Label("Yeniden aç", systemImage: "arrow.uturn.backward")
            }
            .tint(Color.asistAccent)
        } else if item.isOpen && item.kind != .note {
            Button {
                _ = DetailItemActions.markDone(item.id, store: store, toasts: toasts)
            } label: {
                Label(item.kind == .waiting ? "Geldi" : "Yaptım", systemImage: "checkmark")
            }
            .tint(Color.asistDone)
            if item.needsReview {
                Button {
                    DetailItemActions.confirmReview(item.id, store: store, toasts: toasts)
                } label: {
                    Label("Doğru", systemImage: "checkmark.seal")
                }
                .tint(Color.asistReview)
            }
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        Button(role: .destructive) {
            DetailItemActions.delete(item.id, store: store, toasts: toasts)
        } label: {
            Label("Sil", systemImage: "trash")
        }
        if item.isOpen && item.isNotifiable, let onSnooze = onSnooze {
            Button {
                onSnooze(item)
            } label: {
                Label("Ertele", systemImage: Symbol.snooze)
            }
            .tint(Color.asistToday)
        }
    }

    private func toggleDone() {
        if item.status == .done {
            DetailItemActions.reopen(item.id, store: store, toasts: toasts)
        } else if item.isOpen {
            _ = DetailItemActions.markDone(item.id, store: store, toasts: toasts)
        }
    }
}

private enum ListSortOrder: String, CaseIterable {
    case time, priority, created

    var title: String {
        switch self {
        case .time: return "Zamana göre"
        case .priority: return "Önceliğe göre"
        case .created: return "Eklenme sırasına göre"
        }
    }
}

@MainActor
struct ListsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(VoiceCoordinator.self) private var voice

    @State private var query = ""
    @State private var projectFilter: UUID? = nil
    @State private var snoozeTarget: Item? = nil
    @State private var showSnoozeDialog = false
    @AppStorage("asist.lists.sort") private var sortRaw: String = ListSortOrder.time.rawValue

    private struct ListData {
        var main: [Item] = []
        var unscheduled: [Item] = []
        var reminders = 0
        var tasks = 0
        var notes = 0
        var followUps = 0
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            listContent(now: context.date)
        }
        .navigationTitle("Listeler")
        .searchable(text: $query, prompt: "Ara: başlık, not, kişi, proje")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
        .overlay(alignment: .bottomTrailing) {
            MicButton(size: Metrics.micFloating, isActive: voice.phase == .listening) {
                startListening()
            }
            .padding(Metrics.padding)
        }
        .confirmationDialog("Ertele", isPresented: $showSnoozeDialog, titleVisibility: .visible,
                            presenting: snoozeTarget) { item in
            snoozeButtons(item)
        }
    }

    // MARK: - Content

    private func listContent(now: Date) -> some View {
        let filter = router.listFilter
        let data = prepare(now: now, filter: filter)
        let names = ListItemSearch.projectNames(store.projects)
        let searchKey = ListItemSearch.key(query)
        return List {
            Section {
                filterChips(data)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)

            if filter == .completed {
                CompletedItemsSection(now: now, searchKey: searchKey, projectID: projectFilter)
            } else if data.main.isEmpty && data.unscheduled.isEmpty {
                Section {
                    emptyState(filter)
                }
                .listRowBackground(Color.clear)
            } else {
                if !data.main.isEmpty {
                    Section {
                        ForEach(data.main) { item in
                            link(item, now: now, names: names)
                        }
                    } header: {
                        SectionHeader(title: mainHeader(filter), count: data.main.count)
                    }
                }
                if !data.unscheduled.isEmpty {
                    Section {
                        ForEach(data.unscheduled) { item in
                            link(item, now: now, names: names)
                        }
                    } header: {
                        SectionHeader(title: "ZAMANI BELİRSİZ", count: data.unscheduled.count)
                    }
                }
            }
            Color.clear
                .frame(height: Metrics.micFloating)
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
    }

    private func link(_ item: Item, now: Date, names: [UUID: String]) -> some View {
        let projectName = item.projectID.flatMap { names[$0] }
        return ListItemLink(item: item, projectName: projectName, now: now, onSnooze: { target in
            snoozeTarget = target
            showSnoozeDialog = true
        })
    }

    private func filterChips(_ data: ListData) -> some View {
        ChipRow {
            ForEach(ListFilter.allCases, id: \.self) { filter in
                Chip(title: chipTitle(filter, data: data), isSelected: router.listFilter == filter) {
                    if router.listFilter != filter {
                        router.listFilter = filter
                        Haptics.selection()
                    }
                }
            }
            if let projectID = projectFilter {
                Chip(title: "Proje: " + (store.project(projectID)?.name ?? "—"),
                     systemImage: "xmark.circle.fill", isSelected: true) {
                    projectFilter = nil
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Metrics.padding)
    }

    private func chipTitle(_ filter: ListFilter, data: ListData) -> String {
        switch filter {
        case .reminders: return "Hatırlatmalar (" + String(data.reminders) + ")"
        case .tasks: return "Görevler (" + String(data.tasks) + ")"
        case .notes: return "Notlar (" + String(data.notes) + ")"
        case .followUps: return "Takip (" + String(data.followUps) + ")"
        case .completed: return "Tamamlananlar"
        }
    }

    private func mainHeader(_ filter: ListFilter) -> String {
        switch filter {
        case .reminders: return "HATIRLATMALAR"
        case .tasks: return "GÖREVLER"
        case .notes: return "NOTLAR"
        case .followUps: return "TAKİP"
        case .completed: return "TAMAMLANANLAR"
        }
    }

    @ViewBuilder
    private func emptyState(_ filter: ListFilter) -> some View {
        if !ListItemSearch.key(query).isEmpty {
            EmptyStateView(title: "Sonuç bulunamadı", message: "Farklı bir kelime dene.",
                           systemImage: "magnifyingglass")
        } else {
            switch filter {
            case .reminders:
                EmptyStateView(title: "Planlanmış hatırlatma yok",
                               message: "“Yarın 9'da raporu hatırlat” gibi söyleyebilirsin.",
                               systemImage: Symbol.reminder)
            case .tasks:
                EmptyStateView(title: "Açık görev yok", message: "Yeni bir iş için mikrofona dokun.",
                               systemImage: Symbol.taskDone)
            case .notes:
                EmptyStateView(title: "Henüz not yok", message: "“Not al: …” diyerek başlayabilirsin.",
                               systemImage: Symbol.note)
            case .followUps:
                EmptyStateView(title: "Kimseden bir şey beklemiyorsun",
                               message: "“Mehmet cumaya kadar listeyi gönderecek” gibi söyleyebilirsin.",
                               systemImage: Symbol.followUp)
            case .completed:
                EmptyStateView(title: "Tamamlanan iş yok", message: "Bitirdiğin işler burada görünür.",
                               systemImage: Symbol.taskDone)
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Sıralama", selection: $sortRaw) {
                ForEach(ListSortOrder.allCases, id: \.self) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
            Picker("Proje", selection: $projectFilter) {
                Text("Proje: Tümü").tag(UUID?.none)
                ForEach(filterProjects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
        } label: {
            Image(systemName: projectFilter == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Sıralama ve proje filtresi")
    }

    private var filterProjects: [Project] {
        let active = store.projects.filter { !$0.archived || $0.id == projectFilter }
        return active.sorted { lhs, rhs in
            TurkishText.searchKey(lhs.name) < TurkishText.searchKey(rhs.name)
        }
    }

    @ViewBuilder
    private func snoozeButtons(_ item: Item) -> some View {
        ForEach(SnoozeOption.allCases) { option in
            if option == .custom {
                Button(option.title) {
                    router.present(.datePicker(DatePickerRequest(itemID: item.id, purpose: .snooze)))
                }
            } else if option.target(now: Date(), settings: store.settings, calendar: AppTime.calendar) != nil {
                Button(option.title) {
                    applySnooze(option, itemID: item.id)
                }
            }
        }
        Button("Vazgeç", role: .cancel) {}
    }

    // MARK: - Data

    private func prepare(now: Date, filter: ListFilter) -> ListData {
        let key = ListItemSearch.key(query)
        let names = ListItemSearch.projectNames(store.projects)
        var data = ListData()
        var main: [Item] = []
        var unscheduled: [Item] = []
        for item in store.items {
            if let projectID = projectFilter, item.projectID != projectID { continue }
            if item.status == .open {
                switch item.kind {
                case .reminder: data.reminders += 1
                case .task: data.tasks += 1
                case .note: data.notes += 1
                case .waiting: data.followUps += 1
                }
            }
            guard ListsView.belongs(item, to: filter) else { continue }
            let projectName = item.projectID.flatMap { names[$0] }
            guard ListItemSearch.matches(item, key: key, projectName: projectName) else { continue }
            if (filter == .reminders || filter == .tasks) && item.anchorDate == nil {
                unscheduled.append(item)
            } else {
                main.append(item)
            }
        }
        let order = ListSortOrder(rawValue: sortRaw) ?? .time
        if filter == .notes {
            data.main = ListsView.sortNotes(main, order: order)
        } else {
            data.main = ListsView.sort(main, order: order)
        }
        data.unscheduled = unscheduled.sorted { lhs, rhs in
            if order == .priority && lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
        return data
    }

    private static func belongs(_ item: Item, to filter: ListFilter) -> Bool {
        switch filter {
        case .reminders: return item.status == .open && item.kind == .reminder
        case .tasks: return item.status == .open && item.kind == .task
        case .notes: return item.status == .open && item.kind == .note
        case .followUps: return item.status == .open && item.kind == .waiting
        case .completed: return item.status == .done
        }
    }

    private static func sort(_ items: [Item], order: ListSortOrder) -> [Item] {
        switch order {
        case .time:
            return items.sorted(by: ListItemSearch.timeOrder)
        case .priority:
            return items.sorted(by: ListItemSearch.priorityOrder)
        case .created:
            return items.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        }
    }

    /// Notes: newest first (03 §4.7); "Önceliğe göre" keeps priority first.
    private static func sortNotes(_ items: [Item], order: ListSortOrder) -> [Item] {
        items.sorted { lhs, rhs in
            if order == .priority && lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: - Actions

    private func applySnooze(_ option: SnoozeOption, itemID: UUID) {
        guard let target = option.target(now: Date(), settings: store.settings, calendar: AppTime.calendar) else {
            toasts.show("Bu seçenek için artık geç; başka bir zaman seç.")
            return
        }
        DetailItemActions.snooze(itemID, until: target, store: store, toasts: toasts)
    }

    private func startListening() {
        Task {
            await voice.startListening()
        }
    }
}
