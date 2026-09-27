// WP9 (04 §5.1; 03 §4.1): 4 tabs, one NavigationStack each (path owned by AppRouter), classic .tabItem (iOS 17),
// one `.navigationDestination(for: Route.self)` per stack on its root view.
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
