// WP0 STUB (04 §5.2) — replaced by WP11 (03 §4.11).
import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.generalSettings) {
                    Label("Genel", systemImage: "person.crop.circle")
                }
                NavigationLink(value: Route.timeSettings) {
                    Label("Zamanlar", systemImage: "clock")
                }
                NavigationLink(value: Route.nagSettings) {
                    Label("Israr", systemImage: Symbol.snooze)
                }
                NavigationLink(value: Route.summarySettings) {
                    Label("Özetler", systemImage: Symbol.briefing)
                }
                NavigationLink(value: Route.triggerSettings) {
                    Label("Tetikleyiciler", systemImage: Symbol.backTap)
                }
                NavigationLink(value: Route.dataSettings) {
                    Label("Veriler", systemImage: Symbol.export)
                }
            }
            Section {
                NavigationLink(value: Route.appStatus) {
                    Label("Uygulama durumu", systemImage: "checkmark.shield")
                }
                NavigationLink(value: Route.diagnostics) {
                    Label("Tanılama", systemImage: "stethoscope")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ayarlar")
    }
}
