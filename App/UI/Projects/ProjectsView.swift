// WP0 STUB (04 §5.2) — replaced by WP10 (03 §4.9).
import SwiftUI
import AsistCore

struct ProjectsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            if store.projects.isEmpty {
                Text("Henüz proje yok.")
                    .foregroundStyle(Color.secondary)
            }
            ForEach(store.projects) { project in
                NavigationLink(value: Route.project(project.id)) {
                    Text(project.name)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Projeler")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.projectEditor(nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Yeni proje")
            }
        }
    }
}
