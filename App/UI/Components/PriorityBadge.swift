// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI
import AsistCore

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        switch priority {
        case .high:
            label("ÖNEMLİ", color: Color.orange)
        case .critical:
            label("KRİTİK", color: Color.red)
        case .low, .normal:
            EmptyView()
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                Capsule().stroke(color, lineWidth: 1)
            }
    }
}
