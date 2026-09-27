// WP0 STUB (04 §5.2) — replaced by WP9 (03 §5.10).
import SwiftUI

struct MatchConfirmationSheet: View {
    let proposal: MatchProposal
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: Metrics.cardSpacing) {
            Text(proposal.candidates.count > 1 ? "Hangisi?" : "Bu kayıt mı?")
                .font(.title2.weight(.semibold))
            Button("Kapat") {
                router.dismissSheet()
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(Metrics.padding)
        .presentationDetents([.medium])
    }
}
