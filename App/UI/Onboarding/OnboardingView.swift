// WP0 STUB (04 §5.2) — replaced by WP11 (3 pages). "Başla" and "Atla" finish onboarding.
import SwiftUI
import AsistCore

struct OnboardingView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Atla") {
                    finish()
                }
            }
            Spacer()
            Text("Asist")
                .font(.largeTitle.weight(.bold))
            Text("Söylediğin hiçbir şey unutulmasın.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Başla") {
                finish()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Metrics.padding)
    }

    @MainActor
    private func finish() {
        store.updateSettings { settings in
            settings.onboardingCompleted = true
        }
        router.showOnboarding = false
    }
}
