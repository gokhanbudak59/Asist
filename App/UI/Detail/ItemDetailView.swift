// WP0 STUB (04 §5.2) — replaced by WP10 (03 §4.8).
import SwiftUI
import AsistCore

struct ItemDetailView: View {
    let itemID: UUID
    @Environment(DataStore.self) private var store

    var body: some View {
        List {
            if let item = store.item(itemID), item.status != .deleted {
                Section {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                }
            } else {
                Section {
                    Text("Kayıt bulunamadı")
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ayrıntı")
        .navigationBarTitleDisplayMode(.inline)
    }
}
