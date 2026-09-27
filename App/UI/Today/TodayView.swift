// WP0 STUB (04 §5.2) — replaced by WP9 (03 §4.3).
import SwiftUI
import AsistCore

struct TodayView: View {
    var body: some View {
        List {
            Section {
                Text("Bugün ekranı hazırlanıyor.")
                    .foregroundStyle(Color.secondary)
            }
            Section {
                NavigationLink(value: Route.endOfDay) {
                    Label("Gün sonu", systemImage: Symbol.endOfDay)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bugün")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MuteMenu()
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomCaptureBar()
        }
    }
}
