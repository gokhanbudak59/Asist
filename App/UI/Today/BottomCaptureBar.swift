// WP9 (04 §5.2; 03 §4.1, §4.3, §5.9): fixed thumb zone on Bugün — Yaz (56) · Mic (88) · Oku/Durdur (56),
// plus the low-volume hint for the volume ×2 trigger (03 listen.vol.hint_zero).
import SwiftUI
import AsistCore

struct BottomCaptureBar: View {
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(AppRouter.self) private var router
    @Environment(DataStore.self) private var store

    var body: some View {
        let speaking = voice.phase == .speaking
        let listening = voice.phase == .listening || voice.phase == .preparing
        VStack(spacing: 6) {
            if voice.volumeTooLow && store.settings.volumeTriggerEnabled {
                Text("Ses en düşükteyken çift basış algılanamaz; sesi biraz aç.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if voice.triggerArmed && store.settings.volumeTriggerEnabled {
                Label("Ses kısma tuşuna 2 kez bas → dinlerim", systemImage: "speaker.wave.1")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Ses kısma tuşuna iki kez basarak dinlemeyi başlatabilirsin")
            }
            HStack(alignment: .center, spacing: Metrics.padding) {
                Button {
                    router.present(.compose(ListenRequest()))
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: Symbol.keyboard)
                        Text("Yaz")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .accessibilityLabel("Yaz")
                .accessibilityHint("Klavyeyle kayıt ekler")

                MicButton(size: Metrics.micLarge, isActive: listening) {
                    startListening()
                }

                Button {
                    readOrStop(speaking: speaking)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: speaking ? Symbol.stop : Symbol.speak)
                        Text(speaking ? "Durdur" : "Oku")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .accessibilityLabel(speaking ? "Durdur" : "Oku")
                .accessibilityHint(speaking ? "Sesli okumayı durdurur" : "Bugünün işlerini sesli okur")
            }
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    @MainActor
    private func startListening() {
        guard !voice.isOverlayVisible else { return }
        let voice = self.voice
        Task { @MainActor in
            await voice.startListening()
        }
    }

    @MainActor
    private func readOrStop(speaking: Bool) {
        if speaking {
            voice.stopSpeaking()
            return
        }
        Haptics.light()
        Task { @MainActor in
            await AppEnvironment.shared.commands.readTodayAgenda()
        }
    }
}
