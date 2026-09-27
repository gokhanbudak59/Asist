// FILE: App/Routing/AppRouter.swift
import Foundation
import Observation
import AsistCore

enum AppTab: Hashable {
    case today, lists, projects, settings

    /// `asist://sekme/<kod>` target → tab.
    init(deepLink tab: DeepLinkTab) {
        switch tab {
        case .today: self = .today
        case .lists: self = .lists
        case .projects: self = .projects
        case .settings: self = .settings
        }
    }
}

/// backTap = guide A (headless "Asist Hızlı Kayıt"), backTapListen = guide A-alt ("Asist Dinle"), siri = C,
/// focus = E, banners = "Bildirimler ekranda kalsın" (Banner Stili › Kalıcı, 05b A9).
enum GuideKind: String, Hashable, CaseIterable { case backTap, backTapListen, siri, focus, banners }

enum ListFilter: String, Hashable, CaseIterable { case reminders, tasks, notes, followUps, completed }

enum Route: Hashable {
    case item(UUID)
    case project(UUID)
    case endOfDay
    case completed
    case recentlyDeleted
    case guide(GuideKind)
    case appStatus
    case diagnostics
    case generalSettings
    case timeSettings
    case nagSettings
    case summarySettings
    case triggerSettings
    case dataSettings
    // Revision 4 (07)
    case weeklyReport
    case people
    case person(String)          // PersonSummary.key
    case places
    case placeEditor(UUID)
    case updates
    case calendarSettings
}

struct ListenRequest: Equatable {
    var kind: ItemKind? = nil
    var projectID: UUID? = nil
    /// Non-nil: the utterance is a new time for this item ("Sesle ertele", 05b D5), never a new capture.
    var snoozeItemID: UUID? = nil

    init(kind: ItemKind? = nil, projectID: UUID? = nil, snoozeItemID: UUID? = nil) {
        self.kind = kind
        self.projectID = projectID
        self.snoozeItemID = snoozeItemID
    }
}

enum DatePickerPurpose: Equatable { case snooze, due }

struct DatePickerRequest: Equatable {
    var itemID: UUID
    var purpose: DatePickerPurpose
}

enum PendingAction: Equatable {
    case listen(ListenRequest)
    case compose
    case readAgenda
    case openItem(UUID)
    case completeItem(UUID)
    case endOfDay
    case today
    case followUpMessage(UUID)
    case settingsTriggers
    case dataSettings
    case showTab(AppTab)
    case openScreen(DeepLinkScreen)
    case editItem(UUID)
}

enum SheetRoute: Identifiable {
    case compose(ListenRequest)
    case confirm(CaptureDraft)
    case match(MatchProposal)
    case agenda(SpokenAnswer)
    case datePicker(DatePickerRequest)
    case projectEditor(UUID?)
    case followUpMessage(UUID)
    case editItem(UUID)

    var id: String {
        switch self {
        case .compose: return "compose"
        case .confirm(let draft): return "confirm-" + draft.id.uuidString
        case .match(let proposal): return "match-" + proposal.id.uuidString
        case .agenda(let answer): return "agenda-" + answer.id
        case .datePicker(let request): return "date-" + request.itemID.uuidString
        case .projectEditor(let id): return "project-" + (id?.uuidString ?? "new")
        case .followUpMessage(let id): return "fu-" + id.uuidString
        case .editItem(let id): return "edit-" + id.uuidString
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var todayPath: [Route] = []
    var listsPath: [Route] = []
    var projectsPath: [Route] = []
    var settingsPath: [Route] = []
    var listFilter: ListFilter = .reminders
    var sheet: SheetRoute?
    /// In-memory voice → "Klavye" hand-off (ListeningOverlay): the partial transcript the next ComposeSheet
    /// starts with, added below any stored draft. Never persisted; ComposeSheet takes and clears it on load.
    var composeSeedText: String?
    /// Set true only by AppEnvironment.sceneDidBecomeActive (store loaded && !onboardingCompleted); false by OnboardingView.
    var showOnboarding = false
    private(set) var pending: PendingAction?

    /// Queue an action; RootView consumes it when the scene is active (+350 ms for listening, 01b §1.3).
    func request(_ action: PendingAction) {
        pending = action
    }

    func takePending() -> PendingAction? {
        let action = pending
        pending = nil
        return action
    }

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .listen(let kind, let projectID): request(.listen(ListenRequest(kind: kind, projectID: projectID)))
        case .compose: request(.compose)
        case .today: request(.today)
        case .item(let id): request(.openItem(id))
        case .completeItem(let id): request(.completeItem(id))
        case .endOfDay: request(.endOfDay)
        case .readAgenda: request(.readAgenda)
        case .settingsTriggers: request(.settingsTriggers)
        case .tab(let tab): request(.showTab(AppTab(deepLink: tab)))
        case .editItem(let id): request(.editItem(id))
        case .screen(let screen): request(.openScreen(screen))
        }
    }

    func openRoute(_ route: Route, in tab: AppTab) {
        sheet = nil
        selectedTab = tab
        switch tab {
        case .today: todayPath = [route]
        case .lists: listsPath = [route]
        case .projects: projectsPath = [route]
        case .settings: settingsPath = [route]
        }
    }

    func openItem(_ id: UUID) {
        openRoute(.item(id), in: .today)
    }

    func showToday() {
        sheet = nil
        selectedTab = .today
        todayPath = []
    }

    /// `asist://sekme/<kod>`: closes the sheet and shows the root of `tab`.
    func showTab(_ tab: AppTab) {
        sheet = nil
        selectedTab = tab
        switch tab {
        case .today: todayPath = []
        case .lists: listsPath = []
        case .projects: projectsPath = []
        case .settings: settingsPath = []
        }
    }

    /// Pushes `route` on the selected tab's stack (menus/toolbars where a NavigationLink cannot be used).
    func push(_ route: Route) {
        switch selectedTab {
        case .today: todayPath.append(route)
        case .lists: listsPath.append(route)
        case .projects: projectsPath.append(route)
        case .settings: settingsPath.append(route)
        }
    }

    /// `asist://ekran/<kod>` (07 R4-D9).
    func openScreen(_ screen: DeepLinkScreen) {
        switch screen {
        case .weeklyReport: openRoute(.weeklyReport, in: .today)
        case .people: openRoute(.people, in: .lists)
        case .places: openRoute(.places, in: .settings)
        case .updates: openRoute(.updates, in: .settings)
        case .calendar: openRoute(.calendarSettings, in: .settings)
        }
    }

    func present(_ newSheet: SheetRoute) {
        sheet = newSheet
    }

    func dismissSheet() {
        sheet = nil
    }
}
