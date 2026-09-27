// WP0 STUB (04 §5.2) — replaced by WP10 (03 §4.7).
import SwiftUI
import AsistCore

struct ListsView: View {
    var body: some View {
        List {
            Section {
                Text("Listeler hazırlanıyor.")
                    .foregroundStyle(Color.secondary)
            }
            Section {
                NavigationLink(value: Route.completed) {
                    Label("Tamamlananlar", systemImage: Symbol.taskDone)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Listeler")
    }
}
