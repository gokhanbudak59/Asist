// WP0 STUB (04 §5.1) — replaced by WP9. 4 tabs, one NavigationStack each, classic .tabItem (iOS 17).
import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.todayPath) {
                TodayView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem { Label("Bugün", systemImage: Symbol.tabToday) }
            .tag(AppTab.today)

            NavigationStack(path: $router.listsPath) {
                ListsView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem { Label("Listeler", systemImage: Symbol.tabLists) }
            .tag(AppTab.lists)

            NavigationStack(path: $router.projectsPath) {
                ProjectsView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem { Label("Projeler", systemImage: Symbol.tabProjects) }
            .tag(AppTab.projects)

            NavigationStack(path: $router.settingsPath) {
                SettingsView()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .tabItem { Label("Ayarlar", systemImage: Symbol.tabSettings) }
            .tag(AppTab.settings)
        }
    }
}
