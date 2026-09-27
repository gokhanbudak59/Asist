// WP0 STUB (04 §5.2) — replaced by WP10.
import SwiftUI
import AsistCore

struct ProjectDetailView: View {
    let projectID: UUID
    @Environment(DataStore.self) private var store

    var body: some View {
        Text(store.project(projectID)?.name ?? "Proje bulunamadı")
            .navigationTitle("Proje")
            .navigationBarTitleDisplayMode(.inline)
    }
}
