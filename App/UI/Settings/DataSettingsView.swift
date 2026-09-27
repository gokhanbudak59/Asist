// WP0 STUB (04 §5.2) — replaced by WP11 (export / security-scoped import / backups).
import SwiftUI

struct DataSettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.recentlyDeleted) {
                    Label("Son silinenler", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Veriler")
    }
}
