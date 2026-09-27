// WP0 STUB (04 §5.2) — replaced by WP9 (03 §5.3).
import SwiftUI

struct ListeningOverlay: View {
    @Environment(VoiceCoordinator.self) private var voice

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Text(voice.phase == .processing ? "Anlıyorum…" : "Dinliyorum…")
                    .font(.headline)
                Text(voice.partialText)
                    .font(.title2)
                    .lineLimit(5)
                    .multilineTextAlignment(.center)
                HStack(spacing: Metrics.padding) {
                    Button("Vazgeç") {
                        voice.cancelListening()
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Color.white, filled: false))
                    Button("Bitti") {
                        voice.finishListening()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .foregroundStyle(Color.white)
            .padding(Metrics.padding)
        }
    }
}
