// WP10 — Tamamlananlar (03 §4.7): son 90 gün, "Daha eski" ile tamamı; kaydırma "Yeniden aç".
import SwiftUI
import AsistCore

@MainActor
struct CompletedListView: View {
    @State private var query = ""

    var body: some View {
        TimelineView(.everyMinute) { context in
            List {
                CompletedItemsSection(now: context.date, searchKey: ListItemSearch.key(query), projectID: nil)
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Tamamlananlar")
        .searchable(text: $query, prompt: "Ara: başlık, not, kişi, proje")
    }
}

/// Sections of completed items (used by `CompletedListView` and the "Tamamlananlar" filter of `ListsView`).
@MainActor
struct CompletedItemsSection: View {
    let now: Date
    let searchKey: String
    let projectID: UUID?

    @Environment(DataStore.self) private var store
    @State private var showOlder = false

    /// Explicit: private @State/@Environment storage must not narrow the memberwise initializer's access level.
    init(now: Date, searchKey: String, projectID: UUID?) {
        self.now = now
        self.searchKey = searchKey
        self.projectID = projectID
    }

    private struct Parts {
        var recent: [Item] = []
        var older: [Item] = []
    }

    var body: some View {
        let parts = partition()
        let names = ListItemSearch.projectNames(store.projects)
        if parts.recent.isEmpty && parts.older.isEmpty {
            Section {
                if searchKey.isEmpty {
                    EmptyStateView(title: "Tamamlanan iş yok", message: "Bitirdiğin işler burada görünür.",
                                   systemImage: Symbol.taskDone)
                } else {
                    EmptyStateView(title: "Sonuç bulunamadı", message: "Farklı bir kelime dene.",
                                   systemImage: "magnifyingglass")
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                if parts.recent.isEmpty {
                    Text("Son 90 günde tamamlanan iş yok.")
                        .foregroundStyle(Color.secondary)
                }
                ForEach(parts.recent) { item in
                    row(item, names: names)
                }
                if !showOlder && !parts.older.isEmpty {
                    Button("Daha eski (\(parts.older.count))") {
                        showOlder = true
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                SectionHeader(title: "SON 90 GÜN", count: parts.recent.count)
            }
            if showOlder && !parts.older.isEmpty {
                Section {
                    ForEach(parts.older) { item in
                        row(item, names: names)
                    }
                } header: {
                    SectionHeader(title: "DAHA ESKİ", count: parts.older.count)
                }
            }
        }
    }

    private func row(_ item: Item, names: [UUID: String]) -> some View {
        let projectName = item.projectID.flatMap { names[$0] }
        return ListItemLink(item: item, projectName: projectName, now: now)
    }

    private static func doneDate(_ item: Item) -> Date {
        item.completedAt ?? item.updatedAt
    }

    private func partition() -> Parts {
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let names = ListItemSearch.projectNames(store.projects)
        var parts = Parts()
        for item in store.items where item.status == .done {
            if let projectID = projectID, item.projectID != projectID { continue }
            let projectName = item.projectID.flatMap { names[$0] }
            guard ListItemSearch.matches(item, key: searchKey, projectName: projectName) else { continue }
            if CompletedItemsSection.doneDate(item) >= cutoff {
                parts.recent.append(item)
            } else {
                parts.older.append(item)
            }
        }
        parts.recent.sort { lhs, rhs in
            CompletedItemsSection.doneDate(lhs) > CompletedItemsSection.doneDate(rhs)
        }
        parts.older.sort { lhs, rhs in
            CompletedItemsSection.doneDate(lhs) > CompletedItemsSection.doneDate(rhs)
        }
        return parts
    }
}
