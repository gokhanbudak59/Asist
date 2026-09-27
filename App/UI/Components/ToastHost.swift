// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI

struct ToastHost: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        if let toast = toasts.current {
            HStack(spacing: Metrics.cardSpacing) {
                Text(toast.text)
                    .font(.subheadline)
                if toast.hasUndo {
                    Button("Geri Al") {
                        toasts.performUndo()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, Metrics.padding)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 96)
        }
    }
}
