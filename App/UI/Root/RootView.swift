// WP9 (04 §5.1; 05a #17/#18/#26; 01b §1.3): hosts the tab shell, the listening overlay, the toast, the single
// app-wide sheet, onboarding, URL handling, the hidden system-volume anchor (volume ×2 trigger, D16) and the
// scene-phase / pending-action lifecycle.
import SwiftUI
import AsistCore

struct RootView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = router
        MainTabView()
            .overlay {
                if voice.isOverlayVisible {
                    ListeningOverlay()
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: voice.isOverlayVisible)
            .overlay(alignment: .bottom) {
                ToastHost()
            }
            .background {
                // 05a #17: 1 pt MPVolumeView keeps the system volume HUD away and lets the trigger read the slider.
                if store.settings.volumeTriggerEnabled {
                    SystemVolumeAnchor(trigger: voice.trigger)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
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
                #if DEBUG
                RootView.consumeDebugLaunchURL(router: router)
                #endif
                consumePending()
            }
        case .background:
            AppEnvironment.shared.sceneDidEnterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    #if DEBUG
    /// CI simulator smoke test only (Debug builds): `simctl launch … -AsistDebugURL asist://…` opens a deep link
    /// without the system "Open in Asist?" prompt that `simctl openurl` shows. Consumed once per process.
    @MainActor private static var debugURLConsumed = false

    @MainActor
    private static func consumeDebugLaunchURL(router: AppRouter) {
        guard !debugURLConsumed else { return }
        debugURLConsumed = true
        guard let raw = UserDefaults.standard.string(forKey: "AsistDebugURL"),
              let url = URL(string: raw) else { return }
        router.handle(url: url)
    }
    #endif

    /// Executes the queued action (deep link, notification tap, App Intent) once the scene is active.
    @MainActor
    private func consumePending() {
        guard let action = router.takePending() else { return }
        switch action {
        case .listen(let request):
            let voice = self.voice
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)      // 01b §1.3: audio session after activation
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
        case .showTab(let tab):
            router.showTab(tab)
        }
    }
}
