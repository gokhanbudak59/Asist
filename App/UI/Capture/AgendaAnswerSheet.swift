// WP0 STUB (04 §5.2) — replaced by WP9 (03 §5.9).
import SwiftUI
import AsistCore

struct AgendaAnswerSheet: View {
    let answer: SpokenAnswer
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            Text(answer.title)
                .font(.title2.weight(.semibold))
            Text(answer.text)
                .font(.body)
            Spacer(minLength: 0)
            Button("Kapat") {
                router.dismissSheet()
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(Metrics.padding)
        .presentationDetents([.medium, .large])
    }
}
