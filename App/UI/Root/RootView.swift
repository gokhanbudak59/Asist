// WP0 STUB (04 §5.1) — replaced by WP9. Hosts the tab shell, overlays, the single sheet, onboarding, URL handling
// and the scene-phase / pending-action lifecycle. (SystemVolumeAnchor background is added by WP9 with WP6.)
import SwiftUI
import AsistCore

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        MainTabView()
            .overlay {
                if voice.isOverlayVisible {
                    ListeningOverlay()
                }
            }
            .overlay(alignment: .bottom) {
                ToastHost()
            }
            .sheet(item: $router.sheet, onDismiss: {
                AppEnvironment.shared.capture.commitActiveDraftIfNeeded()
            }) { route in
                SheetHost(route: route)
            }
            .fullScreenCover(isPresented: $router.showOnboarding) {
                OnboardingView()
            }
            .onOpenURL { url in
                router.handle(url: url)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                handleScenePhase(phase)
            }
            .onChange(of: router.pending) { _, newValue in
                if newValue != nil && scenePhase == .active {
                    consumePending()
                }
            }
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { @MainActor in
                await AppEnvironment.shared.sceneDidBecomeActive()
                consumePending()
            }
        case .background:
            AppEnvironment.shared.sceneDidEnterBackground()
        default:
            break
        }
    }

    @MainActor
    private func consumePending() {
        guard let action = router.takePending() else { return }
        switch action {
        case .listen(let request):
            let voice = self.voice
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                await voice.startListening(request)
            }
        case .compose:
            router.present(.compose(ListenRequest()))
        case .readAgenda:
            Task { @MainActor in
                await AppEnvironment.shared.commands.readTodayAgenda()
            }
        case .openItem(let id):
            router.openItem(id)
        case .completeItem(let id):
            AppEnvironment.shared.capture.completeFromLink(id)
            router.showToday()
        case .endOfDay:
            router.openRoute(.endOfDay, in: .today)
        case .today:
            router.showToday()
        case .followUpMessage(let id):
            router.present(.followUpMessage(id))
        case .settingsTriggers:
            router.openRoute(.triggerSettings, in: .settings)
        case .dataSettings:
            router.openRoute(.dataSettings, in: .settings)
        }
    }
}
