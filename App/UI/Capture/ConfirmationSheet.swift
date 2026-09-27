// WP0 STUB (04 §5.2) — replaced by WP9 (03 §4.5).
import SwiftUI
import AsistCore

struct ConfirmationSheet: View {
    let draft: CaptureDraft
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            Text(draft.heardText)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(draft.item.title)
                .font(.title2.weight(.semibold))
            Spacer(minLength: 0)
            HStack(spacing: Metrics.padding) {
                Button("Vazgeç") {
                    AppEnvironment.shared.capture.discard(draft)
                    router.dismissSheet()
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                Button("Kaydet") {
                    AppEnvironment.shared.capture.commit(draft)
                    router.dismissSheet()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Metrics.padding)
        .presentationDetents([.medium, .large])
    }
}
