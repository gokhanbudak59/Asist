// WP0 STUB (04 §5.2) — replaced by WP9. Yaz / Mic / Oku.
import SwiftUI

struct BottomCaptureBar: View {
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: Metrics.padding) {
            Button {
                router.present(.compose(ListenRequest()))
            } label: {
                Label("Yaz", systemImage: Symbol.keyboard)
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))

            MicButton(size: Metrics.micLarge, isActive: voice.phase == .listening) {
                let voice = self.voice
                Task { @MainActor in
                    await voice.startListening()
                }
            }

            Button {
                Task { @MainActor in
                    await AppEnvironment.shared.commands.readTodayAgenda()
                }
            } label: {
                Label("Oku", systemImage: Symbol.speak)
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
