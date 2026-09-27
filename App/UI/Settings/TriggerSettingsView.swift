// WP0 STUB (04 §5.2) — replaced by WP11.
import SwiftUI

struct TriggerSettingsView: View {
    var body: some View {
        List {
            Section("Rehberler") {
                ForEach(GuideKind.allCases, id: \.self) { kind in
                    NavigationLink(value: Route.guide(kind)) {
                        Text(kind.rawValue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tetikleyiciler")
    }
}
