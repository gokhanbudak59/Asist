// WP0 STUB (04 §5.1) — replaced by WP9. `Route → View` switch (already the final mapping).
import SwiftUI

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .item(let id):
            ItemDetailView(itemID: id)
        case .project(let id):
            ProjectDetailView(projectID: id)
        case .endOfDay:
            EndOfDayView()
        case .completed:
            CompletedListView()
        case .recentlyDeleted:
            RecentlyDeletedView()
        case .guide(let kind):
            GuideView(kind: kind)
        case .appStatus:
            AppStatusView()
        case .diagnostics:
            DiagnosticsView()
        case .generalSettings:
            GeneralSettingsView()
        case .timeSettings:
            TimeSettingsView()
        case .nagSettings:
            NagSettingsView()
        case .summarySettings:
            SummarySettingsView()
        case .triggerSettings:
            TriggerSettingsView()
        case .dataSettings:
            DataSettingsView()
        }
    }
}
