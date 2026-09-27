// WP9 (04 §5.3, signature frozen; 03 §7.1): high "ÖNEMLİ" orange, critical "KRİTİK" red, else nothing.
// Color never carries meaning alone: symbol + uppercase literal text.
import SwiftUI
import AsistCore

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        switch priority {
        case .high:
            label("ÖNEMLİ", symbol: Symbol.important, color: Color.orange, a11y: "Önemli")
        case .critical:
            label("KRİTİK", symbol: Symbol.critical, color: Color.red, a11y: "Kritik")
        case .low, .normal:
            EmptyView()
        }
    }

    private func label(_ text: String, symbol: String, color: Color, a11y: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay {
            Capsule().stroke(color, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}
