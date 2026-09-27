// WP0 STUB (04 §5.2) — replaced by WP10.
import SwiftUI

struct DateTimePickerSheet: View {
    let request: DatePickerRequest
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: Metrics.cardSpacing) {
            Text(request.purpose == .snooze ? "Ertele" : "Zaman")
                .font(.title2.weight(.semibold))
            Button("Kapat") {
                router.dismissSheet()
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(Metrics.padding)
    }
}
